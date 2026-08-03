-- P0-F local settlement wrappers: rollback-only Peng Yuhan mirror and ACL tests.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout = '10s';
set local statement_timeout = '240s';

do $seed$
declare
  v_marker constant text := 'codex-test tuition-p0f-local-wrapper-20260803';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_subject constant uuid := 'f0f30000-0000-4000-8000-00000000d001';
  v_teacher constant uuid := 'f0f30000-0000-4000-8000-000000007001';
  v_student constant uuid := 'f0f30000-0000-4000-8000-00000000a001';
  v_unused constant uuid := 'f0f30000-0000-4000-8000-000000001001';
  v_fulfilled constant uuid := 'f0f30000-0000-4000-8000-000000001002';
  v_income constant uuid := 'f0f30000-0000-4000-8000-000000007101';
begin
  if exists(select 1 from public.school_students where id=v_student or note=v_marker)
     or exists(select 1 from public.school_lesson_records where id in (v_unused,v_fulfilled) or note=v_marker) then
    raise exception 'P0F_LOCAL_WRAPPER_FIXTURE_COLLISION';
  end if;
  insert into public.school_subjects(id,name,category,is_active,note,primary_category)
  values(v_subject,'codex-test P0-F local wrapper subject','codex-test',true,v_marker,'班课');
  insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
    default_business_entity_id,status,note,app_type)
  values(v_teacher,'codex-test-p0f-local','codex-test P0-F local wrapper teacher',
    'codex-test P0-F local wrapper teacher',v_subject,v_entity,'active',v_marker,'school');
  insert into public.school_students(id,student_code,name,display_name,business_entity_id,
    status,app_type,preset_exchange_rate,previous_balance_cny,note)
  values(v_student,'codex-test-p0f-local','codex-test P0-F local wrapper student',
    'codex-test P0-F local wrapper student',v_entity,'active','school',0.05,0,v_marker);
  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,actual_minutes,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
  ) values
    (v_unused,'planned','2020-07-08','2020-07',v_student,v_teacher,v_subject,v_entity,
      '10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',8500,17000,1,120,
      'online',v_marker,'2020-07','2020-07-06','2020-07-08','2020-07',
      'explicit_billing_week_at_create',now()),
    (v_fulfilled,'planned','2020-07-15','2020-07',v_student,v_teacher,v_subject,v_entity,
      '10:00','12:00',2,v_marker,'planned',true,v_marker,'school',8500,17000,1,120,
      'online',v_marker,'2020-07','2020-07-13','2020-07-15','2020-07',
      'explicit_billing_week_at_create',now());
  perform * from public.school_create_actual_lesson_from_planned(
    v_fulfilled,'2020-07-15','10:00','12:15',2.25,8500,null,1,v_marker,v_marker
  );
  insert into public.school_income_records(
    id,business_entity_id,student_id,income_date,year_month,settlement_month,
    income_category,description,currency,amount,amount_jpy,payment_currency,status,
    is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
    operational_excluded
  ) values(v_income,v_entity,v_student,'2020-07-20','2020-07','2020-07','tuition',
    v_marker,'JPY',34000,34000,'JPY','received',false,'codex-test',true,v_marker,'school',false);
end
$seed$;

do $acl$
declare
  v_save regprocedure := 'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)'::regprocedure;
  v_lock regprocedure := 'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)'::regprocedure;
begin
  if has_function_privilege('anon',v_save,'execute')
     or has_function_privilege('authenticated',v_save,'execute')
     or not has_function_privilege('service_role',v_save,'execute')
     or has_function_privilege('anon',v_lock,'execute')
     or has_function_privilege('authenticated',v_lock,'execute')
     or not has_function_privilege('service_role',v_lock,'execute') then
    raise exception 'P0F_LOCAL_WRAPPER_ACL_FAILED';
  end if;
  if has_function_privilege('anon','public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','execute')
     or has_function_privilege('anon','public.school_lock_student_monthly_settlement(uuid,text,text)','execute')
     or has_function_privilege('anon','public.school_unlock_student_monthly_settlement(uuid,text)','execute')
     or has_function_privilege('anon','public.school_relock_student_monthly_settlement(uuid,text)','execute') then
    raise exception 'P0F_ANON_WRITER_ACL_CLOSURE_FAILED';
  end if;
end
$acl$;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

do $service_role_test$
declare
  v_student constant uuid := 'f0f30000-0000-4000-8000-00000000a001';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_reason constant text := 'codex-test tuition-p0f-local-wrapper-20260803';
  v_preview jsonb;
  v_save jsonb;
  v_lock jsonb;
  v_source_id uuid;
  v_source_updated timestamptz;
  v_adjustment_id uuid;
  v_adjustment_updated timestamptz;
  v_manifest text;
  v_lesson_manifest text;
  v_confirmation text;
