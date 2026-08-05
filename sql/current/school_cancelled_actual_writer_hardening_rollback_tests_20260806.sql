-- School V2 cancellation writer rollback-only permission and business matrix.
-- Every fixture uses fixed c608... IDs and the transaction always rolls back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir school_create_cancelled_actual_lesson_from_planned_rpc.sql

do $fixture_preflight$
begin
  if exists(select 1 from auth.users where id::text like 'c6080000-%')
     or exists(select 1 from public.school_students where id::text like 'c6080000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'c6080000-%') then
    raise exception 'CANCELLATION_WRITER_FIXTURE_ID_COLLISION';
  end if;
end;
$fixture_preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('c6080000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-admin"}'::jsonb,now(),now()),
  ('c6080000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-operator"}'::jsonb,now(),now()),
  ('c6080000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-read-only"}'::jsonb,now(),now()),
  ('c6080000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-inactive-admin"}'::jsonb,now(),now()),
  ('c6080000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-inactive-operator"}'::jsonb,now(),now()),
  ('c6080000-0000-4000-8000-000000000006','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cancel-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('c6080000-0000-4000-8000-000000000001','admin',true,'c6080000-0000-4000-8000-000000000001','c6080000-0000-4000-8000-000000000001','codex-test cancellation active admin'),
  ('c6080000-0000-4000-8000-000000000002','operator',true,'c6080000-0000-4000-8000-000000000001','c6080000-0000-4000-8000-000000000001','codex-test cancellation active operator'),
  ('c6080000-0000-4000-8000-000000000003','read_only',true,'c6080000-0000-4000-8000-000000000001','c6080000-0000-4000-8000-000000000001','codex-test cancellation read-only'),
  ('c6080000-0000-4000-8000-000000000004','admin',false,'c6080000-0000-4000-8000-000000000001','c6080000-0000-4000-8000-000000000001','codex-test cancellation inactive admin'),
  ('c6080000-0000-4000-8000-000000000005','operator',false,'c6080000-0000-4000-8000-000000000001','c6080000-0000-4000-8000-000000000001','codex-test cancellation inactive operator');

insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('c6080000-0000-4000-8000-00000000d001','codex-test cancellation subject','codex-test',true,'codex-test cancellation rollback','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  'c6080000-0000-4000-8000-000000007001','codex-cancel-teacher','codex-test cancellation teacher',
  'codex-test cancellation teacher','c6080000-0000-4000-8000-00000000d001',
  public.school_primary_business_entity_id(),'active','codex-test cancellation rollback','school'
);
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values
  ('c6080000-0000-4000-8000-00000000a001','codex-cancel-main','codex-test cancellation main','codex-test cancellation main',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-00000000a002','codex-cancel-locked','codex-test cancellation locked','codex-test cancellation locked',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-00000000a003','codex-cancel-consumed','codex-test cancellation consumed','codex-test cancellation consumed',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-00000000a004','codex-cancel-claim','codex-test cancellation claim','codex-test cancellation claim',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test cancellation rollback');

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  lesson_delivery_mode,lesson_venue,note
) values
  ('c6080000-0000-4000-8000-000000001101','planned','2020-01-06','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'admin success','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001102','planned','2020-01-13','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'11:00','13:00',2,'operator success','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001103','planned','2020-01-20','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'13:00','15:00',2,'pending source','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001104','planned','2020-01-21','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'14:00','16:00',2,'grid source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001105','planned','2020-01-22','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'15:00','17:00',2,'range source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001106','planned','2020-01-23','2020-01','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'16:00','18:00',2,'mismatch source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001201','planned','2020-02-03','2020-02','c6080000-0000-4000-8000-00000000a002','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'locked source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001301','planned','2020-03-02','2020-03','c6080000-0000-4000-8000-00000000a003','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'10:00','12:00',2,'consumed source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001401','planned','2020-04-06','2020-04','c6080000-0000-4000-8000-00000000a004','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'11:00','13:00',2,'claim source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback'),
  ('c6080000-0000-4000-8000-000000001501','planned','2020-05-04','2020-05','c6080000-0000-4000-8000-00000000a001','c6080000-0000-4000-8000-000000007001','c6080000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'12:00','14:00',2,'wage source','planned',true,'school',1000,2000,1,'online','Zoom','codex-test cancellation rollback');

-- Locked settlement fixture is isolated and rolled back; replica mode only
-- avoids invoking the unrelated settlement creation workflow.
set local session_replication_role='replica';
insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,
  settlement_status,locked_at,note
) values(
  'c6080000-0000-4000-8000-00000000b002','c6080000-0000-4000-8000-00000000a002','2020-02',
  public.school_primary_business_entity_id(),0,'locked',now(),'codex-test cancellation locked rollback'
);
set local session_replication_role='origin';

insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,settlement_status,note
) values
  ('c6080000-0000-4000-8000-00000000b003','c6080000-0000-4000-8000-00000000a003','2020-03',public.school_primary_business_entity_id(),0,'unlocked','codex-test cancellation consumed rollback'),
  ('c6080000-0000-4000-8000-00000000b004','c6080000-0000-4000-8000-00000000a004','2020-04',public.school_primary_business_entity_id(),0,'unlocked','codex-test cancellation claim rollback');

-- Permanent Rule B fixture: the only revision and bill are already voided.
set local session_replication_role='replica';
insert into public.school_student_tuition_bills(
  id,student_id,business_entity_id,billing_month,previous_settlement_month,
  previous_settlement_id,previous_carryover_cny,planned_lesson_count,
  planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
  source_snapshot,note,app_type,billing_role,cash_submission_blocked
) values(
  'c6080000-0000-4000-8000-000000006001','c6080000-0000-4000-8000-00000000a003',
  public.school_primary_business_entity_id(),'2020-04','2020-03',
  'c6080000-0000-4000-8000-00000000b003',0,1,1,1000,1000,'JPY','cancelled',
  '{}'::jsonb,'codex-test cancellation voided bill rollback','school','canonical_charge',false
);
insert into public.school_student_tuition_billing_identities(
  id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
) values(
  'c6080000-0000-4000-8000-000000002001','c6080000-0000-4000-8000-00000000a003','2020-04',
  'c6080000-0000-4000-8000-000000006001','codex-test-cancel-rule-b','atomic_charge','codex-test cancellation','{}'::jsonb
);
insert into public.school_student_tuition_generation_identities(
  id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
) values(
  'c6080000-0000-4000-8000-000000003001','c6080000-0000-4000-8000-00000000a003',
  public.school_primary_business_entity_id(),'2020-04-01','c6080000-0000-4000-8000-000000002001',now(),'codex-test cancellation'
);
insert into public.school_student_tuition_generation_revisions(
  id,generation_identity_id,tuition_bill_id,revision_no,generation_manifest_sha256,
  manifest_kind,lifecycle_status,created_at,created_by_authority,activated_at,
  voided_at,voided_by_authority
) values(
  'c6080000-0000-4000-8000-000000004001','c6080000-0000-4000-8000-000000003001',
  'c6080000-0000-4000-8000-000000006001',1,repeat('c',64),'atomic_generation_v1',
  'voided',now(),'codex-test cancellation',now(),now(),'codex-test cancellation'
);
set local session_replication_role='origin';

select set_config('school.p0f_claim_writer','on',true);
insert into public.school_student_settlement_lesson_variance_claims(
  id,claim_batch_id,claim_batch_version,settlement_id,student_id,business_entity_id,
  year_month,source_type,source_planned_lesson_id,source_hours,source_amount_jpy,
  source_amount_cny,settlement_exchange_rate,calculation_version,
  line_manifest_sha256,claim_status,created_by
) values(
  'c6080000-0000-4000-8000-000000005001','c6080000-0000-4000-8000-000000005002',1,
  'c6080000-0000-4000-8000-00000000b004','c6080000-0000-4000-8000-00000000a004',
  public.school_primary_business_entity_id(),'2020-04','unused_planned_credit_v1',
  'c6080000-0000-4000-8000-000000001401',-2,-1000,-50,0.05,
  'lesson_variance_financial_netting_v1',repeat('d',64),'active','codex-test cancellation'
);
select set_config('school.p0f_claim_writer','off',true);

insert into public.school_teacher_wage_locks(
  id,settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
  settlement_type,exchange_rate,total_minutes,pay_hours,lesson_wage_jpy,
  lesson_wage_cny,fee_jpy,total_jpy,total_cny,lesson_count,status,locked_at
) values(
  'c6080000-0000-4000-8000-000000007101','2020-05','c6080000-0000-4000-8000-000000007001',
  'codex-test cancellation teacher',public.school_primary_business_entity_id(),
  'codex-test cancellation entity','jpy_hourly',0,60,1,1000,0,0,1000,0,1,'locked',now()
);

set local role anon;
do $anon_acl$
declare v_denied boolean:=false;
begin
  begin
    perform * from public.school_create_cancelled_actual_lesson_from_planned(
      'c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,null,null
    );
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'CANCELLATION_WRITER_ANON_ALLOWED'; end if;
end;
$anon_acl$;
reset role;

set local role service_role;
do $service_acl$
declare v_denied boolean:=false;
begin
  begin
    perform * from public.school_create_cancelled_actual_lesson_from_planned(
      'c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,null,null
    );
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'CANCELLATION_WRITER_SERVICE_ALLOWED'; end if;
end;
$service_acl$;
reset role;

set local role authenticated;
do $membership_matrix$
declare
  v_actor uuid;
  v_expected text;
  v_denied boolean;
begin
  for v_actor,v_expected in
    select * from (values
      ('c6080000-0000-4000-8000-000000000006'::uuid,'LESSON_CANCELLATION_MEMBERSHIP_REQUIRED'),
      ('c6080000-0000-4000-8000-000000000003'::uuid,'LESSON_CANCELLATION_ROLE_REQUIRED'),
      ('c6080000-0000-4000-8000-000000000004'::uuid,'LESSON_CANCELLATION_ACTIVE_MEMBERSHIP_REQUIRED'),
      ('c6080000-0000-4000-8000-000000000005'::uuid,'LESSON_CANCELLATION_ACTIVE_MEMBERSHIP_REQUIRED')
    ) expected(actor,error_code)
  loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_denied:=false;
    begin
      perform * from public.school_create_cancelled_actual_lesson_from_planned(
        'c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,null,null
      );
    exception when insufficient_privilege then
      if sqlerrm=v_expected then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'CANCELLATION_WRITER_MEMBERSHIP_ALLOWED:%',v_actor; end if;
  end loop;

  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  v_denied:=false;
  begin
    perform * from public.school_create_cancelled_actual_lesson_from_planned(
      'c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,null,null
    );
  exception when insufficient_privilege then
    if sqlerrm='LESSON_CANCELLATION_AUTH_REQUIRED' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'CANCELLATION_WRITER_AUTHLESS_ALLOWED'; end if;
end;
$membership_matrix$;

do $success_and_guard_matrix$
declare
  v_actual_admin uuid;
  v_actual_operator uuid;
  v_denied boolean;
  v_code text;
begin
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','c6080000-0000-4000-8000-000000000001'::uuid,'role','authenticated'
  )::text,true);
  select lesson_id into strict v_actual_admin
  from public.school_create_cancelled_actual_lesson_from_planned(
    'c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,
    'codex-test admin cancelled','codex-test cancellation rollback'
  );
  if not exists(
    select 1 from public.school_lesson_records actual
    join public.school_lesson_records planned on planned.id=actual.planned_lesson_id
    where actual.id=v_actual_admin
      and actual.lesson_type='actual' and actual.status='cancelled'
      and actual.planned_lesson_id='c6080000-0000-4000-8000-000000001101'
      and actual.student_id=planned.student_id and actual.teacher_id=planned.teacher_id
      and actual.subject_id=planned.subject_id
      and actual.business_entity_id=planned.business_entity_id
      and actual.start_time='09:00' and actual.end_time='10:15'
      and actual.duration_hours=1.25 and not actual.is_billable
      and actual.lesson_fee=0 and actual.actual_minutes=0
      and actual.year_month='2020-01' and actual.teacher_settlement_month='2020-01'
      and planned.status='pending_makeup'
  ) then raise exception 'CANCELLATION_WRITER_ADMIN_RESULT_INVALID'; end if;
  if public.school_get_lesson_credit_remaining_hours(
       'c6080000-0000-4000-8000-000000001101'
     )<>2 then
    raise exception 'CANCELLATION_WRITER_CREDIT_BALANCE_INVALID';
  end if;
  if not exists(
    select 1 from public.school_list_open_lesson_credit_sources('2020-01','2020-01','2020-01')
    where id='c6080000-0000-4000-8000-000000001101'
  ) then raise exception 'CANCELLATION_WRITER_MAKEUP_READER_MISSING'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','c6080000-0000-4000-8000-000000000002'::uuid,'role','authenticated'
  )::text,true);
  select lesson_id into strict v_actual_operator
  from public.school_create_cancelled_actual_lesson_from_planned(
    'c6080000-0000-4000-8000-000000001102','2020-01-13','11:00','12:00',null,1000,1,
    'codex-test operator cancelled','codex-test cancellation rollback'
  );
  if (select duration_hours from public.school_lesson_records where id=v_actual_operator)<>1 then
    raise exception 'CANCELLATION_WRITER_OPERATOR_DB_DURATION_INVALID';
  end if;

  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','c6080000-0000-4000-8000-000000000001'::uuid,'role','authenticated'
  )::text,true);
  for v_code in select unnest(array[
    'LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS',
    'LESSON_CANCELLATION_SOURCE_STATUS_INVALID',
    'LESSON_CANCELLATION_TIME_GRID_INVALID',
    'LESSON_CANCELLATION_TIME_RANGE_INVALID',
    'LESSON_CANCELLATION_DURATION_MISMATCH',
    'LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED',
    'LESSON_FINANCIAL_FACT_IMMUTABLE',
    'SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED',
    'LESSON_CANCELLATION_TEACHER_WAGE_LOCKED'
  ]) loop
    v_denied:=false;
    begin
      case v_code
        when 'LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001101','2020-01-06','09:00','10:15',1.25,1000,1,null,null);
        when 'LESSON_CANCELLATION_SOURCE_STATUS_INVALID' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001103','2020-01-20','13:00','14:00',1,1000,1,null,null);
        when 'LESSON_CANCELLATION_TIME_GRID_INVALID' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001104','2020-01-21','14:10','15:00',null,1000,1,null,null);
        when 'LESSON_CANCELLATION_TIME_RANGE_INVALID' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001105','2020-01-22','16:00','15:00',null,1000,1,null,null);
        when 'LESSON_CANCELLATION_DURATION_MISMATCH' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001106','2020-01-23','16:00','17:15',1,1000,1,null,null);
        when 'LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001201','2020-02-03','09:00','10:00',1,1000,1,null,null);
        when 'LESSON_FINANCIAL_FACT_IMMUTABLE' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001301','2020-03-02','10:00','11:00',1,1000,1,null,null);
        when 'SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001401','2020-04-06','11:00','12:00',1,1000,1,null,null);
        when 'LESSON_CANCELLATION_TEACHER_WAGE_LOCKED' then
          perform * from public.school_create_cancelled_actual_lesson_from_planned('c6080000-0000-4000-8000-000000001501','2020-05-04','12:00','13:00',1,1000,1,null,null);
      end case;
    exception when others then
      if position(v_code in sqlerrm)>0 then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'CANCELLATION_WRITER_GUARD_ALLOWED:%',v_code; end if;
  end loop;

  if exists(
    select 1 from public.school_lesson_records
    where planned_lesson_id in (
      'c6080000-0000-4000-8000-000000001103','c6080000-0000-4000-8000-000000001104',
      'c6080000-0000-4000-8000-000000001105','c6080000-0000-4000-8000-000000001106',
      'c6080000-0000-4000-8000-000000001201','c6080000-0000-4000-8000-000000001301',
      'c6080000-0000-4000-8000-000000001401','c6080000-0000-4000-8000-000000001501'
    )
  ) or exists(
    select 1 from public.school_lesson_records
    where id in (
      'c6080000-0000-4000-8000-000000001104','c6080000-0000-4000-8000-000000001105',
      'c6080000-0000-4000-8000-000000001106','c6080000-0000-4000-8000-000000001201',
      'c6080000-0000-4000-8000-000000001301','c6080000-0000-4000-8000-000000001401',
      'c6080000-0000-4000-8000-000000001501'
    ) and status<>'planned'
  ) then raise exception 'CANCELLATION_WRITER_REJECTION_LEFT_PARTIAL_WRITE'; end if;

  if exists(
    select 1 from public.school_teacher_wage_lock_details
    where lesson_record_id in (v_actual_admin,v_actual_operator)
  ) or position($needle$status in ('completed', 'makeup_completed')$needle$ in lower(pg_get_functiondef(
       'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
     )))=0 then
    raise exception 'CANCELLATION_WRITER_WAGE_EXCLUSION_INVALID';
  end if;
