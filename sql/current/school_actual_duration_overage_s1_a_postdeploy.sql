\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $postdeploy$
DECLARE
  v_function record;
  v_expected_md5 text;
  v_fixed_count bigint;
BEGIN
  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_lesson_records'
        AND ((column_name = 'student_duration_overage_minutes' AND data_type = 'integer')
          OR (column_name = 'student_duration_overage_fee_jpy' AND data_type = 'numeric')
          OR (column_name = 'student_duration_overage_policy_version' AND data_type = 'text')
          OR (column_name = 'student_duration_overage_source' AND data_type = 'text')
          OR (column_name = 'student_duration_overage_decided_at' AND data_type = 'timestamp with time zone'))
        AND is_nullable = 'YES' AND column_default IS NULL) <> 5 THEN
    RAISE EXCEPTION 'S1-A postdeploy: lesson column contract mismatch';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_student_monthly_settlements'
        AND ((column_name = 'duration_overage_minutes' AND data_type = 'integer')
          OR (column_name = 'duration_overage_fee_jpy' AND data_type = 'numeric')
          OR (column_name = 'duration_overage_fee_cny' AND data_type = 'numeric')
          OR (column_name = 'duration_overage_actual_count' AND data_type = 'integer')
          OR (column_name = 'duration_overage_policy_version' AND data_type = 'text')
          OR (column_name = 'duration_overage_source' AND data_type = 'text'))
        AND is_nullable = 'YES' AND column_default IS NULL) <> 6 THEN
    RAISE EXCEPTION 'S1-A postdeploy: settlement column contract mismatch';
  END IF;

  IF (SELECT count(*)
      FROM pg_constraint c
      WHERE c.conrelid IN (
        'public.school_lesson_records'::regclass,
        'public.school_student_monthly_settlements'::regclass
      )
        AND c.conname IN (
          'school_lesson_records_duration_overage_bundle_chk',
          'school_lesson_records_duration_overage_context_chk',
          'school_lesson_records_duration_overage_amount_chk',
          'school_student_settlements_duration_overage_bundle_chk',
          'school_student_settlements_duration_overage_policy_chk',
          'school_student_settlements_duration_overage_amount_chk'
        )
        AND c.contype = 'c'
        AND c.convalidated) <> 6 THEN
    RAISE EXCEPTION 'S1-A postdeploy: validated CHECK constraint contract mismatch';
  END IF;

  IF (SELECT count(*)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'school_lesson_records_duration_overage_month_idx'
        AND NOT i.indisunique
        AND position('(student_id, business_entity_id, student_settlement_month)' in pg_get_indexdef(i.indexrelid)) > 0
        AND position('student_duration_overage_policy_version' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_source' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_fee_jpy' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_v1' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('ordinary_actual_rpc' in pg_get_expr(i.indpred, i.indrelid)) > 0) <> 1
     OR (SELECT count(*)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'school_lesson_records_duration_overage_planned_uidx'
        AND i.indisunique
        AND position('(planned_lesson_id)' in pg_get_indexdef(i.indexrelid)) > 0
        AND position('student_duration_overage_policy_version' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_source' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('student_duration_overage_v1' in pg_get_expr(i.indpred, i.indrelid)) > 0
        AND position('ordinary_actual_rpc' in pg_get_expr(i.indpred, i.indrelid)) > 0) <> 1 THEN
    RAISE EXCEPTION 'S1-A postdeploy: partial index contract mismatch';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(
        student_duration_overage_minutes,
        student_duration_overage_fee_jpy,
        student_duration_overage_policy_version,
        student_duration_overage_source,
        student_duration_overage_decided_at
      ) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
      WHERE num_nonnulls(
        duration_overage_minutes,
        duration_overage_fee_jpy,
        duration_overage_fee_cny,
        duration_overage_actual_count,
        duration_overage_policy_version,
        duration_overage_source
      ) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A postdeploy: historical snapshot fields are not all NULL';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE student_duration_overage_policy_version = 'student_duration_overage_v1'
        AND student_duration_overage_source = 'ordinary_actual_rpc') <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE student_duration_overage_policy_version = 'student_duration_overage_v1'
        AND student_duration_overage_source = 'ordinary_actual_rpc'
        AND student_duration_overage_fee_jpy > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A postdeploy: partial index has an eligible business row';
  END IF;

  WITH fixed(id) AS (
    VALUES
      ('14f0ad66-6a72-4562-bdf6-f867f5e7901d'::uuid),
      ('1cb708d2-404b-4fed-a9cb-fb9b974da41c'::uuid),
      ('4645f239-d6f7-473f-96e0-75647cf2b937'::uuid),
      ('4c0214ac-6ce5-4afd-b518-e3d6bd9ab978'::uuid),
      ('555faff7-6658-4860-8277-22f2bc4a9c65'::uuid),
      ('5e0786c6-8b10-4e10-9e84-addaedd5509e'::uuid),
      ('6a3641db-4740-4d95-b1c9-8e3ae77516c2'::uuid),
      ('6e16fea8-c408-421a-adc2-05107f987f5b'::uuid),
      ('714c671d-b98a-464f-afe2-629ed4ba148b'::uuid),
      ('78301f55-e157-4219-8c29-8a87f5a8fa0b'::uuid),
      ('7f468446-13e2-489d-aec5-2b64aeca4f9a'::uuid),
      ('a13b216e-4524-4315-b5aa-c1d2cc053082'::uuid),
      ('a7275d9c-15f1-4829-a78e-fc48b9e88e14'::uuid),
      ('a97f7d25-061d-4504-a47e-53490ba81061'::uuid),
      ('acbc65c8-ba47-4595-b2db-244ae74f83d0'::uuid),
      ('ae53ba74-3cb6-4090-ac7d-d19332dcad9d'::uuid),
      ('b74f743a-0acc-4156-9f00-2d6dfe388ce2'::uuid),
      ('bb4a9aa8-f3dc-4681-a934-e049ff3dce33'::uuid),
      ('eefe54b0-5a01-4836-b1d1-ffcca570447d'::uuid)
  )
  SELECT count(*) INTO v_fixed_count
  FROM fixed f
  JOIN public.school_lesson_records l ON l.id = f.id
  WHERE num_nonnulls(
    l.student_duration_overage_minutes,
    l.student_duration_overage_fee_jpy,
    l.student_duration_overage_policy_version,
    l.student_duration_overage_source,
    l.student_duration_overage_decided_at
  ) = 0;
  IF v_fixed_count <> 19 THEN
    RAISE EXCEPTION 'S1-A postdeploy: fixed legacy 19 NULL isolation mismatch';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5((to_jsonb(l) - ARRAY[
        'student_duration_overage_minutes',
        'student_duration_overage_fee_jpy',
        'student_duration_overage_policy_version',
        'student_duration_overage_source',
        'student_duration_overage_decided_at'
      ])::text), '' ORDER BY l.id::text), ''))
      FROM public.school_lesson_records l
      WHERE l.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> 'fd8b5570f42d618f136b2f6408704ae8' THEN
    RAISE EXCEPTION 'S1-A postdeploy: stable lesson history hash mismatch';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5((to_jsonb(s) - ARRAY[
        'duration_overage_minutes',
        'duration_overage_fee_jpy',
        'duration_overage_fee_cny',
        'duration_overage_actual_count',
        'duration_overage_policy_version',
        'duration_overage_source'
      ])::text), '' ORDER BY s.id::text), ''))
      FROM public.school_student_monthly_settlements s
      WHERE s.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
      <> '7925cf3018bd0e669cd29710f6593238' THEN
    RAISE EXCEPTION 'S1-A postdeploy: stable settlement history hash mismatch';
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
      )) <> '352e72ac33d648a23be84bb27b3580d1' THEN
    RAISE EXCEPTION 'S1-A postdeploy: fixed legacy 19 projection hash mismatch';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(base_lesson_fee_jpy, aircon_fee_jpy, fee_calculation_version) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A postdeploy: aircon/planned fee component population changed';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 630
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') <> 397
     OR (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual') <> 233
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15 THEN
    RAISE EXCEPTION 'S1-A postdeploy: lesson/settlement row-count boundary changed';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bills x) <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_income_records x) <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bill_lessons x) <> '285172fedeb923c67ea9a179480d8692' THEN
    RAISE EXCEPTION 'S1-A postdeploy: bill/income/relation boundary changed';
  END IF;

  FOR v_function IN
    SELECT p.oid::regprocedure::text AS signature, md5(pg_get_functiondef(p.oid)) AS actual_md5
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'school_create_actual_lesson_from_planned',
        'school_create_partial_completed_actual_from_planned',
        'school_create_lesson_credit_makeup_actual',
        'school_get_student_monthly_settlement_summary',
        'school_get_student_monthly_settlement_preview',
        'school_lock_student_monthly_settlement',
        'school_relock_student_monthly_settlement',
        'school_list_student_tuition_candidates',
        'school_resolve_planned_billing_attribution',
        'school_resolve_planned_duration',
        'school_calculate_planned_fee_components'
      )
  LOOP
    v_expected_md5 := CASE v_function.signature
      WHEN 'school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)' THEN 'da156f6c951b233a2878ecb100b2748b'
      WHEN 'school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)' THEN 'ec7bdebb8b2eacf0527c603a32650af9'
      WHEN 'school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)' THEN 'eaad3fc14366af9c11cc70ba34275091'
      WHEN 'school_get_student_monthly_settlement_summary(uuid,text)' THEN '87aab230b7d9cb35124eeca7899317f5'
      WHEN 'school_get_student_monthly_settlement_preview(uuid,text)' THEN '7bc39abec927bc4e3c72167b29c06e8e'
      WHEN 'school_lock_student_monthly_settlement(uuid,text,text)' THEN '6a172d58ed07d983db80972e31bd34a1'
      WHEN 'school_relock_student_monthly_settlement(uuid,text)' THEN '6db55eec5e3f6601b1d7aae0835d3b58'
      WHEN 'school_list_student_tuition_candidates(uuid,uuid,text,boolean)' THEN '8981a2ce07abf8c28231bfaf05451368'
      WHEN 'school_resolve_planned_billing_attribution(date,date)' THEN '529c7387e63dcdb2e6972398c2d74dae'
      WHEN 'school_resolve_planned_duration(text,text,numeric)' THEN '4f5b754585c9e3752639e6b0f2fa7a34'
      WHEN 'school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)' THEN '2dfabf4a920f7138043079855347207b'
      ELSE NULL
    END;
    IF v_function.actual_md5 IS DISTINCT FROM v_expected_md5 THEN
      RAISE EXCEPTION 'S1-A postdeploy: protected function changed: %', v_function.signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (
        'school_create_actual_lesson_from_planned',
        'school_create_partial_completed_actual_from_planned',
        'school_create_lesson_credit_makeup_actual',
        'school_get_student_monthly_settlement_summary',
        'school_get_student_monthly_settlement_preview',
        'school_lock_student_monthly_settlement',
        'school_relock_student_monthly_settlement',
        'school_list_student_tuition_candidates',
        'school_resolve_planned_billing_attribution',
        'school_resolve_planned_duration',
        'school_calculate_planned_fee_components')) <> 11 THEN
    RAISE EXCEPTION 'S1-A postdeploy: protected function count mismatch';
  END IF;

  IF (SELECT count(*) FROM information_schema.triggers
      WHERE event_object_schema = 'public'
        AND event_object_table IN ('school_lesson_records','school_student_monthly_settlements')) <> 4
     OR (SELECT md5(coalesce(string_agg(
        event_object_table || '|' || trigger_name || '|' || action_timing || '|' || event_manipulation,
        '' ORDER BY event_object_table, trigger_name, event_manipulation), ''))
      FROM information_schema.triggers
      WHERE event_object_schema = 'public'
        AND event_object_table IN ('school_lesson_records','school_student_monthly_settlements'))
        <> 'cb1a97defaa110e198d529c4fda56577' THEN
    RAISE EXCEPTION 'S1-A postdeploy: unexpected trigger change';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND column_name LIKE '%duration_overage%') <> 11
     OR (SELECT count(*)
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname LIKE '%duration_overage%') <> 2
     OR (SELECT count(*)
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname LIKE '%duration_overage%') <> 0
     OR (SELECT count(*)
         FROM information_schema.triggers
         WHERE trigger_schema = 'public'
           AND trigger_name LIKE '%duration_overage%') <> 0 THEN
    RAISE EXCEPTION 'S1-A postdeploy: unexpected duration-overage object inventory';
  END IF;

  IF (SELECT relacl::text FROM pg_class WHERE oid = 'public.school_lesson_records'::regclass)
       <> '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'
     OR (SELECT relacl::text FROM pg_class WHERE oid = 'public.school_student_monthly_settlements'::regclass)
       <> '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    RAISE EXCEPTION 'S1-A postdeploy: table ACL changed';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1-A postdeploy: R0 feature gates mismatch';
  END IF;