begin
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null
  );
  if (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric <> -17000
     or (v_preview->'preview'->>'overage_charge_jpy')::numeric <> 2125
     or (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric <> -14875
     or (v_preview->'preview'->>'net_lesson_variance_cny')::numeric <> -624.75
     or (v_preview->'preview'->>'projected_final_carryover_cny')::numeric <> -624.75
     or (v_preview->'preview'->>'lesson_variance_source_count')::integer <> 2 then
    raise exception 'P0F_LOCAL_WRAPPER_PENG_MIRROR_PREVIEW_FAILED: %',v_preview;
  end if;
  v_manifest := v_preview->>'preview_manifest_sha256';
  v_lesson_manifest := v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256';
  v_confirmation := format('SAVE STUDENT SETTLEMENT DRAFT %s %s MANIFEST %s',
    v_student,'2020-07',v_manifest);

  begin
    perform public.school_save_student_settlement_draft_local(
      v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
      0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
      v_manifest,v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
      v_reason,v_reason,'local_trusted_business_owner_v1','WRONG CONFIRMATION'
    );
    raise exception 'EXPECTED_CONFIRMATION_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_LOCAL_CONFIRMATION_MISMATCH' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform public.school_save_student_settlement_draft_local(
      v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
      0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
      repeat('0',64),v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
      v_reason,v_reason,'local_trusted_business_owner_v1',format(
        'SAVE STUDENT SETTLEMENT DRAFT %s %s MANIFEST %s',
        v_student,'2020-07',repeat('0',64)
      )
    );
    raise exception 'EXPECTED_STALE_PREVIEW_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_LOCAL_EXPECTED_FACTS_MISMATCH' in sqlerrm)=0 then raise; end if;
  end;

  v_save := public.school_save_student_settlement_draft_local(
    v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
    v_manifest,v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
    v_reason,v_reason,'local_trusted_business_owner_v1',v_confirmation
  );
  if not (v_save->>'ok')::boolean
     or (v_save->>'adjustment_amount_cny')::numeric <> 0
     or (v_save->>'final_carryover_cny')::numeric <> -624.75 then
    raise exception 'P0F_LOCAL_WRAPPER_SAVE_FAILED: %',v_save;
  end if;
  v_source_id := (v_save->>'source_treatment_draft_id')::uuid;
  v_source_updated := (v_save->>'source_treatment_draft_updated_at')::timestamptz;
  v_adjustment_id := (v_save->>'adjustment_draft_id')::uuid;
  v_adjustment_updated := (v_save->>'adjustment_draft_updated_at')::timestamptz;

  v_confirmation := format('LOCK STUDENT SETTLEMENT %s %s MANIFEST %s CARRY %s',
    v_student,'2020-07',v_manifest,-624.75);
  v_lock := public.school_lock_student_monthly_settlement_local(
    v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
    v_manifest,v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
    v_source_id,v_source_updated,v_adjustment_id,v_adjustment_updated,
    v_reason,'local_trusted_business_owner_v1',v_confirmation
  );
  if not (v_lock->>'ok')::boolean
     or v_lock->>'settlement_status' <> 'locked'
     or (v_lock->>'active_claim_count')::integer <> 2
     or (v_lock->>'final_carryover_cny')::numeric <> -624.75 then
    raise exception 'P0F_LOCAL_WRAPPER_LOCK_FAILED: %',v_lock;
  end if;
  begin
    perform public.school_lock_student_monthly_settlement_local(
      v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
      0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
      v_manifest,v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
      v_source_id,v_source_updated + interval '1 second',v_adjustment_id,v_adjustment_updated,
      v_reason,'local_trusted_business_owner_v1',v_confirmation
    );
    raise exception 'EXPECTED_DUPLICATE_LOCK_STALE_DRAFT_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_LOCAL_DUPLICATE_LOCK_FACTS_MISMATCH' in sqlerrm)=0 then raise; end if;
  end;
  v_lock := public.school_lock_student_monthly_settlement_local(
    v_student,v_entity,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01','carry_final_balance',null,
    v_manifest,v_lesson_manifest,2,-17000,2125,-14875,-624.75,-624.75,-624.75,
    v_source_id,v_source_updated,v_adjustment_id,v_adjustment_updated,
    v_reason,'local_trusted_business_owner_v1',v_confirmation
  );
  if not coalesce((v_lock->>'idempotent')::boolean,false)
     or v_lock->>'settlement_status' <> 'locked'
     or (v_lock->>'active_claim_count')::integer <> 2 then
    raise exception 'P0F_LOCAL_WRAPPER_DUPLICATE_LOCK_FAILED: %',v_lock;
  end if;
end
$service_role_test$;

reset role;
do $verify$
begin
  if (select count(*) from public.school_student_monthly_settlements
      where student_id='f0f30000-0000-4000-8000-00000000a001' and year_month='2020-07')<>1
     or (select count(*) from public.school_student_settlement_lesson_variance_claims
      where student_id='f0f30000-0000-4000-8000-00000000a001' and claim_status='active')<>2 then
    raise exception 'P0F_LOCAL_WRAPPER_POSTLOCK_VERIFY_FAILED';
  end if;
end
$verify$;

rollback;
