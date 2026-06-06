-- school_update_account_profile_rpc.sql
-- RPC: public.school_update_account_profile
-- Purpose: Update non-balance account profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.40.0-account-profile-update-full-autopilot-20260607
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updates only name/account_type/is_company_account/is_active/note and leaves no residue.
-- - Commit test uses whitelisted codex-test account only.
-- - opening_balance, current_balance, account transactions, and historical income,
--   expense, reimbursement, payment, transfer, adjustment, settlement, and wage data remain unchanged.
-- - Empty name and invalid account type are rejected.
--
-- Scope:
-- - Update one school account row.
-- - Allowed fields: name, account_type, is_company_account, is_active, note.
-- - Preserve account_code, currency, business_entity_id, opening_balance,
--   current_balance, app_type, created_at, account transactions, and all
--   historical business records.
--
-- Not supported:
-- - Creating or deleting accounts.
-- - Editing opening_balance or current_balance.
-- - Editing currency or business ownership.
-- - Recalculating, repairing, inserting, updating, or deleting account transactions.
-- - Balance corrections; use the verified account adjustment flow instead.
--
-- Review before execution:
-- - Confirm public.school_accounts has all allowed columns.
-- - Confirm account_type allowed values fit current product expectations.
-- - Confirm commit test uses whitelisted test account only.

create or replace function public.school_update_account_profile(
  p_account_id uuid,
  p_name text,
  p_account_type text,
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
  v_account_type text := nullif(trim(coalesce(p_account_type, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_account_id is null then
    raise exception '请选择要编辑的账户。';
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

  if p_is_company_account is null then
    raise exception '公司账户标记不能为空。';
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
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

  update public.school_accounts a
  set
    name = v_name,
    account_type = v_account_type,
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
  boolean,
  boolean,
  text
) is
  'Updates only non-balance school account profile fields: name, account_type, is_company_account, is_active, and note.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
