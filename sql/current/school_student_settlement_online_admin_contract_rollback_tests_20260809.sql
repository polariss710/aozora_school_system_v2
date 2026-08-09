-- Phase A online settlement DB contract rollback-only matrix.
-- Fixed a109... synthetic IDs are created and removed by the final ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like 'a1090000-%')
     or exists(select 1 from public.school_app_memberships where user_id::text like 'a1090000-%')
     or exists(select 1 from public.school_students where id::text like 'a1090000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_monthly_settlements where student_id::text like 'a1090000-%') then
    raise exception 'SETTLEMENT_ONLINE_FIXTURE_ID_COLLISION';
  end if;
end
$preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('a1090000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-admin-1"}'::jsonb,now(),now()),
  ('a1090000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-admin-2"}'::jsonb,now(),now()),
  ('a1090000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-operator"}'::jsonb,now(),now()),
  ('a1090000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-read-only"}'::jsonb,now(),now()),
  ('a1090000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-inactive"}'::jsonb,now(),now()),
  ('a1090000-0000-4000-8000-000000000006','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"phase-a-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('a1090000-0000-4000-8000-000000000001','admin',true,'a1090000-0000-4000-8000-000000000001','a1090000-0000-4000-8000-000000000001','codex-test settlement online phase-a rollback'),
  ('a1090000-0000-4000-8000-000000000002','admin',true,'a1090000-0000-4000-8000-000000000001','a1090000-0000-4000-8000-000000000001','codex-test settlement online phase-a rollback'),
  ('a1090000-0000-4000-8000-000000000003','operator',true,'a1090000-0000-4000-8000-000000000001','a1090000-0000-4000-8000-000000000001','codex-test settlement online phase-a rollback'),
  ('a1090000-0000-4000-8000-000000000004','read_only',true,'a1090000-0000-4000-8000-000000000001','a1090000-0000-4000-8000-000000000001','codex-test settlement online phase-a rollback'),
  ('a1090000-0000-4000-8000-000000000005','admin',false,'a1090000-0000-4000-8000-000000000001','a1090000-0000-4000-8000-000000000001','codex-test settlement online phase-a rollback');

set local session_replication_role = 'replica';
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('a1090000-0000-4000-8000-00000000d001','codex-test online settlement subject','codex-test',true,'codex-test settlement online phase-a rollback','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  'a1090000-0000-4000-8000-000000007001','codex-test-online-settlement-teacher',
  'codex-test online settlement teacher','codex-test online settlement teacher',
  'a1090000-0000-4000-8000-00000000d001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  'active','codex-test settlement online phase-a rollback','school'
);
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  'a1090000-0000-4000-8000-00000000a001','codex-test-online-settlement-student',
  'codex-test online settlement student','codex-test online settlement student',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','active','school',0.05,0,
  'codex-test settlement online phase-a rollback'
);

insert into public.school_income_records(
  id,business_entity_id,student_id,income_date,year_month,settlement_month,
  income_category,description,currency,amount,amount_jpy,amount_cny,payment_currency,
  status,is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
  cash_submission_blocked,operational_excluded
) values
  ('a1090000-0000-4000-8000-00000000f001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','a1090000-0000-4000-8000-00000000a001','2020-01-15','2020-01','2020-01','tuition','codex-test phase-a carry','CNY',100,0,100,'CNY','received',false,'codex-test',true,'codex-test settlement online phase-a rollback','school',false,false),
  ('a1090000-0000-4000-8000-00000000f002','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','a1090000-0000-4000-8000-00000000a001','2020-02-15','2020-02','2020-02','tuition','codex-test phase-a clear net','JPY',1000,1000,0,'JPY','received',false,'codex-test',true,'codex-test settlement online phase-a rollback','school',false,false),
  ('a1090000-0000-4000-8000-00000000f003','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','a1090000-0000-4000-8000-00000000a001','2020-03-15','2020-03','2020-03','tuition','codex-test phase-a no-wage','CNY',100,0,100,'CNY','received',false,'codex-test',true,'codex-test settlement online phase-a rollback','school',false,false),
  ('a1090000-0000-4000-8000-00000000f004','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','a1090000-0000-4000-8000-00000000a001','2020-04-15','2020-04','2020-04','tuition','codex-test phase-a paid-wage','CNY',100,0,100,'CNY','received',false,'codex-test',true,'codex-test settlement online phase-a rollback','school',false,false);

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
  teacher_settlement_month,student_settlement_month,billing_month,
  billing_week_start_date,scheduled_lesson_date,billing_month_source,
  billing_month_decided_at
) values
  ('a1090000-0000-4000-8000-000000001103','planned','2020-03-10','2020-03','a1090000-0000-4000-8000-00000000a001','a1090000-0000-4000-8000-000000007001','a1090000-0000-4000-8000-00000000d001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','10:00','12:00',2,'codex-test no wage source','planned',true,'codex-test settlement online phase-a rollback','school',0,0,1,'2020-03','2020-03','2020-03','2020-03-09','2020-03-10','explicit_billing_week_at_create',now()),
  ('a1090000-0000-4000-8000-000000001104','planned','2020-04-10','2020-04','a1090000-0000-4000-8000-00000000a001','a1090000-0000-4000-8000-000000007001','a1090000-0000-4000-8000-00000000d001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','10:00','12:00',2,'codex-test paid wage source','planned',true,'codex-test settlement online phase-a rollback','school',1000,2000,1,'2020-04','2020-04','2020-04','2020-04-06','2020-04-10','explicit_billing_week_at_create',now());

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,note,app_type,unit_price,lesson_fee,lesson_count,actual_minutes,
  teacher_settlement_month,planned_lesson_id,student_settlement_month
) values
  ('a1090000-0000-4000-8000-000000001003','actual','2020-03-10','2020-03','a1090000-0000-4000-8000-00000000a001','a1090000-0000-4000-8000-000000007001','a1090000-0000-4000-8000-00000000d001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','10:00','11:00',1,'codex-test no wage','completed',true,'codex-test settlement online phase-a rollback','school',0,0,1,60,'2020-03','a1090000-0000-4000-8000-000000001103','2020-03'),
  ('a1090000-0000-4000-8000-000000001004','actual','2020-04-10','2020-04','a1090000-0000-4000-8000-00000000a001','a1090000-0000-4000-8000-000000007001','a1090000-0000-4000-8000-00000000d001','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','10:00','11:00',1,'codex-test paid wage','completed',true,'codex-test settlement online phase-a rollback','school',1000,1000,1,60,'2020-04','a1090000-0000-4000-8000-000000001104','2020-04');

