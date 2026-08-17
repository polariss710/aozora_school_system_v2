-- Phase 2C-C-R2 production ROLLBACK rehearsal.
-- 2c22... fixture UUIDs exist only in this transaction. No writer is called.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('school_phase2c_c_r2_20260817',0));

create temporary table phase2c_c_r2_baseline(
  object_name text primary key,row_count bigint,row_hash text
) on commit drop;
insert into phase2c_c_r2_baseline
select object_name,row_count,row_hash from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
    from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'clearances',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_clearances x
  union all select 5,'clearance_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_clearance_details x
  union all select 6,'package_lots',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_package_credit_lots x
) baseline order by sort_order;

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like '2c220000-%')
     or exists(select 1 from public.school_students where id::text like '2c220000-%')
     or exists(select 1 from public.school_teachers where id::text like '2c220000-%')
     or exists(select 1 from public.school_subjects where id::text like '2c220000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '2c220000-%')
     or exists(select 1 from public.school_student_monthly_settlements where id::text like '2c220000-%')
     or exists(select 1 from public.school_student_settlement_lesson_variance_claims where id::text like '2c220000-%')
     or exists(select 1 from public.school_lesson_clearances where id::text like '2c220000-%') then
    raise exception 'PHASE2C_C_R2_REHEARSAL_FIXTURE_COLLISION';
  end if;
end
$preflight$;

\set PHASE2C_C_R2_REHEARSAL 1
\ir school_phase2c_c_r2_clearance_candidate_readers_migration_20260817.sql

set local session_replication_role='replica';
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('2c220000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-r2-admin"}',now(),now()),
 ('2c220000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-r2-operator"}',now(),now()),
 ('2c220000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-r2-readonly"}',now(),now()),
 ('2c220000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-r2-inactive"}',now(),now()),
 ('2c220000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"phase2cc-r2-no-membership"}',now(),now());
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('2c220000-0000-4000-8000-000000000001','admin',true,'2c220000-0000-4000-8000-000000000001','2c220000-0000-4000-8000-000000000001','codex-test Phase2C-C-R2 rehearsal'),
 ('2c220000-0000-4000-8000-000000000002','operator',true,'2c220000-0000-4000-8000-000000000001','2c220000-0000-4000-8000-000000000001','codex-test Phase2C-C-R2 rehearsal'),
 ('2c220000-0000-4000-8000-000000000003','read_only',true,'2c220000-0000-4000-8000-000000000001','2c220000-0000-4000-8000-000000000001','codex-test Phase2C-C-R2 rehearsal'),
 ('2c220000-0000-4000-8000-000000000004','admin',false,'2c220000-0000-4000-8000-000000000001','2c220000-0000-4000-8000-000000000001','codex-test Phase2C-C-R2 rehearsal');
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values
 ('2c220000-0000-4000-8000-00000000d001','codex-test Phase2C-C-R2 subject A','codex-test',true,'codex-test Phase2C-C-R2','班课'),
 ('2c220000-0000-4000-8000-00000000d002','codex-test Phase2C-C-R2 subject B','codex-test',true,'codex-test Phase2C-C-R2','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,
  status,note,app_type
) values
 ('2c220000-0000-4000-8000-000000007001','codex-phase2cc-r2-a','codex-test Phase2C-C-R2 teacher A','codex-test Phase2C-C-R2 teacher A','2c220000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'active','codex-test Phase2C-C-R2','school'),
 ('2c220000-0000-4000-8000-000000007002','codex-phase2cc-r2-b','codex-test Phase2C-C-R2 teacher B','codex-test Phase2C-C-R2 teacher B','2c220000-0000-4000-8000-00000000d002',public.school_primary_business_entity_id(),'active','codex-test Phase2C-C-R2','school');
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  '2c220000-0000-4000-8000-00000000a001','codex-phase2cc-r2','codex-test Phase2C-C-R2 student','codex-test Phase2C-C-R2 student',public.school_primary_business_entity_id(),'active','school',0.05,0,'codex-test Phase2C-C-R2');

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,note,billing_month,
  billing_week_start_date,scheduled_lesson_date,billing_month_source,
  billing_month_decided_at,created_at,updated_at
) select fixture.id,'planned',fixture.lesson_date,to_char(fixture.lesson_date,'YYYY-MM'),
  '2c220000-0000-4000-8000-00000000a001',fixture.teacher_id,fixture.subject_id,
  public.school_primary_business_entity_id(),'09:00','11:00',fixture.hours,
  fixture.label,fixture.status,true,'school',1000,1000*fixture.hours,1,
  to_char(fixture.lesson_date,'YYYY-MM'),to_char(fixture.lesson_date,'YYYY-MM'),
  'codex-test Phase2C-C-R2',to_char(fixture.lesson_date,'YYYY-MM'),
  date_trunc('week',fixture.lesson_date::timestamp)::date,
  fixture.lesson_date,'explicit_billing_week_at_create',now(),fixture.created_at,fixture.created_at
