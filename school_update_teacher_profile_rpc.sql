-- school_update_teacher_profile_rpc.sql
-- RPC: public.school_update_teacher_profile
-- Purpose: Update non-sensitive teacher display profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.37.0-teacher-profile-update-full-autopilot-trial-20260607
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updates only display_name/status/default_business_entity_id/note and leaves no residue.
-- - Commit test uses whitelisted codex-test teacher only.
-- - Wage rule, settlement, payment, lesson, and sensitive fields remain unchanged.
-- - Empty display name, invalid status, and inactive/missing business entity are rejected.
--
-- Scope:
-- - Update one school teacher row.
-- - Allowed fields: display_name, status, default_business_entity_id, note.
-- - Preserve wage rules, settlement fields, payment data, lesson data, bank
--   details, phone, email, wechat, default rates, currencies, payment method,
--   department, subject, teacher_code, and system name.
--
-- Not supported:
-- - Editing teacher_code, name, kana_name, department, subject, pay rates, currencies, payment method.
-- - Editing bank, alipay, wechat pay, phone, email, or other sensitive/contact fields.
-- - Editing wage rules, wage locks, salary payments, lessons, or settlements.
-- - Creating, deleting, or merging teachers.
--
-- Review before execution:
-- - Confirm public.school_teachers has all allowed columns.
-- - Confirm status allowed values fit current product expectations.
-- - Confirm commit test uses whitelisted test teacher only.

create or replace function public.school_update_teacher_profile(
  p_teacher_id uuid,
  p_display_name text,
  p_status text,
  p_default_business_entity_id uuid default null,
  p_note text default null
)
returns table (
  teacher_id uuid,
  teacher_code text,
  name text,
  display_name text,
  status text,
  default_business_entity_id uuid,
  note text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_teacher public.school_teachers%rowtype;
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_teacher_id is null then
    raise exception '请选择要编辑的老师。';
  end if;

  if v_display_name is null then
    raise exception '老师显示名称不能为空。';
  end if;

  if v_status is null then
    raise exception '老师状态不能为空。';
  end if;

  if v_status not in ('employed', 'inactive', 'paused', 'resigned') then
    raise exception '老师状态无效：%。', v_status;
  end if;

  if p_default_business_entity_id is not null
    and not exists (
      select 1
      from public.school_business_entities b
      where b.id = p_default_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
    raise exception '业务归属不存在或已停用。';
  end if;

  select *
  into v_teacher
  from public.school_teachers t
  where t.id = p_teacher_id
    and coalesce(t.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '老师不存在。';
  end if;

  update public.school_teachers t
  set
    display_name = v_display_name,
    status = v_status,
    default_business_entity_id = p_default_business_entity_id,
    note = v_note,
    updated_at = v_now
  where t.id = v_teacher.id;

  return query
  select
    t.id,
    t.teacher_code,
    t.name,
    t.display_name,
    t.status,
    t.default_business_entity_id,
    t.note,
    t.updated_at
  from public.school_teachers t
  where t.id = v_teacher.id;
end;
$$;

comment on function public.school_update_teacher_profile(
  uuid,
  text,
  text,
  uuid,
  text
) is
  'Updates only non-sensitive school teacher profile display fields: display_name, status, default_business_entity_id, and note.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
