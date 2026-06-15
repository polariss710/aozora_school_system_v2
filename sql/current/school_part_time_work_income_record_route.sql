-- school_part_time_work_income_record_route.sql
-- Status: executed on School DB 2026-06-15 for v2.121.0 part-time work income canonical routing.
-- Purpose:
-- - Route external part-time work income through school_income_records.
-- - Keep locked JPY settlement totals as the School-side original amount.
-- - Let Cash confirmation use actual received amount/currency via income linkage events.
-- Safety:
-- - No destructive operations.
-- - No real data is modified except through guarded RPC calls.
-- - Write RPCs are granted to authenticated only.

begin;

alter table public.school_income_records
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists source_label text,
  add column if not exists source_snapshot jsonb;

alter table public.school_part_time_work_monthly_settlements
  add column if not exists income_record_id uuid references public.school_income_records(id);

create index if not exists school_income_records_source_idx
  on public.school_income_records (source_type, source_id)
  where source_type is not null and source_id is not null;

create index if not exists school_part_time_work_settlements_income_record_idx
  on public.school_part_time_work_monthly_settlements (income_record_id)
  where income_record_id is not null;

drop function if exists public.school_create_part_time_work_income_record(uuid);
drop function if exists public.school_request_cash_income_confirmation_for_record(uuid, uuid, uuid, text, text, numeric, text, numeric, text);
drop function if exists public.school_lock_part_time_work_monthly_settlement(text, text, integer, text);
drop function if exists public.school_unlock_part_time_work_monthly_settlement(uuid);
drop function if exists public.school_list_part_time_work_monthly_settlements(text);

