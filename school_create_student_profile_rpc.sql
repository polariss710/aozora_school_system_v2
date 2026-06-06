-- school_create_student_profile_rpc.sql
-- RPC: public.school_create_student_profile
-- Purpose: Create future-use student master data only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.45.0-teacher-student-create-full-autopilot-20260606
--
-- Scope:
-- - Insert one row into public.school_students.
-- - Allowed fields: student_code, name, kana_name, display_name, status,
--   course_track, target_type, target_schools, business_entity_id,
--   default_currency, note, app_type.
-- - Use existing table defaults for balances, exchange rate, contact/parent
--   fields, birthday, timestamps, and id.
--
-- Not supported:
-- - Deleting, merging, or replacing students.
-- - Creating or editing monthly settlements, carryovers, income records,
--   lesson records, wage data, or account transactions.
-- - Editing contact, parent, birthday, tuition rule, balance, or settlement
--   fields.
-- - Recalculating historical data.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - public.school_students.student_code has unique constraint
--   school_students_student_code_key.
-- - Rollback test inserted one codex-test student and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox student
--   d2dcd249-5d01-4857-b12d-293e6a2fa092.
-- - Duplicate student code is rejected.
-- - Monthly settlement, carryover, income, lesson, wage, and account
--   transaction counts stayed unchanged.

create or replace function public.school_create_student_profile(
  p_display_name text,
  p_student_code text default null,
  p_name text default null,
  p_kana_name text default null,
  p_status text default 'active',
  p_course_track text default null,
  p_target_type text default null,
  p_target_schools text default null,
  p_default_business_entity_id uuid default null,
  p_default_currency text default 'CNY',
  p_note text default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  kana_name text,
  display_name text,
  status text,
  course_track text,
  target_type text,
  target_schools text,
  business_entity_id uuid,
  default_currency text,
  note text,
  previous_balance_cny numeric,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_student_code text := nullif(trim(coalesce(p_student_code, '')), '');
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_kana_name text := nullif(trim(coalesce(p_kana_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, 'active')), '');
  v_course_track text := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_type text := nullif(trim(coalesce(p_target_type, '')), '');
  v_target_schools text := nullif(trim(coalesce(p_target_schools, '')), '');
  v_default_currency text := upper(nullif(trim(coalesce(p_default_currency, 'CNY')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_student_id uuid;
begin
  if v_display_name is null then
    raise exception '学生显示名称不能为空。';
  end if;

  v_name := coalesce(v_name, v_display_name);

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

  if v_default_currency is null then
    raise exception '默认币种不能为空。';
  end if;

  if v_default_currency not in ('JPY', 'CNY') then
    raise exception '默认币种无效：%。', v_default_currency;
  end if;

  if p_default_business_entity_id is not null
    and not exists (
      select 1
      from public.school_business_entities b
      where b.id = p_default_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
    raise exception '默认业务归属不存在或已停用。';
  end if;

  if v_student_code is not null and exists (
    select 1
    from public.school_students s
    where s.student_code = v_student_code
  ) then
    raise exception '学生编号已存在：%。', v_student_code;
  end if;

  insert into public.school_students (
    student_code,
    name,
    kana_name,
    display_name,
    status,
    course_track,
    target_type,
    target_schools,
    business_entity_id,
    default_currency,
    note,
    app_type
  )
  values (
    v_student_code,
    v_name,
    v_kana_name,
    v_display_name,
    v_status,
    v_course_track,
    v_target_type,
    v_target_schools,
    p_default_business_entity_id,
    v_default_currency,
    v_note,
    'school'
  )
  returning id into v_student_id;

  return query
  select
    s.id,
    s.student_code,
    s.name,
    s.kana_name,
    s.display_name,
    s.status,
    s.course_track,
    s.target_type,
    s.target_schools,
    s.business_entity_id,
    s.default_currency,
    s.note,
    s.previous_balance_cny,
    s.created_at,
    s.updated_at
  from public.school_students s
  where s.id = v_student_id;
exception
  when unique_violation then
    raise exception '学生编号已存在：%。', v_student_code;
end;
$$;

comment on function public.school_create_student_profile(
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text
) is
  'Creates one future-use school student master row. Does not modify monthly settlements, carryovers, income records, lesson records, wage data, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
