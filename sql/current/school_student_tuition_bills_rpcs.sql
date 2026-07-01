-- school_student_tuition_bills_rpcs.sql
-- Purpose:
-- - Generate a student tuition bill from DB/RPC-authoritative planned lessons.
-- - Create one pending school_income_records row from a tuition bill.
-- - Extend Cash income request backend amount calculation so CNY Cash requests
--   for tuition bills add the frozen previous-month CNY carryover before
--   rounding. Frontend may preview, but DB/RPC remains authoritative.

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
declare
  v_student public.school_students%rowtype;
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%rowtype;
  v_existing public.school_student_tuition_bills%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_planned_count integer;
  v_planned_hours numeric;
  v_planned_fee_jpy numeric;
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
           previous_carryover_cny = round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2),
           planned_lesson_count = v_planned_count,
           planned_lesson_hours = v_planned_hours,
           planned_lesson_fee_jpy = v_planned_fee_jpy,
           bill_amount_jpy = v_planned_fee_jpy,
           currency = 'JPY',
           source_snapshot = jsonb_build_object(
             'student_id', p_student_id,
             'business_entity_id', v_student.business_entity_id,
             'billing_month', v_billing_month,
             'previous_settlement_month', v_previous_month,
             'previous_settlement_id', v_previous_settlement.id,
             'previous_carryover_cny', round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2),
             'planned_lesson_count', v_planned_count,
             'planned_lesson_hours', v_planned_hours,
             'planned_lesson_fee_jpy', v_planned_fee_jpy,
             'planned_lesson_ids', to_jsonb(v_lesson_ids)
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
      round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2),
      v_planned_count,
      v_planned_hours,
      v_planned_fee_jpy,
      v_planned_fee_jpy,
      'JPY',
      'draft',
      jsonb_build_object(
        'student_id', p_student_id,
        'business_entity_id', v_student.business_entity_id,
        'billing_month', v_billing_month,
        'previous_settlement_month', v_previous_month,
        'previous_settlement_id', v_previous_settlement.id,
        'previous_carryover_cny', round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2),
        'planned_lesson_count', v_planned_count,
        'planned_lesson_hours', v_planned_hours,
        'planned_lesson_fee_jpy', v_planned_fee_jpy,
        'planned_lesson_ids', to_jsonb(v_lesson_ids)
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
    v_bill.status,
    v_bill.income_record_id,
    v_message;
end;
$$;

comment on function public.school_generate_student_tuition_bill(uuid, text, text) is
  'Generates or recalculates one draft student tuition bill from formal planned lessons. DB/RPC freezes JPY planned-lesson tuition and previous locked settlement CNY carryover. Does not create income, Cash requests, Cash transactions, account rows, settlements, wages, or lessons.';

revoke all on function public.school_generate_student_tuition_bill(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.school_generate_student_tuition_bill(uuid, text, text)
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
      'bill_amount_jpy', v_bill.bill_amount_jpy
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
  'Creates one pending tuition school_income_records row from a draft student tuition bill. The original School income amount is the bill JPY planned-lesson amount; previous CNY carryover is applied later by the Cash request RPC when requesting CNY receipt.';

revoke all on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  from public, anon, authenticated;

grant execute on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  to authenticated, service_role;

drop function if exists public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
);