insert into public.school_teacher_wage_locks(
  id,settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
  settlement_type,total_minutes,pay_hours,lesson_wage_jpy,total_jpy,lesson_count,status
) values
  ('a1090000-0000-4000-8000-000000007101','2020-03','a1090000-0000-4000-8000-000000007001','codex-test teacher','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','codex-test','no_wage',60,0,0,0,1,'locked'),
  ('a1090000-0000-4000-8000-000000007102','2020-04','a1090000-0000-4000-8000-000000007001','codex-test teacher','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','codex-test','jpy_hourly',60,1,1000,1000,1,'locked');
insert into public.school_teacher_wage_lock_details(
  id,lock_id,lesson_record_id,lesson_date,student_id,student_name,subject_id,
  subject_name,business_entity_id,business_name,pay_hours,lesson_wage_jpy,total_jpy,
  settlement_type,is_no_wage,status,lesson_content
) values
  ('a1090000-0000-4000-8000-000000007201','a1090000-0000-4000-8000-000000007101','a1090000-0000-4000-8000-000000001003','2020-03-10','a1090000-0000-4000-8000-00000000a001','codex-test student','a1090000-0000-4000-8000-00000000d001','codex-test subject','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','codex-test',0,0,0,'no_wage',true,'locked','codex-test no wage'),
  ('a1090000-0000-4000-8000-000000007202','a1090000-0000-4000-8000-000000007102','a1090000-0000-4000-8000-000000001004','2020-04-10','a1090000-0000-4000-8000-00000000a001','codex-test student','a1090000-0000-4000-8000-00000000d001','codex-test subject','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','codex-test',1,1000,1000,'jpy_hourly',false,'locked','codex-test paid wage');
set local session_replication_role = 'origin';

do $acl_and_actor$
declare
  v_role text;
