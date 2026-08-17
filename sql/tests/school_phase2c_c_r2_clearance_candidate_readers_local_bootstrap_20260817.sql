-- Disposable PostgreSQL only. Builds the deployed Phase 2C-C/R1 contracts locally.
\set ON_ERROR_STOP on
\ir school_phase2c_c_lesson_clearance_local_bootstrap_20260817.sql

alter table public.school_students add column display_name text;
update public.school_students set display_name=name;
alter table public.school_student_settlement_lesson_variance_claims
  add column source_hours numeric not null default 0;

create table public.school_teachers(
  id uuid primary key,name text,display_name text,updated_at timestamptz default now()
);
create table public.school_subjects(
  id uuid primary key,name text,updated_at timestamptz default now()
);

insert into public.school_teachers(id,name,display_name)
select teacher_id,'codex-test teacher '||right(teacher_id::text,4),
  'codex-test teacher '||right(teacher_id::text,4)
from public.school_lesson_records
where teacher_id is not null and teacher_id<>'71000000-0000-4000-8000-000000000099'
group by teacher_id;
insert into public.school_subjects(id,name)
select subject_id,'codex-test subject '||right(subject_id::text,4)
from public.school_lesson_records
where subject_id is not null and subject_id<>'72000000-0000-4000-8000-000000000099'
group by subject_id;

\ir ../current/school_phase2c_c_lesson_clearance_schema_migration_20260817.sql
\ir ../current/school_phase2c_c_lesson_clearance_backend_migration_20260817.sql
\ir ../current/school_phase2c_c_r1_clearance_read_contract_migration_20260817.sql

-- Synthetic gross consume/reversal facts for decomposition tests.
insert into public.school_lesson_clearances(
  id,student_id,business_entity_id,clearance_type,operation_date,
  operational_year_month,financial_year_month,requires_forward_adjustment,
  selection_mode,recommended_pending_source_id,deviated_from_recommendation,
  business_note,actor_user_id,actor_role,idempotency_key,rule_version,
  input_manifest_sha256,reverses_clearance_id
) values
 ('2c200000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001','overtime_offset','2026-02-10',
  '2026-02',null,false,'manual','30000000-0000-4000-8000-000000000001',false,
  'codex-test Phase2C-C-R2 consume','90000000-0000-4000-8000-000000000001',
  'admin','phase2cc-r2-consume','lesson_clearance_v2_same_price_v1',repeat('a',64),null),
 ('2c200000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001','reversal','2026-02-11',
  '2026-02',null,false,'manual',null,false,
  'codex-test Phase2C-C-R2 reversal','90000000-0000-4000-8000-000000000001',
  'admin','phase2cc-r2-reversal','lesson_clearance_v2_same_price_v1',repeat('b',64),
  '2c200000-0000-4000-8000-000000000001');

insert into public.school_lesson_clearance_details(
  id,clearance_id,line_no,pending_source_planned_id,overtime_source_actual_id,
  allocated_minutes,balance_effect,pending_unit_price_jpy,overtime_unit_price_jpy,
  pending_source_year_month,overtime_source_year_month,
  pending_before_minutes,pending_after_minutes,overtime_before_minutes,
  overtime_after_minutes,forward_adjustment_direction,
  forward_adjustment_amount_jpy,forward_adjustment_amount_source,
  pending_source_updated_at,pending_source_row_md5,
  overtime_source_updated_at,overtime_source_row_md5
) select
  fixture.detail_id,fixture.clearance_id,1,
  '30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000101',fixture.minutes,fixture.effect,
  10000,10000,'2026-01','2026-02',fixture.pending_before,
  fixture.pending_after,fixture.overtime_before,fixture.overtime_after,
  'none',0,'same_unit_price_zero_residual_v1',pending.updated_at,
  md5(to_jsonb(pending)::text),overtime.updated_at,md5(to_jsonb(overtime)::text)
from (values
  ('2c200000-0000-4000-8000-000000000011'::uuid,
   '2c200000-0000-4000-8000-000000000001'::uuid,30,'consume',120,90,120,90),
  ('2c200000-0000-4000-8000-000000000012'::uuid,
   '2c200000-0000-4000-8000-000000000002'::uuid,15,'restore',90,105,90,105)
) fixture(detail_id,clearance_id,minutes,effect,pending_before,pending_after,
  overtime_before,overtime_after)
cross join public.school_lesson_records pending
cross join public.school_lesson_records overtime
where pending.id='30000000-0000-4000-8000-000000000001'
  and overtime.id='40000000-0000-4000-8000-000000000101';

insert into public.school_student_settlement_lesson_variance_claims(
  id,claim_status,source_type,source_planned_lesson_id,source_actual_lesson_id,
  source_hours
) values
 ('2c200000-0000-4000-8000-000000000021','active',
  'unused_planned_credit_v1','30000000-0000-4000-8000-000000000002',null,-2),
 ('2c200000-0000-4000-8000-000000000022','active',
  'actual_duration_overage_charge_v1',null,
  '40000000-0000-4000-8000-000000000102',1);

-- One cross-month makeup actual with different source/actual teacher and subject.
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,start_time,end_time,duration_hours,unit_price,lesson_fee,is_billable,
  year_month,student_settlement_month,created_at,updated_at
) values(
  '30000000-0000-4000-8000-000000000020','planned','pending_makeup',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2026-01-20','09:00','10:00',1,10000,10000,true,'2026-01','2026-01',
  '2026-01-20 00:00+00','2026-01-20 00:00+00');
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  planned_lesson_id,lesson_date,start_time,end_time,duration_hours,actual_minutes,
  unit_price,lesson_fee,is_billable,year_month,student_settlement_month,
  teacher_settlement_month,created_at,updated_at
) values(
  '40000000-0000-4000-8000-000000000120','actual','makeup_completed',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000020','2026-02-20','13:00','14:00',1,60,
  0,0,false,'2026-02','2026-01','2026-02',
  '2026-02-20 00:00+00','2026-02-20 00:00+00');

-- Preserve a row whose teacher/subject current master name is unavailable.
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,duration_hours,unit_price,lesson_fee,is_billable,year_month,
  student_settlement_month,created_at,updated_at
) values(
  '30000000-0000-4000-8000-000000000099','planned','pending_makeup',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000099','72000000-0000-4000-8000-000000000099',
  '2026-01-30',1,10000,10000,true,'2026-01','2026-01',
  '2026-01-30 00:00+00','2026-01-30 00:00+00');
