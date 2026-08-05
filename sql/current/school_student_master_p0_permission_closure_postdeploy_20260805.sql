-- School V2 student-master P0 permission closure read-only postdeploy.
\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare
  v_oid oid;
  v_def text;
begin
  if has_table_privilege('anon','public.school_students','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('authenticated','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role','public.school_students','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated','public.school_students','SELECT')
     or not has_table_privilege('service_role','public.school_students','SELECT') then
    raise exception 'STUDENT_P0_POSTDEPLOY_TABLE_ACL_INVALID';
  end if;

  if (select count(*) from pg_policies
      where schemaname='public' and tablename='school_students')<>1
     or not exists (
       select 1 from pg_policies
       where schemaname='public' and tablename='school_students'
         and policyname='school_students_active_membership_select'
         and cmd='SELECT' and roles='{authenticated}'
         and qual ilike '%school_get_current_app_membership%'
     ) then
    raise exception 'STUDENT_P0_POSTDEPLOY_RLS_INVALID';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_create_student_profile')<>3
     or (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_update_student_profile')<>6 then
    raise exception 'STUDENT_P0_POSTDEPLOY_OVERLOAD_COUNT_INVALID';
  end if;

  for v_oid in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('school_create_student_profile','school_update_student_profile')
  loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STUDENT_P0_POSTDEPLOY_CLIENT_EXECUTE_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  foreach v_oid in array array[
    'public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)'::regprocedure::oid,
    'public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)'::regprocedure::oid
  ] loop
    select lower(pg_get_functiondef(p.oid)) into strict v_def from pg_proc p where p.oid=v_oid;
    if not (select p.prosecdef and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
            from pg_proc p where p.oid=v_oid)
       or position('school_require_current_app_admin' in v_def)=0
       or not has_function_privilege('authenticated',v_oid,'EXECUTE') then
      raise exception 'STUDENT_P0_POSTDEPLOY_CANONICAL_WRITER_INVALID:%',v_oid::regprocedure;
    end if;
  end loop;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('school_create_student_profile','school_update_student_profile')
      and p.oid not in (
        'public.school_create_student_profile(text,uuid,text,numeric,text,text,date,text,text,text)'::regprocedure,
        'public.school_update_student_profile(uuid,text,uuid,text,numeric,text,text,date,text,text,text,timestamptz)'::regprocedure
      )
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) then
    raise exception 'STUDENT_P0_POSTDEPLOY_LEGACY_OVERLOAD_EXPOSED';
  end if;

  if exists (
    select 1 from information_schema.views
    where table_schema='public' and view_definition ilike '%school_students%'
      and (is_updatable='YES' or is_insertable_into='YES')
  ) then
    raise exception 'STUDENT_P0_POSTDEPLOY_WRITABLE_VIEW_FOUND';
  end if;

  if pg_get_serial_sequence('public.school_students','id') is not null then
    raise exception 'STUDENT_P0_POSTDEPLOY_UNEXPECTED_SEQUENCE';
  end if;

  if (select count(*) from public.school_students)<>8
     or (select count(*) from public.school_students where status='active')<>7
     or (select count(*) from public.school_students where status='paused')<>1
     or (select md5(coalesce(string_agg(to_jsonb(s)::text,'|' order by s.id),'')) from public.school_students s)
        <>'431ae7f350902dde0642ddc4982054ed' then
    raise exception 'STUDENT_P0_POSTDEPLOY_STUDENT_FINGERPRINT_CHANGED';
  end if;

  if exists (
    select 1 from public.school_students
    where id::text like 'a0500000-%'
       or coalesce(note,'') ilike '%student-p0%'
  ) or exists (
    select 1 from auth.users where id::text like 'a0500000-%'
  ) then
    raise exception 'STUDENT_P0_POSTDEPLOY_FIXTURE_RESIDUE';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure::text signature,
       pg_get_userbyid(p.proowner) owner,p.prosecdef,p.proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('school_create_student_profile','school_update_student_profile')
order by signature;

select md5(string_agg(concat_ws('|',coalesce(grantee,''),privilege_type),',' order by grantee,privilege_type)) acl_md5
from information_schema.role_table_grants
where table_schema='public' and table_name='school_students';

select 'STUDENT_P0_PERMISSION_CLOSURE_POSTDEPLOY_PASS' result;
