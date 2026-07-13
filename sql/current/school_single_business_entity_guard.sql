-- school_single_business_entity_guard.sql
-- Purpose: Centralize the V2 single-new-business-entity policy.
-- Policy:
-- - New School business rows must use business entity code = aosora.
-- - Historical non-aosora rows remain readable and can continue inherited
--   processing through their original source records.

create or replace function public.school_primary_business_entity_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_business_entity_id uuid;
begin
  select b.id
  into v_business_entity_id
  from public.school_business_entities b
  where b.code = 'aosora'
    and coalesce(b.is_active, true) = true
  order by b.created_at nulls last, b.id
  limit 1;

  if v_business_entity_id is null then
    raise exception '青空进学塾业务归属不存在或已停用。';
  end if;

  return v_business_entity_id;
end;
$$;

comment on function public.school_primary_business_entity_id() is
  'Returns the active primary School business entity for new V2 business writes. Current policy resolves by school_business_entities.code = aosora.';

create or replace function public.school_assert_new_business_entity_allowed(
  p_business_entity_id uuid,
  p_context text default '新业务'
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_primary_business_entity_id uuid;
begin
  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  v_primary_business_entity_id := public.school_primary_business_entity_id();

  if p_business_entity_id is distinct from v_primary_business_entity_id then
    raise exception '%只能归属青空进学塾。个人名义仅保留历史处理，不能用于新业务。', coalesce(nullif(trim(p_context), ''), '新业务');
  end if;

  return v_primary_business_entity_id;
end;
$$;

comment on function public.school_assert_new_business_entity_allowed(uuid, text) is
  'Validates that a new School business write targets the primary aosora business entity while preserving historical non-aosora rows for inherited processing.';

grant execute on function public.school_primary_business_entity_id() to authenticated;
grant execute on function public.school_assert_new_business_entity_allowed(uuid, text) to authenticated;
