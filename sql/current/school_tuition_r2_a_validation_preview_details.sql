-- Aozora School V2 tuition P0 R2-A.
-- Adds one read-only, R0 validation-only preview detail RPC.
-- Required psql variable: r2_a_commit=0 for rollback rehearsal or 1 for deployment.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_a_commit}
\else
  \echo 'R2_A_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

DO $preflight$
BEGIN
  IF to_regprocedure(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_DETAILS_ALREADY_EXISTS';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R2_A_PROTECTED_READER_DRIFT';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.school_preview_student_tuition_bill(uuid,text,numeric)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'authenticated',
       'public.school_preview_student_tuition_bill(uuid,text,numeric)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_A_PROTECTED_READER_ACL_DRIFT';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_A_R0_DRIFT';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE r2_a_business_before ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons', (SELECT jsonb_build_array(count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
    FROM public.school_lesson_records t),
  'bills', (SELECT jsonb_build_array(count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
    FROM public.school_student_tuition_bills t),
  'income', (SELECT jsonb_build_array(count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
    FROM public.school_income_records t),
  'gates', (SELECT jsonb_build_array(count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.feature_key), '')))
    FROM public.school_feature_gates t)
) AS fingerprint;

CREATE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
RETURNS TABLE (
  feature_state text,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  candidate_count integer,
  total_lesson_count integer,
  total_duration_hours numeric,
  total_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,
  existing_income_record_id uuid,
  existing_income_status text,
  candidate_uuid_md5 text,
  candidate_manifest_sha256 text,
  candidates jsonb,
  message text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_billing_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month, '')), '');
  v_preview record;
  v_candidate_count integer;
  v_distinct_candidate_count integer;
  v_total_lesson_count integer;
  v_total_duration_hours numeric;
  v_total_fee_jpy numeric;
  v_candidate_uuid_md5 text;
  v_candidate_manifest_sha256 text;
  v_candidates jsonb;
  v_contract_valid boolean;
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_preview',
    'validation_preview_only',
    'TUITION_PREVIEW_BLOCKED',
    '学费预览 gate 不可用，已按 fail-closed 拒绝。'
  );

  SELECT * INTO STRICT v_preview
  FROM public.school_preview_student_tuition_bill(
    p_student_id,
    v_billing_month,
    p_billing_exchange_rate
  );

  WITH candidate_rows AS MATERIALIZED (
    SELECT
      candidate.planned_lesson_id,
      candidate.student_id,
      candidate.business_entity_id,
      candidate.candidate_billing_month AS billing_month,
      lesson.billing_week_start_date,
      candidate.lesson_date,
      candidate.lesson_count,
      candidate.duration_hours,
      candidate.lesson_fee
    FROM public.school_list_student_tuition_candidates(
      p_student_id,
      v_preview.business_entity_id,
      v_billing_month,
      false
    ) candidate
    JOIN public.school_lesson_records lesson
      ON lesson.id = candidate.planned_lesson_id
  ), aggregated AS (
    SELECT
      count(*)::integer AS candidate_count,
      count(DISTINCT candidate_detail.planned_lesson_id)::integer AS distinct_candidate_count,
      coalesce(sum(candidate_detail.lesson_count), 0)::integer AS total_lesson_count,
      coalesce(sum(candidate_detail.duration_hours), 0)::numeric AS total_duration_hours,
      coalesce(sum(candidate_detail.lesson_fee), 0)::numeric AS total_fee_jpy,
      md5(string_agg(candidate_detail.planned_lesson_id::text, ','
        ORDER BY candidate_detail.planned_lesson_id::text))
        AS candidate_uuid_md5,
      encode(pg_catalog.sha256(pg_catalog.convert_to(
        string_agg(concat_ws('|',
          candidate_detail.planned_lesson_id::text,
          candidate_detail.student_id::text,
          candidate_detail.business_entity_id::text,
          candidate_detail.billing_month,
          candidate_detail.billing_week_start_date::text,
          candidate_detail.lesson_date::text,
          candidate_detail.lesson_count::text,
          candidate_detail.duration_hours::text,
          candidate_detail.lesson_fee::text
        ), E'\n' ORDER BY candidate_detail.billing_week_start_date,
          candidate_detail.lesson_date, candidate_detail.planned_lesson_id)
        || E'\n',
        'UTF8'
      )), 'hex') AS candidate_manifest_sha256,
      jsonb_agg(jsonb_build_object(
        'planned_lesson_id', candidate_detail.planned_lesson_id,
        'student_id', candidate_detail.student_id,
        'business_entity_id', candidate_detail.business_entity_id,
        'billing_month', candidate_detail.billing_month,
        'billing_week_start_date', candidate_detail.billing_week_start_date,
        'lesson_date', candidate_detail.lesson_date,
        'lesson_count', candidate_detail.lesson_count,
        'duration_hours', candidate_detail.duration_hours,
        'lesson_fee', candidate_detail.lesson_fee
      ) ORDER BY candidate_detail.billing_week_start_date,
        candidate_detail.lesson_date, candidate_detail.planned_lesson_id) AS candidates,
      bool_and(
        candidate_detail.student_id = p_student_id
        AND candidate_detail.business_entity_id = v_preview.business_entity_id
        AND candidate_detail.billing_month = v_billing_month
        AND candidate_detail.billing_week_start_date IS NOT NULL
        AND extract(isodow FROM candidate_detail.billing_week_start_date) = 1
        AND to_char(candidate_detail.billing_week_start_date, 'YYYY-MM') = v_billing_month
      ) AS contract_valid
    FROM candidate_rows candidate_detail
  )
  SELECT
    aggregated.candidate_count,
    aggregated.distinct_candidate_count,
    aggregated.total_lesson_count,
    aggregated.total_duration_hours,
    aggregated.total_fee_jpy,
    aggregated.candidate_uuid_md5,
    aggregated.candidate_manifest_sha256,
    aggregated.candidates,
    aggregated.contract_valid
  INTO
    v_candidate_count,
    v_distinct_candidate_count,
    v_total_lesson_count,
    v_total_duration_hours,
    v_total_fee_jpy,
    v_candidate_uuid_md5,
    v_candidate_manifest_sha256,
    v_candidates,
    v_contract_valid
  FROM aggregated;

  IF v_candidate_count IS NULL OR v_candidate_count <= 0 THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_CANDIDATES_EMPTY';
  END IF;
  IF v_candidate_count IS DISTINCT FROM v_distinct_candidate_count THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_DUPLICATE_PLANNED_UUID';
  END IF;
  IF v_contract_valid IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_CANDIDATE_ATTRIBUTION_MISMATCH';
  END IF;
  IF v_preview.student_id IS DISTINCT FROM p_student_id
     OR v_preview.billing_month IS DISTINCT FROM v_billing_month
     OR v_preview.planned_lesson_count IS DISTINCT FROM v_candidate_count
     OR v_preview.planned_lesson_hours IS DISTINCT FROM v_total_duration_hours
     OR v_preview.planned_lesson_fee_jpy IS DISTINCT FROM v_total_fee_jpy
     OR v_preview.bill_amount_jpy IS DISTINCT FROM v_total_fee_jpy THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_SUMMARY_DETAIL_MISMATCH';
  END IF;
  IF jsonb_array_length(v_candidates) IS DISTINCT FROM v_candidate_count THEN
    RAISE EXCEPTION 'R2_A_PREVIEW_JSON_COUNT_MISMATCH';
  END IF;

  RETURN QUERY SELECT
    'validation_preview_only'::text,
    v_preview.student_id,
    v_preview.business_entity_id,
    v_preview.billing_month,
    v_preview.previous_settlement_month,
    v_preview.previous_settlement_id,
    v_preview.previous_carryover_cny,
    v_candidate_count,
    v_total_lesson_count,
    v_total_duration_hours,
    v_total_fee_jpy,
    v_preview.bill_amount_jpy,
    v_preview.currency,
    v_preview.billing_exchange_rate,
    v_preview.billing_amount_cny,
    v_preview.billing_amount_currency,
    v_preview.existing_tuition_bill_id,
    v_preview.existing_tuition_bill_status,
    v_preview.existing_income_record_id,
    v_preview.existing_income_status,
    v_candidate_uuid_md5,
    v_candidate_manifest_sha256,
    v_candidates,
    v_preview.message;
