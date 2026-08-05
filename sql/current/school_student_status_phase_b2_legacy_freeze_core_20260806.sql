-- School V2 student monthly status Phase B2 core, 2026-08-06.
-- Freezes school_students.status, installs status-free profile writers, and
-- temporarily removes all client EXECUTE rights from Phase A event writers.
-- This file changes function/trigger/ACL/comment definitions only.

do $preflight$
begin
  if to_regclass('public.school_students') is null
     or to_regclass('public.school_student_status_events') is null
     or to_regprocedure('public.school_require_current_app_admin()') is null then
    raise exception 'STUDENT_STATUS_B2_AUTHORITY_PREFLIGHT_FAILED';
  end if;

  if to_regprocedure(
       'public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text)'
     ) is null
     or to_regprocedure(
       'public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)'
     ) is null
     or to_regprocedure(
       'public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)'
     ) is null
     or to_regprocedure(
       'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'
     ) is null
     or to_regprocedure(
       'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'
     ) is null then
    raise exception 'STUDENT_STATUS_B2_REQUIRED_WRITER_MISSING';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'school_create_student_profile'
  ) <> 3 then
    raise exception 'STUDENT_STATUS_B2_CREATE_OVERLOAD_DRIFT';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'school_update_student_profile'
  ) not in (6, 7) then
    raise exception 'STUDENT_STATUS_B2_UPDATE_OVERLOAD_DRIFT';
  end if;

  if exists (
    select 1
    from public.school_students s
    where s.status not in ('active', 'paused')
  ) then
    raise exception 'STUDENT_STATUS_B2_UNEXPECTED_LEGACY_STATUS_BASELINE';
  end if;
end;
$preflight$;

create or replace function public.school_guard_legacy_student_status_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'active' then
      raise exception using
        errcode = '23514',
        message = 'STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE';
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    raise exception using
      errcode = '23514',
      message = 'STUDENT_LEGACY_STATUS_IMMUTABLE';
  end if;

  return new;
end;
$function$;

drop trigger if exists school_students_legacy_status_immutable_guard
  on public.school_students;
create trigger school_students_legacy_status_immutable_guard
before insert or update on public.school_students
for each row execute function public.school_guard_legacy_student_status_immutable_v1();

revoke all on function public.school_guard_legacy_student_status_immutable_v1()
  from public, anon, authenticated, service_role;

comment on function public.school_guard_legacy_student_status_immutable_v1() is
  'Phase B2 owner-only trigger guard. New rows must use the exact legacy snapshot active; existing school_students.status values are immutable.';
comment on column public.school_students.status is
  'Frozen legacy snapshot since student-status Phase B2. New rows are active; month-effective operational status is resolved only from school_student_status_events with its approved active fallback.';

create or replace function public.school_create_student_profile_v2(
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
set search_path = pg_catalog, public
as $function$
declare
  v_name text;
  v_course_track text;
  v_target_schools text;
  v_wechat text;
  v_phone text;
  v_note text;
  v_preset_exchange_rate numeric;
  v_business_entity_id uuid;
  v_target_school_count integer := 0;
  v_student_id uuid;
begin
  perform public.school_require_current_app_admin();

  v_name := nullif(trim(coalesce(p_name, '')), '');
  v_course_track := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_schools := nullif(trim(coalesce(p_target_schools, '')), '');
  v_wechat := nullif(trim(coalesce(p_wechat, '')), '');
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');
  v_preset_exchange_rate := coalesce(p_preset_exchange_rate, 0);

  if v_name is null then
    raise exception using errcode = '22023', message = '学生姓名不能为空。';
  end if;
  if v_course_track is not null
     and v_course_track not in ('science', 'humanities') then
    raise exception using errcode = '22023', message = '文理区分无效。';
  end if;
  if v_preset_exchange_rate < 0 then
    raise exception using errcode = '22023', message = '预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*) into v_target_school_count
    from regexp_split_to_table(v_target_schools, E'\\r?\\n') item
    where nullif(trim(item), '') is not null;
    if v_target_school_count > 3 then
      raise exception using errcode = '22023', message = '目标学校最多填写 3 个。';
    end if;
  end if;

  v_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_default_business_entity_id, public.school_primary_business_entity_id()),
    '新增学生'
  );

  insert into public.school_students (
    name, display_name, status, course_track, target_schools, business_entity_id,
    default_currency, preset_exchange_rate, wechat, phone, entrance_date, note,
    app_type
  ) values (
    v_name, v_name, 'active', v_course_track, v_target_schools,
    v_business_entity_id, 'CNY', v_preset_exchange_rate, v_wechat, v_phone,
    p_entrance_date, v_note, 'school'
  ) returning id into v_student_id;

  return query
  select s.id, s.student_code, s.name, s.display_name, s.status,
         s.course_track, s.target_schools, s.business_entity_id,
         s.default_currency, s.preset_exchange_rate, s.wechat, s.phone,
         s.entrance_date, s.note, s.previous_balance_cny, s.created_at,
         s.updated_at
  from public.school_students s
  where s.id = v_student_id;
end;
$function$;

