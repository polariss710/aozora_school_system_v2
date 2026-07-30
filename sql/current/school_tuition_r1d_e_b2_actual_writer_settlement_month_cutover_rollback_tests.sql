-- School V2 tuition P0 R1D-E-B2 rollback-only writer/invariant matrix.
-- Define r1d_e_b2_tests_existing_tx when the cutover rehearsal owns BEGIN/ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_b2_tests_existing_tx}
  \echo 'R1D_E_B2_TESTS_USING_CALLER_TRANSACTION'
\else
  BEGIN;
\endif

SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMPORARY TABLE r1d_e_b2_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_actual public.school_lesson_records%ROWTYPE;
  v_legacy_actual public.school_lesson_records%ROWTYPE;
  v_locked_actual public.school_lesson_records%ROWTYPE;
  v_wage_actual public.school_lesson_records%ROWTYPE;
  v_legacy_source public.school_lesson_records%ROWTYPE;
  v_legacy_source_md5 text;
  v_legacy_actual_md5 text;
  v_source_same uuid;
  v_source_cross uuid;
  v_source_cancel uuid;
  v_source_partial uuid;
  v_source_makeup uuid;
  v_source_direct_forged uuid;
  v_source_direct_null uuid;
  v_source_partial_bundle uuid;
  v_actual_same uuid;
  v_actual_cross uuid;
  v_actual_cancel uuid;
  v_actual_partial uuid;
  v_actual_makeup uuid;
  v_actual_wrapper uuid;
  v_actual_cross_wrapper uuid;
  v_actual_ids uuid[];
  v_evidence_count bigint;
  v_evidence_uuid_md5 text;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
    AND lesson.status='planned' AND lesson.voided_at IS NULL
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest','approved_r1c_c_b_manifest')
    AND lesson.student_id IS NOT NULL AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id=public.school_primary_business_entity_id()
  ORDER BY lesson.id LIMIT 1;

  SELECT lesson.*
  INTO STRICT v_legacy_source
  FROM public.school_legacy_planned_settlement_evidence evidence
  JOIN public.school_lesson_records lesson
    ON lesson.id=evidence.planned_lesson_id
  WHERE evidence.approved_manifest=true
    AND evidence.evidence_source='r1d_e_b1_fixed_legacy_279'
    AND evidence.evidence_version='legacy_settlement_evidence_v1'
    AND lesson.lesson_type='planned' AND lesson.app_type='school'
    AND lesson.status='planned' AND lesson.voided_at IS NULL
    AND num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
          lesson.student_settlement_month,lesson.billing_month_source,
          lesson.billing_month_decided_at)=0
    AND lesson.student_id IS NOT DISTINCT FROM evidence.student_id_snapshot
    AND lesson.business_entity_id IS NOT DISTINCT FROM evidence.business_entity_id_snapshot
    AND lesson.year_month IS NOT DISTINCT FROM evidence.legacy_student_settlement_month
    AND evidence.lesson_identity_md5=md5(concat_ws('|',lesson.id::text,
          coalesce(lesson.student_id::text,'<NULL>'),
          coalesce(lesson.business_entity_id::text,'<NULL>'),
          coalesce(lesson.year_month,'<NULL>'),lesson.lesson_type,lesson.app_type))
    AND NOT EXISTS (SELECT 1 FROM public.school_lesson_records a
                    WHERE a.lesson_type='actual'
                      AND a.planned_lesson_id=lesson.id)
    AND NOT EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
                    WHERE s.student_id=lesson.student_id
                      AND s.business_entity_id IS NOT DISTINCT FROM
                          lesson.business_entity_id
                      AND s.year_month=evidence.legacy_student_settlement_month
                      AND s.settlement_status='locked')
  ORDER BY evidence.planned_lesson_id LIMIT 1;
  v_legacy_source_md5:=md5(to_jsonb(v_legacy_source)::text);

  SELECT a.*
  INTO STRICT v_legacy_actual
  FROM public.school_legacy_actual_settlement_evidence e
  JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
  WHERE NOT EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
                    WHERE s.student_id=a.student_id
                      AND s.business_entity_id IS NOT DISTINCT FROM a.business_entity_id
                      AND s.year_month=e.legacy_year_month
                      AND s.settlement_status='locked')
    AND NOT EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details d
                    JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
                    WHERE d.lesson_record_id=a.id AND w.status='locked'
                      AND w.voided_at IS NULL)
    AND NOT EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
                    WHERE w.teacher_id=a.teacher_id
                      AND w.business_entity_id IS NOT DISTINCT FROM a.business_entity_id
                      AND w.settlement_month=e.teacher_settlement_month_snapshot
                      AND w.status='locked')
  ORDER BY a.id LIMIT 1;
  v_legacy_actual_md5:=md5(to_jsonb(v_legacy_actual)::text);

  SELECT a.* INTO STRICT v_locked_actual
  FROM public.school_legacy_actual_settlement_evidence e
  JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
  JOIN public.school_student_monthly_settlements s
    ON s.student_id=a.student_id
   AND s.business_entity_id IS NOT DISTINCT FROM a.business_entity_id
   AND s.year_month=e.legacy_year_month AND s.settlement_status='locked'
  ORDER BY a.id LIMIT 1;

  SELECT a.* INTO STRICT v_wage_actual
  FROM public.school_legacy_actual_settlement_evidence e
  JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
  JOIN public.school_teacher_wage_lock_details d ON d.lesson_record_id=a.id
  JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
  WHERE w.status='locked' AND w.voided_at IS NULL
  ORDER BY a.id LIMIT 1;

  SELECT count(*),md5(string_agg(actual_lesson_id::text,','
    ORDER BY actual_lesson_id::text))
  INTO v_evidence_count,v_evidence_uuid_md5
  FROM public.school_legacy_actual_settlement_evidence;

  SELECT lesson_id INTO STRICT v_source_same
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-03',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 ordinary same',
    'codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_source_cross
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-10',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 ordinary cross',
    'codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_source_cancel
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-17',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 cancelled',
    'codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_source_partial
  FROM public.school_create_planned_lesson_record(
    DATE '2033-01-24',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'15:00','17:00',0,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 partial',
    'codex-test r1d-e-b2');
  SELECT id INTO STRICT v_source_makeup
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2033-01-31',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,3,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 makeup',
    'codex-test r1d-e-b2','online',NULL);
  UPDATE public.school_lesson_records SET status='pending_makeup'
  WHERE id=v_source_makeup;
  SELECT lesson_id INTO STRICT v_source_direct_forged
  FROM public.school_create_planned_lesson_record(
    DATE '2033-02-07',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 direct forged',
    'codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_source_direct_null
  FROM public.school_create_planned_lesson_record(
    DATE '2033-02-14',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 direct null',
    'codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_source_partial_bundle
  FROM public.school_create_planned_lesson_record(
    DATE '2033-02-21',v_fixture.student_id,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,NULL,NULL,2,
    1000,NULL,'planned',1,'codex-test R1D-E-B2 partial bundle',
    'codex-test r1d-e-b2');

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_same,DATE '2033-01-03','15:00','16:00',1,1000,NULL,1,
      'codex-test ordinary too short','codex-test r1d-e-b2');
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_ORDINARY_SHORT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_same,DATE '2033-01-03','15:00','18:00',3,1000,NULL,1,
      'codex-test ordinary too long','codex-test r1d-e-b2');
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_ORDINARY_LONG_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  SELECT lesson_id INTO STRICT v_actual_same
  FROM public.school_create_actual_lesson_from_planned(
    v_source_same,DATE '2033-01-03','15:00','17:00',2,1000,NULL,1,
    'codex-test ordinary same','codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_actual_cross
  FROM public.school_create_actual_lesson_from_planned(
    v_source_cross,DATE '2033-02-10','15:00','17:00',2,1000,NULL,1,
    'codex-test ordinary cross','codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_actual_cancel
  FROM public.school_create_cancelled_actual_lesson_from_planned(
    v_source_cancel,DATE '2033-02-17','15:00','17:00',2,1000,1,
    'codex-test cancelled','codex-test r1d-e-b2');
  SELECT id INTO STRICT v_actual_partial
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source_partial,DATE '2033-02-24','15:00','16:00',1,
    'codex-test partial','codex-test r1d-e-b2');

  BEGIN
    PERFORM * FROM public.school_create_partial_completed_actual_from_planned(
      v_source_direct_null,DATE '2033-02-14','15:00','17:00',2,
      'codex-test partial equal','codex-test r1d-e-b2');
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_PARTIAL_EQUAL_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  SELECT id INTO STRICT v_actual_makeup
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source_makeup,DATE '2033-02-28',NULL,NULL,'15:00','16:00',1,
    'codex-test canonical makeup','codex-test r1d-e-b2',1,NULL,NULL);
  BEGIN
    PERFORM * FROM public.school_create_lesson_credit_makeup_actual(
      v_source_makeup,DATE '2033-03-01',NULL,NULL,'15:00','18:00',3,
      'codex-test makeup excess','codex-test r1d-e-b2',1,NULL,NULL);
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_MAKEUP_EXCESS_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  SELECT lesson_id INTO STRICT v_actual_wrapper
  FROM public.school_create_makeup_completed_actual_lesson_from_planned(
    v_source_makeup,DATE '2033-03-01','15:00','16:00',1,NULL,NULL,true,1,
    'codex-test wrapper makeup','codex-test r1d-e-b2');
  SELECT lesson_id INTO STRICT v_actual_cross_wrapper
  FROM public.school_create_cross_month_makeup_completed_actual_from_planned(
    v_source_makeup,DATE '2033-04-01','15:00','16:00',1,NULL,NULL,false,1,
    'codex-test cross wrapper makeup','codex-test r1d-e-b2');

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
    WHERE a.id IN (v_actual_same,v_actual_cross,v_actual_cancel,v_actual_partial,
                   v_actual_makeup,v_actual_wrapper,v_actual_cross_wrapper)
      AND (a.student_settlement_month IS DISTINCT FROM p.student_settlement_month
        OR a.year_month IS DISTINCT FROM p.student_settlement_month
        OR a.teacher_settlement_month IS DISTINCT FROM to_char(a.lesson_date,'YYYY-MM'))
  ) OR NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id=v_actual_cross AND student_settlement_month='2033-01'
      AND year_month='2033-01' AND teacher_settlement_month='2033-02'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE id=v_actual_cancel AND status='cancelled'
      AND is_billable=false AND lesson_fee=0 AND actual_minutes=0
  ) THEN
    RAISE EXCEPTION 'R1D_E_B2_RPC_MONTH_OR_CANCELLED_MATRIX_FAILED';
  END IF;

  INSERT INTO public.school_lesson_records (
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,duration_hours,status,is_billable,app_type,
    planned_lesson_id,unit_price,lesson_fee,student_settlement_month,
    teacher_settlement_month,lesson_content,note
  ) VALUES (
    'e2000000-0000-4000-8000-00000000a001','actual',DATE '2033-05-01','2099-01',
    v_legacy_source.student_id,v_legacy_source.teacher_id,v_legacy_source.subject_id,
    v_legacy_source.business_entity_id,v_legacy_source.duration_hours,'completed',true,
    'school',v_legacy_source.id,coalesce(v_legacy_source.unit_price,0),
    coalesce(v_legacy_source.lesson_fee,0),'2099-01','2099-01',
    'codex-test legacy source direct','codex-test r1d-e-b2'),
    ('e2000000-0000-4000-8000-00000000a002','actual',DATE '2033-05-08','2099-01',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,2,'completed',true,'school',
    v_source_direct_forged,1000,2000,'2099-01','2099-01',
    'codex-test canonical forged direct','codex-test r1d-e-b2'),
    ('e2000000-0000-4000-8000-00000000a003','actual',DATE '2033-05-15','2099-01',
    v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,2,'completed',true,'school',
    v_source_direct_null,1000,2000,NULL,NULL,
    'codex-test canonical null direct','codex-test r1d-e-b2');

  IF NOT EXISTS (SELECT 1 FROM public.school_lesson_records a
                 WHERE a.id='e2000000-0000-4000-8000-00000000a001'
                   AND a.student_settlement_month=v_legacy_source.year_month
                   AND a.year_month=v_legacy_source.year_month
                   AND a.teacher_settlement_month='2033-05')
     OR EXISTS (SELECT 1 FROM public.school_lesson_records a
                JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
                WHERE a.id IN (
                  'e2000000-0000-4000-8000-00000000a002'::uuid,
                  'e2000000-0000-4000-8000-00000000a003'::uuid)
                  AND (a.student_settlement_month IS DISTINCT FROM p.student_settlement_month
                    OR a.year_month IS DISTINCT FROM p.student_settlement_month
                    OR a.teacher_settlement_month<>'2033-05')) THEN
    RAISE EXCEPTION 'R1D_E_B2_DIRECT_INSERT_AUTHORITY_FAILED';
  END IF;

  BEGIN
    INSERT INTO public.school_lesson_records (
      id,lesson_type,lesson_date,year_month,student_id,business_entity_id,
      duration_hours,status,is_billable,app_type,planned_lesson_id)
    VALUES ('e2000000-0000-4000-8000-00000000a010','actual',DATE '2033-06-01',
      '2033-06',v_fixture.student_id,v_fixture.business_entity_id,2,'completed',true,
      'school','e2000000-0000-4000-8000-00000000ffff');
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_INVALID_SOURCE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_pair_complete_chk;
    ALTER TABLE public.school_lesson_records
      DROP CONSTRAINT school_lesson_records_billing_source_metadata_chk;
    UPDATE public.school_lesson_records SET billing_month=NULL
    WHERE id=v_source_partial_bundle;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    BEGIN
      INSERT INTO public.school_lesson_records (
        id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
        business_entity_id,duration_hours,status,is_billable,app_type,planned_lesson_id)
      VALUES ('e2000000-0000-4000-8000-00000000a011','actual',DATE '2033-06-02',
        '2033-06',v_fixture.student_id,v_fixture.teacher_id,v_fixture.subject_id,
        v_fixture.business_entity_id,2,'completed',true,'school',v_source_partial_bundle);
      RAISE EXCEPTION 'R1D_E_B2_EXPECTED_PARTIAL_BUNDLE_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_B2_PARTIAL_BUNDLE_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_B2_PARTIAL_BUNDLE_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;

  BEGIN
    ALTER TABLE public.school_lesson_records
      DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    UPDATE public.school_lesson_records SET year_month='2099-01'
    WHERE id=v_legacy_source.id;
    ALTER TABLE public.school_lesson_records
      ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
    BEGIN
      PERFORM public.school_resolve_r1d_e_b2_actual_student_month(v_legacy_source.id);
      RAISE EXCEPTION 'R1D_E_B2_EXPECTED_LEGACY_DRIFT_REJECTION_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'R1D_E_B2_LEGACY_DRIFT_SUBTX_COMPLETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R1D_E_B2_LEGACY_DRIFT_SUBTX_COMPLETE' THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_actual FROM public.school_lesson_records
  WHERE id=v_actual_cross;
  PERFORM * FROM public.school_update_lesson_record_guarded(
    v_actual.id,v_actual.updated_at,DATE '2033-03-10',v_actual.student_id,
    v_actual.teacher_id,v_actual.subject_id,v_actual.business_entity_id,
    v_actual.start_time,v_actual.end_time,v_actual.duration_hours,
    v_actual.unit_price,v_actual.lesson_fee,v_actual.status,v_actual.is_billable,
    v_actual.lesson_count,v_actual.lesson_content,'codex-test canonical date edit');
  IF NOT EXISTS (SELECT 1 FROM public.school_lesson_records
                 WHERE id=v_actual_cross AND student_settlement_month='2033-01'
                   AND year_month='2033-01' AND teacher_settlement_month='2033-03') THEN
    RAISE EXCEPTION 'R1D_E_B2_CANONICAL_EDIT_MONTH_SEPARATION_FAILED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records SET student_settlement_month='2099-01'
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_MONTH_CHANGE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET student_settlement_month=NULL
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_MONTH_CLEAR_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET planned_lesson_id=v_source_same
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_SOURCE_CHANGE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET student_id=NULL WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_STUDENT_CHANGE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET business_entity_id=NULL
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_ENTITY_CHANGE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_lesson_records SET lesson_type='planned'
    WHERE id=v_legacy_actual.id;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_LEGACY_ACTUAL_TYPE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET lesson_type='planned'
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_ACTUAL_TYPE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET app_type='cash'
    WHERE id=v_legacy_actual.id;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_LEGACY_ACTUAL_APP_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET app_type='cash'
    WHERE id=v_actual_cross;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_CANONICAL_ACTUAL_APP_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' THEN RAISE; END IF;
  END;

  UPDATE public.school_lesson_records SET note=note
  WHERE id=v_source_partial_bundle;
  IF NOT EXISTS (SELECT 1 FROM public.school_lesson_records
                 WHERE id=v_source_partial_bundle
                   AND lesson_type='planned' AND app_type='school') THEN
    RAISE EXCEPTION 'R1D_E_B2_PLANNED_UPDATE_ISOLATION_FAILED';
  END IF;

  UPDATE public.school_lesson_records SET note=note,lesson_content=lesson_content
  WHERE id=v_legacy_actual.id;
  BEGIN
    UPDATE public.school_lesson_records SET year_month='2099-01'
    WHERE id=v_legacy_actual.id;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_LEGACY_ATTRIBUTION_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET note=note WHERE id=v_locked_actual.id;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_LOCKED_SETTLEMENT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET note=note WHERE id=v_wage_actual.id;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_WAGE_LOCK_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.school_legacy_actual_settlement_evidence
    SELECT * FROM public.school_legacy_actual_settlement_evidence LIMIT 1;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_EVIDENCE_INSERT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_legacy_actual_settlement_evidence
    SET recorded_at=recorded_at;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_EVIDENCE_UPDATE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM public.school_legacy_actual_settlement_evidence;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_EVIDENCE_DELETE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;
  BEGIN
    TRUNCATE public.school_legacy_actual_settlement_evidence;
    RAISE EXCEPTION 'R1D_E_B2_EXPECTED_EVIDENCE_TRUNCATE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R1D_E_B2_EXPECTED_%' THEN RAISE; END IF;
  END;

  SELECT array_agg(id ORDER BY id) INTO v_actual_ids
  FROM public.school_lesson_records
  WHERE id IN (v_actual_same,v_actual_cross,v_actual_cancel,v_actual_partial,
    v_actual_makeup,v_actual_wrapper,v_actual_cross_wrapper,
    'e2000000-0000-4000-8000-00000000a001'::uuid,
    'e2000000-0000-4000-8000-00000000a002'::uuid,
    'e2000000-0000-4000-8000-00000000a003'::uuid);

  IF cardinality(v_actual_ids)<>10
     OR EXISTS (SELECT 1 FROM public.school_lesson_records a
                WHERE a.id=ANY(v_actual_ids)
                  AND (a.student_settlement_month IS NULL
                    OR a.year_month IS DISTINCT FROM a.student_settlement_month
                    OR a.teacher_settlement_month IS DISTINCT FROM
                       to_char(a.lesson_date,'YYYY-MM')
                    OR num_nonnulls(a.student_duration_overage_minutes,
                       a.student_duration_overage_fee_jpy,
                       a.student_duration_overage_policy_version,
                       a.student_duration_overage_source,
                       a.student_duration_overage_decided_at)>0))
     OR (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)
          <>v_evidence_count
     OR (SELECT md5(string_agg(actual_lesson_id::text,','
           ORDER BY actual_lesson_id::text))
         FROM public.school_legacy_actual_settlement_evidence)
          <>v_evidence_uuid_md5
     OR has_table_privilege('anon',
          'public.school_legacy_actual_settlement_evidence','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated',
          'public.school_legacy_actual_settlement_evidence','SELECT,INSERT,UPDATE,DELETE')
     OR NOT has_table_privilege('service_role',
          'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_table_privilege('service_role',
          'public.school_legacy_actual_settlement_evidence','INSERT,UPDATE,DELETE,TRUNCATE')
     OR (SELECT md5(to_jsonb(l)::text) FROM public.school_lesson_records l
         WHERE l.id=v_legacy_source.id)<>v_legacy_source_md5 THEN
    RAISE EXCEPTION 'R1D_E_B2_FINAL_IN_TRANSACTION_BOUNDARY_FAILED';
  END IF;

  INSERT INTO r1d_e_b2_test_results VALUES
    ('canonical_rpc_matrix',true,'ordinary same/cross, cancelled, partial, canonical makeup'),
    ('compatibility_wrappers',true,'same-month and cross-month wrappers call canonical makeup'),
    ('duration_and_credit',true,'ordinary equal only, partial strict less, makeup remaining credit'),
    ('direct_table_invariant',true,'forged/null month canonicalized; invalid/partial source rejected'),
    ('canonical_edit',true,'student/source/entity/month immutable; date changes teacher month only'),
    ('actual_type_app_bypass',true,'legacy/canonical actual type and app immutable; planned update isolated'),
    ('legacy_actual',true,'unlocked content edit allowed; attribution/settlement/wage locks reject'),
    ('evidence_acl_immutable',true,'insert/update/delete/truncate rejected; role privileges fixed'),
    ('overage_and_planned_isolation',true,'overage fields null; F1 planned rows remain canonical');

  RAISE NOTICE 'R1D_E_B2_TEST_ACTUAL_IDS=%',v_actual_ids;
  RAISE NOTICE 'R1D_E_B2_LEGACY_PLANNED_FIXTURE_ID=%',v_legacy_source.id;
  RAISE NOTICE 'R1D_E_B2_LEGACY_PLANNED_PRETEST_FULL_MD5=%',v_legacy_source_md5;
  RAISE NOTICE 'R1D_E_B2_LEGACY_ACTUAL_FIXTURE_ID=%',v_legacy_actual.id;
  RAISE NOTICE 'R1D_E_B2_LEGACY_ACTUAL_PRETEST_FULL_MD5=%',v_legacy_actual_md5;
  RAISE NOTICE 'R1D_E_B2_LOCKED_ACTUAL_FIXTURE_ID=%',v_locked_actual.id;
  RAISE NOTICE 'R1D_E_B2_WAGE_LOCKED_ACTUAL_FIXTURE_ID=%',v_wage_actual.id;
END
$tests$;

SELECT test_name,passed,detail FROM r1d_e_b2_test_results ORDER BY test_name;

\if :{?r1d_e_b2_tests_existing_tx}
  \echo 'R1D_E_B2_TESTS_COMPLETE_CALLER_MUST_ROLLBACK'
\else
  ROLLBACK;

  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
  DO $postrollback$
  BEGIN
    IF EXISTS (SELECT 1 FROM public.school_lesson_records
               WHERE id IN (
                 'e2000000-0000-4000-8000-00000000a001'::uuid,
                 'e2000000-0000-4000-8000-00000000a002'::uuid,
                 'e2000000-0000-4000-8000-00000000a003'::uuid,
                 'e2000000-0000-4000-8000-00000000a010'::uuid,
                 'e2000000-0000-4000-8000-00000000a011'::uuid))
       OR EXISTS (SELECT 1 FROM public.school_lesson_records
                  WHERE note='codex-test r1d-e-b2') THEN
      RAISE EXCEPTION 'R1D_E_B2_ROLLBACK_TEST_RESIDUE_FOUND';
    END IF;
  END
  $postrollback$;
  SELECT true AS rollback_tests_pass,0 AS persisted_test_rows;
  ROLLBACK;
\endif
