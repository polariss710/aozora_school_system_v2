-- P0-F rollback-only business/claim/permission matrix.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $tests$
declare
  v_marker constant text:='codex-test tuition-p0f-20260803';
  v_entity constant uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_subject constant uuid:='f0f00000-0000-4000-8000-00000000d001';
  v_teacher constant uuid:='f0f00000-0000-4000-8000-000000007001';
  v_student constant uuid:='f0f00000-0000-4000-8000-00000000a001';
  v_unused constant uuid:='f0f00000-0000-4000-8000-000000001001';
  v_fulfilled constant uuid:='f0f00000-0000-4000-8000-000000001002';
  v_actual uuid;
  v_income constant uuid:='f0f00000-0000-4000-8000-000000007101';
  v_separate_income constant uuid:='f0f00000-0000-4000-8000-000000007102';
  v_void_lesson constant uuid:='f0f00000-0000-4000-8000-000000001004';
  v_bill constant uuid:='f0f00000-0000-4000-8000-000000006001';
  v_legacy constant uuid:='f0f00000-0000-4000-8000-000000002001';
  v_generation constant uuid:='f0f00000-0000-4000-8000-000000003001';
  v_revision constant uuid:='f0f00000-0000-4000-8000-000000004001';
  v_relation constant uuid:='f0f00000-0000-4000-8000-000000005001';
  v_preview record; v_lock record; v_relock record; v_updated timestamptz;
  v_claims integer; v_batch uuid; v_net_settlement uuid;
  v_manifest constant text:=repeat('f',64);
  v_draft_manifest text; v_current_manifest text;
