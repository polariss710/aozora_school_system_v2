-- Committed School-only synthetic fixture for P0-C multi-session tests.
-- Required p0c_fixture_action: preflight | insert | cleanup | residue.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0c_fixture_action}
\else
  \echo 'P0C_FIXTURE_ACTION_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';
select set_config('tuition.p0c_fixture_action',:'p0c_fixture_action',true);

do $fixture$
declare
  v_action constant text:=current_setting('tuition.p0c_fixture_action');
  v_marker constant text:='codex-test atomic-void-reissue-p0c-20260803';
  v_entity constant uuid:='c0c00000-0000-4000-8000-00000000e001';
  v_subject constant uuid:='c0c00000-0000-4000-8000-00000000d001';
  v_teacher constant uuid:='c0c00000-0000-4000-8000-000000007001';
  v_student constant uuid:='c0c00000-0000-4000-8000-00000000a001';
  v_settlement constant uuid:='c0c00000-0000-4000-8000-00000000b001';
  v_lessons constant uuid[]:=array[
    'c0c00000-0000-4000-8000-000000001101'::uuid,
    'c0c00000-0000-4000-8000-000000001102'::uuid
  ];
  v_relations constant uuid[]:=array[
    'c0c00000-0000-4000-8000-000000005001'::uuid,
    'c0c00000-0000-4000-8000-000000005002'::uuid
  ];
  v_bill constant uuid:='c0c00000-0000-4000-8000-000000006001';
  v_income constant uuid:='c0c00000-0000-4000-8000-000000007101';
  v_legacy constant uuid:='c0c00000-0000-4000-8000-000000002001';
  v_generation constant uuid:='c0c00000-0000-4000-8000-000000003001';
  v_revision constant uuid:='c0c00000-0000-4000-8000-000000004001';
  v_snapshot record; v_line jsonb; v_line_no integer:=0; v_now timestamptz:=clock_timestamp();
