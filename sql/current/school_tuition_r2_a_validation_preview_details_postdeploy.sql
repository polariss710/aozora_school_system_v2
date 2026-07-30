-- R2-A read-only postdeploy acceptance.

\set ON_ERROR_STOP on
\pset pager off

DO $postdeploy$
DECLARE
  v_result record;
  v_definition text;
BEGIN
  IF to_regprocedure(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'
     ) IS NULL THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_RPC_MISSING';
  END IF;

  SELECT pg_get_functiondef(procedure.oid)
  INTO STRICT v_definition
  FROM pg_proc procedure
  WHERE procedure.oid =
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
    AND procedure.provolatile = 's'
    AND procedure.prosecdef
    AND procedure.proconfig = ARRAY['search_path=pg_catalog, public'];

  IF md5(v_definition) <> '13fbc4d680d3b223cd2c6b59d66f2384'
     OR position(
       'school_list_student_tuition_candidates' IN v_definition
     ) = 0
     OR position(
       'school_preview_student_tuition_bill' IN v_definition
     ) = 0
     OR position('R2_A_PREVIEW_DUPLICATE_PLANNED_UUID' IN v_definition) = 0
     OR position('R2_A_PREVIEW_SUMMARY_DETAIL_MISMATCH' IN v_definition) = 0
     OR upper(v_definition) ~ '\m(INSERT|UPDATE|DELETE|UPSERT|MERGE|TRUNCATE)\M' THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_DEFINITION_MISMATCH';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368'
     OR md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920' THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_PROTECTED_READER_DRIFT';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_ACL_MISMATCH';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_R0_MISMATCH';
  END IF;

  SELECT * INTO STRICT v_result
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4',
    '2026-08',
    0.05
  );

  IF v_result.feature_state <> 'validation_preview_only'
     OR v_result.candidate_count <= 0
     OR v_result.candidate_count <> (
       SELECT count(*)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         planned_lesson_id uuid
       )
     )
     OR v_result.candidate_count <> (
       SELECT count(DISTINCT planned_lesson_id)
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         planned_lesson_id uuid
       )
     )
     OR v_result.total_lesson_count <= 0
     OR v_result.total_duration_hours <= 0
     OR v_result.total_fee_jpy <= 0
     OR v_result.bill_amount_jpy <> v_result.total_fee_jpy
     OR v_result.candidate_uuid_md5 !~ '^[0-9a-f]{32}$'
     OR v_result.candidate_manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_SUMMARY_DETAIL_MISMATCH';
  END IF;

  IF EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         planned_lesson_id uuid,
         student_id uuid,
         business_entity_id uuid,
         billing_month text,
         billing_week_start_date date,
         lesson_date date
       )
       WHERE candidate.student_id <> v_result.student_id
          OR candidate.business_entity_id <> v_result.business_entity_id
          OR candidate.billing_month <> '2026-08'
          OR extract(isodow FROM candidate.billing_week_start_date) <> 1
          OR to_char(candidate.billing_week_start_date, 'YYYY-MM') <> '2026-08'
          OR candidate.billing_week_start_date = '2026-07-27'::date
     )
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) candidate(
         billing_week_start_date date
       )
       WHERE candidate.billing_week_start_date = '2026-08-31'::date
     ) THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_MONTH_WEEK_MISMATCH';
  END IF;

  IF NOT public.school_is_valid_tuition_billing_period(
       '2026-07', '2026-07-27'::date
     )
     OR public.school_is_valid_tuition_billing_period(
       '2026-08', '2026-07-27'::date
     )
     OR NOT public.school_is_valid_tuition_billing_period(
       '2026-08', '2026-08-31'::date
     ) THEN
    RAISE EXCEPTION 'R2_A_POSTDEPLOY_CROSS_MONTH_RULE_MISMATCH';
  END IF;
END
$postdeploy$;

SELECT
  public.school_r1d_f1_planned_attribution_cutover_version() AS planned_writer_version,
  public.school_r1d_e_b2_actual_writer_cutover_version() AS actual_writer_version,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS canonical_candidate_md5,
  md5(pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  )) AS preview_details_md5,
  (SELECT jsonb_object_agg(feature_key, state ORDER BY feature_key)
   FROM public.school_feature_gates
   WHERE feature_key IN (
     'student_tuition_preview',
     'student_tuition_generate',
     'student_tuition_cash_submit'
   )) AS r0_states,
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count;