begin
  if exists(
    select 1 from public.school_students where id=v_student
    union all select 1 from public.school_lesson_records
      where id in (v_unused,v_fulfilled,v_actual,v_void_lesson)
  ) then raise exception 'P0F_FIXTURE_ID_COLLISION'; end if;

  insert into public.school_subjects(id,name,category,is_active,note,primary_category)
  values(v_subject,'codex-test P0-F subject','codex-test',true,v_marker,'班课');
  insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
    default_business_entity_id,status,note,app_type)
  values(v_teacher,'codex-test-p0f-teacher','codex-test P0-F teacher','codex-test P0-F teacher',
    v_subject,v_entity,'active',v_marker,'school');
  insert into public.school_students(id,student_code,name,display_name,business_entity_id,status,
    app_type,preset_exchange_rate,previous_balance_cny,note)
  values(v_student,'codex-test-p0f-student','codex-test P0-F student','codex-test P0-F student',
    v_entity,'active','school',0.05,0,v_marker);

  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,actual_minutes,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,
    billing_month_decided_at
  ) values
    (v_unused,'planned','2020-07-08','2020-07',v_student,v_teacher,v_subject,v_entity,
      '10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',8500,17000,1,120,
      'online',v_marker,'2020-07','2020-07-06','2020-07-08','2020-07',
      'explicit_billing_week_at_create',now()),
    (v_fulfilled,'planned','2020-07-15','2020-07',v_student,v_teacher,v_subject,v_entity,
      '10:00','12:00',2,v_marker,'planned',true,v_marker,'school',8500,17000,1,120,
      'online',v_marker,'2020-07','2020-07-13','2020-07-15','2020-07',
      'explicit_billing_week_at_create',now());
  select lesson_id into strict v_actual
  from public.school_create_actual_lesson_from_planned(
    v_fulfilled,'2020-07-15','10:00','12:15',2.25,8500,null,1,v_marker,v_marker
  );
  insert into public.school_income_records(
    id,business_entity_id,student_id,income_date,year_month,settlement_month,
    income_category,description,currency,amount,amount_jpy,payment_currency,status,
    is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
    operational_excluded
  ) values(v_income,v_entity,v_student,'2020-07-20','2020-07','2020-07','tuition',
    v_marker,'JPY',34000,34000,'JPY','received',false,'codex-test',true,v_marker,'school',false);

  select * into strict v_preview
  from public.school_preview_student_settlement_source_treatment(
    v_student,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01'
  );
  if v_preview.pending_makeup_hours<>2 or v_preview.overage_hours<>0.25
     or v_preview.unused_planned_credit_jpy<>-17000
     or v_preview.overage_charge_jpy<>2125
     or v_preview.lesson_variance_display_hours<>-1.75
     or v_preview.net_lesson_variance_jpy<>-14875
     or v_preview.net_lesson_variance_cny<>-624.75
     or v_preview.system_difference_cny<>-624.75
     or v_preview.lesson_variance_source_count<>2 then
    raise exception 'P0F_PENG_MIRROR_PREVIEW_FAILED: %',to_jsonb(v_preview);
  end if;

  perform * from public.school_set_student_settlement_source_treatment_draft(
    v_student,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01',v_marker
  );
  select source_manifest_sha256 into strict v_draft_manifest
  from public.school_student_settlement_source_treatment_drafts
  where student_id=v_student and year_month='2020-07' and status='active';
  select lesson_variance_manifest_sha256 into strict v_current_manifest
  from public.school_preview_student_settlement_source_treatment(
    v_student,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01'
  );
  if v_draft_manifest is distinct from v_current_manifest then
    raise exception 'P0F_DRAFT_PRELOCK_MANIFEST_DRIFT: % <> %',v_draft_manifest,v_current_manifest;
  end if;
  select * into strict v_lock
  from public.school_lock_student_monthly_settlement(v_student,'2020-07',v_marker);
  v_net_settlement:=v_lock.settlement_id;
  if v_lock.system_difference_cny<>-624.75 or v_lock.carryover_amount_cny<>-624.75 then
    raise exception 'P0F_LOCK_CARRY_FAILED: %',to_jsonb(v_lock);
  end if;
  select count(*),(array_agg(claim_batch_id))[1] into v_claims,v_batch
  from public.school_student_settlement_lesson_variance_claims
  where settlement_id=v_lock.settlement_id and claim_status='active';
  if v_claims<>2 or (select count(distinct claim_batch_id)
      from public.school_student_settlement_lesson_variance_claims
      where settlement_id=v_lock.settlement_id)<>1 then
    raise exception 'P0F_LOCK_CLAIM_BATCH_FAILED';
  end if;
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      v_unused,'2020-07-22',v_teacher,v_subject,'10:00','11:00',1,
      v_marker,v_marker,1,'online',v_marker
    );
    raise exception 'EXPECTED_CLAIMED_MAKEUP_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED' in sqlerrm)=0
       and position('补课来源学生月度结算已锁定' in sqlerrm)=0 then raise; end if;
  end;
  begin
    update public.school_student_settlement_source_treatment_drafts set reason='forbidden'
    where student_id=v_student;
    raise exception 'EXPECTED_DRAFT_DIRECT_DML_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_SOURCE_TREATMENT_DRAFT_RPC_ONLY' in sqlerrm)=0 then raise; end if;
  end;

  perform * from public.school_unlock_student_monthly_settlement(v_lock.settlement_id,v_marker);
  if (select count(*) from public.school_student_settlement_lesson_variance_claims
      where settlement_id=v_lock.settlement_id and claim_status='active')<>0
     or (select count(*) from public.school_student_settlement_lesson_variance_claims
      where settlement_id=v_lock.settlement_id and claim_status='released')<>2 then
    raise exception 'P0F_UNLOCK_RELEASE_FAILED';
  end if;
  perform * from public.school_set_student_settlement_source_treatment_draft(
    v_student,'2020-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2020-07-01',v_marker||' relock'
  );
  select * into strict v_relock
  from public.school_relock_student_monthly_settlement(v_lock.settlement_id,v_marker);
  if v_relock.carryover_amount_cny<>-624.75
     or (select count(*) from public.school_student_settlement_lesson_variance_claims
       where settlement_id=v_lock.settlement_id and claim_status='active')<>2
     or (select count(distinct claim_batch_id) from public.school_student_settlement_lesson_variance_claims
       where settlement_id=v_lock.settlement_id)<>2
     or (select max(claim_batch_version) from public.school_student_settlement_lesson_variance_claims
       where settlement_id=v_lock.settlement_id)<>2 then
    raise exception 'P0F_RELOCK_NEW_BATCH_FAILED';
  end if;

  -- Explicit old mode consumes its draft, creates no claims and preserves the
  -- legacy summary/adjustment contract.
  insert into public.school_income_records(
    id,business_entity_id,student_id,income_date,year_month,settlement_month,
    income_category,description,currency,amount,amount_cny,payment_currency,status,
    is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
    operational_excluded
  ) values(v_separate_income,v_entity,v_student,'2020-06-20','2020-06','2020-06',
    'tuition',v_marker,'CNY',100,100,'CNY','received',false,'codex-test',true,
    v_marker,'school',false);
  perform * from public.school_set_student_settlement_source_treatment_draft(
    v_student,'2020-06','separate_makeup_and_overage_v1',null,null,null,v_marker
  );
  select * into strict v_lock
  from public.school_lock_student_monthly_settlement(v_student,'2020-06',v_marker);
  if (select source_treatment_mode from public.school_student_monthly_settlements
      where id=v_lock.settlement_id)<>'separate_makeup_and_overage_v1'
     or exists(select 1 from public.school_student_monthly_settlements
       where id=v_lock.settlement_id and (settlement_exchange_rate is not null
         or net_lesson_variance_cny is not null))
     or exists(select 1 from public.school_student_settlement_lesson_variance_claims
       where settlement_id=v_lock.settlement_id)
     or (select status from public.school_student_settlement_source_treatment_drafts
       where student_id=v_student and year_month='2020-06')<>'consumed' then
    raise exception 'P0F_EXPLICIT_SEPARATE_MODE_COMPATIBILITY_FAILED';
  end if;

  -- Controlled post-Void lesson path with a separate fixed synthetic lesson.
  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
  ) values(v_void_lesson,'planned','2020-08-12','2020-08',v_student,v_teacher,v_subject,
    v_entity,'15:00','17:00',2,v_marker,'planned',true,v_marker,'school',8500,17000,1,
    'online',v_marker,'2020-08','2020-08-10','2020-08-12','2020-08',
    'explicit_billing_week_at_create',now());
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  insert into public.school_student_tuition_bills(
    id,student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,billing_role,cash_submission_blocked
  ) values(v_bill,v_student,v_entity,'2020-08','2020-07',v_net_settlement,-624.75,1,2,17000,17000,
    'JPY','cancelled','{}',v_marker,'school','canonical_charge',false);
  insert into public.school_student_tuition_billing_identities(
    id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
  ) values(v_legacy,v_student,'2020-08',v_bill,'codex-test-p0f-void','atomic_charge',v_marker,'{}');
  insert into public.school_student_tuition_bill_lessons(
    id,tuition_bill_id,planned_lesson_id,relation_role,line_no,student_id_snapshot,
    business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
    scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
    lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
    lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,
    attribution_confidence,snapshot_source,created_by
  ) select v_relation,v_bill,v_void_lesson,'canonical_charge',1,v_student,v_entity,'2020-08',
    '2020-08-10','2020-08-12',v_teacher,v_subject,1,2,8500,17000,updated_at,'{}',
    'high','student_tuition_atomic_generate_v1',v_marker
  from public.school_lesson_records where id=v_void_lesson;
  insert into public.school_student_tuition_generation_identities(
    id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
  ) values(v_generation,v_student,v_entity,'2020-08-01',v_legacy,now(),v_marker);
  insert into public.school_student_tuition_generation_revisions(
    id,generation_identity_id,tuition_bill_id,revision_no,generation_manifest_sha256,
    manifest_kind,lifecycle_status,created_at,created_by_authority,activated_at,
    voided_at,voided_by_authority
  ) values(v_revision,v_generation,v_bill,1,v_manifest,'atomic_generation_v1','voided',
    now(),v_marker,now(),now(),v_marker);
  delete from public.school_tuition_atomic_writer_context
  where backend_pid=pg_backend_pid() and transaction_id=txid_current();
  begin
    perform * from public.school_unlock_student_monthly_settlement(v_net_settlement,v_marker);
    raise exception 'EXPECTED_P0F_CONSUMED_SETTLEMENT_REJECTION_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  if (select count(*) from public.school_student_settlement_lesson_variance_claims
      where settlement_id=v_net_settlement and claim_status='active')<>2 then
    raise exception 'P0F_CONSUMED_SETTLEMENT_RELEASED_CLAIMS';
  end if;
  select updated_at into v_updated from public.school_lesson_records where id=v_void_lesson;
  perform * from public.school_void_planned_lesson(v_void_lesson,v_updated,v_marker);
  if (select voided_at is null from public.school_lesson_records where id=v_void_lesson)
     or (select count(*) from public.school_student_tuition_bill_lessons where id=v_relation)<>1
     or (select lifecycle_status from public.school_student_tuition_generation_revisions where id=v_revision)<>'voided' then
    raise exception 'P0F_CONTROLLED_LESSON_VOID_FAILED';
  end if;

  if has_table_privilege('anon','public.school_student_settlement_source_treatment_drafts','INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_student_settlement_lesson_variance_claims','INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_student_settlement_lesson_variance_claims','INSERT,UPDATE,DELETE')
     or not has_table_privilege('service_role','public.school_student_settlement_lesson_variance_claims','SELECT')
     or has_function_privilege('anon','public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)','EXECUTE') then
    raise exception 'P0F_PERMISSION_MATRIX_FAILED';
  end if;
end
$tests$;

rollback;
\echo 'P0F_ROLLBACK_MATRIX_PASSED'