create or replace function public.school_update_student_profile_v2(
  p_student_id uuid,
  p_name text,
  p_default_business_entity_id uuid default null,
  p_course_track text default null,
  p_preset_exchange_rate numeric default 0,
  p_wechat text default null,
  p_phone text default null,
  p_entrance_date date default null,
  p_target_schools text default null,
  p_note text default null,
  p_expected_updated_at timestamptz default null
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
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_student public.school_students%rowtype;
  v_name text;
  v_course_track text;
  v_target_schools text;
  v_wechat text;
  v_phone text;
  v_note text;
  v_preset_exchange_rate numeric;
  v_business_entity_id uuid;
  v_target_school_count integer := 0;
begin
  perform public.school_require_current_app_admin();

  if p_student_id is null or p_expected_updated_at is null then
    raise exception using errcode = '22023', message = '请选择学生并提供最新版本。';
  end if;

  v_name := nullif(trim(coalesce(p_name, '')), '');
  v_course_track := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_schools := nullif(trim(coalesce(p_target_schools, '')), '');
  v_wechat := nullif(trim(coalesce(p_wechat, '')), '');
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');
  v_preset_exchange_rate := coalesce(p_preset_exchange_rate, 0);

  if v_name is null then
    raise exception using errcode = '22023', message = '学生姓名不能为空。';
  end if;
  if v_course_track is not null
     and v_course_track not in ('science', 'humanities') then
    raise exception using errcode = '22023', message = '文理区分无效。';
  end if;
  if v_preset_exchange_rate < 0 then
    raise exception using errcode = '22023', message = '预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*) into v_target_school_count
    from regexp_split_to_table(v_target_schools, E'\\r?\\n') item
    where nullif(trim(item), '') is not null;
    if v_target_school_count > 3 then
      raise exception using errcode = '22023', message = '目标学校最多填写 3 个。';
    end if;
  end if;

  select * into v_student
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '学生不存在。';
  end if;
  if v_student.updated_at is distinct from p_expected_updated_at then
    raise exception using
      errcode = '40001',
      message = '学生资料已被其他操作更新，请刷新后重试。';
  end if;

  if p_default_business_entity_id is not null
     and not exists (
       select 1
       from public.school_business_entities b
       where b.id = p_default_business_entity_id
         and coalesce(b.is_active, true)
     ) then
    raise exception using errcode = '22023', message = '默认业务归属不存在或已停用。';
  end if;

  if p_default_business_entity_id is distinct from v_student.business_entity_id then
    v_business_entity_id := public.school_assert_new_business_entity_allowed(
      p_default_business_entity_id,
      '更新学生默认业务归属'
    );
  else
    v_business_entity_id := p_default_business_entity_id;
  end if;

  update public.school_students s
  set name = v_name,
      display_name = v_name,
      course_track = v_course_track,
      target_schools = v_target_schools,
      business_entity_id = v_business_entity_id,
      preset_exchange_rate = v_preset_exchange_rate,
      wechat = v_wechat,
      phone = v_phone,
      entrance_date = p_entrance_date,
      note = v_note
  where s.id = v_student.id;

  return query
  select s.id, s.student_code, s.name, s.display_name, s.status,
         s.course_track, s.target_schools, s.business_entity_id,
         s.default_currency, s.preset_exchange_rate, s.wechat, s.phone,
         s.entrance_date, s.note, s.previous_balance_cny, s.updated_at
  from public.school_students s
  where s.id = v_student.id;
end;
$function$;

revoke all on function public.school_create_student_profile(text,text,text,text,text,text,text,text,uuid,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_create_student_profile_v2(text,uuid,text,numeric,text,text,date,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_create_student_profile_v2(text,uuid,text,numeric,text,text,date,text,text)
  to authenticated;

revoke all on function public.school_update_student_profile(uuid,text,text,text,text,text,text,text,uuid,text,numeric,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile(uuid,text,text,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile(uuid,text,text,text,text,uuid,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.school_update_student_profile_v2(uuid,text,uuid,text,numeric,text,text,date,text,text,timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.school_update_student_profile_v2(uuid,text,uuid,text,numeric,text,text,date,text,text,timestamptz)
  to authenticated;

revoke all on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)
  from public, anon, authenticated, service_role;

comment on function public.school_create_student_profile_v2(text,uuid,text,numeric,text,text,date,text,text) is
  'Phase B2 canonical active-admin profile create. The client cannot pass status; DB writes exact legacy active and creates no status event.';
comment on function public.school_update_student_profile_v2(uuid,text,uuid,text,numeric,text,text,date,text,text,timestamptz) is
  'Phase B2 canonical active-admin ordinary-profile update. Requires row lock and exact expected updated_at; legacy status is never accepted or changed.';
comment on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text) is
  'Phase B2 temporarily frozen owner-only event append writer. B5 may restore EXECUTE to authenticated only after B3/B4 acceptance; PUBLIC, anon and service_role remain denied.';
comment on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text) is
  'Phase B2 temporarily frozen owner-only event correction writer. B5 may restore EXECUTE to authenticated only after B3/B4 acceptance; PUBLIC, anon and service_role remain denied.';

notify pgrst, 'reload schema';
