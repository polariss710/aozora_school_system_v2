-- school_create_personal_cash_tuition_income_record_rpc.sql
-- Status: executed on School DB 2026-06-13 for historical Phase 2 personal tuition linkage.
-- Purpose:
-- - Create one personal-business tuition JPY income record for Cash System linkage.
-- - Create one pending school_personal_cash_income_linkage_events outbox row
--   in the same school DB transaction.
-- - Do not update school_accounts.current_balance.
-- - Do not insert school_account_transactions.
-- - Do not write Cash System.

create or replace function public.school_create_personal_cash_tuition_income_record(
  p_income_date date,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_student_id uuid,
  p_cash_account_mapping_id uuid,
  p_amount numeric,
  p_income_category text default 'tuition',
  p_description text default null,
  p_currency text default 'JPY',
  p_payment_currency text default 'JPY',
  p_payment_method text default null,
  p_is_taxable_income boolean default false,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_note text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  business_entity_id uuid,
  student_id uuid,
  cash_account_mapping_id uuid,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  currency text,
  amount numeric,
  income_status text,
  source_event_type text,
  idempotency_key text,
  sync_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_mapping public.school_personal_cash_account_mappings%rowtype;
  v_income_id uuid;
  v_event_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_description text;
  v_note text;
  v_idempotency_key text;
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

  if p_student_id is null then
    raise exception '个人业务学费收入必须选择学生。';
  end if;

  if p_cash_account_mapping_id is null then
    raise exception '请选择 Cash System 入账账户映射。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category <> 'tuition' then
    raise exception '个人业务 Cash 联动收入仅支持 tuition。';
  end if;

  if v_currency <> 'JPY' or v_payment_currency <> 'JPY' then
    raise exception '个人业务 Cash 联动收入仅支持 JPY。';
  end if;

  select *
    into v_business_entity
    from public.school_business_entities
   where id = p_business_entity_id
     and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if coalesce(v_business_entity.entity_type, '') <> 'personal' then
    raise exception '个人业务 Cash 联动收入仅支持 personal business。';
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

  if exists (
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
    into v_mapping
    from public.school_personal_cash_account_mappings
   where school_personal_cash_account_mappings.id = p_cash_account_mapping_id
   for update;

  if not found then
    raise exception 'personal Cash account mapping not found: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.is_active is not true then
    raise exception 'personal Cash account mapping is inactive: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.business_entity_id is distinct from p_business_entity_id then
    raise exception 'Cash account mapping business entity does not match income business entity';
  end if;

  if v_mapping.flow_type <> 'tuition_income'
     or v_mapping.school_currency <> 'JPY'
     or v_mapping.cash_currency <> 'JPY' then
    raise exception 'Cash account mapping is not valid for Phase 2 tuition_income JPY linkage';
  end if;

  v_description := coalesce(nullif(trim(p_description), ''), '学费收入');
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
    'tuition',
    v_description,
    'JPY',
    p_amount,
    p_amount,
    null,
    null,
    'JPY',
    nullif(trim(coalesce(p_payment_method, '')), ''),
    'received',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认'),
    true,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  v_idempotency_key := concat(
    'aozora_school:school_income_records:',
    v_income_id::text,
    ':tuition_income_received'
  );

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
    cash_transaction_table,
    cash_transaction_id,
    currency,
    amount,
    idempotency_key,
    sync_status,
    retry_count,
    last_error,
    note,
    created_at,
    updated_at,
    synced_at
  )
  values (
    'school_income_records',
    v_income_id,
    'tuition_income_received',
    v_income_id,
    p_business_entity_id,
    p_cash_account_mapping_id,
    v_mapping.cash_user_id,
    v_mapping.cash_account_id,
    v_mapping.cash_account_name_snapshot,
    'home_jpy_transactions',
    null,
    'JPY',
    p_amount,
    v_idempotency_key,
    'pending',
    0,
    null,
    v_note,
    v_now,
    v_now,
    null
  )
  returning id into v_event_id;

  return query
  select
    v_income_id,
    v_event_id,
    p_business_entity_id,
    p_student_id,
    p_cash_account_mapping_id,
    v_mapping.cash_user_id,
    v_mapping.cash_account_id,
    v_mapping.cash_account_name_snapshot,
    'JPY'::text,
    p_amount,
    'received'::text,
    'tuition_income_received'::text,
    v_idempotency_key,
    'pending'::text,
    v_now;
end;
$$;

comment on function public.school_create_personal_cash_tuition_income_record(
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
  text,
  boolean,
  text,
  text,
  text
) is
  'Creates one personal-business tuition JPY income record and one pending school-side Cash income linkage event. Does not write school account balance, school account transactions, or Cash DB.';

grant execute on function public.school_create_personal_cash_tuition_income_record(
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
  text,
  boolean,
  text,
  text,
  text
) to authenticated;
