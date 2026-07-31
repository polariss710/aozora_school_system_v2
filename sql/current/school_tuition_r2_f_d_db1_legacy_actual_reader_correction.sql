-- School V2 R2-F-D-DB1: legacy actual reader schema-evolution correction.
-- Required psql variable:
--   r2_f_d_db1_commit=0  same-byte rehearsal with explicit ROLLBACK
--   r2_f_d_db1_commit=1  formal DDL deployment with explicit COMMIT
-- This file only replaces school_resolve_r1d_e_c_lesson_student_month(uuid).

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_d_db1_commit}
\else
  \echo 'R2_F_D_DB1_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_F_D_DB1_BEGIN'
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

LOCK TABLE public.school_lesson_records IN SHARE MODE;

DO $preflight$
DECLARE
  v_proc pg_proc%ROWTYPE;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid=
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure;

  IF md5(pg_get_functiondef(v_proc.oid))<>
       '8de65e9787d8d66f2cd7b65eb2479a8c' THEN
    RAISE EXCEPTION 'R2_F_D_DB1_UNEXPECTED_DEPLOYED_RESOLVER';
  END IF;
  IF v_proc.provolatile<>'s' OR NOT v_proc.prosecdef
     OR v_proc.proowner::regrole::text<>'postgres'
     OR v_proc.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, public']::text[]
     OR v_proc.proacl::text<>'{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'R2_F_D_DB1_RESOLVER_METADATA_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR EXISTS (
       SELECT 1
       FROM public.school_legacy_actual_settlement_evidence evidence
       JOIN public.school_lesson_records actual
         ON actual.id=evidence.actual_lesson_id
       WHERE evidence.actual_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
               actual.id::text,actual.planned_lesson_id::text,
               actual.student_id::text,actual.business_entity_id::text,
               coalesce(actual.teacher_id::text,'<NULL>'),
               coalesce(actual.subject_id::text,'<NULL>'),actual.year_month,
               coalesce(actual.teacher_settlement_month,
                 to_char(actual.lesson_date,'YYYY-MM')),
               actual.lesson_date::text,actual.lesson_type,actual.app_type))
          OR evidence.actual_full_row_md5 IS DISTINCT FROM
               md5((to_jsonb(actual)-'lesson_total_fee_jpy')::text)
          OR actual.lesson_total_fee_jpy IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'R2_F_D_DB1_LEGACY_EVIDENCE_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*)
      FROM public.school_legacy_actual_settlement_evidence evidence
      JOIN public.school_lesson_records actual
        ON actual.id=evidence.actual_lesson_id
      WHERE evidence.actual_full_row_md5 IS DISTINCT FROM
        md5(to_jsonb(actual)::text))<>234 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_SCHEMA_EVOLUTION_MISMATCH_NOT_REPRODUCED';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_R0_CHANGED';
  END IF;
END
$preflight$;

