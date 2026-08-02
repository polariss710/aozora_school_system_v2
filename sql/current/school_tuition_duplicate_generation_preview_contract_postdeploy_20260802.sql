-- Read-only postdeploy acceptance for the duplicate-generation preview contract.
\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout='240s';

DO $assert_contract$
DECLARE
  v_definition text;
  v_real_checked integer := 0;
  v_row record;
BEGIN
  v_definition:=pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  );
  IF md5(v_definition)<>'c90ce637c055b7322f278d89ff9fbed6'
     OR position('R2_F_B_ALREADY_BILLED' IN v_definition)=0
     OR position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN v_definition)=0
     OR position('school_validate_tuition_identity_for_bill' IN v_definition)=0
     OR position('school_validate_tuition_bill_income_for_bill' IN v_definition)=0
     OR position('school_validate_tuition_bill_lessons_for_bill' IN v_definition)=0
     OR position('R2_F_B_ALREADY_BILLED' IN v_definition)>
        position('school_build_student_tuition_generation_snapshot' IN v_definition) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_DEPLOYED_CONTRACT_FAILED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'65e718ba8d2e4cb46ebb0dc84b11bc2e' THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_PROTECTED_FUNCTION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_GATE_FAILED';
  END IF;

  FOR v_row IN
    SELECT identity_row.student_id,identity_row.billing_month,
      bill.billing_exchange_rate
    FROM public.school_student_tuition_billing_identities identity_row
    JOIN public.school_student_tuition_bills bill
      ON bill.id=identity_row.canonical_bill_id
    WHERE identity_row.source='atomic_charge'
      AND identity_row.evidence->>'generation_source'
          ='student_tuition_atomic_generate_v1'
    ORDER BY identity_row.student_id,identity_row.billing_month
  LOOP
    BEGIN
      PERFORM *
      FROM public.school_get_student_tuition_validation_preview_details(
        v_row.student_id,v_row.billing_month,v_row.billing_exchange_rate
      );
      RAISE EXCEPTION 'EXPECTED_REAL_ALREADY_BILLED_MISSING';
    EXCEPTION WHEN OTHERS THEN
      IF position('R2_F_B_ALREADY_BILLED' IN SQLERRM)=0 THEN RAISE; END IF;
    END;
    v_real_checked:=v_real_checked+1;
  END LOOP;
  IF v_real_checked<>7 THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_REAL_IDENTITY_COUNT_FAILED:%',v_real_checked;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_students
    WHERE id::text LIKE 'f2fd0000-0000-4000-8000-00000000a00%'
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE note='codex-test duplicate preview contract'
  ) OR EXISTS (
    SELECT 1 FROM public.school_tuition_atomic_writer_context
  ) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_FIXTURE_RESIDUE';
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
     ) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_EXECUTE_ACL_FAILED';
  END IF;

  RAISE NOTICE 'TUITION_DUPLICATE_PREVIEW_REAL_ALREADY_BILLED_CHECKED=%',v_real_checked;
END
$assert_contract$;

DO $assert_business_fingerprints$
BEGIN
  IF (SELECT count(*)<>236
        OR md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
             <>'92e869986eef9124b7ac7603d6429c4b'
      FROM public.school_student_tuition_bill_lessons x)
     OR (SELECT count(*)<>14
        OR md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
             <>'de90fc39ad1e17758c6ca95f7c882a46'
      FROM public.school_student_tuition_billing_identities x)
     OR (SELECT count(*)<>49
        OR md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
             <>'682bc8fd2b13fbf58878f349e7c91a41'
      FROM public.school_income_records x)
     OR (SELECT count(*)<>706
        OR md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
             <>'d1461edbc3b4e86a87dd59223e914ae3'
      FROM public.school_lesson_records x)
     OR (SELECT count(*)<>16
        OR md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
             <>'c8b3f17f4381148e26433817fa214ab8'
      FROM public.school_student_tuition_bills x) THEN
    RAISE EXCEPTION 'TUITION_DUPLICATE_PREVIEW_BUSINESS_FINGERPRINT_DRIFT';
  END IF;
END
$assert_business_fingerprints$;

SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,
  md5(pg_get_functiondef(p.oid)) AS function_md5,
  p.provolatile,p.prosecdef
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
  'school_get_student_tuition_validation_preview_details',
  'school_build_student_tuition_generation_snapshot',
  'school_generate_student_tuition_bill_atomic_core',
  'school_generate_student_tuition_bill_atomic',
  'school_list_student_tuition_charge_candidates'
)
ORDER BY p.proname;

SELECT feature_key,state,release_version,evidence_hash
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT 'bill_relations' AS object,count(*) AS row_count,
  md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text) AS row_hash
FROM public.school_student_tuition_bill_lessons x
UNION ALL
SELECT 'billing_identities',count(*),
  md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
FROM public.school_student_tuition_billing_identities x
UNION ALL
SELECT 'income_records',count(*),
  md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
FROM public.school_income_records x
UNION ALL
SELECT 'lesson_records',count(*),
  md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
FROM public.school_lesson_records x
UNION ALL
SELECT 'tuition_bills',count(*),
  md5(jsonb_agg(to_jsonb(x) ORDER BY x.id::text)::text)
FROM public.school_student_tuition_bills x
ORDER BY object;

ROLLBACK;
\echo 'TUITION_DUPLICATE_PREVIEW_POSTDEPLOY_PASS_READ_ONLY'
