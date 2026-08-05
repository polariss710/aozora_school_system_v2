-- School V2 student-master P0 permission closure core, 2026-08-05.
-- Included byte-for-byte by rollback tests and the formal deployment wrapper.
-- This file changes ACL/RLS/function definitions only and never writes student rows.

do $preflight$
begin
  if to_regclass('public.school_students') is null
     or to_regclass('public.school_app_memberships') is null
     or to_regprocedure('public.school_get_current_app_membership()') is null
     or to_regprocedure('public.school_require_current_app_admin()') is null then
    raise exception 'STUDENT_P0_AUTHORITY_PREFLIGHT_FAILED';
  end if;

  if to_regprocedure(
    'public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)'
  ) is null
     or to_regprocedure(
       'public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text)'
     ) is null then
    raise exception 'STUDENT_P0_CANONICAL_WRITER_MISSING';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='school_create_student_profile'
  ) <> 3 then
    raise exception 'STUDENT_P0_CREATE_OVERLOAD_DRIFT';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='school_update_student_profile'
  ) not in (5,6) then
    raise exception 'STUDENT_P0_UPDATE_OVERLOAD_DRIFT';
  end if;
end;
$preflight$;

create or replace function public.school_create_student_profile(
  p_name text,
  p_default_business_entity_id uuid default null,
  p_course_track text default null,
  p_preset_exchange_rate numeric default 0,
  p_wechat text default null,
  p_phone text default null,
  p_entrance_date date default null,
  p_target_schools text default null,
  p_note text default null,
  p_status text default 'active'
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
  v_status text;
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

  v_name := nullif(trim(coalesce(p_name,'')),'');
  v_status := coalesce(nullif(trim(coalesce(p_status,'')),''),'active');
  v_course_track := nullif(trim(coalesce(p_course_track,'')),'');
  v_target_schools := nullif(trim(coalesce(p_target_schools,'')),'');
  v_wechat := nullif(trim(coalesce(p_wechat,'')),'');
  v_phone := nullif(trim(coalesce(p_phone,'')),'');
  v_note := nullif(trim(coalesce(p_note,'')),'');
  v_preset_exchange_rate := coalesce(p_preset_exchange_rate,0);

  if v_name is null then
    raise exception using errcode='22023',message='学生姓名不能为空。';
  end if;
  if v_status not in ('active','paused','graduated','withdrawn') then
    raise exception using errcode='22023',message='学生状态无效。';
  end if;
  if v_course_track is not null
     and v_course_track not in ('science','humanities') then
    raise exception using errcode='22023',message='文理区分无效。';
  end if;
  if v_preset_exchange_rate < 0 then
    raise exception using errcode='22023',message='预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*) into v_target_school_count
    from regexp_split_to_table(v_target_schools,E'\\r?\\n') item
    where nullif(trim(item),'') is not null;
    if v_target_school_count > 3 then
      raise exception using errcode='22023',message='目标学校最多填写 3 个。';
    end if;
  end if;

  v_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_default_business_entity_id,public.school_primary_business_entity_id()),
    '新增学生'
  );

  insert into public.school_students (
    name,display_name,status,course_track,target_schools,business_entity_id,
    default_currency,preset_exchange_rate,wechat,phone,entrance_date,note,app_type
  ) values (
    v_name,v_name,v_status,v_course_track,v_target_schools,v_business_entity_id,
    'CNY',v_preset_exchange_rate,v_wechat,v_phone,p_entrance_date,v_note,'school'
  ) returning id into v_student_id;

  return query
  select s.id,s.student_code,s.name,s.display_name,s.status,s.course_track,
         s.target_schools,s.business_entity_id,s.default_currency,
         s.preset_exchange_rate,s.wechat,s.phone,s.entrance_date,s.note,
         s.previous_balance_cny,s.created_at,s.updated_at
  from public.school_students s
  where s.id=v_student_id;
end;
$function$;

