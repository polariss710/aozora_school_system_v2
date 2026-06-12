-- school_update_income_record_rpc.sql
-- RPC: public.school_update_income_record
-- Purpose: guarded v2 edit for received income records.
--
-- Scope:
-- - Update one received income row.
-- - Keep writes inside income/account/account-transaction chain.
-- - Adjust the linked account current_balance and original income_adjust transaction
--   only when the original transaction is still the latest transaction for the account.
-- - Reject reversed income, student-payment-chain income, locked tuition settlement,
--   account changes, currency mismatches, and abnormal account transaction history.
--
-- Notes:
-- - Account currency is not user-maintained. The selected account owns the currency.
-- - Only tuition income participates in student monthly settlement guards.
-- - Non-tuition categories are ordinary income and are stored with
--   include_in_student_settlement = false.

create or replace function public.school_update_income_record(
  p_income_id uuid,
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
  v_income public.school_income_records%rowtype;
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_transaction_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_new_balance numeric;
  v_amount_delta numeric;
  v_description text;
  v_note text;
  v_include_in_student_settlement boolean;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
begin
  if p_income_id is null then
    raise exception '请选择要编辑的收入记录。';
  end if;

  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

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
    raise exception '收入币种必须与收款币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
  into v_income
  from public.school_income_records i
  where i.id = p_income_id
    and coalesce(i.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '收入记录不存在。';
  end if;

  if v_income.status = 'reversed'
    or v_income.reversed_at is not null
    or v_income.reversal_account_transaction_id is not null then
    raise exception '已撤销收入不能编辑。';
  end if;

  if v_income.status is distinct from 'received' then
    raise exception '只能编辑已收款收入。';
  end if;

  if v_income.student_payment_id is not null then
    raise exception '关联学生收款链路的收入暂不支持普通编辑。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '已存在收入撤销流水，不能编辑。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '收入原始账户流水不存在或不唯一，不能编辑。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust'
  for update;

  if v_original_transaction.amount is distinct from v_income.amount
    or v_original_transaction.account_id is distinct from v_income.account_id
    or v_original_transaction.currency is distinct from v_income.currency then
    raise exception '收入原始账户流水与收入记录不一致，不能编辑。';
  end if;

  if exists (
    select 1
    from public.school_account_transactions t
    where t.account_id = v_original_transaction.account_id
      and coalesce(t.app_type, '') = 'school'
      and (
        t.created_at > v_original_transaction.created_at
        or (t.created_at = v_original_transaction.created_at and t.id::text > v_original_transaction.id::text)
      )
  ) then
    raise exception '该收入之后已有账户流水，不能直接编辑会影响余额的字段。请使用撤销后重新新增。';
  end if;

  if p_account_id is distinct from v_income.account_id then
    raise exception '已入账收入暂不支持更换入账账户。请撤销后重新新增。';
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

  if coalesce(v_income.include_in_student_settlement, false)
    and v_income.student_id is not null
    and nullif(trim(coalesce(v_income.settlement_month, '')), '') is not null
    and v_income.business_entity_id is not null
    and exists (
      select 1
      from public.school_student_monthly_settlements s
      where s.student_id = v_income.student_id
        and s.business_entity_id = v_income.business_entity_id
        and s.year_month = v_income.settlement_month
        and s.settlement_status = 'locked'
    ) then
    raise exception '原学生月度结算已锁定，不能编辑收入。';
  end if;

  if v_include_in_student_settlement and exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and s.year_month = v_year_month
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能编辑收入。';
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

  if v_account.currency is distinct from v_payment_currency
    or v_account.currency is distinct from v_currency then
    raise exception '入账账户币种必须与收入币种一致。';
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
  v_amount_delta := p_amount - v_income.amount;
  v_new_balance := coalesce(v_account.current_balance, 0) + v_amount_delta;
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

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

  update public.school_account_transactions t
  set
    business_entity_id = p_business_entity_id,
    transaction_date = p_income_date,
    year_month = v_transaction_month,
    currency = v_account.currency,
    amount = p_amount,
    balance_after = v_new_balance,
    description = '收入入账：' || v_description,
    note = v_note,
    updated_at = v_now
  where t.id = v_original_transaction.id;

  update public.school_income_records i
  set
    business_entity_id = p_business_entity_id,
    student_id = p_student_id,
    account_id = p_account_id,
    income_date = p_income_date,
    year_month = v_year_month,
    settlement_month = v_year_month,
    income_category = v_income_category,
    description = v_description,
    currency = v_account.currency,
    amount = p_amount,
    amount_jpy = v_amount_jpy,
    amount_cny = v_amount_cny,
    exchange_rate = p_exchange_rate,
    payment_currency = v_account.currency,
    payment_method = nullif(trim(coalesce(p_payment_method, '')), ''),
    is_taxable_income = coalesce(p_is_taxable_income, false),
    tax_category = nullif(trim(coalesce(p_tax_category, '')), ''),
    receipt_status = coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认'),
    include_in_student_settlement = v_include_in_student_settlement,
    note = v_note,
    updated_at = v_now
  where i.id = v_income.id;

  return query
  select
    v_income.id,
    v_original_transaction.id,
    v_account.id,
    v_new_balance,
    'received'::text,
    'income_adjust'::text,
    v_year_month;
end;
$$;

comment on function public.school_update_income_record(
  uuid,
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
  'Guarded v2 income edit: updates one received income and its original account transaction only when settlement/account guards pass.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
