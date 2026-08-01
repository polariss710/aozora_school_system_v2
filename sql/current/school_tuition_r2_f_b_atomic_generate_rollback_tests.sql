-- R2-F-B rollback-only acceptance matrix. No fixture write may commit.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_b_existing_tx}
  \echo 'R2_F_B_TESTS_USING_EXISTING_TRANSACTION'
\else
  BEGIN;
\endif

SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='240s';

CREATE TEMPORARY TABLE r2_f_b_results(
  test_name text PRIMARY KEY,passed boolean NOT NULL,detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_student_a constant uuid:='f2fb0000-0000-4000-8000-00000000a001';
  v_student_b constant uuid:='f2fb0000-0000-4000-8000-00000000a002';
  v_student_c constant uuid:='f2fb0000-0000-4000-8000-00000000a003';
  v_student_d constant uuid:='f2fb0000-0000-4000-8000-00000000a004';
  v_student_e constant uuid:='f2fb0000-0000-4000-8000-00000000a005';
  v_settlement_b constant uuid:='f2fb0000-0000-4000-8000-00000000b001';
  v_a1 uuid; v_a2 uuid; v_a_actual uuid;
  v_b1 uuid; v_c_source uuid; v_c_target uuid; v_c_actual uuid;
  v_d1 uuid; v_e_july uuid; v_e_august uuid;
  v_preview_a record; v_preview_a_rate2 record; v_preview_b record;
  v_preview_c record;
  v_preview_a_unchanged record;
  v_preview_d record; v_result_a record; v_result_a2 record; v_result_b record;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_relation_count integer; v_candidate_count integer; v_overage record;
  v_generic_income uuid:='f2fb0000-0000-4000-8000-00000000c001';
  v_failed boolean;
  v_alt_teacher uuid; v_alt_subject uuid; v_bad_rate numeric;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  JOIN public.school_students student ON student.id=lesson.student_id
  WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
    AND lesson.status='planned' AND lesson.voided_at IS NULL
    AND lesson.teacher_id IS NOT NULL AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND student.business_entity_id IS NOT DISTINCT FROM lesson.business_entity_id
  ORDER BY lesson.id LIMIT 1;

  SELECT lesson.teacher_id INTO STRICT v_alt_teacher
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type='school' AND lesson.teacher_id IS NOT NULL
    AND lesson.teacher_id<>v_fixture.teacher_id
  ORDER BY lesson.teacher_id LIMIT 1;
  SELECT lesson.subject_id INTO STRICT v_alt_subject
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type='school' AND lesson.subject_id IS NOT NULL
    AND lesson.subject_id<>v_fixture.subject_id
  ORDER BY lesson.subject_id LIMIT 1;

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES
    (v_student_a,'codex-r2fb-a','codex-test R2-F-B A','codex-test R2-F-B A',v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-b'),
    (v_student_b,'codex-r2fb-b','codex-test R2-F-B B','codex-test R2-F-B B',v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-b'),
    (v_student_c,'codex-r2fb-c','codex-test R2-F-B C','codex-test R2-F-B C',v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-b'),
    (v_student_d,'codex-r2fb-d','codex-test R2-F-B D','codex-test R2-F-B D',v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-b'),
    (v_student_e,'codex-r2fb-e','codex-test R2-F-B E','codex-test R2-F-B E',v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-b');

  SELECT created.id INTO STRICT v_a1
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2022-08-07',v_student_a,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',2,
    'codex-test R2-F-B A1','codex-test r2-f-b','online','codex-test venue A',330
  ) created;
  SELECT created.id INTO STRICT v_a2
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2022-08-08',v_student_a,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',3,
    'codex-test R2-F-B A2','codex-test r2-f-b',NULL,NULL,660
  ) created;
  SELECT actual.lesson_id INTO STRICT v_a_actual
  FROM public.school_create_actual_lesson_from_planned(
    v_a1,DATE '2022-08-07','15:00','17:15',2.25,10000,NULL,2,
    'codex-test R2-F-B actual','codex-test r2-f-b'
  ) actual;
  INSERT INTO public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
    student_settlement_month
  ) SELECT 'f2fb0000-0000-4000-8000-00000000d001', 'actual',lesson_date,
    year_month,student_id,teacher_id,subject_id,business_entity_id,start_time,
    end_time,duration_hours,'codex-test partial','partial',true,'codex-test r2-f-b',
    'school',id,unit_price,lesson_fee,lesson_count,student_settlement_month
  FROM public.school_lesson_records WHERE id=v_a2;
  INSERT INTO public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
    student_settlement_month
  ) SELECT 'f2fb0000-0000-4000-8000-00000000d002','actual',lesson_date,
    year_month,student_id,teacher_id,subject_id,business_entity_id,start_time,
    end_time,duration_hours,'codex-test makeup','makeup',true,'codex-test r2-f-b',
    'school',id,unit_price,lesson_fee,lesson_count,student_settlement_month
  FROM public.school_lesson_records WHERE id=v_a2;
  SELECT created.lesson_id INTO STRICT v_d1
  FROM public.school_create_planned_lesson_record(
    DATE '2022-08-14',v_student_a,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',1,
    'codex-test cancelled candidate','codex-test r2-f-b'
  ) created;
  UPDATE public.school_lesson_records lesson
  SET status='cancelled' WHERE lesson.id=v_d1;

  SELECT * INTO STRICT v_preview_a
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2022-08',0.05
  );
  SELECT * INTO STRICT v_preview_a_rate2
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2022-08',0.06
  );
  IF v_preview_a.generation_manifest_sha256=v_preview_a_rate2.generation_manifest_sha256
     OR v_preview_a.candidate_count<>2 OR v_preview_a.total_lesson_count<>5
     OR v_preview_a.total_duration_hours<>4
     OR v_preview_a.total_base_lesson_fee_jpy<>40000
     OR v_preview_a.total_aircon_fee_jpy<>0
     OR v_preview_a.total_fee_jpy<>40000
     OR v_preview_a.total_fee_jpy<>
          v_preview_a.total_base_lesson_fee_jpy+v_preview_a.total_aircon_fee_jpy
     OR v_preview_a.previous_carryover_cny<>0
     OR jsonb_array_length(v_preview_a.candidates)<>2 THEN
    RAISE EXCEPTION 'R2_F_B_PREVIEW_AND_MANIFEST_MATRIX_FAILED candidates=% lessons=% hours=% base=% aircon=% total=% carryover=%',
      v_preview_a.candidate_count,v_preview_a.total_lesson_count,
      v_preview_a.total_duration_hours,v_preview_a.total_base_lesson_fee_jpy,
      v_preview_a.total_aircon_fee_jpy,v_preview_a.total_fee_jpy,
      v_preview_a.previous_carryover_cny;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_list_student_tuition_charge_candidates(
      v_student_a,v_fixture.business_entity_id,'2022-08',false
    ) candidate JOIN public.school_lesson_records lesson
      ON lesson.id=candidate.planned_lesson_id
    WHERE lesson.lesson_type<>'planned' OR lesson.status<>'planned'
  ) THEN RAISE EXCEPTION 'R2_F_B_NONPLANNED_CANDIDATE_INCLUDED'; END IF;

  -- Every frozen non-amount fact participates in the candidate manifest.
  BEGIN
    UPDATE public.school_lesson_records lesson SET teacher_id=v_alt_teacher
    WHERE lesson.id=v_a1;
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_TEACHER_STALE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_TEACHER_STALE_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records lesson SET subject_id=v_alt_subject
    WHERE lesson.id=v_a1;
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_SUBJECT_STALE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_SUBJECT_STALE_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records lesson
    SET lesson_venue='codex-test venue B' WHERE lesson.id=v_a1;
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_VENUE_STALE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_VENUE_STALE_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records lesson
    SET lesson_date=lesson.lesson_date-1 WHERE lesson.id=v_a1;
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_LESSON_DATE_STALE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_LESSON_DATE_STALE_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  SELECT * INTO STRICT v_preview_a_unchanged
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2022-08',0.05
  );
  IF v_preview_a_unchanged.generation_manifest_sha256
       IS DISTINCT FROM v_preview_a.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_B_UNCHANGED_MANIFEST_NOT_STABLE';
  END IF;

  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,
      'codex-test public gate'
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_PUBLIC_GATE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_PUBLIC_GATE_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('TUITION_GENERATION_BLOCKED' IN SQLERRM)=0 THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_result_a
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,
    'codex-test atomic A',NULL
  );
  IF v_result_a.idempotent OR v_result_a.bill_status<>'income_created'
     OR v_result_a.income_status<>'pending' THEN
    RAISE EXCEPTION 'R2_F_B_ATOMIC_CREATE_RESULT_FAILED';
  END IF;
  SELECT * INTO STRICT v_bill FROM public.school_student_tuition_bills
  WHERE id=v_result_a.tuition_bill_id;
  SELECT * INTO STRICT v_income FROM public.school_income_records
  WHERE id=v_result_a.income_record_id;
  SELECT * INTO STRICT v_identity FROM public.school_student_tuition_billing_identities
  WHERE id=v_result_a.billing_identity_id;
  SELECT count(*)::integer INTO v_relation_count
  FROM public.school_student_tuition_bill_lessons relation
  WHERE relation.tuition_bill_id=v_bill.id;
  IF v_relation_count<>2 OR v_bill.income_record_id<>v_income.id
     OR v_income.tuition_bill_id<>v_bill.id OR v_income.source_id<>v_bill.id
     OR v_identity.canonical_bill_id<>v_bill.id
     OR v_bill.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_a.generation_manifest_sha256
     OR v_income.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_a.generation_manifest_sha256
     OR v_identity.evidence->>'generation_manifest_sha256'
          <>v_preview_a.generation_manifest_sha256
     OR v_bill.source_snapshot->>'carryover_evidence_sha256'
          IS DISTINCT FROM v_income.source_snapshot->>'carryover_evidence_sha256'
     OR v_bill.source_snapshot->>'carryover_evidence_sha256'
          IS DISTINCT FROM v_identity.evidence->>'carryover_evidence_sha256' THEN
    RAISE EXCEPTION 'R2_F_B_ATOMIC_FOUR_OBJECT_CONSISTENCY_FAILED';
  END IF;
  PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);

  SELECT * INTO STRICT v_result_a2
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,
    'ignored idempotent note',NULL
  );
  IF NOT v_result_a2.idempotent OR v_result_a2.tuition_bill_id<>v_result_a.tuition_bill_id
     OR v_result_a2.income_record_id<>v_result_a.income_record_id THEN
    RAISE EXCEPTION 'R2_F_B_IDEMPOTENT_RETURN_FAILED';
  END IF;
  BEGIN
    INSERT INTO public.school_tuition_atomic_writer_context(
      backend_pid,transaction_id,writer_source
    ) VALUES (pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
    UPDATE public.school_student_tuition_bills bill SET source_snapshot=jsonb_set(
      bill.source_snapshot,
      '{carryover_evidence,carryover_amount_cny}','1'::jsonb,false
    ) WHERE bill.id=v_result_a.tuition_bill_id;
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.05,v_preview_a.generation_manifest_sha256,
      NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_CARRYOVER_EVIDENCE_CONFLICT_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_CARRYOVER_EVIDENCE_CONFLICT_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.06,v_preview_a.generation_manifest_sha256,
      NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_EXISTING_RATE_CONFLICT_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_EXISTING_RATE_CONFLICT_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  FOREACH v_bad_rate IN ARRAY ARRAY[NULL::numeric,0::numeric,-1::numeric] LOOP
    BEGIN
      PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
        v_student_a,'2022-08',v_bad_rate,v_preview_a.generation_manifest_sha256,
        NULL,NULL
      );
      RAISE EXCEPTION 'R2_F_B_EXPECTED_INVALID_EXISTING_RATE_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM='R2_F_B_EXPECTED_INVALID_EXISTING_RATE_REJECTION_MISSING' THEN RAISE; END IF;
      IF position('R2_F_B_EXCHANGE_RATE_INVALID' IN SQLERRM)=0 THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2022-08',0.06,v_preview_a_rate2.generation_manifest_sha256,
      NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_MANIFEST_CONFLICT_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_MANIFEST_CONFLICT_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_cancel_pending_income_record(
      v_income.id,'codex-test atomic cancellation must fail','codex-test'
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_ATOMIC_CANCEL_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_ATOMIC_CANCEL_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('TUITION_ATOMIC_CANCEL_FORBIDDEN' IN SQLERRM)=0 THEN RAISE; END IF;
  END;

  -- Unique indexes are final concurrency backstops.
  BEGIN
    INSERT INTO public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
      source,created_by,evidence
    ) VALUES ('f2fb0000-0000-4000-8000-00000000e001',v_student_a,'2022-08',
      v_bill.id,'codex-test-duplicate-identity','atomic_charge','codex-test','{}');
    RAISE EXCEPTION 'R2_F_B_EXPECTED_IDENTITY_UNIQUE_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.school_student_tuition_bill_lessons
    SELECT 'f2fb0000-0000-4000-8000-00000000e002',tuition_bill_id,
      planned_lesson_id,relation_role,line_no+100,student_id_snapshot,
      business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
      scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
      lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
      lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,
      attribution_confidence,snapshot_source,backfill_batch_id,now(),created_by,
      base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
      aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
      aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,
      lesson_venue_id_snapshot,lesson_venue_code_snapshot
    FROM public.school_student_tuition_bill_lessons WHERE tuition_bill_id=v_bill.id LIMIT 1;
    RAISE EXCEPTION 'R2_F_B_EXPECTED_PLANNED_UUID_UNIQUE_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.school_tuition_atomic_writer_context(
      backend_pid,transaction_id,writer_source
    ) VALUES (pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
    INSERT INTO public.school_income_records
    SELECT (jsonb_populate_record(
      NULL::public.school_income_records,
      to_jsonb(v_income)||jsonb_build_object(
        'id','f2fb0000-0000-4000-8000-00000000e003'
      )
    )).*;
    RAISE EXCEPTION 'R2_F_B_EXPECTED_INCOME_UNIQUE_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL; END;

  -- Locked carryover is consumed exactly once by the DB calculation.
  INSERT INTO public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,carryover_amount_cny,
    settlement_status,locked_at,note
  ) VALUES (v_settlement_b,v_student_b,'2022-09',v_fixture.business_entity_id,
    123.45,'locked',now(),'codex-test r2-f-b locked carryover');
  SELECT created.lesson_id INTO STRICT v_b1
  FROM public.school_create_planned_lesson_record(
    DATE '2022-10-09',v_student_b,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',1,
    'codex-test R2-F-B B1','codex-test r2-f-b'
  ) created;
  SELECT * INTO STRICT v_preview_b
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_b,'2022-10',0.05
  );
  IF v_preview_b.previous_settlement_id<>v_settlement_b
     OR v_preview_b.previous_carryover_cny<>123.45
     OR v_preview_b.billing_amount_cny<>
       round(v_preview_b.total_fee_jpy*0.05+123.45,2) THEN
    RAISE EXCEPTION 'R2_F_B_LOCKED_CARRYOVER_CALCULATION_FAILED';
  END IF;
  SELECT * INTO STRICT v_result_b
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_b,'2022-10',0.05,v_preview_b.generation_manifest_sha256,NULL,NULL
  );

  -- Unlocked prior-month facts are not carryover authority. No locked row means zero.
  SELECT created.lesson_id INTO STRICT v_c_source
  FROM public.school_create_planned_lesson_record(
    DATE '2024-01-09',v_student_c,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1100,NULL,'planned',1,
    'codex-test R2-F-B overage source','codex-test r2-f-b'
  ) created;
  SELECT actual.lesson_id INTO STRICT v_c_actual
  FROM public.school_create_actual_lesson_from_planned(
    v_c_source,DATE '2024-03-09','15:00','17:30',2.5,9999,NULL,1,
    'codex-test R2-F-B overage actual','codex-test r2-f-b'
  ) actual;
  SELECT created.lesson_id INTO STRICT v_c_target
  FROM public.school_create_planned_lesson_record(
    DATE '2024-02-06',v_student_c,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1100,NULL,'planned',1,
    'codex-test R2-F-B target','codex-test r2-f-b'
  ) created;
  SELECT * INTO STRICT v_overage
  FROM public.school_get_student_duration_overage_aggregate(v_student_c,'2024-01');
  IF coalesce(v_overage.duration_overage_actual_count,0)<>1
     OR coalesce(v_overage.duration_overage_minutes,0)<>30 THEN
    RAISE EXCEPTION 'R2_F_B_OVERAGE_FIXTURE_INVALID';
  END IF;
  SELECT * INTO STRICT v_preview_c
  FROM public.school_build_student_tuition_generation_snapshot(
    v_student_c,'2024-02',0.05
  );
  IF v_preview_c.previous_settlement_id IS NOT NULL
     OR v_preview_c.previous_carryover_cny<>0
     OR v_preview_c.candidate_count<>1
     OR v_preview_c.billing_amount_cny<>round(v_preview_c.total_fee_jpy*0.05,2)
     OR v_preview_c.carryover_evidence->>'mode'<>'zero_carryover_verified_v1'
     OR v_preview_c.carryover_evidence->>'authority'<>'locked_previous_settlement_only'
     OR (v_preview_c.carryover_evidence->>'locked_settlement_count')::integer<>0 THEN
    RAISE EXCEPTION 'R2_F_B_NO_LOCKED_SETTLEMENT_ZERO_CARRYOVER_FAILED';
  END IF;

  -- Injected failure proves bill/identity/relation/income all roll back together.
  SELECT created.lesson_id INTO STRICT v_d1
  FROM public.school_create_planned_lesson_record(
    DATE '2025-08-11',v_student_d,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1000,NULL,'planned',1,
    'codex-test R2-F-B failure','codex-test r2-f-b'
  ) created;
  SELECT * INTO STRICT v_preview_d
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_d,'2025-08',0.05
  );
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_d,'2025-08',0.05,repeat('0',64),NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_STALE_MANIFEST_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_STALE_MANIFEST_REJECTION_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_d,'2025-08',0.05,v_preview_d.generation_manifest_sha256,
      NULL,'after_relations'
    );
    RAISE EXCEPTION 'R2_F_B_EXPECTED_INJECTED_FAILURE_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_INJECTED_FAILURE_MISSING' THEN RAISE; END IF;
    IF position('R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.school_student_tuition_bills WHERE student_id=v_student_d)
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_billing_identities WHERE student_id=v_student_d)
     OR EXISTS (SELECT 1 FROM public.school_income_records WHERE student_id=v_student_d)
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
       JOIN public.school_student_tuition_bills bill ON bill.id=relation.tuition_bill_id
       WHERE bill.student_id=v_student_d) THEN
    RAISE EXCEPTION 'R2_F_B_INJECTED_FAILURE_LEFT_RESIDUE';
  END IF;

  -- Exact cross-month natural-week boundaries remain canonical-reader facts.
  SELECT created.lesson_id INTO STRICT v_e_july
  FROM public.school_create_planned_lesson_record(
    DATE '2026-08-01',v_student_e,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1000,NULL,'planned',1,
    'codex-test R2-F-B July boundary','codex-test r2-f-b'
  ) created;
  SELECT created.lesson_id INTO STRICT v_e_august
  FROM public.school_create_planned_lesson_record(
    DATE '2026-09-05',v_student_e,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1000,NULL,'planned',1,
    'codex-test R2-F-B August boundary','codex-test r2-f-b'
  ) created;
  IF (SELECT billing_month FROM public.school_lesson_records WHERE id=v_e_july)<>'2026-07'
     OR (SELECT aircon_fee_jpy FROM public.school_lesson_records WHERE id=v_e_july)<>0
     OR (SELECT billing_month FROM public.school_lesson_records WHERE id=v_e_august)<>'2026-08' THEN
    RAISE EXCEPTION 'R2_F_B_CROSS_MONTH_BOUNDARY_FAILED';
  END IF;

  -- Historical 19 legacy duration differences remain outside authoritative overage.
  SELECT count(*)::integer INTO v_candidate_count
  FROM public.school_lesson_records lesson WHERE lesson.id IN (
    '14f0ad66-6a72-4562-bdf6-f867f5e7901d','1cb708d2-404b-4fed-a9cb-fb9b974da41c',
    '4645f239-d6f7-473f-96e0-75647cf2b937','4c0214ac-6ce5-4afd-b518-e3d6bd9ab978',
    '555faff7-6658-4860-8277-22f2bc4a9c65','5e0786c6-8b10-4e10-9e84-addaedd5509e',
    '6a3641db-4740-4d95-b1c9-8e3ae77516c2','6e16fea8-c408-421a-adc2-05107f987f5b',
    '714c671d-b98a-464f-afe2-629ed4ba148b','78301f55-e157-4219-8c29-8a87f5a8fa0b',
    '7f468446-13e2-489d-aec5-2b64aeca4f9a','a13b216e-4524-4315-b5aa-c1d2cc053082',
    'a7275d9c-15f1-4829-a78e-fc48b9e88e14','a97f7d25-061d-4504-a47e-53490ba81061',
    'acbc65c8-ba47-4595-b2db-244ae74f83d0','ae53ba74-3cb6-4090-ac7d-d19332dcad9d',
    'b74f743a-0acc-4156-9f00-2d6dfe388ce2','bb4a9aa8-f3dc-4681-a934-e049ff3dce33',
    'eefe54b0-5a01-4836-b1d1-ffcca570447d'
  ) AND lesson.student_duration_overage_policy_version IS NULL
    AND lesson.student_duration_overage_source IS NULL;
  IF v_candidate_count<>19 THEN RAISE EXCEPTION 'R2_F_B_HISTORICAL_19_OVERAGE_DRIFT'; END IF;

  -- Ordinary non-tuition pending cancellation remains operational.
  INSERT INTO public.school_income_records(
    id,business_entity_id,income_date,year_month,income_category,description,
    currency,amount,status,app_type,source_type,note
  ) VALUES (v_generic_income,v_fixture.business_entity_id,current_date,'2025-01',
    'other','codex-test ordinary income','JPY',1,'pending','school',
    'codex-test-r2-f-b','codex-test r2-f-b');
  PERFORM * FROM public.school_cancel_pending_income_record(
    v_generic_income,'codex-test ordinary cancellation','codex-test'
  );
  IF (SELECT status FROM public.school_income_records WHERE id=v_generic_income)<>'cancelled' THEN
    RAISE EXCEPTION 'R2_F_B_ORDINARY_INCOME_CANCEL_DAMAGED';
  END IF;

  IF (SELECT count(*) FROM pg_locks
      WHERE pid=pg_backend_pid() AND locktype='advisory' AND granted)<2 THEN
    RAISE EXCEPTION 'R2_F_B_ADVISORY_SERIALIZATION_LOCK_MISSING';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_B_WRITER_CONTEXT_RESIDUE_DURING_TEST';
  END IF;

  INSERT INTO r2_f_b_results VALUES
    ('01_candidate_count_unique',true,'two unique canonical planned candidates'),
    ('02_candidate_status_scope',true,'actual/partial/makeup/cancelled excluded'),
    ('03_candidate_amount_authority',true,'base + aircon = authoritative course total'),
    ('04_candidate_order_and_json',true,'stable two-line candidate JSON'),
    ('05_rate_changes_manifest',true,'exchange-rate change produces a new manifest'),
    ('06_teacher_stale_rejected',true,'teacher mutation invalidates manifest'),
    ('07_subject_stale_rejected',true,'subject mutation invalidates manifest'),
    ('08_venue_stale_rejected',true,'venue mutation invalidates manifest'),
    ('09_lesson_date_stale_rejected',true,'lesson-date mutation invalidates manifest'),
    ('10_unchanged_manifest_stable',true,'unchanged preview manifest is stable'),
    ('11_public_gate_blocked_before_release',true,'public writer remains blocked during matrix'),
    ('12_atomic_four_objects',true,'bill, identity, relations and pending income are exact'),
    ('13_atomic_validators',true,'all three authoritative validators pass'),
    ('14_idempotent_return',true,'repeat request returns the same four objects'),
    ('15_carryover_tamper_rejected',true,'frozen carryover evidence conflict rejected'),
    ('16_existing_rate_conflict',true,'existing identity rate conflict rejected'),
    ('17_invalid_rates_rejected',true,'null, zero and negative rates rejected'),
    ('18_manifest_conflict_rejected',true,'alternate valid manifest cannot replace identity'),
    ('19_atomic_cancel_rejected',true,'atomic tuition pending income cannot be cancelled'),
    ('20_unique_backstops',true,'identity, planned relation and tuition income uniqueness enforced'),
    ('21_locked_carryover_once',true,'locked previous carryover consumed exactly once'),
    ('22_no_locked_means_zero',true,'unlocked prior facts ignored; carryover is zero'),
    ('23_injected_failure_atomic',true,'post-relation failure leaves no atomic objects'),
    ('24_cross_month_week_authority',true,'July/August boundary weeks remain canonical'),
    ('25_legacy_actual_out_of_scope',true,'historical legacy overage rows remain excluded'),
    ('26_ordinary_income_unchanged',true,'ordinary non-tuition cancellation preserved'),
    ('27_advisory_locks',true,'student-month and global locks held'),
    ('28_writer_context_clean',true,'temporary writer context has no residue');

  RAISE NOTICE 'R2_F_B_FIXTURE_IDS=%,%,%,%,%,%,%,%',
    v_student_a,v_student_b,v_student_c,v_student_d,v_student_e,
    v_result_a.tuition_bill_id,v_result_a.billing_identity_id,v_result_a.income_record_id;
