-- Included by rehearsal and installed-object rollback tests.
-- Caller owns transaction control. Every fixture is synthetic and rollback-only.

insert into auth.users (id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('a0510000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"status-operator"}'::jsonb,now(),now()),
  ('a0510000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"status-read-only"}'::jsonb,now(),now()),
  ('a0510000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"status-inactive"}'::jsonb,now(),now()),
  ('a0510000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"status-admin"}'::jsonb,now(),now()),
  ('a0510000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"status-none"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('a0510000-0000-4000-8000-000000000001','operator',true,'a0510000-0000-4000-8000-000000000004','a0510000-0000-4000-8000-000000000004','codex-test status operator'),
  ('a0510000-0000-4000-8000-000000000002','read_only',true,'a0510000-0000-4000-8000-000000000004','a0510000-0000-4000-8000-000000000004','codex-test status read-only'),
  ('a0510000-0000-4000-8000-000000000003','admin',false,'a0510000-0000-4000-8000-000000000004','a0510000-0000-4000-8000-000000000004','codex-test status inactive'),
  ('a0510000-0000-4000-8000-000000000004','admin',true,'a0510000-0000-4000-8000-000000000004','a0510000-0000-4000-8000-000000000004','codex-test status admin');

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values
  ('a0510000-0000-4000-8000-000000000100','CODEX-STATUS-A','codex-test status A','codex-test status A','paused',public.school_primary_business_entity_id(),'CNY',0,'codex-test status rollback-only','school',now(),now()),
  ('a0510000-0000-4000-8000-000000000101','CODEX-STATUS-B','codex-test status B','codex-test status B','active',public.school_primary_business_entity_id(),'CNY',0,'codex-test status rollback-only','school',now(),now()),
  ('a0510000-0000-4000-8000-000000000102','CODEX-STATUS-C','codex-test status C','codex-test status C','active',public.school_primary_business_entity_id(),'CNY',0,'codex-test status rollback-only','school',now(),now());

set local role anon;
do $anon_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform * from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-06-01');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_ANON_READER_ALLOWED'; end if;
  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-01','paused','denied',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_ANON_WRITER_ALLOWED'; end if;
end;
$anon_matrix$;
reset role;

set local role service_role;
do $service_matrix$
declare v_denied boolean;
begin
  v_denied:=false;
  begin perform * from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-06-01');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_SERVICE_READER_ALLOWED'; end if;
  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-01','paused','denied',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_SERVICE_WRITER_ALLOWED'; end if;
end;
$service_matrix$;
reset role;

set local role authenticated;
do $membership_matrix$
declare
  v_actor uuid;
  v_denied boolean;
  v_row record;
begin
  foreach v_actor in array array[
    'a0510000-0000-4000-8000-000000000005'::uuid,
    'a0510000-0000-4000-8000-000000000003'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied:=false;
    begin perform * from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-06-01');
    exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'STATUS_INELIGIBLE_READER_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'a0510000-0000-4000-8000-000000000001'::uuid,
    'a0510000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    select * into strict v_row from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-06-01');
    if v_row.resolved_status<>'active' or not v_row.is_legacy_fallback then
      raise exception 'STATUS_MEMBER_FALLBACK_INVALID:%',v_actor;
    end if;
    v_denied:=false;
    begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-01','paused','denied',null,'RECORD_STUDENT_STATUS_EVENT_V1');
    exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'STATUS_NON_ADMIN_WRITER_ALLOWED:%',v_actor; end if;
  end loop;
end;
$membership_matrix$;

do $admin_matrix$
declare
  v_actor constant uuid:='a0510000-0000-4000-8000-000000000004';
  v_denied boolean;
  v_event record;
  v_event2 record;
  v_event3 record;
  v_corrected record;
  v_resolved record;
  v_count bigint;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);

  v_denied:=false;
  begin perform count(*) from public.school_student_status_events;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_DIRECT_SELECT_ALLOWED'; end if;
  v_denied:=false;
  begin insert into public.school_student_status_events(student_id,effective_month,status,reason,created_by_user_id,created_by_membership_id) values ('a0510000-0000-4000-8000-000000000100','2026-07-01','paused','direct',v_actor,v_actor);
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_DIRECT_INSERT_ALLOWED'; end if;

  select * into strict v_resolved from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-06-01');
  if v_resolved.resolved_status<>'active' or not v_resolved.is_legacy_fallback then
    raise exception 'STATUS_LEGACY_SNAPSHOT_USED_AS_FALLBACK';
  end if;

  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-06-01','active','redundant fallback active',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when check_violation then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_FIRST_ACTIVE_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-02','paused','bad month',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_NON_MONTH_FIRST_ALLOWED'; end if;
  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-01','invalid','bad state',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_INVALID_STATE_ALLOWED'; end if;
  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-07-01','paused',' ',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_EMPTY_REASON_ALLOWED'; end if;

  select * into strict v_event from public.school_record_student_status_event_v1(
    'a0510000-0000-4000-8000-000000000100','2026-07-01','paused','codex-test pause',null,'RECORD_STUDENT_STATUS_EVENT_V1'
  );
  if v_event.created_by_user_id<>v_actor or v_event.created_by_membership_id<>v_actor then
    raise exception 'STATUS_ACTOR_NOT_DB_DERIVED';
  end if;
  select * into strict v_resolved from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000100','2026-07-01');
  if v_resolved.resolved_status<>'paused' or v_resolved.source_event_id<>v_event.event_id then
    raise exception 'STATUS_EVENT_RESOLUTION_INVALID';
  end if;

  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-08-01','left','stale expected',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when serialization_failure then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_STALE_EXPECTED_ALLOWED'; end if;

  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-08-01','paused','redundant state',v_event.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when check_violation then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_REDUNDANT_SAME_STATE_ALLOWED'; end if;

  select * into strict v_event2 from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-08-01','left','codex-test left',v_event.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');
  v_denied:=false;
  begin perform * from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-09-01','paused','left to paused forbidden',v_event2.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');
  exception when check_violation then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_LEFT_TO_PAUSED_ALLOWED'; end if;
  select * into strict v_event3 from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000100','2026-09-01','active','codex-test resume',v_event2.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');

  select * into strict v_event from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000102','2026-07-01','paused','codex-test cycle pause 1',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  select * into strict v_event2 from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000102','2026-08-01','active','codex-test cycle resume',v_event.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');
  select * into strict v_event3 from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000102','2026-09-01','paused','codex-test cycle pause 2',v_event2.event_id,'RECORD_STUDENT_STATUS_EVENT_V1');

  select * into strict v_event from public.school_record_student_status_event_v1('a0510000-0000-4000-8000-000000000101','2026-07-01','paused','codex-test correct target',null,'RECORD_STUDENT_STATUS_EVENT_V1');
  select * into strict v_corrected from public.school_correct_student_status_event_v1(
    v_event.event_id,v_event.row_version,'2026-08-01','paused','codex-test corrected pause','codex-test wrong effective month','CORRECT_STUDENT_STATUS_EVENT_V1'
  );
  if v_corrected.affected_start_month<>'2026-07-01' or v_corrected.affected_end_month is not null then
    raise exception 'STATUS_CORRECTION_AFFECTED_RANGE_INVALID';
  end if;
  select * into strict v_resolved from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000101','2026-07-01');
  if v_resolved.resolved_status<>'active' or not v_resolved.is_legacy_fallback then raise exception 'STATUS_CORRECTION_OLD_MONTH_INVALID'; end if;
  select * into strict v_resolved from public.school_resolve_student_status_at_month_v1('a0510000-0000-4000-8000-000000000101','2026-08-01');
  if v_resolved.resolved_status<>'paused' or v_resolved.source_event_id<>v_corrected.replacement_event_id then raise exception 'STATUS_CORRECTION_NEW_MONTH_INVALID'; end if;
  v_denied:=false;
  begin perform * from public.school_correct_student_status_event_v1(v_event.event_id,v_event.row_version,'2026-09-01','paused','stale','stale','CORRECT_STUDENT_STATUS_EVENT_V1');
  exception when check_violation or serialization_failure then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_STALE_CORRECTION_ALLOWED'; end if;

  select count(*) into v_count from public.school_list_student_month_candidates_v1('2026-08-01',false,null)
  where student_id='a0510000-0000-4000-8000-000000000101';
  if v_count<>0 then raise exception 'STATUS_INACTIVE_MONTH_CANDIDATE_INCLUDED'; end if;
  select count(*) into v_count from public.school_list_student_month_candidates_v1('2026-08-01',false,'a0510000-0000-4000-8000-000000000101')
  where student_id='a0510000-0000-4000-8000-000000000101' and is_selected_override;
  if v_count<>1 then raise exception 'STATUS_SELECTED_OVERRIDE_MISSING'; end if;
  select count(*) into v_count from public.school_list_student_range_candidates_v1('2026-07-20','2026-08-03',false,null)
  where student_id='a0510000-0000-4000-8000-000000000101';
  if v_count<>1 then raise exception 'STATUS_RANGE_ACTIVE_ANY_MONTH_INVALID'; end if;
  select count(*) into v_count from public.school_list_student_range_candidates_v1('2026-08-01','2026-09-30',false,null)
  where student_id='a0510000-0000-4000-8000-000000000101';
  if v_count<>0 then raise exception 'STATUS_RANGE_INACTIVE_INCLUDED'; end if;

  v_denied:=false;
  begin update public.school_student_status_events set reason=reason where id=v_event3.event_id;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_DIRECT_UPDATE_ALLOWED'; end if;
  if has_table_privilege('authenticated','public.school_student_status_events','DELETE') then
    raise exception 'STATUS_DIRECT_DELETE_PRIVILEGE_PRESENT';
  end if;
end;
$admin_matrix$;
reset role;

do $owner_guard_matrix$
declare
  v_denied boolean;
  v_old record;
begin
  select * into strict v_old
  from public.school_student_status_events
  where student_id='a0510000-0000-4000-8000-000000000101' and voided_at is not null;
  if v_old.replacement_event_id is null
     or v_old.voided_by_user_id<>'a0510000-0000-4000-8000-000000000004'
     or v_old.voided_by_membership_id<>'a0510000-0000-4000-8000-000000000004'
     or v_old.row_version is null then
    raise exception 'STATUS_CORRECTION_AUDIT_INVALID';
  end if;
  v_denied:=false;
  begin update public.school_student_status_events set reason=reason where id=v_old.id;
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'STATUS_OWNER_DIRECT_UPDATE_ALLOWED'; end if;
  if position('STUDENT_STATUS_EVENT_PHYSICAL_DELETE_FORBIDDEN' in
      pg_get_functiondef('public.school_guard_student_status_event_mutation_v1()'::regprocedure))=0 then
    raise exception 'STATUS_PHYSICAL_DELETE_GUARD_MISSING';
  end if;
end;
$owner_guard_matrix$;

select 'STUDENT_STATUS_PHASE_A_TEST_MATRIX_PASS' result;