end;
$success_and_guard_matrix$;
reset role;

do $catalog_matrix$
declare
  v_writer regprocedure :=
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
begin
  if not has_function_privilege('authenticated',v_writer,'EXECUTE')
     or has_function_privilege('public',v_writer,'EXECUTE')
     or has_function_privilege('anon',v_writer,'EXECUTE')
     or has_function_privilege('service_role',v_writer,'EXECUTE')
     or pg_get_userbyid((select proowner from pg_proc where oid=v_writer))<>'postgres'
     or not (select prosecdef from pg_proc where oid=v_writer)
     or (select proconfig from pg_proc where oid=v_writer)<>'{"search_path=pg_catalog, public"}'::text[]
     or (select count(*) from public.school_lesson_records
         where planned_lesson_id in (
           'c6080000-0000-4000-8000-000000001101',
           'c6080000-0000-4000-8000-000000001102'
         ) and lesson_type='actual')<>2 then
    raise exception 'CANCELLATION_WRITER_CATALOG_MATRIX_INVALID';
  end if;
end;
$catalog_matrix$;

select 'CANCELLATION_WRITER_HARDENING_ROLLBACK_TEST_PASS' result;
rollback;

do $residue$
begin
  if exists(select 1 from auth.users where id::text like 'c6080000-%')
     or exists(select 1 from public.school_students where id::text like 'c6080000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'c6080000-%')
     or exists(select 1 from public.school_student_monthly_settlements where id::text like 'c6080000-%')
     or exists(select 1 from public.school_teacher_wage_locks where id::text like 'c6080000-%') then
    raise exception 'CANCELLATION_WRITER_ROLLBACK_RESIDUE';
  end if;
end;
$residue$;
