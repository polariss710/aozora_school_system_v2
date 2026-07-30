\set ON_ERROR_STOP on
\pset pager off

-- Read-only postdeployment acceptance for the S1-B approved legacy source patch.

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';

DO $postdeploy$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  ) INTO v_definition;

  IF md5(v_definition) <> '149634304f5407de81f23717b913be7e'
     OR position('S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED' IN v_definition) = 0
     OR position('S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED' IN v_definition) = 0
     OR position('coalesce(v_overage_source_student_month, v_planned.year_month)' IN v_definition) = 0
     OR position('S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED' IN v_definition) > 0 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_WRITER_DEFINITION_INVALID';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
     )) <> 'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
     )) <> 'd24b82f51053b3960ce0e4839613ddc7'
     OR md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
     )) <> 'f9f5e0fffc2d0fcb5f917cc374c9e9ac'
     OR md5(pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
     )) <> '523058b631837025101d558668ce10c8'
     OR md5(pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> '5b313cc696057a4a1f960ed8f1b50124' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_PROTECTED_FUNCTION_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records p
    JOIN public.school_legacy_planned_settlement_evidence e
      ON e.planned_lesson_id = p.id
    JOIN public.school_business_entities b ON b.id = p.business_entity_id
    WHERE p.id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
      AND p.lesson_type = 'planned'
      AND p.status = 'planned'
      AND p.voided_at IS NULL
      AND p.is_billable IS TRUE
      AND p.duration_hours = 2
      AND p.unit_price = 10000
      AND b.code = 'aosora'
      AND b.name = '青空进学塾'
      AND e.approved_manifest IS TRUE
      AND e.evidence_source = 'r1d_e_b1_fixed_legacy_279'
      AND e.evidence_version = 'legacy_settlement_evidence_v1'
      AND e.legacy_student_settlement_month = '2026-07'
      AND e.lesson_identity_md5 = md5(concat_ws('|',
        p.id::text,
        coalesce(p.student_id::text, '<NULL>'),
        coalesce(p.business_entity_id::text, '<NULL>'),
        coalesce(p.year_month, '<NULL>'),
        p.lesson_type,
        p.app_type
      ))
      AND num_nonnulls(
        p.billing_month,
        p.billing_week_start_date,
        p.student_settlement_month,
        p.billing_month_source,
        p.billing_month_decided_at
      ) = 0
      AND public.school_resolve_r1d_e_b2_actual_student_month(p.id) = '2026-07'
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_SOURCE_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records a
    WHERE a.lesson_type = 'actual'
      AND a.planned_lesson_id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_ACTUAL_WAS_CREATED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_monthly_settlements s
    JOIN public.school_lesson_records p ON p.student_id = s.student_id
    WHERE p.id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
      AND s.business_entity_id IS NOT DISTINCT FROM p.business_entity_id
      AND s.year_month = '2026-07'
      AND s.settlement_status = 'locked'
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_SOURCE_MONTH_LOCKED';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_R0_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM pg_trigger t
      WHERE t.tgrelid = 'public.school_lesson_records'::regclass
        AND t.tgname = 'trg_school_lesson_r1d_f1_planned_attribution'
        AND t.tgenabled = 'O') <> 1
     OR (SELECT count(*)
         FROM pg_trigger t
         WHERE t.tgrelid =
               'public.school_legacy_planned_settlement_evidence'::regclass
           AND t.tgname = 'school_legacy_planned_evidence_row_immutable'
           AND t.tgenabled = 'O') <> 1 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_FIXTURE_TRIGGER_STATE_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM pg_constraint c
      WHERE c.conrelid = 'public.school_lesson_records'::regclass
        AND c.conname IN (
          'school_lesson_records_billing_pair_complete_chk',
          'school_lesson_records_billing_source_metadata_chk'
        )
        AND c.convalidated) <> 2 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_FIXTURE_CONSTRAINT_STATE_CHANGED';
  END IF;
END
$postdeploy$;

SELECT
  md5(pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  )) AS ordinary_writer_md5,
  (SELECT count(*)
   FROM public.school_lesson_records a
   WHERE a.lesson_type = 'actual'
     AND a.planned_lesson_id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid)
    AS target_associated_actual_count,
  (SELECT count(*)
   FROM public.school_lesson_records l
   WHERE num_nonnulls(
     l.student_duration_overage_minutes,
     l.student_duration_overage_fee_jpy,
     l.student_duration_overage_policy_version,
     l.student_duration_overage_source,
     l.student_duration_overage_decided_at
   ) > 0) AS formal_overage_bundle_count,
  (SELECT count(*) FROM public.school_lesson_records) AS lesson_count,
  (SELECT count(*) FROM public.school_student_monthly_settlements)
    AS settlement_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count;

SELECT feature_key, state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

ROLLBACK;