\echo 'R2_F_D_DB1_CREATE_OR_REPLACE_RESOLVER'
CREATE OR REPLACE FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(
  p_lesson_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_lesson public.school_lesson_records%ROWTYPE;
  v_source public.school_lesson_records%ROWTYPE;
  v_planned_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
  v_actual_evidence public.school_legacy_actual_settlement_evidence%ROWTYPE;
  v_source_month text;
  v_duration numeric;
  v_bundle_count integer;
BEGIN
  IF p_lesson_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_ID_REQUIRED';
  END IF;

  SELECT lesson.* INTO v_lesson
  FROM public.school_lesson_records lesson
  WHERE lesson.id=p_lesson_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_NOT_FOUND';
  END IF;
  IF v_lesson.app_type IS DISTINCT FROM 'school'
     OR v_lesson.lesson_type NOT IN ('planned','actual')
     OR v_lesson.student_id IS NULL
     OR v_lesson.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_BASE_IDENTITY_INVALID';
  END IF;

  IF v_lesson.lesson_type='planned' THEN
    v_bundle_count:=num_nonnulls(v_lesson.billing_month,
      v_lesson.billing_week_start_date,v_lesson.student_settlement_month,
      v_lesson.billing_month_source,v_lesson.billing_month_decided_at);

    IF v_bundle_count=5 THEN
      IF v_lesson.billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
         OR v_lesson.student_settlement_month IS DISTINCT FROM
              v_lesson.billing_month
         OR extract(isodow FROM v_lesson.billing_week_start_date)<>1
         OR to_char(v_lesson.billing_week_start_date,'YYYY-MM')<>
              v_lesson.billing_month
         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create') THEN
        RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_ATTRIBUTION_INVALID';
      END IF;

      IF v_lesson.billing_month_source IN (
           'scheduled_date_at_create','explicit_billing_week_at_create') THEN
        IF v_lesson.lesson_date IS NULL THEN
          RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_DATE_REQUIRED';
        END IF;
        v_duration:=public.school_resolve_planned_duration(
          v_lesson.start_time::text,
          v_lesson.end_time::text,
          CASE WHEN v_lesson.start_time IS NULL AND v_lesson.end_time IS NULL
               THEN v_lesson.duration_hours ELSE NULL END
        );
        IF v_lesson.duration_hours IS DISTINCT FROM v_duration THEN
          RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_DURATION_INVALID';
        END IF;
      END IF;
      RETURN v_lesson.student_settlement_month;
    END IF;

    IF v_bundle_count=0 THEN
      SELECT evidence.* INTO v_planned_evidence
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=v_lesson.id;

      IF NOT FOUND
         OR v_planned_evidence.approved_manifest IS DISTINCT FROM true
         OR v_planned_evidence.evidence_source<>
              'r1d_e_b1_fixed_legacy_279'
         OR v_planned_evidence.evidence_version<>
              'legacy_settlement_evidence_v1'
         OR v_lesson.student_id IS DISTINCT FROM
              v_planned_evidence.student_id_snapshot
         OR v_lesson.business_entity_id IS DISTINCT FROM
              v_planned_evidence.business_entity_id_snapshot
         OR v_lesson.year_month IS DISTINCT FROM
              v_planned_evidence.legacy_student_settlement_month
         OR v_planned_evidence.lesson_identity_md5 IS DISTINCT FROM
              md5(concat_ws('|',v_lesson.id::text,
                coalesce(v_lesson.student_id::text,'<NULL>'),
                coalesce(v_lesson.business_entity_id::text,'<NULL>'),
                coalesce(v_lesson.year_month,'<NULL>'),
                v_lesson.lesson_type,v_lesson.app_type)) THEN
        RAISE EXCEPTION 'R1D_E_C_LEGACY_PLANNED_EVIDENCE_MISMATCH';
      END IF;
      RETURN v_planned_evidence.legacy_student_settlement_month;
    END IF;

    RAISE EXCEPTION 'R1D_E_C_PARTIAL_PLANNED_ATTRIBUTION_REJECTED';
  END IF;

  SELECT evidence.* INTO v_actual_evidence
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE evidence.actual_lesson_id=v_lesson.id;

  IF FOUND THEN
    IF v_lesson.student_settlement_month IS NOT NULL
       OR v_actual_evidence.source_planned_lesson_id IS DISTINCT FROM
            v_lesson.planned_lesson_id
       OR v_actual_evidence.student_id_snapshot IS DISTINCT FROM
            v_lesson.student_id
       OR v_actual_evidence.business_entity_id_snapshot IS DISTINCT FROM
            v_lesson.business_entity_id
       OR v_actual_evidence.teacher_id_snapshot IS DISTINCT FROM
            v_lesson.teacher_id
       OR v_actual_evidence.subject_id_snapshot IS DISTINCT FROM
            v_lesson.subject_id
       OR v_actual_evidence.legacy_year_month IS DISTINCT FROM
            v_lesson.year_month
       OR v_actual_evidence.teacher_settlement_month_snapshot IS DISTINCT FROM
            coalesce(v_lesson.teacher_settlement_month,
              to_char(v_lesson.lesson_date,'YYYY-MM'))
       OR v_actual_evidence.lesson_date_snapshot IS DISTINCT FROM
            v_lesson.lesson_date
       OR v_actual_evidence.evidence_source<>
            'r1d_e_b2_all_existing_actual_at_cutover'
       OR v_actual_evidence.evidence_version<>
            'actual_legacy_settlement_evidence_v1'
       OR v_actual_evidence.actual_identity_md5 IS DISTINCT FROM
            md5(concat_ws('|',v_lesson.id::text,
              v_lesson.planned_lesson_id::text,v_lesson.student_id::text,
              v_lesson.business_entity_id::text,
              coalesce(v_lesson.teacher_id::text,'<NULL>'),
              coalesce(v_lesson.subject_id::text,'<NULL>'),v_lesson.year_month,
              coalesce(v_lesson.teacher_settlement_month,
                to_char(v_lesson.lesson_date,'YYYY-MM')),
              v_lesson.lesson_date::text,v_lesson.lesson_type,v_lesson.app_type))
       OR v_lesson.lesson_total_fee_jpy IS NOT NULL
       OR v_actual_evidence.actual_full_row_md5 IS DISTINCT FROM
            md5((to_jsonb(v_lesson)-'lesson_total_fee_jpy')::text) THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;
    RETURN v_actual_evidence.legacy_year_month;
  END IF;

  IF v_lesson.planned_lesson_id IS NULL
     OR v_lesson.student_settlement_month IS NULL
     OR v_lesson.student_settlement_month !~
          '^[0-9]{4}-(0[1-9]|1[0-2])$'
     OR v_lesson.year_month IS DISTINCT FROM
          v_lesson.student_settlement_month
     OR v_lesson.lesson_date IS NULL
     OR v_lesson.teacher_settlement_month IS DISTINCT FROM
          to_char(v_lesson.lesson_date,'YYYY-MM')
     OR num_nonnulls(v_lesson.billing_month,
          v_lesson.billing_week_start_date,v_lesson.billing_month_source,
          v_lesson.billing_month_decided_at)<>0 THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_ATTRIBUTION_INVALID';
  END IF;

  SELECT source.* INTO v_source
  FROM public.school_lesson_records source
  WHERE source.id=v_lesson.planned_lesson_id;

  IF NOT FOUND
     OR v_source.app_type IS DISTINCT FROM 'school'
     OR v_source.lesson_type IS DISTINCT FROM 'planned'
     OR v_source.voided_at IS NOT NULL
     OR v_source.student_id IS DISTINCT FROM v_lesson.student_id
     OR v_source.business_entity_id IS DISTINCT FROM
          v_lesson.business_entity_id THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_SOURCE_INVALID';
  END IF;

  v_source_month:=
    public.school_resolve_r1d_e_c_lesson_student_month(v_source.id);
  IF v_lesson.student_settlement_month IS DISTINCT FROM v_source_month THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_SOURCE_MONTH_MISMATCH';
  END IF;

  RETURN v_lesson.student_settlement_month;
END
$function$;

REVOKE ALL ON FUNCTION
  public.school_resolve_r1d_e_c_lesson_student_month(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(uuid)
IS 'R2-F-D-DB1 authoritative settlement-month resolver. Legacy actual evidence remains immutable; schema-added lesson_total_fee_jpy must be NULL and is excluded from the pre-column full-row hash.';

\echo 'R2_F_D_DB1_TARGET_CALLS'
DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_resolved_count integer;
  v_error text;
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
          '%v_lesson.lesson_total_fee_jpy IS NOT NULL%' THEN
    RAISE EXCEPTION 'R2_F_D_DB1_RESOLVER_NOT_CORRECTED';
  END IF;

  SELECT count(*) INTO v_resolved_count
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE public.school_resolve_r1d_e_c_lesson_student_month(
          evidence.actual_lesson_id)=evidence.legacy_year_month;
  IF v_resolved_count<>234 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_LEGACY_RESOLUTION_COUNT_FAILED';
  END IF;

  PERFORM * FROM public.school_get_student_monthly_settlement_preview(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07');
  PERFORM * FROM public.school_get_student_monthly_settlement_preview(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07');

  BEGIN
    PERFORM *
    FROM public.school_get_student_tuition_validation_preview_details(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_SUN_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM *
    FROM public.school_get_student_tuition_validation_preview_details(
      '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043);
    RAISE EXCEPTION 'R2_F_D_DB1_ZHANG_EXPECTED_PREVIOUS_SETTLEMENT_REQUIRED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error<>'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED' THEN RAISE; END IF;
  END;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_D_DB1_R0_CHANGED_AFTER_REPLACE';
  END IF;
END
$verify$;

\if :r2_f_d_db1_commit
  \echo 'R2_F_D_DB1_COMMIT'
  COMMIT;
\else
  \echo 'R2_F_D_DB1_ROLLBACK'
  ROLLBACK;
\endif
