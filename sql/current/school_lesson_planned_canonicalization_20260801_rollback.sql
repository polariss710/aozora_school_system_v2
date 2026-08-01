-- Targeted rollback for the fixed 279 planned rows and four replaced functions.
-- Required: -v planned_canonicalization_expected_updated_at='<formal timestamp>'
-- Test:     -v planned_canonicalization_rollback_commit=0
-- Execute:  -v planned_canonicalization_rollback_commit=1
\set ON_ERROR_STOP on
\pset pager off
\if :{?planned_canonicalization_expected_updated_at}
\else
  \echo 'planned_canonicalization_expected_updated_at is required'
  \quit 3
\endif
\if :{?planned_canonicalization_rollback_commit}
\else
  \set planned_canonicalization_rollback_commit 0
\endif

BEGIN;
\ir school_lesson_planned_canonicalization_20260801_manifest_values.sql
CREATE TEMPORARY TABLE school_planned_rollback_clock ON COMMIT DROP AS
SELECT :'planned_canonicalization_expected_updated_at'::timestamptz AS expected_updated_at;

SELECT count(*) AS locked_target_rows
FROM (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
  ORDER BY lesson.id
  FOR UPDATE OF lesson
) locked;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records lesson
      JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
      WHERE lesson.updated_at=(SELECT expected_updated_at FROM school_planned_rollback_clock)
        AND lesson.business_entity_id=manifest.target_business_entity_id
        AND lesson.billing_month=manifest.target_billing_month
        AND lesson.billing_week_start_date=manifest.target_billing_week_start_date
        AND lesson.student_settlement_month=manifest.target_student_settlement_month
        AND lesson.billing_month_source=manifest.target_billing_month_source
        AND lesson.billing_month_decided_at=manifest.target_billing_month_decided_at
        AND md5((to_jsonb(lesson)-'updated_at')::text)=manifest.expected_after_stable_row_hash)<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_ROLLBACK_AFTER_FINGERPRINT_DRIFT';
  END IF;
  IF position('v_old_bundle=5' IN pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure))=0
     OR position('approved_legacy_planned_canonicalization_20260801' IN pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure))=0
     OR position('approved_legacy_planned_canonicalization_20260801' IN pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure))=0
     OR position('approved_legacy_planned_canonicalization_20260801' IN pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_ROLLBACK_FUNCTION_DRIFT';
  END IF;
END
$preflight$;

-- Restore the three previous reader definitions by removing exactly one approved
-- source allowlist entry from each current definition.
DO $restore_allowlists$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$       OR v_source.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create',
         'approved_legacy_planned_canonicalization_20260801')$old$;
  v_new:=$new$       OR v_source.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create')$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'ROLLBACK_ACTUAL_SOURCE_ALLOWLIST_FAILED'; END IF;
  EXECUTE v_replaced;

  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create',
           'approved_legacy_planned_canonicalization_20260801')$old$;
  v_new:=$new$         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create')$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'ROLLBACK_LESSON_MONTH_ALLOWLIST_FAILED'; END IF;
  EXECUTE v_replaced;

  SELECT pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create',
              'approved_legacy_planned_canonicalization_20260801'
            )$old$;
  v_new:=$new$            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create'
            )$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'ROLLBACK_CANDIDATE_ALLOWLIST_FAILED'; END IF;
  EXECUTE v_replaced;

  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$
    SELECT source.* INTO v_source
    FROM public.school_lesson_records source
    WHERE source.id=v_actual_evidence.source_planned_lesson_id;
    IF NOT FOUND
       OR v_source.app_type IS DISTINCT FROM 'school'
       OR v_source.lesson_type IS DISTINCT FROM 'planned'
       OR v_source.voided_at IS NOT NULL
       OR v_source.student_id IS DISTINCT FROM v_lesson.student_id THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;

    IF v_source.business_entity_id IS DISTINCT FROM v_lesson.business_entity_id THEN
      -- Planned-only entity canonicalization leaves legacy actual rows untouched.
      -- The current source must be Aozora, while both immutable evidence rows must
      -- prove the same pre-migration student/entity link. Neither evidence source
      -- supplies or overrides the actual fulfilment month here.
      SELECT evidence.* INTO v_planned_evidence
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=v_source.id;
      IF NOT FOUND
         OR v_source.business_entity_id IS DISTINCT FROM
              '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
         OR v_planned_evidence.approved_manifest IS DISTINCT FROM true
         OR v_planned_evidence.evidence_source<>'r1d_e_b1_fixed_legacy_279'
         OR v_planned_evidence.evidence_version<>'legacy_settlement_evidence_v1'
         OR v_planned_evidence.student_id_snapshot IS DISTINCT FROM
              v_lesson.student_id
         OR v_planned_evidence.business_entity_id_snapshot IS DISTINCT FROM
              v_actual_evidence.business_entity_id_snapshot
         OR v_planned_evidence.lesson_identity_md5 IS DISTINCT FROM
              md5(concat_ws('|',v_source.id::text,
                coalesce(v_source.student_id::text,'<NULL>'),
                coalesce(v_planned_evidence.business_entity_id_snapshot::text,'<NULL>'),
                coalesce(v_source.year_month,'<NULL>'),
                v_source.lesson_type,v_source.app_type)) THEN
        RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
      END IF;
    END IF;
