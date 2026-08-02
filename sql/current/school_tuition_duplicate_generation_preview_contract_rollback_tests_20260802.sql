-- Rollback-only fixed-whitelist acceptance matrix.
-- This file is included after a SAVEPOINT by the cutover and never commits fixtures.

CREATE TEMPORARY TABLE tuition_duplicate_preview_results(
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

CREATE PROCEDURE pg_temp.assert_tuition_duplicate_preview_error(
  p_student uuid,p_month text,p_rate numeric,p_code text
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
  BEGIN
    PERFORM *
    FROM public.school_get_student_tuition_validation_preview_details(
      p_student,p_month,p_rate
    );
    RAISE EXCEPTION 'EXPECTED_PREVIEW_ERROR_MISSING:%',p_code;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_code IN SQLERRM)=0 THEN RAISE; END IF;
  END;
END
$procedure$;

CREATE PROCEDURE pg_temp.begin_tuition_duplicate_writer_mutation()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO public.school_tuition_atomic_writer_context(
    backend_pid,transaction_id,writer_source
  ) VALUES (
    pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1'
  );
END
$procedure$;

DO $tests$
DECLARE
  v_student_billed constant uuid := 'f2fd0000-0000-4000-8000-00000000a001';
  v_student_empty constant uuid := 'f2fd0000-0000-4000-8000-00000000a002';
  v_student_candidate constant uuid := 'f2fd0000-0000-4000-8000-00000000a003';
  v_missing_bill constant uuid := 'f2fd0000-0000-4000-8000-00000000b001';
  v_duplicate_bill constant uuid := 'f2fd0000-0000-4000-8000-00000000b002';
  v_duplicate_income constant uuid := 'f2fd0000-0000-4000-8000-00000000c002';
  v_orphan_income constant uuid := 'f2fd0000-0000-4000-8000-00000000c003';
  v_fixture public.school_lesson_records%ROWTYPE;
  v_alt_entity uuid;
  v_billed_lesson uuid;
  v_candidate_lesson uuid;
  v_preview_before record;
  v_preview_after record;
  v_generated record;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_before_bill_hash text;
  v_before_income_hash text;
  v_before_identity_hash text;
  v_before_relation_hash text;
  v_after_bill_hash text;
  v_after_income_hash text;
  v_after_identity_hash text;
  v_after_relation_hash text;
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

  SELECT entity.id INTO STRICT v_alt_entity
  FROM public.school_business_entities entity
  WHERE entity.id<>v_fixture.business_entity_id
  ORDER BY entity.id LIMIT 1;

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES
    (v_student_billed,'codex-duplicate-preview-a','codex-test duplicate preview billed',
      'codex-test duplicate preview billed',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test duplicate preview contract'),
    (v_student_empty,'codex-duplicate-preview-b','codex-test duplicate preview empty',
      'codex-test duplicate preview empty',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test duplicate preview contract'),
    (v_student_candidate,'codex-duplicate-preview-c','codex-test duplicate preview candidate',
      'codex-test duplicate preview candidate',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test duplicate preview contract');

  SELECT created.lesson_id INTO STRICT v_billed_lesson
  FROM public.school_create_planned_lesson_record(
    DATE '2022-11-08',v_student_billed,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1000,NULL,'planned',1,
    'codex-test duplicate preview billed','codex-test duplicate preview contract'
  ) created;
  SELECT created.lesson_id INTO STRICT v_candidate_lesson
  FROM public.school_create_planned_lesson_record(
    DATE '2022-11-15',v_student_candidate,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1200,NULL,'planned',2,
    'codex-test duplicate preview candidate','codex-test duplicate preview contract'
  ) created;

  SELECT * INTO STRICT v_preview_before
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_candidate,'2022-11',0.05
  );
  IF v_preview_before.candidate_count<>1
     OR v_preview_before.total_lesson_count<>2
     OR v_preview_before.total_duration_hours<>2
     OR v_preview_before.total_fee_jpy<>2400
     OR v_preview_before.billing_amount_cny<>120
     OR v_preview_before.generation_manifest_sha256 !~ '^[0-9a-f]{64}$'
     OR v_preview_before.generate_feature_state<>'enabled' THEN
    RAISE EXCEPTION 'NORMAL_CANDIDATE_PREVIEW_CONTRACT_FAILED';
  END IF;
  SELECT * INTO STRICT v_preview_after
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_candidate,'2022-11',0.05
  );
  IF to_jsonb(v_preview_after) IS DISTINCT FROM to_jsonb(v_preview_before) THEN
    RAISE EXCEPTION 'NORMAL_CANDIDATE_PREVIEW_NOT_STABLE';
  END IF;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (1,'normal_candidate_preview',true,'amounts and generation manifest remain stable');

  CALL pg_temp.assert_tuition_duplicate_preview_error(
    v_student_empty,'2022-11',0.05,'R2_F_B_CANDIDATES_EMPTY'
  );
  INSERT INTO tuition_duplicate_preview_results VALUES
    (2,'empty_without_identity',true,'candidate zero remains R2_F_B_CANDIDATES_EMPTY');

  SELECT * INTO STRICT v_preview_before
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_billed,'2022-11',0.05
  );
  SELECT * INTO STRICT v_generated
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_billed,'2022-11',0.05,
    v_preview_before.generation_manifest_sha256,
    'codex-test duplicate preview contract',NULL
  );
  SELECT bill.* INTO STRICT v_bill
  FROM public.school_student_tuition_bills bill WHERE bill.id=v_generated.tuition_bill_id;
  SELECT income.* INTO STRICT v_income
  FROM public.school_income_records income WHERE income.id=v_generated.income_record_id;
  SELECT identity_row.* INTO STRICT v_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.id=v_generated.billing_identity_id;

  SELECT md5(to_jsonb(bill)::text) INTO v_before_bill_hash
  FROM public.school_student_tuition_bills bill WHERE bill.id=v_bill.id;
  SELECT md5(to_jsonb(income)::text) INTO v_before_income_hash
  FROM public.school_income_records income WHERE income.id=v_income.id;
  SELECT md5(to_jsonb(identity_row)::text) INTO v_before_identity_hash
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.id=v_identity.id;
  SELECT md5(coalesce(string_agg(md5(to_jsonb(relation)::text),'' ORDER BY relation.id::text),''))
  INTO v_before_relation_hash
  FROM public.school_student_tuition_bill_lessons relation
  WHERE relation.tuition_bill_id=v_bill.id;

  CALL pg_temp.assert_tuition_duplicate_preview_error(
    v_student_billed,'2022-11',0.05,'R2_F_B_ALREADY_BILLED'
  );

  SELECT md5(to_jsonb(bill)::text) INTO v_after_bill_hash
  FROM public.school_student_tuition_bills bill WHERE bill.id=v_bill.id;
  SELECT md5(to_jsonb(income)::text) INTO v_after_income_hash
  FROM public.school_income_records income WHERE income.id=v_income.id;
  SELECT md5(to_jsonb(identity_row)::text) INTO v_after_identity_hash
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.id=v_identity.id;
  SELECT md5(coalesce(string_agg(md5(to_jsonb(relation)::text),'' ORDER BY relation.id::text),''))
  INTO v_after_relation_hash
  FROM public.school_student_tuition_bill_lessons relation
  WHERE relation.tuition_bill_id=v_bill.id;
  IF v_after_bill_hash IS DISTINCT FROM v_before_bill_hash
     OR v_after_income_hash IS DISTINCT FROM v_before_income_hash
     OR v_after_identity_hash IS DISTINCT FROM v_before_identity_hash
     OR v_after_relation_hash IS DISTINCT FROM v_before_relation_hash THEN
    RAISE EXCEPTION 'PREVIEW_MUTATED_EXISTING_CHAIN';
  END IF;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (3,'complete_chain_already_billed',true,'valid chain returns stable business error and remains unchanged');

  -- A received income is still an effective generated charge, not an invalid chain.
  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_income_records SET status='received' WHERE id=v_income.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(
      v_student_billed,'2022-11',0.05,'R2_F_B_ALREADY_BILLED'
    );
    RAISE EXCEPTION 'ROLLBACK_RECEIVED_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_RECEIVED_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (4,'received_chain_already_billed',true,'received canonical income remains a valid generated chain');

  -- The non-deferrable FK is the first fail-closed layer for a missing bill.
  BEGIN
    INSERT INTO public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
      source,created_by,evidence
    ) VALUES (
      'f2fd0000-0000-4000-8000-00000000d002',v_student_empty,'2022-11',
      v_missing_bill,'codex-test duplicate preview missing bill','atomic_charge',
      'codex-test',v_identity.evidence
    );
    RAISE EXCEPTION 'EXPECTED_MISSING_BILL_FK_REJECTION_MISSING';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (5,'identity_missing_bill',true,'non-deferrable canonical-bill FK rejects missing bill');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET status='draft',income_record_id=NULL,income_created_at=NULL
    WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_MISSING_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_MISSING_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (6,'bill_missing_income',true,'missing linked income fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    INSERT INTO public.school_student_tuition_bills
    SELECT (jsonb_populate_record(NULL::public.school_student_tuition_bills,
      to_jsonb(v_bill)||jsonb_build_object(
        'id',v_duplicate_bill,
        'income_record_id',v_duplicate_income
      ))).*;
    RAISE EXCEPTION 'EXPECTED_DUPLICATE_BILL_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    INSERT INTO public.school_income_records
    SELECT (jsonb_populate_record(NULL::public.school_income_records,
      to_jsonb(v_income)||jsonb_build_object(
        'id',v_duplicate_income,
        'source_id',v_orphan_income,
        'tuition_bill_id',NULL
      ))).*;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_DUPLICATE_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_DUPLICATE_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (7,'duplicate_bill_income',true,'bill unique index rejects duplicates; duplicate target income fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET student_id=v_student_empty WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_STUDENT_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_STUDENT_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (8,'student_mismatch',true,'identity/bill student mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET business_entity_id=v_alt_entity
    WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_ENTITY_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_ENTITY_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (9,'business_entity_mismatch',true,'bill business entity mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET billing_month='2022-12' WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_MONTH_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_MONTH_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (10,'billing_month_mismatch',true,'bill billing month mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_income_records
    SET source_id=v_orphan_income WHERE id=v_income.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_REVERSE_LINK_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_REVERSE_LINK_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (11,'income_reverse_link_mismatch',true,'bill/income reverse-link mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET status='cancelled',cancelled_at=clock_timestamp(),
        cancelled_reason='codex-test invalid chain'
    WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_CANCELLED_BILL_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_CANCELLED_BILL_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (12,'cancelled_bill_invalid',true,'cancelled bill never reports already billed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_income_records
    SET status='cancelled',cancelled_at=clock_timestamp(),
        cancelled_reason='codex-test invalid chain',cancelled_by='codex-test'
    WHERE id=v_income.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_CANCELLED_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_CANCELLED_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (13,'cancelled_income_invalid',true,'cancelled income never reports already billed');

  BEGIN
    CALL pg_temp.begin_tuition_duplicate_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET incident_locked_at=clock_timestamp(),incident_reason='codex-test invalid chain'
    WHERE id=v_bill.id;
    CALL pg_temp.assert_tuition_duplicate_preview_error(v_student_billed,'2022-11',0.05,
      'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE');
    RAISE EXCEPTION 'ROLLBACK_INCIDENT_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_INCIDENT_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (14,'incident_chain_invalid',true,'incident-locked bill never reports already billed');

  BEGIN
    INSERT INTO public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
      source,created_by,evidence
    ) VALUES (
      'f2fd0000-0000-4000-8000-00000000d001',v_student_billed,'2022-11',
      v_bill.id,'codex-test duplicate preview duplicate identity','atomic_charge',
      'codex-test',v_identity.evidence
    );
    RAISE EXCEPTION 'EXPECTED_DUPLICATE_IDENTITY_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (15,'duplicate_identity_backstop',true,'unique student/month identity prevents duplicate authority');

  CALL pg_temp.assert_tuition_duplicate_preview_error(
    NULL,'2022-11',0.05,'R2_F_B_STUDENT_REQUIRED'
  );
  CALL pg_temp.assert_tuition_duplicate_preview_error(
    v_student_empty,'bad-month',0.05,'R2_F_B_BILLING_MONTH_INVALID'
  );
  CALL pg_temp.assert_tuition_duplicate_preview_error(
    v_student_empty,'2022-11',0,'R2_F_B_EXCHANGE_RATE_INVALID'
  );
  INSERT INTO tuition_duplicate_preview_results VALUES
    (16,'input_validation_precedence',true,'student, month and rate validation remain first');

  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'WRITER_CONTEXT_RESIDUE_DURING_TEST';
  END IF;
  INSERT INTO tuition_duplicate_preview_results VALUES
    (17,'fixture_writer_context_clean',true,'atomic fixture writer context has no residue');

  RAISE NOTICE 'TUITION_DUPLICATE_PREVIEW_FIXTURE_IDS students=%,%,%; lessons=%,%; bill=%; identity=%; income=%',
    v_student_billed,v_student_empty,v_student_candidate,
    v_billed_lesson,v_candidate_lesson,v_bill.id,v_identity.id,v_income.id;
END
$tests$;

SELECT test_no,test_name,passed,detail
FROM tuition_duplicate_preview_results
ORDER BY test_no;

DO $assert_matrix$
BEGIN
  IF (SELECT count(*) FROM tuition_duplicate_preview_results)<>17
     OR EXISTS (SELECT 1 FROM tuition_duplicate_preview_results WHERE NOT passed) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_ROLLBACK_MATRIX_FAILED';
  END IF;
END
$assert_matrix$;
