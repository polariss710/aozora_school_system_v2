-- School V2 Phase 2C-C production ROLLBACK rehearsal.
-- Fixed 2cc0... fixtures exist only inside this transaction. No real business UUID is used.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('school_phase2c_c_20260817',0));

create temporary table phase2cc_baseline(
  object_name text primary key,object_hash text not null
) on commit drop;
insert into phase2cc_baseline values
  ('raw',md5(pg_get_functiondef('public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))),
  ('remaining',md5(pg_get_functiondef('public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure))),
  ('balances',md5(pg_get_functiondef('public.school_list_student_lesson_credit_balances(uuid)'::regprocedure))),
  ('open_sources',md5(pg_get_functiondef('public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))),
  ('p0f_lines',md5(pg_get_functiondef('public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure))),
  ('p002',(select md5(to_jsonb(row_value)::text) from public.school_student_package_credit_lots row_value
    where id='2a000000-0000-4000-8000-202608170002'));

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like '2cc00000-%')
     or exists(select 1 from public.school_students where id::text like '2cc00000-%')
     or exists(select 1 from public.school_teachers where id::text like '2cc00000-%')
     or exists(select 1 from public.school_subjects where id::text like '2cc00000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '2cc00000-%')
     or exists(select 1 from public.school_student_monthly_settlements where id::text like '2cc00000-%')
     or exists(select 1 from public.school_student_settlement_lesson_variance_claims where id::text like '2cc00000-%') then
    raise exception 'PHASE2C_C_REHEARSAL_FIXTURE_COLLISION';
  end if;
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regprocedure('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)') is not null then
    raise exception 'PHASE2C_C_REHEARSAL_OBJECT_ALREADY_PRESENT';
  end if;
end
$preflight$;

\set PHASE2C_C_REHEARSAL 1
\ir school_phase2c_c_lesson_clearance_schema_migration_20260817.sql
\ir school_phase2c_c_lesson_clearance_backend_migration_20260817.sql

set local session_replication_role='replica';
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('2cc00000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-admin"}',now(),now()),
 ('2cc00000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-operator"}',now(),now()),
 ('2cc00000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-read-only"}',now(),now()),
 ('2cc00000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-inactive"}',now(),now()),
 ('2cc00000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-no-membership"}',now(),now());
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('2cc00000-0000-4000-8000-000000000001','admin',true,'2cc00000-0000-4000-8000-000000000001','2cc00000-0000-4000-8000-000000000001','codex-test Phase2C-C rehearsal'),
 ('2cc00000-0000-4000-8000-000000000002','operator',true,'2cc00000-0000-4000-8000-000000000001','2cc00000-0000-4000-8000-000000000001','codex-test Phase2C-C rehearsal'),
 ('2cc00000-0000-4000-8000-000000000003','read_only',true,'2cc00000-0000-4000-8000-000000000001','2cc00000-0000-4000-8000-000000000001','codex-test Phase2C-C rehearsal'),
 ('2cc00000-0000-4000-8000-000000000004','admin',false,'2cc00000-0000-4000-8000-000000000001','2cc00000-0000-4000-8000-000000000001','codex-test Phase2C-C rehearsal');
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('2cc00000-0000-4000-8000-00000000d001','codex-test Phase2C-C subject','codex-test',true,'codex-test Phase2C-C rehearsal','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  '2cc00000-0000-4000-8000-000000007001','codex-phase2cc','codex-test Phase2C-C teacher',
  'codex-test Phase2C-C teacher','2cc00000-0000-4000-8000-00000000d001',
  public.school_primary_business_entity_id(),'active','codex-test Phase2C-C rehearsal','school'
);
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  '2cc00000-0000-4000-8000-00000000a001','codex-phase2cc','codex-test Phase2C-C student',
  'codex-test Phase2C-C student',public.school_primary_business_entity_id(),
  'active','school',0.05,0,'codex-test Phase2C-C rehearsal'
);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,note,billing_month,
  billing_week_start_date,scheduled_lesson_date,billing_month_source,
  billing_month_decided_at
) select fixture.id,'planned',fixture.lesson_date,to_char(fixture.lesson_date,'YYYY-MM'),
  '2cc00000-0000-4000-8000-00000000a001','2cc00000-0000-4000-8000-000000007001',
  '2cc00000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),
  '09:00','11:00',2,fixture.label,fixture.status,true,'school',1000,2000,1,
  to_char(fixture.lesson_date,'YYYY-MM'),to_char(fixture.lesson_date,'YYYY-MM'),
  'codex-test Phase2C-C rehearsal',to_char(fixture.lesson_date,'YYYY-MM'),
  fixture.lesson_date,fixture.lesson_date,'explicit_billing_week_at_create',now()
from (values
  ('2cc00000-0000-4000-8000-000000001101'::uuid,date '2020-01-06','pending one','pending_makeup'),
  ('2cc00000-0000-4000-8000-000000001102'::uuid,date '2020-01-13','pending claimed','pending_makeup'),
  ('2cc00000-0000-4000-8000-000000001103'::uuid,date '2019-12-16','pending locked','pending_makeup'),
  ('2cc00000-0000-4000-8000-000000001104'::uuid,date '2020-02-03','ordinary source one','planned'),
  ('2cc00000-0000-4000-8000-000000001105'::uuid,date '2020-02-10','ordinary source two','planned')
) fixture(id,lesson_date,label,status);
insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,actual_minutes,
  lesson_content,status,is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,
  lesson_count,teacher_settlement_month,student_settlement_month,note,
  student_duration_overage_minutes,student_duration_overage_fee_jpy,
  student_duration_overage_policy_version,student_duration_overage_source,
  student_duration_overage_decided_at
) values
 ('2cc00000-0000-4000-8000-000000001201','actual','2020-02-03','2020-02',
  '2cc00000-0000-4000-8000-00000000a001','2cc00000-0000-4000-8000-000000007001',
  '2cc00000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),
  '09:00','13:00',4,240,'overage one','completed',true,'school',
  '2cc00000-0000-4000-8000-000000001104',1000,4000,1,'2020-02','2020-02',
  'codex-test Phase2C-C rehearsal',120,2000,'student_duration_overage_v1',
  'ordinary_actual_rpc',now()),
 ('2cc00000-0000-4000-8000-000000001202','actual','2020-02-04','2020-02',
  '2cc00000-0000-4000-8000-00000000a001','2cc00000-0000-4000-8000-000000007001',
  '2cc00000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),
  '09:00','11:00',2,120,'overage two','completed',true,'school',
  '2cc00000-0000-4000-8000-000000001105',1000,2000,1,'2020-02','2020-02',
  'codex-test Phase2C-C rehearsal',60,1000,'student_duration_overage_v1',
  'ordinary_actual_rpc',now());
insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,settlement_status,locked_at,note
) values
 ('2cc00000-0000-4000-8000-00000000b001','2cc00000-0000-4000-8000-00000000a001',
  '2019-12',public.school_primary_business_entity_id(),0,'locked',now(),'codex-test Phase2C-C locked'),
 ('2cc00000-0000-4000-8000-00000000b002','2cc00000-0000-4000-8000-00000000a001',
  '2020-01',public.school_primary_business_entity_id(),0,'unlocked',null,'codex-test Phase2C-C unlocked');
set local session_replication_role='origin';

savepoint phase2cc_contract_writes;
set local school.p0f_claim_writer='on';

insert into public.school_student_settlement_lesson_variance_claims(
  id,claim_batch_id,claim_batch_version,settlement_id,student_id,business_entity_id,
  year_month,source_type,source_planned_lesson_id,source_hours,source_amount_jpy,
  source_amount_cny,settlement_exchange_rate,calculation_version,
  line_manifest_sha256,claim_status,created_by
) values(
  '2cc00000-0000-4000-8000-00000000c001','2cc00000-0000-4000-8000-00000000c101',1,
  '2cc00000-0000-4000-8000-00000000b002','2cc00000-0000-4000-8000-00000000a001',
  public.school_primary_business_entity_id(),'2020-01','unused_planned_credit_v1',
  '2cc00000-0000-4000-8000-000000001102',-2,-2000,-100,0.05,
  'lesson_variance_financial_netting_v1',repeat('c',64),'active','codex-test Phase2C-C rehearsal'
);

do $claim_blocks_clearance$
begin
  begin
    perform * from public.school_create_lesson_clearance_core(
      'overtime_offset','2cc00000-0000-4000-8000-000000001102',
      '2cc00000-0000-4000-8000-000000001201',30,'2020-02-10',
      'manual_business_choice','claim first','codex-test claim first',null,
      'phase2cc-rehearsal-claim-first','2cc00000-0000-4000-8000-000000000001','admin');
    raise exception 'PHASE2C_C_EXPECTED_CLAIM_BLOCK_MISSING';
  exception when others then
    if sqlerrm='PHASE2C_C_EXPECTED_CLAIM_BLOCK_MISSING'
       or position('LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED' in sqlerrm)=0 then raise; end if;
  end;
end
$claim_blocks_clearance$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2cc00000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select * from public.school_create_lesson_clearance(
  'overtime_offset','2cc00000-0000-4000-8000-000000001101',
  '2cc00000-0000-4000-8000-000000001201',30,'2020-02-10',
  null,null,'codex-test operator unlocked',null,
  'phase2cc-rehearsal-operator-unlocked'
);
reset role;

do $clearance_blocks_claim$
begin
  begin
    insert into public.school_student_settlement_lesson_variance_claims(
      id,claim_batch_id,claim_batch_version,settlement_id,student_id,business_entity_id,
      year_month,source_type,source_planned_lesson_id,source_hours,source_amount_jpy,
      source_amount_cny,settlement_exchange_rate,calculation_version,
      line_manifest_sha256,claim_status,created_by
    ) values(
      '2cc00000-0000-4000-8000-00000000c002','2cc00000-0000-4000-8000-00000000c102',1,
      '2cc00000-0000-4000-8000-00000000b002','2cc00000-0000-4000-8000-00000000a001',
      public.school_primary_business_entity_id(),'2020-01','unused_planned_credit_v1',
      '2cc00000-0000-4000-8000-000000001101',-2,-2000,-100,0.05,
      'lesson_variance_financial_netting_v1',repeat('d',64),'active','codex-test Phase2C-C rehearsal');
    raise exception 'PHASE2C_C_EXPECTED_CLEARANCE_BLOCK_MISSING';
  exception when others then
    if sqlerrm='PHASE2C_C_EXPECTED_CLEARANCE_BLOCK_MISSING'
       or position('LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_ALLOCATED' in sqlerrm)=0 then raise; end if;
  end;
end
$clearance_blocks_claim$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2cc00000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select * from public.school_create_lesson_clearance(
  'overtime_offset','2cc00000-0000-4000-8000-000000001103',
  '2cc00000-0000-4000-8000-000000001202',30,'2020-02-10',
  'manual_business_choice','admin chose locked fixture','codex-test admin locked forward',
  null,'phase2cc-rehearsal-admin-locked'
);
reset role;

do $contract_assertions$
begin
  if (select count(*) from public.school_lesson_clearances)<>2
     or (select count(*) from public.school_lesson_clearance_details)<>2 then
    raise exception 'PHASE2C_C_REHEARSAL_CLEARANCE_COUNT_INVALID';
  end if;
  if not exists(select 1 from public.school_lesson_clearances header
    join public.school_lesson_clearance_details detail on detail.clearance_id=header.id
    where header.idempotency_key='phase2cc-rehearsal-admin-locked'
      and header.requires_forward_adjustment and header.financial_year_month='2020-02'
      and detail.forward_adjustment_direction='none'
      and detail.forward_adjustment_amount_jpy=0) then
    raise exception 'PHASE2C_C_REHEARSAL_LOCKED_FORWARD_INVALID';
  end if;
  if has_table_privilege('authenticated','public.school_lesson_clearances','INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_lesson_clearance_details','INSERT,UPDATE,DELETE') then
    raise exception 'PHASE2C_C_REHEARSAL_TABLE_DML_EXPOSED';
  end if;
  if has_function_privilege('anon','public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)','EXECUTE')
     or has_function_privilege('service_role','public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)','EXECUTE') then
    raise exception 'PHASE2C_C_REHEARSAL_WRITER_ACL_INVALID';
  end if;
end
$contract_assertions$;

rollback to savepoint phase2cc_contract_writes;
do $zero_after_contract$
begin
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details)
     or exists(select 1 from public.school_student_settlement_lesson_variance_claims
       where id::text like '2cc00000-%') then
    raise exception 'PHASE2C_C_REHEARSAL_SAVEPOINT_ROLLBACK_FAILED';
  end if;
end
$zero_after_contract$;

\ir school_phase2c_c_lesson_clearance_exact_rollback_20260817.sql

do $exact_rollback_contract$
begin
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null
     or to_regprocedure('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)') is not null then
    raise exception 'PHASE2C_C_REHEARSAL_EXACT_ROLLBACK_OBJECT_REMAINS';
  end if;
  if (select object_hash from phase2cc_baseline where object_name='raw')
       <>md5(pg_get_functiondef('public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))
     or (select object_hash from phase2cc_baseline where object_name='remaining')
       <>md5(pg_get_functiondef('public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure))
     or (select object_hash from phase2cc_baseline where object_name='balances')
       <>md5(pg_get_functiondef('public.school_list_student_lesson_credit_balances(uuid)'::regprocedure))
     or (select object_hash from phase2cc_baseline where object_name='open_sources')
       <>md5(pg_get_functiondef('public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))
     or (select object_hash from phase2cc_baseline where object_name='p0f_lines')
       <>md5(pg_get_functiondef('public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure)) then
    raise exception 'PHASE2C_C_REHEARSAL_EXACT_ROLLBACK_MD5_MISMATCH';
  end if;
  if (select object_hash from phase2cc_baseline where object_name='p002')
       <>(select md5(to_jsonb(row_value)::text) from public.school_student_package_credit_lots row_value
          where id='2a000000-0000-4000-8000-202608170002') then
    raise exception 'PHASE2C_C_REHEARSAL_P002_CHANGED';
  end if;
end
$exact_rollback_contract$;

select 'PHASE2C_C_PRODUCTION_REHEARSAL_PASS' result;
rollback;
