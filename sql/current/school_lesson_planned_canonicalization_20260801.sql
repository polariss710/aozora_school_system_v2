-- Approved one-time canonicalization of the fixed 279 legacy planned lessons.
-- Rehearsal: psql ... -v planned_canonicalization_commit=0 -f this_file.sql
-- Formal:    psql ... -v planned_canonicalization_commit=1 -f this_file.sql
-- The same bytes are used for both. No actual, bill, income, settlement, wage,
-- account, Cash-linkage, evidence, or feature-gate row is written.
\set ON_ERROR_STOP on
\pset pager off
\if :{?planned_canonicalization_commit}
\else
  \set planned_canonicalization_commit 0
\endif

BEGIN;

\ir school_lesson_planned_canonicalization_20260801_manifest_values.sql

-- Freeze the approved rows and fail closed on any drift from the fixed manifest.
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
  IF (SELECT count(*) FROM school_planned_canonicalization_manifest)<>279
     OR (SELECT count(DISTINCT lesson_id) FROM school_planned_canonicalization_manifest)<>279
     OR EXISTS (
       SELECT 1 FROM school_planned_canonicalization_manifest
       WHERE target_business_entity_id<>'2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
          OR target_billing_month_source<>'approved_legacy_planned_canonicalization_20260801'
          OR target_billing_month_decided_at<>'2026-08-01 13:39:37.829675+00'::timestamptz
          OR target_student_settlement_month<>target_billing_month
          OR extract(isodow FROM target_billing_week_start_date)<>1
          OR to_char(target_billing_week_start_date,'YYYY-MM')<>target_billing_month
          OR lesson_date NOT BETWEEN target_billing_week_start_date
                                 AND target_billing_week_start_date+6
     ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_MANIFEST_CONTRACT_INVALID';
  END IF;

  IF (SELECT count(*) FROM public.school_business_entities
      WHERE id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
        AND name='青空进学塾')<>1 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_TARGET_ENTITY_INVALID';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_GATE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records lesson
      JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
      WHERE lesson.app_type='school'
        AND lesson.lesson_type='planned'
        AND lesson.student_id=manifest.student_id
        AND lesson.lesson_date=manifest.lesson_date
        AND lesson.status=manifest.status
        AND lesson.import_batch_id IS NOT DISTINCT FROM manifest.generation_batch_id
        AND lesson.business_entity_id=manifest.current_business_entity_id
        AND lesson.updated_at=manifest.before_updated_at
        AND md5(to_jsonb(lesson)::text)=manifest.before_row_hash
        AND md5((to_jsonb(lesson)-'updated_at')::text)=manifest.before_stable_row_hash
        AND num_nonnulls(
          lesson.billing_month,lesson.billing_week_start_date,
          lesson.student_settlement_month,lesson.billing_month_source,
          lesson.billing_month_decided_at
        )=0)<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_BEFORE_FINGERPRINT_DRIFT';
  END IF;

  IF (SELECT count(*)
      FROM public.school_legacy_planned_settlement_evidence evidence
      JOIN school_planned_canonicalization_manifest manifest
        ON manifest.lesson_id=evidence.planned_lesson_id
      JOIN public.school_lesson_records lesson ON lesson.id=manifest.lesson_id
      WHERE evidence.approved_manifest IS TRUE
        AND evidence.evidence_source=manifest.evidence_source
        AND evidence.evidence_version=manifest.evidence_version
        AND evidence.recorded_at=manifest.evidence_recorded_at
        AND evidence.legacy_student_settlement_month=manifest.legacy_evidence_month
        AND evidence.student_id_snapshot=lesson.student_id
        AND evidence.business_entity_id_snapshot=lesson.business_entity_id
        AND evidence.lesson_identity_md5=md5(concat_ws('|',
          lesson.id::text,coalesce(lesson.student_id::text,'<NULL>'),
          coalesce(lesson.business_entity_id::text,'<NULL>'),
          coalesce(lesson.year_month,'<NULL>'),lesson.lesson_type,lesson.app_type
        )))<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_EVIDENCE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE app_type='school' AND lesson_type='planned'
        AND num_nonnulls(
          billing_month,billing_week_start_date,student_settlement_month,
          billing_month_source,billing_month_decided_at
        )=0)<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_LEGACY_SCOPE_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM school_planned_canonicalization_manifest
       WHERE lesson_id='f256bca9-fac5-4909-b113-8077efd27d65'::uuid
         AND target_billing_week_start_date='2026-09-28'
         AND target_billing_month='2026-09'
         AND target_student_settlement_month='2026-09'
     ) OR NOT EXISTS (
       SELECT 1 FROM school_planned_canonicalization_manifest
       WHERE lesson_id='552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid
         AND target_billing_week_start_date='2026-10-26'
         AND target_billing_month='2026-10'
         AND target_student_settlement_month='2026-10'
     ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_SPECIAL_IDS_INVALID';
  END IF;

  IF md5(pg_get_functiondef(
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
     ))<>'1770f3469dbc3bc030a977381b853deb'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'33d0a36904ef02f595c69caafefe4f92' THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_FUNCTION_DRIFT';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE school_planned_protected_before (
  object_name text PRIMARY KEY,row_count bigint,row_hash text
) ON COMMIT DROP;

