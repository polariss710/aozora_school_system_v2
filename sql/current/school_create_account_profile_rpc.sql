-- school_create_account_profile_rpc.sql
-- RPC: public.school_create_account_profile
-- Purpose: Create future-use school account master data only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and whitelist commit-tested.
-- Version: v2.104.0-account-dialog-field-scope-20260612
--
-- Scope:
-- - Insert one row into public.school_accounts.
-- - Open create fields: name, currency, account_type, business_entity_id,
--   opening/current initial balance, is_company_account, is_active, note.
-- - account_code is generated when omitted by the UI.
-- - opening_balance and current_balance are initialized to the same value only
--   at account creation time.
--
-- Not supported:
-- - Creating account transactions for the initial balance.
-- - Editing current balance from the profile dialog.
-- - Rewriting historical income, expense, reimbursement, transfer, adjustment,
--   payment request, balance, or account transaction records.
-- - Deleting, merging, or replacing accounts.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test inserted one codex-test account with non-zero initial balance,
--   verified opening/current balance initialization, verified zero account
--   transactions, updated profile fields, and left no residue.
-- - Whitelist commit test inserted only codex-test business entities/account,
--   verified generated account_code, initial balance, currency/type/business
--   edit, and zero account transactions.

create or replace function public.school_create_account_profile(
  p_account_code text,
  p_name text,
  p_initial_balance numeric,
  p_account_type text default null,
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
  v_currency text := upper(nullif(trim(coalesce(p_currency, 'JPY')), ''));
  v_account_type text := nullif(trim(coalesce(p_account_type, '')), '');
  v_initial_balance numeric := coalesce(p_initial_balance, 0);
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_account_id uuid;
begin
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

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增账户'
  );

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = p_business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属不存在或已停用。';
  end if;

  if p_is_company_account is null then
    raise exception '公司账户标记不能为空。';
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  if v_account_code is null then
    loop
      v_account_code := 'acct-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
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
    p_business_entity_id,
    v_initial_balance,
    v_initial_balance,
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
  numeric,
  text,
  text,
  uuid,
  boolean,
  boolean,
  text
) is
  'Creates one future-use school account master row. Account code can be generated by RPC; opening/current balances are initialized only at creation and no account transaction is created.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
