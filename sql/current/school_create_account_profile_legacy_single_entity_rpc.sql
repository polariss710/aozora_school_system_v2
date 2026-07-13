-- school_create_account_profile_legacy_single_entity_rpc.sql
-- Purpose: Guard the legacy account-create overload with the V2 single
--          new-business-entity policy while preserving the old signature.

create or replace function public.school_create_account_profile(
  p_account_code text,
  p_name text,
  p_account_type text default 'bank',
  p_currency text default 'JPY',
  p_business_entity_id uuid default null,
  p_is_company_account boolean default false,
  p_is_active boolean default true,
  p_note text default null
)
returns table (
  account_id uuid,
  account_code text,
  name text,
  account_type text,
  currency text,
  business_entity_id uuid,
  opening_balance numeric,
  current_balance numeric,
  is_company_account boolean,
  is_active boolean,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_code text := nullif(trim(coalesce(p_account_code, '')), '');
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_account_type text := nullif(trim(coalesce(p_account_type, 'bank')), '');
  v_currency text := upper(nullif(trim(coalesce(p_currency, 'JPY')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_business_entity_id uuid;
  v_account_id uuid;
begin
  if v_account_code is null then
    raise exception '账户编码不能为空。';
  end if;

  if v_name is null then
    raise exception '账户名称不能为空。';
  end if;

  if v_account_type is null then
    raise exception '账户类型不能为空。';
  end if;

  if v_account_type not in ('cash', 'bank', 'wallet', 'receivable', 'payable', 'other') then
    raise exception '账户类型无效：%。', v_account_type;
  end if;

  if v_currency is null then
    raise exception '账户币种不能为空。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '账户币种无效：%。', v_currency;
  end if;

  v_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_business_entity_id, public.school_primary_business_entity_id()),
    '新增账户'
  );

  if p_is_company_account is null then
    raise exception '公司账户标记不能为空。';
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  if exists (
    select 1
    from public.school_accounts a
    where a.account_code = v_account_code
  ) then
    raise exception '账户编码已存在：%。', v_account_code;
  end if;

  insert into public.school_accounts (
    account_code,
    name,
    account_type,
    currency,
    business_entity_id,
    opening_balance,
    current_balance,
    is_company_account,
    is_active,
    note,
    app_type
  )
  values (
    v_account_code,
    v_name,
    v_account_type,
    v_currency,
    v_business_entity_id,
    0,
    0,
    p_is_company_account,
    p_is_active,
    v_note,
    'school'
  )
  returning id into v_account_id;

  return query
  select
    a.id,
    a.account_code,
    a.name,
    a.account_type,
    a.currency,
    a.business_entity_id,
    a.opening_balance,
    a.current_balance,
    a.is_company_account,
    a.is_active,
    a.note,
    a.created_at,
    a.updated_at
  from public.school_accounts a
  where a.id = v_account_id;
exception
  when unique_violation then
    raise exception '账户编码已存在：%。', v_account_code;
end;
$$;

comment on function public.school_create_account_profile(
  text,
  text,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text
) is
  'Legacy account create overload guarded by the V2 single new business entity policy.';
