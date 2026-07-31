-- R2-E rollback-only acceptance matrix. No successful test write commits.
\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '240s';

CREATE TEMPORARY TABLE r2_e_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_row public.school_lesson_records%ROWTYPE;
  v_calc record;
  v_preview record;
  v_id uuid;
  v_zero_id uuid;
  v_rate_id uuid;
  v_batch_id uuid;
  v_import_id uuid;
  v_actual_id uuid;
  v_before_aircon jsonb;
  v_candidate_count integer;
  v_candidate_hours numeric;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  JOIN public.school_students student ON student.id = lesson.student_id
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND student.business_entity_id IS NOT DISTINCT FROM lesson.business_entity_id
  ORDER BY lesson.id
  LIMIT 1;

  -- Date/month/amount matrix is pure DB authority and includes the nullable
  -- date branch even though the operational lesson_date column is NOT NULL.
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-03','2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 0
     OR v_calc.aircon_rate_jpy_per_hour <> 330
     OR v_calc.lesson_total_fee_jpy <> 17000 THEN
    RAISE EXCEPTION 'R2_E_TEST_WEEKDAY_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 660
     OR v_calc.lesson_total_fee_jpy <> 17660 THEN
    RAISE EXCEPTION 'R2_E_TEST_SATURDAY_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-09','2026-08',3,17000,660
  );
  IF v_calc.aircon_fee_jpy <> 1980
     OR v_calc.lesson_total_fee_jpy <> 18980 THEN
    RAISE EXCEPTION 'R2_E_TEST_SUNDAY_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    NULL,'2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 0
     OR v_calc.aircon_rate_jpy_per_hour <> 330 THEN
    RAISE EXCEPTION 'R2_E_TEST_NULL_DATE_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-01','2026-07',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 0 THEN
    RAISE EXCEPTION 'R2_E_TEST_JULY_STUDENT_MONTH_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-09-05','2026-08',2,17000,330
  );
  IF v_calc.aircon_fee_jpy <> 660 THEN
    RAISE EXCEPTION 'R2_E_TEST_AUG31_BILLING_WEEK_FAILED';
  END IF;

  -- Legacy single signature: omitted rate creates complete zero state.
  SELECT created.lesson_id INTO STRICT v_zero_id
  FROM public.school_create_planned_lesson_record(
    DATE '2032-08-02',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    8500,NULL,'planned',1,'codex-test R2-E zero','codex-test r2-e'
  ) created;
  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id = v_zero_id;
  IF v_row.lesson_fee <> 17000
     OR v_row.base_lesson_fee_jpy <> 17000
     OR v_row.aircon_unit_price_jpy_snapshot <> 0
     OR v_row.aircon_fee_jpy <> 0
     OR v_row.lesson_total_fee_jpy <> 17000
     OR v_row.fee_calculation_version <> 'planned_weekend_aircon_v1' THEN
    RAISE EXCEPTION 'R2_E_TEST_LEGACY_SINGLE_ZERO_BUNDLE_FAILED';
  END IF;

  -- New venue overload: only rate is submitted; DB decides fee and total.
  SELECT created.id INTO STRICT v_rate_id
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2032-08-07',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    8500,NULL,'planned',2,'codex-test R2-E 330','codex-test r2-e',
    NULL,NULL,330
  ) created;
  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id = v_rate_id;
  IF v_row.lesson_fee <> 17000
     OR v_row.aircon_unit_price_jpy_snapshot <> 330
     OR v_row.aircon_fee_jpy <> 660
     OR v_row.lesson_total_fee_jpy <> 17660 THEN
    RAISE EXCEPTION 'R2_E_TEST_NEW_SINGLE_330_FAILED';
  END IF;

  -- Valid date changes recalculate fee while preserving the saved rate.
  UPDATE public.school_lesson_records
  SET lesson_date = DATE '2032-08-08'
  WHERE id = v_rate_id;
  IF (SELECT aircon_fee_jpy FROM public.school_lesson_records WHERE id=v_rate_id)
       <> 660 THEN
    RAISE EXCEPTION 'R2_E_TEST_WEEKEND_TO_WEEKEND_FAILED';
  END IF;
  UPDATE public.school_lesson_records
  SET lesson_date = DATE '2032-08-10'
  WHERE id = v_rate_id;
  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id=v_rate_id;
  IF v_row.aircon_fee_jpy <> 0
     OR v_row.aircon_unit_price_jpy_snapshot <> 330
     OR v_row.lesson_total_fee_jpy <> v_row.lesson_fee THEN
    RAISE EXCEPTION 'R2_E_TEST_WEEKEND_TO_WEEKDAY_FAILED';
  END IF;

  -- Both guarded update entry points preserve/rewrite only the rate input.
  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id=v_rate_id;
  PERFORM * FROM public.school_update_lesson_record_guarded(
    v_row.id,v_row.updated_at,v_row.lesson_date,v_row.student_id,
    v_row.teacher_id,v_row.subject_id,v_row.business_entity_id,
    v_row.start_time,v_row.end_time,v_row.duration_hours,v_row.unit_price,
    v_row.lesson_fee,v_row.status,v_row.is_billable,v_row.lesson_count,
    v_row.lesson_content,'codex-test r2-e core update',660
  );
  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id=v_rate_id;
  PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
    v_row.id,v_row.updated_at,v_row.lesson_date,v_row.student_id,
    v_row.teacher_id,v_row.subject_id,v_row.business_entity_id,
    v_row.start_time,v_row.end_time,v_row.duration_hours,v_row.unit_price,
    v_row.lesson_fee,v_row.status,v_row.is_billable,v_row.lesson_count,
    v_row.lesson_content,'codex-test r2-e venue update',
    v_row.lesson_delivery_mode,v_row.lesson_venue,330
  );

  -- Batch core and venue wrapper both write one independent rate per lesson.
  BEGIN
    SELECT result.created_lesson_id INTO STRICT v_batch_id
    FROM public.school_generate_planned_lessons_batch(
      'e2000000-0000-4000-8000-00000000b001',
      v_fixture.student_id,v_fixture.business_entity_id,
      DATE '2032-09-06',DATE '2032-09-06',
      jsonb_build_array(jsonb_build_object(
        'pattern_index',1,'weekday',1,'status','planned',
        'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
        'start_time','15:00','end_time','17:00','duration_hours',0,
        'unit_price',8500,'occurrence_count',1,'lesson_count',3,
        'lesson_content','codex-test R2-E batch',
        'aircon_rate_jpy_per_hour',330
      )),'[]'::jsonb,'codex-test r2-e'
    ) result
    WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
    IF (SELECT aircon_unit_price_jpy_snapshot
        FROM public.school_lesson_records WHERE id=v_batch_id) <> 330 THEN
      RAISE EXCEPTION 'R2_E_TEST_BATCH_CORE_RATE_FAILED';
    END IF;
    RAISE EXCEPTION 'R2_E_BATCH_CORE_SUBTX_DONE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R2_E_BATCH_CORE_SUBTX_DONE' THEN RAISE; END IF;
  END;

  SELECT result.created_lesson_id INTO STRICT v_batch_id
  FROM public.school_generate_planned_lessons_batch_with_venue(
    'e2000000-0000-4000-8000-00000000b002',
    v_fixture.student_id,v_fixture.business_entity_id,
    DATE '2032-09-13',DATE '2032-09-13',
    jsonb_build_array(jsonb_build_object(
      'pattern_index',1,'weekday',1,'status','planned',
      'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
      'start_time','15:00','end_time','17:00','duration_hours',0,
      'unit_price',8500,'occurrence_count',1,'lesson_count',4,
      'lesson_content','codex-test R2-E batch venue',
      'lesson_delivery_mode',NULL,'lesson_venue',NULL,
      'aircon_rate_jpy_per_hour',0
    )),'[]'::jsonb,'codex-test r2-e'
  ) result
  WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
  IF (SELECT aircon_unit_price_jpy_snapshot
      FROM public.school_lesson_records WHERE id=v_batch_id) <> 0 THEN
    RAISE EXCEPTION 'R2_E_TEST_BATCH_WRAPPER_ZERO_FAILED';
  END IF;

  -- Import core and venue wrapper use the same JSON field and default.
  BEGIN
    SELECT result.created_lesson_id INTO STRICT v_import_id
    FROM public.school_import_lesson_records_batch(
      'e2000000-0000-4000-8000-00000000c001',
      'codex-test-r2-e.csv','codex-test-r2-e-hash',
      jsonb_build_array(jsonb_build_object(
        'row_index',1,'source_row_no',2,'row_key','r2-e-import',
        'lesson_type','planned','status','planned','lesson_date','2032-10-02',
        'start_time','15:00','end_time','17:00','duration_hours',0,
        'lesson_count',5,'unit_price',8500,'lesson_fee',NULL,
        'is_billable',true,'student_id',v_fixture.student_id,
        'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
        'business_entity_id',v_fixture.business_entity_id,
        'planned_lesson_id',NULL,'lesson_content','codex-test R2-E import',
        'aircon_rate_jpy_per_hour',330
      )),'codex-test r2-e'
    ) result
    WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
    IF (SELECT aircon_unit_price_jpy_snapshot
        FROM public.school_lesson_records WHERE id=v_import_id) <> 330 THEN
      RAISE EXCEPTION 'R2_E_TEST_IMPORT_CORE_RATE_FAILED';
    END IF;
    RAISE EXCEPTION 'R2_E_IMPORT_CORE_SUBTX_DONE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R2_E_IMPORT_CORE_SUBTX_DONE' THEN RAISE; END IF;
  END;

  SELECT result.created_lesson_id INTO STRICT v_import_id
  FROM public.school_import_lesson_records_batch_with_venue(
    'e2000000-0000-4000-8000-00000000c002',
    'codex-test-r2-e-venue.csv','codex-test-r2-e-venue-hash',
    jsonb_build_array(jsonb_build_object(
      'row_index',1,'source_row_no',2,'row_key','r2-e-import-venue',
      'lesson_type','planned','status','planned','lesson_date','2032-10-03',
      'start_time','15:00','end_time','17:00','duration_hours',0,
      'lesson_count',6,'unit_price',8500,'lesson_fee',NULL,
      'is_billable',true,'student_id',v_fixture.student_id,
      'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
      'business_entity_id',v_fixture.business_entity_id,
      'planned_lesson_id',NULL,'lesson_content','codex-test R2-E import venue',
      'lesson_delivery_mode',NULL,'lesson_venue',NULL
    )),'codex-test r2-e'
  ) result
  WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
  IF (SELECT aircon_unit_price_jpy_snapshot
      FROM public.school_lesson_records WHERE id=v_import_id) <> 0 THEN
    RAISE EXCEPTION 'R2_E_TEST_IMPORT_WRAPPER_DEFAULT_FAILED';
  END IF;

  -- Direct clients may submit only rate. Forged/partial authority is rejected.
  BEGIN
    UPDATE public.school_lesson_records
    SET aircon_fee_jpy = 999999
    WHERE id = v_rate_id;
    RAISE EXCEPTION 'R2_E_EXPECTED_FORGED_FEE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'R2_E_EXPECTED_FORGED_FEE_REJECTION_MISSING' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records
    SET lesson_total_fee_jpy = NULL
    WHERE id = v_rate_id;
    RAISE EXCEPTION 'R2_E_EXPECTED_PARTIAL_BUNDLE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'R2_E_EXPECTED_PARTIAL_BUNDLE_REJECTION_MISSING' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.school_lesson_records (
      id,lesson_type,lesson_date,year_month,duration_hours,status,is_billable,
      app_type,unit_price,lesson_fee,aircon_fee_jpy
    ) VALUES (
      'e2000000-0000-4000-8000-00000000d001','planned','2032-08-07',
      '2032-08',2,'planned',true,'school',8500,17000,999999
    );
    RAISE EXCEPTION 'R2_E_EXPECTED_DIRECT_INSERT_FORGERY_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'R2_E_EXPECTED_DIRECT_INSERT_FORGERY_REJECTION_MISSING' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    INSERT INTO public.school_lesson_records (
      id,lesson_type,lesson_date,year_month,duration_hours,status,is_billable,
      app_type,unit_price,lesson_fee,aircon_unit_price_jpy_snapshot
    ) VALUES (
      'e2000000-0000-4000-8000-00000000d002','actual','2032-08-07',
      '2032-08',2,'completed',true,'school',8500,17000,330
    );
    RAISE EXCEPTION 'R2_E_EXPECTED_ACTUAL_AIRCON_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'R2_E_EXPECTED_ACTUAL_AIRCON_REJECTION_MISSING' THEN RAISE; END IF;
  END;

  -- Ordinary actual copies base fee only and cannot mutate source aircon facts.
  SELECT to_jsonb(lesson) - ARRAY['updated_at']::text[]
  INTO STRICT v_before_aircon
  FROM public.school_lesson_records lesson WHERE lesson.id=v_zero_id;
  SELECT actual.lesson_id INTO STRICT v_actual_id
  FROM public.school_create_actual_lesson_from_planned(
    v_zero_id,DATE '2032-08-02','15:00','17:00',2,8500,NULL,1,
    'codex-test R2-E actual','codex-test r2-e'
  ) actual;
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records actual
    WHERE actual.id=v_actual_id
      AND num_nonnulls(
        actual.base_lesson_fee_jpy,actual.aircon_charge_status,
        actual.aircon_unit_price_jpy_snapshot,
        actual.aircon_billable_hours_snapshot,actual.aircon_fee_jpy,
        actual.aircon_calculated_at,actual.fee_calculation_version,
        actual.lesson_total_fee_jpy
      ) > 0
  ) OR (SELECT to_jsonb(lesson) - ARRAY['updated_at']::text[]
        FROM public.school_lesson_records lesson WHERE lesson.id=v_zero_id)
       IS DISTINCT FROM v_before_aircon THEN
    RAISE EXCEPTION 'R2_E_TEST_ACTUAL_ISOLATION_FAILED';
  END IF;

  -- Candidate count/hours are unchanged; preview total is base + aircon.
  SELECT count(*)::integer,sum(duration_hours)
  INTO v_candidate_count,v_candidate_hours
  FROM public.school_list_student_tuition_charge_candidates(
    v_fixture.student_id,v_fixture.business_entity_id,'2032-08',false
  );
  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    v_fixture.student_id,'2032-08',0.05
  );
  IF v_preview.candidate_count <> v_candidate_count
     OR v_preview.total_duration_hours <> v_candidate_hours
     OR v_preview.total_fee_jpy
          <> v_preview.total_base_lesson_fee_jpy
             + v_preview.total_aircon_fee_jpy
     OR v_preview.total_aircon_fee_jpy <> 0
     OR jsonb_array_length(v_preview.candidates)
          <> v_preview.candidate_count THEN
    RAISE EXCEPTION 'R2_E_TEST_PREVIEW_CONTRACT_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_student_aircon_rates
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_venues
  ) THEN
    RAISE EXCEPTION 'R2_E_TEST_DYNAMIC_RATE_OR_VENUE_CREATED';
  END IF;

  INSERT INTO r2_e_results VALUES
    ('writer_entries',true,'legacy/new single, batch/import core+venue, guarded core+venue'),
    ('date_month_amount',true,'weekday/weekend/null date/July/August/cross-month week'),
    ('direct_invariant',true,'forged fee, partial bundle and actual aircon rejected'),
    ('actual_isolation',true,'ordinary actual leaves source planned fee bundle unchanged'),
    ('preview_contract',true,'candidate count/hours stable; base+aircon=total; one snapshot'),
    ('r0_and_history',true,'student dynamic rate and venue rows remain zero');

  RAISE NOTICE 'R2_E_TEST_LESSON_IDS=%,%,%,%,%,%',
    v_zero_id,v_rate_id,v_batch_id,v_import_id,v_actual_id,
    'e2000000-0000-4000-8000-00000000d001';
END
$tests$;

SELECT test_name,passed,detail
FROM r2_e_results ORDER BY test_name;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $residual$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id IN (
      'e2000000-0000-4000-8000-00000000d001',
      'e2000000-0000-4000-8000-00000000d002'
    )
       OR import_batch_id IN (
         'e2000000-0000-4000-8000-00000000b001',
         'e2000000-0000-4000-8000-00000000b002',
         'e2000000-0000-4000-8000-00000000c001',
         'e2000000-0000-4000-8000-00000000c002'
       )
  ) THEN
    RAISE EXCEPTION 'R2_E_ROLLBACK_TEST_RESIDUE';
  END IF;
END
$residual$;
SELECT true AS rollback_tests_pass,0 AS persisted_test_rows;
ROLLBACK;
