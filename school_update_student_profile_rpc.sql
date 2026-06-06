-- school_update_student_profile_rpc.sql
-- RPC: public.school_update_student_profile
-- Purpose: Update non-sensitive student display profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.36.0-student-profile-update-full-autopilot-trial-20260607
-- Version: v2.36.0-student-profile-update-full-autopilot-trial-20260607
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updated only display_name/status/course_track/target_type/note and left no residue.
-- - Commit test used whitelisted codex-test student only.
-- - previous_balance_cny, phone, email, wechat, parent_name, birthday remained unchanged.
-- - lesson, settlement, income, and payment request counts for the test student remained unchanged.
-- - Empty display name, invalid course track, and invalid status were rejected.
--
-- Scope:
-- - Update one school student row.
-- - Allowed fields: display_name, status, course_track, target_type, note.
-- - Preserve previous_balance_cny, settlement fields, tuition rules, contact
--   details, parent details, birthday, lesson, income, settlement, and payment data.
--
-- Not supported:
-- - Editing name, student_code, phone, email, wechat, parent fields, birthday.
-- - Editing previous_balance_cny, settlement state, tuition rule fields, or balances.
-- - Creating, deleting, or merging students.
--
-- Review before execution:
-- - Confirm public.school_students has all allowed columns.
-- - Confirm status / course_track allowed values fit current product expectations.
-- - Confirm commit test uses whitelisted test student only.

create or replace function public.school_update_student_profile(
  p_student_id uuid,
  p_display_name text,
  p_status text,
  p_course_track text default null,
  p_target_type text default null,
  p_note text default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  status text,
  course_track text,
  target_type text,
  note text,
  previous_balance_cny numeric,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_student public.school_students%rowtype;
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_course_track text := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_type text := nullif(trim(coalesce(p_target_type, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_student_id is null then
    raise exception '请选择要编辑的学生。';
  end if;

  if v_display_name is null then
    raise exception '学生显示名称不能为空。';
  end if;

  if v_status is null then
    raise exception '学生状态不能为空。';
  end if;

  if v_status not in ('active', 'inactive', 'paused', 'graduated') then
    raise exception '学生状态无效：%。', v_status;
  end if;

  if v_course_track is not null
    and v_course_track not in ('science', 'humanities') then
    raise exception '课程方向无效：%。', v_course_track;
  end if;

  select *
  into v_student
  from public.school_students s
  where s.id = p_student_id
    and coalesce(s.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '学生不存在。';
  end if;

  update public.school_students s
  set
    display_name = v_display_name,
    status = v_status,
    course_track = v_course_track,
    target_type = v_target_type,
    note = v_note,
    updated_at = v_now
  where s.id = v_student.id;

  return query
  select
    s.id,
    s.student_code,
    s.name,
    s.display_name,
    s.status,
    s.course_track,
    s.target_type,
    s.note,
    s.previous_balance_cny,
    s.updated_at
  from public.school_students s
  where s.id = v_student.id;
end;
$$;

comment on function public.school_update_student_profile(
  uuid,
  text,
  text,
  text,
  text,
  text
) is
  'Updates only non-sensitive school student profile display fields: display_name, status, course_track, target_type, and note.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
