-- school_create_teacher_profile_rpc.sql
-- RPC: public.school_create_teacher_profile
-- Purpose: Create future-use teacher master data only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.45.0-teacher-student-create-full-autopilot-20260606
--
-- Scope:
-- - Insert one row into public.school_teachers.
-- - Allowed fields: teacher_code, name, kana_name, display_name, department,
--   status, default_business_entity_id, note, app_type.
-- - Use existing table defaults for rates, currencies, payment method, subject,
--   bank/contact fields, timestamps, and id.
--
-- Not supported:
-- - Deleting, merging, or replacing teachers.
-- - Creating or editing wage rules, wage locks, payment requests, expenses, or
--   account transactions.
-- - Editing sensitive/contact/payment fields.
-- - Recalculating historical data.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - public.school_teachers.teacher_code has unique constraint
--   school_teachers_teacher_code_key.
-- - Rollback test inserted one codex-test teacher and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox teacher
--   efeafbbe-6d89-4f46-9d48-2970d2ec5a2f.
-- - Duplicate teacher code is rejected.
-- - Wage rule, wage lock, payment request, expense, and account transaction
--   counts stayed unchanged.

create or replace function public.school_create_teacher_profile(
  p_display_name text,
  p_teacher_code text default null,
  p_name text default null,
  p_kana_name text default null,
  p_status text default 'employed',
  p_department text default null,
  p_default_business_entity_id uuid default null,
  p_note text default null
)
returns table (
  teacher_id uuid,
  teacher_code text,
  name text,
  kana_name text,
  display_name text,
  department text,
  status text,
  default_business_entity_id uuid,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_teacher_code text := nullif(trim(coalesce(p_teacher_code, '')), '');
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_kana_name text := nullif(trim(coalesce(p_kana_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, 'employed')), '');
  v_department text := nullif(trim(coalesce(p_department, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_teacher_id uuid;
begin
  if v_display_name is null then
    raise exception '老师显示名称不能为空。';
  end if;

  v_name := coalesce(v_name, v_display_name);

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

  if v_teacher_code is not null and exists (
    select 1
    from public.school_teachers t
    where t.teacher_code = v_teacher_code
  ) then
    raise exception '老师编号已存在：%。', v_teacher_code;
  end if;

  insert into public.school_teachers (
    teacher_code,
    name,
    kana_name,
    display_name,
    department,
    status,
    default_business_entity_id,
    note,
    app_type
  )
  values (
    v_teacher_code,
    v_name,
    v_kana_name,
    v_display_name,
    v_department,
    v_status,
    p_default_business_entity_id,
    v_note,
    'school'
  )
  returning id into v_teacher_id;

  return query
  select
    t.id,
    t.teacher_code,
    t.name,
    t.kana_name,
    t.display_name,
    t.department,
    t.status,
    t.default_business_entity_id,
    t.note,
    t.created_at,
    t.updated_at
  from public.school_teachers t
  where t.id = v_teacher_id;
exception
  when unique_violation then
    raise exception '老师编号已存在：%。', v_teacher_code;
end;
$$;

comment on function public.school_create_teacher_profile(
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text
) is
  'Creates one future-use school teacher master row. Does not modify wage rules, wage locks, payment requests, expenses, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