END
$tests$;

-- Direct client paths: bill DML is revoked; tuition income is rejected by RLS.
SET LOCAL ROLE authenticated;
DO $client_acl$
BEGIN
  BEGIN
    INSERT INTO public.school_student_tuition_bills DEFAULT VALUES;
    RAISE EXCEPTION 'R2_F_B_EXPECTED_DIRECT_BILL_PERMISSION_REJECTION_MISSING';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.school_income_records(
      id,income_date,year_month,income_category,currency,amount,status,app_type,
      source_type,source_id,tuition_bill_id
    ) VALUES ('f2fb0000-0000-4000-8000-00000000f001',current_date,'2025-01',
      'tuition','JPY',1,'pending','school','student_tuition_bill',
      'f2fb0000-0000-4000-8000-00000000f002',
      'f2fb0000-0000-4000-8000-00000000f002');
    RAISE EXCEPTION 'R2_F_B_EXPECTED_DIRECT_TUITION_INCOME_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_B_EXPECTED_DIRECT_TUITION_INCOME_REJECTION_MISSING' THEN
      RAISE;
    END IF;
    IF position('TUITION_GENERATION_BLOCKED' IN SQLERRM)=0
       AND position('TUITION_DIRECT_DML_FORBIDDEN' IN SQLERRM)=0
       AND SQLSTATE<>'42501' THEN
      RAISE;
    END IF;
  END;
  INSERT INTO public.school_income_records(
    id,income_date,year_month,income_category,description,currency,amount,
    status,app_type,source_type,note
  ) VALUES ('f2fb0000-0000-4000-8000-00000000f003',current_date,'2025-01',
    'other','codex-test authenticated ordinary income','JPY',1,'pending',
    'school','codex-test-r2-f-b','codex-test r2-f-b');
  UPDATE public.school_income_records income SET note='codex-test r2-f-b updated'
  WHERE income.id='f2fb0000-0000-4000-8000-00000000f003';
  IF NOT FOUND THEN RAISE EXCEPTION 'R2_F_B_AUTHENTICATED_ORDINARY_INCOME_UPDATE_FAILED'; END IF;
  DELETE FROM public.school_income_records income
  WHERE income.id='f2fb0000-0000-4000-8000-00000000f003';
  IF NOT FOUND THEN RAISE EXCEPTION 'R2_F_B_AUTHENTICATED_ORDINARY_INCOME_DELETE_FAILED'; END IF;
END
$client_acl$;
RESET ROLE;

SELECT test_name,passed,detail FROM r2_f_b_results ORDER BY test_name;

\if :{?r2_f_b_existing_tx}
  \echo 'R2_F_B_ROLLBACK_TESTS_PASS_PENDING_OUTER_ROLLBACK'
\else
  ROLLBACK;
  BEGIN TRANSACTION READ ONLY;
  DO $residual$
  BEGIN
    IF EXISTS (SELECT 1 FROM public.school_students
      WHERE id::text LIKE 'f2fb0000-0000-4000-8000-00000000a00%')
       OR EXISTS (SELECT 1 FROM public.school_lesson_records
         WHERE note='codex-test r2-f-b')
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_bills
         WHERE source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1')
       OR EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
      RAISE EXCEPTION 'R2_F_B_ROLLBACK_TEST_RESIDUE';
    END IF;
  END
  $residual$;
  SELECT true AS rollback_tests_pass,0 AS persisted_fixture_rows;
  ROLLBACK;
  \echo 'R2_F_B_ROLLBACK_TESTS_ROLLED_BACK'
\endif
