\set ON_ERROR_STOP on
\pset pager off

-- S1-B normal page -> API -> RPC rollback-only matrix.
-- No direct-table attack testing is included. Every test write is rolled back.

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '300s';
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMPORARY TABLE s1_b_test_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_legacy_source public.school_lesson_records%ROWTYPE;
  v_actual public.school_lesson_records%ROWTYPE;
  v_planned_before public.school_lesson_records%ROWTYPE;
  v_other_entity_id uuid;
  v_source_equal uuid;
  v_source_overage uuid;
  v_source_short uuid;
  v_source_cancel uuid;
  v_source_partial uuid;
  v_source_other_entity uuid := 'f3100000-0000-4000-8000-00000000b009'::uuid;
  v_actual_equal uuid;
  v_actual_overage uuid;
  v_actual_cancel uuid;
  v_actual_partial uuid;
  v_actual_makeup uuid;
  v_planned_overage_md5 text;
  v_fixed_19_hash text;
  v_safe_note text := 'codex-test s1-b safe note edit';
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id = public.school_primary_business_entity_id()
    AND lesson.student_settlement_month IS NOT NULL
    AND num_nonnulls(
      lesson.billing_month,
      lesson.billing_week_start_date,
      lesson.student_settlement_month,
      lesson.billing_month_source,
      lesson.billing_month_decided_at
    ) = 5
    AND EXISTS (
      SELECT 1 FROM public.school_students s
      WHERE s.id = lesson.student_id
        AND s.app_type = 'school'
        AND coalesce(s.status, 'active') NOT IN ('inactive', 'graduated')
        AND (s.business_entity_id IS NULL OR s.business_entity_id = lesson.business_entity_id)
    )
    AND EXISTS (
      SELECT 1 FROM public.school_teachers t
      WHERE t.id = lesson.teacher_id
        AND t.app_type = 'school'
        AND coalesce(t.status, 'employed') NOT IN ('inactive', 'retired')
    )
    AND EXISTS (
      SELECT 1 FROM public.school_subjects s
      WHERE s.id = lesson.subject_id AND coalesce(s.is_active, true)
    )
  ORDER BY lesson.id
  LIMIT 1;

  SELECT b.id INTO STRICT v_other_entity_id
  FROM public.school_business_entities b
  WHERE b.id <> public.school_primary_business_entity_id()
    AND coalesce(b.is_active, true)
  ORDER BY b.id
  LIMIT 1;

  SELECT lesson.* INTO STRICT v_legacy_source
  FROM public.school_legacy_planned_settlement_evidence evidence
  JOIN public.school_lesson_records lesson ON lesson.id = evidence.planned_lesson_id
  WHERE evidence.approved_manifest = true
    AND evidence.evidence_source = 'r1d_e_b1_fixed_legacy_279'
    AND evidence.evidence_version = 'legacy_settlement_evidence_v1'
    AND lesson.lesson_type = 'planned'
    AND lesson.app_type = 'school'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.duration_hours > 0
    AND lesson.unit_price > 0
    AND num_nonnulls(
      lesson.billing_month,
      lesson.billing_week_start_date,
      lesson.student_settlement_month,
      lesson.billing_month_source,
      lesson.billing_month_decided_at
    ) = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.school_lesson_records a
      WHERE a.lesson_type = 'actual' AND a.planned_lesson_id = lesson.id
    )
  ORDER BY lesson.id
  LIMIT 1;

  SELECT md5(string_agg(l.id::text || ':' || l.duration_hours::text || ':' ||
    l.lesson_fee::text || ':' || l.updated_at::text, ',' ORDER BY l.id::text))
  INTO v_fixed_19_hash
  FROM public.school_lesson_records l
  WHERE l.id IN (
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
  );
  IF v_fixed_19_hash <> '352e72ac33d648a23be84bb27b3580d1' THEN
    RAISE EXCEPTION 'S1_B_TEST_FIXED_19_BASELINE_DRIFT';
  END IF;

  SELECT lesson_id INTO STRICT v_source_equal
  FROM public.school_create_planned_lesson_record(
    DATE '2034-01-02', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 1100, NULL, 'planned', 1,
    'codex-test S1-B equal source', 'codex-test s1-b'
  );
  SELECT lesson_id INTO STRICT v_source_overage
  FROM public.school_create_planned_lesson_record(
    DATE '2034-01-09', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 1100, NULL, 'planned', 1,
    'codex-test S1-B overage source', 'codex-test s1-b'
  );
  SELECT lesson_id INTO STRICT v_source_short
  FROM public.school_create_planned_lesson_record(
    DATE '2034-01-16', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 1100, NULL, 'planned', 1,
    'codex-test S1-B short source', 'codex-test s1-b'
  );
  SELECT lesson_id INTO STRICT v_source_cancel
  FROM public.school_create_planned_lesson_record(
    DATE '2034-01-23', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    '15:00', '17:00', 0, 1100, NULL, 'planned', 1,
    'codex-test S1-B cancelled source', 'codex-test s1-b'
  );
  SELECT id INTO STRICT v_source_partial
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2034-01-30', v_fixture.student_id, v_fixture.teacher_id,
    v_fixture.subject_id, v_fixture.business_entity_id,
    NULL, NULL, 2, 1100, NULL, 'planned', 1,
    'codex-test S1-B partial source', 'codex-test s1-b',
    'online', NULL
  );

  INSERT INTO public.school_lesson_records (
    id, lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, unit_price, lesson_fee, lesson_count
  ) VALUES (
    v_source_other_entity, 'planned', DATE '2034-02-06', '2034-02',
    v_fixture.student_id, v_fixture.teacher_id, v_fixture.subject_id,
    v_other_entity_id, '15:00', '17:00', 2,
    'codex-test S1-B other entity source', 'planned', true,
    'codex-test s1-b', 'school', 1100, 2200, 1
  );

  SELECT p.* INTO STRICT v_planned_before
  FROM public.school_lesson_records p
  WHERE p.id = v_source_overage;
  v_planned_overage_md5 := md5(to_jsonb(v_planned_before)::text);

  SELECT lesson_id INTO STRICT v_actual_equal
  FROM public.school_create_actual_lesson_from_planned(
    v_source_equal, DATE '2034-01-02', '15:00', '17:00', 2, 1100, NULL, 1,
    'codex-test S1-B equal actual', 'codex-test s1-b'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    JOIN public.school_lesson_records p ON p.id = a.planned_lesson_id
    WHERE a.id = v_actual_equal
      AND a.status = 'completed'
      AND a.duration_hours = p.duration_hours
      AND a.student_settlement_month = p.student_settlement_month
      AND num_nonnulls(
        a.student_duration_overage_minutes,
        a.student_duration_overage_fee_jpy,
        a.student_duration_overage_policy_version,
        a.student_duration_overage_source,
        a.student_duration_overage_decided_at
      ) = 0
  ) THEN
    RAISE EXCEPTION 'S1_B_EQUAL_BRANCH_FAILED';
  END IF;

  SELECT lesson_id INTO STRICT v_actual_overage
  FROM public.school_create_actual_lesson_from_planned(
    v_source_overage, DATE '2034-03-09', '15:00', '17:30', 2.5, 9999, NULL, 1,
    'codex-test S1-B overage actual', 'codex-test s1-b'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    JOIN public.school_lesson_records p ON p.id = a.planned_lesson_id
    WHERE a.id = v_actual_overage
      AND a.status = 'completed'
      AND a.is_billable IS TRUE
      AND a.business_entity_id = public.school_primary_business_entity_id()
      AND a.student_settlement_month = p.student_settlement_month
      AND a.year_month = p.student_settlement_month
      AND a.teacher_settlement_month = '2034-03'
      AND p.student_settlement_month = '2034-01'
      AND to_char(
        (to_date(a.student_settlement_month || '-01', 'YYYY-MM-DD')
          + interval '1 month')::date,
        'YYYY-MM'
      ) = '2034-02'
      AND a.student_duration_overage_minutes = 30
      AND a.student_duration_overage_fee_jpy = 550
      AND a.student_duration_overage_policy_version = 'student_duration_overage_v1'
      AND a.student_duration_overage_source = 'ordinary_actual_rpc'
      AND a.student_duration_overage_decided_at IS NOT NULL
      AND a.unit_price = 9999
      AND a.base_lesson_fee_jpy IS NULL
      AND a.aircon_fee_jpy IS NULL
      AND a.fee_calculation_version IS NULL
  ) THEN
    RAISE EXCEPTION 'S1_B_OVERAGE_FACT_OR_MONTH_FAILED';
  END IF;

  IF (SELECT md5(to_jsonb(p)::text) FROM public.school_lesson_records p
      WHERE p.id = v_source_overage) <> v_planned_overage_md5 THEN
    RAISE EXCEPTION 'S1_B_SOURCE_PLANNED_WAS_MODIFIED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_short, DATE '2034-01-16', '15:00', '16:00', 1, 1100, NULL, 1,
      'codex-test S1-B short actual', 'codex-test s1-b'
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_SHORT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '实际完成时长小于预定时长；部分完成请使用%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_legacy_source.id, v_legacy_source.lesson_date,
      coalesce(v_legacy_source.start_time, '15:00'),
      coalesce(v_legacy_source.end_time, '18:00'),
      v_legacy_source.duration_hours + 1,
      v_legacy_source.unit_price, NULL, v_legacy_source.lesson_count,
      'codex-test S1-B legacy overage', 'codex-test s1-b'
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_LEGACY_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_other_entity, DATE '2034-02-06', '15:00', '17:30', 2.5,
      1100, NULL, 1, 'codex-test S1-B other entity overage', 'codex-test s1-b'
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_OTHER_ENTITY_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_PRIMARY_BUSINESS_ENTITY_REQUIRED' THEN RAISE; END IF;
  END;

  SELECT lesson_id INTO STRICT v_actual_cancel
  FROM public.school_create_cancelled_actual_lesson_from_planned(
    v_source_cancel, DATE '2034-02-23', '15:00', '17:00', 2, 1100, 1,
    'codex-test S1-B cancelled actual', 'codex-test s1-b'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id = v_actual_cancel
      AND a.status = 'cancelled'
      AND a.is_billable = false
      AND a.lesson_fee = 0
      AND num_nonnulls(
        a.student_duration_overage_minutes,
        a.student_duration_overage_fee_jpy,
        a.student_duration_overage_policy_version,
        a.student_duration_overage_source,
        a.student_duration_overage_decided_at
      ) = 0
  ) THEN
    RAISE EXCEPTION 'S1_B_CANCELLED_NULL_BUNDLE_FAILED';
  END IF;

  SELECT id INTO STRICT v_actual_partial
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source_partial, DATE '2034-02-28', '15:00', '16:00', 1,
    'codex-test S1-B partial actual', 'codex-test s1-b'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id = v_actual_partial
      AND num_nonnulls(
        a.student_duration_overage_minutes,
        a.student_duration_overage_fee_jpy,
        a.student_duration_overage_policy_version,
        a.student_duration_overage_source,
        a.student_duration_overage_decided_at
      ) = 0
  ) OR public.school_get_lesson_credit_remaining_hours(v_source_partial) <> 1 THEN
    RAISE EXCEPTION 'S1_B_PARTIAL_NULL_BUNDLE_OR_CREDIT_FAILED';
  END IF;

  SELECT id INTO STRICT v_actual_makeup
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source_partial, DATE '2034-03-01', NULL, NULL,
    '15:00', '16:00', 1,
    'codex-test S1-B makeup actual', 'codex-test s1-b', 1, NULL, NULL
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id = v_actual_makeup
      AND a.status = 'makeup_completed'
      AND a.is_billable = false
      AND a.lesson_fee = 0
      AND num_nonnulls(
        a.student_duration_overage_minutes,
        a.student_duration_overage_fee_jpy,
        a.student_duration_overage_policy_version,
        a.student_duration_overage_source,
        a.student_duration_overage_decided_at
      ) = 0
  ) OR public.school_get_lesson_credit_remaining_hours(v_source_partial) <> 0 THEN
    RAISE EXCEPTION 'S1_B_MAKEUP_NULL_BUNDLE_OR_CREDIT_FAILED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_source_equal, DATE '2034-01-02', '15:00', '17:00', 2, 1100, NULL, 1,
      'codex-test S1-B duplicate actual', 'codex-test s1-b'
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_DUPLICATE_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> '该预定课时已有关联 actual，不能重复生成。' THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_actual
  FROM public.school_lesson_records a
  WHERE a.id = v_actual_overage;
  PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
    v_actual.id, v_actual.updated_at, v_actual.lesson_date,
    v_actual.student_id, v_actual.teacher_id, v_actual.subject_id,
    v_actual.business_entity_id, v_actual.start_time, v_actual.end_time,
    v_actual.duration_hours, v_actual.unit_price, v_actual.lesson_fee,
    v_actual.status, v_actual.is_billable, v_actual.lesson_count,
    v_actual.lesson_content, v_safe_note,
    v_actual.lesson_delivery_mode, v_actual.lesson_venue
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id = v_actual_overage
      AND a.note = v_safe_note
      AND a.student_duration_overage_minutes = 30
      AND a.student_duration_overage_fee_jpy = 550
  ) THEN
    RAISE EXCEPTION 'S1_B_SAFE_EDIT_DID_NOT_PRESERVE_OVERAGE';
  END IF;

  SELECT * INTO STRICT v_actual
  FROM public.school_lesson_records a
  WHERE a.id = v_actual_overage;
  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_actual.id, v_actual.updated_at, v_actual.lesson_date,
      v_actual.student_id, v_actual.teacher_id, v_actual.subject_id,
      v_actual.business_entity_id, v_actual.start_time, v_actual.end_time,
      v_actual.duration_hours + 0.5, v_actual.unit_price, NULL,
      v_actual.status, v_actual.is_billable, v_actual.lesson_count,
      v_actual.lesson_content, v_actual.note,
      v_actual.lesson_delivery_mode, v_actual.lesson_venue
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_DURATION_EDIT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE' THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_actual
  FROM public.school_lesson_records a
  WHERE a.id = v_actual_overage;
  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_actual.id, v_actual.updated_at, v_actual.lesson_date,
      v_actual.student_id, v_actual.teacher_id, v_actual.subject_id,
      v_actual.business_entity_id, v_actual.start_time, v_actual.end_time,
      v_actual.duration_hours, v_actual.unit_price + 1, NULL,
      v_actual.status, v_actual.is_billable, v_actual.lesson_count,
      v_actual.lesson_content, v_actual.note,
      v_actual.lesson_delivery_mode, v_actual.lesson_venue
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_UNIT_PRICE_EDIT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE' THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_actual
  FROM public.school_lesson_records a
  WHERE a.id = v_actual_overage;
  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded(
      v_actual.id, v_actual.updated_at, v_actual.lesson_date,
      v_actual.student_id, v_actual.teacher_id, v_actual.subject_id,
      v_actual.business_entity_id, v_actual.start_time, v_actual.end_time,
      v_actual.duration_hours, v_actual.unit_price, v_actual.lesson_fee,
      'cancelled', v_actual.is_billable, v_actual.lesson_count,
      v_actual.lesson_content, v_actual.note
    );
    RAISE EXCEPTION 'S1_B_EXPECTED_STATUS_EDIT_REJECTION_MISSING';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'actual 课时 V1 不允许修改状态。' THEN RAISE; END IF;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.id = v_actual_overage
      AND a.duration_hours = 2.5
      AND a.unit_price = 9999
      AND a.status = 'completed'
      AND a.student_duration_overage_minutes = 30
      AND a.student_duration_overage_fee_jpy = 550
  ) THEN
    RAISE EXCEPTION 'S1_B_GUARDED_REJECTIONS_NOT_ATOMIC';
  END IF;

  IF (SELECT md5(string_agg(l.id::text || ':' || l.duration_hours::text || ':' ||
    l.lesson_fee::text || ':' || l.updated_at::text, ',' ORDER BY l.id::text))
    FROM public.school_lesson_records l
    WHERE l.id IN (
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
    )) <> v_fixed_19_hash
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records l
       WHERE l.id IN (
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
       )
         AND num_nonnulls(
           student_duration_overage_minutes,
           student_duration_overage_fee_jpy,
           student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at
         ) > 0
     ) THEN
    RAISE EXCEPTION 'S1_B_FIXED_19_CHANGED_IN_TEST';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) <> '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure
     )) <> '155e831118acbeadfd04b6640324c7cd'
     OR md5(pg_get_functiondef(
       'public.school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)'::regprocedure
     )) <> '2dfabf4a920f7138043079855347207b' THEN
    RAISE EXCEPTION 'S1_B_PROTECTED_MD5_CHANGED_IN_TEST';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_R0_CHANGED_IN_TEST';
  END IF;

  INSERT INTO s1_b_test_results VALUES
    ('equal_branch', true, 'canonical equal actual succeeds with all-NULL overage bundle'),
    ('overage_fact', true, 'canonical Aozora overage is atomic: 30 minutes and JPY 550 from planned unit price'),
    ('authoritative_months', true, 'source month 2034-01, derived target 2034-02, actual date month 2034-03'),
    ('short_rejection', true, 'actual shorter than planned remains on partial-only path'),
    ('eligibility_rejections', true, 'legacy and non-Aozora overage fail closed'),
    ('partial_makeup_cancelled', true, 'all remain outside overage and makeup credit remains correct'),
    ('duplicate_and_planned', true, 'duplicate ordinary rejected and source planned unchanged'),
    ('guarded_edit', true, 'safe note edit preserved fact; duration/unit/status edits rejected atomically'),
    ('history_and_boundaries', true, 'fixed 19, protected MD5, aircon separation, and R0 unchanged');

  RAISE NOTICE 'S1_B_TEST_ACTUAL_IDS=%,%,%,%,%',
    v_actual_equal, v_actual_overage, v_actual_cancel, v_actual_partial, v_actual_makeup;
