-- School V2 R2-F-D-DB1 postdeploy verification.
-- Read-only; always rolls back.

\set ON_ERROR_STOP on
\pset pager off

\echo 'R2_F_D_DB1_POSTDEPLOY_BEGIN'
BEGIN TRANSACTION READ ONLY ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='180s';

DO $postdeploy$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_resolved_count integer;
  v_canonical_count integer;
  v_error text;
  v_preview record;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid=
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure;
  IF md5(pg_get_functiondef(v_proc.oid))=
       '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR pg_get_functiondef(v_proc.oid) NOT LIKE
          '%to_jsonb(v_lesson)%lesson_total_fee_jpy%'
     OR pg_get_functiondef(v_proc.oid) NOT LIKE
          '%v_lesson.lesson_total_fee_jpy IS NOT NULL%'
     OR v_proc.provolatile<>'s' OR NOT v_proc.prosecdef
     OR v_proc.proowner::regrole::text<>'postgres'
     OR v_proc.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, public']::text[]
     OR v_proc.proacl::text<>'{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_RESOLVER_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR EXISTS (
       SELECT 1
       FROM public.school_legacy_actual_settlement_evidence evidence
       JOIN public.school_lesson_records actual
         ON actual.id=evidence.actual_lesson_id
       WHERE actual.lesson_total_fee_jpy IS NOT NULL
          OR evidence.source_planned_lesson_id IS DISTINCT FROM
               actual.planned_lesson_id
          OR evidence.student_id_snapshot IS DISTINCT FROM actual.student_id
          OR evidence.business_entity_id_snapshot IS DISTINCT FROM
               actual.business_entity_id
          OR evidence.teacher_id_snapshot IS DISTINCT FROM actual.teacher_id
          OR evidence.subject_id_snapshot IS DISTINCT FROM actual.subject_id
          OR evidence.legacy_year_month IS DISTINCT FROM actual.year_month
          OR evidence.teacher_settlement_month_snapshot IS DISTINCT FROM
               coalesce(actual.teacher_settlement_month,
                 to_char(actual.lesson_date,'YYYY-MM'))
          OR evidence.lesson_date_snapshot IS DISTINCT FROM actual.lesson_date
          OR evidence.actual_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
               actual.id::text,actual.planned_lesson_id::text,
               actual.student_id::text,actual.business_entity_id::text,
               coalesce(actual.teacher_id::text,'<NULL>'),
               coalesce(actual.subject_id::text,'<NULL>'),actual.year_month,
               coalesce(actual.teacher_settlement_month,
                 to_char(actual.lesson_date,'YYYY-MM')),
               actual.lesson_date::text,actual.lesson_type,actual.app_type))
          OR evidence.actual_full_row_md5 IS DISTINCT FROM
               md5((to_jsonb(actual)-'lesson_total_fee_jpy')::text)
     ) THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_EVIDENCE_FAILED';
  END IF;

  SELECT count(*) INTO v_resolved_count
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE public.school_resolve_r1d_e_c_lesson_student_month(
          evidence.actual_lesson_id)=evidence.legacy_year_month;
  IF v_resolved_count<>234 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_LEGACY_RESOLUTION_FAILED';
  END IF;

  SELECT count(*) INTO v_canonical_count
  FROM public.school_lesson_records actual
  WHERE actual.app_type='school' AND actual.lesson_type='actual'
    AND NOT EXISTS (
      SELECT 1 FROM public.school_legacy_actual_settlement_evidence evidence
      WHERE evidence.actual_lesson_id=actual.id)
    AND public.school_resolve_r1d_e_c_lesson_student_month(actual.id)=
          actual.student_settlement_month;
  IF v_canonical_count<>6 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_CANONICAL_ACTUAL_FAILED';
  END IF;

  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07');
  RAISE NOTICE 'R2_F_D_DB1_SUN_JULY_PREVIEW=%',to_jsonb(v_preview);
  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07');
  RAISE NOTICE 'R2_F_D_DB1_ZHANG_JULY_PREVIEW=%',to_jsonb(v_preview);

  BEGIN
    PERFORM * FROM public.school_get_student_tuition_validation_preview_details(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_SUN_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.school_get_student_tuition_validation_preview_details(
      '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_ZHANG_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id IN (
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '7aef8061-7037-4881-a847-a2cdb031c0f4')
      AND settlement.business_entity_id=
        '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      AND settlement.year_month='2026-07'
      AND settlement.settlement_status='locked'
  ) THEN
    RAISE EXCEPTION 'R2_F_D_DB1_UNEXPECTED_JULY_LOCKED_SETTLEMENT';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills)<>9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
          ORDER BY row_value.id::text),''))
         FROM public.school_student_tuition_bills row_value)<>
          '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
          ORDER BY row_value.id::text),''))
         FROM public.school_income_records row_value)<>
          '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)<>121
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
          ORDER BY row_value.id::text),''))
         FROM public.school_student_tuition_bill_lessons row_value)<>
          '285172fedeb923c67ea9a179480d8692'
     OR (SELECT count(*) FROM public.school_student_tuition_billing_identities)<>7
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
          ORDER BY row_value.id::text),''))
         FROM public.school_student_tuition_billing_identities row_value)<>
          '4d91a5a1074f90389822fc367a7e5467'
     OR (SELECT count(*) FROM public.school_student_monthly_settlements)<>15
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
          ORDER BY row_value.id::text),''))
         FROM public.school_student_monthly_settlements row_value)<>
          '8d40d937d45c64eca0ec0ba7b1c5e65d' THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_HISTORY_FINGERPRINT_CHANGED';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_POSTDEPLOY_R0_CHANGED';
  END IF;
END
$postdeploy$;

\echo 'R2_F_D_DB1_POSTDEPLOY_ROLLBACK'
ROLLBACK;