$old$;
  v_new:=$new$
    SELECT source.* INTO v_source
    FROM public.school_lesson_records source
    WHERE source.id=v_actual_evidence.source_planned_lesson_id;
    IF NOT FOUND
       OR v_source.app_type IS DISTINCT FROM 'school'
       OR v_source.lesson_type IS DISTINCT FROM 'planned'
       OR v_source.voided_at IS NOT NULL
       OR v_source.student_id IS DISTINCT FROM v_lesson.student_id
       OR v_source.business_entity_id IS DISTINCT FROM
            v_lesson.business_entity_id THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;
$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'ROLLBACK_ACTUAL_ENTITY_COMPAT_FAILED'; END IF;
  EXECUTE v_replaced;
END
$restore_allowlists$;

CREATE OR REPLACE FUNCTION public.school_enforce_r1d_f1_planned_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_attribution record;
  v_duration numeric;
  v_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.lesson_type IS DISTINCT FROM NEW.lesson_type
     AND (OLD.lesson_type = 'planned' OR NEW.lesson_type = 'planned') THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_LESSON_TYPE_IMMUTABLE';
  END IF;

  IF NEW.lesson_type IS DISTINCT FROM 'planned' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.lesson_date IS NULL THEN
      RAISE EXCEPTION 'R1D_F1_NEW_PLANNED_LESSON_DATE_REQUIRED';
    END IF;

    IF NEW.import_source LIKE 'lesson_planned_batch_generator%' THEN
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NULL,NEW.lesson_date);
    ELSE
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NEW.lesson_date,NULL);
    END IF;

    NEW.billing_week_start_date := v_attribution.billing_week_start_date;
    NEW.billing_month := v_attribution.billing_month;
    NEW.student_settlement_month := v_attribution.student_settlement_month;
    NEW.billing_month_source := v_attribution.billing_month_source;
    NEW.billing_month_decided_at := statement_timestamp();

    IF NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                               AND NEW.billing_week_start_date+6 THEN
      RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
    END IF;

    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_PLANNED_DURATION_NOT_DB_AUTHORITATIVE';
    END IF;
    RETURN NEW;
  END IF;

  SELECT evidence.* INTO v_evidence
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id = OLD.id;

  IF FOUND THEN
    IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
         OLD.student_settlement_month,OLD.billing_month_source,
         OLD.billing_month_decided_at) <> 0
       OR num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
         NEW.student_settlement_month,NEW.billing_month_source,
         NEW.billing_month_decided_at) <> 0
       OR NEW.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR NEW.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR NEW.year_month IS DISTINCT FROM v_evidence.legacy_student_settlement_month
       OR md5(concat_ws('|',NEW.id::text,coalesce(NEW.student_id::text,'<NULL>'),
            coalesce(NEW.business_entity_id::text,'<NULL>'),
            coalesce(NEW.year_month,'<NULL>'),NEW.lesson_type,NEW.app_type))
          IS DISTINCT FROM v_evidence.lesson_identity_md5 THEN
      RAISE EXCEPTION 'R1D_F1_LEGACY_PLANNED_IDENTITY_OR_NULL_BUNDLE_IMMUTABLE';
    END IF;
    IF NEW.lesson_date IS DISTINCT FROM OLD.lesson_date THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;

  IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
       OLD.student_settlement_month,OLD.billing_month_source,
       OLD.billing_month_decided_at) <> 5 THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_REQUIRED';
  END IF;
  IF NEW.billing_month IS DISTINCT FROM OLD.billing_month
     OR NEW.billing_week_start_date IS DISTINCT FROM OLD.billing_week_start_date
     OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
     OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
     OR NEW.billing_month_decided_at IS DISTINCT FROM OLD.billing_month_decided_at THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
  END IF;
  IF NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month
     OR NEW.billing_month IS DISTINCT FROM
          to_char(NEW.billing_week_start_date,'YYYY-MM') THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
  END IF;
  IF NEW.lesson_date IS NULL
     OR NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                               AND NEW.billing_week_start_date+6 THEN
    RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
  END IF;

  IF OLD.billing_month_source IN (
       'scheduled_date_at_create','explicit_billing_week_at_create'
     ) THEN
    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_CANONICAL_PLANNED_DURATION_INVALID';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