begin
  if v_action not in ('preflight','insert','cleanup','residue') then
    raise exception 'P0C_FIXTURE_ACTION_INVALID';
  end if;
  if v_action in ('preflight','insert') and exists(
    select 1 from public.school_business_entities where id=v_entity or code='codex-test-p0c-void-reissue'
    union all select 1 from public.school_subjects where id=v_subject or name='codex-test P0-C subject'
    union all select 1 from public.school_teachers where id=v_teacher or teacher_code='codex-test-p0c-teacher'
    union all select 1 from public.school_students where id=v_student or student_code='codex-test-p0c-student'
    union all select 1 from public.school_lesson_records where id=any(v_lessons) or note=v_marker
    union all select 1 from public.school_student_monthly_settlements where id=v_settlement or note=v_marker
    union all select 1 from public.school_student_tuition_bills where id=v_bill or student_id=v_student
    union all select 1 from public.school_income_records where id=v_income or student_id=v_student
    union all select 1 from public.school_student_tuition_billing_identities where id=v_legacy or student_id=v_student
    union all select 1 from public.school_student_tuition_generation_identities where id=v_generation or student_id=v_student
  ) then raise exception 'P0C_FIXTURE_COLLISION'; end if;

  if v_action='insert' then
    insert into public.school_business_entities(id,code,name,entity_type,default_currency,is_active,note)
    values(v_entity,'codex-test-p0c-void-reissue','codex-test P0-C entity','company','JPY',true,v_marker);
    insert into public.school_subjects(id,name,category,is_active,note,primary_category)
    values(v_subject,'codex-test P0-C subject','codex-test',true,v_marker,'班课');
    insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
      default_business_entity_id,status,note,app_type)
    values(v_teacher,'codex-test-p0c-teacher','codex-test P0-C teacher','codex-test P0-C teacher',
      v_subject,v_entity,'active',v_marker,'school');
    insert into public.school_students(id,student_code,name,display_name,business_entity_id,status,
      app_type,preset_exchange_rate,previous_balance_cny,note)
    values(v_student,'codex-test-p0c-student','codex-test P0-C student','codex-test P0-C student',
      v_entity,'active','school',0.05,0,v_marker);
    insert into public.school_lesson_records(
      id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
      business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
      is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
      lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
      scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
    ) select lesson_id,'planned',lesson_date,'2020-08',v_student,v_teacher,v_subject,
      v_entity,'15:00','17:00',2,v_marker,'planned',true,v_marker,'school',
      10000,1,2,'online',v_marker,'2020-08',date_trunc('week',lesson_date::timestamp)::date,
      lesson_date,'2020-08','explicit_billing_week_at_create',statement_timestamp()
    from (values(v_lessons[1],date '2020-08-12'),(v_lessons[2],date '2020-08-19')) x(lesson_id,lesson_date);
    insert into public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id,preset_exchange_rate,
      planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
      actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
      received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
      carryover_amount_cny,settlement_status,locked_at,note,
      duration_overage_minutes,duration_overage_fee_jpy,duration_overage_fee_cny,
      duration_overage_actual_count,duration_overage_policy_version,duration_overage_source
    ) values(v_settlement,v_student,'2020-07',v_entity,0.05,0,0,0,0,0,0,0,0,0,0,0,
      'locked',v_now,v_marker,0,0,0,0,'student_duration_overage_v1','monthly_settlement_lock');

    select * into strict v_snapshot
    from public.school_build_student_tuition_generation_snapshot(v_student,'2020-08',0.05);
    if v_snapshot.candidate_count<>2 or v_snapshot.previous_settlement_id<>v_settlement then
      raise exception 'P0C_FIXTURE_SNAPSHOT_INVALID';
    end if;
    insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
    insert into public.school_student_tuition_bills(
      id,student_id,business_entity_id,billing_month,previous_settlement_month,
      previous_settlement_id,previous_carryover_cny,planned_lesson_count,
      planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
      source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
      billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
      billing_role,cash_submission_blocked
    ) values(v_bill,v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
      v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
      v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,v_snapshot.total_duration_hours,
      v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
        'generation_source','student_tuition_atomic_generate_v1',
        'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
        'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,'student_id',v_snapshot.student_id,
        'business_entity_id',v_snapshot.business_entity_id,'billing_month',v_snapshot.billing_month,
        'previous_settlement_month',v_snapshot.previous_settlement_month,
        'previous_settlement_id',v_snapshot.previous_settlement_id,
        'previous_carryover_cny',v_snapshot.previous_carryover_cny,
        'carryover_evidence',v_snapshot.carryover_evidence,
        'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
        'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
        'total_duration_hours',v_snapshot.total_duration_hours,
        'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
        'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
        'planned_lesson_ids',(select jsonb_agg(line->'planned_lesson_id') from jsonb_array_elements(v_snapshot.candidates) line),
        'candidate_lines',v_snapshot.candidates,'billing_exchange_rate',v_snapshot.billing_exchange_rate,
        'billing_amount_cny',v_snapshot.billing_amount_cny,'billing_amount_currency','CNY'
      ),v_marker,'school',v_marker,v_marker,v_now,v_now,v_snapshot.billing_exchange_rate,
      v_snapshot.billing_amount_cny,v_now,'canonical_charge',false);
    insert into public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
    ) values(v_legacy,v_student,'2020-08',v_bill,
      'student_tuition_atomic_generate_v1:'||v_snapshot.generation_manifest_sha256,
      'atomic_charge',v_marker,jsonb_build_object('generation_source','student_tuition_atomic_generate_v1',
        'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'business_entity_id',v_entity,'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
        'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex')));
    for v_line in select value from jsonb_array_elements(v_snapshot.candidates) loop
      v_line_no:=v_line_no+1;
      insert into public.school_student_tuition_bill_lessons(
        id,tuition_bill_id,planned_lesson_id,relation_role,line_no,student_id_snapshot,
        business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
        scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
        lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
        lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,
        attribution_confidence,snapshot_source,created_by,base_lesson_fee_jpy_snapshot,
        aircon_rate_id_snapshot,aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
        aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,lesson_venue_id_snapshot,
        lesson_venue_code_snapshot
      ) values(v_relations[v_line_no],v_bill,(v_line->>'planned_lesson_id')::uuid,
        'canonical_charge',v_line_no,(v_line->>'student_id')::uuid,
        (v_line->>'business_entity_id')::uuid,v_line->>'billing_month',
        (v_line->>'billing_week_start_date')::date,(v_line->>'lesson_date')::date,
        (v_line->>'teacher_id')::uuid,(v_line->>'subject_id')::uuid,
        (v_line->>'lesson_count')::integer,(v_line->>'duration_hours')::numeric,
        (v_line->>'unit_price_jpy')::numeric,(v_line->>'course_total_jpy')::numeric,
        (v_line->>'source_lesson_updated_at')::timestamptz,
        v_line||jsonb_build_object('generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
          'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256),
        'high','student_tuition_atomic_generate_v1',v_marker,
        (v_line->>'base_lesson_fee_jpy')::numeric,null,
        (v_line->>'aircon_rate_jpy_per_hour')::integer,(v_line->>'aircon_billable_hours')::numeric,
        (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
        nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code');
    end loop;
    insert into public.school_income_records(
      id,business_entity_id,student_id,student_payment_id,account_id,income_date,
      year_month,settlement_month,income_category,description,currency,amount,
      amount_jpy,amount_cny,exchange_rate,payment_currency,payment_method,status,
      is_taxable_income,tax_category,receipt_status,include_in_student_settlement,
      note,source_type,source_id,source_label,source_snapshot,app_type,created_at,
      updated_at,tuition_bill_id,cash_submission_blocked,operational_excluded
    ) values(v_income,v_entity,v_student,null,null,current_date,'2020-08','2020-08','tuition',
      'codex-test P0-C 学费应收','JPY',v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,
      null,null,'JPY',null,'pending',false,null,'Cash待提交',true,v_marker,
      'student_tuition_bill',v_bill,'codex-test P0-C 学费应收',jsonb_build_object(
        'generation_source','student_tuition_atomic_generate_v1',
        'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'tuition_bill_id',v_bill,'billing_identity_id',v_legacy,'billing_month','2020-08',
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
        'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
        'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
        'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
        'previous_settlement_month',v_snapshot.previous_settlement_month,
        'previous_settlement_id',v_snapshot.previous_settlement_id,
        'previous_carryover_cny',v_snapshot.previous_carryover_cny,
        'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
        'billing_exchange_rate',v_snapshot.billing_exchange_rate,
        'billing_amount_cny',v_snapshot.billing_amount_cny,'billing_amount_currency','CNY'),
      'school',v_now,v_now,v_bill,false,false);
    update public.school_student_tuition_bills set status='income_created',income_record_id=v_income,
      income_created_at=v_now,updated_at=v_now where id=v_bill;
    insert into public.school_student_tuition_generation_identities(
      id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
    ) values(v_generation,v_student,v_entity,date '2020-08-01',v_legacy,v_now,v_marker);
    insert into public.school_student_tuition_generation_revisions(
      id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
      generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,
      created_by_authority,activated_at,voided_at,voided_by_authority
    ) values(v_revision,v_generation,v_bill,1,null,v_snapshot.generation_manifest_sha256,
      'atomic_generation_v1','active',v_now,v_marker,v_now,null,null);
    delete from public.school_tuition_atomic_writer_context
    where backend_pid=pg_backend_pid() and transaction_id=txid_current();
    perform public.school_validate_tuition_identity_for_bill(v_bill);
    perform public.school_validate_tuition_bill_income_for_bill(v_bill);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    perform public.school_validate_tuition_generation_revision_for_bill(v_bill);
  elsif v_action='cleanup' then
    if (select count(*) from public.school_students where id=v_student and note=v_marker)<>1
       or (select count(*) from public.school_student_tuition_bills where id=v_bill and note=v_marker)<>1
       or (select count(*) from public.school_income_records where id=v_income and note=v_marker)<>1
       or (select count(*) from public.school_lesson_records where id=any(v_lessons) and note=v_marker)<>2
       or (select count(*) from public.school_student_tuition_generation_identities where id=v_generation and created_by_authority=v_marker)<>1
       or (select count(*) from public.school_student_tuition_generation_revisions where id=v_revision and created_by_authority=v_marker)<>1 then
      raise exception 'P0C_FIXTURE_CLEANUP_OWNERSHIP_FAILED';
    end if;
    perform set_config('tuition.p0c_fixture_cleanup',v_marker,true);
    insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
    delete from public.school_student_tuition_generation_void_events
      where id='c0c00000-0000-4000-8000-000000008001';
    delete from public.school_student_tuition_generation_revisions where id=v_revision;
    delete from public.school_student_tuition_generation_identities where id=v_generation;
    delete from public.school_student_tuition_billing_identities where id=v_legacy;
    delete from public.school_student_tuition_bill_lessons where id=any(v_relations);
    update public.school_student_tuition_bills set status='cancelled',income_record_id=null where id=v_bill;
    delete from public.school_income_records where id=v_income;
    delete from public.school_student_tuition_bills where id=v_bill;
    delete from public.school_tuition_atomic_writer_context
      where backend_pid=pg_backend_pid() and transaction_id=txid_current();
    delete from public.school_student_monthly_settlements where id=v_settlement;
    delete from public.school_lesson_records where id=any(v_lessons);
    delete from public.school_students where id=v_student;
    delete from public.school_teachers where id=v_teacher;
    delete from public.school_subjects where id=v_subject;
    delete from public.school_business_entities where id=v_entity;
  end if;

  if v_action in ('preflight','cleanup','residue') and exists(
    select 1 from public.school_business_entities where id=v_entity or note=v_marker
    union all select 1 from public.school_subjects where id=v_subject or note=v_marker
    union all select 1 from public.school_teachers where id=v_teacher or note=v_marker
    union all select 1 from public.school_students where id=v_student or note=v_marker
    union all select 1 from public.school_lesson_records where id=any(v_lessons) or note=v_marker
    union all select 1 from public.school_student_monthly_settlements where id=v_settlement or note=v_marker
    union all select 1 from public.school_student_tuition_bills where id=v_bill or note=v_marker
    union all select 1 from public.school_income_records where id=v_income or note=v_marker
    union all select 1 from public.school_student_tuition_billing_identities where id=v_legacy
    union all select 1 from public.school_student_tuition_bill_lessons where id=any(v_relations)
    union all select 1 from public.school_student_tuition_generation_identities where id=v_generation
    union all select 1 from public.school_student_tuition_generation_revisions where id=v_revision
    union all select 1 from public.school_student_tuition_generation_void_events where id='c0c00000-0000-4000-8000-000000008001'
    union all select 1 from public.school_personal_cash_income_linkage_events where income_record_id=v_income
  ) then raise exception 'P0C_FIXTURE_RESIDUE_NOT_ZERO'; end if;
end;
$fixture$;

select :'p0c_fixture_action' action,
  (select count(*) from public.school_students where id='c0c00000-0000-4000-8000-00000000a001') student_count,
  (select count(*) from public.school_student_tuition_generation_revisions where id='c0c00000-0000-4000-8000-000000004001') revision_count;
commit;