create or replace function public.school_update_student_profile(
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
  p_status text default null,
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
  v_status text;
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
    raise exception using errcode='22023',message='请选择学生并提供最新版本。';
  end if;

  v_name := nullif(trim(coalesce(p_name,'')),'');
  v_course_track := nullif(trim(coalesce(p_course_track,'')),'');
  v_target_schools := nullif(trim(coalesce(p_target_schools,'')),'');
  v_wechat := nullif(trim(coalesce(p_wechat,'')),'');
  v_phone := nullif(trim(coalesce(p_phone,'')),'');
  v_note := nullif(trim(coalesce(p_note,'')),'');
  v_preset_exchange_rate := coalesce(p_preset_exchange_rate,0);

  if v_name is null then
    raise exception using errcode='22023',message='学生姓名不能为空。';
  end if;
  if v_course_track is not null
     and v_course_track not in ('science','humanities') then
    raise exception using errcode='22023',message='文理区分无效。';
  end if;
  if v_preset_exchange_rate < 0 then
    raise exception using errcode='22023',message='预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*) into v_target_school_count
    from regexp_split_to_table(v_target_schools,E'\\r?\\n') item
    where nullif(trim(item),'') is not null;
    if v_target_school_count > 3 then
      raise exception using errcode='22023',message='目标学校最多填写 3 个。';
    end if;
  end if;

  select * into v_student
  from public.school_students s
  where s.id=p_student_id
    and s.app_type='school'
  for update;

  if not found then
    raise exception using errcode='P0002',message='学生不存在。';
  end if;
  if v_student.updated_at is distinct from p_expected_updated_at then
    raise exception using
      errcode='40001',
      message='学生资料已被其他操作更新，请刷新后重试。';
  end if;

  v_status := coalesce(nullif(trim(coalesce(p_status,'')),''),v_student.status,'active');
  if v_status not in ('active','paused','graduated','withdrawn') then
    raise exception using errcode='22023',message='学生状态无效。';
  end if;

  if p_default_business_entity_id is not null
     and not exists (
       select 1 from public.school_business_entities b
       where b.id=p_default_business_entity_id
         and coalesce(b.is_active,true)
     ) then
    raise exception using errcode='22023',message='默认业务归属不存在或已停用。';
  end if;

  if p_default_business_entity_id is distinct from v_student.business_entity_id then
    v_business_entity_id := public.school_assert_new_business_entity_allowed(
      p_default_business_entity_id,'更新学生默认业务归属'
    );
  else
    v_business_entity_id := p_default_business_entity_id;
  end if;

  update public.school_students s
  set name=v_name,
      display_name=v_name,
      status=v_status,
      course_track=v_course_track,
      target_schools=v_target_schools,
      business_entity_id=v_business_entity_id,
      preset_exchange_rate=v_preset_exchange_rate,
      wechat=v_wechat,
      phone=v_phone,
      entrance_date=p_entrance_date,
      note=v_note
  where s.id=v_student.id;

  return query
  select s.id,s.student_code,s.name,s.display_name,s.status,s.course_track,
         s.target_schools,s.business_entity_id,s.default_currency,
         s.preset_exchange_rate,s.wechat,s.phone,s.entrance_date,s.note,
         s.previous_balance_cny,s.updated_at
  from public.school_students s
  where s.id=v_student.id;
end;
$function$;

alter table public.school_students enable row level security;

drop policy if exists school_allow_all_students on public.school_students;
drop policy if exists school_students_active_membership_select on public.school_students;
create policy school_students_active_membership_select
  on public.school_students
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.school_get_current_app_membership() membership
      where membership.is_active
        and membership.role in ('admin','operator','read_only')
    )
  );

revoke all privileges on table public.school_students
  from public,anon,authenticated,service_role;
grant select on table public.school_students to authenticated,service_role;

revoke all on function public.school_create_student_profile(text,text,text,text,text,text,text,text,uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)
  to authenticated;

revoke all on function public.school_update_student_profile(uuid,text,text,text,text,text,text,text,uuid,text,numeric,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_student_profile(uuid,text,text,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_student_profile(uuid,text,text,text,text,uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)
  to authenticated;

alter default privileges for role postgres in schema public
  revoke all privileges on tables from public,anon,authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from public,anon,authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on functions from public,anon,authenticated;

comment on function public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text) is
  'Interactive student-profile create writer. Authenticated callers must be current active admins; direct service-role use is denied.';
comment on function public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz) is
  'Interactive student-profile update writer. Requires current active admin, row lock, and exact expected updated_at; direct service-role use is denied.';
comment on policy school_students_active_membership_select on public.school_students is
  'Student master rows are readable only by authenticated users with a current active admin, operator, or read_only membership.';