END
$tests$;

SELECT test_name, passed, detail
FROM s1_b_test_results
ORDER BY test_name;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $postrollback$
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records) <> 649
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') <> 414
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual') <> 235
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records
       WHERE note = 'codex-test s1-b'
          OR lesson_content LIKE 'codex-test S1-B%'
          OR id = 'f3100000-0000-4000-8000-00000000b009'::uuid
     )
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(
           student_duration_overage_minutes,
           student_duration_overage_fee_jpy,
           student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at
         ) > 0) <> 0
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(l) - ARRAY[
        'student_duration_overage_minutes',
        'student_duration_overage_fee_jpy',
        'student_duration_overage_policy_version',
        'student_duration_overage_source',
        'student_duration_overage_decided_at'
      ])::text), '' ORDER BY l.id::text), ''))
      FROM public.school_lesson_records l
      WHERE l.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> 'fd8b5570f42d618f136b2f6408704ae8'
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(s) - ARRAY[
        'duration_overage_minutes',
        'duration_overage_fee_jpy',
        'duration_overage_fee_cny',
        'duration_overage_actual_count',
        'duration_overage_policy_version',
        'duration_overage_source'
      ])::text), '' ORDER BY s.id::text), ''))
      FROM public.school_student_monthly_settlements s
      WHERE s.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> '7925cf3018bd0e669cd29710f6593238'
     OR (SELECT count(*) FROM public.school_feature_gates
         WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
            OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
            OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_ROLLBACK_RESIDUE_OR_BOUNDARY_CHANGE_FOUND';
  END IF;
END
$postrollback$;

SELECT true AS s1_b_rollback_tests_pass, 0 AS persisted_test_rows;
ROLLBACK;
