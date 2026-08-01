-- Read-only history fingerprints. School-side Cash linkage only; Cash DB is not connected.
\set ON_ERROR_STOP on
\pset pager off

SELECT clock_timestamp() AS fingerprint_at_utc;
SELECT object_name,row_count,row_hash FROM (
  SELECT 'lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) row_hash FROM public.school_lesson_records x
  UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
  UNION ALL SELECT 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
  UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
  UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
  UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
  UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
  UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
  UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
  UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
  UNION ALL SELECT 'planned_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),'')) FROM public.school_legacy_planned_settlement_evidence x
  UNION ALL SELECT 'actual_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),'')) FROM public.school_legacy_actual_settlement_evidence x
  UNION ALL SELECT 'historical_exclusions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_historical_lesson_exclusions x
) fingerprint
ORDER BY object_name;

SELECT p.oid::regprocedure::text AS function_signature,
       md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p
WHERE p.oid IN (
  'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,
  'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure,
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure,
  'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
)
ORDER BY function_signature;