from (values
  ('2c220000-0000-4000-8000-000000001101'::uuid,date '2020-01-06',2::numeric,'pending decomposed','pending_makeup','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2020-01-06 00:00+00'::timestamptz),
  ('2c220000-0000-4000-8000-000000001102'::uuid,date '2020-01-13',2::numeric,'pending claimed','pending_makeup','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2020-01-13 00:00+00'::timestamptz),
  ('2c220000-0000-4000-8000-000000001103'::uuid,date '2019-12-16',2::numeric,'pending locked','pending_makeup','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2019-12-16 00:00+00'::timestamptz),
  ('2c220000-0000-4000-8000-000000001104'::uuid,date '2020-02-03',2::numeric,'ordinary overage source','planned','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2020-02-03 00:00+00'::timestamptz),
  ('2c220000-0000-4000-8000-000000001106'::uuid,date '2020-02-04',1::numeric,'claimed overage source','planned','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2020-02-04 00:00+00'::timestamptz),
  ('2c220000-0000-4000-8000-000000001105'::uuid,date '2019-12-20',2::numeric,'cross-month source','pending_makeup','2c220000-0000-4000-8000-000000007001'::uuid,'2c220000-0000-4000-8000-00000000d001'::uuid,'2019-12-20 00:00+00'::timestamptz)
) fixture(id,lesson_date,hours,label,status,teacher_id,subject_id,created_at);

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,actual_minutes,
  lesson_content,status,is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,
  lesson_count,teacher_settlement_month,student_settlement_month,note,
  student_duration_overage_minutes,student_duration_overage_fee_jpy,
  student_duration_overage_policy_version,student_duration_overage_source,
  student_duration_overage_decided_at,created_at,updated_at
) values
 ('2c220000-0000-4000-8000-000000001201','actual','2020-01-06','2020-01','2c220000-0000-4000-8000-00000000a001','2c220000-0000-4000-8000-000000007001','2c220000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,0,'cancelled source','cancelled',false,'school','2c220000-0000-4000-8000-000000001101',0,0,1,'2020-01','2020-01','codex-test Phase2C-C-R2',null,null,null,null,null,'2020-01-06 01:00+00','2020-01-06 01:00+00'),
 ('2c220000-0000-4000-8000-000000001202','actual','2020-01-07','2020-01','2c220000-0000-4000-8000-00000000a001','2c220000-0000-4000-8000-000000007001','2c220000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','09:30',0.5,30,'makeup consume','makeup_completed',false,'school','2c220000-0000-4000-8000-000000001101',0,0,1,'2020-01','2020-01','codex-test Phase2C-C-R2',null,null,null,null,null,'2020-01-07 01:00+00','2020-01-07 01:00+00'),
 ('2c220000-0000-4000-8000-000000001203','actual','2020-02-03','2020-02','2c220000-0000-4000-8000-00000000a001','2c220000-0000-4000-8000-000000007001','2c220000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','13:00',4,240,'overage source','completed',true,'school','2c220000-0000-4000-8000-000000001104',1000,4000,1,'2020-02','2020-02','codex-test Phase2C-C-R2',120,2000,'student_duration_overage_v1','ordinary_actual_rpc',now(),'2020-02-03 01:00+00','2020-02-03 01:00+00'),
 ('2c220000-0000-4000-8000-000000001204','actual','2020-02-04','2020-02','2c220000-0000-4000-8000-00000000a001','2c220000-0000-4000-8000-000000007001','2c220000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','12:00',3,180,'overage claimed','completed',true,'school','2c220000-0000-4000-8000-000000001106',1000,3000,1,'2020-02','2020-02','codex-test Phase2C-C-R2',60,1000,'student_duration_overage_v1','ordinary_actual_rpc',now(),'2020-02-04 01:00+00','2020-02-04 01:00+00'),
 ('2c220000-0000-4000-8000-000000001205','actual','2020-02-20','2020-02','2c220000-0000-4000-8000-00000000a001','2c220000-0000-4000-8000-000000007002','2c220000-0000-4000-8000-00000000d002',public.school_primary_business_entity_id(),'13:00','14:00',1,60,'cross-month makeup','makeup_completed',false,'school','2c220000-0000-4000-8000-000000001105',0,0,1,'2020-02','2019-12','codex-test Phase2C-C-R2',null,null,null,null,null,'2020-02-20 01:00+00','2020-02-20 01:00+00');

insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,
  settlement_status,locked_at,note
) values
 ('2c220000-0000-4000-8000-00000000b001','2c220000-0000-4000-8000-00000000a001','2019-12',public.school_primary_business_entity_id(),0,'locked',now(),'codex-test Phase2C-C-R2 locked'),
 ('2c220000-0000-4000-8000-00000000b002','2c220000-0000-4000-8000-00000000a001','2020-01',public.school_primary_business_entity_id(),0,'unlocked',null,'codex-test Phase2C-C-R2 unlocked'),
 ('2c220000-0000-4000-8000-00000000b003','2c220000-0000-4000-8000-00000000a001','2020-02',public.school_primary_business_entity_id(),0,'unlocked',null,'codex-test Phase2C-C-R2 unlocked');
