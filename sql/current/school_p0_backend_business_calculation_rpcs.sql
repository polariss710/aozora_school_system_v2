-- school_p0_backend_business_calculation_rpcs.sql
-- Purpose: Move P0 business calculations for student settlement adjustment and pending Cash income into DB/RPC.
-- Status: EXECUTED ON SUPABASE 2026-06-28 via SCHOOL_SUPABASE_DB_URL.
--
-- Scope:
-- - Replaces public.school_set_student_monthly_settlement_draft_adjustment so
--   non-manual adjustment modes are calculated by DB/RPC:
--   carry_final_balance -> 0, clear_balance -> -final_due_cny from DB summary.
-- - Adds public.school_create_pending_cash_income_record so pending Cash income
--   rows are created by RPC, including amount_jpy/amount_cny calculation.
-- - Does not modify schema, historical data, Cash DB, accounts, account
--   transactions, lessons, teacher wage, payment, expense, or carryover rows.

create or replace function public.school_set_student_monthly_settlement_draft_adjustment(
  p_student_id uuid,
  p_year_month text,
  p_adjustment_amount_cny numeric,
  p_adjustment_source text default 'manual',
  p_adjustment_reason text default null,
  p_note text default null
)
returns table (
  student_id uuid,
  year_month text,
  business_entity_id uuid,
  exchange_rate numeric,
  carryover_cny numeric,
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  planned_fee_cny numeric,
  planned_total_cny numeric,
  actual_fee_jpy numeric,
  actual_fee_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  final_due_cny numeric,
  adjustment_amount_cny numeric,
  adjustment_source text,
  adjustment_reason text,
  adjustment_note text,
  locked_carryover_cny numeric,
  draft_id uuid,
  draft_status text,
  draft_updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_source text := nullif(trim(coalesce(p_adjustment_source, '')), '');
  v_reason text := nullif(trim(coalesce(p_adjustment_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_adjustment_amount_cny numeric;
  v_business_entity_id uuid;
  v_existing_status text;
  v_summary record;
  v_now timestamptz := now();
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_year_month is null or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效，请使用 YYYY-MM。';
  end if;

  if v_source is null then
    raise exception '请填写差额调整来源。';
  end if;

  if v_source not in ('carry_final_balance', 'clear_balance', 'manual_adjustment', 'manual') then
    raise exception '差额调整来源无效：%。', v_source;
  end if;

  if v_reason is null then
    raise exception '请填写差额调整理由。';
  end if;

  select s.business_entity_id
  into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id
    and s.app_type = 'school';

  if not found then
    raise exception '学生不存在或不属于学校业务。';
  end if;

  if v_business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能记录差额调整。';
  end if;

  select m.settlement_status
  into v_existing_status
  from public.school_student_monthly_settlements m
  where m.student_id = p_student_id
    and m.year_month = v_year_month;

  if found and coalesce(v_existing_status, '') <> 'unlocked' then
    raise exception '该学生月份已锁定，差额调整只能只读查看，不能再修改。';
  end if;

  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id,
    v_year_month,
    '保存学生月度结算差额调整'
  );

  if not exists (
    select 1
    from public.school_lesson_records l
    where l.app_type = 'school'
      and l.student_id = p_student_id
      and l.year_month = v_year_month
      and not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1
    from public.school_income_records i
    where i.app_type = 'school'
      and i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = v_year_month
      and i.income_category = 'tuition'
      and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception '该学生月份没有可结算的课时或学费收入，不能记录差额调整。';
  end if;

  select *
  into v_summary
  from public.school_get_student_monthly_settlement_summary(p_student_id, v_year_month)
  limit 1;

  if not found then
    raise exception '未能读取学生月度结算摘要，不能记录差额调整。';
  end if;

  if v_source = 'carry_final_balance' then
    v_adjustment_amount_cny := 0;
  elsif v_source = 'clear_balance' then
    v_adjustment_amount_cny := round(-coalesce(v_summary.final_due_cny, 0), 2);
  else
    if p_adjustment_amount_cny is null then
      raise exception '请填写差额调整金额。';
    end if;
    v_adjustment_amount_cny := round(p_adjustment_amount_cny, 2);
  end if;

  insert into public.school_student_settlement_adjustment_drafts (
    student_id,
    year_month,
    business_entity_id,
    adjustment_amount_cny,
    adjustment_source,
    adjustment_reason,
    note,
    status,
    settlement_id,
    app_type,
    created_by,
    updated_by,
    consumed_at,
    created_at,
    updated_at
  )
  values (
    p_student_id,
    v_year_month,
    v_business_entity_id,
    v_adjustment_amount_cny,
    v_source,
    v_reason,
    v_note,
    'active',
    null,
    'school',
    current_user,
    current_user,
    null,
    v_now,
    v_now
  )
  on conflict on constraint school_student_settlement_adjustment_drafts_student_month_key
  do update set
    business_entity_id = excluded.business_entity_id,
    adjustment_amount_cny = excluded.adjustment_amount_cny,
    adjustment_source = excluded.adjustment_source,
    adjustment_reason = excluded.adjustment_reason,
    note = excluded.note,
    status = 'active',
    settlement_id = null,
    updated_by = current_user,
    consumed_at = null,
    updated_at = v_now;

  return query
  select *
  from public.school_get_student_monthly_settlement_preview(p_student_id, v_year_month);
end;
$$;

comment on function public.school_set_student_monthly_settlement_draft_adjustment(uuid, text, numeric, text, text, text) is
  'Creates or updates one active pre-lock difference adjustment draft for a student/month. Non-manual adjustment amounts are calculated in DB/RPC; manual CNY amount is rounded to 2 decimals. Rejects locked snapshots and downstream active teacher wage blockers.';

create or replace function public.school_create_pending_cash_income_record(
  p_income_date date,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_student_id uuid,
  p_amount numeric,
  p_income_category text default 'tuition',
  p_description text default null,
  p_currency text default 'JPY',
  p_payment_currency text default 'JPY',
  p_exchange_rate numeric default null,
  p_is_taxable_income boolean default false,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_note text default null
)
returns table (
  income_id uuid,
  account_transaction_id uuid,
  account_id uuid,
  income_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_income_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, p_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_description text;
  v_note text;
begin
  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增 Cash 待提交收入'
  );

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  if v_currency not in ('JPY', 'CNY') or v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'Cash 收入币种仅支持 JPY / CNY。';
  end if;

  if v_currency <> v_payment_currency then
    raise exception 'Cash 收入要求收入币种与收款币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
    into v_business_entity
    from public.school_business_entities
   where id = p_business_entity_id
     and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  select *
    into v_student
    from public.school_students
   where id = p_student_id
     and app_type = 'school';

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student.business_entity_id is not null
     and v_student.business_entity_id is distinct from p_business_entity_id then
    raise exception '学生业务归属与收入业务归属不一致。';
  end if;

  if v_income_category = 'tuition' and exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = p_business_entity_id
       and s.year_month = v_year_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能直接新增收入。';
  end if;

  if v_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case when p_exchange_rate is not null then p_amount / p_exchange_rate else null end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case when p_exchange_rate is not null then p_amount * p_exchange_rate else null end;
  end if;

  v_description := coalesce(
    nullif(trim(p_description), ''),
    case v_income_category
      when 'tuition' then '学费收入'
      when 'material_fee' then '教材费收入'
      when 'registration_fee' then '报名费收入'
      else '其他费用收入'
    end
  );
  v_note := nullif(trim(coalesce(p_note, '')), '');

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
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_student_id,
    null,
    null,
    p_income_date,
    v_year_month,
    v_year_month,
    v_income_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_currency,
    null,
    'pending',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), 'Cash待提交'),
    v_income_category = 'tuition',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  return query
  select
    v_income_id,
    null::uuid,
    null::uuid,
    'pending'::text,
    null::uuid,
    null::text,
    null::uuid,
    'Cash 收入记录已保存，尚未提交 Cash。'::text;
end;
$$;

comment on function public.school_create_pending_cash_income_record(
  date,
  text,
  uuid,
  uuid,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  boolean,
  text,
  text,
  text
) is
  'Creates one pending School income record for later Cash submission. Amount JPY/CNY conversion is calculated in DB/RPC and no School account ledger or Cash request is created.';

grant execute on function public.school_create_pending_cash_income_record(
  date,
  text,
  uuid,
  uuid,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  boolean,
  text,
  text,
  text
) to authenticated, service_role;
