-- school_create_student_profile_rpc.sql
-- RPC: public.school_create_student_profile
-- Purpose: Create a narrowed future-use student profile for v2 student management.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.100.0-student-dialog-field-scope-20260612
--
-- Scope:
-- - Insert one row into public.school_students.
-- - Allowed user-maintained fields: name, business_entity_id, course_track,
--   preset_exchange_rate, wechat, phone, entrance_date, target_schools, note.
-- - Internal defaults: student_code null, display_name mirrors name,
--   status active, default_currency CNY, app_type school.
-- - Preserve existing table defaults for id, timestamps, previous_balance_cny,
--   and other historical/reserved columns.
--
-- Not supported:
-- - Editing student_code, display_name as a separate field, kana_name,
--   target_type, default_currency, status, gender, birthday, parent fields,
--   balance/carryover, settlement, tuition/billing, lesson, income, expense,
--   payment, wage, or account-transaction chains.
-- - Creating, deleting, merging, or replacing students.
--
-- Verification:
-- - Confirm public.school_students has all allowed columns.
-- - Rollback test created codex-test/v2-test/sandbox rows in one transaction
--   and left student/business residue 0.
-- - Commit/browser tests used clearly marked test student data only.

create or replace function public.school_create_student_profile(
  p_name text,
  p_default_business_entity_id uuid default null,
  p_course_track text default null,
  p_preset_exchange_rate numeric default 0,
  p_wechat text default null,
  p_phone text default null,
  p_entrance_date date default null,
  p_target_schools text default null,
  p_note text default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  status text,
  course_track text,
  target_schools text,
  business_entity_id uuid,
  default_currency text,
  preset_exchange_rate numeric,
  wechat text,
  phone text,
  entrance_date date,
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
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_course_track text := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_schools text := nullif(trim(coalesce(p_target_schools, '')), '');
  v_wechat text := nullif(trim(coalesce(p_wechat, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_preset_exchange_rate numeric := coalesce(p_preset_exchange_rate, 0);
  v_business_entity_id uuid;
  v_target_school_count integer := 0;
  v_student_id uuid;
begin
  if v_name is null then
    raise exception '学生姓名不能为空。';
  end if;

  if v_course_track is not null
    and v_course_track not in ('science', 'humanities') then
    raise exception '文理区分无效：%。', v_course_track;
  end if;

  if v_preset_exchange_rate < 0 then
    raise exception '预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*)
    into v_target_school_count
    from regexp_split_to_table(v_target_schools, E'\\r?\\n') as item
    where nullif(trim(item), '') is not null;

    if v_target_school_count > 3 then
      raise exception '目标学校最多填写 3 个。';
    end if;
  end if;

  v_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_default_business_entity_id, public.school_primary_business_entity_id()),
    '新增学生'
  );

  insert into public.school_students (
    name,
    display_name,
    status,
    course_track,
    target_schools,
    business_entity_id,
    default_currency,
    preset_exchange_rate,
    wechat,
    phone,
    entrance_date,
    note,
    app_type
  )
  values (
    v_name,
    v_name,
    'active',
    v_course_track,
    v_target_schools,
    v_business_entity_id,
    'CNY',
    v_preset_exchange_rate,
    v_wechat,
    v_phone,
    p_entrance_date,
    v_note,
    'school'
  )
  returning id into v_student_id;

  return query
  select
    s.id,
    s.student_code,
    s.name,
    s.display_name,
    s.status,
    s.course_track,
    s.target_schools,
    s.business_entity_id,
    s.default_currency,
    s.preset_exchange_rate,
    s.wechat,
    s.phone,
    s.entrance_date,
    s.note,
    s.previous_balance_cny,
    s.created_at,
    s.updated_at
  from public.school_students s
  where s.id = v_student_id;
end;
$$;

comment on function public.school_create_student_profile(
  text,
  uuid,
  text,
  numeric,
  text,
  text,
  date,
  text,
  text
) is
  'Creates one narrowed v2 student profile row. Only writes safe student master/contact fields and does not modify settlement, income, lesson, wage, payment, expense, or account data.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