INSERT INTO school_planned_protected_before
SELECT 'actual_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
FROM public.school_lesson_records x WHERE x.lesson_type='actual'
UNION ALL SELECT 'non_target_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
FROM public.school_lesson_records x WHERE NOT EXISTS (
  SELECT 1 FROM school_planned_canonicalization_manifest m WHERE m.lesson_id=x.id)
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
UNION ALL SELECT 'expense',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_expense_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'settlement_adjustments',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_settlement_adjustments x
UNION ALL SELECT 'student_payments',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_payments x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'planned_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),'')) FROM public.school_legacy_planned_settlement_evidence x
UNION ALL SELECT 'actual_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),'')) FROM public.school_legacy_actual_settlement_evidence x
UNION ALL SELECT 'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.feature_key),'')) FROM public.school_feature_gates x;

-- Canonical-first planned trigger. Inserts retain the existing writer authority;
-- migrated rows no longer re-enter the legacy evidence branch on later updates.
CREATE OR REPLACE FUNCTION public.school_enforce_r1d_f1_planned_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_attribution record;
  v_duration numeric;
  v_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
  v_old_bundle integer;
  v_new_bundle integer;
BEGIN
  IF TG_OP='UPDATE'
     AND OLD.lesson_type IS DISTINCT FROM NEW.lesson_type
     AND (OLD.lesson_type='planned' OR NEW.lesson_type='planned') THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_LESSON_TYPE_IMMUTABLE';
  END IF;
  IF NEW.lesson_type IS DISTINCT FROM 'planned' THEN RETURN NEW; END IF;

  IF TG_OP='INSERT' THEN
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
    NEW.billing_week_start_date:=v_attribution.billing_week_start_date;
    NEW.billing_month:=v_attribution.billing_month;
    NEW.student_settlement_month:=v_attribution.student_settlement_month;
    NEW.billing_month_source:=v_attribution.billing_month_source;
    NEW.billing_month_decided_at:=statement_timestamp();
    IF NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                               AND NEW.billing_week_start_date+6 THEN
      RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
    END IF;
    v_duration:=public.school_resolve_planned_duration(
      NEW.start_time::text,NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END);
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_PLANNED_DURATION_NOT_DB_AUTHORITATIVE';
    END IF;
    RETURN NEW;
  END IF;

  v_old_bundle:=num_nonnulls(
    OLD.billing_month,OLD.billing_week_start_date,OLD.student_settlement_month,
    OLD.billing_month_source,OLD.billing_month_decided_at);
  v_new_bundle:=num_nonnulls(
    NEW.billing_month,NEW.billing_week_start_date,NEW.student_settlement_month,
    NEW.billing_month_source,NEW.billing_month_decided_at);

  IF v_old_bundle=5 THEN
    IF v_new_bundle<>5
       OR NEW.billing_month IS DISTINCT FROM OLD.billing_month
       OR NEW.billing_week_start_date IS DISTINCT FROM OLD.billing_week_start_date
       OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
       OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
       OR NEW.billing_month_decided_at IS DISTINCT FROM OLD.billing_month_decided_at
       OR NEW.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create',
         'approved_legacy_planned_canonicalization_20260801')
       OR NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month
       OR NEW.billing_month IS DISTINCT FROM to_char(NEW.billing_week_start_date,'YYYY-MM') THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF NEW.lesson_date IS NULL
       OR NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                                   AND NEW.billing_week_start_date+6 THEN
      RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
    END IF;
    IF OLD.billing_month_source IN (
         'scheduled_date_at_create','explicit_billing_week_at_create') THEN
      v_duration:=public.school_resolve_planned_duration(
        NEW.start_time::text,NEW.end_time::text,
        CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
             THEN NEW.duration_hours ELSE NULL END);
      IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
        RAISE EXCEPTION 'R1D_F1_CANONICAL_PLANNED_DURATION_INVALID';
      END IF;
    END IF;
    RETURN NEW;
  ELSIF v_old_bundle<>0 THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_REQUIRED';
  END IF;

  SELECT evidence.* INTO v_evidence
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id=OLD.id;
  IF NOT FOUND OR v_new_bundle<>0
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
END
$function$;