set local session_replication_role='origin';

insert into public.school_lesson_clearances(
  id,student_id,business_entity_id,clearance_type,operation_date,
  operational_year_month,financial_year_month,requires_forward_adjustment,
  selection_mode,recommended_pending_source_id,deviated_from_recommendation,
  business_note,actor_user_id,actor_role,idempotency_key,reverses_clearance_id,
  rule_version,input_manifest_sha256
) values
 ('2c220000-0000-4000-8000-00000000e001','2c220000-0000-4000-8000-00000000a001',public.school_primary_business_entity_id(),'overtime_offset','2020-02-10','2020-02',null,false,'manual','2c220000-0000-4000-8000-000000001101',false,'codex-test Phase2C-C-R2 consume','2c220000-0000-4000-8000-000000000001','admin','phase2cc-r2-consume',null,'lesson_clearance_v2_same_price_v1',repeat('a',64)),
 ('2c220000-0000-4000-8000-00000000e002','2c220000-0000-4000-8000-00000000a001',public.school_primary_business_entity_id(),'reversal','2020-02-11','2020-02',null,false,'manual',null,false,'codex-test Phase2C-C-R2 reversal','2c220000-0000-4000-8000-000000000001','admin','phase2cc-r2-reversal','2c220000-0000-4000-8000-00000000e001','lesson_clearance_v2_same_price_v1',repeat('b',64));
insert into public.school_lesson_clearance_details(
  id,clearance_id,line_no,pending_source_planned_id,overtime_source_actual_id,
  allocated_minutes,balance_effect,pending_unit_price_jpy,overtime_unit_price_jpy,
  pending_source_year_month,overtime_source_year_month,pending_before_minutes,
  pending_after_minutes,overtime_before_minutes,overtime_after_minutes,
  forward_adjustment_direction,forward_adjustment_amount_jpy,
  forward_adjustment_amount_source,pending_source_updated_at,
  pending_source_row_md5,overtime_source_updated_at,overtime_source_row_md5
) select fixture.detail_id,fixture.clearance_id,1,
  '2c220000-0000-4000-8000-000000001101','2c220000-0000-4000-8000-000000001203',
  fixture.minutes,fixture.effect,1000,1000,'2020-01','2020-02',
  fixture.pending_before,fixture.pending_after,fixture.overtime_before,
  fixture.overtime_after,'none',0,'same_unit_price_zero_residual_v1',
  pending.updated_at,md5(to_jsonb(pending)::text),overtime.updated_at,
  md5(to_jsonb(overtime)::text)
