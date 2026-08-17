-- Phase 2C-C-R1 production ROLLBACK rehearsal. Read RPCs only; no writer call.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('school_phase2c_c_r1_clearance_read_contract_20260817',0));

create temporary table phase2ccr1_baseline(name text primary key,value text) on commit drop;
insert into phase2ccr1_baseline values
  ('create_writer',md5(pg_get_functiondef('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure))),
  ('reverse_writer',md5(pg_get_functiondef('public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure))),
  ('old_preview',md5(pg_get_functiondef('public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure))),
  ('old_history',md5(pg_get_functiondef('public.school_list_lesson_clearance_history(uuid)'::regprocedure))),
  ('p002',(select md5(to_jsonb(row_value)::text) from public.school_student_package_credit_lots row_value
    where id='2a000000-0000-4000-8000-202608170002'));

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like '2c100000-%')
     or exists(select 1 from public.school_students where id::text like '2c100000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '2c100000-%')
     or exists(select 1 from public.school_lesson_clearances where id::text like '2c100000-%') then
    raise exception 'PHASE2C_C_R1_FIXTURE_COLLISION';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_R1_PRODUCTION_CLEARANCE_NOT_EMPTY';
  end if;
end
$preflight$;

\set PHASE2C_C_R1_REHEARSAL 1
\ir school_phase2c_c_r1_clearance_read_contract_migration_20260817.sql
savepoint phase2ccr1_fixture;

set local session_replication_role='replica';
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('2c100000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2ccr1-admin"}',now(),now()),
 ('2c100000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2ccr1-operator"}',now(),now()),
 ('2c100000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2ccr1-readonly"}',now(),now());
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('2c100000-0000-4000-8000-000000000001','admin',true,'2c100000-0000-4000-8000-000000000001','2c100000-0000-4000-8000-000000000001','codex-test Phase2C-C-R1 rehearsal'),
 ('2c100000-0000-4000-8000-000000000002','operator',true,'2c100000-0000-4000-8000-000000000001','2c100000-0000-4000-8000-000000000001','codex-test Phase2C-C-R1 rehearsal'),
 ('2c100000-0000-4000-8000-000000000003','read_only',true,'2c100000-0000-4000-8000-000000000001','2c100000-0000-4000-8000-000000000001','codex-test Phase2C-C-R1 rehearsal');
insert into public.school_subjects(id,name,category,is_active,note,primary_category) values
 ('2c100000-0000-4000-8000-00000000d001','codex-test R1 pending subject','codex-test',true,'codex-test R1','班课'),
 ('2c100000-0000-4000-8000-00000000d002','codex-test R1 overtime subject','codex-test',true,'codex-test R1','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values
 ('2c100000-0000-4000-8000-000000007001','codex-r1-p','codex-test R1 pending teacher','codex-test R1 pending teacher','2c100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'active','codex-test R1','school'),
 ('2c100000-0000-4000-8000-000000007002','codex-r1-o','codex-test R1 overtime teacher','codex-test R1 overtime teacher','2c100000-0000-4000-8000-00000000d002',public.school_primary_business_entity_id(),'active','codex-test R1','school');
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  '2c100000-0000-4000-8000-00000000a001','codex-r1','codex-test R1 student',
  'codex-test R1 student',public.school_primary_business_entity_id(),
  'active','school',0.05,0,'codex-test Phase2C-C-R1 rehearsal'
);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,note,billing_month,
  billing_week_start_date,scheduled_lesson_date,billing_month_source,billing_month_decided_at
) values(
  '2c100000-0000-4000-8000-000000001101','planned','2019-12-16','2019-12',
  '2c100000-0000-4000-8000-00000000a001','2c100000-0000-4000-8000-000000007001',
  '2c100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),
  '09:00','11:00',2,'codex-test R1 pending','pending_makeup',true,'school',1000,2000,1,
  '2019-12','2019-12','codex-test R1','2019-12','2019-12-16','2019-12-16',
  'explicit_billing_week_at_create',now()
);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,note,billing_month,
  billing_week_start_date,scheduled_lesson_date,billing_month_source,billing_month_decided_at
) values(
  '2c100000-0000-4000-8000-000000001102','planned','2020-02-03','2020-02',
  '2c100000-0000-4000-8000-00000000a001','2c100000-0000-4000-8000-000000007002',
  '2c100000-0000-4000-8000-00000000d002',public.school_primary_business_entity_id(),
  '09:00','13:00',4,'codex-test R1 ordinary source','planned',true,'school',1000,4000,1,
  '2020-02','2020-02','codex-test R1','2020-02','2020-02-03','2020-02-03',
  'explicit_billing_week_at_create',now()
);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,actual_minutes,
  lesson_content,status,is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,note,
  student_duration_overage_minutes,student_duration_overage_fee_jpy,
  student_duration_overage_policy_version,student_duration_overage_source,
  student_duration_overage_decided_at
) values(
  '2c100000-0000-4000-8000-000000001201','actual','2020-02-03','2020-02',
  '2c100000-0000-4000-8000-00000000a001','2c100000-0000-4000-8000-000000007002',
  '2c100000-0000-4000-8000-00000000d002',public.school_primary_business_entity_id(),
  '09:00','13:00',4,240,'codex-test R1 overage','completed',true,'school',
  '2c100000-0000-4000-8000-000000001102',1000,4000,1,
  '2020-02','2020-02','codex-test R1',120,2000,'student_duration_overage_v1',
  'ordinary_actual_rpc',now()
);
insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,settlement_status,locked_at,note
) values(
  '2c100000-0000-4000-8000-00000000b001','2c100000-0000-4000-8000-00000000a001',
  '2019-12',public.school_primary_business_entity_id(),0,'locked',now(),'codex-test R1 locked'
);

insert into public.school_lesson_clearances(
  id,student_id,business_entity_id,clearance_type,operation_date,
  operational_year_month,financial_year_month,requires_forward_adjustment,
  selection_mode,recommended_pending_source_id,deviated_from_recommendation,
  business_note,actor_user_id,actor_role,idempotency_key,rule_version,input_manifest_sha256
) values(
  '2c100000-0000-4000-8000-00000000c001','2c100000-0000-4000-8000-00000000a001',
  public.school_primary_business_entity_id(),'overtime_offset','2020-02-10','2020-02','2020-02',true,
  'manual','2c100000-0000-4000-8000-000000001101',false,'codex-test direct fixture',
  '2c100000-0000-4000-8000-000000000001','admin',
  '2c100000-0000-4000-8000-00000000f001','lesson_clearance_v2_same_price_v1',repeat('a',64)
);
insert into public.school_lesson_clearance_details(
  id,clearance_id,line_no,pending_source_planned_id,overtime_source_actual_id,
  allocated_minutes,balance_effect,pending_unit_price_jpy,overtime_unit_price_jpy,
  pending_source_year_month,overtime_source_year_month,
  pending_before_minutes,pending_after_minutes,overtime_before_minutes,overtime_after_minutes,
  forward_adjustment_direction,forward_adjustment_amount_jpy,
  forward_adjustment_amount_source,pending_source_updated_at,pending_source_row_md5,
  overtime_source_updated_at,overtime_source_row_md5
) select
  '2c100000-0000-4000-8000-00000000c101','2c100000-0000-4000-8000-00000000c001',1,
  pending.id,overtime.id,30,'consume',1000,1000,'2019-12','2020-02',120,90,120,90,
  'none',0,'same_unit_price_zero_residual_v1',pending.updated_at,md5(to_jsonb(pending)::text),
  overtime.updated_at,md5(to_jsonb(overtime)::text)
from public.school_lesson_records pending,public.school_lesson_records overtime
where pending.id='2c100000-0000-4000-8000-000000001101'
  and overtime.id='2c100000-0000-4000-8000-000000001201';
set local session_replication_role='origin';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2c100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.school_preview_lesson_clearance_v2(
  '2c100000-0000-4000-8000-00000000f002','overtime_offset',
  '2c100000-0000-4000-8000-000000001101','2c100000-0000-4000-8000-000000001201',
  30,'2020-03-10',null,null,'codex-test read Preview',null
) admin_preview \gset r1_admin_
select public.school_preview_lesson_clearance_reversal_v1(
  '2c100000-0000-4000-8000-00000000f003',
  '2c100000-0000-4000-8000-00000000c001','2020-04-01'
) reversal_preview \gset r1_reverse_
select public.school_list_lesson_clearance_history_v2(
  '2c100000-0000-4000-8000-00000000a001'
) history \gset r1_history_
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2c100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.school_preview_lesson_clearance_v2(
  '2c100000-0000-4000-8000-00000000f004','overtime_offset',
  '2c100000-0000-4000-8000-000000001101','2c100000-0000-4000-8000-000000001201',
  30,'2020-03-10',null,null,'codex-test operator Preview',null
) operator_preview \gset r1_operator_
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2c100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select public.school_preview_lesson_clearance_v2(
  '2c100000-0000-4000-8000-00000000f005','overtime_offset',
  '2c100000-0000-4000-8000-000000001101','2c100000-0000-4000-8000-000000001201',
  30,'2020-03-10',null,null,'codex-test read-only Preview',null
) readonly_preview \gset r1_readonly_
reset role;

select 1 / case when
  (:'r1_admin_admin_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and (:'r1_admin_admin_preview'::jsonb->'comparison'->>'cross_teacher')::boolean
  and (:'r1_admin_admin_preview'::jsonb->'comparison'->>'cross_subject')::boolean
  and :'r1_admin_admin_preview'::jsonb->'financial'->>'forward_destination_month'='2020-03'
  then 1 else 0 end admin_preview_assertion;
select 1 / case when
  not (:'r1_operator_operator_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and :'r1_operator_operator_preview'::jsonb->'authorization'->>'blocker_code'
    ='LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED'
  then 1 else 0 end operator_preview_assertion;
select 1 / case when
  not (:'r1_readonly_readonly_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and :'r1_readonly_readonly_preview'::jsonb->'authorization'->>'blocker_code'
    ='LESSON_CLEARANCE_ROLE_REQUIRED'
  then 1 else 0 end readonly_preview_assertion;
select 1 / case when
  has_function_privilege(
    'authenticated','public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)','EXECUTE'
  )
  and has_function_privilege(
    'authenticated','public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)','EXECUTE'
  )
  and has_function_privilege(
    'authenticated','public.school_list_lesson_clearance_history_v2(uuid)','EXECUTE'
  )
  and not has_function_privilege(
    'anon','public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)','EXECUTE'
  )
  and not has_function_privilege(
    'service_role','public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)','EXECUTE'
  )
  then 1 else 0 end acl_assertion;
select 1 / case when
  (:'r1_reverse_reversal_preview'::jsonb->'authorization'->>'can_reverse')::boolean
  and :'r1_reverse_reversal_preview'::jsonb->'forward'->>'forward_destination_month'='2020-04'
  then 1 else 0 end reversal_preview_assertion;
select 1 / case when jsonb_array_length(:'r1_history_history'::jsonb)=1
  and (:'r1_history_history'::jsonb->0->>'cross_teacher')::boolean
  and :'r1_history_history'::jsonb->0->>'source_lock_evidence_status'='unavailable'
  then 1 else 0 end history_assertion;
select 1 / case when (select count(*) from public.school_lesson_clearances)=1
  and (select count(*) from public.school_lesson_clearance_details)=1
  then 1 else 0 end reader_zero_write_assertion;

select jsonb_pretty(:'r1_admin_admin_preview'::jsonb) clearance_preview_v2_sample;
select jsonb_pretty(:'r1_reverse_reversal_preview'::jsonb) reversal_preview_v1_sample;
select jsonb_pretty(:'r1_history_history'::jsonb) history_v2_sample;

rollback to savepoint phase2ccr1_fixture;
do $fixture_zero$
begin
  if exists(select 1 from auth.users where id::text like '2c100000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '2c100000-%')
     or exists(select 1 from public.school_lesson_clearances where id::text like '2c100000-%') then
    raise exception 'PHASE2C_C_R1_FIXTURE_ROLLBACK_FAILED';
  end if;
end
$fixture_zero$;

\ir school_phase2c_c_r1_clearance_read_contract_exact_rollback_20260817.sql
\unset PHASE2C_C_R1_REHEARSAL

do $exact_rollback$
begin
  if to_regprocedure('public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)') is not null
     or to_regprocedure('public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_history_v2(uuid)') is not null then
    raise exception 'PHASE2C_C_R1_REHEARSAL_NEW_FUNCTION_RESIDUE';
  end if;
  if md5(pg_get_functiondef('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure))
       <> (select value from phase2ccr1_baseline where name='create_writer')
     or md5(pg_get_functiondef('public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure))
       <> (select value from phase2ccr1_baseline where name='reverse_writer')
     or md5(pg_get_functiondef('public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure))
       <> (select value from phase2ccr1_baseline where name='old_preview')
     or md5(pg_get_functiondef('public.school_list_lesson_clearance_history(uuid)'::regprocedure))
       <> (select value from phase2ccr1_baseline where name='old_history') then
    raise exception 'PHASE2C_C_R1_REHEARSAL_OLD_FUNCTION_CHANGED';
  end if;
  if (select md5(to_jsonb(row_value)::text) from public.school_student_package_credit_lots row_value
      where id='2a000000-0000-4000-8000-202608170002')
      <> (select value from phase2ccr1_baseline where name='p002') then
    raise exception 'PHASE2C_C_R1_REHEARSAL_P002_CHANGED';
  end if;
end
$exact_rollback$;

select 'PHASE2C_C_R1_PRODUCTION_REHEARSAL_PASS' result;
rollback;
