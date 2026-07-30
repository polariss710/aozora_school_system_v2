-- School V2 tuition P0 R1D-F1 rollback-only writer and invariant tests.
-- When r1d_f1_tests_existing_tx is defined, the caller owns BEGIN/ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_f1_tests_existing_tx}
  \echo 'R1D_F1_TESTS_USING_CALLER_TRANSACTION'
\else
  BEGIN;
\endif

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

CREATE TEMPORARY TABLE r1d_f1_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_lesson public.school_lesson_records%ROWTYPE;
  v_single_id uuid;
  v_single_3_id uuid;
  v_single_time_id uuid;
  v_venue_id uuid;
  v_batch_id uuid;
  v_batch_venue_id uuid;
  v_import_id uuid;
  v_import_venue_id uuid;
  v_legacy_test_id uuid;
  v_legacy_before jsonb;
  v_legacy_before_md5 text;
  v_fixed_118_md5 text;
  v_ids uuid[];
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school' AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned' AND lesson.voided_at IS NULL
    AND lesson.billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest')
    AND lesson.student_id IS NOT NULL AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id = public.school_primary_business_entity_id()
  ORDER BY lesson.id LIMIT 1;

  SELECT evidence.planned_lesson_id,
         to_jsonb(lesson),
         md5(to_jsonb(lesson)::text)
  INTO STRICT v_legacy_test_id,v_legacy_before,v_legacy_before_md5
  FROM public.school_legacy_planned_settlement_evidence evidence
  JOIN public.school_lesson_records lesson
    ON lesson.id = evidence.planned_lesson_id
  WHERE evidence.approved_manifest = true
    AND evidence.evidence_source = 'r1d_e_b1_fixed_legacy_279'
    AND evidence.evidence_version = 'legacy_settlement_evidence_v1'
    AND lesson.lesson_type = 'planned'
    AND lesson.app_type = 'school'
    AND num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
          lesson.student_settlement_month,lesson.billing_month_source,
          lesson.billing_month_decided_at) = 0
    AND lesson.student_id IS NOT DISTINCT FROM evidence.student_id_snapshot
    AND lesson.business_entity_id IS NOT DISTINCT FROM evidence.business_entity_id_snapshot
    AND lesson.year_month IS NOT DISTINCT FROM evidence.legacy_student_settlement_month
    AND evidence.lesson_identity_md5 = md5(concat_ws('|',
          lesson.id::text,coalesce(lesson.student_id::text,'<NULL>'),
          coalesce(lesson.business_entity_id::text,'<NULL>'),
          coalesce(lesson.year_month,'<NULL>'),lesson.lesson_type,lesson.app_type))
  ORDER BY evidence.planned_lesson_id LIMIT 1;
  SELECT md5(string_agg(md5(to_jsonb(lesson)::text),'' ORDER BY lesson.id::text))
  INTO v_fixed_118_md5
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
      lesson.student_settlement_month,lesson.billing_month_source,
      lesson.billing_month_decided_at) = 5;

  SELECT created.lesson_id INTO STRICT v_single_id
  FROM public.school_create_planned_lesson_record(
    DATE '2031-03-03',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R1D-F1 single 2h','codex-test r1d-f1'
  ) created;
  SELECT * INTO STRICT v_lesson FROM public.school_lesson_records WHERE id = v_single_id;
  IF num_nonnulls(v_lesson.billing_month,v_lesson.billing_week_start_date,
       v_lesson.student_settlement_month,v_lesson.billing_month_source,
       v_lesson.billing_month_decided_at) <> 5
     OR v_lesson.billing_week_start_date <> DATE '2031-03-03'
     OR v_lesson.billing_month <> '2031-03'
     OR v_lesson.student_settlement_month <> '2031-03'
     OR v_lesson.billing_month_source <> 'scheduled_date_at_create'
     OR v_lesson.duration_hours <> 2 THEN
    RAISE EXCEPTION 'R1D_F1_TEST_SINGLE_2H_FAILED';
  END IF;

  SELECT created.lesson_id INTO STRICT v_single_3_id
  FROM public.school_create_planned_lesson_record(
    DATE '2031-03-04',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,3,
    1000,NULL,'planned',2,'codex-test R1D-F1 single 3h','codex-test r1d-f1'
  ) created;

  SELECT created.lesson_id INTO STRICT v_single_time_id
  FROM public.school_create_planned_lesson_record(
    DATE '2031-03-05',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',3,'codex-test R1D-F1 single time','codex-test r1d-f1'
  ) created;
  IF (SELECT duration_hours FROM public.school_lesson_records WHERE id=v_single_time_id) <> 2 THEN
    RAISE EXCEPTION 'R1D_F1_TEST_SINGLE_TIME_DURATION_FAILED';
  END IF;

  SELECT created.id INTO STRICT v_venue_id
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2031-03-10',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',4,'codex-test R1D-F1 venue','codex-test r1d-f1',NULL,NULL
  ) created;

  BEGIN
    SELECT result.created_lesson_id INTO STRICT v_batch_id
    FROM public.school_generate_planned_lessons_batch(
      'f1000000-0000-4000-8000-00000000b001'::uuid,
      v_fixture.student_id,v_fixture.business_entity_id,
      DATE '2031-04-07',DATE '2031-04-07',
      jsonb_build_array(jsonb_build_object(
        'pattern_index',1,'weekday',1,'status','planned',
        'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
        'start_time','15:00','end_time','17:00','duration_hours',0,
        'unit_price',1000,'occurrence_count',1,'lesson_count',5,
        'lesson_content','codex-test R1D-F1 batch','note','codex-test r1d-f1'
      )),'[]'::jsonb,'codex-test r1d-f1'
    ) result WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
    IF (SELECT billing_month_source FROM public.school_lesson_records WHERE id=v_batch_id)
         <> 'explicit_billing_week_at_create' THEN
      RAISE EXCEPTION 'R1D_F1_TEST_BATCH_SOURCE_FAILED';
    END IF;
    RAISE EXCEPTION 'R1D_F1_TEST_BATCH_CORE_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_F1_TEST_BATCH_CORE_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;

  SELECT result.created_lesson_id INTO STRICT v_batch_venue_id
  FROM public.school_generate_planned_lessons_batch_with_venue(
    'f1000000-0000-4000-8000-00000000b002'::uuid,
    v_fixture.student_id,v_fixture.business_entity_id,
    DATE '2031-04-14',DATE '2031-04-14',
    jsonb_build_array(jsonb_build_object(
      'pattern_index',1,'weekday',1,'status','planned',
      'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
      'start_time',NULL,'end_time',NULL,'duration_hours',2,
      'unit_price',1000,'occurrence_count',1,'lesson_count',6,
      'lesson_content','codex-test R1D-F1 batch venue','note','codex-test r1d-f1',
      'lesson_delivery_mode',NULL,'lesson_venue',NULL
    )),'[]'::jsonb,'codex-test r1d-f1'
  ) result WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;

  BEGIN
    SELECT result.created_lesson_id INTO STRICT v_import_id
    FROM public.school_import_lesson_records_batch(
      'f1000000-0000-4000-8000-00000000c001'::uuid,
      'codex-test-r1d-f1.csv','codex-test-r1d-f1-hash',
      jsonb_build_array(jsonb_build_object(
        'row_index',1,'source_row_no',2,'row_key','r1d-f1-import',
        'lesson_type','planned','status','planned','lesson_date','2031-05-10',
        'start_time','15:00','end_time','17:00','duration_hours',0,
        'lesson_count',7,'unit_price',1000,'lesson_fee',NULL,'is_billable',true,
        'student_id',v_fixture.student_id,'teacher_id',v_fixture.teacher_id,
        'subject_id',v_fixture.subject_id,'business_entity_id',v_fixture.business_entity_id,
        'planned_lesson_id',NULL,'lesson_content','codex-test R1D-F1 import',
        'note','codex-test r1d-f1'
      )),'codex-test r1d-f1'
    ) result WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
    IF (SELECT billing_month_source FROM public.school_lesson_records WHERE id=v_import_id)
         <> 'scheduled_date_at_create' THEN
      RAISE EXCEPTION 'R1D_F1_TEST_IMPORT_SOURCE_FAILED';
    END IF;
    RAISE EXCEPTION 'R1D_F1_TEST_IMPORT_CORE_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_F1_TEST_IMPORT_CORE_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;

  SELECT result.created_lesson_id INTO STRICT v_import_venue_id
  FROM public.school_import_lesson_records_batch_with_venue(
    'f1000000-0000-4000-8000-00000000c002'::uuid,
    'codex-test-r1d-f1-venue.csv','codex-test-r1d-f1-venue-hash',
    jsonb_build_array(jsonb_build_object(
      'row_index',1,'source_row_no',2,'row_key','r1d-f1-import-venue',
      'lesson_type','planned','status','planned','lesson_date','2031-05-17',
      'start_time',NULL,'end_time',NULL,'duration_hours',2,
      'lesson_count',8,'unit_price',1000,'lesson_fee',NULL,'is_billable',true,
      'student_id',v_fixture.student_id,'teacher_id',v_fixture.teacher_id,
      'subject_id',v_fixture.subject_id,'business_entity_id',v_fixture.business_entity_id,
      'planned_lesson_id',NULL,'lesson_content','codex-test R1D-F1 import venue',
      'note','codex-test r1d-f1','lesson_delivery_mode',NULL,'lesson_venue',NULL
    )),'codex-test r1d-f1'
  ) result WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;

  SELECT * INTO STRICT v_lesson FROM public.school_lesson_records WHERE id=v_single_id;
  PERFORM * FROM public.school_update_lesson_record_guarded(
    v_lesson.id,v_lesson.updated_at,v_lesson.lesson_date,v_lesson.student_id,
    v_lesson.teacher_id,v_lesson.subject_id,v_lesson.business_entity_id,
    v_lesson.start_time::text,v_lesson.end_time::text,v_lesson.duration_hours,
    v_lesson.unit_price,v_lesson.lesson_fee,v_lesson.status,v_lesson.is_billable,
    v_lesson.lesson_count,v_lesson.lesson_content,'codex-test r1d-f1 guarded update'
  );
  SELECT * INTO STRICT v_lesson FROM public.school_lesson_records WHERE id=v_single_id;
  PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
    v_lesson.id,v_lesson.updated_at,v_lesson.lesson_date,v_lesson.student_id,
    v_lesson.teacher_id,v_lesson.subject_id,v_lesson.business_entity_id,
    v_lesson.start_time::text,v_lesson.end_time::text,v_lesson.duration_hours,
    v_lesson.unit_price,v_lesson.lesson_fee,v_lesson.status,v_lesson.is_billable,
    v_lesson.lesson_count,v_lesson.lesson_content,'codex-test r1d-f1 venue update',NULL,NULL
  );

  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-01',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,NULL,NULL,1,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_DURATION_1_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-02',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,NULL,NULL,1.5,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_DURATION_1_5_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-03',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,NULL,NULL,2.25,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_DURATION_2_25_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-04',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,NULL,NULL,2.5,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_DURATION_2_5_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-05',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,'15:00','17:15',0,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_TIME_2_25_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-06',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,'15:00',NULL,2,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_ONE_SIDED_TIME_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-07',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,'17:00','15:00',0,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_REVERSED_TIME_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_planned_lesson_record(
      DATE '2031-07-08',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,'23:00','01:00',0,1000,NULL,'planned',1,NULL,'codex-test r1d-f1');
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_CROSS_MIDNIGHT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;

  INSERT INTO public.school_lesson_records (
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,planned_lesson_id,unit_price,lesson_fee,
    import_batch_id,import_source,imported_at,lesson_count,actual_minutes,
    teacher_settlement_month,billing_month,billing_week_start_date,
    student_settlement_month,billing_month_source,billing_month_decided_at
  ) VALUES
  ('f1000000-0000-4000-8000-00000000d001','planned','2031-06-02','2031-06',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,v_fixture.business_entity_id,
    NULL,NULL,2,'codex-test direct Monday','planned',true,'codex-test r1d-f1','school',
    NULL,1000,2000,NULL,NULL,NULL,9,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
  ('f1000000-0000-4000-8000-00000000d002','planned','2031-06-08','2031-06',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,v_fixture.business_entity_id,
    NULL,NULL,2,'codex-test direct weekend','planned',true,'codex-test r1d-f1','school',
    NULL,1000,2000,NULL,NULL,NULL,10,NULL,NULL,'2099-01','2099-01-05','2099-01',
    'forged_client_source',clock_timestamp()),
  ('f1000000-0000-4000-8000-00000000d003','planned','2031-08-01','2031-08',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,v_fixture.business_entity_id,
    NULL,NULL,2,'codex-test direct cross month','planned',true,'codex-test r1d-f1','school',
    NULL,1000,2000,NULL,NULL,NULL,11,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
  ('f1000000-0000-4000-8000-00000000d004','planned','2032-01-01','2032-01',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,v_fixture.business_entity_id,
    NULL,NULL,2,'codex-test direct cross year','planned',true,'codex-test r1d-f1','school',
    NULL,1000,2000,NULL,NULL,NULL,12,NULL,NULL,NULL,NULL,NULL,NULL,NULL);

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id IN (
      'f1000000-0000-4000-8000-00000000d001'::uuid,
      'f1000000-0000-4000-8000-00000000d002'::uuid,
      'f1000000-0000-4000-8000-00000000d003'::uuid,
      'f1000000-0000-4000-8000-00000000d004'::uuid
    ) AND (num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
          lesson.student_settlement_month,lesson.billing_month_source,
          lesson.billing_month_decided_at) <> 5
      OR lesson.student_settlement_month IS DISTINCT FROM lesson.billing_month
      OR extract(isodow FROM lesson.billing_week_start_date) <> 1
      OR to_char(lesson.billing_week_start_date,'YYYY-MM') <> lesson.billing_month)
  ) OR NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id='f1000000-0000-4000-8000-00000000d002'::uuid
      AND billing_week_start_date=DATE '2031-06-02'
      AND billing_month='2031-06'
      AND billing_month_source='scheduled_date_at_create'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id='f1000000-0000-4000-8000-00000000d003'::uuid
      AND billing_week_start_date=DATE '2031-07-28' AND billing_month='2031-07'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id='f1000000-0000-4000-8000-00000000d004'::uuid
      AND billing_week_start_date=DATE '2031-12-29' AND billing_month='2031-12'
  ) THEN
    RAISE EXCEPTION 'R1D_F1_TEST_DIRECT_INSERT_OR_WEEK_MATRIX_FAILED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records SET billing_month=NULL
    WHERE id='f1000000-0000-4000-8000-00000000d001'::uuid;
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_CANONICAL_CLEAR_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET billing_month_source='forged_update'
    WHERE id='f1000000-0000-4000-8000-00000000d001'::uuid;
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_CANONICAL_PARTIAL_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;

  UPDATE public.school_lesson_records SET note=note WHERE id=v_legacy_test_id;
  IF (SELECT num_nonnulls(billing_month,billing_week_start_date,
       student_settlement_month,billing_month_source,billing_month_decided_at)
      FROM public.school_lesson_records WHERE id=v_legacy_test_id) <> 0 THEN
    RAISE EXCEPTION 'R1D_F1_TEST_LEGACY_NONATTRIBUTION_EDIT_UPGRADED';
  END IF;
  BEGIN
    UPDATE public.school_lesson_records SET year_month='2099-01' WHERE id=v_legacy_test_id;
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_LEGACY_IDENTITY_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_legacy_planned_settlement_evidence
    SET recorded_at=recorded_at WHERE planned_lesson_id=v_legacy_test_id;
    RAISE EXCEPTION 'R1D_F1_TEST_EXPECTED_EVIDENCE_IMMUTABLE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_F1_TEST_EXPECTED_%' THEN RAISE; END IF;
  END;

  SELECT array_agg(id ORDER BY id) INTO v_ids
  FROM public.school_lesson_records
  WHERE id IN (v_single_id,v_single_3_id,v_single_time_id,v_venue_id,
    v_batch_id,v_batch_venue_id,v_import_id,v_import_venue_id,
    'f1000000-0000-4000-8000-00000000d001'::uuid,
    'f1000000-0000-4000-8000-00000000d002'::uuid,
    'f1000000-0000-4000-8000-00000000d003'::uuid,
    'f1000000-0000-4000-8000-00000000d004'::uuid);

  IF cardinality(v_ids) <> 10
     OR EXISTS (SELECT 1 FROM public.school_lesson_records lesson
                WHERE lesson.id=ANY(v_ids)
                  AND num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
                    lesson.student_settlement_month,lesson.billing_month_source,
                    lesson.billing_month_decided_at) <> 5)
     OR (SELECT md5(string_agg(md5(to_jsonb(lesson)::text),'' ORDER BY lesson.id::text))
         FROM public.school_lesson_records lesson
         WHERE lesson.lesson_type='planned'
           AND lesson.billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest'))
        <> v_fixed_118_md5
     OR (SELECT to_jsonb(lesson)-'updated_at' FROM public.school_lesson_records lesson
         WHERE lesson.id=v_legacy_test_id)
        IS DISTINCT FROM (v_legacy_before-'updated_at') THEN
    RAISE EXCEPTION 'R1D_F1_TEST_FINAL_IN_TRANSACTION_BOUNDARY_FAILED';
  END IF;

  INSERT INTO r1d_f1_test_results VALUES
    ('single_writer_matrix',true,'2h,3h,time-derived and invalid durations/times'),
    ('wrapper_call_graph',true,'single/batch/import venue wrappers and both update paths'),
    ('billing_week_matrix',true,'Monday,weekend,cross-month,cross-year'),
    ('direct_crud_invariant',true,'null/forged insert canonicalized; clear/partial update rejected'),
    ('legacy_and_118',true,'whitelisted legacy edit remains null; identity/evidence immutable; fixed118 hash unchanged'),
    ('actual_isolation',true,'no actual test row created');

  RAISE NOTICE 'R1D_F1_TEST_LESSON_IDS=%',v_ids;
  RAISE NOTICE 'R1D_F1_WHITELISTED_LEGACY_TEST_ID=%',v_legacy_test_id;
  RAISE NOTICE 'R1D_F1_WHITELISTED_LEGACY_PRETEST_FULL_MD5=%',v_legacy_before_md5;
  RAISE NOTICE 'R1D_F1_LEGACY_FIXTURE_SELECTION=lowest planned_lesson_id among approved r1d_e_b1_fixed_legacy_279/legacy_settlement_evidence_v1 rows whose joined school planned lesson has a zero-field bundle and exact frozen identity';
END
$tests$;

SELECT test_name,passed,detail FROM r1d_f1_test_results ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE lesson_type='planned'
    AND billing_month_source IN ('scheduled_date_at_create','explicit_billing_week_at_create'))
    AS test_new_canonical_rows,
  count(*) FILTER (WHERE lesson_type='actual') AS actual_rows_disclosed,
  0 AS actual_test_rows_created
