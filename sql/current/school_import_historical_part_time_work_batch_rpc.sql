-- school_import_historical_part_time_work_batch_rpc.sql
-- Version: v10.3.86-historical-part-time-work-import-rpc-20260715
-- Status: v10.3.86 executed on School DB 2026-07-15; full Newfield rollback and 2099 codex-test commit tests passed.
-- Scope:
-- - Install one owner-only, all-or-nothing import RPC for explicitly approved historical batches.
-- - Derive end_time and lesson wage inside School DB from explicit paid hours and hourly rate.
-- - Create planned/actual lessons, locked settlements, received income rows, and linkage evidence.
-- - Protect historical_confirmed income rows from later ordinary writes.
-- - Does not write Cash DB and is not granted to page roles.

begin;

create or replace function public.school_guard_historical_confirmed_income_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.source_table = 'school_income_records'
      and e.income_record_id = old.id
      and e.sync_status = 'historical_confirmed'
  ) then
    raise exception '历史人工确认收入已锁定；普通更新、取消、冲销或删除均不允许。';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'school_income_records'
      and t.tgname = 'school_guard_historical_confirmed_income_write_trigger'
      and not t.tgisinternal
  ) then
    execute $trigger$
      create trigger school_guard_historical_confirmed_income_write_trigger
      before update or delete on public.school_income_records
      for each row
      execute function public.school_guard_historical_confirmed_income_write()
    $trigger$;
  end if;
end $$;