begin
  foreach v_role in array array['public','anon','authenticated'] loop
    if has_function_privilege(v_role,
      'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)', 'EXECUTE') then
      raise exception 'SETTLEMENT_ONLINE_CLIENT_WRAPPER_EXPOSED:%', v_role;
    end if;
  end loop;
  if not has_function_privilege('service_role',
      'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role',
      'public.school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)', 'EXECUTE') then
    raise exception 'SETTLEMENT_ONLINE_SERVICE_WRAPPER_MISSING';
  end if;
  foreach v_role in array array['public','anon','authenticated','service_role'] loop
    if has_function_privilege(v_role,
      'public.school_lock_student_monthly_settlement(uuid,text,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_unlock_student_monthly_settlement(uuid,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_relock_student_monthly_settlement(uuid,text)', 'EXECUTE') then
      raise exception 'SETTLEMENT_CORE_OR_UNLOCK_EXPOSED:%', v_role;
    end if;
  end loop;

  perform public.school_assert_student_settlement_online_admin('a1090000-0000-4000-8000-000000000001');
  begin
    perform public.school_assert_student_settlement_online_admin(null);
    raise exception 'EXPECTED_NULL_ACTOR_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADMIN_REQUIRED' then raise; end if;
  end;
  begin
    perform public.school_assert_student_settlement_online_admin('a1090000-0000-4000-8000-000000000003');
    raise exception 'EXPECTED_OPERATOR_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADMIN_REQUIRED' then raise; end if;
  end;
  begin
    perform public.school_assert_student_settlement_online_admin('a1090000-0000-4000-8000-000000000004');
    raise exception 'EXPECTED_READ_ONLY_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADMIN_REQUIRED' then raise; end if;
  end;
  begin
    perform public.school_assert_student_settlement_online_admin('a1090000-0000-4000-8000-000000000005');
    raise exception 'EXPECTED_INACTIVE_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADMIN_REQUIRED' then raise; end if;
  end;
  begin
    perform public.school_assert_student_settlement_online_admin('a1090000-0000-4000-8000-000000000006');
    raise exception 'EXPECTED_NO_MEMBERSHIP_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADMIN_REQUIRED' then raise; end if;
  end;
end
$acl_and_actor$;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $online_contract$
declare
  v_student constant uuid := 'a1090000-0000-4000-8000-00000000a001';
  v_admin constant uuid := 'a1090000-0000-4000-8000-000000000001';
  v_admin2 constant uuid := 'a1090000-0000-4000-8000-000000000002';
  v_preview jsonb;
  v_result jsonb;
  v_retry jsonb;
  v_source_id uuid;
  v_source_updated timestamptz;
  v_adjustment_id uuid;
  v_adjustment_updated timestamptz;
  v_new_adjustment_updated timestamptz;
  v_settlement_id uuid;
