-- Historical zero-carry evidence / effective wage resolver rollback-only matrix.
-- All business fixtures use fixed 8909... codex-test IDs and always roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
\ir school_historical_zero_carry_completion_schema_20260809.sql
\ir school_historical_zero_carry_completion_rpcs_20260809.sql

do $fixture_preflight$
begin
  if exists(select 1 from auth.users where id::text like '89090000-%')
     or exists(select 1 from public.school_business_entities where id::text like '89090000-%')
     or exists(select 1 from public.school_students where id::text like '89090000-%')
     or exists(select 1 from public.school_lesson_records where id::text like '89090000-%')
     or exists(select 1 from public.school_student_monthly_settlement_historical_completion_evidence where id::text like '89090000-%') then
    raise exception 'HISTORICAL_ZERO_CARRY_FIXTURE_ID_COLLISION';
  end if;
end
$fixture_preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('89090000-0000-4000-8000-000000000001','authenticated','authenticated',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"codex_test":"historical-zero-carry-admin"}'::jsonb,now(),now());
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values(
  '89090000-0000-4000-8000-000000000001','admin',true,
  '89090000-0000-4000-8000-000000000001','89090000-0000-4000-8000-000000000001',
  'codex-test historical zero-carry rollback'
);

set local session_replication_role='replica';
insert into public.school_business_entities(id,code,name,entity_type,default_currency,is_active,note)
values
  ('89090000-0000-4000-8000-00000000e001','codex-test-hzc-a','codex-test HZC entity A','company','JPY',true,'codex-test historical zero-carry rollback'),
  ('89090000-0000-4000-8000-00000000e002','codex-test-hzc-b','codex-test HZC entity B','company','JPY',true,'codex-test historical zero-carry rollback');
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values
  ('89090000-0000-4000-8000-00000000d001','codex-test HZC no wage subject','codex-test',true,'codex-test historical zero-carry rollback','班课'),
  ('89090000-0000-4000-8000-00000000d002','codex-test HZC paid subject','codex-test',true,'codex-test historical zero-carry rollback','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  '89090000-0000-4000-8000-000000007001','codex-test-hzc-teacher',
  'codex-test HZC teacher','codex-test HZC teacher','89090000-0000-4000-8000-00000000d001',
  '89090000-0000-4000-8000-00000000e001','active','codex-test historical zero-carry rollback','school'
);
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values
  ('89090000-0000-4000-8000-00000000a001','codex-test-hzc-wage','codex-test HZC wage','codex-test HZC wage','89090000-0000-4000-8000-00000000e001','active','school',0.05,0,'codex-test historical zero-carry rollback'),
  ('89090000-0000-4000-8000-00000000a002','codex-test-hzc-consumed','codex-test HZC consumed','codex-test HZC consumed','89090000-0000-4000-8000-00000000e001','active','school',0.05,0,'codex-test historical zero-carry rollback'),
  ('89090000-0000-4000-8000-00000000a003','codex-test-hzc-incomplete','codex-test HZC incomplete','codex-test HZC incomplete','89090000-0000-4000-8000-00000000e001','active','school',0.05,0,'codex-test historical zero-carry rollback');

