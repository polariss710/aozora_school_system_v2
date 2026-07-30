-- School V2 tuition P0 R1D-E-B1 postdeploy read-only verification.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '120s';

DO $postdeploy$
DECLARE
  v_planned_manifest text;
  v_snapshot_manifest text;
  v_group record;
BEGIN
  IF to_regclass('public.school_legacy_planned_settlement_evidence') IS NULL
     OR to_regclass('public.school_legacy_settlement_snapshot_basis_evidence') IS NULL
     OR to_regprocedure('public.school_guard_r1d_e_b1_legacy_evidence_immutable()') IS NULL
     OR to_regprocedure('public.school_get_legacy_planned_student_settlement_month(uuid)') IS NULL
     OR to_regprocedure('public.school_is_legacy_settlement_snapshot_basis(uuid)') IS NULL THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_OBJECT_MISSING';
  END IF;

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
     OR (SELECT count(DISTINCT planned_lesson_id)
         FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR v_planned_manifest <> '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR (SELECT count(DISTINCT settlement_snapshot_id)
         FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR v_snapshot_manifest <> '68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_MANIFEST_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_legacy_planned_settlement_evidence evidence
    JOIN public.school_lesson_records lesson ON lesson.id = evidence.planned_lesson_id
    WHERE evidence.student_id_snapshot IS DISTINCT FROM lesson.student_id
       OR evidence.business_entity_id_snapshot IS DISTINCT FROM lesson.business_entity_id
       OR evidence.legacy_student_settlement_month IS DISTINCT FROM lesson.year_month
       OR evidence.lesson_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
            lesson.id::text, coalesce(lesson.student_id::text, '<NULL>'),
            coalesce(lesson.business_entity_id::text, '<NULL>'),
            coalesce(lesson.year_month, '<NULL>'), lesson.lesson_type, lesson.app_type))
       OR evidence.approved_manifest IS DISTINCT FROM true
       OR evidence.evidence_source IS DISTINCT FROM 'r1d_e_b1_fixed_legacy_279'
       OR evidence.evidence_version IS DISTINCT FROM 'legacy_settlement_evidence_v1'
  ) THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_PLANNED_ROW_DRIFT';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_legacy_planned_settlement_evidence') <> 9
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_legacy_settlement_snapshot_basis_evidence') <> 14
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid IN (
           'public.school_legacy_planned_settlement_evidence'::regclass,
           'public.school_legacy_settlement_snapshot_basis_evidence'::regclass
         ) AND NOT tgisinternal AND tgenabled = 'O') <> 4
     OR NOT (SELECT bool_and(c.relrowsecurity)
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relname IN (
               'school_legacy_planned_settlement_evidence',
               'school_legacy_settlement_snapshot_basis_evidence')) THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_SCHEMA_FAILED';
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
     OR NOT has_function_privilege('service_role',
       'public.school_get_legacy_planned_student_settlement_month(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.school_is_legacy_settlement_snapshot_basis(uuid)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.school_get_legacy_planned_student_settlement_month(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_is_legacy_settlement_snapshot_basis(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_PRIVILEGE_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.oid IN (
        'public.school_get_legacy_planned_student_settlement_month(uuid)'::regprocedure,
        'public.school_is_legacy_settlement_snapshot_basis(uuid)'::regprocedure
      )
      AND (p.prosecdef OR p.provolatile <> 's'
        OR NOT coalesce(p.proconfig @> ARRAY['search_path=pg_catalog, public'], false))
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'public.school_guard_r1d_e_b1_legacy_evidence_immutable()'::regprocedure
      AND (NOT p.prosecdef
        OR NOT coalesce(p.proconfig @> ARRAY['search_path=pg_catalog'], false))
  ) THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_FUNCTION_SECURITY_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_R0_OR_CANDIDATE_CHANGED';
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
          billing_month_decided_at) BETWEEN 1 AND 4) <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE app_type = 'school' AND lesson_type = 'actual'
           AND created_at <= TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND student_settlement_month IS NULL) <> 233 THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_LESSON_BOUNDARY_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_student_monthly_settlements
      WHERE settlement_status = 'locked') <> 15
     OR (SELECT md5(string_agg(md5(to_jsonb(s)::text), ',' ORDER BY id::text))
         FROM public.school_student_monthly_settlements s
         WHERE settlement_status = 'locked')
        <> '51fd3d3759b432c4b214e0eb5038e616'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(student_duration_overage_minutes,
           student_duration_overage_fee_jpy,
           student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at) > 0) <> 0 THEN
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_SETTLEMENT_OR_OVERAGE_CHANGED';
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
    RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_FINANCIAL_CHAIN_CHANGED';
  END IF;

  FOR v_group IN
    WITH groups(group_name, names, expected_count, expected_md5) AS (
      VALUES
        ('actual_writer', ARRAY[
          'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
          'school_create_partial_completed_actual_from_planned','school_create_lesson_credit_makeup_actual',
          'school_create_makeup_completed_actual_lesson_from_planned',
          'school_create_cross_month_makeup_completed_actual_from_planned',
          'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue'
        ]::text[], 8::bigint, '4986090e0ba4e4706ea9ca4abd9580c5'),
        ('planned_writer', ARRAY[
          'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
          'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
          'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
          'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue'
        ]::text[], 8::bigint, 'a3925ad6065af7900adaf4b3420df0c2'),
        ('settlement_reader_writer', ARRAY[
          'school_get_student_monthly_settlement_summary','school_get_student_monthly_settlement_preview',
          'school_get_student_monthly_settlement_wage_blockers',
          'school_assert_student_monthly_settlement_no_wage_blocker',
          'school_lock_student_monthly_settlement','school_unlock_student_monthly_settlement',
          'school_relock_student_monthly_settlement',
          'school_set_student_monthly_settlement_draft_adjustment'
        ]::text[], 8::bigint, 'b17b31a3dc1797159556032abdb04ac3')
    ), functions AS (
      SELECT p.proname, p.oid::regprocedure::text AS signature,
             md5(pg_get_functiondef(p.oid)) AS definition_md5,
             coalesce(p.proacl::text, '<NULL>') AS acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
    )
    SELECT g.group_name, g.expected_count, g.expected_md5,
           count(f.signature) AS actual_count,
           md5(string_agg(concat_ws('|', f.signature, f.definition_md5, f.acl),
             E'\n' ORDER BY f.signature)) AS actual_md5
    FROM groups g LEFT JOIN functions f ON f.proname = ANY(g.names)
    GROUP BY g.group_name, g.expected_count, g.expected_md5
  LOOP
    IF v_group.actual_count <> v_group.expected_count
       OR v_group.actual_md5 <> v_group.expected_md5 THEN
      RAISE EXCEPTION 'R1D_E_B1_POSTDEPLOY_FUNCTION_GROUP_CHANGED: %', v_group.group_name;
    END IF;
  END LOOP;
END
$postdeploy$;

SELECT
  (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)
    AS legacy_planned_evidence_rows,
  (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence)
    AS snapshot_basis_evidence_rows,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE lesson_type = 'actual') AS actual_rows_disclosed,
  true AS r0_candidate_writers_readers_financial_chain_unchanged,
  true AS postdeploy_pass;

ROLLBACK;