begin
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',
    'separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
      'carry_final_balance',null,'codex-test phase-a reason','codex-test phase-a note',
      repeat('0',64),
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      null,null,null,null,null
    );
    raise exception 'EXPECTED_PREVIEW_MANIFEST_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_PREVIEW_MANIFEST_STALE' then raise; end if;
  end;
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
      'carry_final_balance',null,'codex-test phase-a reason','codex-test phase-a note',
      v_preview->>'preview_manifest_sha256',repeat('1',64),
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      null,null,null,null,null
    );
    raise exception 'EXPECTED_LESSON_MANIFEST_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_LESSON_MANIFEST_STALE' then raise; end if;
  end;
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
      'carry_final_balance',null,'codex-test phase-a reason','codex-test phase-a note',
      v_preview->>'preview_manifest_sha256',
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer + 1,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric + 1,
      null,null,null,null,null
    );
    raise exception 'EXPECTED_FACTS_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_EXPECTED_FACTS_MISMATCH' then raise; end if;
  end;
  if exists(select 1 from public.school_student_settlement_source_treatment_drafts
       where student_id=v_student and year_month='2020-01')
     or exists(select 1 from public.school_student_settlement_adjustment_drafts
       where student_id=v_student and year_month='2020-01') then
    raise exception 'SETTLEMENT_ONLINE_NEGATIVE_PREVIEW_WROTE_DRAFT';
  end if;
  v_result := public.school_save_student_monthly_settlement_draft_online_admin(
    v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null,'codex-test phase-a reason','codex-test phase-a note',
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    null,null,null,null,'a1090000-0000-4000-8000-000000009001'
  );
  if (v_result->>'idempotent')::boolean
     or exists(select 1 from public.school_student_monthly_settlements
       where student_id=v_student and year_month='2020-01') then
    raise exception 'SETTLEMENT_ONLINE_FIRST_SAVE_INVALID:%', v_result;
  end if;
  v_source_id := (v_result->>'source_treatment_draft_id')::uuid;
  v_source_updated := (v_result->>'source_treatment_draft_updated_at')::timestamptz;
  v_adjustment_id := (v_result->>'adjustment_draft_id')::uuid;
  v_adjustment_updated := (v_result->>'adjustment_draft_updated_at')::timestamptz;

  v_retry := public.school_save_student_monthly_settlement_draft_online_admin(
    v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null,'codex-test phase-a reason','codex-test phase-a note',
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    null,null,null,null,'a1090000-0000-4000-8000-000000009001'
  );
  if not (v_retry->>'idempotent')::boolean
     or (v_retry->>'source_treatment_draft_id')::uuid <> v_source_id
     or (v_retry->>'adjustment_draft_id')::uuid <> v_adjustment_id
     or (v_retry->>'source_treatment_draft_updated_at')::timestamptz <> v_source_updated
     or (v_retry->>'adjustment_draft_updated_at')::timestamptz <> v_adjustment_updated then
    raise exception 'SETTLEMENT_ONLINE_SAVE_IDEMPOTENCY_FAILED:%', v_retry;
  end if;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',
    'separate_makeup_and_overage_v1',null,null,null,
    'manual_adjustment',1
  );
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin2,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
      'manual_adjustment',1,'codex-test phase-a reason','codex-test phase-a note',
      v_preview->>'preview_manifest_sha256',
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      null,null,null,null,null
    );
    raise exception 'EXPECTED_STALE_DIFFERENT_PAYLOAD_REJECTION_MISSING';
  exception when others then
    if sqlerrm not in ('SETTLEMENT_ADJUSTMENT_DRAFT_STALE','SETTLEMENT_SOURCE_DRAFT_STALE') then raise; end if;
  end;

  v_result := public.school_save_student_monthly_settlement_draft_online_admin(
    v_admin,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
    'manual_adjustment',1,'codex-test phase-a reason','codex-test phase-a note',
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    v_source_id,v_source_updated,v_adjustment_id,v_adjustment_updated,null
  );
  v_new_adjustment_updated := (v_result->>'adjustment_draft_updated_at')::timestamptz;
  if (v_result->>'source_treatment_draft_updated_at')::timestamptz <> v_source_updated
     or (select adjustment_source from public.school_student_settlement_adjustment_drafts
         where id = v_adjustment_id) <> 'manual_adjustment'
     or (select adjustment_amount_cny from public.school_student_settlement_adjustment_drafts
         where id = v_adjustment_id) <> 1 then
    raise exception 'SETTLEMENT_ONLINE_PARTIAL_DRAFT_UPDATE_INVALID:%', v_result;
  end if;

  begin
    v_preview := public.school_preview_student_settlement_adjustment_dialog(
      v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',
      'separate_makeup_and_overage_v1',null,null,null,'manual_adjustment',2
    );
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin2,v_student,'2020-01','separate_makeup_and_overage_v1',null,null,null,
      'manual_adjustment',2,'codex-test phase-a reason','codex-test phase-a note',
      v_preview->>'preview_manifest_sha256',
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      v_source_id,v_source_updated,v_adjustment_id,
      v_adjustment_updated - interval '1 second',null
    );
    raise exception 'EXPECTED_SECOND_ADMIN_STALE_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ADJUSTMENT_DRAFT_STALE' then raise; end if;
  end;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',
    'separate_makeup_and_overage_v1',null,null,null,'manual_adjustment',1
  );
  begin
    perform public.school_lock_student_monthly_settlement_online_admin(
      v_admin,v_student,'2020-01',v_source_id,v_source_updated - interval '1 second',
      v_adjustment_id,v_new_adjustment_updated,
      v_preview->>'preview_manifest_sha256',
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      'codex-test phase-a lock',null
    );
    raise exception 'EXPECTED_LOCK_SOURCE_STALE_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_SOURCE_DRAFT_STALE' then raise; end if;
  end;
  begin
    perform public.school_lock_student_monthly_settlement_online_admin(
      v_admin,v_student,'2020-01',v_source_id,v_source_updated,
      v_adjustment_id,v_new_adjustment_updated,repeat('0',64),
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
      (v_preview->'preview'->>'lesson_variance_source_count')::integer,
      (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
      (v_preview->'preview'->>'overage_charge_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
      (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
      'codex-test phase-a lock',null
    );
    raise exception 'EXPECTED_LOCK_PREVIEW_STALE_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_PREVIEW_MANIFEST_STALE' then raise; end if;
  end;
  v_result := public.school_lock_student_monthly_settlement_online_admin(
    v_admin,v_student,'2020-01',v_source_id,v_source_updated,
    v_adjustment_id,v_new_adjustment_updated,
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    'codex-test phase-a lock',null
  );
  v_settlement_id := (v_result->>'settlement_id')::uuid;
  if (v_result->>'idempotent')::boolean
     or (select count(*) from public.school_student_monthly_settlements
       where student_id=v_student and year_month='2020-01') <> 1 then
    raise exception 'SETTLEMENT_ONLINE_FIRST_LOCK_INVALID:%', v_result;
  end if;
  v_retry := public.school_lock_student_monthly_settlement_online_admin(
    v_admin,v_student,'2020-01',v_source_id,v_source_updated,
    v_adjustment_id,v_new_adjustment_updated,
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    'codex-test phase-a lock',null
  );
  if not (v_retry->>'idempotent')::boolean
     or (v_retry->>'settlement_id')::uuid <> v_settlement_id then
    raise exception 'SETTLEMENT_ONLINE_LOCK_IDEMPOTENCY_FAILED:%', v_retry;
  end if;

  -- net source treatment + clear balance use the same DB-authoritative preview.
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-02',
    'net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-02-01',
    'clear_balance',null
  );
  v_result := public.school_save_student_monthly_settlement_draft_online_admin(
    v_admin,v_student,'2020-02','net_lesson_variance_to_financial_credit_v1',0.05,
    'codex_test_rate','2020-02-01','clear_balance',null,
    'codex-test phase-a net clear','codex-test',
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    null,null,null,null,null
  );
  if (v_result->'authoritative_preview'->'preview'->>'projected_final_carryover_cny')::numeric <> 0 then
    raise exception 'SETTLEMENT_ONLINE_CLEAR_BALANCE_FAILED:%', v_result;
  end if;

  -- no_wage detail is not a settlement mutation blocker.
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-03',
    'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null
  );
  perform public.school_save_student_monthly_settlement_draft_online_admin(
    v_admin,v_student,'2020-03','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null,'codex-test phase-a no wage','codex-test',
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    null,null,null,null,null
  );

  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,v_student,'2020-04','separate_makeup_and_overage_v1',null,null,null,
      'carry_final_balance',null,'codex-test phase-a paid wage','codex-test',
      null,null,0,0,0,0,0,0,0,null,null,null,null,null
    );
    raise exception 'EXPECTED_WAGE_BLOCKER_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_WAGE_BLOCKED' then raise; end if;
  end;

  -- Real immutable scopes are rejection-only; no write statement is reached.
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,'eceb2c59-9689-4ec8-9d3f-799b90bfdb27','2026-07',
      'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null,
      'codex-test guard','codex-test',null,null,0,0,0,0,0,0,0,null,null,null,null,null
    );
    raise exception 'EXPECTED_HISTORICAL_ZERO_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE' then raise; end if;
  end;
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,'7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07',
      'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null,
      'codex-test guard','codex-test',null,null,0,0,0,0,0,0,0,null,null,null,null,null
    );
    raise exception 'EXPECTED_CONSUMED_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_HISTORICALLY_CONSUMED' then raise; end if;
  end;
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07',
      'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null,
      'codex-test guard','codex-test',null,null,0,0,0,0,0,0,0,null,null,null,null,null
    );
    raise exception 'EXPECTED_ORDINARY_LOCKED_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ORDINARY_ALREADY_LOCKED' then raise; end if;
  end;
  begin
    perform public.school_save_student_monthly_settlement_draft_online_admin(
      v_admin,'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',
      'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null,
      'codex-test guard','codex-test',null,null,0,0,0,0,0,0,0,null,null,null,null,null
    );
    raise exception 'EXPECTED_SUCCESSOR_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED' then raise; end if;
  end;