COMMENT ON FUNCTION public.school_enforce_r1d_f1_planned_attribution() IS
  'R1D-F1/R2-F-F2 planned attribution authority: canonical creation, immutable billing month/week/student month, week-bounded scheduled-date edits, and fail-closed legacy date edits.';
COMMENT ON FUNCTION public.school_resolve_r1d_e_b2_actual_student_month(uuid) IS
  'R1D-E-B2 actual student-month resolver. Complete immutable planned attribution is authoritative; only a unique approved R1D-E-B1 legacy evidence row may resolve an all-NULL cutover source. Partial bundles fail closed.';
COMMENT ON FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(uuid) IS
  'R2-F-D-DB1 student-month authority. Canonical actuals resolve through their immutable source planned; legacy actuals resolve only from a matching immutable R1D-E-B2 evidence row under the full current 54-column lesson shape. No row repair, evidence rewrite, broad fallback or historical reinterpretation.';
COMMENT ON FUNCTION public.school_list_student_tuition_candidates(uuid,uuid,text,boolean) IS
  'R2-B canonical service-role candidate reader. Accepts the two approved migration manifests and both F1 planned-writer sources only when the full immutable attribution bundle and all existing candidate/evidence invariants pass. No legacy year_month or lesson_date billing fallback.';

ALTER TABLE public.school_lesson_records DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
ALTER TABLE public.school_lesson_records DISABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
ALTER TABLE public.school_lesson_records DISABLE TRIGGER trg_school_lesson_records_updated_at;

CREATE TEMPORARY TABLE school_planned_rollback_changed ON COMMIT DROP AS
WITH changed AS (
  UPDATE public.school_lesson_records lesson
  SET business_entity_id=manifest.current_business_entity_id,
      billing_month=NULL,
      billing_week_start_date=NULL,
      student_settlement_month=NULL,
      billing_month_source=NULL,
      billing_month_decided_at=NULL,
      updated_at=manifest.before_updated_at
  FROM school_planned_canonicalization_manifest manifest
  WHERE lesson.id=manifest.lesson_id
    AND lesson.updated_at=:'planned_canonicalization_expected_updated_at'::timestamptz
    AND md5((to_jsonb(lesson)-'updated_at')::text)=manifest.expected_after_stable_row_hash
  RETURNING lesson.id
)
SELECT id FROM changed;

ALTER TABLE public.school_lesson_records ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
ALTER TABLE public.school_lesson_records ENABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
ALTER TABLE public.school_lesson_records ENABLE TRIGGER trg_school_lesson_records_updated_at;

DO $verify$
BEGIN
  IF (SELECT count(*) FROM school_planned_rollback_changed)<>279
     OR (SELECT count(*) FROM public.school_lesson_records lesson
         JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
         WHERE lesson.business_entity_id=manifest.current_business_entity_id
           AND lesson.updated_at=manifest.before_updated_at
           AND md5(to_jsonb(lesson)::text)=manifest.before_row_hash
           AND num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
             lesson.student_settlement_month,lesson.billing_month_source,
             lesson.billing_month_decided_at)=0)<>279
     OR md5(pg_get_functiondef(
          'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
        ))<>'cc3fc1846815f1f2848186ca14319df5'
     OR md5(pg_get_functiondef(
          'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
        ))<>'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
          'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
        ))<>'ea944ad620268ac4d86fc8e622ba8d02'
     OR md5(pg_get_functiondef(
          'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
        ))<>'1770f3469dbc3bc030a977381b853deb' THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_ROLLBACK_VALIDATION_FAILED';
  END IF;
END
$verify$;

\if :planned_canonicalization_rollback_commit
  COMMIT;
  \echo 'PLANNED_CANONICALIZATION_20260801_ROLLBACK_COMMITTED'
\else
  ROLLBACK;
  \echo 'PLANNED_CANONICALIZATION_20260801_ROLLBACK_TEST_ROLLED_BACK'
\endif
