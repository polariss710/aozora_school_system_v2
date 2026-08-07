-- School V2 student monthly status Phase B5 rollback-only matrix, 2026-08-07.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir ../current/school_student_status_phase_b5_core_20260807.sql

grant execute on function public.school_transition_student_status_v1(uuid,text,date,text,uuid,text)
  to authenticated;
grant execute on function public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)
  to authenticated;

insert into auth.users (id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('b5000000-0000-4000-8000-000000000001','authenticated','authenticated','b5-operator@codex.test','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-operator"}'::jsonb,now(),now()),
  ('b5000000-0000-4000-8000-000000000002','authenticated','authenticated','b5-read-only@codex.test','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-read-only"}'::jsonb,now(),now()),
  ('b5000000-0000-4000-8000-000000000003','authenticated','authenticated','b5-inactive@codex.test','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-inactive"}'::jsonb,now(),now()),
  ('b5000000-0000-4000-8000-000000000004','authenticated','authenticated','b5-admin@codex.test','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-admin"}'::jsonb,now(),now()),
  ('b5000000-0000-4000-8000-000000000005','authenticated','authenticated','b5-none@codex.test','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-none"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('b5000000-0000-4000-8000-000000000001','operator',true,'b5000000-0000-4000-8000-000000000004','b5000000-0000-4000-8000-000000000004','codex-test b5 operator'),
  ('b5000000-0000-4000-8000-000000000002','read_only',true,'b5000000-0000-4000-8000-000000000004','b5000000-0000-4000-8000-000000000004','codex-test b5 read-only'),
  ('b5000000-0000-4000-8000-000000000003','admin',false,'b5000000-0000-4000-8000-000000000004','b5000000-0000-4000-8000-000000000004','codex-test b5 inactive'),
  ('b5000000-0000-4000-8000-000000000004','admin',true,'b5000000-0000-4000-8000-000000000004','b5000000-0000-4000-8000-000000000004','codex-test b5 admin');

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values
  ('b5000000-0000-4000-8000-000000000100','CODEX-B5-A','codex-test B5 A','codex-test B5 A','active',public.school_primary_business_entity_id(),'CNY',0,'codex-test b5 rollback-only','school',now(),now()),
  ('b5000000-0000-4000-8000-000000000101','CODEX-B5-B','codex-test B5 B','codex-test B5 B','active',public.school_primary_business_entity_id(),'CNY',0,'codex-test b5 rollback-only','school',now(),now()),
  ('b5000000-0000-4000-8000-000000000102','CODEX-B5-C','codex-test B5 C','codex-test B5 C','active',public.school_primary_business_entity_id(),'CNY',0,'codex-test b5 rollback-only','school',now(),now());

set local role anon;
do $anon$
declare v_denied boolean;
begin
  v_denied := false;
  begin perform * from public.school_list_student_status_management_v1();
  exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_ANON_READER_ALLOWED'; end if;
  v_denied := false;
  begin perform * from public.school_transition_student_status_v1('b5000000-0000-4000-8000-000000000100','paused','2026-04-01','denied',null,'TRANSITION_STUDENT_STATUS_V1');
  exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_ANON_WRITER_ALLOWED'; end if;
end;
$anon$;
reset role;

set local role service_role;
do $service$
declare v_denied boolean;
begin
  v_denied := false;
  begin perform * from public.school_preview_student_status_transition_v1('b5000000-0000-4000-8000-000000000100','paused','2026-04-01',null);
  exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_SERVICE_PREVIEW_ALLOWED'; end if;
  v_denied := false;
  begin perform * from public.school_transition_student_status_v1('b5000000-0000-4000-8000-000000000100','paused','2026-04-01','denied',null,'TRANSITION_STUDENT_STATUS_V1');
  exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_SERVICE_WRITER_ALLOWED'; end if;
end;
$service$;
reset role;

set local role authenticated;
do $role_matrix$
declare
  v_actor uuid;
  v_denied boolean;
  v_count bigint;
begin
  foreach v_actor in array array[
    'b5000000-0000-4000-8000-000000000001'::uuid,
    'b5000000-0000-4000-8000-000000000002'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    select count(*) into v_count from public.school_list_student_status_management_v1()
    where student_id::text like 'b5000000-%';
    if v_count <> 3 then raise exception 'B5_READER_ROLE_MISSING_ROWS:%',v_actor; end if;
    v_denied := false;
    begin perform * from public.school_transition_student_status_v1('b5000000-0000-4000-8000-000000000100','paused','2026-04-01','denied',null,'TRANSITION_STUDENT_STATUS_V1');
    exception when insufficient_privilege then v_denied := true; end;
    if not v_denied then raise exception 'B5_NON_ADMIN_TRANSITION_ALLOWED:%',v_actor; end if;
  end loop;

  foreach v_actor in array array[
    'b5000000-0000-4000-8000-000000000003'::uuid,
    'b5000000-0000-4000-8000-000000000005'::uuid
  ] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied := false;
    begin perform * from public.school_list_student_status_management_v1();
    exception when insufficient_privilege then v_denied := true; end;
    if not v_denied then raise exception 'B5_INELIGIBLE_READER_ALLOWED:%',v_actor; end if;
    v_denied := false;
    begin perform * from public.school_transition_student_status_v1('b5000000-0000-4000-8000-000000000100','paused','2026-04-01','denied',null,'TRANSITION_STUDENT_STATUS_V1');
    exception when insufficient_privilege then v_denied := true; end;
    if not v_denied then raise exception 'B5_INELIGIBLE_WRITER_ALLOWED:%',v_actor; end if;
  end loop;
end;
$role_matrix$;

do $admin_matrix$
declare
  v_actor constant uuid := 'b5000000-0000-4000-8000-000000000004';
  v_preview record;
  v_event1 record;
  v_event2 record;
  v_event3 record;
  v_event4 record;
  v_event5 record;
  v_corrected record;
  v_history_count bigint;
  v_candidate_count bigint;
  v_denied boolean;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);

  select * into strict v_preview
  from public.school_preview_student_status_transition_v1(
    'b5000000-0000-4000-8000-000000000100','paused','2026-04-01',null
  );
  if v_preview.current_status <> 'active' or v_preview.effective_month <> '2026-05-01'
     or v_preview.transition_kind <> 'active_to_paused' then
    raise exception 'B5_ACTIVE_PAUSE_PREVIEW_INVALID';
  end if;

  select * into strict v_event1 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000100','paused','2026-04-01','codex-test pause one',null,'TRANSITION_STUDENT_STATUS_V1'
  );
  if v_event1.effective_month <> '2026-05-01' or v_event1.resolved_status <> 'paused' then
    raise exception 'B5_ACTIVE_PAUSE_INVALID';
  end if;

  select * into strict v_event2 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000100','active','2026-06-01','codex-test resume one',v_event1.event_id,'TRANSITION_STUDENT_STATUS_V1'
  );
  select * into strict v_event3 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000100','paused','2026-06-01','codex-test pause two',v_event2.event_id,'TRANSITION_STUDENT_STATUS_V1'
  );
  select * into strict v_event4 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000100','left','2026-08-01','codex-test left from pause',v_event3.event_id,'TRANSITION_STUDENT_STATUS_V1'
  );

  select count(*) into v_candidate_count
  from public.school_list_student_month_candidates_v1('2026-08-01',false,null)
  where student_id = 'b5000000-0000-4000-8000-000000000100';
  if v_candidate_count <> 0 then raise exception 'B5_B4_FINANCE_MONTH_CANDIDATE_NOT_UPDATED'; end if;
  select count(*) into v_candidate_count
  from public.school_list_student_month_candidates_v1(
    '2026-08-01',false,'b5000000-0000-4000-8000-000000000100'
  ) where student_id = 'b5000000-0000-4000-8000-000000000100' and is_selected_override;
  if v_candidate_count <> 1 then raise exception 'B5_B4_SELECTED_OVERRIDE_MISSING'; end if;
  select count(*) into v_candidate_count
  from public.school_list_student_range_candidates_v1('2026-05-25','2026-06-07',false,null)
  where student_id = 'b5000000-0000-4000-8000-000000000100' and is_active_in_range;
  if v_candidate_count <> 1 then raise exception 'B5_B4_RANGE_ANY_ACTIVE_INVALID'; end if;
  select count(*) into v_candidate_count
  from public.school_list_current_student_month_candidates_v1(false,null)
  where student_id = 'b5000000-0000-4000-8000-000000000100';
  if v_candidate_count <> 0 then raise exception 'B5_B4_WAGE_RULE_CURRENT_CANDIDATE_NOT_UPDATED'; end if;
  select count(*) into v_candidate_count
  from public.school_list_planned_lesson_student_candidates_v1(
    '2026-08-03',public.school_primary_business_entity_id(),
    'b5000000-0000-4000-8000-000000000100'
  ) where student_id = 'b5000000-0000-4000-8000-000000000100'
      and is_selected_override and not is_eligible;
  if v_candidate_count <> 1 then raise exception 'B5_B4_LESSON_PLANNED_SELECTED_OVERRIDE_INVALID'; end if;

  select * into strict v_event5 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000100','active','2026-09-01','codex-test re-enroll',v_event4.event_id,'TRANSITION_STUDENT_STATUS_V1'
  );
  if v_event2.effective_month <> '2026-06-01'
     or v_event3.effective_month <> '2026-07-01'
     or v_event4.effective_month <> '2026-08-01'
     or v_event5.effective_month <> '2026-09-01' then
    raise exception 'B5_MULTI_CYCLE_MONTHS_INVALID';
  end if;

  select * into strict v_event1 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','left','2026-05-01','codex-test direct left',null,'TRANSITION_STUDENT_STATUS_V1'
  );
  if v_event1.effective_month <> '2026-06-01' then raise exception 'B5_ACTIVE_LEFT_INVALID'; end if;
  v_denied := false;
  begin perform * from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','paused','2026-07-01','forbidden',v_event1.event_id,'TRANSITION_STUDENT_STATUS_V1'
  ); exception when check_violation then v_denied := true; end;
  if not v_denied then raise exception 'B5_LEFT_PAUSED_ALLOWED'; end if;
  select * into strict v_event2 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','active','2026-07-01','codex-test re-enroll B',v_event1.event_id,'TRANSITION_STUDENT_STATUS_V1'
  );

  v_denied := false;
  begin perform * from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','active','2026-08-01','redundant',v_event2.event_id,'TRANSITION_STUDENT_STATUS_V1'
  ); exception when check_violation then v_denied := true; end;
  if not v_denied then raise exception 'B5_REDUNDANT_ALLOWED'; end if;

  v_denied := false;
  begin perform * from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','paused','2026-06-01','out of order',v_event2.event_id,'TRANSITION_STUDENT_STATUS_V1'
  ); exception when check_violation then v_denied := true; end;
  if not v_denied then raise exception 'B5_OUT_OF_ORDER_ALLOWED'; end if;

  v_denied := false;
  begin perform * from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','paused','2026-07-01','stale expected',v_event1.event_id,'TRANSITION_STUDENT_STATUS_V1'
  ); exception when serialization_failure then v_denied := true; end;
  if not v_denied then raise exception 'B5_STALE_EXPECTED_ALLOWED'; end if;

  v_denied := false;
  begin perform * from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000101','paused','2026-07-01',' ',v_event2.event_id,'TRANSITION_STUDENT_STATUS_V1'
  ); exception when invalid_parameter_value then v_denied := true; end;
  if not v_denied then raise exception 'B5_EMPTY_REASON_ALLOWED'; end if;

  select * into strict v_event1 from public.school_transition_student_status_v1(
    'b5000000-0000-4000-8000-000000000102','paused','2026-04-01','codex-test correction target',null,'TRANSITION_STUDENT_STATUS_V1'
  );
  select * into strict v_preview from public.school_preview_student_status_correction_v1(
    v_event1.event_id,v_event1.row_version,v_event1.event_id,'2026-06-01','paused'
  );
  if v_preview.original_effective_month <> '2026-05-01'
     or v_preview.replacement_effective_month <> '2026-06-01' then
    raise exception 'B5_CORRECTION_PREVIEW_INVALID';
  end if;
  select * into strict v_corrected from public.school_correct_student_status_event_v1(
    v_event1.event_id,v_event1.row_version,v_event1.event_id,'2026-06-01','paused',
    'codex-test corrected pause','codex-test wrong month','CORRECT_STUDENT_STATUS_EVENT_B5_V1'
  );
  if v_corrected.replacement_effective_month <> '2026-06-01'
     or v_corrected.voided_event_id <> v_event1.event_id then
    raise exception 'B5_CORRECTION_RESULT_INVALID';
  end if;
  select count(*) into v_history_count
  from public.school_list_student_status_history_v1('b5000000-0000-4000-8000-000000000102');
  if v_history_count <> 2 then raise exception 'B5_CORRECTION_HISTORY_INVALID'; end if;

  v_denied := false;
  begin perform * from public.school_correct_student_status_event_v1(
    v_event1.event_id,v_event1.row_version,v_event1.event_id,'2026-07-01','paused',
    'stale','stale','CORRECT_STUDENT_STATUS_EVENT_B5_V1'
  ); exception when check_violation or serialization_failure then v_denied := true; end;
  if not v_denied then raise exception 'B5_STALE_CORRECTION_ALLOWED'; end if;

  v_denied := false;
  begin perform * from public.school_record_student_status_event_v1(
    'b5000000-0000-4000-8000-000000000102','2026-07-01','active','raw denied',v_corrected.replacement_event_id,'RECORD_STUDENT_STATUS_EVENT_V1'
  ); exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_RAW_RECORD_WRITER_EXPOSED'; end if;

  v_denied := false;
  begin perform * from public.school_correct_student_status_event_v1(
    v_corrected.replacement_event_id,v_corrected.replacement_row_version,'2026-07-01','active','old denied','old denied','CORRECT_STUDENT_STATUS_EVENT_V1'
  ); exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_OLD_CORRECTION_WRITER_EXPOSED'; end if;

  v_denied := false;
  begin update public.school_students set status = 'paused' where id = 'b5000000-0000-4000-8000-000000000102';
  exception when insufficient_privilege or check_violation then v_denied := true; end;
  if not v_denied then raise exception 'B5_LEGACY_STATUS_MUTABLE'; end if;
  v_denied := false;
  begin insert into public.school_student_status_events(student_id,effective_month,status,reason,created_by_user_id,created_by_membership_id)
    values ('b5000000-0000-4000-8000-000000000102','2026-07-01','active','direct',v_actor,v_actor);
  exception when insufficient_privilege then v_denied := true; end;
  if not v_denied then raise exception 'B5_DIRECT_EVENT_DML_ALLOWED'; end if;
end;
$admin_matrix$;
reset role;

do $owner_assertions$
begin
  if exists (
    select 1 from public.school_students s
    where s.id::text like 'b5000000-%' and s.status <> 'active'
  ) then raise exception 'B5_LEGACY_STATUS_FIXTURE_CHANGED'; end if;
  if not exists (
    select 1 from public.school_student_status_events e
    where e.student_id = 'b5000000-0000-4000-8000-000000000102'
      and e.voided_at is not null and e.replacement_event_id is not null
  ) then raise exception 'B5_CORRECTION_VOID_REPLACEMENT_MISSING'; end if;
end;
$owner_assertions$;

rollback;

do $residue$
begin
  if exists (select 1 from auth.users where id::text like 'b5000000-%')
     or exists (select 1 from public.school_students where id::text like 'b5000000-%')
     or exists (select 1 from public.school_student_status_events where student_id::text like 'b5000000-%') then
    raise exception 'B5_ROLLBACK_RESIDUE';
  end if;
end;
$residue$;

select 'STUDENT_STATUS_PHASE_B5_ROLLBACK_PASS' result;
