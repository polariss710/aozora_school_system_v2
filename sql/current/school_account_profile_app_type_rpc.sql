-- school_account_profile_app_type_rpc.sql
-- RPC: public.school_create_account_profile / public.school_update_account_profile app_type overloads
-- Purpose: First-stage account app isolation for school/family account master data.
-- Status: executed for 2026-06-13 account app_type isolation.
-- Version: v2.109.0-account-app-type-isolation-20260613
--
-- Scope:
-- - Add overloads that accept p_app_type.
-- - Allow account profile create/update for app_type = school or family.
-- - Keep family accounts as account master rows only in this phase; no family
--   account transactions, family income/expense pages, transfer, adjustment,
--   reimbursement, payment, wage, or settlement flows are added.
-- - Preserve existing legacy overloads for old callers.

create or replace function public.school_create_account_profile(
  p_account_code text,
  p_name text,
  p_initial_balance numeric,
  p_account_type text default null,
  p_currency text default 'JPY',
  p_business_entity_id uuid default null,
  p_is_company_account boolean default false,
  p_is_active boolean default true,
  p_note text default null,
  p_app_type text default 'school'
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
  app_type text,
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
  v_currency text := upper(nullif(trim(coalesce(p_currency, 'JPY')), ''));
  v_account_type text := nullif(trim(coalesce(p_account_type, '')), '');
  v_initial_balance numeric := coalesce(p_initial_balance, 0);
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_app_type text := lower(nullif(trim(coalesce(p_app_type, 'school')), ''));
  v_business_entity_id uuid := p_business_entity_id;
  v_is_company_account boolean := coalesce(p_is_company_account, false);
  v_account_id uuid;
begin
  if v_name is null then
    raise exception '账户名称不能为空。';
  end if;

  if v_app_type not in ('school', 'family') then
    raise exception '账户用途无效：%。', coalesce(v_app_type, '');
  end if;

  if v_currency is null then
    raise exception '账户币种不能为空。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '账户币种无效：%。', v_currency;
  end if;

  if v_account_type is null then
    v_account_type := case
      when v_currency = 'CNY' then 'cny_yuebao'
      else 'jpy_mufg_card'
    end;
  end if;

  if not (
    (v_currency = 'CNY' and v_account_type in ('cny_yuebao', 'cny_yulibao'))
    or (v_currency = 'JPY' and v_account_type in ('jpy_mufg_card', 'jpy_rakuten_card', 'jpy_cash'))
  ) then
    raise exception '账户类型与币种不匹配。';
  end if;

  if v_app_type = 'school' then
    if v_business_entity_id is null then
      raise exception '请选择业务归属。';
    end if;

    if not exists (
      select 1
      from public.school_business_entities b
      where b.id = v_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
      raise exception '业务归属不存在或已停用。';
    end if;

    if p_is_company_account is null then
      raise exception '公司账户标记不能为空。';
    end if;
  else
    v_business_entity_id := null;
    v_is_company_account := false;
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  if v_account_code is null then
    loop
      v_account_code := case
        when v_app_type = 'family' then 'fam-acct-'
        else 'acct-'
      end || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
      exit when not exists (
        select 1
        from public.school_accounts a
        where a.account_code = v_account_code
      );
    end loop;
  elsif exists (
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
    v_initial_balance,
    v_initial_balance,
    v_is_company_account,
    p_is_active,
    v_note,
    v_app_type
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
    a.app_type,
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
  numeric,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text,
  text
) is
  'Creates one account profile row for app_type school or family. Family accounts are master data only in this phase and do not create account transactions.';

create or replace function public.school_update_account_profile(
  p_account_id uuid,
  p_name text,
  p_currency text,
  p_account_type text,
  p_business_entity_id uuid,
  p_is_company_account boolean,
  p_is_active boolean,
  p_note text default null,
  p_app_type text default null
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
  app_type text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_account public.school_accounts%rowtype;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_currency text := upper(nullif(trim(coalesce(p_currency, '')), ''));
  v_account_type text := nullif(trim(coalesce(p_account_type, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_requested_app_type text := lower(nullif(trim(coalesce(p_app_type, '')), ''));
  v_business_entity_id uuid := p_business_entity_id;
  v_is_company_account boolean := coalesce(p_is_company_account, false);
  v_type_matches_currency boolean;
  v_preserves_legacy_type boolean;
begin
  if p_account_id is null then
    raise exception '请选择要编辑的账户。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = p_account_id
    and coalesce(a.app_type, '') in ('school', 'family')
  for update;

  if not found then
    raise exception '账户不存在。';
  end if;

  if v_requested_app_type is not null and v_requested_app_type <> v_account.app_type then
    raise exception '账户用途不能在资料编辑中修改。';
  end if;

  if v_name is null then
    raise exception '账户名称不能为空。';
  end if;

  if v_currency is null then
    raise exception '账户币种不能为空。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '账户币种无效：%。', v_currency;
  end if;

  if v_account_type is null then
    raise exception '账户类型不能为空。';
  end if;

  v_type_matches_currency := (
    (v_currency = 'CNY' and v_account_type in ('cny_yuebao', 'cny_yulibao'))
    or (v_currency = 'JPY' and v_account_type in ('jpy_mufg_card', 'jpy_rakuten_card', 'jpy_cash'))
  );

  v_preserves_legacy_type := (
    v_currency = v_account.currency
    and v_account_type = v_account.account_type
  );

  if not v_type_matches_currency and not v_preserves_legacy_type then
    raise exception '账户类型与币种不匹配。';
  end if;

  if v_currency <> v_account.currency and exists (
    select 1
    from public.school_account_transactions tx
    where tx.account_id = v_account.id
  ) then
    raise exception '账户已有流水，不能在资料编辑中修改币种。';
  end if;

  if v_account.app_type = 'school' then
    if v_business_entity_id is null then
      raise exception '请选择业务归属。';
    end if;

    if v_business_entity_id is distinct from v_account.business_entity_id then
      if not exists (
        select 1
        from public.school_business_entities b
        where b.id = v_business_entity_id
          and coalesce(b.is_active, true) = true
      ) then
        raise exception '业务归属不存在或已停用。';
      end if;
    elsif not exists (
      select 1
      from public.school_business_entities b
      where b.id = v_business_entity_id
    ) then
      raise exception '业务归属不存在。';
    end if;

    if p_is_company_account is null then
      raise exception '公司账户标记不能为空。';
    end if;
  else
    v_business_entity_id := null;
    v_is_company_account := false;
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  update public.school_accounts a
  set
    name = v_name,
    currency = v_currency,
    account_type = v_account_type,
    business_entity_id = v_business_entity_id,
    is_company_account = v_is_company_account,
    is_active = p_is_active,
    note = v_note,
    updated_at = v_now
  where a.id = v_account.id;

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
    a.app_type,
    a.updated_at
  from public.school_accounts a
  where a.id = v_account.id;
end;
$$;

comment on function public.school_update_account_profile(
  uuid,
  text,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text,
  text
) is
  'Updates profile fields for existing school/family account rows without changing app_type, balances, or account transactions.';

grant execute on function public.school_create_account_profile(
  text,
  text,
  numeric,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text,
  text
) to authenticated;

grant execute on function public.school_update_account_profile(
  uuid,
  text,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text,
  text
) to authenticated;
