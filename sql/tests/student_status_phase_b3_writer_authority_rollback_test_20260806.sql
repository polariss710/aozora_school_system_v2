-- Phase B3 writer authority rollback-only business and role matrix.
-- All fixtures use fixed b301..b306 UUID ranges and the transaction rolls back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir ../current/school_student_status_phase_b3_writer_authority_core_20260806.sql

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like 'b3010000-%')
     or exists(select 1 from public.school_students where id::text like 'b3020000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'b3030000-%')
     or exists(select 1 from public.school_student_status_events where id::text like 'b3050000-%')
     or exists(select 1 from public.school_teacher_wage_rules where id::text like 'b3060000-%') then
    raise exception 'STUDENT_STATUS_B3_FIXTURE_COLLISION';
  end if;
end;
$preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('b3010000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b3-admin"}'::jsonb,now(),now()),
 ('b3010000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b3-operator"}'::jsonb,now(),now()),
 ('b3010000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b3-read-only"}'::jsonb,now(),now()),
 ('b3010000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b3-inactive-admin"}'::jsonb,now(),now()),
 ('b3010000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b3-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships(user_id,role,is_active,created_by_user_id,updated_by_user_id,note)
values
 ('b3010000-0000-4000-8000-000000000001','admin',true,'b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','codex-test phase-b3 admin'),
 ('b3010000-0000-4000-8000-000000000002','operator',true,'b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','codex-test phase-b3 operator'),
 ('b3010000-0000-4000-8000-000000000003','read_only',true,'b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','codex-test phase-b3 read-only'),
 ('b3010000-0000-4000-8000-000000000004','admin',false,'b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','codex-test phase-b3 inactive admin');

insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('b3040000-0000-4000-8000-000000000001','codex-test phase-b3 subject','codex-test',true,'codex-test phase-b3 rollback','班课');

insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  'b3040000-0000-4000-8000-000000000002','codex-b3-teacher','codex-test phase-b3 teacher',
  'codex-test phase-b3 teacher','b3040000-0000-4000-8000-000000000001',
  public.school_primary_business_entity_id(),'active','codex-test phase-b3 rollback','school'
);

insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values
 ('b3020000-0000-4000-8000-000000000001','codex-b3-fallback','codex-test phase-b3 fallback','codex-test phase-b3 fallback',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test phase-b3 rollback'),
 ('b3020000-0000-4000-8000-000000000002','codex-b3-timeline','codex-test phase-b3 timeline','codex-test phase-b3 timeline',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test phase-b3 rollback'),
 ('b3020000-0000-4000-8000-000000000003','codex-b3-current-paused','codex-test phase-b3 paused','codex-test phase-b3 paused',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test phase-b3 rollback'),
 ('b3020000-0000-4000-8000-000000000004','codex-b3-current-left','codex-test phase-b3 left','codex-test phase-b3 left',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test phase-b3 rollback');

insert into public.school_student_status_events(
  id,student_id,effective_month,status,reason,row_version,
  created_by_user_id,created_by_membership_id,created_at
) values
 ('b3050000-0000-4000-8000-000000000001','b3020000-0000-4000-8000-000000000002','2025-05-01','active','codex-test phase-b3 active boundary','b3050000-0000-4000-8000-000000000101','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-05-01 00:00+00'),
 ('b3050000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000002','2025-06-01','paused','codex-test phase-b3 paused boundary','b3050000-0000-4000-8000-000000000102','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-06-01 00:00+00'),
 ('b3050000-0000-4000-8000-000000000003','b3020000-0000-4000-8000-000000000002','2025-07-01','active','codex-test phase-b3 resumed boundary','b3050000-0000-4000-8000-000000000103','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-07-01 00:00+00'),
 ('b3050000-0000-4000-8000-000000000004','b3020000-0000-4000-8000-000000000002','2025-08-01','left','codex-test phase-b3 left boundary','b3050000-0000-4000-8000-000000000104','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-08-01 00:00+00'),
 ('b3050000-0000-4000-8000-000000000005','b3020000-0000-4000-8000-000000000003','2025-05-01','paused','codex-test phase-b3 paused throughout test window','b3050000-0000-4000-8000-000000000105','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-05-01 00:00+00'),
 ('b3050000-0000-4000-8000-000000000006','b3020000-0000-4000-8000-000000000004','2025-05-01','left','codex-test phase-b3 left throughout test window','b3050000-0000-4000-8000-000000000106','b3010000-0000-4000-8000-000000000001','b3010000-0000-4000-8000-000000000001','2025-05-01 00:00+00');

do $resolver_matrix$
begin
  if not (select is_active from public.school_resolve_student_status_at_month_core_v1('b3020000-0000-4000-8000-000000000001','2025-05-01'))
     or (select resolved_status from public.school_resolve_student_status_at_month_core_v1('b3020000-0000-4000-8000-000000000002','2025-05-01'))<>'active'
     or (select resolved_status from public.school_resolve_student_status_at_month_core_v1('b3020000-0000-4000-8000-000000000002','2025-06-01'))<>'paused'
     or (select resolved_status from public.school_resolve_student_status_at_month_core_v1('b3020000-0000-4000-8000-000000000002','2025-07-01'))<>'active'
     or (select resolved_status from public.school_resolve_student_status_at_month_core_v1('b3020000-0000-4000-8000-000000000002','2025-08-01'))<>'left' then
    raise exception 'STUDENT_STATUS_B3_RESOLVER_MATRIX_INVALID';
  end if;
end;
$resolver_matrix$;

create temp table b3_created_plans(kind text primary key,lesson_id uuid not null) on commit drop;

do $planned_create_matrix$
declare
  v_id uuid;
  v_denied boolean;
  v_date date;
begin
  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2025-05-05','b3020000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    '09:00','11:00',2,1000,null,'planned',1,'codex-test fallback active','codex-test phase-b3 rollback'
  );
  insert into b3_created_plans values('fallback_active',v_id);

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2025-05-12','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    '09:00','11:00',2,1000,null,'planned',2,'codex-test last active','codex-test phase-b3 rollback'
  );
  insert into b3_created_plans values('timeline_edit',v_id);

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2025-07-07','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    '09:00','11:00',2,1000,null,'planned',3,'codex-test resumed','codex-test phase-b3 rollback'
  );
  insert into b3_created_plans values('resumed_active',v_id);

  foreach v_date in array array['2025-06-02'::date,'2025-08-04'::date] loop
    v_denied:=false;
    begin
      perform * from public.school_create_planned_lesson_record(
        v_date,'b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
        '12:00','14:00',2,1000,null,'planned',4,'codex-test denied','codex-test phase-b3 rollback'
      );
    exception when sqlstate '22023' then
      if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
    end;
    if not v_denied then raise exception 'STUDENT_STATUS_B3_PLANNED_INACTIVE_ALLOWED:%',v_date; end if;
  end loop;
end;
$planned_create_matrix$;

create temp table b3_batch_result on commit drop as
select * from public.school_generate_planned_lessons_batch(
  'b3030000-0000-4000-8000-00000000b001','b3020000-0000-4000-8000-000000000002',public.school_primary_business_entity_id(),
  '2025-05-05','2025-06-02',
  jsonb_build_array(jsonb_build_object(
    'pattern_index',1,'weekday',1,'status','planned','teacher_id','b3040000-0000-4000-8000-000000000002',
    'subject_id','b3040000-0000-4000-8000-000000000001','start_time','14:00','end_time','16:00',
    'duration_hours',2,'unit_price',1000,'occurrence_count',1,'lesson_count',5,
    'lesson_content','codex-test phase-b3 batch','note','codex-test phase-b3 rollback'
  )),'[]'::jsonb,'codex-test phase-b3 rollback'
);

do $batch_matrix$
begin
  if not exists(select 1 from b3_batch_result where array_to_string(errors,'|') like '%STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH%billing_month=2025-06%')
     or exists(select 1 from b3_batch_result where batch_committed)
     or exists(select 1 from public.school_lesson_records where import_batch_id='b3030000-0000-4000-8000-00000000b001') then
    raise exception 'STUDENT_STATUS_B3_BATCH_ATOMIC_MATRIX_INVALID';
  end if;
end;
$batch_matrix$;

create temp table b3_import_result on commit drop as
select * from public.school_import_lesson_records_batch(
  'b3030000-0000-4000-8000-00000000c001','codex-test-phase-b3.csv','codex-test-phase-b3-hash',
  jsonb_build_array(
    jsonb_build_object('row_index',1,'source_row_no',2,'row_key','active','lesson_type','planned','status','planned','lesson_date','2025-05-19','start_time','10:00','end_time','12:00','duration_hours',2,'lesson_count',6,'unit_price',1000,'lesson_fee',null,'is_billable',true,'student_id','b3020000-0000-4000-8000-000000000002','teacher_id','b3040000-0000-4000-8000-000000000002','subject_id','b3040000-0000-4000-8000-000000000001','business_entity_id',public.school_primary_business_entity_id(),'planned_lesson_id',null,'lesson_content','codex-test active import','note','codex-test phase-b3 rollback'),
    jsonb_build_object('row_index',2,'source_row_no',3,'row_key','paused','lesson_type','planned','status','planned','lesson_date','2025-06-09','start_time','10:00','end_time','12:00','duration_hours',2,'lesson_count',7,'unit_price',1000,'lesson_fee',null,'is_billable',true,'student_id','b3020000-0000-4000-8000-000000000002','teacher_id','b3040000-0000-4000-8000-000000000002','subject_id','b3040000-0000-4000-8000-000000000001','business_entity_id',public.school_primary_business_entity_id(),'planned_lesson_id',null,'lesson_content','codex-test paused import','note','codex-test phase-b3 rollback')
  ),'codex-test phase-b3 rollback'
);

do $import_matrix$
begin
  if not exists(select 1 from b3_import_result where array_to_string(errors,'|') like '%STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH%billing_month=2025-06%')
     or exists(select 1 from b3_import_result where batch_committed)
     or exists(select 1 from public.school_lesson_records where import_batch_id='b3030000-0000-4000-8000-00000000c001') then
    raise exception 'STUDENT_STATUS_B3_IMPORT_ATOMIC_MATRIX_INVALID';
  end if;
end;
$import_matrix$;

do $planned_update_matrix$
declare
  v_id uuid := (select lesson_id from b3_created_plans where kind='timeline_edit');
  v_row public.school_lesson_records%rowtype;
  v_denied boolean;
begin
  select * into strict v_row from public.school_lesson_records where id=v_id;
  perform * from public.school_update_lesson_record_guarded(
    v_row.id,v_row.updated_at,v_row.lesson_date,v_row.student_id,v_row.teacher_id,v_row.subject_id,v_row.business_entity_id,
    v_row.start_time::text,v_row.end_time::text,v_row.duration_hours,v_row.unit_price,null,v_row.status,v_row.is_billable,v_row.lesson_count,
    'codex-test same month correction','codex-test phase-b3 rollback'
  );
  select * into strict v_row from public.school_lesson_records where id=v_id;
  v_denied:=false;
  begin
    perform * from public.school_update_lesson_record_guarded(
      v_row.id,v_row.updated_at,'2025-06-02',v_row.student_id,v_row.teacher_id,v_row.subject_id,v_row.business_entity_id,
      v_row.start_time::text,v_row.end_time::text,v_row.duration_hours,v_row.unit_price,null,v_row.status,v_row.is_billable,v_row.lesson_count,
      v_row.lesson_content,v_row.note
    );
  exception when sqlstate '22023' then
    if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B3_PLANNED_MONTH_MOVE_ALLOWED'; end if;

  v_denied:=false;
  begin
    perform * from public.school_update_lesson_record_guarded(
      v_row.id,v_row.updated_at,v_row.lesson_date,'b3020000-0000-4000-8000-000000000003',v_row.teacher_id,v_row.subject_id,v_row.business_entity_id,
      v_row.start_time::text,v_row.end_time::text,v_row.duration_hours,v_row.unit_price,null,v_row.status,v_row.is_billable,v_row.lesson_count,
      v_row.lesson_content,v_row.note
    );
  exception when sqlstate '22023' then
    if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B3_PLANNED_STUDENT_CHANGE_ALLOWED'; end if;
end;
$planned_update_matrix$;

-- Four existing May planned/source facts; the student is paused in June.
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,business_entity_id,
  start_time,end_time,duration_hours,lesson_content,status,is_billable,app_type,unit_price,lesson_fee,lesson_count,note
) values
 ('b3030000-0000-4000-8000-000000001001','planned','2025-05-05','2025-05','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test ordinary source','planned',true,'school',1000,2000,10,'codex-test phase-b3 rollback'),
 ('b3030000-0000-4000-8000-000000001002','planned','2025-05-12','2025-05','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test cancel source','planned',true,'school',1000,2000,11,'codex-test phase-b3 rollback'),
 ('b3030000-0000-4000-8000-000000001003','planned','2025-05-19','2025-05','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test partial source','planned',true,'school',1000,2000,12,'codex-test phase-b3 rollback'),
 ('b3030000-0000-4000-8000-000000001004','planned','2025-05-26','2025-05','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test cross-month wrapper source','pending_makeup',true,'school',1000,2000,13,'codex-test phase-b3 rollback'),
 ('b3030000-0000-4000-8000-000000001005','planned','2025-05-27','2025-05','b3020000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test direct makeup source','pending_makeup',true,'school',1000,2000,14,'codex-test phase-b3 rollback');

do $existing_fact_fulfilment_matrix$
declare
  v_ordinary uuid;
  v_partial uuid;
  v_makeup uuid;
  v_direct_makeup uuid;
begin
  select lesson_id into strict v_ordinary from public.school_create_actual_lesson_from_planned(
    'b3030000-0000-4000-8000-000000001001','2025-06-03','09:00','11:00',2,1000,null,10,'codex-test ordinary completed','codex-test phase-b3 rollback'
  );
  select a.id into strict v_partial from public.school_create_partial_completed_actual_from_planned(
    'b3030000-0000-4000-8000-000000001003','2025-06-10','09:00','10:00',1,'codex-test partial completed','codex-test phase-b3 rollback'
  ) a;
  select lesson_id into strict v_makeup from public.school_create_cross_month_makeup_completed_actual_from_planned(
    'b3030000-0000-4000-8000-000000001004','2025-06-17','09:00','10:00',1,
    null,null,false,13,'codex-test cross-month makeup','codex-test phase-b3 rollback'
  );
  select a.id into strict v_direct_makeup from public.school_create_lesson_credit_makeup_actual(
    'b3030000-0000-4000-8000-000000001005','2025-06-24',
    'b3040000-0000-4000-8000-000000000002','b3040000-0000-4000-8000-000000000001',
    '09:00','10:00',1,'codex-test direct makeup','codex-test phase-b3 rollback',14,'online','codex-test'
  ) a;
  if (select student_settlement_month from public.school_lesson_records where id=v_ordinary)<>'2025-05'
     or (select student_settlement_month from public.school_lesson_records where id=v_partial)<>'2025-05'
     or (select student_settlement_month from public.school_lesson_records where id=v_makeup)<>'2025-05'
     or (select teacher_settlement_month from public.school_lesson_records where id=v_makeup)<>'2025-06'
     or (select student_settlement_month from public.school_lesson_records where id=v_direct_makeup)<>'2025-05'
     or (select teacher_settlement_month from public.school_lesson_records where id=v_direct_makeup)<>'2025-06'
     or (select count(*) from public.school_lesson_records where planned_lesson_id='b3030000-0000-4000-8000-000000001001')<>1
     or (select count(*) from public.school_lesson_records where planned_lesson_id='b3030000-0000-4000-8000-000000001003')<>1
     or (select count(*) from public.school_lesson_records where planned_lesson_id='b3030000-0000-4000-8000-000000001004')<>1
     or (select count(*) from public.school_lesson_records where planned_lesson_id='b3030000-0000-4000-8000-000000001005')<>1 then
    raise exception 'STUDENT_STATUS_B3_EXISTING_FACT_FULFILMENT_INVALID';
  end if;
end;
$existing_fact_fulfilment_matrix$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub','b3010000-0000-4000-8000-000000000001'::uuid,'role','authenticated')::text,true);

do $cancel_paused_matrix$
declare v_actual uuid;
begin
  select lesson_id into strict v_actual from public.school_create_cancelled_actual_lesson_from_planned(
    'b3030000-0000-4000-8000-000000001002','2025-06-04','09:00','10:15',1.25,1000,11,'codex-test cancelled','codex-test phase-b3 rollback'
  );
  if not exists(
    select 1 from public.school_lesson_records a
    join public.school_lesson_records p on p.id=a.planned_lesson_id
    where a.id=v_actual and a.status='cancelled' and not a.is_billable
      and a.lesson_fee=0 and a.actual_minutes=0 and a.duration_hours=1.25
      and p.status='pending_makeup'
  ) or (select count(*) from public.school_lesson_records where planned_lesson_id='b3030000-0000-4000-8000-000000001002')<>1 then
    raise exception 'STUDENT_STATUS_B3_CANCEL_CONTRACT_INVALID';
  end if;
end;
$cancel_paused_matrix$;

do $wage_rule_matrix$
declare
  v_active_rule uuid;
  v_denied boolean;
begin
  select wage_rule_id into strict v_active_rule from public.school_create_teacher_wage_rule_config(
    'b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    'jpy_hourly',1000,0,0,0,0,true,'codex-test phase-b3 active wage rule'
  );
  v_denied:=false;
  begin
    perform * from public.school_create_teacher_wage_rule_config(
      'b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000003','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
      'jpy_hourly',1000,0,0,0,0,true,'codex-test phase-b3 paused wage rule'
    );
  exception when sqlstate '22023' then
    if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B3_WAGE_CREATE_PAUSED_ALLOWED'; end if;

  v_denied:=false;
  begin
    perform * from public.school_update_teacher_wage_rule_config(
      v_active_rule,'b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000003','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
      'jpy_hourly',1000,0,0,0,0,true,'codex-test phase-b3 change to paused student denied'
    );
  exception when sqlstate '22023' then
    if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B3_WAGE_STUDENT_CHANGE_PAUSED_ALLOWED'; end if;

  perform * from public.school_update_teacher_wage_rule_config(
    v_active_rule,'b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    'jpy_hourly',1000,0,0,0,0,false,'codex-test phase-b3 deactivate allowed'
  );
end;
$wage_rule_matrix$;
reset role;

insert into public.school_teacher_wage_rules(
  id,teacher_id,student_id,subject_id,business_entity_id,settlement_type,
  hourly_rate_jpy,hourly_rate_cny,exchange_rate,transport_fee_jpy,classroom_fee_jpy,is_active,note
) values(
  'b3060000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000003','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
  'jpy_hourly',1000,0,0,0,0,false,'codex-test phase-b3 paused disabled rule'
);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub','b3010000-0000-4000-8000-000000000001'::uuid,'role','authenticated')::text,true);
do $wage_update_matrix$
declare v_denied boolean;
begin
  perform * from public.school_update_teacher_wage_rule_config(
    'b3060000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000003','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
    'jpy_hourly',1100,0,0,0,0,false,'codex-test same paused student correction allowed'
  );
  v_denied:=false;
  begin
    perform * from public.school_update_teacher_wage_rule_config(
      'b3060000-0000-4000-8000-000000000001','b3040000-0000-4000-8000-000000000002','b3020000-0000-4000-8000-000000000003','b3040000-0000-4000-8000-000000000001',public.school_primary_business_entity_id(),
      'jpy_hourly',1100,0,0,0,0,true,'codex-test paused reactivation denied'
    );
  exception when sqlstate '22023' then
    if sqlerrm='STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH' then v_denied:=true; else raise; end if;
  end;
  if not v_denied then raise exception 'STUDENT_STATUS_B3_WAGE_REACTIVATE_PAUSED_ALLOWED'; end if;
end;
$wage_update_matrix$;
reset role;

do $tuition_closeout_matrix$
declare v_message text;
begin
  begin
    perform * from public.school_build_student_tuition_generation_snapshot(
      'b3020000-0000-4000-8000-000000000003','2026-08',0.05
    );
  exception when others then
    if sqlerrm='R2_F_B_STUDENT_INACTIVE' then raise; end if;
  end;

  begin
    perform * from public.school_preview_student_tuition_bill(
      'b3020000-0000-4000-8000-000000000004','2026-08',0.05
    );
  exception when others then
    if position('学生已停用' in sqlerrm)>0 then raise; end if;
  end;

  begin
    perform * from public.school_generate_student_tuition_bill_atomic(
      'b3020000-0000-4000-8000-000000000003','2026-08',0.05,'codex-test','codex-test'
    );
    raise exception 'STUDENT_STATUS_B3_GENERATE_GATE_UNEXPECTEDLY_OPEN';
  exception when others then
    if sqlerrm='STUDENT_STATUS_B3_GENERATE_GATE_UNEXPECTEDLY_OPEN' then raise; end if;
    if position('TUITION_GENERATE_BLOCKED' in sqlerrm)=0
       and position('blocked' in lower(sqlerrm))=0 then raise; end if;
  end;

  if lower(pg_get_functiondef('public.school_void_atomic_student_tuition_generation_core(uuid,uuid,uuid,text,text)'::regprocedure)) like '%school_students%status%'
     or lower(pg_get_functiondef('public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure)) like '%school_students%status%'
     or lower(pg_get_functiondef('public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)'::regprocedure)) like '%school_students%status%' then
    raise exception 'STUDENT_STATUS_B3_TUITION_CLOSEOUT_LEGACY_PREDICATE';
  end if;
end;
$tuition_closeout_matrix$;

do $catalog_matrix$
declare
  v_cancel regprocedure := 'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_cancel))<>'e1d7414424dada7e1a77c0130c67d159'
     or not has_function_privilege('authenticated',v_cancel,'EXECUTE')
     or has_function_privilege('anon',v_cancel,'EXECUTE')
     or has_function_privilege('service_role',v_cancel,'EXECUTE')
     or (select proconfig from pg_proc where oid=v_cancel)<>'{"search_path=pg_catalog, public"}'::text[] then
    raise exception 'STUDENT_STATUS_B3_CANCEL_METADATA_REGRESSION';
  end if;
  if has_function_privilege('authenticated','public.school_assert_student_active_at_business_month_v1(uuid,date,text)','EXECUTE')
     or has_function_privilege('anon','public.school_assert_student_active_at_business_month_v1(uuid,date,text)','EXECUTE')
     or has_function_privilege('service_role','public.school_assert_student_active_at_business_month_v1(uuid,date,text)','EXECUTE') then
    raise exception 'STUDENT_STATUS_B3_HELPER_ACL_INVALID';
  end if;
  if has_function_privilege('authenticated','public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)','EXECUTE') then
    raise exception 'STUDENT_STATUS_B3_EVENT_WRITER_REOPENED';
  end if;
  if md5(pg_get_functiondef('public.school_get_weekly_lesson_operations(date)'::regprocedure))<>'e7eac5f3bb07c31ad15e750e8721c01f' then
    raise exception 'STUDENT_STATUS_B3_WEEKLY_READER_REGRESSION';
  end if;
end;
$catalog_matrix$;

select 'STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_ROLLBACK_PASS' as result;
rollback;
