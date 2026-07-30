-- School V2 tuition P0 R1D-E-B1: immutable legacy settlement evidence.
-- Required psql variable: r1d_e_b1_commit=0 for rollback rehearsal or 1 for deployment.
-- This file creates two evidence tables and two read-only helpers. It never updates
-- lessons, actuals, settlements, writers, readers, financial rows, or R0 gates.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_b1_commit}
\else
  \echo 'R1D_E_B1_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF to_regclass('public.school_legacy_planned_settlement_evidence') IS NOT NULL
     OR to_regclass('public.school_legacy_settlement_snapshot_basis_evidence') IS NOT NULL
     OR to_regprocedure('public.school_guard_r1d_e_b1_legacy_evidence_immutable()') IS NOT NULL
     OR to_regprocedure('public.school_get_legacy_planned_student_settlement_month(uuid)') IS NOT NULL
     OR to_regprocedure('public.school_is_legacy_settlement_snapshot_basis(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'R1D_E_B1_TARGET_OBJECT_ALREADY_EXISTS';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R1D_E_B1_R0_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_B1_CANDIDATE_FUNCTION_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month, billing_week_start_date,
          student_settlement_month, billing_month_source,
          billing_month_decided_at) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month, billing_week_start_date,
          student_settlement_month, billing_month_source,
          billing_month_decided_at) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(billing_month, billing_week_start_date,
          student_settlement_month, billing_month_source,
          billing_month_decided_at) BETWEEN 1 AND 4) <> 0 THEN
    RAISE EXCEPTION 'R1D_E_B1_PLANNED_118_279_0_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'planned'
        AND num_nonnulls(billing_month, billing_week_start_date,
          student_settlement_month, billing_month_source,
          billing_month_decided_at) = 0) <> 279
     OR (SELECT md5(string_agg(id::text, ',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE app_type = 'school' AND lesson_type = 'planned'
           AND num_nonnulls(billing_month, billing_week_start_date,
             student_settlement_month, billing_month_source,
             billing_month_decided_at) = 0)
        <> '0975fdc91b533680e5ccc909f076ac62'
     OR (SELECT encode(sha256(convert_to(
          string_agg(concat_ws('|', id::text, coalesce(student_id::text, '<NULL>'),
            coalesce(business_entity_id::text, '<NULL>'), coalesce(year_month, '<NULL>'),
            lesson_type, app_type), E'\n' ORDER BY id::text) || E'\n', 'UTF8'
        )), 'hex')
         FROM public.school_lesson_records
         WHERE app_type = 'school' AND lesson_type = 'planned'
           AND num_nonnulls(billing_month, billing_week_start_date,
             student_settlement_month, billing_month_source,
             billing_month_decided_at) = 0)
        <> '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627' THEN
    RAISE EXCEPTION 'R1D_E_B1_LEGACY_279_MANIFEST_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE app_type = 'school' AND lesson_type = 'actual'
        AND created_at <= TIMESTAMPTZ '2026-07-30 03:24:07.006005+00') <> 233
     OR (SELECT md5(string_agg(id::text, ',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE app_type = 'school' AND lesson_type = 'actual'
           AND created_at <= TIMESTAMPTZ '2026-07-30 03:24:07.006005+00')
        <> '606b4cce348e67e4cffac62eb9e4a487'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text), '' ORDER BY id::text), ''))
         FROM public.school_lesson_records a
         WHERE app_type = 'school' AND lesson_type = 'actual'
           AND created_at <= TIMESTAMPTZ '2026-07-30 03:24:07.006005+00')
        <> 'b7307877cd924a20fc1e96f844f68a74'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE app_type = 'school' AND lesson_type = 'actual'
           AND created_at <= TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND student_settlement_month IS NULL) <> 233 THEN
    RAISE EXCEPTION 'R1D_E_B1_FIXED_ACTUAL_233_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(student_duration_overage_minutes,
        student_duration_overage_fee_jpy,
        student_duration_overage_policy_version,
        student_duration_overage_source,
        student_duration_overage_decided_at) > 0) <> 0 THEN
    RAISE EXCEPTION 'R1D_E_B1_OVERAGE_FIELDS_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_student_monthly_settlements
      WHERE settlement_status = 'locked') <> 15
     OR (SELECT md5(string_agg(id::text, ',' ORDER BY id::text))
         FROM public.school_student_monthly_settlements
         WHERE settlement_status = 'locked')
        <> 'c87016564bb4ab954993ddf9f37ff955'
     OR (SELECT md5(string_agg(md5(to_jsonb(s)::text), ',' ORDER BY id::text))
         FROM public.school_student_monthly_settlements s
         WHERE settlement_status = 'locked')
        <> '51fd3d3759b432c4b214e0eb5038e616' THEN
    RAISE EXCEPTION 'R1D_E_B1_LOCKED_SNAPSHOT_SET_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bills x)
        <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_income_records x)
        <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(x) - ARRAY[
          'base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot'
        ])::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bill_lessons x)
        <> '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_historical_lesson_exclusions x)
        <> '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R1D_E_B1_FINANCIAL_CHAIN_CHANGED';
  END IF;