insert into public.school_income_records(
  id,business_entity_id,student_id,income_date,year_month,settlement_month,
  income_category,description,currency,amount,amount_jpy,amount_cny,payment_currency,
  status,is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
  cash_submission_blocked,operational_excluded
) values(
  '89090000-0000-4000-8000-00000000f001','89090000-0000-4000-8000-00000000e001',
  '89090000-0000-4000-8000-00000000a001','2020-08-01','2020-08','2020-08',
  'tuition','codex-test historical zero-carry rollback','JPY',1000,1000,50,'CNY',
  'received',false,'codex-test',true,'codex-test historical zero-carry rollback','school',false,false
);
insert into public.school_student_tuition_bills(
  id,student_id,business_entity_id,billing_month,previous_settlement_month,
  previous_settlement_id,previous_carryover_cny,planned_lesson_count,
  planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
  income_record_id,source_snapshot,note,app_type,billing_exchange_rate,
  billing_amount_cny,billing_amount_calculated_at,billing_role,cash_submission_blocked,
  income_created_at
) values(
  '89090000-0000-4000-8000-000000006001','89090000-0000-4000-8000-00000000a001',
  '89090000-0000-4000-8000-00000000e001','2020-08','2020-07',null,0,1,1,1000,1000,
  'JPY','income_created','89090000-0000-4000-8000-00000000f001','{}'::jsonb,
  'codex-test historical zero-carry rollback','school',0.05,50,now(),'canonical_charge',false,now()
);
insert into public.school_student_tuition_billing_identities(
  id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
) values(
  '89090000-0000-4000-8000-000000002001','89090000-0000-4000-8000-00000000a001','2020-08',
  '89090000-0000-4000-8000-000000006001','codex-test:hzc:identity:1','atomic_charge',
  'codex-test historical zero-carry rollback','{}'::jsonb
);
insert into public.school_student_tuition_generation_identities(
  id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
) values(
  '89090000-0000-4000-8000-000000003001','89090000-0000-4000-8000-00000000a001',
  '89090000-0000-4000-8000-00000000e001','2020-08-01','89090000-0000-4000-8000-000000002001',
  now(),'codex-test historical zero-carry rollback'
);
insert into public.school_student_tuition_generation_revisions(
  id,generation_identity_id,tuition_bill_id,revision_no,generation_manifest_sha256,
  manifest_kind,lifecycle_status,created_at,created_by_authority,activated_at
) values(
  '89090000-0000-4000-8000-000000004001','89090000-0000-4000-8000-000000003001',
  '89090000-0000-4000-8000-000000006001',1,repeat('8',64),'atomic_generation_v1','active',
  now(),'codex-test historical zero-carry rollback',now()
);
insert into public.school_personal_cash_income_linkage_events
select (jsonb_populate_record(
  null::public.school_personal_cash_income_linkage_events,
  to_jsonb(e) || jsonb_build_object(
    'id','89090000-0000-4000-8000-000000005001',
    'source_table','school_income_records',
    'source_id','89090000-0000-4000-8000-00000000f001',
    'source_event_type','tuition_income_received',
    'income_record_id','89090000-0000-4000-8000-00000000f001',
    'business_entity_id','89090000-0000-4000-8000-00000000e001',
    'cash_transaction_table','home_cny_transactions',
    'cash_transaction_id','89090000-0000-4000-8000-000000009001',
    'currency','JPY','amount',1000,
    'idempotency_key','codex-test:hzc:cash:1','sync_status','synced','retry_count',0,
    'note','codex-test historical zero-carry rollback','synced_at',now(),
    'payment_currency','CNY','payment_exchange_rate',0.05,'payment_amount',50,
    'attempt_no',1,'cash_request_id','89090000-0000-4000-8000-000000008001',
    'cash_request_status','approved','requested_at',now(),'confirmed_at',now(),
    'rejected_at',null,'rejected_reason',null,'last_error',null
  )
)).*
from public.school_personal_cash_income_linkage_events e
where e.cash_transaction_table='home_cny_transactions'
  and e.sync_status='synced' and e.cash_request_status='approved'
order by e.created_at
limit 1;

insert into public.school_student_monthly_settlements(
  id,student_id,year_month,business_entity_id,carryover_amount_cny,settlement_status,locked_at,note
) values
  ('89090000-0000-4000-8000-00000000b001','89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e002',0,'locked',now(),'codex-test cross-entity only'),
  ('89090000-0000-4000-8000-00000000b002','89090000-0000-4000-8000-00000000a002','2020-06','89090000-0000-4000-8000-00000000e001',0,'unlocked',null,'codex-test consumed');
