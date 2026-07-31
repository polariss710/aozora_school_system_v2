-- R2-F-B read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_definition text;
  v_snapshot_definition text;
  v_validator_definition text;
  v_core_definition text;
  v_bill_id uuid;
  v_policy_count integer;
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_R0_GATE_MISMATCH';
  END IF;

  SELECT proc_row.* INTO STRICT v_proc FROM pg_proc proc_row
  WHERE proc_row.oid='public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure;
  IF NOT v_proc.prosecdef
     OR v_proc.proowner<>(SELECT oid FROM pg_roles WHERE rolname='postgres')
     OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']::text[]
     OR NOT has_function_privilege('authenticated',v_proc.oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_proc.oid,'EXECUTE')
     OR has_function_privilege('anon',v_proc.oid,'EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_PUBLIC_WRAPPER_METADATA_INVALID';
  END IF;

  IF has_function_privilege('anon',
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role',
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','EXECUTE')
     OR has_function_privilege('anon',
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','EXECUTE')
     OR has_function_privilege('service_role',
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_INTERNAL_FUNCTION_EXPOSED';
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_WRITER_CONTEXT_RESIDUE';
  END IF;
  IF has_table_privilege('anon','public.school_tuition_atomic_writer_context','SELECT')
     OR has_table_privilege('authenticated','public.school_tuition_atomic_writer_context','INSERT')
     OR has_table_privilege('service_role','public.school_tuition_atomic_writer_context','INSERT') THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_WRITER_CONTEXT_ACL_INVALID';
  END IF;

  IF has_table_privilege('anon','public.school_student_tuition_bills','INSERT')
     OR has_table_privilege('anon','public.school_student_tuition_bills','UPDATE')
     OR has_table_privilege('authenticated','public.school_student_tuition_bills','INSERT')
     OR has_table_privilege('authenticated','public.school_student_tuition_bills','UPDATE')
     OR has_table_privilege('service_role','public.school_student_tuition_bills','INSERT')
     OR has_table_privilege('service_role','public.school_student_tuition_bills','UPDATE')
     OR NOT has_table_privilege('authenticated','public.school_student_tuition_bills','SELECT') THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_BILL_ACL_INVALID';
  END IF;
  IF NOT has_table_privilege('authenticated','public.school_income_records','INSERT')
     OR NOT has_table_privilege('authenticated','public.school_income_records','UPDATE')
     OR NOT has_table_privilege('authenticated','public.school_income_records','SELECT') THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_ORDINARY_INCOME_PRIVILEGES_DAMAGED';
  END IF;

  SELECT count(*)::integer INTO v_policy_count FROM pg_policies
  WHERE schemaname='public' AND tablename='school_income_records'
    AND policyname IN (
      'school_select_operational_income_records',
      'school_insert_non_tuition_income_records',
      'school_update_non_tuition_income_records',
      'school_delete_non_tuition_income_records'
    );
  IF v_policy_count<>4 OR EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='school_income_records'
      AND policyname='school_allow_all_income_records'
  ) THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_INCOME_RLS_INVALID';
  END IF;

  SELECT pg_get_functiondef(
    'public.school_generate_student_tuition_bill(uuid,text,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('R0 does not provide an enabled generation path' IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_OLD_GENERATE_3ARG_REVIVED';
  END IF;
  SELECT pg_get_functiondef(
    'public.school_generate_student_tuition_bill(uuid,text,numeric,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('R0 does not provide an enabled generation path' IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_OLD_GENERATE_4ARG_REVIVED';
  END IF;
  SELECT pg_get_functiondef(
    'public.school_create_student_tuition_bill_income_record(uuid,date,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('R0 does not provide an enabled income-generation path' IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_OLD_CREATE_INCOME_REVIVED';
  END IF;
  SELECT pg_get_functiondef(
    'public.school_cancel_pending_income_record(uuid,text,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('TUITION_ATOMIC_CANCEL_FORBIDDEN' IN v_definition)=0
     OR position('legacy_tuition_cancel' IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_CANCEL_GUARD_MISSING';
  END IF;

  SELECT pg_get_functiondef(
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
  ) INTO STRICT v_snapshot_definition;
  SELECT pg_get_functiondef(
    'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure
  ) INTO STRICT v_validator_definition;
  SELECT pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
  ) INTO STRICT v_core_definition;
  IF position('canonical_lines AS' IN v_snapshot_definition)=0
     OR position('candidate_line_hash' IN v_snapshot_definition)=0
     OR position('complete_row_hash' IN v_snapshot_definition)=0
     OR position('source_lesson_updated_at' IN v_snapshot_definition)=0
     OR position('lesson_venue_code' IN v_snapshot_definition)=0
     OR position('string_agg(detail.candidate_line_hash' IN v_snapshot_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_MANIFEST_COVERAGE_MISSING';
  END IF;
  IF position($needle$)-'candidate_line_hash')::text$needle$ IN v_validator_definition)=0
     OR position($needle$rel.source_snapshot->>'complete_row_hash'$needle$ IN v_validator_definition)=0
     OR position($needle$rel.source_snapshot->>'candidate_line_hash'$needle$ IN v_validator_definition)=0
     OR position('v_recomputed_candidate_manifest' IN v_validator_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_RELATION_MANIFEST_VALIDATOR_MISSING';
  END IF;
  IF position('v_bill.billing_exchange_rate IS DISTINCT FROM p_billing_exchange_rate' IN v_core_definition)=0
     OR position($needle$v_income.source_snapshot->>'candidate_manifest_sha256'$needle$ IN v_core_definition)=0
     OR position($needle$v_bill.source_snapshot->>'candidate_manifest_sha256'$needle$ IN v_core_definition)=0
     OR position('carryover_evidence_sha256' IN v_core_definition)=0
     OR position($needle$(v_bill.source_snapshot->'carryover_evidence')::text$needle$ IN v_core_definition)=0
     OR position($needle$v_income.source_snapshot->>'previous_settlement_month'$needle$ IN v_core_definition)=0
     OR position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN v_core_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_IDEMPOTENCY_HARDENING_MISSING';
  END IF;

  FOR v_bill_id IN SELECT bill.id FROM public.school_student_tuition_bills bill
  LOOP
    PERFORM public.school_validate_tuition_identity_for_bill(v_bill_id);
    PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill_id);
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill_id);
  END LOOP;
END
$verify$;

WITH fingerprints AS (
  SELECT 'bills' object,count(*)::integer row_count,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) full_row_hash
  FROM public.school_student_tuition_bills t
  UNION ALL SELECT 'income',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_income_records t
  UNION ALL SELECT 'relations',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_tuition_bill_lessons t
  UNION ALL SELECT 'identities',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_tuition_billing_identities t
  UNION ALL SELECT 'settlements',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_monthly_settlements t
), expected(object,row_count,full_row_hash) AS (VALUES
  ('bills',9,'0f0323b79e7ff1c47ff6b90c75477a2d'),
  ('income',42,'2a4897b752f272b1f192045418b4940c'),
  ('relations',121,'285172fedeb923c67ea9a179480d8692'),
  ('identities',7,'4d91a5a1074f90389822fc367a7e5467'),
  ('settlements',15,'8d40d937d45c64eca0ec0ba7b1c5e65d')
)
SELECT fingerprints.*,
  fingerprints.row_count=expected.row_count
  AND fingerprints.full_row_hash=expected.full_row_hash AS baseline_unchanged
FROM fingerprints JOIN expected USING(object)
ORDER BY object;

DO $fingerprint_assert$
BEGIN
  IF (SELECT count(*) FROM (
    SELECT 1 FROM public.school_student_tuition_bills t
    HAVING count(*)=9 AND md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))='0f0323b79e7ff1c47ff6b90c75477a2d'
  ) x)<>1 OR
  (SELECT count(*) FROM (
    SELECT 1 FROM public.school_income_records t
    HAVING count(*)=42 AND md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))='2a4897b752f272b1f192045418b4940c'
  ) x)<>1 OR
  (SELECT count(*) FROM (
    SELECT 1 FROM public.school_student_tuition_bill_lessons t
    HAVING count(*)=121 AND md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))='285172fedeb923c67ea9a179480d8692'
  ) x)<>1 OR
  (SELECT count(*) FROM (
    SELECT 1 FROM public.school_student_tuition_billing_identities t
    HAVING count(*)=7 AND md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))='4d91a5a1074f90389822fc367a7e5467'
  ) x)<>1 OR
  (SELECT count(*) FROM (
    SELECT 1 FROM public.school_student_monthly_settlements t
    HAVING count(*)=15 AND md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))='8d40d937d45c64eca0ec0ba7b1c5e65d'
  ) x)<>1 THEN
    RAISE EXCEPTION 'R2_F_B_POSTDEPLOY_BUSINESS_FINGERPRINT_DRIFT';
  END IF;
END
$fingerprint_assert$;

SELECT p.oid::regprocedure AS signature,r.rolname AS owner,p.prosecdef,
  p.proconfig,p.proacl,md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
WHERE p.oid IN (
  'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure,
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure,
  'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,
  'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure,
  'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure,
  'public.school_cancel_pending_income_record(uuid,text,text)'::regprocedure
) ORDER BY p.oid::regprocedure::text;

SELECT feature_key,state FROM public.school_feature_gates
WHERE feature_key IN ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
ORDER BY feature_key;

ROLLBACK;
\echo 'R2_F_B_POSTDEPLOY_READ_ONLY_PASS'