end
$online_contract$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1090000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $status_admin$
declare v jsonb;
begin
  v := public.school_get_student_monthly_settlement_online_status(
    'a1090000-0000-4000-8000-00000000a001','2020-01'
  );
  if v->'effective_state'->>'effective_status' <> 'ordinary_locked'
     or (v->>'can_save')::boolean or (v->>'can_lock')::boolean then
    raise exception 'SETTLEMENT_ONLINE_STATUS_ORDINARY_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07'
  );
  if v->'effective_state'->>'effective_status' <> 'historically_consumed_immutable' then
    raise exception 'SETTLEMENT_ONLINE_STATUS_CONSUMED_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    'eceb2c59-9689-4ec8-9d3f-799b90bfdb27','2026-07'
  );
  if v->'effective_state'->>'effective_status' <> 'historical_zero_carry_complete' then
    raise exception 'SETTLEMENT_ONLINE_STATUS_HISTORICAL_ZERO_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    'a1090000-0000-4000-8000-00000000a001','2020-02'
  );
  if v->'effective_state'->>'effective_status' <> 'incomplete'
     or v->'source_treatment_draft'->>'draft_id' is null
     or v->'source_treatment_draft'->>'updated_at' is null
     or v->'adjustment_draft'->>'draft_id' is null
     or v->'adjustment_draft'->>'updated_at' is null
     or not (v->>'can_lock')::boolean then
    raise exception 'SETTLEMENT_ONLINE_STATUS_INCOMPLETE_INVALID:%', v;
  end if;
