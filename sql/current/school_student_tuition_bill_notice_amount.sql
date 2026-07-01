-- school_student_tuition_bill_notice_amount.sql
-- Purpose:
-- - Add DB/RPC-authoritative CNY notification amount for student tuition bills.
-- - The frontend supplies only the notification exchange rate. DB/RPC freezes
--   billing_amount_cny = planned JPY tuition * rate + previous CNY carryover.
-- - Existing bill rows are not backfilled or modified by this file.

begin;

alter table public.school_student_tuition_bills
  add column if not exists billing_exchange_rate numeric,
  add column if not exists billing_amount_cny numeric,
  add column if not exists billing_amount_calculated_at timestamptz;

do $$
begin
  alter table public.school_student_tuition_bills
    add constraint school_student_tuition_bills_billing_rate_check
    check (billing_exchange_rate is null or billing_exchange_rate > 0);
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  alter table public.school_student_tuition_bills
    add constraint school_student_tuition_bills_billing_cny_check
    check (billing_amount_cny is null or billing_amount_cny > 0);
exception
  when duplicate_object then null;
end;
$$;

comment on column public.school_student_tuition_bills.billing_exchange_rate is
  'CNY/JPY notification exchange rate explicitly entered by the operator when generating the tuition bill.';

comment on column public.school_student_tuition_bills.billing_amount_cny is
  'CNY amount notified to the student, calculated by DB/RPC as JPY tuition * notification rate + previous CNY carryover, rounded to 2 decimals.';

comment on column public.school_student_tuition_bills.billing_amount_calculated_at is
  'Timestamp when DB/RPC calculated billing_amount_cny.';

commit;

