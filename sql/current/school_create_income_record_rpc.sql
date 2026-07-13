-- school_create_income_record_rpc.sql
-- RPC: public.school_create_income_record
-- Status: Executed on Supabase and verified by RPC unit tests.
-- Version: v2.21.4-income-create-rpc-sql-verified-20260603
--
-- Scope:
-- - Create received income record.
-- - Update school account current_balance.
-- - Insert related account transaction.
-- - Run all operations in one DB transaction.
--
-- Verified tests:
-- - Function exists in public schema.
-- - Rollback test succeeded.
-- - Commit test succeeded.
-- - Income / account / account transaction consistency verified.
-- - amount <= 0 rejected.
-- - exchange_rate <= 0 rejected.
-- - account currency mismatch rejected.
-- - Cross-month income_date / settlement_month rollback test succeeded.
-- - locked student monthly settlement rejected.
--
-- Notes:
-- - Only tuition income participates in student monthly settlement guards.
-- - Edit/reversal are handled by dedicated guarded RPCs; no delete/void/attachment support here.
-- - No complex cross-currency posting.
-- - account.currency must match payment_currency.
-- - locked student monthly settlement cannot be directly modified by income creation.

create or replace function public.school_create_income_record(
  p_income_date date,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_student_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_income_category text default 'tuition',
  p_description text default null,
  p_currency text default 'JPY',
  p_payment_currency text default 'JPY',
  p_exchange_rate numeric default null,
  p_payment_method text default null,
  p_is_taxable_income boolean default false,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_include_in_student_settlement boolean default true,
  p_note text default null
)
returns table (
  income_id uuid,
  account_transaction_id uuid,
  account_id uuid,
  new_balance numeric,
  income_status text,
  transaction_type text,
  settlement_month text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_account public.school_accounts%rowtype;
  v_income_id uuid;
  v_account_transaction_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_include_in_student_settlement boolean;
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_transaction_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_old_balance numeric;
  v_new_balance numeric;
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
    '新增收入'
  );

  if p_account_id is null then
    raise exception '请选择入账账户。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category = '' then
    raise exception '收入分类不能为空。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  v_include_in_student_settlement := v_income_category = 'tuition'
    and coalesce(p_include_in_student_settlement, true);

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收入币种：%。', v_currency;
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收款币种：%。', v_payment_currency;
  end if;

  if v_currency <> v_payment_currency then
    raise exception '第一版要求收入币种与收款币种一致。';
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

  if v_include_in_student_settlement and p_student_id is null then
    raise exception '进入学生结算的收入必须选择学生。';
  end if;

  if p_student_id is not null then
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
  end if;

  if v_include_in_student_settlement and exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and s.year_month = v_year_month
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能直接新增收入。';
  end if;

  select *
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '入账账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '入账账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '入账账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_payment_currency then
    raise exception '入账账户币种必须与收款币种一致。';
  end if;

  if v_payment_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case
      when p_exchange_rate is not null then p_amount / p_exchange_rate
      else null
    end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case
      when p_exchange_rate is not null then p_amount * p_exchange_rate
      else null
    end;
  end if;

  v_transaction_month := to_char(p_income_date, 'YYYY-MM');
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance + p_amount;
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
    p_account_id,
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
    nullif(trim(coalesce(p_payment_method, '')), ''),
    'received',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认'),
    v_include_in_student_settlement,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  update public.school_accounts
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where id = v_account.id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_account.id,
    p_business_entity_id,
    p_income_date,
    v_transaction_month,
    'income_adjust',
    'school_income_records',
    v_income_id,
    v_account.currency,
    p_amount,
    v_new_balance,
    '收入入账：' || v_description,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  return query
  select
    v_income_id,
    v_account_transaction_id,
    v_account.id,
    v_new_balance,
    'received'::text,
    'income_adjust'::text,
    v_year_month;
end;
$$;

comment on function public.school_create_income_record(
  date,
  text,
  uuid,
  uuid,
  uuid,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  text,
  boolean,
  text,
  text,
  boolean,
  text
) is
  'Verified RPC for v2 income creation: creates received income, updates account balance, and inserts account transaction. Only tuition income participates in student settlement.';

-- Permission note:
-- Keep execute permission management explicit. If permissions need to be
-- re-applied in another environment, review before enabling:
-- grant execute on function public.school_create_income_record(
--   date, text, uuid, uuid, uuid, numeric, text, text, text, text,
--   numeric, text, boolean, text, text, boolean, text
-- ) to authenticated;
--
-- This file intentionally does not include executable test insert/update/delete
-- statements.

-- Reference call example with placeholder IDs.
--
-- select *
-- from public.school_create_income_record(
--   p_income_date := date '2026-06-03',
--   p_settlement_month := '2026-06',
--   p_business_entity_id := '00000000-0000-0000-0000-000000000000',
--   p_student_id := '00000000-0000-0000-0000-000000000000',
--   p_account_id := '00000000-0000-0000-0000-000000000000',
--   p_amount := 10000,
--   p_income_category := 'tuition',
--   p_description := '学费收入',
--   p_currency := 'JPY',
--   p_payment_currency := 'JPY',
--   p_payment_method := 'cash',
--   p_include_in_student_settlement := true,
--   p_note := null
-- );