insert into public.school_student_tuition_bills(
  id,student_id,business_entity_id,billing_month,previous_settlement_month,
  previous_settlement_id,previous_carryover_cny,planned_lesson_count,
  planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
  source_snapshot,note,app_type,billing_role,cash_submission_blocked
) values(
  '89090000-0000-4000-8000-000000006002','89090000-0000-4000-8000-00000000a002',
  '89090000-0000-4000-8000-00000000e001','2020-07','2020-06',
  '89090000-0000-4000-8000-00000000b002',0,1,1,1000,1000,'JPY','draft','{}'::jsonb,
  'codex-test consumed','school','canonical_charge',false
);
insert into public.school_student_tuition_billing_identities(
  id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
) values(
  '89090000-0000-4000-8000-000000002002','89090000-0000-4000-8000-00000000a002','2020-07',
  '89090000-0000-4000-8000-000000006002','codex-test:hzc:identity:2','atomic_charge',
  'codex-test historical zero-carry rollback','{}'::jsonb
);
insert into public.school_student_tuition_generation_identities(
  id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
) values(
  '89090000-0000-4000-8000-000000003002','89090000-0000-4000-8000-00000000a002',
  '89090000-0000-4000-8000-00000000e001','2020-07-01','89090000-0000-4000-8000-000000002002',
  now(),'codex-test historical zero-carry rollback'
);
insert into public.school_student_tuition_generation_revisions(
  id,generation_identity_id,tuition_bill_id,revision_no,generation_manifest_sha256,
  manifest_kind,lifecycle_status,created_at,created_by_authority,activated_at
) values(
  '89090000-0000-4000-8000-000000004002','89090000-0000-4000-8000-000000003002',
  '89090000-0000-4000-8000-000000006002',1,repeat('9',64),'atomic_generation_v1','active',
  now(),'codex-test historical zero-carry rollback',now()
);

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,business_entity_id,
  start_time,end_time,duration_hours,lesson_content,status,is_billable,note,app_type,
  unit_price,lesson_fee,lesson_count,teacher_settlement_month,student_settlement_month,
  billing_month,billing_week_start_date,scheduled_lesson_date,billing_month_source,
  billing_month_decided_at
) values
  ('89090000-0000-4000-8000-000000001101','planned','2020-07-06','2020-07','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000d001','89090000-0000-4000-8000-00000000e001','09:00','11:00',2,'codex-test no wage source','planned',true,'codex-test historical zero-carry rollback','school',0,0,1,'2020-07','2020-07','2020-07','2020-07-06','2020-07-06','explicit_billing_week_at_create',now()),
  ('89090000-0000-4000-8000-000000001102','planned','2020-07-07','2020-07','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000d002','89090000-0000-4000-8000-00000000e001','09:00','11:00',2,'codex-test paid source','planned',true,'codex-test historical zero-carry rollback','school',0,0,1,'2020-07','2020-07','2020-07','2020-07-06','2020-07-07','explicit_billing_week_at_create',now());

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,business_entity_id,
  start_time,end_time,duration_hours,lesson_content,status,is_billable,note,app_type,
  unit_price,lesson_fee,lesson_count,actual_minutes,teacher_settlement_month,planned_lesson_id,
  student_settlement_month
) values
  ('89090000-0000-4000-8000-000000001001','actual','2020-07-06','2020-07','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000d001','89090000-0000-4000-8000-00000000e001','09:00','10:00',1,'codex-test no wage','completed',true,'codex-test historical zero-carry rollback','school',0,0,1,60,'2020-07','89090000-0000-4000-8000-000000001101','2020-07'),
  ('89090000-0000-4000-8000-000000001002','actual','2020-07-07','2020-07','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000d002','89090000-0000-4000-8000-00000000e001','09:00','10:00',1,'codex-test paid','completed',true,'codex-test historical zero-carry rollback','school',0,0,1,60,'2020-07','89090000-0000-4000-8000-000000001102','2020-07');
