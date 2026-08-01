-- School V2 fixed 64 historical-paid planned exclusion migration core.
-- Transaction control is intentionally owned by the rehearsal/formal wrappers.
-- The identical bytes in this file are used for ROLLBACK rehearsal and COMMIT deployment.
\set ON_ERROR_STOP on

DO $predeploy_contract$
BEGIN
  IF to_regclass('public.school_student_tuition_historical_lesson_exclusions') IS NULL
     OR to_regprocedure('public.school_r1d_c_c_b_fixed_42_manifest()') IS NULL
     OR to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_insert()') IS NULL
     OR to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_immutable()') IS NULL
     OR to_regprocedure('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)') IS NULL THEN
    RAISE EXCEPTION 'FIXED64_REQUIRED_OBJECT_MISSING';
  END IF;

  IF to_regprocedure('public.school_20260802_fixed_64_already_charged_manifest()') IS NOT NULL THEN
    RAISE EXCEPTION 'FIXED64_MANIFEST_ALREADY_EXISTS';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42 THEN
    RAISE EXCEPTION 'FIXED64_EXPECTED_OLD42_COUNT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='school_student_tuition_historical_lesson_exclusions'
      AND column_name IN (
        'evidence_profile_code','lesson_complete_row_hash',
        'external_evidence_snapshot','external_evidence_sha256'
      )
  ) THEN
    RAISE EXCEPTION 'FIXED64_SCHEMA_ALREADY_PARTIALLY_DEPLOYED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked')) <> 3 THEN
    RAISE EXCEPTION 'FIXED64_GATE_DRIFT';
  END IF;

  IF position(
       'school_student_tuition_historical_lesson_exclusions' IN
       pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)
     ) = 0 THEN
    RAISE EXCEPTION 'FIXED64_CANDIDATE_READER_AUTHORITY_DRIFT';
  END IF;
END
$predeploy_contract$;

