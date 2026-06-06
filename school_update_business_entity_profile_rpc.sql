-- school_update_business_entity_profile_rpc.sql
-- RPC: public.school_update_business_entity_profile
-- Purpose: Update non-sensitive business entity profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.39.0-business-entity-profile-update-full-autopilot-20260607
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updates only name/entity_type/default_currency/is_active/note and leaves no residue.
-- - Commit test uses whitelisted codex-test business entity only.
-- - Historical income, expense, account, settlement, wage, payment, account balance, and account transaction data remain unchanged.
-- - Empty name, invalid entity type, and invalid currency are rejected.
--
-- Scope:
-- - Update one business entity row.
-- - Allowed fields: name, entity_type, default_currency, is_active, note.
-- - Preserve code, is_company_report, created_at, historical module data,
--   account balances, and account transactions.
--
-- Not supported:
-- - Editing code or company-report inclusion.
-- - Deleting or merging business entities.
-- - Reassigning, recalculating, or repairing historical records.
--
-- Review before execution:
-- - Confirm public.school_business_entities has all allowed columns.
-- - Confirm entity_type and currency allowed values fit current product expectations.
-- - Confirm commit test uses whitelisted test business entity only.

create or replace function public.school_update_business_entity_profile(
  p_business_entity_id uuid,
  p_name text,
  p_entity_type text,
  p_default_currency text,
  p_is_active boolean,
  p_note text default null
)
returns table (
  business_entity_id uuid,
  code text,
  name text,
  entity_type text,
  default_currency text,
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
  v_entity public.school_business_entities%rowtype;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_entity_type text := nullif(trim(coalesce(p_entity_type, '')), '');
  v_default_currency text := upper(nullif(trim(coalesce(p_default_currency, '')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_business_entity_id is null then
    raise exception '请选择要编辑的业务归属。';
  end if;

  if v_name is null then
    raise exception '业务归属名称不能为空。';
  end if;

  if v_entity_type is null then
    raise exception '业务归属类型不能为空。';
  end if;

  if v_entity_type not in ('company', 'personal') then
    raise exception '业务归属类型无效：%。', v_entity_type;
  end if;

  if v_default_currency is null then
    raise exception '默认币种不能为空。';
  end if;

  if v_default_currency not in ('JPY', 'CNY') then
    raise exception '默认币种无效：%。', v_default_currency;
  end if;

  if p_is_active is null then
    raise exception '启用状态不能为空。';
  end if;

  select *
  into v_entity
  from public.school_business_entities b
  where b.id = p_business_entity_id
  for update;

  if not found then
    raise exception '业务归属不存在。';
  end if;

  update public.school_business_entities b
  set
    name = v_name,
    entity_type = v_entity_type,
    default_currency = v_default_currency,
    is_active = p_is_active,
    note = v_note,
    updated_at = v_now
  where b.id = v_entity.id;

  return query
  select
    b.id,
    b.code,
    b.name,
    b.entity_type,
    b.default_currency,
    b.is_active,
    b.note,
    b.updated_at
  from public.school_business_entities b
  where b.id = v_entity.id;
end;
$$;

comment on function public.school_update_business_entity_profile(
  uuid,
  text,
  text,
  text,
  boolean,
  text
) is
  'Updates only non-sensitive business entity profile fields: name, entity_type, default_currency, is_active, and note.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
