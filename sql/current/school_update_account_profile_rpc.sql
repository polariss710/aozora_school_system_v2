-- school_update_account_profile_rpc.sql
-- RPC: public.school_update_account_profile
-- Purpose: Update non-balance account profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and whitelist commit-tested.
-- Version: v2.104.0-account-dialog-field-scope-20260612
--
-- Scope:
-- - Update one school account row.
-- - Open edit fields: name, currency, account_type, business_entity_id,
--   is_company_account, is_active, note.
-- - Preserve account_code, opening_balance, current_balance, app_type,
--   created_at, account transactions, and all historical business records.
-- - Currency changes are rejected once the account has account transactions,
--   because historical transaction currency is not rewritten by this profile RPC.
-- - Legacy account_type values are preserved only when unchanged with the
--   current currency; changing currency/type must use the narrowed options.
--
-- Not supported:
-- - Creating or deleting accounts.
-- - Editing opening_balance or current_balance.
-- - Recalculating, repairing, inserting, updating, or deleting account
--   transactions.
-- - Balance corrections; use the verified account adjustment flow instead.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updated only account profile fields and preserved
--   opening_balance/current_balance and account transaction count.
-- - Rollback guard test rejected currency changes after an account transaction
--   existed and left no residue.
-- - Whitelist commit test used only codex-test business entities/account.

create or replace function public.school_update_account_profile(
  p_account_id uuid,
  p_name text,
  p_currency text,
  p_account_type text,
  p_business_entity_id uuid,
  p_is_company_account boolean,
  p_is_active boolean,
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
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '账户不存在。';
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
      and coalesce(tx.app_type, '') = 'school'
  ) then
    raise exception '账户已有流水，不能在资料编辑中修改币种。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_business_entity_id is distinct from v_account.business_entity_id then
    if not exists (
      select 1
      from public.school_business_entities b
      where b.id = p_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
      raise exception '业务归属不存在或已停用。';
    end if;
  elsif not exists (
    select 1
    from public.school_business_entities b
    where b.id = p_business_entity_id
  ) then
    raise exception '业务归属不存在。';
  end if;

  if p_is_company_account is null then
    raise exception '公司账户标记不能为空。';
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  update public.school_accounts a
  set
    name = v_name,
    currency = v_currency,
    account_type = v_account_type,
    business_entity_id = p_business_entity_id,
    is_company_account = p_is_company_account,
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
  text
) is
  'Updates only school account profile fields exposed by the narrowed dialog: name, currency, account_type, business_entity_id, is_company_account, is_active, and note. Preserves balances and account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
