-- Rollback-only fixed-whitelist acceptance matrix for historical canonical preview reading.
-- Included after a SAVEPOINT by the cutover; no fixture write may commit.

CREATE TEMPORARY TABLE historical_canonical_preview_results(
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

CREATE PROCEDURE pg_temp.assert_historical_canonical_preview_error(
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

CREATE PROCEDURE pg_temp.begin_historical_canonical_writer_mutation()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO public.school_tuition_atomic_writer_context(
    backend_pid,transaction_id,writer_source
  ) VALUES (
    pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1'
  ) ON CONFLICT (backend_pid,transaction_id) DO NOTHING;
END
$procedure$;

DO $tests$
DECLARE
  v_student_atomic constant uuid := 'f2fe0000-0000-4000-8000-00000000a001';
  v_student_historical constant uuid := 'f2fe0000-0000-4000-8000-00000000a002';
  v_student_empty constant uuid := 'f2fe0000-0000-4000-8000-00000000a003';
  v_student_candidate constant uuid := 'f2fe0000-0000-4000-8000-00000000a004';
  v_hist_bill_id constant uuid := 'f2fe0000-0000-4000-8000-00000000b002';
  v_duplicate_bill_id constant uuid := 'f2fe0000-0000-4000-8000-00000000b003';
  v_missing_bill_id constant uuid := 'f2fe0000-0000-4000-8000-00000000b099';
  v_identityless_bill_id constant uuid := 'f2fe0000-0000-4000-8000-00000000b004';
  v_hist_income_id constant uuid := 'f2fe0000-0000-4000-8000-00000000c002';
  v_duplicate_income_id constant uuid := 'f2fe0000-0000-4000-8000-00000000c003';
  v_hist_identity_id constant uuid := 'f2fe0000-0000-4000-8000-00000000d002';
  v_hist_relation_id constant uuid := 'f2fe0000-0000-4000-8000-00000000e002';
  v_fixture public.school_lesson_records%ROWTYPE;
  v_alt_entity uuid;
  v_atomic_lesson uuid;
  v_hist_lesson uuid;
  v_candidate_lesson uuid;
  v_atomic_preview record;
  v_candidate_preview_before record;
  v_candidate_preview_after record;
  v_hist_preview record;
  v_atomic_generated record;
  v_hist_bill public.school_student_tuition_bills%ROWTYPE;
  v_hist_income public.school_income_records%ROWTYPE;
  v_hist_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_hist_line jsonb;
  v_check_rejected boolean := false;
  v_check_voided boolean := false;
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
    (v_student_atomic,'codex-hist-preview-a','codex-test historical preview atomic',
      'codex-test historical preview atomic',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test historical canonical preview reader'),
    (v_student_historical,'codex-hist-preview-b','codex-test historical preview canonical',
      'codex-test historical preview canonical',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test historical canonical preview reader'),
    (v_student_empty,'codex-hist-preview-c','codex-test historical preview empty',
      'codex-test historical preview empty',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test historical canonical preview reader'),
    (v_student_candidate,'codex-hist-preview-d','codex-test historical preview candidate',
      'codex-test historical preview candidate',v_fixture.business_entity_id,'active','school',
      0.05,0,'codex-test historical canonical preview reader');

  SELECT created.lesson_id INTO STRICT v_atomic_lesson
  FROM public.school_create_planned_lesson_record(
    DATE '2022-11-08',v_student_atomic,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,900,NULL,'planned',1,
    'codex-test historical preview atomic','codex-test historical canonical preview reader'
  ) created;
  SELECT created.lesson_id INTO STRICT v_hist_lesson
  FROM public.school_create_planned_lesson_record(
    DATE '2022-11-15',v_student_historical,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1000,NULL,'planned',2,
    'codex-test historical preview canonical','codex-test historical canonical preview reader'
  ) created;
  SELECT created.lesson_id INTO STRICT v_candidate_lesson
  FROM public.school_create_planned_lesson_record(
    DATE '2022-11-22',v_student_candidate,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,1200,NULL,'planned',3,
    'codex-test historical preview candidate','codex-test historical canonical preview reader'
  ) created;

  SELECT * INTO STRICT v_candidate_preview_before
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_candidate,'2022-11',0.05
  );
  SELECT * INTO STRICT v_candidate_preview_after
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_candidate,'2022-11',0.05
  );
  RAISE NOTICE 'HISTORICAL_CANONICAL_NORMAL_PREVIEW candidate_count=% lesson_count=% hours=% fee=% billing_cny=% manifest=%',
    v_candidate_preview_before.candidate_count,
    v_candidate_preview_before.total_lesson_count,
    v_candidate_preview_before.total_duration_hours,
    v_candidate_preview_before.total_fee_jpy,
    v_candidate_preview_before.billing_amount_cny,
    v_candidate_preview_before.generation_manifest_sha256;
  IF v_candidate_preview_before.candidate_count<>1
     OR v_candidate_preview_before.total_lesson_count<>3
     OR v_candidate_preview_before.total_duration_hours<>2
     OR v_candidate_preview_before.total_fee_jpy<>2400
     OR v_candidate_preview_before.billing_amount_cny<>120
     OR v_candidate_preview_before.generation_manifest_sha256 !~ '^[0-9a-f]{64}$'
     OR to_jsonb(v_candidate_preview_after) IS DISTINCT FROM to_jsonb(v_candidate_preview_before) THEN
    RAISE EXCEPTION 'HISTORICAL_CANONICAL_NORMAL_PREVIEW_CHANGED';
  END IF;
  INSERT INTO historical_canonical_preview_results VALUES
    (1,'normal_candidate_preview',true,'candidate amounts and generation manifest are stable');

  CALL pg_temp.assert_historical_canonical_preview_error(
    v_student_empty,'2022-11',0.05,'R2_F_B_CANDIDATES_EMPTY'
  );
  INSERT INTO historical_canonical_preview_results VALUES
    (2,'empty_without_identity',true,'no identity and no candidate remains candidates empty');

  SELECT * INTO STRICT v_atomic_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_atomic,'2022-11',0.05
  );
  SELECT * INTO STRICT v_atomic_generated
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_atomic,'2022-11',0.05,
    v_atomic_preview.generation_manifest_sha256,
    'codex-test historical canonical preview reader',NULL
  );
  CALL pg_temp.assert_historical_canonical_preview_error(
    v_student_atomic,'2022-11',0.05,'R2_F_B_ALREADY_BILLED'
  );
  INSERT INTO historical_canonical_preview_results VALUES
    (3,'atomic_complete_chain',true,'complete atomic_charge chain remains already billed');

  SELECT * INTO STRICT v_hist_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_historical,'2022-11',0.05
  );
  v_hist_line:=v_hist_preview.candidates->0;

  CALL pg_temp.begin_historical_canonical_writer_mutation();
  INSERT INTO public.school_student_tuition_bills(
    id,student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) VALUES (
    v_hist_bill_id,v_student_historical,v_fixture.business_entity_id,'2022-11',
    v_hist_preview.previous_settlement_month,v_hist_preview.previous_settlement_id,
    v_hist_preview.previous_carryover_cny,v_hist_preview.candidate_count,
    v_hist_preview.total_duration_hours,v_hist_preview.total_fee_jpy,
    v_hist_preview.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'historical_fixture',true,
      'planned_lesson_ids',jsonb_build_array(v_hist_lesson)
    ),'codex-test historical canonical preview reader','school','codex-test','codex-test',
    clock_timestamp(),clock_timestamp(),v_hist_preview.billing_exchange_rate,
    v_hist_preview.billing_amount_cny,clock_timestamp(),'canonical_charge',false
  );
  INSERT INTO public.school_student_tuition_billing_identities(
    id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
    source,created_by,evidence
  ) VALUES (
    v_hist_identity_id,v_student_historical,'2022-11',v_hist_bill_id,
    'codex-test:historical-canonical-preview:2022-11','historical_backfill',
    'codex-test',jsonb_build_object(
      'historical_fixture',true,'bill_id',v_hist_bill_id,'income_id',v_hist_income_id
    )
  );
  INSERT INTO public.school_student_tuition_bill_lessons(
    id,tuition_bill_id,planned_lesson_id,relation_role,line_no,
    student_id_snapshot,business_entity_id_snapshot,billing_month_snapshot,
    week_start_date_snapshot,scheduled_lesson_date_snapshot,
    teacher_id_snapshot,subject_id_snapshot,lesson_count_snapshot,
    duration_hours_snapshot,unit_price_jpy_snapshot,lesson_fee_jpy_snapshot,
    source_lesson_updated_at,source_snapshot,attribution_confidence,
    snapshot_source,created_by,base_lesson_fee_jpy_snapshot,
    aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
    aircon_fee_jpy_snapshot,fee_calculation_version_snapshot
  ) VALUES (
    v_hist_relation_id,v_hist_bill_id,v_hist_lesson,'canonical_charge',1,
    v_student_historical,v_fixture.business_entity_id,'2022-11',NULL,NULL,
    (v_hist_line->>'teacher_id')::uuid,(v_hist_line->>'subject_id')::uuid,
    (v_hist_line->>'lesson_count')::integer,(v_hist_line->>'duration_hours')::numeric,
    (v_hist_line->>'unit_price_jpy')::numeric,(v_hist_line->>'course_total_jpy')::numeric,
    (v_hist_line->>'source_lesson_updated_at')::timestamptz,
    jsonb_build_object('historical_fixture',true),'medium',
    'bill_json_exact_id_plus_current_source_fields_aggregate_verified','codex-test',
    (v_hist_line->>'base_lesson_fee_jpy')::numeric,
    (v_hist_line->>'aircon_rate_jpy_per_hour')::integer,
    (v_hist_line->>'aircon_billable_hours')::numeric,
    (v_hist_line->>'aircon_fee_jpy')::numeric,v_hist_line->>'fee_policy_version'
  );
  INSERT INTO public.school_income_records(
    id,business_entity_id,student_id,student_payment_id,account_id,income_date,
    year_month,settlement_month,income_category,description,currency,amount,
    amount_jpy,amount_cny,exchange_rate,payment_currency,payment_method,status,
    is_taxable_income,tax_category,receipt_status,include_in_student_settlement,
    note,source_type,source_id,source_label,source_snapshot,app_type,
    created_at,updated_at,tuition_bill_id,cash_submission_blocked,operational_excluded
  ) VALUES (
    v_hist_income_id,v_fixture.business_entity_id,v_student_historical,NULL,NULL,
    DATE '2022-11-01','2022-11','2022-11','tuition','2022-11 学费应收','JPY',
    v_hist_preview.total_fee_jpy,v_hist_preview.total_fee_jpy,NULL,NULL,'JPY',NULL,
    'pending',false,NULL,'Cash待提交',true,
    'codex-test historical canonical preview reader','student_tuition_bill',
    v_hist_bill_id,'2022-11 学费应收',jsonb_build_object(
      'historical_fixture',true,'billing_month','2022-11','tuition_bill_id',v_hist_bill_id
    ),'school',clock_timestamp(),clock_timestamp(),v_hist_bill_id,false,false
  );
  UPDATE public.school_student_tuition_bills bill SET
    status='income_created',income_record_id=v_hist_income_id,
    income_created_at=clock_timestamp(),updated_at=clock_timestamp()
  WHERE bill.id=v_hist_bill_id;

  SELECT bill.* INTO STRICT v_hist_bill
  FROM public.school_student_tuition_bills bill WHERE bill.id=v_hist_bill_id;
  SELECT income.* INTO STRICT v_hist_income
  FROM public.school_income_records income WHERE income.id=v_hist_income_id;
  SELECT identity_row.* INTO STRICT v_hist_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.id=v_hist_identity_id;
  PERFORM public.school_validate_tuition_identity_for_bill(v_hist_bill_id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_hist_bill_id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_hist_bill_id);

  CALL pg_temp.assert_historical_canonical_preview_error(
    v_student_historical,'2022-11',0.05,'R2_F_B_ALREADY_BILLED'
  );
  INSERT INTO historical_canonical_preview_results VALUES
    (4,'historical_pending_complete_chain',true,'complete historical_backfill pending chain is already billed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_income_records SET status='received' WHERE id=v_hist_income_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_ALREADY_BILLED'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_RECEIVED_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_RECEIVED_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (5,'historical_received_complete_chain',true,'complete historical_backfill received chain is already billed');

  BEGIN
    INSERT INTO public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
      source,created_by,evidence
    ) VALUES (
      'f2fe0000-0000-4000-8000-00000000d003',v_student_historical,'2022-11',
      v_hist_bill_id,'codex-test:duplicate-historical-identity','historical_backfill',
      'codex-test','{}'
    );
    RAISE EXCEPTION 'EXPECTED_DUPLICATE_HISTORICAL_IDENTITY_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (6,'historical_duplicate_identity',true,'unique identity backstop rejects duplicate student/month authority');

  BEGIN
    INSERT INTO public.school_student_tuition_billing_identities(
      id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
      source,created_by,evidence
    ) VALUES (
      'f2fe0000-0000-4000-8000-00000000d004',v_student_empty,'2022-11',
      v_missing_bill_id,'codex-test:missing-historical-bill','historical_backfill',
      'codex-test','{}'
    );
    RAISE EXCEPTION 'EXPECTED_MISSING_HISTORICAL_BILL_REJECTION_MISSING';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (7,'historical_missing_bill',true,'canonical-bill foreign key rejects missing historical bill');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET
      status='draft',income_record_id=NULL,income_created_at=NULL
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_MISSING_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_MISSING_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (8,'historical_missing_income',true,'missing linked income fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    INSERT INTO public.school_student_tuition_bills
    SELECT (jsonb_populate_record(NULL::public.school_student_tuition_bills,
      to_jsonb(v_hist_bill)||jsonb_build_object(
        'id',v_duplicate_bill_id,'status','draft','income_record_id',NULL,
        'income_created_at',NULL
      ))).*;
    RAISE EXCEPTION 'EXPECTED_DUPLICATE_HISTORICAL_BILL_REJECTION_MISSING';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (9,'historical_duplicate_bill',true,'canonical bill unique backstop rejects duplicate student/month bill');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    INSERT INTO public.school_income_records
    SELECT (jsonb_populate_record(NULL::public.school_income_records,
      to_jsonb(v_hist_income)||jsonb_build_object('id',v_duplicate_income_id))).*;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_DUPLICATE_HISTORICAL_INCOME_CASE';
  EXCEPTION WHEN unique_violation THEN NULL;
    WHEN OTHERS THEN
      IF SQLERRM<>'ROLLBACK_DUPLICATE_HISTORICAL_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (10,'historical_duplicate_income',true,'duplicate linked income is rejected or fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_income_records SET
      source_id='f2fe0000-0000-4000-8000-00000000c099'
    WHERE id=v_hist_income_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_REVERSE_LINK_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_REVERSE_LINK_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (11,'historical_reverse_link_mismatch',true,'bill and income reverse-link mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET student_id=v_student_empty
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_STUDENT_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_STUDENT_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (12,'historical_student_mismatch',true,'identity and bill student mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET business_entity_id=v_alt_entity
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_ENTITY_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_ENTITY_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (13,'historical_entity_mismatch',true,'historical business entity mismatch fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET billing_month='2022-12'
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_MONTH_MISMATCH_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_MONTH_MISMATCH_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (14,'historical_month_mismatch',true,'historical billing month mismatch fails closed');

  BEGIN
    INSERT INTO public.school_student_tuition_bill_lessons
    SELECT (jsonb_populate_record(NULL::public.school_student_tuition_bill_lessons,
      to_jsonb(relation)||jsonb_build_object(
        'id','f2fe0000-0000-4000-8000-00000000e003',
        'planned_lesson_id',v_candidate_lesson,'line_no',2
      ))).*
    FROM public.school_student_tuition_bill_lessons relation
    WHERE relation.id=v_hist_relation_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_RELATION_INCOMPLETE_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_RELATION_INCOMPLETE_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (15,'historical_normalized_relation_incomplete',true,'invalid normalized relation fails closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills
    SET planned_lesson_hours=planned_lesson_hours+1
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_VALIDATOR_FAILURE_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_VALIDATOR_FAILURE_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (16,'historical_validator_failure',true,'existing lesson validator failure remains fail closed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET
      status='cancelled',cancelled_at=clock_timestamp(),
      cancelled_reason='codex-test historical invalid bill'
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_CANCELLED_BILL_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_CANCELLED_BILL_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (17,'historical_cancelled_bill',true,'cancelled historical bill never reports already billed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_income_records SET
      status='cancelled',cancelled_at=clock_timestamp(),
      cancelled_reason='codex-test historical invalid income',cancelled_by='codex-test'
    WHERE id=v_hist_income_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_CANCELLED_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_CANCELLED_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (18,'historical_cancelled_income',true,'cancelled historical income never reports already billed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_income_records SET
      status='reversed',reversed_at=clock_timestamp()
    WHERE id=v_hist_income_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_REVERSED_INCOME_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_REVERSED_INCOME_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (19,'historical_reversed_income',true,'reversed historical income never reports already billed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET
      incident_locked_at=clock_timestamp(),
      incident_reason='codex-test historical incident'
    WHERE id=v_hist_bill_id;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_historical,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_HISTORICAL_INCIDENT_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_HISTORICAL_INCIDENT_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (20,'historical_incident_chain',true,'incident-locked historical chain never reports already billed');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_student_tuition_bills SET status='voided'
    WHERE id=v_hist_bill_id;
  EXCEPTION WHEN check_violation THEN v_check_voided:=true;
  END;
  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    UPDATE public.school_income_records SET status='rejected'
    WHERE id=v_hist_income_id;
  EXCEPTION WHEN check_violation THEN v_check_rejected:=true;
  END;
  IF NOT v_check_voided OR NOT v_check_rejected THEN
    RAISE EXCEPTION 'HISTORICAL_INVALID_STATUS_CHECK_BACKSTOP_FAILED';
  END IF;
  INSERT INTO historical_canonical_preview_results VALUES
    (21,'historical_voided_rejected_unrepresentable',true,'existing status checks reject voided and rejected states');

  BEGIN
    CALL pg_temp.begin_historical_canonical_writer_mutation();
    INSERT INTO public.school_student_tuition_bills
    SELECT (jsonb_populate_record(NULL::public.school_student_tuition_bills,
      to_jsonb(v_hist_bill)||jsonb_build_object(
        'id',v_identityless_bill_id,'student_id',v_student_candidate,
        'status','draft','income_record_id',NULL,'income_created_at',NULL,
        'source_snapshot',jsonb_build_object(
          'historical_fixture',true,
          'planned_lesson_ids',jsonb_build_array(v_candidate_lesson)
        )
      ))).*;
    CALL pg_temp.assert_historical_canonical_preview_error(
      v_student_candidate,'2022-11',0.05,'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'
    );
    RAISE EXCEPTION 'ROLLBACK_IDENTITYLESS_HISTORICAL_BILL_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_IDENTITYLESS_HISTORICAL_BILL_CASE' THEN RAISE; END IF;
  END;
  INSERT INTO historical_canonical_preview_results VALUES
    (22,'identityless_historical_bill',true,'identityless historical bill is never used as fallback');

  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'65e718ba8d2e4cb46ebb0dc84b11bc2e' THEN
    RAISE EXCEPTION 'HISTORICAL_CANONICAL_PROTECTED_FUNCTION_CHANGED_IN_MATRIX';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'HISTORICAL_CANONICAL_GATE_CHANGED_IN_MATRIX';
  END IF;
  INSERT INTO historical_canonical_preview_results VALUES
    (23,'protected_contracts_and_gates',true,'candidate reader, snapshot, atomic functions and gates remain unchanged');

  IF (SELECT count(*) FROM public.school_tuition_atomic_writer_context
      WHERE backend_pid=pg_backend_pid()
        AND transaction_id=txid_current()
        AND writer_source='student_tuition_atomic_generate_v1')<>1 THEN
    RAISE EXCEPTION 'HISTORICAL_CANONICAL_WRITER_CONTEXT_FIXTURE_SCOPE_FAILED';
  END IF;
  INSERT INTO historical_canonical_preview_results VALUES
    (24,'fixture_writer_context_scoped',true,'one transaction-scoped fixture capability will be removed by savepoint rollback');

  RAISE NOTICE 'HISTORICAL_CANONICAL_PREVIEW_FIXTURE_IDS students=%,%,%,%; lessons=%,%,%; atomic_bill=%; historical_bill=%; historical_identity=%; historical_income=%; historical_relation=%',
    v_student_atomic,v_student_historical,v_student_empty,v_student_candidate,
    v_atomic_lesson,v_hist_lesson,v_candidate_lesson,
    v_atomic_generated.tuition_bill_id,v_hist_bill_id,v_hist_identity_id,
    v_hist_income_id,v_hist_relation_id;
END
$tests$;

SELECT test_no,test_name,passed,detail
FROM historical_canonical_preview_results
ORDER BY test_no;

DO $assert_matrix$
BEGIN
  IF (SELECT count(*) FROM historical_canonical_preview_results)<>24
     OR EXISTS (SELECT 1 FROM historical_canonical_preview_results WHERE NOT passed) THEN
    RAISE EXCEPTION 'HISTORICAL_CANONICAL_PREVIEW_ROLLBACK_MATRIX_FAILED';
  END IF;
END
$assert_matrix$;
