-- Retire the one-time fixed64 insert authority after successful phase 1 postdeploy.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;

DO $retire_preflight$
BEGIN
  IF to_regprocedure('public.school_20260802_fixed_64_already_charged_manifest()') IS NULL
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>106
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1')<>64 THEN
    RAISE EXCEPTION 'FIXED64_RETIRE_PREFLIGHT_FAILED';
  END IF;
END
$retire_preflight$;

CREATE TEMP TABLE fixed64_retire_before (
  object_name text PRIMARY KEY,row_count bigint NOT NULL,row_hash text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixed64_retire_before(object_name,row_count,row_hash)
SELECT 'lesson_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_lesson_records x
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'historical_exclusions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_historical_lesson_exclusions x
UNION ALL SELECT 'candidate_reader',1,md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure));

CREATE OR REPLACE FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION 'TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED';
END
$function$;

COMMENT ON FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert() IS
  'Retired historical exclusion writer. All future INSERT attempts are rejected; immutable approved rows remain the sole reader authority.';
REVOKE ALL ON FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert()
  FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION public.school_20260802_fixed_64_already_charged_manifest();

CREATE TEMP TABLE fixed64_retire_after (
  object_name text PRIMARY KEY,row_count bigint NOT NULL,row_hash text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixed64_retire_after(object_name,row_count,row_hash)
SELECT 'lesson_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_lesson_records x
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'historical_exclusions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_historical_lesson_exclusions x
UNION ALL SELECT 'candidate_reader',1,md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure));

DO $retire_verify$
BEGIN
  IF to_regprocedure('public.school_20260802_fixed_64_already_charged_manifest()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM fixed64_retire_before before_row
       FULL JOIN fixed64_retire_after after_row USING(object_name)
       WHERE before_row.object_name IS NULL OR after_row.object_name IS NULL
          OR before_row.row_count IS DISTINCT FROM after_row.row_count
          OR before_row.row_hash IS DISTINCT FROM after_row.row_hash
     )
     OR position('TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED' IN
        pg_get_functiondef('public.school_guard_tuition_historical_lesson_exclusion_insert()'::regprocedure))=0
     OR position('school_20260802_fixed_64_already_charged_manifest' IN
        pg_get_functiondef('public.school_guard_tuition_historical_lesson_exclusion_insert()'::regprocedure))>0 THEN
    RAISE EXCEPTION 'FIXED64_RETIRE_VERIFY_FAILED';
  END IF;
END
$retire_verify$;

COMMIT;