create or replace function public.school_request_cash_income_confirmation_for_record(
  p_income_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_exchange_rate numeric default null,
  p_note text default null,
  p_payment_rounding_mode text default null
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
  v_bill public.school_student_tuition_bills%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_request_type text;
  v_idempotency_key text;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_rounding_mode text := lower(trim(coalesce(p_payment_rounding_mode, '')));
  v_payment_amount numeric := p_payment_amount;
  v_payment_exchange_rate numeric;
  v_computed_amount numeric;
  v_carryover_cny numeric := 0;
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

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '实际到账币种必须是 JPY 或 CNY。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
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

  if v_income.source_type = 'student_tuition_bill' then
    select *
      into v_bill
      from public.school_student_tuition_bills b
     where b.id = v_income.source_id
       and b.income_record_id = v_income.id
       and b.status = 'income_created'
       and b.app_type = 'school'
     for update;

    if not found then
      raise exception '学生学费应收单与收入记录不匹配，不能提交 Cash。';
    end if;

    v_carryover_cny := round(coalesce(v_bill.previous_carryover_cny, 0), 2);
  end if;

  if v_carryover_cny <> 0 and v_payment_currency <> 'CNY' then
    raise exception '该学费应收包含 CNY 结转金额，Cash 实际到账币种必须为 CNY。';
  end if;

  if v_income.currency = v_payment_currency then
    if p_exchange_rate is not null and p_exchange_rate <> 1 then
      raise exception '同币种实际到账汇率应为空或 1。';
    end if;

    v_payment_exchange_rate := coalesce(p_exchange_rate, 1);

    if v_payment_amount is null then
      v_payment_amount := v_income.amount;
    end if;
  else
    if v_payment_amount is null and (p_exchange_rate is null or p_exchange_rate <= 0) then
      raise exception '后端计算跨币种实际到账金额时必须填写本次汇率。';
    end if;

    if p_exchange_rate is not null then
      v_payment_exchange_rate := p_exchange_rate;
    elsif v_payment_amount is not null and v_payment_amount > 0 and v_income.amount > 0 then
      v_payment_exchange_rate := case
        when v_income.currency = 'JPY' and v_payment_currency = 'CNY' then round(((v_payment_amount - v_carryover_cny) / v_income.amount) * 10000000) / 10000000
        when v_income.currency = 'CNY' and v_payment_currency = 'JPY' then round((v_income.amount / v_payment_amount) * 10000000) / 10000000
        else null
      end;
    end if;

    if v_payment_exchange_rate is null or v_payment_exchange_rate <= 0 then
      raise exception '跨币种实际到账汇率计算失败。';
    end if;
  end if;

  if v_income.currency <> v_payment_currency and v_payment_amount is null then
    if v_rounding_mode not in ('round', 'ceil', 'floor') then
      raise exception '后端计算实际到账金额时必须指定取整方式。';
    end if;

    v_computed_amount := case
      when v_income.currency = 'JPY' and v_payment_currency = 'CNY' then v_income.amount * v_payment_exchange_rate + v_carryover_cny
      when v_income.currency = 'CNY' and v_payment_currency = 'JPY' then v_income.amount / v_payment_exchange_rate
      else null
    end;

    if v_computed_amount is null or v_computed_amount <= 0 then
      raise exception '实际到账金额计算失败。';
    end if;

    if v_rounding_mode = 'ceil' then
      v_payment_amount := ceil(v_computed_amount);
    elsif v_rounding_mode = 'floor' then
      v_payment_amount := floor(v_computed_amount);
    else
      v_payment_amount := round(v_computed_amount);
    end if;
  end if;

  if v_payment_amount is null or v_payment_amount <= 0 then
    raise exception '实际到账金额必须大于 0。';
  end if;

  if v_carryover_cny > 0 and v_payment_currency = 'CNY' and v_payment_amount <= v_carryover_cny then
    raise exception '实际到账金额必须大于 CNY 结转金额。';
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
       or v_existing.payment_exchange_rate is distinct from v_payment_exchange_rate
       or v_existing.payment_amount is distinct from v_payment_amount then
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
      v_payment_exchange_rate,
      v_payment_amount,
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

revoke all on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) to authenticated;

comment on function public.school_request_cash_income_confirmation_for_record(
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  text,
  text
) is
  'Creates/reuses a Cash income linkage event for an existing pending school_income_records row. DB/RPC computes payment amount from exchange rate/rounding; student_tuition_bill CNY requests add frozen previous-month CNY carryover.';

-- v10.3.52 overlay:
-- Student tuition bills now require a DB/RPC-authoritative CNY notification
-- amount calculated from an operator-entered CNY/JPY notification rate.
-- Keep this relative include at the end so executing the historical full RPC
-- file cannot accidentally revert the current tuition-bill signatures.
\ir school_student_tuition_bill_notice_amount.sql
