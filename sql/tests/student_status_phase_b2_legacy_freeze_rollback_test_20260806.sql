-- School V2 student status Phase B2 rollback-only role and mutation matrix.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir ../current/school_student_status_phase_b2_legacy_freeze_core_20260806.sql

insert into auth.users (id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('b2010000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-b2-operator"}'::jsonb,now(),now()),
  ('b2010000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-b2-read-only"}'::jsonb,now(),now()),
  ('b2010000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-b2-inactive-admin"}'::jsonb,now(),now()),
  ('b2010000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-b2-active-admin"}'::jsonb,now(),now()),
  ('b2010000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"student-b2-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('b2010000-0000-4000-8000-000000000001','operator',true,'b2010000-0000-4000-8000-000000000004','b2010000-0000-4000-8000-000000000004','codex-test student-b2 operator'),
  ('b2010000-0000-4000-8000-000000000002','read_only',true,'b2010000-0000-4000-8000-000000000004','b2010000-0000-4000-8000-000000000004','codex-test student-b2 read-only'),
  ('b2010000-0000-4000-8000-000000000003','admin',false,'b2010000-0000-4000-8000-000000000004','b2010000-0000-4000-8000-000000000004','codex-test student-b2 inactive admin'),
  ('b2010000-0000-4000-8000-000000000004','admin',true,'b2010000-0000-4000-8000-000000000004','b2010000-0000-4000-8000-000000000004','codex-test student-b2 active admin');

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values (
  'b2020000-0000-4000-8000-000000000100','CODEX-STUDENT-B2-FIXTURE',
  'codex-test student-b2 fixture','codex-test student-b2 fixture','active',
  public.school_primary_business_entity_id(),'CNY',0,
  'codex-test student-b2 rollback-only','school',now()-interval '1 day',now()-interval '1 day'
);

set local role anon;
do $anon_matrix$
declare v_denied boolean := false;
begin
  begin
    perform * from public.school_create_student_profile_v2(
      'codex-test anon denied',null,null,0,null,null,null,null,null
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_ANON_CREATE_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_resolve_student_status_at_month_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01'
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_ANON_READER_ALLOWED'; end if;
end;
$anon_matrix$;
reset role;

set local role authenticated;
do $authenticated_matrix$
declare
  v_actor uuid;
  v_denied boolean;
  v_created record;
  v_updated record;
  v_original_updated_at timestamptz;
  v_resolved record;
begin
  foreach v_actor in array array[
    'b2010000-0000-4000-8000-000000000005'::uuid,
    'b2010000-0000-4000-8000-000000000003'::uuid,
    'b2010000-0000-4000-8000-000000000001'::uuid,
    'b2010000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied := false;
    begin
      perform * from public.school_create_student_profile_v2(
        'codex-test student-b2 denied',null,null,0,null,null,null,null,null
      );
    exception when insufficient_privilege then
      if sqlerrm = 'P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied := true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_STATUS_B2_NON_ADMIN_CREATE_ALLOWED:%',v_actor; end if;

    v_denied := false;
    begin
      perform * from public.school_update_student_profile_v2(
        'b2020000-0000-4000-8000-000000000100','codex-test student-b2 denied',
        public.school_primary_business_entity_id(),null,0,null,null,null,null,null,now()
      );
    exception when insufficient_privilege then
      if sqlerrm = 'P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied := true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_STATUS_B2_NON_ADMIN_UPDATE_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'b2010000-0000-4000-8000-000000000005'::uuid,
    'b2010000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied := false;
    begin
      perform * from public.school_resolve_student_status_at_month_v1(
        'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01'
      );
    exception when insufficient_privilege then
      if sqlerrm = 'STUDENT_STATUS_ACTIVE_MEMBERSHIP_REQUIRED' then v_denied := true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_STATUS_B2_INELIGIBLE_READER_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'b2010000-0000-4000-8000-000000000004'::uuid,
    'b2010000-0000-4000-8000-000000000001'::uuid,
    'b2010000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    select * into strict v_resolved
    from public.school_resolve_student_status_at_month_v1(
      'cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01'
    );
    if v_resolved.resolved_status <> 'paused' then
      raise exception 'STUDENT_STATUS_B2_MEMBER_READER_INVALID:%',v_actor;
    end if;
  end loop;

  v_actor := 'b2010000-0000-4000-8000-000000000004'::uuid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);

  select * into strict v_created
  from public.school_create_student_profile_v2(
    'codex-test student-b2 created',public.school_primary_business_entity_id(),
    'science',0,null,null,current_date,null,'codex-test rollback-only'
  );
  if v_created.status <> 'active' then raise exception 'STUDENT_STATUS_B2_CREATE_NOT_ACTIVE'; end if;

  select * into strict v_resolved
  from public.school_resolve_student_status_at_month_v1(
    v_created.student_id,date_trunc('month',current_date)::date
  );
  if v_resolved.resolved_status <> 'active'
     or not v_resolved.is_legacy_fallback
     or v_resolved.source_event_id is not null then
    raise exception 'STUDENT_STATUS_B2_CREATE_RESOLVER_NOT_FALLBACK_ACTIVE';
  end if;

  select updated_at into strict v_original_updated_at
  from public.school_students
  where id = 'b2020000-0000-4000-8000-000000000100';

  select * into strict v_updated
  from public.school_update_student_profile_v2(
    'b2020000-0000-4000-8000-000000000100','codex-test student-b2 updated',
    public.school_primary_business_entity_id(),'humanities',0,null,null,current_date,
    null,'codex-test student-b2 rollback-updated',v_original_updated_at
  );
  if v_updated.status <> 'active' or v_updated.name <> 'codex-test student-b2 updated' then
    raise exception 'STUDENT_STATUS_B2_ORDINARY_UPDATE_INVALID';
  end if;

  v_denied := false;
  begin
    perform * from public.school_update_student_profile_v2(
      'b2020000-0000-4000-8000-000000000100','codex-test stale rejected',
      public.school_primary_business_entity_id(),'humanities',0,null,null,current_date,
      null,'codex-test stale rejected',v_original_updated_at
    );
  exception when serialization_failure then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_STALE_UPDATE_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_create_student_profile(
      'codex-test old create denied',public.school_primary_business_entity_id(),
      null,0,null,null,null,null,'codex-test rollback-only','paused'
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_OLD_CREATE_AUTH_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_update_student_profile(
      'b2020000-0000-4000-8000-000000000100','codex-test old update denied',
      public.school_primary_business_entity_id(),null,0,null,null,null,null,null,
      'paused',v_updated.updated_at
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_OLD_UPDATE_AUTH_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_record_student_status_event_v1(
      'b2020000-0000-4000-8000-000000000100',date_trunc('month',current_date)::date,
      'paused','codex-test frozen event',null,'RECORD_STUDENT_STATUS_EVENT_V1'
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_EVENT_RECORD_AUTH_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_correct_student_status_event_v1(
      '4190bddf-d995-4e6a-af6b-85997e6f999b',
      '70debcb4-6caf-42dd-ba99-b10a83ecb68d','2026-07-01','paused',
      'codex-test frozen correction','codex-test frozen correction',
      'CORRECT_STUDENT_STATUS_EVENT_V1'
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_EVENT_CORRECT_AUTH_ALLOWED'; end if;
end;
$authenticated_matrix$;
reset role;

set local role service_role;
do $service_matrix$
declare v_denied boolean;
begin
  v_denied := false;
  begin
    insert into public.school_students (name,display_name,status,app_type)
    values ('codex-test service insert','codex-test service insert','active','school');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_SERVICE_INSERT_ALLOWED'; end if;

  v_denied := false;
  begin
    update public.school_students set status = 'paused'
    where id = 'b2020000-0000-4000-8000-000000000100';
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_SERVICE_UPDATE_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_create_student_profile_v2(
      'codex-test service denied',null,null,0,null,null,null,null,null
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_SERVICE_CREATE_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_record_student_status_event_v1(
      'b2020000-0000-4000-8000-000000000100',date_trunc('month',current_date)::date,
      'paused','codex-test service event',null,'RECORD_STUDENT_STATUS_EVENT_V1'
    );
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_SERVICE_EVENT_ALLOWED'; end if;
end;
$service_matrix$;
reset role;

do $owner_guard_matrix$
declare
  v_denied boolean;
  v_status text;
  v_updated_at timestamptz;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub','b2010000-0000-4000-8000-000000000004'::uuid,'role','authenticated')::text,
    true
  );

  update public.school_students set note = note
  where id = 'b2020000-0000-4000-8000-000000000100';

  foreach v_status in array array['paused','left','inactive','graduated','withdrawn','ACTIVE'] loop
    v_denied := false;
    begin
      insert into public.school_students (
        id,name,display_name,status,app_type,note
      ) values (
        gen_random_uuid(),'codex-test student-b2 invalid insert',
        'codex-test student-b2 invalid insert',v_status,'school','codex-test rollback-only'
      );
    exception when check_violation then
      if sqlerrm = 'STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE' then v_denied := true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_STATUS_B2_NON_ACTIVE_INSERT_ALLOWED:%',v_status; end if;
  end loop;

  v_denied := false;
  begin
    insert into public.school_students (id,name,display_name,status,app_type,note)
    values (gen_random_uuid(),'codex-test null insert','codex-test null insert',null,'school','codex-test rollback-only');
  exception when check_violation then
    if sqlerrm = 'STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_NULL_INSERT_ALLOWED'; end if;

  v_denied := false;
  begin
    update public.school_students set status = 'paused'
    where id = 'b2020000-0000-4000-8000-000000000100';
  exception when check_violation then
    if sqlerrm = 'STUDENT_LEGACY_STATUS_IMMUTABLE' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_ACTIVE_TO_PAUSED_ALLOWED'; end if;

  v_denied := false;
  begin
    update public.school_students set status = 'active'
    where id = 'cff85c52-6acc-4b0f-8c92-3db280a5dd77';
  exception when check_violation then
    if sqlerrm = 'STUDENT_LEGACY_STATUS_IMMUTABLE' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_PAUSED_TO_ACTIVE_ALLOWED'; end if;

  v_denied := false;
  begin
    select updated_at into strict v_updated_at
    from public.school_students
    where id = 'b2020000-0000-4000-8000-000000000100';
    perform * from public.school_update_student_profile(
      'b2020000-0000-4000-8000-000000000100'::uuid,
      'codex-test legacy owner update',public.school_primary_business_entity_id(),
      'humanities',0,null,null,current_date,null,'codex-test rollback-only',
      'paused',v_updated_at
    );
  exception when check_violation then
    if sqlerrm = 'STUDENT_LEGACY_STATUS_IMMUTABLE' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_OWNER_LEGACY_UPDATE_ALLOWED'; end if;

  v_denied := false;
  begin
    perform * from public.school_create_student_profile(
      'codex-test retired owner create',public.school_primary_business_entity_id(),
      null,0,null,null,null,null,'codex-test rollback-only','paused'
    );
  exception when check_violation then
    if sqlerrm = 'STUDENT_LEGACY_STATUS_INSERT_MUST_BE_ACTIVE' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B2_OWNER_LEGACY_CREATE_ALLOWED'; end if;
end;
$owner_guard_matrix$;

do $final_matrix$
declare v_oid oid;
begin
  if (select count(*) from public.school_student_status_events where student_id::text like 'b2020000-%') <> 0 then
    raise exception 'STUDENT_STATUS_B2_EVENT_CREATED';
  end if;

  if (select status from public.school_students where id = 'cff85c52-6acc-4b0f-8c92-3db280a5dd77') <> 'paused'
     or (select count(*) from public.school_student_status_events) <> 1 then
    raise exception 'STUDENT_STATUS_B2_REAL_PAUSED_FACT_CHANGED';
  end if;

  foreach v_oid in array array[
    'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)'::regprocedure::oid,
    'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)'::regprocedure::oid
  ] loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'STUDENT_STATUS_B2_EVENT_WRITER_EXPOSED:%',v_oid::regprocedure;
    end if;
  end loop;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.school_students'::regclass
        and not tgisinternal
        and tgname = 'school_students_legacy_status_immutable_guard'
        and tgenabled = 'O') <> 1 then
    raise exception 'STUDENT_STATUS_B2_IMMUTABLE_GUARD_INVALID';
  end if;
end;
$final_matrix$;

select 'STUDENT_STATUS_PHASE_B2_LEGACY_FREEZE_ROLLBACK_PASS' result;
rollback;

do $residue$
begin
  if exists (select 1 from auth.users where id::text like 'b2010000-%')
     or exists (select 1 from public.school_students where id::text like 'b2020000-%')
     or exists (select 1 from public.school_student_status_events where student_id::text like 'b2020000-%') then
    raise exception 'STUDENT_STATUS_B2_ROLLBACK_RESIDUE';
  end if;
end;
$residue$;
