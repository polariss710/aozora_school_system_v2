-- Phase 1 postdeploy: fixed64 rows committed, temporary manifest/guard still present.
\set ON_ERROR_STOP on
\pset pager off

DO $phase1$
DECLARE
  v_count bigint;
  v_hash text;
  v_reader text;
BEGIN
  IF to_regprocedure('public.school_20260802_fixed_64_already_charged_manifest()') IS NULL THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_MANIFEST_MISSING';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name='school_student_tuition_historical_lesson_exclusions'
        AND ((column_name='evidence_profile_code' AND is_nullable='NO' AND data_type='text')
          OR (column_name='lesson_complete_row_hash' AND is_nullable='YES' AND data_type='text')
          OR (column_name='external_evidence_snapshot' AND is_nullable='NO' AND data_type='jsonb')
          OR (column_name='external_evidence_sha256' AND is_nullable='YES' AND data_type='text')))<>4 THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_COLUMN_CONTRACT_DRIFT';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name='school_student_tuition_historical_lesson_exclusions'
        AND column_name IN ('locked_settlement_id','received_tuition_income_id','school_account_transaction_id')
        AND is_nullable='YES')<>3 THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_NULLABILITY_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>106
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
           AND locked_settlement_id IS NOT NULL AND received_tuition_income_id IS NOT NULL
           AND school_account_transaction_id IS NOT NULL
           AND lesson_complete_row_hash IS NULL AND external_evidence_snapshot='{}'::jsonb
           AND external_evidence_sha256 IS NULL)<>42
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='CASH_MANUAL_INCOME_MATCHED_V1')<>22
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1')<>8
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1')<>34 THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_PROFILE_COUNT_DRIFT';
  END IF;

  SELECT count(*),encode(digest(string_agg(planned_lesson_id::text,'|' ORDER BY planned_lesson_id::text),'sha256'),'hex')
  INTO v_count,v_hash
  FROM public.school_20260802_fixed_64_already_charged_manifest();
  IF v_count<>64 OR v_hash<>'7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85' THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_MANIFEST_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
    LEFT JOIN public.school_student_tuition_historical_lesson_exclusions exclusion
      ON exclusion.planned_lesson_id=manifest.planned_lesson_id
    WHERE exclusion.id IS NULL
       OR exclusion.evidence_hash IS DISTINCT FROM manifest.expected_evidence_hash
       OR exclusion.external_evidence_sha256 IS DISTINCT FROM manifest.expected_external_evidence_sha256
       OR exclusion.external_evidence_sha256<>encode(digest(
          convert_to(exclusion.external_evidence_snapshot::text,'UTF8'),'sha256'),'hex')
  ) THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_ROW_OR_HASH_DRIFT';
  END IF;

  WITH scopes AS (
    SELECT DISTINCT expected_student_id student_id,expected_business_entity_id entity_id,expected_billing_month billing_month
    FROM public.school_20260802_fixed_64_already_charged_manifest()
  ), included AS (
    SELECT c.*
    FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(s.student_id,s.entity_id,s.billing_month,true) c
    JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
      ON manifest.planned_lesson_id=c.planned_lesson_id
  ), leaked AS (
    SELECT c.*
    FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(s.student_id,s.entity_id,s.billing_month,false) c
    JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
      ON manifest.planned_lesson_id=c.planned_lesson_id
  )
  SELECT count(*) INTO v_count FROM included
  WHERE candidate_status='excluded' AND exclusion_reason='historical_paid_exclusion';
  IF v_count<>64 OR EXISTS (
    WITH scopes AS (
      SELECT DISTINCT expected_student_id student_id,expected_business_entity_id entity_id,expected_billing_month billing_month
      FROM public.school_20260802_fixed_64_already_charged_manifest()
    )
    SELECT 1 FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(s.student_id,s.entity_id,s.billing_month,false) c
    JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
      ON manifest.planned_lesson_id=c.planned_lesson_id
  ) THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_CANDIDATE_FAILURE';
  END IF;

  v_reader:=pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure);
  IF position('school_student_tuition_historical_lesson_exclusions' IN v_reader)=0
     OR position('external_evidence_snapshot' IN v_reader)>0
     OR position('lesson_complete_row_hash' IN v_reader)>0 THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_READER_AUTHORITY_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_GATE_DRIFT';
  END IF;

  IF has_table_privilege('anon','public.school_student_tuition_historical_lesson_exclusions','SELECT')
     OR has_table_privilege('authenticated','public.school_student_tuition_historical_lesson_exclusions','SELECT')
     OR has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     OR has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','UPDATE')
     OR has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','DELETE')
     OR NOT has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','SELECT') THEN
    RAISE EXCEPTION 'FIXED64_PHASE1_ACL_DRIFT';
  END IF;
END
$phase1$;

SELECT evidence_profile_code,count(*) row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) full_row_hash
FROM public.school_student_tuition_historical_lesson_exclusions x
GROUP BY evidence_profile_code ORDER BY evidence_profile_code;

SELECT 'planned_lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) row_hash
FROM public.school_lesson_records x WHERE lesson_type='planned'
UNION ALL SELECT 'actual_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_lesson_records x WHERE lesson_type='actual'
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_income_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) FROM public.school_personal_cash_income_linkage_events x
ORDER BY object_name;

SELECT md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)) candidate_reader_md5,
       md5(pg_get_functiondef('public.school_guard_tuition_historical_lesson_exclusion_insert()'::regprocedure)) temporary_guard_md5,
       md5(pg_get_functiondef('public.school_20260802_fixed_64_already_charged_manifest()'::regprocedure)) manifest_function_md5;