COMMENT ON FUNCTION public.school_enforce_r1d_f1_planned_attribution() IS
  'Planned attribution authority: canonical rows are authoritative and immutable even when cutover evidence remains for audit; all-NULL legacy rows remain fail-closed. New writers cannot emit the approved one-time 20260801 historical source.';

-- Add the single approved historical source to existing canonical reader allowlists.
DO $replace_allowlists$
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
         'scheduled_date_at_create','explicit_billing_week_at_create')$old$;
  v_new:=$new$       OR v_source.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create',
         'approved_legacy_planned_canonicalization_20260801')$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'ACTUAL_SOURCE_ALLOWLIST_REPLACE_FAILED'; END IF;
  EXECUTE v_replaced;

  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create')$old$;
  v_new:=$new$         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create',
           'approved_legacy_planned_canonicalization_20260801')$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'LESSON_MONTH_ALLOWLIST_REPLACE_FAILED'; END IF;
  EXECUTE v_replaced;

  SELECT pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  ) INTO v_definition;
  v_old:=$old$            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create'
            )$old$;
  v_new:=$new$            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create',
              'approved_legacy_planned_canonicalization_20260801'
            )$new$;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition THEN RAISE EXCEPTION 'CANDIDATE_ALLOWLIST_REPLACE_FAILED'; END IF;
  EXECUTE v_replaced;
END
$replace_allowlists$;

COMMENT ON FUNCTION public.school_resolve_r1d_e_b2_actual_student_month(uuid) IS
  'Resolves a source planned student month from a complete approved canonical bundle, including the fixed 20260801 planned historical canonicalization source; all-NULL legacy evidence remains temporary read compatibility.';
COMMENT ON FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(uuid) IS
  'Authoritative lesson student-month resolver. Complete canonical planned rows, including the fixed 20260801 planned historical source, take precedence; unmigrated actual evidence remains authoritative for the excluded legacy actual scope.';
COMMENT ON FUNCTION public.school_list_student_tuition_candidates(uuid,uuid,text,boolean) IS
  'Canonical tuition candidate reader. Accepts the fixed 20260801 planned historical source only with the complete immutable attribution bundle; no lesson-date or year_month billing fallback.';

-- The two business guards correctly reject legacy charged-row attribution changes.
-- The fixed manifest and complete fingerprints below replace those generic guards
-- only for this one transaction; both triggers are restored before validation/commit.
ALTER TABLE public.school_lesson_records
  DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
ALTER TABLE public.school_lesson_records
  DISABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;

CREATE TEMPORARY TABLE school_planned_changed_ids ON COMMIT DROP AS
WITH changed AS (
  UPDATE public.school_lesson_records lesson
  SET business_entity_id=manifest.target_business_entity_id,
      billing_month=manifest.target_billing_month,
      billing_week_start_date=manifest.target_billing_week_start_date,
      student_settlement_month=manifest.target_student_settlement_month,
      billing_month_source=manifest.target_billing_month_source,
      billing_month_decided_at=manifest.target_billing_month_decided_at
  FROM school_planned_canonicalization_manifest manifest
  WHERE lesson.id=manifest.lesson_id
    AND lesson.updated_at=manifest.before_updated_at
    AND md5(to_jsonb(lesson)::text)=manifest.before_row_hash
  RETURNING lesson.id
)
SELECT id FROM changed;

DO $update_count$
BEGIN
  IF (SELECT count(*) FROM school_planned_changed_ids)<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_UPDATE_COUNT_MISMATCH';
  END IF;
END
$update_count$;

ALTER TABLE public.school_lesson_records
  ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
ALTER TABLE public.school_lesson_records
  ENABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;

CREATE TEMPORARY TABLE school_planned_protected_after
  (LIKE school_planned_protected_before INCLUDING ALL) ON COMMIT DROP;
INSERT INTO school_planned_protected_after
SELECT 'actual_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
FROM public.school_lesson_records x WHERE x.lesson_type='actual'
UNION ALL SELECT 'non_target_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
FROM public.school_lesson_records x WHERE NOT EXISTS (
  SELECT 1 FROM school_planned_canonicalization_manifest m WHERE m.lesson_id=x.id)
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
UNION ALL SELECT 'expense',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_expense_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'settlement_adjustments',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_settlement_adjustments x
UNION ALL SELECT 'student_payments',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_payments x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'planned_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),'')) FROM public.school_legacy_planned_settlement_evidence x
UNION ALL SELECT 'actual_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),'')) FROM public.school_legacy_actual_settlement_evidence x
UNION ALL SELECT 'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.feature_key),'')) FROM public.school_feature_gates x;