end
$status_admin$;

select set_config('request.jwt.claims','{"sub":"a1090000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select public.school_get_student_monthly_settlement_online_status('a1090000-0000-4000-8000-00000000a001','2020-02') is not null as operator_status_allowed;
select set_config('request.jwt.claims','{"sub":"a1090000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select public.school_get_student_monthly_settlement_online_status('a1090000-0000-4000-8000-00000000a001','2020-02') is not null as read_only_status_allowed;

select set_config('request.jwt.claims','{"sub":"a1090000-0000-4000-8000-000000000005","role":"authenticated"}',true);
do $inactive_status$
begin
  begin
    perform public.school_get_student_monthly_settlement_online_status('a1090000-0000-4000-8000-00000000a001','2020-02');
    raise exception 'EXPECTED_INACTIVE_STATUS_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ACTIVE_MEMBERSHIP_REQUIRED' then raise; end if;
  end;
end
$inactive_status$;
select set_config('request.jwt.claims','{"sub":"a1090000-0000-4000-8000-000000000006","role":"authenticated"}',true);
do $no_membership_status$
begin
  begin
    perform public.school_get_student_monthly_settlement_online_status('a1090000-0000-4000-8000-00000000a001','2020-02');
    raise exception 'EXPECTED_NO_MEMBERSHIP_STATUS_REJECTION_MISSING';
  exception when others then
    if sqlerrm <> 'SETTLEMENT_ACTIVE_MEMBERSHIP_REQUIRED' then raise; end if;
  end;
end
$no_membership_status$;
reset role;

do $business_boundary$
begin
  if exists(select 1 from public.school_student_tuition_bills where student_id='a1090000-0000-4000-8000-00000000a001')
     or exists(select 1 from public.school_payment_requests where source_id in (
       select id from public.school_student_monthly_settlements where student_id='a1090000-0000-4000-8000-00000000a001'
     ))
     or (select count(*) from public.school_student_monthly_settlements
       where student_id='a1090000-0000-4000-8000-00000000a001') <> 1 then
    raise exception 'SETTLEMENT_ONLINE_DOWNSTREAM_BOUNDARY_FAILED';
  end if;
end
$business_boundary$;

rollback;

do $residue$
begin
  if exists(select 1 from auth.users where id::text like 'a1090000-%')
     or exists(select 1 from public.school_app_memberships where user_id::text like 'a1090000-%')
     or exists(select 1 from public.school_students where id::text like 'a1090000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'a1090000-%')
     or exists(select 1 from public.school_income_records where id::text like 'a1090000-%')
     or exists(select 1 from public.school_teacher_wage_locks where id::text like 'a1090000-%')
     or exists(select 1 from public.school_teacher_wage_lock_details where id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_monthly_settlements where student_id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_settlement_source_treatment_drafts where student_id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_settlement_adjustment_drafts where student_id::text like 'a1090000-%') then
    raise exception 'SETTLEMENT_ONLINE_ROLLBACK_RESIDUE';
  end if;
end
$residue$;

select 'SETTLEMENT_ONLINE_PHASE_A_ROLLBACK_TESTS_PASS' as result;