create or replace function public.school_create_part_time_work_income_record(p_settlement_id uuid)
returns table (
  settlement_id uuid,
  income_record_id uuid,
  year_month text,
  workplace_name text,
  income_status text,
  amount_jpy numeric,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_income public.school_income_records%rowtype;
  v_business_entity_id uuid;
  v_business_entity_count integer;
  v_income_date date;
  v_note text;
  v_snapshot jsonb;
  v_now timestamptz := now();
begin
  if p_settlement_id is null then
    raise exception 'settlement id is required';
  end if;

  select *
    into v_settlement
    from public.school_part_time_work_monthly_settlements s
   where s.id = p_settlement_id
     and s.deleted_at is null
   for update;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;

  if v_settlement.status not in ('locked', 'income_request_created') then
    raise exception '请先锁定月度工资结算，再生成收入记录。';
  end if;

  if coalesce(v_settlement.total_wage_jpy, 0) <= 0 then
    raise exception '工资总额必须大于 0，才能生成收入记录。';
  end if;

  if v_settlement.income_record_id is not null then
    select *
      into v_income
      from public.school_income_records i
     where i.id = v_settlement.income_record_id
       and coalesce(i.app_type, '') = 'school';

    if found then
      return query
      select
        v_settlement.id,
        v_income.id,
        v_settlement.year_month,
        v_settlement.workplace_name,
        v_income.status,
        v_income.amount_jpy,
        'Part-time work income record already exists'::text;
      return;
    end if;
  end if;

  select *
    into v_income
    from public.school_income_records i
   where i.source_type = 'part_time_work'
     and i.source_id = v_settlement.id
     and coalesce(i.app_type, '') = 'school'
     and coalesce(i.status, '') <> 'reversed'
   order by i.created_at desc
   limit 1
   for update;

  if found then
    update public.school_part_time_work_monthly_settlements s
       set income_record_id = v_income.id,
           status = 'income_request_created',
           updated_at = v_now
     where s.id = v_settlement.id;

    return query
    select
      v_settlement.id,
      v_income.id,
      v_settlement.year_month,
      v_settlement.workplace_name,
      v_income.status,
      v_income.amount_jpy,
      'Existing part-time work income record linked to settlement'::text;
    return;
  end if;

  select count(*)::integer
    into v_business_entity_count
    from public.school_business_entities
   where is_active = true
     and entity_type = 'personal';

  if v_business_entity_count <> 1 then
    raise exception '外部塾打工收入需要且只能有一个 active personal 业务归属。当前数量: %', v_business_entity_count;
  end if;

  select id
    into v_business_entity_id
    from public.school_business_entities
   where is_active = true
     and entity_type = 'personal'
   order by name
   limit 1;

  if v_business_entity_id is null then
    raise exception '外部塾打工收入 personal 业务归属不存在。';
  end if;

  v_income_date := (
    date_trunc('month', (v_settlement.year_month || '-01')::date)
    + interval '1 month - 1 day'
  )::date;

  v_note := concat(
    v_settlement.workplace_name,
    ' ',
    v_settlement.year_month,
    ' 外部塾打工收入，School锁定工资总额 ',
    v_settlement.total_wage_jpy::text,
    ' JPY。'
  );

  v_snapshot := jsonb_build_object(
    'settlement_id', v_settlement.id,
    'year_month', v_settlement.year_month,
    'workplace_name', v_settlement.workplace_name,
    'teacher_name', v_settlement.teacher_name,
    'actual_lesson_count', v_settlement.actual_lesson_count,
    'actual_hours_total', v_settlement.actual_hours_total,
    'lesson_wage_jpy', v_settlement.lesson_wage_jpy,
    'transportation_fee_jpy', v_settlement.transportation_fee_jpy,
    'adjustment_jpy', v_settlement.adjustment_jpy,
    'total_wage_jpy', v_settlement.total_wage_jpy
  );

  insert into public.school_income_records (
    business_entity_id,
    student_id,
    student_payment_id,
    account_id,
    income_date,
    year_month,
    settlement_month,
    income_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_currency,
    payment_method,
    status,
    is_taxable_income,
    tax_category,
    receipt_status,
    include_in_student_settlement,
    note,
    source_type,
    source_id,
    source_label,
    source_snapshot,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_business_entity_id,
    null,
    null,
    null,
    v_income_date,
    v_settlement.year_month,
    v_settlement.year_month,
    'part_time_work',
    '外部塾打工收入',
    'JPY',
    v_settlement.total_wage_jpy,
    v_settlement.total_wage_jpy,
    null,
    null,
    'JPY',
    null,
    'pending',
    true,
    '売上',
    '待提交 Cash',
    false,
    v_note,
    'part_time_work',
    v_settlement.id,
    concat(v_settlement.workplace_name, ' ', v_settlement.year_month, ' 外部塾打工收入'),
    v_snapshot,
    'school',
    v_now,
    v_now
  )
  returning * into v_income;

  update public.school_part_time_work_monthly_settlements s
     set income_record_id = v_income.id,
         status = 'income_request_created',
         updated_at = v_now
   where s.id = v_settlement.id;

  return query
  select
    v_settlement.id,
    v_income.id,
    v_settlement.year_month,
    v_settlement.workplace_name,
    v_income.status,
    v_income.amount_jpy,
    'Part-time work income record created'::text;
end;
$$;

create or replace function public.school_request_cash_income_confirmation_for_record(
  p_income_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_exchange_rate numeric default null,
  p_note text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  amount numeric,
  currency text,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_income public.school_income_records%rowtype;
  v_existing public.school_personal_cash_income_linkage_events%rowtype;
  v_latest public.school_personal_cash_income_linkage_events%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_request_type text;
  v_idempotency_key text;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
begin
  if p_income_record_id is null then
    raise exception 'income record id is required';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception '请选择 Cash System 账户。';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  if p_payment_amount is null or p_payment_amount <= 0 then
    raise exception '实际到账金额必须大于 0。';
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '实际到账币种必须是 JPY 或 CNY。';
  end if;

  if v_payment_currency = 'CNY' and (p_exchange_rate is null or p_exchange_rate <= 0) then
    raise exception 'CNY 实际到账必须填写本次汇率。';
  end if;

  if v_payment_currency = 'JPY' and p_exchange_rate is not null and p_exchange_rate <> 1 then
    raise exception 'JPY 实际到账汇率应为空或 1。';
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = p_income_record_id
     and coalesce(app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'income record not found: %', p_income_record_id;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'Cash income request requires pending School income. current status: %', v_income.status;
  end if;

  if v_income.account_id is not null then
    raise exception 'Cash income must not have a School account id.';
  end if;

  if v_income.currency not in ('JPY', 'CNY') then
    raise exception 'School income original currency must be JPY or CNY.';
  end if;

  v_request_type := case
    when v_income.income_category = 'tuition' then 'tuition_income_received'
    else 'income_received'
  end;

  v_cash_transaction_table := case
    when v_payment_currency = 'JPY' then 'home_jpy_transactions'
    else 'home_cny_transactions'
  end;

  select *
    into v_existing
    from public.school_personal_cash_income_linkage_events e
   where e.source_table = 'school_income_records'
     and e.source_id = p_income_record_id
     and e.source_event_type = v_request_type
     and e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
   for update;

  if found then
    if v_existing.cash_user_id is distinct from p_cash_user_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.cash_account_name_snapshot is distinct from v_cash_account_name
       or v_existing.cash_account_type_snapshot is distinct from v_cash_account_type
       or v_existing.currency is distinct from v_income.currency
       or v_existing.amount is distinct from v_income.amount
       or v_existing.payment_currency is distinct from v_payment_currency
       or v_existing.payment_amount is distinct from p_payment_amount then
      raise exception 'existing Cash income linkage event conflicts with requested snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash income linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    v_event_id := v_existing.id;
  else
    select *
      into v_latest
      from public.school_personal_cash_income_linkage_events e
     where e.source_table = 'school_income_records'
       and e.source_id = p_income_record_id
       and e.source_event_type = v_request_type
     order by e.attempt_no desc, e.created_at desc, e.id desc
     limit 1
     for update;

    if found and v_latest.sync_status <> 'cash_rejected' then
      raise exception 'latest Cash income linkage event is not rejected or requestable: %', v_latest.sync_status;
    end if;

    v_attempt_no := coalesce(v_latest.attempt_no, 0) + 1;
    v_idempotency_key := concat(
      'aozora_school:school_income_records:',
      p_income_record_id::text,
      ':',
      v_request_type,
      ':attempt:',
      v_attempt_no::text
    );

    insert into public.school_personal_cash_income_linkage_events (
      source_table,
      source_id,
      source_event_type,
      income_record_id,
      business_entity_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      cash_transaction_table,
      currency,
      amount,
      payment_currency,
      payment_exchange_rate,
      payment_amount,
      idempotency_key,
      sync_status,
      attempt_no,
      retry_count,
      note,
      created_at,
      updated_at
    )
    values (
      'school_income_records',
      p_income_record_id,
      v_request_type,
      p_income_record_id,
      v_income.business_entity_id,
      p_cash_user_id,
      p_cash_account_id,
      v_cash_account_name,
      v_cash_account_type,
      v_cash_transaction_table,
      v_income.currency,
      v_income.amount,
      v_payment_currency,
      case when v_payment_currency = 'JPY' then coalesce(p_exchange_rate, 1) else p_exchange_rate end,
      p_payment_amount,
      v_idempotency_key,
      'pending_cash_request',
      v_attempt_no,
      coalesce(v_latest.retry_count, 0) + case when found then 1 else 0 end,
      v_note,
      v_now,
      v_now
    )
    returning id into v_event_id;
  end if;

  update public.school_income_records
     set receipt_status = 'Cash待确认',
         updated_at = v_now
   where id = p_income_record_id;

  return query
  select
    i.id,
    e.id,
    e.sync_status,
    e.attempt_no,
    e.idempotency_key,
    e.source_event_type,
    e.amount,
    e.currency,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_account_type_snapshot,
    e.cash_request_id,
    e.cash_request_status,
    case
      when e.sync_status = 'awaiting_cash_confirmation' then 'Cash income confirmation request already submitted'
      else 'School Cash income confirmation request event is ready to submit'
    end::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = v_event_id
  where i.id = p_income_record_id;
end;
$$;

create or replace function public.school_list_part_time_work_monthly_settlements(
  p_year_month text
)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  income_record_id uuid,
  income_record_status text,
  income_record_cash_status text,
  memo text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with target_workplaces(workplace_name) as (
    values ('诺应教育'), ('致远教育'), ('新领域')
  ),
  actual_totals as (
    select
      l.workplace_name,
      count(*)::integer as actual_lesson_count,
      coalesce(sum(l.actual_hours), 0)::numeric as actual_hours_total,
      coalesce(sum(l.lesson_wage_jpy), 0)::integer as default_lesson_wage_jpy,
      coalesce(sum(l.transportation_fee_jpy), 0)::integer as transportation_fee_jpy
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
      and l.record_kind = 'actual'
      and l.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    group by l.workplace_name
  ),
  latest_income_linkage as (
    select distinct on (e.income_record_id)
      e.income_record_id,
      e.sync_status
    from public.school_personal_cash_income_linkage_events e
    where e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
    order by e.income_record_id, e.created_at desc, e.id desc
  )
  select
    s.id,
    public.school_part_time_work_validate_year_month(p_year_month) as year_month,
    w.workplace_name,
    coalesce(s.teacher_name, '吴峰') as teacher_name,
    case when s.status in ('locked', 'income_request_created') then s.actual_lesson_count else coalesce(a.actual_lesson_count, 0) end as actual_lesson_count,
    case when s.status in ('locked', 'income_request_created') then s.actual_hours_total else coalesce(a.actual_hours_total, 0) end as actual_hours_total,
    coalesce(s.hourly_rate_jpy, 0) as hourly_rate_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.lesson_wage_jpy
      else coalesce(a.default_lesson_wage_jpy, 0)
    end as lesson_wage_jpy,
    case when s.status in ('locked', 'income_request_created') then s.transportation_fee_jpy else coalesce(a.transportation_fee_jpy, 0) end as transportation_fee_jpy,
    coalesce(s.adjustment_jpy, 0) as adjustment_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.total_wage_jpy
      else (
        coalesce(a.default_lesson_wage_jpy, 0)
        + coalesce(a.transportation_fee_jpy, 0)
        + coalesce(s.adjustment_jpy, 0)
      )
    end as total_wage_jpy,
    coalesce(s.status, 'draft') as status,
    s.locked_at,
    s.income_request_id,
    ir.status as income_request_status,
    s.income_record_id,
    i.status as income_record_status,
    l.sync_status as income_record_cash_status,
    s.memo,
    s.updated_at
  from target_workplaces w
  left join actual_totals a
    on a.workplace_name = w.workplace_name
  left join public.school_part_time_work_monthly_settlements s
    on s.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    and s.workplace_name = w.workplace_name
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  left join public.school_income_records i
    on i.id = s.income_record_id
    and coalesce(i.app_type, '') = 'school'
  left join latest_income_linkage l
    on l.income_record_id = i.id
  order by case w.workplace_name when '诺应教育' then 1 when '致远教育' then 2 else 3 end;
$$;

create or replace function public.school_lock_part_time_work_monthly_settlement(
  p_year_month text,
  p_workplace_name text,
  p_adjustment_jpy integer default 0,
  p_memo text default null
)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  income_record_id uuid,
  income_record_status text,
  income_record_cash_status text,
  memo text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := public.school_part_time_work_validate_year_month(p_year_month);
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_actual_lesson_count integer;
  v_actual_hours_total numeric(10,2);
  v_lesson_wage_jpy integer;
  v_transportation_fee_jpy integer;
  v_adjustment_jpy integer := coalesce(p_adjustment_jpy, 0);
  v_total_wage_jpy integer;
  v_detail_count integer;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.year_month = v_year_month
    and s.workplace_name = v_workplace_name
    and s.deleted_at is null
  for update;

  if found and v_settlement.status <> 'draft' then
    raise exception '只有草稿状态的月度工资结算可以锁定。';
  end if;

  select
    count(*)::integer,
    coalesce(sum(l.actual_hours), 0)::numeric(10,2),
    coalesce(sum(l.lesson_wage_jpy), 0)::integer,
    coalesce(sum(l.transportation_fee_jpy), 0)::integer
  into v_actual_lesson_count, v_actual_hours_total, v_lesson_wage_jpy, v_transportation_fee_jpy
  from public.school_part_time_work_lessons l
  where l.year_month = v_year_month
    and l.workplace_name = v_workplace_name
    and l.record_kind = 'actual'
    and l.deleted_at is null;

  if v_actual_lesson_count <= 0 then
    raise exception '没有实际打工课时，不能锁定工资结算。';
  end if;

  v_total_wage_jpy := v_lesson_wage_jpy + v_transportation_fee_jpy + v_adjustment_jpy;

  if v_total_wage_jpy < 0 then
    raise exception '工资总额不能小于 0。';
  end if;

  if v_settlement.id is not null then
    update public.school_part_time_work_monthly_settlements s
    set
      actual_lesson_count = v_actual_lesson_count,
      actual_hours_total = v_actual_hours_total,
      hourly_rate_jpy = 0,
      lesson_wage_jpy = v_lesson_wage_jpy,
      transportation_fee_jpy = v_transportation_fee_jpy,
      adjustment_jpy = v_adjustment_jpy,
      total_wage_jpy = v_total_wage_jpy,
      memo = nullif(trim(coalesce(p_memo, '')), ''),
      updated_at = now()
    where s.id = v_settlement.id
    returning * into v_settlement;
  else
    insert into public.school_part_time_work_monthly_settlements (
      year_month,
      workplace_name,
      actual_lesson_count,
      actual_hours_total,
      hourly_rate_jpy,
      lesson_wage_jpy,
      transportation_fee_jpy,
      adjustment_jpy,
      total_wage_jpy,
      status,
      memo,
      updated_at
    )
    values (
      v_year_month,
      v_workplace_name,
      v_actual_lesson_count,
      v_actual_hours_total,
      0,
      v_lesson_wage_jpy,
      v_transportation_fee_jpy,
      v_adjustment_jpy,
      v_total_wage_jpy,
      'draft',
      nullif(trim(coalesce(p_memo, '')), ''),
      now()
    )
    returning * into v_settlement;
  end if;

  delete from public.school_part_time_work_monthly_settlement_details
  where school_part_time_work_monthly_settlement_details.settlement_id = v_settlement.id;

  insert into public.school_part_time_work_monthly_settlement_details (
    settlement_id,
    actual_lesson_id,
    work_date,
    start_time,
    end_time,
    workplace_name,
    subject_name,
    class_description,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  select
    v_settlement.id,
    l.id,
    l.work_date,
    l.start_time,
    l.end_time,
    l.workplace_name,
    l.subject_name,
    l.class_description,
    l.actual_hours,
    l.lesson_count,
    l.cumulative_hours,
    l.hourly_rate_jpy,
    l.lesson_wage_jpy,
    l.transportation_fee_jpy,
    l.memo
  from public.school_part_time_work_lessons l
  where l.year_month = v_settlement.year_month
    and l.workplace_name = v_settlement.workplace_name
    and l.record_kind = 'actual'
    and l.deleted_at is null
  order by l.work_date, l.created_at;

  get diagnostics v_detail_count = row_count;

  if v_detail_count <> v_settlement.actual_lesson_count then
    raise exception '锁定明细数量不一致，请刷新后重新锁定结算。';
  end if;

  update public.school_part_time_work_monthly_settlements
  set status = 'locked',
      locked_at = now(),
      updated_at = now()
  where school_part_time_work_monthly_settlements.id = v_settlement.id;

  return query
  select *
  from public.school_list_part_time_work_monthly_settlements(v_settlement.year_month) r
  where r.id = v_settlement.id;
end;
$$;

create or replace function public.school_unlock_part_time_work_monthly_settlement(p_settlement_id uuid)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  income_record_id uuid,
  income_record_status text,
  income_record_cash_status text,
  memo text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.id = p_settlement_id
    and s.deleted_at is null
  for update;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;
  if v_settlement.status <> 'locked' then
    raise exception '只有已锁定且未生成收入记录的结算可以撤销锁定。';
  end if;
  if v_settlement.income_record_id is not null then
    raise exception '已生成收入记录，不能撤销锁定。';
  end if;
  if v_settlement.income_request_id is not null or exists (
    select 1
    from public.school_part_time_work_income_requests ir
    where ir.settlement_id = v_settlement.id
      and ir.deleted_at is null
  ) then
    raise exception '已存在旧收入请求，不能撤销锁定。';
  end if;

  delete from public.school_part_time_work_monthly_settlement_details d
  where d.settlement_id = v_settlement.id;

  update public.school_part_time_work_monthly_settlements
  set status = 'draft',
      locked_at = null,
      updated_at = now()
  where school_part_time_work_monthly_settlements.id = v_settlement.id;

  return query
  select *
  from public.school_list_part_time_work_monthly_settlements(v_settlement.year_month) r
  where r.id = v_settlement.id;
end;
$$;

revoke all on function public.school_create_part_time_work_income_record(uuid) from public, anon, authenticated;
revoke all on function public.school_request_cash_income_confirmation_for_record(uuid, uuid, uuid, text, text, numeric, text, numeric, text) from public, anon, authenticated;
revoke all on function public.school_list_part_time_work_monthly_settlements(text) from public, anon, authenticated;
revoke all on function public.school_lock_part_time_work_monthly_settlement(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.school_unlock_part_time_work_monthly_settlement(uuid) from public, anon, authenticated;

grant execute on function public.school_create_part_time_work_income_record(uuid) to authenticated;
grant execute on function public.school_request_cash_income_confirmation_for_record(uuid, uuid, uuid, text, text, numeric, text, numeric, text) to authenticated;
grant execute on function public.school_list_part_time_work_monthly_settlements(text) to authenticated;
grant execute on function public.school_lock_part_time_work_monthly_settlement(text, text, integer, text) to authenticated;
grant execute on function public.school_unlock_part_time_work_monthly_settlement(uuid) to authenticated;

comment on column public.school_income_records.source_type is
  'Canonical business source for generated income rows, e.g. part_time_work.';
comment on column public.school_income_records.source_id is
  'Canonical business source row id. For part_time_work this references school_part_time_work_monthly_settlements.id.';
comment on function public.school_create_part_time_work_income_record(uuid) is
  'Creates or returns the canonical school_income_records row for a locked external part-time work settlement. Does not create Cash requests.';
comment on function public.school_request_cash_income_confirmation_for_record(uuid, uuid, uuid, text, text, numeric, text, numeric, text) is
  'Creates/reuses a Cash income linkage event for an existing pending school_income_records row, allowing actual received amount/currency to differ from original School amount.';

commit;
