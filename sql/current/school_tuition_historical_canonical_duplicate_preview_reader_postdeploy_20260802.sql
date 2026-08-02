-- School V2 historical canonical duplicate-preview reader postdeploy.
-- SELECT-only. It does not call generate and writes no business data.
\set ON_ERROR_STOP on
\pset pager off

SELECT p.proname,
  md5(pg_get_functiondef(p.oid)) AS actual_md5,
  expected.expected_md5,
  md5(pg_get_functiondef(p.oid))=expected.expected_md5 AS matches_expected
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN (VALUES
  ('school_get_student_tuition_validation_preview_details','6c5f083d2151f43d48bcb3b7d0cc9dfe'),
  ('school_build_student_tuition_generation_snapshot','083bcb58c2b92f34ded07dceafbbbbfe'),
  ('school_generate_student_tuition_bill_atomic_core','b88f6d960d920c10b914fe8e58cf38cb'),
  ('school_generate_student_tuition_bill_atomic','36bdadc9af59637c9d336ce68d9afb4c'),
  ('school_list_student_tuition_charge_candidates','65e718ba8d2e4cb46ebb0dc84b11bc2e')
) expected(proname,expected_md5) ON expected.proname=p.proname
WHERE n.nspname='public'
  AND p.oid IN (
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure,
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure,
    'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure,
    'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
  )
ORDER BY p.proname;

SELECT
  position('''historical_backfill''' IN definition)>0 AS has_historical_branch,
  position('''atomic_charge''' IN definition)>0 AS has_atomic_branch,
  position('R2_F_B_ALREADY_BILLED' IN definition)>0 AS has_already_billed,
  position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' IN definition)>0 AS has_fail_closed,
  position('school_validate_tuition_identity_for_bill' IN definition)>0 AS has_identity_validator,
  position('school_validate_tuition_bill_income_for_bill' IN definition)>0 AS has_income_validator,
  position('school_validate_tuition_bill_lessons_for_bill' IN definition)>0 AS has_lesson_validator
FROM (
  SELECT pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  ) AS definition
) deployed;

SELECT feature_key,state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT 'school_income_records' AS table_name,count(*) AS row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) AS row_fingerprint,
  49::bigint AS expected_count,'76dfc996acdf1dca834d7b6cb75af8be'::text AS expected_fingerprint
FROM public.school_income_records t
UNION ALL
SELECT 'school_lesson_records',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')),
  706,'9b1644dbb1605164c5c3672106d6ba9f'
FROM public.school_lesson_records t
UNION ALL
SELECT 'school_student_tuition_bill_lessons',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')),
  236,'3d064537a43cc38392277f364c32f138'
FROM public.school_student_tuition_bill_lessons t
UNION ALL
SELECT 'school_student_tuition_billing_identities',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')),
  14,'dd6b170ed6eb60d72db72975dd197d4e'
FROM public.school_student_tuition_billing_identities t
UNION ALL
SELECT 'school_student_tuition_bills',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')),
  16,'66efdf2de6cf5ec906eb6879ccb2ae52'
FROM public.school_student_tuition_bills t
ORDER BY table_name;

SELECT i.id AS identity_id,i.student_id,s.name AS student_name,
  i.billing_month,i.source,i.canonical_bill_id,b.income_record_id,
  b.status AS bill_status,income.status AS income_status,
  b.cancelled_at,b.incident_locked_at,
  income.cancelled_at AS income_cancelled_at,
  income.reversed_at AS income_reversed_at,
  income.incident_type,income.operational_excluded
FROM public.school_student_tuition_billing_identities i
JOIN public.school_students s ON s.id=i.student_id
LEFT JOIN public.school_student_tuition_bills b ON b.id=i.canonical_bill_id
LEFT JOIN public.school_income_records income ON income.id=b.income_record_id
WHERE i.billing_month='2026-08'
ORDER BY i.source,s.name;

SELECT
  (SELECT count(*) FROM public.school_students
   WHERE id::text LIKE 'f2fe0000-0000-4000-8000-00000000a00%') AS fixture_students,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE note='codex-test historical canonical preview reader') AS fixture_lessons,
  (SELECT count(*) FROM public.school_tuition_atomic_writer_context) AS writer_context_rows;