insert into public.school_teacher_wage_rules(
  id,teacher_id,student_id,subject_id,business_entity_id,settlement_type,
  hourly_rate_jpy,hourly_rate_cny,exchange_rate,transport_fee_jpy,classroom_fee_jpy,is_active,note
) values
  ('89090000-0000-4000-8000-000000007101','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-00000000d001','89090000-0000-4000-8000-00000000e001','no_wage',0,0,0,0,0,true,'codex-test historical zero-carry rollback'),
  ('89090000-0000-4000-8000-000000007102','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000a001','89090000-0000-4000-8000-00000000d002','89090000-0000-4000-8000-00000000e001','jpy_hourly',2000,0,0,0,0,true,'codex-test historical zero-carry rollback');
set local session_replication_role='origin';

do $acl_matrix$
declare v_role text;
begin
  foreach v_role in array array['public','anon','authenticated','service_role'] loop
    if has_table_privilege(v_role,'public.school_student_monthly_settlement_historical_completion_evidence','INSERT')
       or has_table_privilege(v_role,'public.school_student_monthly_settlement_historical_completion_evidence','UPDATE')
       or has_table_privilege(v_role,'public.school_student_monthly_settlement_historical_completion_evidence','DELETE') then
      raise exception 'HISTORICAL_ZERO_CARRY_TABLE_DML_EXPOSED:%',v_role;
    end if;
    if has_function_privilege(v_role,'public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE') then
      raise exception 'HISTORICAL_ZERO_CARRY_CORE_EXPOSED:%',v_role;
    end if;
  end loop;
  if not has_function_privilege('service_role','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)','EXECUTE') then
    raise exception 'HISTORICAL_ZERO_CARRY_WRAPPER_ACL_INVALID';
  end if;
end
$acl_matrix$;