DO $verify$
DECLARE
  v_preview record;
BEGIN
  IF EXISTS (
    (SELECT * FROM school_planned_protected_before EXCEPT SELECT * FROM school_planned_protected_after)
    UNION ALL
    (SELECT * FROM school_planned_protected_after EXCEPT SELECT * FROM school_planned_protected_before)
  ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_PROTECTED_OBJECT_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records lesson
      JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
      WHERE lesson.business_entity_id=manifest.target_business_entity_id
        AND lesson.billing_month=manifest.target_billing_month
        AND lesson.billing_week_start_date=manifest.target_billing_week_start_date
        AND lesson.student_settlement_month=manifest.target_student_settlement_month
        AND lesson.billing_month_source=manifest.target_billing_month_source
        AND lesson.billing_month_decided_at=manifest.target_billing_month_decided_at
        AND md5((to_jsonb(lesson)-'updated_at')::text)=manifest.expected_after_stable_row_hash)<>279
     OR (SELECT count(DISTINCT lesson.updated_at)
         FROM public.school_lesson_records lesson
         JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id)<>1
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466')<>417
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0)<>0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND billing_month_source='approved_legacy_planned_canonicalization_20260801')<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_TARGET_VALIDATION_FAILED';
  END IF;

  IF (SELECT count(*) FROM school_planned_canonicalization_manifest manifest
      WHERE public.school_resolve_r1d_e_c_lesson_student_month(manifest.lesson_id)
            =manifest.target_student_settlement_month)<>279 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_RESOLVER_FAILED';
  END IF;

  -- Validate the planned-only canonical month directly. The combined page reader
  -- also scans legacy actuals; one pre-existing post-evidence actual-row drift is
  -- intentionally left for the separately approved actual phase.
  IF (SELECT count(*) FROM public.school_lesson_records lesson
      WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
        AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc')<>18
     OR (SELECT sum(lesson.duration_hours) FROM public.school_lesson_records lesson
      WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
        AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc')<>36
     OR (SELECT sum(lesson.lesson_fee) FROM public.school_lesson_records lesson
      WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
        AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc')<>306000 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_SUN_MONTH_FAILED';
  END IF;

  IF EXISTS (
    WITH expected(week_start,row_count,hours,fee) AS (VALUES
      ('2026-07-06'::date,4::bigint,8::numeric,68000::numeric),
      ('2026-07-13'::date,4::bigint,8::numeric,68000::numeric),
      ('2026-07-20'::date,5::bigint,10::numeric,85000::numeric),
      ('2026-07-27'::date,5::bigint,10::numeric,85000::numeric)
    ), actual AS (
      SELECT expected.week_start,
        (SELECT count(*) FROM public.school_lesson_records lesson
         WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
           AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
           AND lesson.billing_week_start_date=expected.week_start
           AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc') row_count,
        (SELECT coalesce(sum(lesson.duration_hours),0) FROM public.school_lesson_records lesson
         WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
           AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
           AND lesson.billing_week_start_date=expected.week_start
           AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc') hours,
        (SELECT coalesce(sum(lesson.lesson_fee),0) FROM public.school_lesson_records lesson
         WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
           AND lesson.voided_at IS NULL AND lesson.billing_month='2026-07'
           AND lesson.billing_week_start_date=expected.week_start
           AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc') fee
      FROM expected
    )
    SELECT 1 FROM expected JOIN actual USING(week_start)
    WHERE (expected.row_count,expected.hours,expected.fee)
       IS DISTINCT FROM (actual.row_count,actual.hours,actual.fee)
  ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_SUN_WEEK_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND lesson_type='planned' AND status='pending_makeup'
        AND billing_week_start_date='2026-07-06')<>4
     OR (SELECT sum(duration_hours) FROM public.school_lesson_records
      WHERE student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND lesson_type='planned' AND status='pending_makeup'
        AND billing_week_start_date='2026-07-06')<>8
     OR (SELECT sum(open_source_count) FROM public.school_list_student_lesson_credit_balances(
          'b17abc58-2f64-4bad-bf20-c9643ead60bc'))<>6
     OR (SELECT sum(open_credit_hours) FROM public.school_list_student_lesson_credit_balances(
          'b17abc58-2f64-4bad-bf20-c9643ead60bc'))<>11 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_MAKEUP_BALANCE_FAILED';
  END IF;

  IF (SELECT count(*)
      FROM (SELECT DISTINCT student_id,target_billing_month
            FROM school_planned_canonicalization_manifest) scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
        scope.target_billing_month,true) candidate
      JOIN school_planned_canonicalization_manifest manifest
        ON manifest.lesson_id=candidate.planned_lesson_id)<>279
     OR EXISTS (
       SELECT 1 FROM school_planned_canonicalization_manifest manifest
       CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
         manifest.student_id,manifest.target_business_entity_id,
         manifest.target_billing_month,true) candidate
       WHERE candidate.planned_lesson_id=manifest.lesson_id
         AND candidate.candidate_status='candidate'
         AND (manifest.status='pending_makeup' OR manifest.has_bill_relation)
     ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_CANDIDATE_FAILED';
  END IF;

  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042::numeric);
  IF v_preview.feature_state<>'enabled'
     OR v_preview.generate_feature_state<>'blocked' THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_PREVIEW_GATE_FAILED';
  END IF;

  -- The actual phase is explicitly excluded. Prove the eight approved makeup
  -- fulfilment months and their immutable rows/evidence directly, without
  -- reinterpreting or rewriting any actual through a planned migration.
  IF EXISTS (
    WITH expected(actual_id,student_month) AS (VALUES
      ('bd07e78c-eeaf-4881-9bd7-6b80bde0f11b'::uuid,'2026-05'::text),
      ('1318070d-363a-486d-b0a4-bac2160cc600'::uuid,'2026-05'::text),
      ('6e6cf820-5c47-40b4-a7aa-6852127d3fe3'::uuid,'2026-06'::text),
      ('2785117a-a3e0-484f-a803-2d023ab22499'::uuid,'2026-06'::text),
      ('45dd767f-a7e2-4d7b-9ce5-e627c7d93d5f'::uuid,'2026-06'::text),
      ('6cb328c3-2af8-4205-9c1c-3183783614e8'::uuid,'2026-06'::text),
      ('68f7cc0f-231b-4fa1-985a-5ecfac59b4e8'::uuid,'2026-07'::text),
      ('9fe69b4b-c5e9-4392-b926-f47ab59c58f7'::uuid,'2026-07'::text)
    )
    SELECT 1
    FROM expected
    LEFT JOIN public.school_lesson_records actual ON actual.id=expected.actual_id
    LEFT JOIN public.school_legacy_actual_settlement_evidence evidence
      ON evidence.actual_lesson_id=expected.actual_id
    WHERE actual.id IS NULL
       OR evidence.actual_lesson_id IS NULL
       OR actual.lesson_type<>'actual'
       OR actual.status<>'makeup_completed'
       OR evidence.legacy_year_month<>expected.student_month
       OR actual.student_settlement_month IS NOT NULL
       OR evidence.source_planned_lesson_id IS DISTINCT FROM actual.planned_lesson_id
       OR evidence.actual_full_row_md5 IS DISTINCT FROM
            md5((to_jsonb(actual)-'lesson_total_fee_jpy')::text)
  ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_MAKEUP_ACTUAL_EVIDENCE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR position('approved_legacy_planned_canonicalization_20260801' IN
          pg_get_functiondef('public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure))=0
     OR position('approved_legacy_planned_canonicalization_20260801' IN
          pg_get_functiondef('public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure))=0
     OR position('approved_legacy_planned_canonicalization_20260801' IN
          pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure))=0
     OR position('v_old_bundle=5' IN
          pg_get_functiondef('public.school_enforce_r1d_f1_planned_attribution()'::regprocedure))=0 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_FINAL_CONTRACT_FAILED';
  END IF;
END
$verify$;

SELECT lesson.updated_at AS migration_row_updated_at,
       count(*) AS migrated_rows,
       md5(string_agg(md5(to_jsonb(lesson)::text),'' ORDER BY lesson.id::text)) AS migrated_full_hash,
       md5(string_agg(md5((to_jsonb(lesson)-'updated_at')::text),'' ORDER BY lesson.id::text)) AS migrated_stable_hash
FROM public.school_lesson_records lesson
JOIN school_planned_canonicalization_manifest manifest ON manifest.lesson_id=lesson.id
GROUP BY lesson.updated_at;

SELECT * FROM school_planned_protected_after ORDER BY object_name;

\if :planned_canonicalization_commit
  COMMIT;
  \echo 'PLANNED_CANONICALIZATION_20260801_COMMITTED'
\else
  ROLLBACK;
  \echo 'PLANNED_CANONICALIZATION_20260801_REHEARSAL_ROLLED_BACK'
\endif