from (values
  ('2c220000-0000-4000-8000-00000000f001'::uuid,'2c220000-0000-4000-8000-00000000e001'::uuid,30,'consume',90,60,120,90),
  ('2c220000-0000-4000-8000-00000000f002'::uuid,'2c220000-0000-4000-8000-00000000e002'::uuid,15,'restore',60,75,90,105)
) fixture(detail_id,clearance_id,minutes,effect,pending_before,pending_after,
  overtime_before,overtime_after)
cross join public.school_lesson_records pending
cross join public.school_lesson_records overtime
where pending.id='2c220000-0000-4000-8000-000000001101'
  and overtime.id='2c220000-0000-4000-8000-000000001203';

set local school.p0f_claim_writer='on';
insert into public.school_student_settlement_lesson_variance_claims(
  id,claim_batch_id,claim_batch_version,settlement_id,student_id,business_entity_id,
  year_month,source_type,source_planned_lesson_id,source_actual_lesson_id,
  source_hours,source_amount_jpy,source_amount_cny,settlement_exchange_rate,
  calculation_version,line_manifest_sha256,claim_status,created_by
) values
 ('2c220000-0000-4000-8000-00000000c001','2c220000-0000-4000-8000-00000000c101',1,'2c220000-0000-4000-8000-00000000b002','2c220000-0000-4000-8000-00000000a001',public.school_primary_business_entity_id(),'2020-01','unused_planned_credit_v1','2c220000-0000-4000-8000-000000001102',null,-2,-2000,-100,0.05,'lesson_variance_financial_netting_v1',repeat('c',64),'active','codex-test Phase2C-C-R2'),
 ('2c220000-0000-4000-8000-00000000c002','2c220000-0000-4000-8000-00000000c102',1,'2c220000-0000-4000-8000-00000000b003','2c220000-0000-4000-8000-00000000a001',public.school_primary_business_entity_id(),'2020-02','actual_duration_overage_charge_v1',null,'2c220000-0000-4000-8000-000000001204',1,1000,50,0.05,'lesson_variance_financial_netting_v1',repeat('d',64),'active','codex-test Phase2C-C-R2');

select set_config('request.jwt.claims','{"sub":"2c220000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create temporary table phase2c_c_r2_payloads(
  payload_name text primary key,payload jsonb not null
) on commit drop;
insert into phase2c_c_r2_payloads values
 ('pending',public.school_list_lesson_clearance_pending_balances_v2(
   '2c220000-0000-4000-8000-00000000a001',true)),
 ('overage',public.school_list_lesson_clearance_available_overages_v2(
   '2c220000-0000-4000-8000-00000000a001',true)),
 ('cross',public.school_list_cross_month_makeup_projection_v2(
   '2c220000-0000-4000-8000-00000000a001',null)),
 ('package',public.school_list_student_package_credit_lots_v2(null)),
 ('summary',public.school_get_lesson_clearance_dashboard_summary_v1(
   '2c220000-0000-4000-8000-00000000a001')),
 ('preview',public.school_preview_lesson_clearance_v2(
   '2c220000-0000-4000-8000-000000000010','overtime_offset',
   '2c220000-0000-4000-8000-000000001101','2c220000-0000-4000-8000-000000001203',
   15,'2020-02-12',null,null,'codex-test Phase2C-C-R2 preview',null));

do $payload_assertions$
declare
  v_pending jsonb;
  v_overage jsonb;
  v_cross jsonb;
  v_package jsonb;
  v_summary jsonb;
  v_preview jsonb;
  v_row jsonb;