END
$preflight$;

CREATE FUNCTION pg_temp.r1d_e_b1_existing_business_fingerprint()
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $fingerprint$
  SELECT jsonb_build_object(
    'lessons', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_lesson_records t),
    'settlements', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_student_monthly_settlements t),
    'bills', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_student_tuition_bills t),
    'income', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_income_records t),
    'relations', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_student_tuition_bill_lessons t),
    'historical_exclusions', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.id::text), ''))) FROM public.school_student_tuition_historical_lesson_exclusions t),
    'feature_gates', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' ORDER BY t.feature_key), ''))) FROM public.school_feature_gates t),
    'candidate', md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)),
    'writer_reader', (SELECT jsonb_build_array(count(*), md5(string_agg(concat_ws('|', p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text, '<NULL>')), E'\n' ORDER BY p.oid::regprocedure::text)))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
        'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
        'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
        'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
        'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue',
        'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
        'school_create_partial_completed_actual_from_planned','school_create_lesson_credit_makeup_actual',
        'school_create_makeup_completed_actual_lesson_from_planned',
        'school_create_cross_month_makeup_completed_actual_from_planned',
        'school_get_student_monthly_settlement_summary','school_get_student_monthly_settlement_preview',
        'school_get_student_monthly_settlement_wage_blockers',
        'school_assert_student_monthly_settlement_no_wage_blocker',
        'school_lock_student_monthly_settlement','school_unlock_student_monthly_settlement',
        'school_relock_student_monthly_settlement',
        'school_set_student_monthly_settlement_draft_adjustment'
      ]::text[]))
  );
$fingerprint$;

CREATE TEMPORARY TABLE r1d_e_b1_existing_business_before
ON COMMIT DROP
AS SELECT pg_temp.r1d_e_b1_existing_business_fingerprint() AS fingerprint;