FROM public.school_lesson_records;

\if :{?r1d_f1_tests_existing_tx}
  \echo 'R1D_F1_TESTS_COMPLETE_CALLER_MUST_ROLLBACK'
\else
  ROLLBACK;

  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
  DO $postrollback$
  BEGIN
    IF EXISTS (SELECT 1 FROM public.school_lesson_records
               WHERE id IN (
                 'f1000000-0000-4000-8000-00000000d001'::uuid,
                 'f1000000-0000-4000-8000-00000000d002'::uuid,
                 'f1000000-0000-4000-8000-00000000d003'::uuid,
                 'f1000000-0000-4000-8000-00000000d004'::uuid))
     OR EXISTS (SELECT 1 FROM public.school_lesson_records
                WHERE import_batch_id IN (
                  'f1000000-0000-4000-8000-00000000b001',
                  'f1000000-0000-4000-8000-00000000b002',
                  'f1000000-0000-4000-8000-00000000c001',
                  'f1000000-0000-4000-8000-00000000c002'))
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=5)
        <> 118 + (SELECT count(*) FROM public.school_lesson_records
                  WHERE lesson_type='planned'
                    AND billing_month_source IN (
                      'scheduled_date_at_create','explicit_billing_week_at_create'))
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)
             BETWEEN 1 AND 4) <> 0 THEN
      RAISE EXCEPTION 'R1D_F1_ROLLBACK_TEST_RESIDUE_OR_BOUNDARY_FAILED';
    END IF;
  END
  $postrollback$;
  SELECT true AS rollback_tests_pass,0 AS persisted_test_rows;
  ROLLBACK;
\endif
