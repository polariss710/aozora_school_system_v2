-- school_update_subject_profile_rpc.sql
-- RPC: public.school_update_subject_profile
-- Purpose: Update non-sensitive subject display profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.38.0-subject-profile-update-full-autopilot-trial-20260607
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updates only name/is_active/note and leaves no residue.
-- - Commit test uses whitelisted codex-test subject only.
-- - Lesson, wage, settlement, payment, and historical records remain unchanged.
-- - Empty name, duplicate name, and invalid status are rejected.
--
-- Scope:
-- - Update one school subject row.
-- - Allowed fields: name, is_active via status, note.
-- - Preserve category, color, sort_order, primary_category, tertiary_category,
--   lesson data, wage data, settlement data, and payment data.
--
-- Not supported:
-- - Editing category/color/sort_order/classification fields.
-- - Deleting or merging subjects.
-- - Editing historical lesson, wage, settlement, or payment records.
--
-- Review before execution:
-- - Confirm public.school_subjects has the allowed columns.
-- - Confirm the current product maps subject status to is_active.
-- - Confirm commit test uses whitelisted test subject only.

create or replace function public.school_update_subject_profile(
  p_subject_id uuid,
  p_name text,
  p_status text,
  p_note text default null
)
returns table (
  subject_id uuid,
  name text,
  status text,
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
  v_subject public.school_subjects%rowtype;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_is_active boolean;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_subject_id is null then
    raise exception '请选择要编辑的科目。';
  end if;

  if v_name is null then
    raise exception '科目名称不能为空。';
  end if;

  if v_status is null then
    raise exception '科目状态不能为空。';
  end if;

  if v_status not in ('active', 'inactive') then
    raise exception '科目状态无效：%。', v_status;
  end if;

  v_is_active := v_status = 'active';

  select *
  into v_subject
  from public.school_subjects s
  where s.id = p_subject_id
  for update;

  if not found then
    raise exception '科目不存在。';
  end if;

  if exists (
    select 1
    from public.school_subjects s
    where s.name = v_name
      and s.id <> v_subject.id
  ) then
    raise exception '科目名称已存在：%。', v_name;
  end if;

  update public.school_subjects s
  set
    name = v_name,
    is_active = v_is_active,
    note = v_note,
    updated_at = v_now
  where s.id = v_subject.id;

  return query
  select
    s.id,
    s.name,
    case when s.is_active then 'active' else 'inactive' end,
    s.is_active,
    s.note,
    s.updated_at
  from public.school_subjects s
  where s.id = v_subject.id;
end;
$$;

comment on function public.school_update_subject_profile(
  uuid,
  text,
  text,
  text
) is
  'Updates only non-sensitive school subject profile display fields: name, status/is_active, and note.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