CREATE TABLE public.school_legacy_planned_settlement_evidence (
  planned_lesson_id uuid PRIMARY KEY
    REFERENCES public.school_lesson_records(id) ON DELETE RESTRICT,
  student_id_snapshot uuid,
  business_entity_id_snapshot uuid,
  legacy_student_settlement_month text NOT NULL,
  lesson_identity_md5 text NOT NULL,
  approved_manifest boolean NOT NULL DEFAULT true,
  evidence_source text NOT NULL DEFAULT 'r1d_e_b1_fixed_legacy_279',
  evidence_version text NOT NULL DEFAULT 'legacy_settlement_evidence_v1',
  recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT school_legacy_planned_month_chk
    CHECK (legacy_student_settlement_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT school_legacy_planned_identity_md5_chk
    CHECK (lesson_identity_md5 ~ '^[0-9a-f]{32}$'),
  CONSTRAINT school_legacy_planned_manifest_chk CHECK (approved_manifest),
  CONSTRAINT school_legacy_planned_source_chk
    CHECK (evidence_source = 'r1d_e_b1_fixed_legacy_279'),
  CONSTRAINT school_legacy_planned_version_chk
    CHECK (evidence_version = 'legacy_settlement_evidence_v1')
);

COMMENT ON TABLE public.school_legacy_planned_settlement_evidence IS
  'R1D-E-B1 immutable evidence for the fixed 279 legacy planned lessons. Not wired into planned writers or settlement readers in this phase.';
COMMENT ON COLUMN public.school_legacy_planned_settlement_evidence.legacy_student_settlement_month IS
  'Approved legacy month evidence copied from the frozen year_month identity; this does not backfill school_lesson_records.student_settlement_month.';

CREATE TABLE public.school_legacy_settlement_snapshot_basis_evidence (
  settlement_snapshot_id uuid PRIMARY KEY
    REFERENCES public.school_student_monthly_settlements(id) ON DELETE RESTRICT,
  student_id_snapshot uuid NOT NULL,
  business_entity_id_snapshot uuid NOT NULL,
  settlement_month_snapshot text NOT NULL,
  settlement_status_snapshot text NOT NULL,
  lesson_count bigint NOT NULL,
  planned_lesson_count bigint NOT NULL,
  actual_lesson_count bigint NOT NULL,
  lesson_uuid_md5 text NOT NULL,
  amount_basis_md5 text NOT NULL,
  settlement_structure_md5 text NOT NULL,
  evidence_source text NOT NULL DEFAULT 'r1d_e_b1_fixed_locked_15',
  evidence_version text NOT NULL DEFAULT 'legacy_settlement_basis_v1',
  recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT school_legacy_snapshot_month_chk
    CHECK (settlement_month_snapshot ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT school_legacy_snapshot_status_chk
    CHECK (settlement_status_snapshot = 'locked'),
  CONSTRAINT school_legacy_snapshot_counts_chk
    CHECK (lesson_count >= 0 AND planned_lesson_count >= 0
      AND actual_lesson_count >= 0
      AND lesson_count = planned_lesson_count + actual_lesson_count),
  CONSTRAINT school_legacy_snapshot_hashes_chk
    CHECK (lesson_uuid_md5 ~ '^[0-9a-f]{32}$'
      AND amount_basis_md5 ~ '^[0-9a-f]{32}$'
      AND settlement_structure_md5 ~ '^[0-9a-f]{32}$'),
  CONSTRAINT school_legacy_snapshot_source_chk
    CHECK (evidence_source = 'r1d_e_b1_fixed_locked_15'),
  CONSTRAINT school_legacy_snapshot_version_chk
    CHECK (evidence_version = 'legacy_settlement_basis_v1')
);

COMMENT ON TABLE public.school_legacy_settlement_snapshot_basis_evidence IS
  'R1D-E-B1 immutable basis evidence for the fixed 15 locked legacy settlement snapshots. No settlement row is modified.';

INSERT INTO public.school_legacy_planned_settlement_evidence (
  planned_lesson_id, student_id_snapshot, business_entity_id_snapshot,
  legacy_student_settlement_month, lesson_identity_md5
)
SELECT
  lesson.id,
  lesson.student_id,
  lesson.business_entity_id,
  lesson.year_month,
  md5(concat_ws('|', lesson.id::text, coalesce(lesson.student_id::text, '<NULL>'),
    coalesce(lesson.business_entity_id::text, '<NULL>'),
    coalesce(lesson.year_month, '<NULL>'), lesson.lesson_type, lesson.app_type))
FROM public.school_lesson_records lesson
WHERE lesson.app_type = 'school'
  AND lesson.lesson_type = 'planned'
  AND num_nonnulls(lesson.billing_month, lesson.billing_week_start_date,
    lesson.student_settlement_month, lesson.billing_month_source,
    lesson.billing_month_decided_at) = 0
ORDER BY lesson.id;

WITH locked AS (
  SELECT * FROM public.school_student_monthly_settlements
  WHERE settlement_status = 'locked'
), basis AS (
  SELECT
    settlement.*,
    lessons.lesson_count,
    lessons.planned_count,
    lessons.actual_count,
    lessons.lesson_uuid_md5,
    md5(concat_ws('|', settlement.preset_exchange_rate::text,
      settlement.planned_lesson_fee_jpy::text, settlement.planned_lesson_fee_cny::text,
      settlement.actual_lesson_fee_jpy::text, settlement.actual_lesson_fee_cny::text,
      settlement.previous_balance_cny::text, settlement.received_jpy::text,
      settlement.received_cny::text, settlement.received_equivalent_cny::text,
      settlement.system_difference_cny::text, settlement.adjustment_amount_cny::text,
      settlement.carryover_amount_cny::text)) AS amount_md5,
    md5(to_jsonb(settlement)::text) AS structure_md5
  FROM locked settlement
  LEFT JOIN LATERAL (
    SELECT
      count(*) AS lesson_count,
      count(*) FILTER (WHERE lesson.lesson_type = 'planned') AS planned_count,
      count(*) FILTER (WHERE lesson.lesson_type = 'actual') AS actual_count,
      md5(string_agg(lesson.id::text, ',' ORDER BY lesson.id::text)) AS lesson_uuid_md5
    FROM public.school_lesson_records lesson
    WHERE lesson.app_type = 'school'
      AND lesson.student_id = settlement.student_id
      AND lesson.year_month = settlement.year_month
      AND NOT (lesson.lesson_type = 'planned' AND lesson.voided_at IS NOT NULL)
  ) lessons ON true
)
INSERT INTO public.school_legacy_settlement_snapshot_basis_evidence (
  settlement_snapshot_id, student_id_snapshot, business_entity_id_snapshot,
  settlement_month_snapshot, settlement_status_snapshot, lesson_count,
  planned_lesson_count, actual_lesson_count, lesson_uuid_md5,
  amount_basis_md5, settlement_structure_md5
)
SELECT
  id, student_id, business_entity_id, year_month, settlement_status,
  lesson_count, planned_count, actual_count, lesson_uuid_md5,
  amount_md5, structure_md5
FROM basis
ORDER BY id;

CREATE FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE';
END
$function$;

COMMENT ON FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable() IS
  'Rejects INSERT, UPDATE, DELETE, and TRUNCATE after the fixed R1D-E-B1 evidence seed is installed.';

CREATE TRIGGER school_legacy_planned_evidence_row_immutable
BEFORE INSERT OR UPDATE OR DELETE
ON public.school_legacy_planned_settlement_evidence
FOR EACH ROW EXECUTE FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable();

CREATE TRIGGER school_legacy_planned_evidence_truncate_immutable
BEFORE TRUNCATE
ON public.school_legacy_planned_settlement_evidence
FOR EACH STATEMENT EXECUTE FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable();

CREATE TRIGGER school_legacy_snapshot_evidence_row_immutable
BEFORE INSERT OR UPDATE OR DELETE
ON public.school_legacy_settlement_snapshot_basis_evidence
FOR EACH ROW EXECUTE FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable();

CREATE TRIGGER school_legacy_snapshot_evidence_truncate_immutable
BEFORE TRUNCATE
ON public.school_legacy_settlement_snapshot_basis_evidence
FOR EACH STATEMENT EXECUTE FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable();

CREATE FUNCTION public.school_get_legacy_planned_student_settlement_month(
  p_planned_lesson_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
  SELECT evidence.legacy_student_settlement_month
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id = p_planned_lesson_id;
$function$;

CREATE FUNCTION public.school_is_legacy_settlement_snapshot_basis(
  p_settlement_snapshot_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.school_legacy_settlement_snapshot_basis_evidence evidence
    WHERE evidence.settlement_snapshot_id = p_settlement_snapshot_id
  );
$function$;

COMMENT ON FUNCTION public.school_get_legacy_planned_student_settlement_month(uuid) IS
  'Read-only R1D-E-B1 helper for the fixed 279 legacy planned evidence; not wired into any writer in this phase.';
COMMENT ON FUNCTION public.school_is_legacy_settlement_snapshot_basis(uuid) IS
  'Read-only R1D-E-B1 membership helper for the fixed 15 locked snapshot basis rows.';

ALTER TABLE public.school_legacy_planned_settlement_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_legacy_settlement_snapshot_basis_evidence ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.school_legacy_planned_settlement_evidence
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.school_legacy_settlement_snapshot_basis_evidence
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.school_legacy_planned_settlement_evidence TO service_role;
GRANT SELECT ON TABLE public.school_legacy_settlement_snapshot_basis_evidence TO service_role;

REVOKE ALL ON FUNCTION public.school_guard_r1d_e_b1_legacy_evidence_immutable()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_get_legacy_planned_student_settlement_month(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.school_is_legacy_settlement_snapshot_basis(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_get_legacy_planned_student_settlement_month(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.school_is_legacy_settlement_snapshot_basis(uuid)
  TO service_role;

DO $verify$
DECLARE
  v_planned_manifest text;
  v_snapshot_manifest text;
  v_sample_planned uuid;
  v_sample_snapshot uuid;
BEGIN
  SELECT encode(sha256(convert_to(
    string_agg(concat_ws('|', planned_lesson_id::text,
      coalesce(student_id_snapshot::text, '<NULL>'),
      coalesce(business_entity_id_snapshot::text, '<NULL>'),
      legacy_student_settlement_month, 'planned', 'school'),
      E'\n' ORDER BY planned_lesson_id::text) || E'\n', 'UTF8'
  )), 'hex')
  INTO v_planned_manifest
  FROM public.school_legacy_planned_settlement_evidence;

  SELECT encode(sha256(convert_to(
    string_agg(concat_ws('|', settlement_snapshot_id::text,
      student_id_snapshot::text, business_entity_id_snapshot::text,
      settlement_month_snapshot, settlement_status_snapshot,
      lesson_count::text, planned_lesson_count::text,
      actual_lesson_count::text, lesson_uuid_md5,
      amount_basis_md5, settlement_structure_md5),
      E'\n' ORDER BY settlement_snapshot_id::text) || E'\n', 'UTF8'
  )), 'hex')
  INTO v_snapshot_manifest
  FROM public.school_legacy_settlement_snapshot_basis_evidence;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR v_planned_manifest <> '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR v_snapshot_manifest <> '68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_B1_INSERTED_EVIDENCE_MANIFEST_FAILED';
  END IF;

  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid IN (
        'public.school_legacy_planned_settlement_evidence'::regclass,
        'public.school_legacy_settlement_snapshot_basis_evidence'::regclass
      ) AND NOT tgisinternal AND tgenabled = 'O') <> 4 THEN
    RAISE EXCEPTION 'R1D_E_B1_IMMUTABLE_TRIGGER_COUNT_FAILED';
  END IF;

  IF NOT has_table_privilege('service_role',
       'public.school_legacy_planned_settlement_evidence', 'SELECT')
     OR has_table_privilege('service_role',
       'public.school_legacy_planned_settlement_evidence', 'INSERT,UPDATE,DELETE,TRUNCATE')
     OR NOT has_table_privilege('service_role',
       'public.school_legacy_settlement_snapshot_basis_evidence', 'SELECT')
     OR has_table_privilege('service_role',
       'public.school_legacy_settlement_snapshot_basis_evidence', 'INSERT,UPDATE,DELETE,TRUNCATE')
     OR has_table_privilege('anon',
       'public.school_legacy_planned_settlement_evidence', 'SELECT')
     OR has_table_privilege('authenticated',
       'public.school_legacy_settlement_snapshot_basis_evidence', 'SELECT')
     OR has_function_privilege('anon',
       'public.school_get_legacy_planned_student_settlement_month(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_is_legacy_settlement_snapshot_basis(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'R1D_E_B1_PRIVILEGE_FAILED';
  END IF;

  SELECT planned_lesson_id INTO v_sample_planned
  FROM public.school_legacy_planned_settlement_evidence
  ORDER BY planned_lesson_id LIMIT 1;
  SELECT settlement_snapshot_id INTO v_sample_snapshot
  FROM public.school_legacy_settlement_snapshot_basis_evidence
  ORDER BY settlement_snapshot_id LIMIT 1;

  IF public.school_get_legacy_planned_student_settlement_month(v_sample_planned)
       IS DISTINCT FROM (SELECT legacy_student_settlement_month
                         FROM public.school_legacy_planned_settlement_evidence
                         WHERE planned_lesson_id = v_sample_planned)
     OR NOT public.school_is_legacy_settlement_snapshot_basis(v_sample_snapshot)
     OR public.school_is_legacy_settlement_snapshot_basis(
          '00000000-0000-4000-8000-00000000eb10'::uuid) THEN
    RAISE EXCEPTION 'R1D_E_B1_READ_HELPER_FAILED';
  END IF;

  BEGIN
    INSERT INTO public.school_legacy_planned_settlement_evidence (
      planned_lesson_id, legacy_student_settlement_month, lesson_identity_md5
    ) VALUES (
      '00000000-0000-4000-8000-00000000eb11'::uuid,
      '2026-01', repeat('0', 32)
    );
    RAISE EXCEPTION 'R1D_E_B1_EXPECTED_PLANNED_INSERT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE public.school_legacy_settlement_snapshot_basis_evidence
    SET recorded_at = recorded_at WHERE settlement_snapshot_id = v_sample_snapshot;
    RAISE EXCEPTION 'R1D_E_B1_EXPECTED_SNAPSHOT_UPDATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM public.school_legacy_planned_settlement_evidence
    WHERE planned_lesson_id = v_sample_planned;
    RAISE EXCEPTION 'R1D_E_B1_EXPECTED_PLANNED_DELETE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  BEGIN
    EXECUTE 'TRUNCATE TABLE public.school_legacy_settlement_snapshot_basis_evidence';
    RAISE EXCEPTION 'R1D_E_B1_EXPECTED_SNAPSHOT_TRUNCATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R1D_E_B1_LEGACY_EVIDENCE_IMMUTABLE' THEN RAISE; END IF;
  END;

  IF (SELECT fingerprint FROM r1d_e_b1_existing_business_before)
       IS DISTINCT FROM pg_temp.r1d_e_b1_existing_business_fingerprint() THEN
    RAISE EXCEPTION 'R1D_E_B1_EXISTING_BUSINESS_FINGERPRINT_CHANGED';
  END IF;
END
$verify$;

SELECT
  (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)
    AS legacy_planned_evidence_rows,
  (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence)
    AS snapshot_basis_evidence_rows,
  (SELECT count(*) FROM pg_trigger WHERE tgrelid IN (
    'public.school_legacy_planned_settlement_evidence'::regclass,
    'public.school_legacy_settlement_snapshot_basis_evidence'::regclass
  ) AND NOT tgisinternal AND tgenabled = 'O') AS immutable_trigger_count,
  true AS existing_business_unchanged;

\if :r1d_e_b1_commit
  COMMIT;
  \echo 'R1D_E_B1_DEPLOYMENT_COMMITTED'
\else
  ROLLBACK;
  \echo 'R1D_E_B1_REHEARSAL_ROLLED_BACK'
\endif