create or replace function public.school_import_historical_part_time_work_batch(
  p_manifest jsonb
)
returns table (
  batch_id uuid,
  source_key text,
  workplace_name text,
  lesson_count integer,
  settlement_count integer,
  total_jpy integer,
  total_cny numeric,
  result_snapshot jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source_key text := nullif(trim(coalesce(p_manifest ->> 'source_key', '')), '');
  v_source_sha256 text := lower(nullif(trim(coalesce(p_manifest ->> 'source_sha256', '')), ''));
  v_source_filename text := nullif(trim(coalesce(p_manifest ->> 'source_filename', '')), '');
  v_import_kind text := lower(nullif(trim(coalesce(p_manifest ->> 'import_kind', '')), ''));
  v_workplace_name text := nullif(trim(coalesce(p_manifest ->> 'workplace_name', '')), '');
  v_teacher_name text := coalesce(nullif(trim(coalesce(p_manifest ->> 'teacher_name', '')), ''), '吴峰');
  v_months jsonb := p_manifest -> 'months';
  v_lessons jsonb := p_manifest -> 'lessons';
  v_batch public.school_historical_part_time_work_import_batches%rowtype;
  v_business_entity_id uuid;
  v_business_entity_count integer;
  v_period_start text;
  v_period_end text;
  v_expected_lesson_count integer;
  v_expected_total_jpy integer;
  v_expected_total_cny numeric;
  v_month_count integer;
  v_lesson jsonb;
  v_month jsonb;
  v_source_row integer;
  v_work_date date;
  v_start_time time;
  v_end_timestamp timestamp;
  v_end_time time;
  v_paid_hours numeric(8,2);
  v_hourly_rate_jpy integer;
  v_expected_lesson_wage_jpy integer;
  v_transportation_fee_jpy integer;
  v_subject_name text;
  v_source_course_name text;
  v_delivery_mode text;
  v_planned_id uuid;
  v_actual_id uuid;
  v_year_month text;
  v_payment_date date;
  v_payment_amount_cny numeric;
  v_linkage_mode text;
  v_adjustment_jpy integer;
  v_adjustment_note text;
  v_month_lesson_count integer;
  v_month_actual_hours numeric(10,2);
  v_month_lesson_wage_jpy integer;
  v_month_transportation_jpy integer;
  v_month_total_jpy integer;
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_income public.school_income_records%rowtype;
  v_linkage_id uuid;
  v_cash_user_id uuid;
  v_cash_account_id uuid;
  v_cash_account_name text;
  v_cash_account_type text;
  v_cash_transaction_table text;
  v_cash_transaction_id uuid;
  v_payment_exchange_rate numeric;
  v_confirmed_at timestamptz;
  v_result_months jsonb := '[]'::jsonb;
  v_result_snapshot jsonb;
  v_now timestamptz := now();
begin
  if p_manifest is null or jsonb_typeof(p_manifest) <> 'object' then
    raise exception '历史导入清单必须是 JSON object。';
  end if;

  if v_source_key is null or v_source_sha256 is null or v_source_filename is null
     or v_import_kind is null or v_workplace_name is null then
    raise exception '历史导入清单缺少来源键、文件哈希、文件名、导入类型或工作单位。';
  end if;

  if v_source_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception '源文件 SHA-256 格式无效。';
  end if;

  if v_workplace_name not in ('诺应教育', '致远教育', '新领域') then
    raise exception '工作单位不在允许范围内。';
  end if;

  if jsonb_typeof(v_months) <> 'array' or jsonb_array_length(v_months) = 0
     or jsonb_typeof(v_lessons) <> 'array' or jsonb_array_length(v_lessons) = 0 then
    raise exception '历史导入清单必须包含非空月份和课时数组。';
  end if;

  select
    min(m ->> 'year_month'),
    max(m ->> 'year_month'),
    count(*)::integer,
    coalesce(sum((m ->> 'expected_lesson_count')::integer), 0)::integer,
    coalesce(sum((m ->> 'expected_total_jpy')::integer), 0)::integer,
    coalesce(sum((m ->> 'payment_amount_cny')::numeric), 0)::numeric
  into
    v_period_start,
    v_period_end,
    v_month_count,
    v_expected_lesson_count,
    v_expected_total_jpy,
    v_expected_total_cny
  from jsonb_array_elements(v_months) m;

  if v_import_kind = 'historical' then
    if v_period_start <> '2025-12'
       or v_period_end <> '2026-04'
       or v_month_count <> 5
       or not (
         (
           v_source_key = 'historical-part-time-work:诺应教育:2025-12:2026-04'
           and v_source_sha256 = '9b237d8fe76478e1a664b82c2f62ac1980f8b9aa8819ad516dca84275574fab9'
           and v_source_filename = '诺应教育2025.12-2026.4.xlsx'
           and v_workplace_name = '诺应教育'
         )
         or (
           v_source_key = 'historical-part-time-work:致远教育:2025-12:2026-04'
           and v_source_sha256 = '5b930dad5aa4badf9a9909f87a551d7e3ef88ce0e4590afab8213798adbd0188'
           and v_source_filename = '致远教育2025.12-2026.4.xlsx'
           and v_workplace_name = '致远教育'
         )
         or (
           v_source_key = 'historical-part-time-work:新领域:2025-12:2026-04'
           and v_source_sha256 = '8017c7c437f5d331bffa653ceb8363d76f9a8716befec33a0a30a868e0b35ffc'
           and v_source_filename = '新领域2025.12-2026.4.xlsx'
           and v_workplace_name = '新领域'
         )
       ) then
      raise exception '正式历史导入只允许已批准且证据完全匹配的 2025-12 至 2026-04 批次。';
    end if;
  elsif v_import_kind = 'test' then
    if v_source_key !~ '^codex-test:' or v_period_start !~ '^2099-' or v_period_end !~ '^2099-' then
      raise exception '测试导入必须使用 codex-test 来源键和 2099 年月份。';
    end if;
  else
    raise exception '导入类型必须是 historical 或 test。';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_source_key, 0));

  select *
    into v_batch
    from public.school_historical_part_time_work_import_batches b
   where b.source_key = v_source_key;

  if found then
    if v_batch.source_sha256 is distinct from v_source_sha256
       or v_batch.source_filename is distinct from v_source_filename
       or v_batch.workplace_name is distinct from v_workplace_name
       or v_batch.period_start is distinct from v_period_start
       or v_batch.period_end is distinct from v_period_end then
      raise exception '来源键已存在，但导入证据不一致：%', v_source_key;
    end if;

    return query
    select
      v_batch.id,
      v_batch.source_key,
      v_batch.workplace_name,
      v_batch.expected_lesson_count,
      jsonb_array_length(coalesce(v_batch.result_snapshot -> 'months', '[]'::jsonb)),
      v_batch.expected_total_jpy,
      v_batch.expected_total_cny,
      v_batch.result_snapshot;
    return;
  end if;

  if v_expected_lesson_count <> jsonb_array_length(v_lessons) then
    raise exception '月份摘要课时数与课时数组数量不一致。';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_months) m
    where coalesce(m ->> 'year_month', '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
       or coalesce((m ->> 'expected_lesson_count')::integer, 0) <= 0
       or coalesce((m ->> 'expected_actual_hours')::numeric, 0) <= 0
       or coalesce((m ->> 'expected_lesson_wage_jpy')::integer, 0) <= 0
       or coalesce((m ->> 'expected_transportation_jpy')::integer, 0) < 0
       or coalesce((m ->> 'adjustment_jpy')::integer, 0) < 0
       or coalesce((m ->> 'expected_total_jpy')::integer, 0) <= 0
       or coalesce((m ->> 'payment_amount_cny')::numeric, 0) <= 0
       or coalesce(m ->> 'linkage_mode', '') not in ('historical_confirmed', 'synced')
  ) then
    raise exception '月份摘要包含无效的月份、数量、金额或联动状态。';
  end if;

  if exists (
    select 1
    from (
      select m ->> 'year_month' as year_month, count(*)
      from jsonb_array_elements(v_months) m
      group by m ->> 'year_month'
      having count(*) <> 1
    ) duplicates
  ) then
    raise exception '月份摘要存在重复月份。';
  end if;

  if exists (
    select 1
    from (
      select (l ->> 'source_row')::integer as source_row, count(*)
      from jsonb_array_elements(v_lessons) l
      group by (l ->> 'source_row')::integer
      having count(*) <> 1
    ) duplicates
  ) then
    raise exception '课时清单存在重复来源行号。';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_lessons) l
    where not exists (
      select 1
      from jsonb_array_elements(v_months) m
      where m ->> 'year_month' = to_char((l ->> 'work_date')::date, 'YYYY-MM')
    )
  ) then
    raise exception '课时清单存在未被月份摘要覆盖的日期。';
  end if;

  for v_month in
    select value
    from jsonb_array_elements(v_months)
    order by value ->> 'year_month'
  loop
    v_year_month := v_month ->> 'year_month';
    v_payment_date := (v_month ->> 'payment_date')::date;
    v_payment_amount_cny := (v_month ->> 'payment_amount_cny')::numeric;
    v_linkage_mode := v_month ->> 'linkage_mode';
    v_adjustment_jpy := coalesce((v_month ->> 'adjustment_jpy')::integer, 0);

    if to_char(v_payment_date, 'YYYY-MM') <= v_year_month then
      raise exception '到账日期必须晚于业务月份：%', v_year_month;
    end if;

    select
      count(*)::integer,
      coalesce(sum((l ->> 'paid_hours')::numeric), 0)::numeric(10,2),
      coalesce(sum((l ->> 'expected_lesson_wage_jpy')::integer), 0)::integer,
      coalesce(sum((l ->> 'transportation_fee_jpy')::integer), 0)::integer
    into
      v_month_lesson_count,
      v_month_actual_hours,
      v_month_lesson_wage_jpy,
      v_month_transportation_jpy
    from jsonb_array_elements(v_lessons) l
    where to_char((l ->> 'work_date')::date, 'YYYY-MM') = v_year_month;

    v_month_total_jpy := v_month_lesson_wage_jpy + v_month_transportation_jpy + v_adjustment_jpy;

    if v_month_lesson_count is distinct from (v_month ->> 'expected_lesson_count')::integer
       or v_month_actual_hours is distinct from (v_month ->> 'expected_actual_hours')::numeric
       or v_month_lesson_wage_jpy is distinct from (v_month ->> 'expected_lesson_wage_jpy')::integer
       or v_month_transportation_jpy is distinct from (v_month ->> 'expected_transportation_jpy')::integer
       or v_month_total_jpy is distinct from (v_month ->> 'expected_total_jpy')::integer then
      raise exception '月份摘要与课时明细复算不一致：%', v_year_month;
    end if;

    if v_import_kind = 'historical' and v_year_month <= '2026-03'
       and v_linkage_mode <> 'historical_confirmed' then
      raise exception '2025-12 至 2026-03 必须使用 historical_confirmed。';
    end if;

    if v_import_kind = 'historical' and v_year_month = '2026-04'
       and v_linkage_mode <> 'synced' then
      raise exception '2026-04 必须关联已核验的 Cash 交易。';
    end if;

    if v_linkage_mode = 'historical_confirmed' and (
      v_month ? 'cash_user_id'
      or v_month ? 'cash_account_id'
      or v_month ? 'cash_account_name_snapshot'
      or v_month ? 'cash_transaction_id'
    ) then
      raise exception 'historical_confirmed 不得携带 Cash 身份、账户或交易：%', v_year_month;
    end if;

    if v_linkage_mode = 'synced' and (
      nullif(trim(coalesce(v_month ->> 'cash_user_id', '')), '') is null
      or nullif(trim(coalesce(v_month ->> 'cash_account_id', '')), '') is null
      or nullif(trim(coalesce(v_month ->> 'cash_account_name_snapshot', '')), '') is null
      or nullif(trim(coalesce(v_month ->> 'cash_transaction_table', '')), '') is null
      or nullif(trim(coalesce(v_month ->> 'cash_transaction_id', '')), '') is null
    ) then
      raise exception 'synced 月份必须携带已核验的 Cash 身份、账户和交易：%', v_year_month;
    end if;
  end loop;

  if exists (
    select 1
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
      and l.workplace_name = v_workplace_name
      and l.year_month in (select m ->> 'year_month' from jsonb_array_elements(v_months) m)
  ) or exists (
    select 1
    from public.school_part_time_work_monthly_settlements s
    where s.deleted_at is null
      and s.workplace_name = v_workplace_name
      and s.year_month in (select m ->> 'year_month' from jsonb_array_elements(v_months) m)
  ) then
    raise exception '目标工作单位和月份已有课时或结算，整批导入已拒绝。';
  end if;

  select count(*)::integer
    into v_business_entity_count
    from public.school_business_entities
   where is_active = true
     and entity_type = 'personal';

  if v_business_entity_count <> 1 then
    raise exception '历史外部塾收入需要且只能有一个 active personal 业务归属。当前数量：%', v_business_entity_count;
  end if;

  select id
    into v_business_entity_id
    from public.school_business_entities
   where is_active = true
     and entity_type = 'personal'
   limit 1;

  insert into public.school_historical_part_time_work_import_batches (
    source_key,
    source_sha256,
    source_filename,
    import_kind,
    workplace_name,
    period_start,
    period_end,
    expected_lesson_count,
    expected_total_jpy,
    expected_total_cny,
    result_snapshot,
    imported_by,
    imported_at
  )
  values (
    v_source_key,
    v_source_sha256,
    v_source_filename,
    v_import_kind,
    v_workplace_name,
    v_period_start,
    v_period_end,
    v_expected_lesson_count,
    v_expected_total_jpy,
    v_expected_total_cny,
    '{}'::jsonb,
    current_user,
    v_now
  )
  returning * into v_batch;

  for v_lesson in
    select value
    from jsonb_array_elements(v_lessons)
    order by (value ->> 'work_date')::date, (value ->> 'start_time')::time, (value ->> 'source_row')::integer
  loop
    v_source_row := (v_lesson ->> 'source_row')::integer;
    v_work_date := (v_lesson ->> 'work_date')::date;
    v_start_time := (v_lesson ->> 'start_time')::time;
    v_paid_hours := (v_lesson ->> 'paid_hours')::numeric;
    v_hourly_rate_jpy := (v_lesson ->> 'hourly_rate_jpy')::integer;
    v_expected_lesson_wage_jpy := (v_lesson ->> 'expected_lesson_wage_jpy')::integer;
    v_transportation_fee_jpy := coalesce((v_lesson ->> 'transportation_fee_jpy')::integer, 0);
    v_subject_name := nullif(trim(coalesce(v_lesson ->> 'subject_name', '')), '');
    v_source_course_name := nullif(trim(coalesce(v_lesson ->> 'source_course_name', '')), '');
    v_delivery_mode := nullif(trim(coalesce(v_lesson ->> 'delivery_mode', '')), '');

    if v_source_row <= 0 or v_source_course_name is null
       or v_subject_name not in ('EJU文数班课', 'EJU理数班课', 'EJU文数一对一', 'EJU理数一对一', '大学院一对一')
       or v_paid_hours <= 0
       or (
         v_paid_hours * 4 <> trunc(v_paid_hours * 4)
         and not (
           v_source_key = 'historical-part-time-work:新领域:2025-12:2026-04'
           and v_source_row = 52
           and v_paid_hours = 0.6
         )
       )
       or v_hourly_rate_jpy <= 0 or v_transportation_fee_jpy < 0 then
      raise exception '课时清单第 % 行包含无效字段。', v_source_row;
    end if;

    if round(v_paid_hours * v_hourly_rate_jpy) <> v_expected_lesson_wage_jpy then
      raise exception '课时清单第 % 行工资不等于 DB 复算值。', v_source_row;
    end if;

    v_end_timestamp := v_work_date + v_start_time + (v_paid_hours * interval '1 hour');
    if v_end_timestamp >= (v_work_date + 1)::timestamp then
      raise exception '课时清单第 % 行修正后的结束时间跨日。', v_source_row;
    end if;
    v_end_time := v_end_timestamp::time;

    insert into public.school_part_time_work_lessons (
      record_kind,
      planned_lesson_id,
      work_date,
      start_time,
      end_time,
      year_month,
      workplace_name,
      teacher_name,
      subject_name,
      class_description,
      planned_hours,
      actual_hours,
      lesson_count,
      cumulative_hours,
      hourly_rate_jpy,
      lesson_wage_jpy,
      transportation_fee_jpy,
      memo,
      historical_import_batch_id,
      historical_source_row
    )
    values (
      'planned',
      null,
      v_work_date,
      v_start_time,
      v_end_time,
      to_char(v_work_date, 'YYYY-MM'),
      v_workplace_name,
      v_teacher_name,
      v_subject_name,
      v_source_course_name,
      v_paid_hours,
      0,
      1,
      0,
      v_hourly_rate_jpy,
      0,
      v_transportation_fee_jpy,
      concat('历史导入；来源行 ', v_source_row, case when v_delivery_mode is null then '' else concat('；', v_delivery_mode) end),
      v_batch.id,
      v_source_row
    )
    returning id into v_planned_id;

    insert into public.school_part_time_work_lessons (
      record_kind,
      planned_lesson_id,
      work_date,
      start_time,
      end_time,
      year_month,
      workplace_name,
      teacher_name,
      subject_name,
      class_description,
      planned_hours,
      actual_hours,
      lesson_count,
      cumulative_hours,
      hourly_rate_jpy,
      lesson_wage_jpy,
      transportation_fee_jpy,
      memo,
      historical_import_batch_id,
      historical_source_row
    )
    values (
      'actual',
      v_planned_id,
      v_work_date,
      v_start_time,
      v_end_time,
      to_char(v_work_date, 'YYYY-MM'),
      v_workplace_name,
      v_teacher_name,
      v_subject_name,
      v_source_course_name,
      0,
      v_paid_hours,
      1,
      0,
      v_hourly_rate_jpy,
      round(v_paid_hours * v_hourly_rate_jpy),
      v_transportation_fee_jpy,
      concat('历史导入；来源行 ', v_source_row, case when v_delivery_mode is null then '' else concat('；', v_delivery_mode) end),
      v_batch.id,
      v_source_row
    )
    returning id into v_actual_id;
  end loop;

  for v_month in
    select value
    from jsonb_array_elements(v_months)
    order by value ->> 'year_month'
  loop
    v_year_month := v_month ->> 'year_month';
    v_payment_date := (v_month ->> 'payment_date')::date;
    v_payment_amount_cny := (v_month ->> 'payment_amount_cny')::numeric;
    v_linkage_mode := v_month ->> 'linkage_mode';
    v_adjustment_jpy := coalesce((v_month ->> 'adjustment_jpy')::integer, 0);
    v_adjustment_note := nullif(trim(coalesce(v_month ->> 'adjustment_note', '')), '');
    v_month_total_jpy := (v_month ->> 'expected_total_jpy')::integer;

    perform 1
    from public.school_lock_part_time_work_monthly_settlement(
      v_year_month,
      v_workplace_name,
      v_adjustment_jpy,
      concat('历史导入批次 ', v_batch.id, case when v_adjustment_note is null then '' else concat('；调整项：', v_adjustment_note) end)
    )
    limit 1;

    select *
      into v_settlement
      from public.school_part_time_work_monthly_settlements s
     where s.year_month = v_year_month
       and s.workplace_name = v_workplace_name
       and s.deleted_at is null
     for update;

    if not found or v_settlement.status <> 'locked'
       or v_settlement.actual_lesson_count is distinct from (v_month ->> 'expected_lesson_count')::integer
       or v_settlement.actual_hours_total is distinct from (v_month ->> 'expected_actual_hours')::numeric
       or v_settlement.lesson_wage_jpy is distinct from (v_month ->> 'expected_lesson_wage_jpy')::integer
       or v_settlement.transportation_fee_jpy is distinct from (v_month ->> 'expected_transportation_jpy')::integer
       or v_settlement.adjustment_jpy is distinct from v_adjustment_jpy
       or v_settlement.total_wage_jpy is distinct from v_month_total_jpy then
      raise exception '锁定结算结果与批准摘要不一致：%', v_year_month;
    end if;

    perform 1
    from public.school_create_part_time_work_income_record(v_settlement.id)
    limit 1;

    select *
      into v_income
      from public.school_income_records i
     where i.source_type = 'part_time_work'
       and i.source_id = v_settlement.id
       and i.app_type = 'school'
     order by i.created_at desc, i.id desc
     limit 1
     for update;

    if not found or v_income.business_entity_id is distinct from v_business_entity_id
       or v_income.amount_jpy is distinct from v_month_total_jpy::numeric then
      raise exception '外部塾收入记录生成或金额核验失败：%', v_year_month;
    end if;

    update public.school_income_records i
       set income_date = v_payment_date,
           status = 'received',
           receipt_status = case when v_linkage_mode = 'synced' then 'Cash已确认' else '历史已确认' end,
           note = concat(
             v_workplace_name,
             ' ',
             v_year_month,
             ' 外部塾打工历史收入；原币 ',
             v_month_total_jpy,
             ' JPY；实际到账 ',
             v_payment_amount_cny,
             ' CNY；到账日 ',
             v_payment_date,
             '。'
           ),
           source_snapshot = coalesce(i.source_snapshot, '{}'::jsonb) || jsonb_build_object(
             'historical_import_batch_id', v_batch.id,
             'source_key', v_source_key,
             'source_sha256', v_source_sha256,
             'payment_date', v_payment_date,
             'payment_currency', 'CNY',
             'payment_amount', v_payment_amount_cny,
             'linkage_mode', v_linkage_mode,
             'adjustment_note', v_adjustment_note
           ),
           updated_at = v_now
     where i.id = v_income.id
     returning * into v_income;

    v_confirmed_at := (v_payment_date::timestamp at time zone 'Asia/Tokyo');
    v_payment_exchange_rate := round(v_month_total_jpy::numeric / v_payment_amount_cny, 8);

    if v_linkage_mode = 'synced' then
      v_cash_user_id := (v_month ->> 'cash_user_id')::uuid;
      v_cash_account_id := (v_month ->> 'cash_account_id')::uuid;
      v_cash_account_name := nullif(trim(v_month ->> 'cash_account_name_snapshot'), '');
      v_cash_account_type := nullif(trim(coalesce(v_month ->> 'cash_account_type_snapshot', '')), '');
      v_cash_transaction_table := v_month ->> 'cash_transaction_table';
      v_cash_transaction_id := (v_month ->> 'cash_transaction_id')::uuid;
    else
      v_cash_user_id := null;
      v_cash_account_id := null;
      v_cash_account_name := null;
      v_cash_account_type := null;
      v_cash_transaction_table := null;
      v_cash_transaction_id := null;
    end if;

    insert into public.school_personal_cash_income_linkage_events (
      source_table,
      source_id,
      source_event_type,
      income_record_id,
      business_entity_id,
      cash_account_mapping_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      cash_transaction_table,
      cash_transaction_id,
      currency,
      amount,
      payment_currency,
      payment_exchange_rate,
      payment_amount,
      idempotency_key,
      sync_status,
      attempt_no,
      cash_request_id,
      cash_request_status,
      confirmed_at,
      retry_count,
      note,
      created_at,
      updated_at,
      synced_at
    )
    values (
      'school_income_records',
      v_income.id,
      'income_received',
      v_income.id,
      v_business_entity_id,
      null,
      v_cash_user_id,
      v_cash_account_id,
      v_cash_account_name,
      v_cash_account_type,
      v_cash_transaction_table,
      v_cash_transaction_id,
      'JPY',
      v_month_total_jpy,
      'CNY',
      v_payment_exchange_rate,
      v_payment_amount_cny,
      concat(v_source_key, ':', v_year_month),
      v_linkage_mode,
      1,
      null,
      null,
      v_confirmed_at,
      0,
      case
        when v_linkage_mode = 'synced' then '历史导入；引用执行前只读核验的既存 Cash 交易。'
        else '历史导入；Cash 系统上线前收入，由原始工资结算证据人工确认。'
      end,
      v_now,
      v_now,
      v_confirmed_at
    )
    returning id into v_linkage_id;

    v_result_months := v_result_months || jsonb_build_array(jsonb_build_object(
      'year_month', v_year_month,
      'settlement_id', v_settlement.id,
      'income_record_id', v_income.id,
      'linkage_event_id', v_linkage_id,
      'linkage_status', v_linkage_mode,
      'total_jpy', v_month_total_jpy,
      'payment_cny', v_payment_amount_cny
    ));
  end loop;

  v_result_snapshot := jsonb_build_object(
    'months', v_result_months,
    'planned_lesson_count', v_expected_lesson_count,
    'actual_lesson_count', v_expected_lesson_count,
    'settlement_count', v_month_count,
    'income_record_count', v_month_count,
    'linkage_event_count', v_month_count,
    'total_jpy', v_expected_total_jpy,
    'total_cny', v_expected_total_cny,
    'completed_at', v_now
  );

  update public.school_historical_part_time_work_import_batches b
     set result_snapshot = v_result_snapshot
   where b.id = v_batch.id
   returning * into v_batch;

  return query
  select
    v_batch.id,
    v_batch.source_key,
    v_batch.workplace_name,
    v_batch.expected_lesson_count,
    v_month_count,
    v_batch.expected_total_jpy,
    v_batch.expected_total_cny,
    v_batch.result_snapshot;
end;
$$;

comment on function public.school_import_historical_part_time_work_batch(jsonb) is
  'Owner-only all-or-nothing import for the explicitly approved historical external part-time-work manifest; never writes Cash DB.';

revoke all on function public.school_guard_historical_confirmed_income_write() from public, anon, authenticated;
revoke all on function public.school_import_historical_part_time_work_batch(jsonb) from public, anon, authenticated;

commit;