END
$postdeploy$;

SELECT
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'planned') AS planned_count,
  (SELECT count(*) FROM public.school_lesson_records WHERE lesson_type = 'actual') AS actual_count,
  (SELECT count(*) FROM public.school_student_monthly_settlements) AS settlement_count,
  (SELECT count(*) FROM public.school_lesson_records WHERE
    num_nonnulls(student_duration_overage_minutes,student_duration_overage_fee_jpy,
      student_duration_overage_policy_version,student_duration_overage_source,
      student_duration_overage_decided_at) > 0) AS lesson_snapshot_nonnull,
  (SELECT count(*) FROM public.school_student_monthly_settlements WHERE
    num_nonnulls(duration_overage_minutes,duration_overage_fee_jpy,duration_overage_fee_cny,
      duration_overage_actual_count,duration_overage_policy_version,duration_overage_source) > 0)
    AS settlement_snapshot_nonnull;

SELECT
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name LIKE '%duration_overage%'
ORDER BY table_name, ordinal_position;

SELECT
  c.conrelid::regclass::text AS table_name,
  c.conname,
  pg_get_constraintdef(c.oid) AS definition,
  c.convalidated
FROM pg_constraint c
WHERE c.conname IN (
  'school_lesson_records_duration_overage_bundle_chk',
  'school_lesson_records_duration_overage_context_chk',
  'school_lesson_records_duration_overage_amount_chk',
  'school_student_settlements_duration_overage_bundle_chk',
  'school_student_settlements_duration_overage_policy_chk',
  'school_student_settlements_duration_overage_amount_chk'
)
ORDER BY table_name, c.conname;

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'school_lesson_records_duration_overage_month_idx',
    'school_lesson_records_duration_overage_planned_uidx'
  )
ORDER BY indexname;

SELECT
  p.oid::regprocedure::text AS signature,
  md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'school_create_actual_lesson_from_planned',
    'school_create_partial_completed_actual_from_planned',
    'school_create_lesson_credit_makeup_actual',
    'school_get_student_monthly_settlement_summary',
    'school_get_student_monthly_settlement_preview',
    'school_lock_student_monthly_settlement',
    'school_relock_student_monthly_settlement',
    'school_list_student_tuition_candidates',
    'school_resolve_planned_billing_attribution',
    'school_resolve_planned_duration',
    'school_calculate_planned_fee_components'
  )
ORDER BY signature;

SELECT feature_key, state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

ROLLBACK;
