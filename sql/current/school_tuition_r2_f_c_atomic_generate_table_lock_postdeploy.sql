-- R2-F-C read-only postdeploy verification.
\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_definition text;
  v_lesson_position integer;
  v_settlement_position integer;
  v_carryover_position integer;
  v_adjustment_position integer;
  v_candidate_position integer;
BEGIN
  SELECT proc_row.* INTO STRICT v_proc FROM pg_proc proc_row
  WHERE proc_row.oid=
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure;
  IF NOT v_proc.prosecdef
     OR v_proc.proowner<>(SELECT oid FROM pg_roles WHERE rolname='postgres')
     OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']::text[]
     OR has_function_privilege('anon',v_proc.oid,'EXECUTE')
     OR has_function_privilege('authenticated',v_proc.oid,'EXECUTE')
     OR has_function_privilege('service_role',v_proc.oid,'EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_C_CORE_METADATA_OR_ACL_INVALID';
  END IF;

  SELECT pg_get_functiondef(v_proc.oid) INTO STRICT v_definition;
  v_lesson_position:=position('LOCK TABLE public.school_lesson_records IN SHARE MODE' IN v_definition);
  v_settlement_position:=position('LOCK TABLE public.school_student_monthly_settlements IN SHARE MODE' IN v_definition);
  v_carryover_position:=position('LOCK TABLE public.school_student_settlement_carryovers IN SHARE MODE' IN v_definition);
  v_adjustment_position:=position('LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE' IN v_definition);
  v_candidate_position:=position('SELECT coalesce(array_agg(candidate.planned_lesson_id' IN v_definition);
  IF v_lesson_position=0 OR v_settlement_position<=v_lesson_position
     OR v_carryover_position<=v_settlement_position
     OR v_adjustment_position<=v_carryover_position
     OR v_candidate_position<=v_adjustment_position
     OR position($needle$set_config('lock_timeout','8s',true)$needle$ IN v_definition)=0
     OR position('R2_F_C_TUITION_SOURCE_BUSY' IN v_definition)=0
     OR position('existing atomic tuition generation returned idempotently' IN v_definition)=0
     OR position('R2_F_B_STALE_GENERATION_MANIFEST' IN v_definition)=0
     OR position('carryover_evidence_sha256' IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_C_CORE_LOCK_OR_R2_F_B_CONTRACT_MISSING';
  END IF;

  PERFORM 'public.school_lesson_records'::regclass;
  PERFORM 'public.school_student_monthly_settlements'::regclass;
  PERFORM 'public.school_student_settlement_carryovers'::regclass;
  PERFORM 'public.school_student_settlement_adjustment_drafts'::regclass;

  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_C_WRITER_CONTEXT_RESIDUE';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_C_R0_GATE_MISMATCH';
  END IF;
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
    RAISE EXCEPTION 'R2_F_C_BUSINESS_FINGERPRINT_DRIFT';
  END IF;
END
$fingerprint_assert$;

SELECT p.oid::regprocedure AS signature,r.rolname AS owner,p.prosecdef,
  p.proconfig,p.proacl,md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
WHERE p.oid=
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure;

SELECT c.oid::regclass AS table_name,c.relrowsecurity,c.relforcerowsecurity,c.relacl
FROM pg_class c
WHERE c.oid IN (
  'public.school_lesson_records'::regclass,
  'public.school_student_monthly_settlements'::regclass,
  'public.school_student_settlement_carryovers'::regclass,
  'public.school_student_settlement_adjustment_drafts'::regclass
)
ORDER BY c.oid::regclass::text;

SELECT feature_key,state FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
ORDER BY feature_key;

ROLLBACK;
\echo 'R2_F_C_POSTDEPLOY_READ_ONLY_PASS'