CREATE TEMP TABLE fixed64_before_fingerprints (
  object_name text PRIMARY KEY,
  row_count bigint NOT NULL,
  row_hash text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixed64_before_fingerprints(object_name,row_count,row_hash)
SELECT 'planned_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_lesson_records x WHERE x.lesson_type='planned'
UNION ALL SELECT 'actual_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_lesson_records x WHERE x.lesson_type='actual'
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_income_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'old42_business_fields',count(*),md5(coalesce(string_agg(md5((to_jsonb(x)-ARRAY[
      'evidence_profile_code','lesson_complete_row_hash','external_evidence_snapshot','external_evidence_sha256'
    ]::text[])::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_historical_lesson_exclusions x
UNION ALL SELECT 'candidate_reader',1,md5(pg_get_functiondef(
  'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
));

WITH scopes AS (
  SELECT DISTINCT student_id,business_entity_id,billing_month
  FROM public.school_lesson_records
  WHERE lesson_type='planned'
    AND student_id IS NOT NULL
    AND business_entity_id IS NOT NULL
    AND billing_month IS NOT NULL
    AND NOT (
      business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
      AND student_id IN (
        'cff85c52-6acc-4b0f-8c92-3db280a5dd77'::uuid,
        'eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,
        'a7b163a0-201e-4867-9b94-372343356a80'::uuid
      )
      AND billing_month IN ('2026-05','2026-06')
    )
), candidate_rows AS (
  SELECT c.*
  FROM scopes s
  CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
    s.student_id,s.business_entity_id,s.billing_month,false
  ) c
)
INSERT INTO fixed64_before_fingerprints(object_name,row_count,row_hash)
SELECT 'other_candidate_rows',count(*),md5(coalesce(string_agg(md5(to_jsonb(candidate_rows)::text),'' ORDER BY planned_lesson_id::text),''))
FROM candidate_rows;

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  ADD COLUMN evidence_profile_code text NOT NULL
    DEFAULT 'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1',
  ADD COLUMN lesson_complete_row_hash text NULL,
  ADD COLUMN external_evidence_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN external_evidence_sha256 text NULL;

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  ALTER COLUMN locked_settlement_id DROP NOT NULL,
  ALTER COLUMN received_tuition_income_id DROP NOT NULL,
  ALTER COLUMN school_account_transaction_id DROP NOT NULL;

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  DROP CONSTRAINT school_tuition_historical_exclusion_class_chk,
  DROP CONSTRAINT school_tuition_historical_exclusion_source_chk,
  DROP CONSTRAINT school_tuition_historical_exclusion_report_chk,
  DROP CONSTRAINT school_tuition_historical_exclusion_manifest_chk;

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  ADD CONSTRAINT school_tuition_historical_exclusion_profile_chk CHECK (
    evidence_profile_code IN (
      'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1',
      'CASH_MANUAL_INCOME_MATCHED_V1',
      'CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1',
      'SCHOOL_INCOME_CASH_SYNC_V1'
    )
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_profile_evidence_chk CHECK (
    (
      evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND locked_settlement_id IS NOT NULL
      AND received_tuition_income_id IS NOT NULL
      AND school_account_transaction_id IS NOT NULL
      AND lesson_complete_row_hash IS NULL
      AND external_evidence_snapshot='{}'::jsonb
      AND external_evidence_sha256 IS NULL
    ) OR (
      evidence_profile_code IN (
        'CASH_MANUAL_INCOME_MATCHED_V1',
        'CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1',
        'SCHOOL_INCOME_CASH_SYNC_V1'
      )
      AND locked_settlement_id IS NULL
      AND received_tuition_income_id IS NULL
      AND school_account_transaction_id IS NULL
      AND lesson_complete_row_hash ~ '^[0-9a-f]{32}$'
      AND jsonb_typeof(external_evidence_snapshot)='object'
      AND external_evidence_snapshot<>'{}'::jsonb
      AND external_evidence_sha256 ~ '^[0-9a-f]{64}$'
    )
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_class_chk CHECK (
    (evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND evidence_class_code='business_approved_reviewable_medium')
    OR
    (evidence_profile_code<>'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND evidence_class_code='business_owner_final_confirmed')
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_source_chk CHECK (
    (evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND approval_source_code='approved_r1d_c_c_a_manifest')
    OR
    (evidence_profile_code<>'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND approval_source_code='approved_20260802_64_already_charged_manifest')
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_report_chk CHECK (
    (evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND approval_report_version='school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1')
    OR
    (evidence_profile_code<>'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND approval_report_version='school-v2-2026-05-06-64-already-charged-final-review-20260802-v1')
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_manifest_chk CHECK (
    (evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND manifest_version='school-v2-r1d-c-c-a-current-only-42-20260728-v1')
    OR
    (evidence_profile_code<>'SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
      AND manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1')
  ),
  ADD CONSTRAINT school_tuition_historical_exclusion_external_hash_chk CHECK (
    external_evidence_sha256 IS NULL
    OR external_evidence_sha256=encode(
      digest(convert_to(external_evidence_snapshot::text,'UTF8'),'sha256'),'hex'
    )
  );

COMMENT ON COLUMN public.school_student_tuition_historical_lesson_exclusions.evidence_profile_code IS
  'Explicit evidence contract. It is never inferred from NULLs; only the four business-approved historical profiles are valid.';
COMMENT ON COLUMN public.school_student_tuition_historical_lesson_exclusions.lesson_complete_row_hash IS
  'Migration-time complete planned row fingerprint for historical audit only. Runtime readers must not recompute it to decide exclusion eligibility.';
COMMENT ON COLUMN public.school_student_tuition_historical_lesson_exclusions.external_evidence_snapshot IS
  'Immutable School/Cash/business-approval evidence snapshot. It is not a payment ledger, amount authority, writer, or runtime reader input.';
COMMENT ON COLUMN public.school_student_tuition_historical_lesson_exclusions.external_evidence_sha256 IS
  'SHA-256 of PostgreSQL canonical jsonb text for external_evidence_snapshot; insert-time anti-forgery and later audit only.';

\ir school_tuition_2026_05_06_fixed_64_already_charged_manifest.sql

CREATE OR REPLACE FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
BEGIN
  IF new.evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.school_r1d_c_c_b_fixed_42_manifest() manifest
      WHERE manifest.planned_lesson_id=new.planned_lesson_id
        AND manifest.expected_old31_hash=new.lesson_old31_hash
        AND manifest.expected_student_id=new.student_id_snapshot
        AND manifest.expected_business_entity_id=new.business_entity_id_snapshot
        AND manifest.expected_year_month=new.settlement_month_snapshot
        AND manifest.expected_actual_lesson_id=new.linked_actual_lesson_id
        AND manifest.expected_settlement_id=new.locked_settlement_id
        AND manifest.expected_income_id=new.received_tuition_income_id
        AND manifest.expected_account_transaction_id=new.school_account_transaction_id
        AND manifest.expected_evidence_hash=new.evidence_hash
        AND new.lesson_complete_row_hash IS NULL
        AND new.external_evidence_snapshot='{}'::jsonb
        AND new.external_evidence_sha256 IS NULL
        AND new.evidence_class_code='business_approved_reviewable_medium'
        AND new.approval_source_code='approved_r1d_c_c_a_manifest'
        AND new.approval_report_version='school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1'
        AND new.manifest_version='school-v2-r1d-c-c-a-current-only-42-20260728-v1'
    ) THEN
      RAISE EXCEPTION 'FIXED64_OLD42_MANIFEST_ROW_REJECTED: lesson %',new.planned_lesson_id;
    END IF;
  ELSIF new.evidence_profile_code IN (
    'CASH_MANUAL_INCOME_MATCHED_V1',
    'CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1',
    'SCHOOL_INCOME_CASH_SYNC_V1'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
      WHERE manifest.planned_lesson_id=new.planned_lesson_id
        AND manifest.expected_student_id=new.student_id_snapshot
        AND manifest.expected_business_entity_id=new.business_entity_id_snapshot
        AND manifest.expected_billing_month=new.settlement_month_snapshot
        AND manifest.expected_actual_lesson_id=new.linked_actual_lesson_id
        AND manifest.expected_old31_hash=new.lesson_old31_hash
        AND manifest.expected_complete_row_hash=new.lesson_complete_row_hash
        AND manifest.evidence_profile_code=new.evidence_profile_code
        AND manifest.normalized_note=new.approval_summary
        AND manifest.expected_external_evidence_snapshot=new.external_evidence_snapshot
        AND manifest.expected_external_evidence_sha256=new.external_evidence_sha256
        AND manifest.expected_evidence_hash=new.evidence_hash
        AND manifest.evidence_recorded_at=new.evidence_recorded_at
        AND new.locked_settlement_id IS NULL
        AND new.received_tuition_income_id IS NULL
        AND new.school_account_transaction_id IS NULL
        AND new.exclusion_reason_code='historical_monthly_tuition_paid'
        AND new.evidence_class_code='business_owner_final_confirmed'
        AND new.approval_source_code='approved_20260802_64_already_charged_manifest'
        AND new.approval_report_version='school-v2-2026-05-06-64-already-charged-final-review-20260802-v1'
        AND new.manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1'
    ) THEN
      RAISE EXCEPTION 'FIXED64_NEW64_MANIFEST_ROW_REJECTED: lesson %',new.planned_lesson_id;
    END IF;
  ELSE
    RAISE EXCEPTION 'FIXED64_EVIDENCE_PROFILE_REJECTED: %',new.evidence_profile_code;
  END IF;
  RETURN new;
END
$function$;

COMMENT ON FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert() IS
  'Temporary fixed64 deployment guard. Old42 rows only match the old42 manifest; new64 rows only match the approved 20260802 fixed64 manifest. This writer must be retired after postdeploy.';
REVOKE ALL ON FUNCTION public.school_guard_tuition_historical_lesson_exclusion_insert()
  FROM PUBLIC,anon,authenticated,service_role;

DO $manifest_preflight$
DECLARE
  v_count bigint;
  v_hash text;
BEGIN
  SELECT count(*),encode(digest(string_agg(planned_lesson_id::text,'|' ORDER BY planned_lesson_id::text),'sha256'),'hex')
  INTO v_count,v_hash
  FROM public.school_20260802_fixed_64_already_charged_manifest();
  IF v_count<>64 OR v_hash<>'7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85' THEN
    RAISE EXCEPTION 'FIXED64_MANIFEST_ID_SET_DRIFT: count %, hash %',v_count,v_hash;
  END IF;

  IF (SELECT count(*) FROM public.school_20260802_fixed_64_already_charged_manifest()
      WHERE evidence_profile_code='CASH_MANUAL_INCOME_MATCHED_V1')<>22
     OR (SELECT count(*) FROM public.school_20260802_fixed_64_already_charged_manifest()
      WHERE evidence_profile_code='CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1')<>8
     OR (SELECT count(*) FROM public.school_20260802_fixed_64_already_charged_manifest()
      WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1')<>34 THEN
    RAISE EXCEPTION 'FIXED64_MANIFEST_PROFILE_DISTRIBUTION_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
    JOIN public.school_lesson_records lesson ON lesson.id=manifest.planned_lesson_id
    LEFT JOIN public.school_lesson_records actual ON actual.id=manifest.expected_actual_lesson_id
    WHERE lesson.lesson_type<>'planned'
       OR lesson.student_id IS DISTINCT FROM manifest.expected_student_id
       OR lesson.business_entity_id IS DISTINCT FROM manifest.expected_business_entity_id
       OR lesson.billing_month IS DISTINCT FROM manifest.expected_billing_month
       OR lesson.billing_week_start_date IS DISTINCT FROM manifest.expected_billing_week_start_date
       OR md5(to_jsonb(lesson)::text) IS DISTINCT FROM manifest.expected_complete_row_hash
       OR md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'
         -'scheduled_lesson_date'-'student_settlement_month'
         -'billing_month_source'-'billing_month_decided_at')::text)
          IS DISTINCT FROM manifest.expected_old31_hash
       OR actual.lesson_type IS DISTINCT FROM 'actual'
       OR actual.planned_lesson_id IS DISTINCT FROM lesson.id
       OR actual.status IS DISTINCT FROM 'completed'
       OR manifest.manual_decision<>'ALREADY_CHARGED_EXCLUDE'
       OR manifest.expected_external_evidence_sha256<>encode(
          digest(convert_to(manifest.expected_external_evidence_snapshot::text,'UTF8'),'sha256'),'hex')
  ) THEN
    RAISE EXCEPTION 'FIXED64_MANIFEST_CURRENT_FACT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
    WHERE (SELECT count(*) FROM public.school_lesson_records actual
           WHERE actual.lesson_type='actual'
             AND actual.planned_lesson_id=manifest.planned_lesson_id)<>1
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
                  WHERE relation.planned_lesson_id=manifest.planned_lesson_id)
       OR EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions exclusion
                  WHERE exclusion.planned_lesson_id=manifest.planned_lesson_id)
  ) THEN
    RAISE EXCEPTION 'FIXED64_PLANNED_RELATION_OR_ACTUAL_DRIFT';
  END IF;

  IF (SELECT count(DISTINCT evidence_package_key)
      FROM public.school_20260802_fixed_64_already_charged_manifest())<>6
     OR EXISTS (
       SELECT 1 FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
       WHERE manifest.expected_external_evidence_snapshot->>'evidence_profile_code'
          IS DISTINCT FROM manifest.evidence_profile_code
          OR manifest.expected_external_evidence_snapshot#>>'{approval,approved_fact}'
             IS DISTINCT FROM 'ALREADY_CHARGED_EXCLUDE'
          OR manifest.expected_external_evidence_snapshot#>>'{planned_scope,authority}'
             IS DISTINCT FROM 'fixed_64_business_owner_manifest'
          OR (manifest.expected_external_evidence_snapshot#>>'{planned_scope,native_payment_to_planned_relation}')::boolean
             IS DISTINCT FROM false
     ) THEN
    RAISE EXCEPTION 'FIXED64_EVIDENCE_PACKAGE_CONTRACT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      SELECT DISTINCT evidence_package_key,expected_external_evidence_snapshot
      FROM public.school_20260802_fixed_64_already_charged_manifest()
      WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1'
    ) package
    CROSS JOIN LATERAL jsonb_array_elements(package.expected_external_evidence_snapshot->'school_income_records') evidence(row_value)
    LEFT JOIN public.school_income_records income ON income.id=(evidence.row_value->>'id')::uuid
    WHERE income.id IS NULL OR to_jsonb(income) IS DISTINCT FROM evidence.row_value
  ) OR EXISTS (
    SELECT 1
    FROM (
      SELECT DISTINCT evidence_package_key,expected_external_evidence_snapshot
      FROM public.school_20260802_fixed_64_already_charged_manifest()
      WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1'
    ) package
    CROSS JOIN LATERAL jsonb_array_elements(package.expected_external_evidence_snapshot->'school_cash_linkages') evidence(row_value)
    LEFT JOIN public.school_personal_cash_income_linkage_events linkage ON linkage.id=(evidence.row_value->>'id')::uuid
    WHERE linkage.id IS NULL OR to_jsonb(linkage) IS DISTINCT FROM evidence.row_value
  ) THEN
    RAISE EXCEPTION 'FIXED64_SCHOOL_EVIDENCE_SNAPSHOT_DRIFT';
  END IF;

  IF (SELECT count(*) FROM (
      SELECT DISTINCT (evidence.row_value->>'id')::uuid
      FROM (
        SELECT DISTINCT evidence_package_key,expected_external_evidence_snapshot
        FROM public.school_20260802_fixed_64_already_charged_manifest()
        WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1'
      ) package
      CROSS JOIN LATERAL jsonb_array_elements(package.expected_external_evidence_snapshot->'school_income_records') evidence(row_value)
    ) income_ids)<>4
     OR (SELECT count(*) FROM (
      SELECT DISTINCT (evidence.row_value->>'id')::uuid
      FROM (
        SELECT DISTINCT evidence_package_key,expected_external_evidence_snapshot
        FROM public.school_20260802_fixed_64_already_charged_manifest()
        WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1'
      ) package
      CROSS JOIN LATERAL jsonb_array_elements(package.expected_external_evidence_snapshot->'school_cash_linkages') evidence(row_value)
    ) linkage_ids)<>4 THEN
    RAISE EXCEPTION 'FIXED64_SCHOOL_EVIDENCE_COUNT_DRIFT';
  END IF;

  WITH scopes AS (
    SELECT DISTINCT expected_student_id student_id,expected_business_entity_id entity_id,expected_billing_month billing_month
    FROM public.school_20260802_fixed_64_already_charged_manifest()
  ), candidates AS (
    SELECT c.planned_lesson_id
    FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      s.student_id,s.entity_id,s.billing_month,false
    ) c
  )
  SELECT count(*) INTO v_count
  FROM candidates
  JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
    ON manifest.planned_lesson_id=candidates.planned_lesson_id;
  IF v_count<>64 THEN
    RAISE EXCEPTION 'FIXED64_CANDIDATE_PREFLIGHT_COUNT: %',v_count;
  END IF;
END
$manifest_preflight$;

INSERT INTO public.school_student_tuition_historical_lesson_exclusions (
  planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
  settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
  locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
  evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
  approval_report_version,manifest_version,approval_summary,evidence_recorded_at,
  recorded_by,evidence_profile_code,lesson_complete_row_hash,
  external_evidence_snapshot,external_evidence_sha256
)
SELECT
  manifest.planned_lesson_id,manifest.expected_student_id,manifest.expected_business_entity_id,
  manifest.expected_billing_month,manifest.expected_old31_hash,manifest.expected_actual_lesson_id,
  NULL,NULL,NULL,manifest.expected_evidence_hash,'historical_monthly_tuition_paid',
  'business_owner_final_confirmed','approved_20260802_64_already_charged_manifest',
  'school-v2-2026-05-06-64-already-charged-final-review-20260802-v1',
  'school-v2-2026-05-06-fixed-64-already-charged-20260802-v1',
  manifest.normalized_note,manifest.evidence_recorded_at,current_user,
  manifest.evidence_profile_code,manifest.expected_complete_row_hash,
  manifest.expected_external_evidence_snapshot,manifest.expected_external_evidence_sha256
FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
ORDER BY manifest.planned_lesson_id;

CREATE TEMP TABLE fixed64_after_fingerprints (
  object_name text PRIMARY KEY,
  row_count bigint NOT NULL,
  row_hash text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixed64_after_fingerprints(object_name,row_count,row_hash)
SELECT 'planned_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_lesson_records x WHERE x.lesson_type='planned'
UNION ALL SELECT 'actual_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_lesson_records x WHERE x.lesson_type='actual'
UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_bills x
UNION ALL SELECT 'income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_income_records x
UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_bill_lessons x
UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_billing_identities x
UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_monthly_settlements x
UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_teacher_wage_locks x
UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_teacher_wage_lock_details x
UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_account_transactions x
UNION ALL SELECT 'school_cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
  FROM public.school_personal_cash_income_linkage_events x
UNION ALL SELECT 'old42_business_fields',count(*),md5(coalesce(string_agg(md5((to_jsonb(x)-ARRAY[
      'evidence_profile_code','lesson_complete_row_hash','external_evidence_snapshot','external_evidence_sha256'
    ]::text[])::text),'' ORDER BY x.id::text),''))
  FROM public.school_student_tuition_historical_lesson_exclusions x
  WHERE x.evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1'
UNION ALL SELECT 'candidate_reader',1,md5(pg_get_functiondef(
  'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
));

WITH scopes AS (
  SELECT DISTINCT student_id,business_entity_id,billing_month
  FROM public.school_lesson_records
  WHERE lesson_type='planned'
    AND student_id IS NOT NULL
    AND business_entity_id IS NOT NULL
    AND billing_month IS NOT NULL
    AND NOT (
      business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
      AND student_id IN (
        'cff85c52-6acc-4b0f-8c92-3db280a5dd77'::uuid,
        'eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,
        'a7b163a0-201e-4867-9b94-372343356a80'::uuid
      )
      AND billing_month IN ('2026-05','2026-06')
    )
), candidate_rows AS (
  SELECT c.*
  FROM scopes s
  CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
    s.student_id,s.business_entity_id,s.billing_month,false
  ) c
)
INSERT INTO fixed64_after_fingerprints(object_name,row_count,row_hash)
SELECT 'other_candidate_rows',count(*),md5(coalesce(string_agg(md5(to_jsonb(candidate_rows)::text),'' ORDER BY planned_lesson_id::text),''))
FROM candidate_rows;

DO $postinsert_contract$
DECLARE
  v_count bigint;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM fixed64_before_fingerprints before_row
    FULL JOIN fixed64_after_fingerprints after_row USING(object_name)
    WHERE before_row.object_name IS NULL OR after_row.object_name IS NULL
       OR before_row.row_count IS DISTINCT FROM after_row.row_count
       OR before_row.row_hash IS DISTINCT FROM after_row.row_hash
  ) THEN
    RAISE EXCEPTION 'FIXED64_IMMUTABLE_OBJECT_FINGERPRINT_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>106
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1')<>42
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='CASH_MANUAL_INCOME_MATCHED_V1')<>22
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='CASH_MANUAL_INCOME_OWNER_CONFIRMED_UNLOCATED_V1')<>8
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='SCHOOL_INCOME_CASH_SYNC_V1')<>34 THEN
    RAISE EXCEPTION 'FIXED64_POSTINSERT_PROFILE_COUNT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_20260802_fixed_64_already_charged_manifest() manifest
    LEFT JOIN public.school_student_tuition_historical_lesson_exclusions exclusion
      ON exclusion.planned_lesson_id=manifest.planned_lesson_id
    WHERE exclusion.id IS NULL
       OR exclusion.student_id_snapshot IS DISTINCT FROM manifest.expected_student_id
       OR exclusion.business_entity_id_snapshot IS DISTINCT FROM manifest.expected_business_entity_id
       OR exclusion.settlement_month_snapshot IS DISTINCT FROM manifest.expected_billing_month
       OR exclusion.linked_actual_lesson_id IS DISTINCT FROM manifest.expected_actual_lesson_id
       OR exclusion.lesson_old31_hash IS DISTINCT FROM manifest.expected_old31_hash
       OR exclusion.lesson_complete_row_hash IS DISTINCT FROM manifest.expected_complete_row_hash
       OR exclusion.evidence_profile_code IS DISTINCT FROM manifest.evidence_profile_code
       OR exclusion.external_evidence_snapshot IS DISTINCT FROM manifest.expected_external_evidence_snapshot
       OR exclusion.external_evidence_sha256 IS DISTINCT FROM manifest.expected_external_evidence_sha256
       OR exclusion.evidence_hash IS DISTINCT FROM manifest.expected_evidence_hash
       OR exclusion.evidence_recorded_at IS DISTINCT FROM manifest.evidence_recorded_at
  ) THEN
    RAISE EXCEPTION 'FIXED64_INSERTED_ROW_MANIFEST_MISMATCH';
  END IF;

  WITH scopes AS (
    SELECT DISTINCT expected_student_id student_id,expected_business_entity_id entity_id,expected_billing_month billing_month
    FROM public.school_20260802_fixed_64_already_charged_manifest()
  ), included AS (
    SELECT c.*
    FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      s.student_id,s.entity_id,s.billing_month,true
    ) c
    JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
      ON manifest.planned_lesson_id=c.planned_lesson_id
  ), leaked AS (
    SELECT c.planned_lesson_id
    FROM scopes s
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      s.student_id,s.entity_id,s.billing_month,false
    ) c
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
    CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
      s.student_id,s.entity_id,s.billing_month,false
    ) c
    JOIN public.school_20260802_fixed_64_already_charged_manifest() manifest
      ON manifest.planned_lesson_id=c.planned_lesson_id
  ) THEN
    RAISE EXCEPTION 'FIXED64_CANDIDATE_POSTINSERT_FAILURE: excluded count %',v_count;
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'FIXED64_POSTINSERT_GATE_DRIFT';
  END IF;
END
$postinsert_contract$;

TABLE fixed64_before_fingerprints;
SELECT evidence_profile_code,count(*) AS row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) AS full_row_hash
FROM public.school_student_tuition_historical_lesson_exclusions x
GROUP BY evidence_profile_code
ORDER BY evidence_profile_code;