END
$function$;

COMMENT ON FUNCTION
  public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
IS 'R2-A read-only R0 validation preview. Reuses the canonical candidate reader and existing preview authority, returns one snapshot with stable UUID/hash/detail manifests, and fails closed on duplicate UUID, month/week, scope, or summary/detail drift.';

REVOKE ALL ON FUNCTION
  public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  TO authenticated, service_role;

DO $verify$
DECLARE
  v_result record;
  v_before jsonb;
  v_after jsonb;
BEGIN
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
     OR EXISTS (
       SELECT 1
       FROM pg_proc procedure
       CROSS JOIN LATERAL aclexplode(coalesce(
         procedure.proacl,
         acldefault('f', procedure.proowner)
       )) acl
       WHERE procedure.oid =
         'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
         AND acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_A_NEW_RPC_ACL_MISMATCH';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'R2_A_CANDIDATE_READER_ACL_EXPANDED';
  END IF;

  SELECT * INTO STRICT v_result
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4',
    '2026-08',
    0.05
  );

  IF v_result.feature_state <> 'validation_preview_only'
     OR v_result.candidate_count <= 0
     OR v_result.total_lesson_count <= 0
     OR v_result.total_duration_hours <= 0
     OR v_result.total_fee_jpy <= 0
     OR jsonb_array_length(v_result.candidates) <> v_result.candidate_count
     OR EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) AS candidate(
         planned_lesson_id uuid,
         billing_month text,
         billing_week_start_date date
       )
       WHERE candidate.billing_month <> '2026-08'
          OR candidate.billing_week_start_date = '2026-07-27'::date
     )
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(v_result.candidates) AS candidate(
         planned_lesson_id uuid,
         billing_month text,
         billing_week_start_date date
       )
       WHERE candidate.billing_week_start_date = '2026-08-31'::date
     ) THEN
    RAISE EXCEPTION 'R2_A_REAL_AUGUST_PREVIEW_MISMATCH';
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
    RAISE EXCEPTION 'R2_A_CROSS_MONTH_WEEK_AUTHORITY_MISMATCH';
  END IF;

  BEGIN
    UPDATE public.school_feature_gates
    SET state = 'blocked'
    WHERE feature_key = 'student_tuition_preview'
      AND state = 'validation_preview_only';

    BEGIN
      PERFORM *
      FROM public.school_get_student_tuition_validation_preview_details(
        '7aef8061-7037-4881-a847-a2cdb031c0f4',
        '2026-08',
        0.05
      );
      RAISE EXCEPTION 'R2_A_EXPECTED_R0_FAILURE_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'R2_A_EXPECTED_R0_FAILURE_MISSING'
         OR position('TUITION_PREVIEW_BLOCKED' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
    END;

    RAISE EXCEPTION 'R2_A_R0_NEGATIVE_FIXTURE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'R2_A_R0_NEGATIVE_FIXTURE_ROLLBACK' THEN
      RAISE;
    END IF;
  END;

  SELECT fingerprint INTO STRICT v_before FROM r2_a_business_before;
  SELECT jsonb_build_object(
    'lessons', (SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
      FROM public.school_lesson_records t),
    'bills', (SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
      FROM public.school_student_tuition_bills t),
    'income', (SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), '')))
      FROM public.school_income_records t),
    'gates', (SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.feature_key), '')))
      FROM public.school_feature_gates t)
  ) INTO v_after;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'R2_A_BUSINESS_DATA_CHANGED';
  END IF;
END
$verify$;

SET LOCAL ROLE authenticated;
SELECT
  feature_state,
  student_id,
  business_entity_id,
  billing_month,
  candidate_count,
  total_lesson_count,
  total_duration_hours,
  total_fee_jpy,
  candidate_uuid_md5,
  candidate_manifest_sha256
FROM public.school_get_student_tuition_validation_preview_details(
  '7aef8061-7037-4881-a847-a2cdb031c0f4',
  '2026-08',
  0.05
);
RESET ROLE;

SELECT
  md5(pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  )) AS preview_details_definition_md5,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS canonical_candidate_definition_md5,
  md5(pg_get_functiondef(
    'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
  )) AS existing_preview_definition_md5;

\if :r2_a_commit
\else
  \ir school_tuition_r2_a_validation_preview_details_postdeploy.sql
\endif

\if :r2_a_commit
  COMMIT;
  \echo 'R2_A_VALIDATION_PREVIEW_DETAILS_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_A_VALIDATION_PREVIEW_DETAILS_REHEARSAL_ROLLED_BACK'
\endif