do $resolver_before_evidence$
declare v record;
begin
  select * into strict v from public.school_resolve_student_monthly_settlement_effective_state(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e002');
  if not v.effective_complete or v.effective_status<>'ordinary_locked' then raise exception 'ORDINARY_RESOLVER_FAILED'; end if;
  select * into strict v from public.school_resolve_student_monthly_settlement_effective_state(
    '89090000-0000-4000-8000-00000000a002','2020-06','89090000-0000-4000-8000-00000000e001');
  if not v.effective_complete or v.effective_status<>'historically_consumed_immutable' then raise exception 'CONSUMED_RESOLVER_FAILED'; end if;
  select * into strict v from public.school_resolve_student_monthly_settlement_effective_state(
    '89090000-0000-4000-8000-00000000a003','2020-07','89090000-0000-4000-8000-00000000e001');
  if v.effective_complete or v.effective_status<>'incomplete' or v.blocker_code<>'WAGE_EFFECTIVE_SETTLEMENT_MISSING' then raise exception 'INCOMPLETE_RESOLVER_FAILED'; end if;
  select * into strict v from public.school_resolve_student_monthly_settlement_effective_state(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001');
  if v.effective_complete or v.blocker_code<>'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then raise exception 'CROSS_ENTITY_FALLBACK_NOT_BLOCKED'; end if;
end
$resolver_before_evidence$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"89090000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $preflight_before_evidence$
declare v jsonb;
begin
  v:=public.school_get_teacher_monthly_wage_generation_preflight('2020-07','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000e001');
  if (v->'summary'->>'candidate_actual_count')::integer<>2
     or (v->'summary'->>'no_wage_lesson_count')::integer<>1
     or (v->'summary'->>'student_settlement_blocker_count')::integer<>1
     or v->'blockers'->0->>'blocker_code'<>'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then
    raise exception 'WAGE_PREFLIGHT_BEFORE_EVIDENCE_INVALID:%',v;
  end if;
end
$preflight_before_evidence$;
reset role;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $service_core_denied$
declare v_denied boolean:=false;
begin
  begin
    perform public.school_create_student_monthly_settlement_historical_completion_evidence_core(
      '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001',
      repeat('0',64),repeat('0',64),'89090000-0000-4000-8000-000000004001',
      '89090000-0000-4000-8000-000000006001','89090000-0000-4000-8000-00000000f001',
      '89090000-0000-4000-8000-000000005001','89090000-0000-4000-8000-000000008001',
      '89090000-0000-4000-8000-000000009001','89090000-0000-4000-8000-000000000001',
      'codex-test','wrong','wrong');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'SERVICE_ROLE_DIRECT_CORE_ALLOWED'; end if;
end
$service_core_denied$;

do $wrapper_idempotency$
declare v_candidate jsonb; v_first jsonb; v_second jsonb; v_conflict boolean:=false;
begin
  v_candidate:=public.school_get_student_monthly_settlement_historical_completion_candidate(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001');
  v_first:=public.school_local_create_student_monthly_settlement_historical_completion_evidence(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001',
    v_candidate->>'lesson_manifest_sha256',v_candidate->>'makeup_manifest_sha256',
    (v_candidate->>'active_revision_id')::uuid,(v_candidate->>'tuition_bill_id')::uuid,
    (v_candidate->>'income_record_id')::uuid,(v_candidate->>'cash_linkage_event_id')::uuid,
    (v_candidate->>'cash_request_id')::uuid,(v_candidate->>'cash_transaction_id')::uuid,
    '89090000-0000-4000-8000-000000000001','codex-test historical zero-carry rollback',
    v_candidate->>'expected_confirmation',v_candidate->>'expected_idempotency_key');
  v_second:=public.school_local_create_student_monthly_settlement_historical_completion_evidence(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001',
    v_candidate->>'lesson_manifest_sha256',v_candidate->>'makeup_manifest_sha256',
    (v_candidate->>'active_revision_id')::uuid,(v_candidate->>'tuition_bill_id')::uuid,
    (v_candidate->>'income_record_id')::uuid,(v_candidate->>'cash_linkage_event_id')::uuid,
    (v_candidate->>'cash_request_id')::uuid,(v_candidate->>'cash_transaction_id')::uuid,
    '89090000-0000-4000-8000-000000000001','codex-test historical zero-carry rollback',
    v_candidate->>'expected_confirmation',v_candidate->>'expected_idempotency_key');
  if (v_first->>'idempotent')::boolean or not (v_second->>'idempotent')::boolean
     or v_first->>'evidence_id' is distinct from v_second->>'evidence_id' then
    raise exception 'HISTORICAL_ZERO_CARRY_IDEMPOTENCY_FAILED:%:%',v_first,v_second;
  end if;
  begin
    perform public.school_local_create_student_monthly_settlement_historical_completion_evidence(
      '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001',
      v_candidate->>'lesson_manifest_sha256',v_candidate->>'makeup_manifest_sha256',
      (v_candidate->>'active_revision_id')::uuid,(v_candidate->>'tuition_bill_id')::uuid,
      (v_candidate->>'income_record_id')::uuid,(v_candidate->>'cash_linkage_event_id')::uuid,
      (v_candidate->>'cash_request_id')::uuid,(v_candidate->>'cash_transaction_id')::uuid,
      '89090000-0000-4000-8000-000000000001','codex-test conflicting reason',
      v_candidate->>'expected_confirmation',v_candidate->>'expected_idempotency_key');
  exception when others then
    if sqlerrm='HISTORICAL_ZERO_CARRY_IDEMPOTENCY_PAYLOAD_CONFLICT' then v_conflict:=true; else raise; end if;
  end;
  if not v_conflict then raise exception 'HISTORICAL_ZERO_CARRY_IDEMPOTENCY_CONFLICT_MISSING'; end if;
end
$wrapper_idempotency$;
reset role;

do $immutable_and_resolver_after$
declare v record; v_rejected boolean;
begin
  select * into strict v from public.school_resolve_student_monthly_settlement_effective_state(
    '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001');
  if not v.effective_complete or v.effective_status<>'historical_zero_carry_complete' or v.carry_cny<>0 then
    raise exception 'HISTORICAL_ZERO_CARRY_RESOLVER_FAILED';
  end if;
  v_rejected:=false;
  begin
    update public.school_student_monthly_settlement_historical_completion_evidence
    set reason='must fail' where id=v.source_id;
  exception when others then
    if sqlerrm='HISTORICAL_ZERO_CARRY_EVIDENCE_IMMUTABLE' then v_rejected:=true; else raise; end if;
  end;
  if not v_rejected then raise exception 'HISTORICAL_ZERO_CARRY_UPDATE_ALLOWED'; end if;
  v_rejected:=false;
  begin
    delete from public.school_student_monthly_settlement_historical_completion_evidence where id=v.source_id;
  exception when others then
    if sqlerrm='HISTORICAL_ZERO_CARRY_EVIDENCE_IMMUTABLE' then v_rejected:=true; else raise; end if;
  end;
  if not v_rejected then raise exception 'HISTORICAL_ZERO_CARRY_DELETE_ALLOWED'; end if;
  v_rejected:=false;
  begin
    insert into public.school_student_monthly_settlements(
      student_id,year_month,business_entity_id,carryover_amount_cny,settlement_status,note
    ) values(
      '89090000-0000-4000-8000-00000000a001','2020-07','89090000-0000-4000-8000-00000000e001',0,'unlocked','must fail'
    );
  exception when others then
    if sqlerrm='HISTORICAL_ZERO_CARRY_EVIDENCE_ALREADY_AUTHORITATIVE' then v_rejected:=true; else raise; end if;
  end;
  if not v_rejected then raise exception 'ORDINARY_SETTLEMENT_AFTER_EVIDENCE_ALLOWED'; end if;
end
$immutable_and_resolver_after$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"89090000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $wage_preflight_and_writer$
declare v jsonb; v_lock record;
begin
  v:=public.school_get_teacher_monthly_wage_generation_preflight('2020-07','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000e001');
  if (v->'summary'->>'blocker_count')::integer<>0
     or (v->'summary'->>'no_wage_lesson_count')::integer<>1
     or (v->'summary'->>'no_wage_minutes')::numeric<>60
     or (v->'summary'->>'conditional_pay_hours')::numeric<>1
     or (v->'summary'->>'conditional_amount_jpy')::numeric<>2000 then
    raise exception 'WAGE_PREFLIGHT_AFTER_EVIDENCE_INVALID:%',v;
  end if;
  select * into strict v_lock from public.school_generate_teacher_monthly_wage(
    '2020-07','89090000-0000-4000-8000-000000007001','89090000-0000-4000-8000-00000000e001');
  if v_lock.lesson_count<>2 or v_lock.total_minutes<>120 or v_lock.pay_hours<>1
     or v_lock.lesson_wage_jpy<>2000 or v_lock.total_jpy<>2000 or v_lock.detail_count<>2 then
    raise exception 'WAGE_WRITER_SYNTHETIC_TOTAL_INVALID';
  end if;
  if not exists(
    select 1 from public.school_teacher_wage_lock_details d
    where d.lock_id=v_lock.wage_lock_id and d.lesson_record_id='89090000-0000-4000-8000-000000001001'
      and d.is_no_wage and d.pay_hours=0 and d.lesson_wage_jpy=0 and d.total_jpy=0
  ) or not exists(
    select 1 from public.school_teacher_wage_lock_details d
    where d.lock_id=v_lock.wage_lock_id and d.lesson_record_id='89090000-0000-4000-8000-000000001002'
      and not d.is_no_wage and d.pay_hours=1 and d.lesson_wage_jpy=2000 and d.total_jpy=2000
  ) then raise exception 'WAGE_WRITER_SYNTHETIC_DETAIL_INVALID'; end if;
end
$wage_preflight_and_writer$;
reset role;

select 'HISTORICAL_ZERO_CARRY_ROLLBACK_MATRIX_PASS' result;
rollback;

select not exists(select 1 from auth.users where id::text like '89090000-%')
  and not exists(select 1 from public.school_business_entities where id::text like '89090000-%')
  and not exists(select 1 from public.school_students where id::text like '89090000-%')
  and not exists(select 1 from public.school_lesson_records where id::text like '89090000-%')
  as fixture_residue_zero;