create or replace function public.school_generate_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_note text default null
)
returns table (
  tuition_bill_id uuid,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  status text,
  income_record_id uuid,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception '通知汇率必填，请刷新页面后重新生成学费应收。';
end;
$$;

comment on function public.school_generate_student_tuition_bill(uuid, text, text) is
  'Compatibility guard only. Tuition bill generation now requires a notification CNY/JPY exchange rate and must call school_generate_student_tuition_bill(uuid, text, numeric, text).';

revoke all on function public.school_generate_student_tuition_bill(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.school_generate_student_tuition_bill(uuid, text, text)
  to authenticated, service_role;

create or replace function public.school_generate_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric,
  p_note text default null
)
returns table (
  tuition_bill_id uuid,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  status text,
  income_record_id uuid,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student public.school_students%rowtype;
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
  v_billing_exchange_rate numeric := p_billing_exchange_rate;
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%rowtype;
  v_existing public.school_student_tuition_bills%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_planned_count integer;
  v_planned_hours numeric;
  v_planned_fee_jpy numeric;
  v_previous_carryover_cny numeric;
  v_billing_amount_cny numeric;
  v_lesson_ids uuid[];
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_message text;
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_billing_month is null or v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '学费月份格式无效，请使用 YYYY-MM。';
  end if;

  if v_billing_exchange_rate is null or v_billing_exchange_rate <= 0 then
    raise exception '通知汇率必须大于 0。';
  end if;

  select *
    into v_student
    from public.school_students s
   where s.id = p_student_id
     and s.app_type = 'school'
   for update;

  if not found then
    raise exception '学生无效或不属于 School。';
  end if;

  if coalesce(v_student.status, '') in ('inactive', 'disabled', 'archived') then
    raise exception '学生已停用，不能生成学费应收。';
  end if;

  if v_student.business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能生成学费应收。';
  end if;

  if exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = v_student.business_entity_id
       and s.year_month = v_billing_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成新的学费应收。';
  end if;

  v_previous_month := to_char(
    (to_date(v_billing_month || '-01', 'YYYY-MM-DD') - interval '1 month')::date,
    'YYYY-MM'
  );

  select *
    into v_previous_settlement
    from public.school_student_monthly_settlements s
   where s.student_id = p_student_id
     and s.business_entity_id = v_student.business_entity_id
     and s.year_month = v_previous_month
     and s.settlement_status = 'locked'
   order by s.locked_at desc nulls last, s.updated_at desc nulls last, s.created_at desc nulls last
   limit 1;

  select
    count(*)::integer,
    coalesce(sum(coalesce(l.duration_hours, 0)), 0)::numeric,
    coalesce(sum(coalesce(l.lesson_fee, coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)), 0)::numeric,
    coalesce(array_agg(l.id order by l.lesson_date, l.start_time, l.id), array[]::uuid[])
  into
    v_planned_count,
    v_planned_hours,
    v_planned_fee_jpy,
    v_lesson_ids
  from public.school_lesson_records l
  where l.app_type = 'school'
    and l.student_id = p_student_id
    and l.business_entity_id = v_student.business_entity_id
    and l.year_month = v_billing_month
    and l.lesson_type = 'planned'
    and l.voided_at is null
    and coalesce(l.status, '') not in ('cancelled', 'voided', 'void');

  if coalesce(v_planned_count, 0) <= 0 then
    raise exception '该学生月份没有可生成学费应收的正式预定课时。';
  end if;

  if coalesce(v_planned_fee_jpy, 0) <= 0 then
    raise exception '该学生月份预定课时费为 0，不能生成学费应收。';
  end if;

  v_previous_carryover_cny := round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2);
  v_billing_amount_cny := round(v_planned_fee_jpy * v_billing_exchange_rate + v_previous_carryover_cny, 2);

  if v_billing_amount_cny <= 0 then
    raise exception '通知金额计算失败。';
  end if;

  select *
    into v_existing
    from public.school_student_tuition_bills b
   where b.student_id = p_student_id
     and b.business_entity_id = v_student.business_entity_id
     and b.billing_month = v_billing_month
     and b.status in ('draft', 'income_created')
   for update;

  if found and v_existing.status = 'income_created' then
    raise exception '该学生月份已生成收入记录，不能重复生成学费应收。';
  end if;

  if found then
    update public.school_student_tuition_bills b
       set previous_settlement_month = v_previous_month,
           previous_settlement_id = v_previous_settlement.id,
           previous_carryover_cny = v_previous_carryover_cny,
           planned_lesson_count = v_planned_count,
           planned_lesson_hours = v_planned_hours,
           planned_lesson_fee_jpy = v_planned_fee_jpy,
           bill_amount_jpy = v_planned_fee_jpy,
           currency = 'JPY',
           billing_exchange_rate = v_billing_exchange_rate,
           billing_amount_cny = v_billing_amount_cny,
           billing_amount_calculated_at = v_now,
           source_snapshot = jsonb_build_object(
             'student_id', p_student_id,
             'business_entity_id', v_student.business_entity_id,
             'billing_month', v_billing_month,
             'previous_settlement_month', v_previous_month,
             'previous_settlement_id', v_previous_settlement.id,
             'previous_carryover_cny', v_previous_carryover_cny,
             'planned_lesson_count', v_planned_count,
             'planned_lesson_hours', v_planned_hours,
             'planned_lesson_fee_jpy', v_planned_fee_jpy,
             'planned_lesson_ids', to_jsonb(v_lesson_ids),
             'bill_amount_jpy', v_planned_fee_jpy,
             'billing_exchange_rate', v_billing_exchange_rate,
             'billing_amount_cny', v_billing_amount_cny,
             'billing_amount_currency', 'CNY',
             'billing_amount_calculated_at', v_now
           ),
           note = v_note,
           updated_by = current_user,
           updated_at = v_now
     where b.id = v_existing.id
     returning * into v_bill;

    v_message := 'existing draft tuition bill recalculated';
  else
    insert into public.school_student_tuition_bills (
      student_id,
      business_entity_id,
      billing_month,
      previous_settlement_month,
      previous_settlement_id,
      previous_carryover_cny,
      planned_lesson_count,
      planned_lesson_hours,
      planned_lesson_fee_jpy,
      bill_amount_jpy,
      currency,
      billing_exchange_rate,
      billing_amount_cny,
      billing_amount_calculated_at,
      status,
      source_snapshot,
      note,
      app_type,
      created_by,
      updated_by,
      created_at,
      updated_at
    )
    values (
      p_student_id,
      v_student.business_entity_id,
      v_billing_month,
      v_previous_month,
      v_previous_settlement.id,
      v_previous_carryover_cny,
      v_planned_count,
      v_planned_hours,
      v_planned_fee_jpy,
      v_planned_fee_jpy,
      'JPY',
      v_billing_exchange_rate,
      v_billing_amount_cny,
      v_now,
      'draft',
      jsonb_build_object(
        'student_id', p_student_id,
        'business_entity_id', v_student.business_entity_id,
        'billing_month', v_billing_month,
        'previous_settlement_month', v_previous_month,
        'previous_settlement_id', v_previous_settlement.id,
        'previous_carryover_cny', v_previous_carryover_cny,
        'planned_lesson_count', v_planned_count,
        'planned_lesson_hours', v_planned_hours,
        'planned_lesson_fee_jpy', v_planned_fee_jpy,
        'planned_lesson_ids', to_jsonb(v_lesson_ids),
        'bill_amount_jpy', v_planned_fee_jpy,
        'billing_exchange_rate', v_billing_exchange_rate,
        'billing_amount_cny', v_billing_amount_cny,
        'billing_amount_currency', 'CNY',
        'billing_amount_calculated_at', v_now
      ),
      v_note,
      'school',
      current_user,
      current_user,
      v_now,
      v_now
    )
    returning * into v_bill;

    v_message := 'tuition bill generated';
  end if;

  return query
  select
    v_bill.id,
    v_bill.student_id,
    v_bill.business_entity_id,
    v_bill.billing_month,
    v_bill.previous_settlement_month,
    v_bill.previous_settlement_id,
    v_bill.previous_carryover_cny,
    v_bill.planned_lesson_count,
    v_bill.planned_lesson_hours,
    v_bill.planned_lesson_fee_jpy,
    v_bill.bill_amount_jpy,
    v_bill.currency,
    v_bill.billing_exchange_rate,
    v_bill.billing_amount_cny,
    'CNY'::text,
    v_bill.status,
    v_bill.income_record_id,
    v_message;
end;
$$;

comment on function public.school_generate_student_tuition_bill(uuid, text, numeric, text) is
  'Generates or recalculates one draft student tuition bill from formal planned lessons. DB/RPC freezes JPY planned-lesson tuition, previous locked settlement CNY carryover, and CNY notification amount from the operator-entered notification exchange rate.';

revoke all on function public.school_generate_student_tuition_bill(uuid, text, numeric, text)
  from public, anon, authenticated;

grant execute on function public.school_generate_student_tuition_bill(uuid, text, numeric, text)
  to authenticated, service_role;

create or replace function public.school_create_student_tuition_bill_income_record(
  p_tuition_bill_id uuid,
  p_income_date date,
  p_note text default null
)
returns table (
  income_id uuid,
  tuition_bill_id uuid,
  income_status text,
  bill_status text,
  amount numeric,
  currency text,
  settlement_month text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_student public.school_students%rowtype;
  v_income_id uuid;
  v_now timestamptz := now();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_description text;
begin
  if p_tuition_bill_id is null then
    raise exception 'tuition bill id is required.';
  end if;

  if p_income_date is null then
    raise exception '请选择收入请求日期。';
  end if;

  select *
    into v_bill
    from public.school_student_tuition_bills b
   where b.id = p_tuition_bill_id
     and b.app_type = 'school'
   for update;

  if not found then
    raise exception '学费应收单不存在。';
  end if;

  if v_bill.status <> 'draft' then
    raise exception '只有草稿状态的学费应收单可以生成收入记录，当前状态：%。', v_bill.status;
  end if;

  if v_bill.income_record_id is not null then
    raise exception '该学费应收单已关联收入记录。';
  end if;

  if coalesce(v_bill.bill_amount_jpy, 0) <= 0 then
    raise exception '学费应收日元金额必须大于 0。';
  end if;

  if coalesce(v_bill.billing_exchange_rate, 0) <= 0 or coalesce(v_bill.billing_amount_cny, 0) <= 0 then
    raise exception '学费应收缺少有效通知汇率或通知金额，请重新生成。';
  end if;

  select *
    into v_student
    from public.school_students s
   where s.id = v_bill.student_id
     and s.app_type = 'school';

  if not found then
    raise exception '学生无效或不属于 School。';
  end if;

  if exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = v_bill.student_id
       and s.business_entity_id = v_bill.business_entity_id
       and s.year_month = v_bill.billing_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成学费收入请求。';
  end if;

  if exists (
    select 1
      from public.school_income_records i
     where i.app_type = 'school'
       and i.source_type = 'student_tuition_bill'
       and i.source_id = v_bill.id
       and coalesce(i.status, '') <> 'cancelled'
  ) then
    raise exception '该学费应收单已存在收入记录。';
  end if;

  v_description := concat(v_bill.billing_month, ' 学费应收');

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
    v_bill.business_entity_id,
    v_bill.student_id,
    null,
    null,
    p_income_date,
    v_bill.billing_month,
    v_bill.billing_month,
    'tuition',
    v_description,
    'JPY',
    v_bill.bill_amount_jpy,
    v_bill.bill_amount_jpy,
    null,
    null,
    'JPY',
    null,
    'pending',
    false,
    null,
    'Cash待提交',
    true,
    v_note,
    'student_tuition_bill',
    v_bill.id,
    concat(v_bill.billing_month, ' ', coalesce(v_student.display_name, v_student.name, '学生'), ' 学费应收'),
    jsonb_build_object(
      'tuition_bill_id', v_bill.id,
      'billing_month', v_bill.billing_month,
      'previous_settlement_month', v_bill.previous_settlement_month,
      'previous_settlement_id', v_bill.previous_settlement_id,
      'previous_carryover_cny', v_bill.previous_carryover_cny,
      'planned_lesson_count', v_bill.planned_lesson_count,
      'planned_lesson_hours', v_bill.planned_lesson_hours,
      'planned_lesson_fee_jpy', v_bill.planned_lesson_fee_jpy,
      'bill_amount_jpy', v_bill.bill_amount_jpy,
      'billing_exchange_rate', v_bill.billing_exchange_rate,
      'billing_amount_cny', v_bill.billing_amount_cny,
      'billing_amount_currency', 'CNY',
      'billing_amount_calculated_at', v_bill.billing_amount_calculated_at
    ),
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  update public.school_student_tuition_bills b
     set status = 'income_created',
         income_record_id = v_income_id,
         income_created_at = v_now,
         updated_by = current_user,
         updated_at = v_now
   where b.id = v_bill.id
   returning * into v_bill;

  return query
  select
    v_income_id,
    v_bill.id,
    'pending'::text,
    v_bill.status,
    v_bill.bill_amount_jpy,
    'JPY'::text,
    v_bill.billing_month,
    'student tuition bill income record created'::text;
end;
$$;

comment on function public.school_create_student_tuition_bill_income_record(uuid, date, text) is
  'Creates one pending tuition school_income_records row from a draft student tuition bill. The original School income amount remains JPY; the DB/RPC-frozen CNY notification amount and rate are copied into source_snapshot for display and Cash-default use.';

revoke all on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  from public, anon, authenticated;

grant execute on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  to authenticated, service_role;