begin
  select payload into strict v_pending from phase2c_c_r2_payloads where payload_name='pending';
  select payload into strict v_overage from phase2c_c_r2_payloads where payload_name='overage';
  select payload into strict v_cross from phase2c_c_r2_payloads where payload_name='cross';
  select payload into strict v_package from phase2c_c_r2_payloads where payload_name='package';
  select payload into strict v_summary from phase2c_c_r2_payloads where payload_name='summary';
  select payload into strict v_preview from phase2c_c_r2_payloads where payload_name='preview';
  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='2c220000-0000-4000-8000-000000001101';
  if (v_row->>'initial_credit_minutes')::int<>120
     or (v_row->>'makeup_consumed_minutes')::int<>30
     or (v_row->>'clearance_allocated_minutes')::int<>30
     or (v_row->>'clearance_reversed_minutes')::int<>15
     or (v_row->>'remaining_minutes')::int<>75
     or not (v_row->>'balance_matches_writer_helper')::boolean
     or v_row->>'source_row_md5'<>(select md5(to_jsonb(x)::text)
       from public.school_lesson_records x
       where x.id='2c220000-0000-4000-8000-000000001101') then
    raise exception 'PHASE2C_C_R2_REHEARSAL_PENDING_INVALID:%',v_row;
  end if;
  select item into strict v_row from jsonb_array_elements(v_overage->'items') item
  where item->>'overtime_source_actual_id'='2c220000-0000-4000-8000-000000001203';
  if (v_row->>'frozen_overtime_minutes')::int<>120
     or (v_row->>'clearance_allocated_minutes')::int<>30
     or (v_row->>'clearance_reversed_minutes')::int<>15
     or (v_row->>'available_minutes')::int<>105
     or not (v_row->>'balance_matches_writer_helper')::boolean then
    raise exception 'PHASE2C_C_R2_REHEARSAL_OVERAGE_INVALID:%',v_row;
  end if;
  if (v_cross->'summary'->>'distinct_actual_count')::int<>1
     or v_cross->'items'->0->>'actual_lesson_id'<>'2c220000-0000-4000-8000-000000001205'
     or v_cross->'items'->0->>'source_teacher_id'=v_cross->'items'->0->>'actual_teacher_id'
     or v_cross->'items'->0->>'source_subject_id'=v_cross->'items'->0->>'actual_subject_id' then
    raise exception 'PHASE2C_C_R2_REHEARSAL_CROSS_INVALID:%',v_cross;
  end if;
  if v_package->'summary'->>'remaining_minutes'<>'1200'
     or (v_package->'items'->0->>'can_consume')::boolean
     or (v_package->'items'->0->>'can_reserve')::boolean then
    raise exception 'PHASE2C_C_R2_REHEARSAL_PACKAGE_INVALID:%',v_package;
  end if;
  if v_summary->>'history_count'<>'2'
     or v_preview->>'request_identity'<>'2c220000-0000-4000-8000-000000000010'
     or not (v_preview->>'writer_revalidation_required')::boolean then
    raise exception 'PHASE2C_C_R2_REHEARSAL_REGRESSION_INVALID';
  end if;
end
$payload_assertions$;

-- Active operator and read_only can read every new contract.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"2c220000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.school_get_lesson_clearance_dashboard_summary_v1(null) is not null operator_read;
select set_config('request.jwt.claims','{"sub":"2c220000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select public.school_get_lesson_clearance_dashboard_summary_v1(null) is not null read_only_read;
reset role;

do $negative_roles$
declare v_actor uuid;v_expected text;v_error text;
begin
  for v_actor,v_expected in select * from (values
    ('2c220000-0000-4000-8000-000000000004'::uuid,'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('2c220000-0000-4000-8000-000000000005'::uuid,'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED')
  ) denied(actor,expected) loop
    perform set_config('request.jwt.claims',jsonb_build_object(
      'sub',v_actor,'role','authenticated')::text,true);
    set local role authenticated;
    begin
      perform public.school_get_lesson_clearance_dashboard_summary_v1(null);
      raise exception 'PHASE2C_C_R2_REHEARSAL_DENIAL_MISSING';
    exception when others then
      get stacked diagnostics v_error=message_text;
      if v_error='PHASE2C_C_R2_REHEARSAL_DENIAL_MISSING'
         or position(v_expected in v_error)=0 then raise; end if;
    end;
    reset role;
  end loop;
end
$negative_roles$;

do $acl$
declare v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure,
    'public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)'::regprocedure,
    'public.school_list_student_package_credit_lots_v2(uuid)'::regprocedure,
    'public.school_list_cross_month_makeup_projection_v2(uuid,text)'::regprocedure,
    'public.school_get_lesson_clearance_dashboard_summary_v1(uuid)'::regprocedure
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE')
       or not has_function_privilege('authenticated',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_R2_REHEARSAL_ACL_INVALID:%',v_signature;
    end if;
  end loop;
end
$acl$;

\set PHASE2C_C_R2_ROLLBACK_IN_EXISTING_TRANSACTION 1
\ir school_phase2c_c_r2_clearance_candidate_readers_exact_rollback_20260817.sql

rollback;
