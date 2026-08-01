-- AUDIT-ONLY rollback design. NOT EXECUTED and not authorized by the deployment approval.
-- A future business-owner decision must explicitly authorize removal of the exact fixed64 set.
\set ON_ERROR_STOP on

\if :{?business_owner_authorization}
\else
  \echo 'Missing business_owner_authorization; audit rollback is blocked.'
  \quit
\endif

SELECT :'business_owner_authorization'='APPROVED_FIXED64_HISTORICAL_EXCLUSION_ROLLBACK'
  AS rollback_authorized \gset
\if :rollback_authorized
\else
  \echo 'Business-owner authorization token mismatch; audit rollback is blocked.'
  \quit
\endif

BEGIN ISOLATION LEVEL REPEATABLE READ;
LOCK TABLE public.school_student_tuition_historical_lesson_exclusions IN ACCESS EXCLUSIVE MODE;

DO $rollback_preflight$
DECLARE
  v_count bigint;
  v_id_hash text;
  v_full_hash text;
BEGIN
  SELECT count(*),
         encode(digest(string_agg(planned_lesson_id::text,'|' ORDER BY planned_lesson_id::text),'sha256'),'hex'),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),''))
  INTO v_count,v_id_hash,v_full_hash
  FROM public.school_student_tuition_historical_lesson_exclusions x
  WHERE manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1';

  IF v_count<>64
     OR v_id_hash<>'7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85'
     OR v_full_hash<>'d09fcf2193218fb02c9d3b2b7e7cbb20' THEN
    RAISE EXCEPTION 'FIXED64_AUDIT_ROLLBACK_AFTER_HASH_DRIFT: count %, id hash %, full hash %',
      v_count,v_id_hash,v_full_hash;
  END IF;
END
$rollback_preflight$;

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  DISABLE TRIGGER school_tuition_historical_exclusion_row_immutable;

DELETE FROM public.school_student_tuition_historical_lesson_exclusions
WHERE manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1';

ALTER TABLE public.school_student_tuition_historical_lesson_exclusions
  ENABLE TRIGGER school_tuition_historical_exclusion_row_immutable;

DO $rollback_verify$
BEGIN
  IF (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>42
     OR EXISTS (
       SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions
       WHERE manifest_version='school-v2-2026-05-06-fixed-64-already-charged-20260802-v1'
     )
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions
         WHERE evidence_profile_code='SCHOOL_SETTLEMENT_INCOME_ACCOUNT_TX_V1')<>42
     OR position('TUITION_HISTORICAL_LESSON_EXCLUSION_INSERT_RETIRED' IN
        pg_get_functiondef('public.school_guard_tuition_historical_lesson_exclusion_insert()'::regprocedure))=0 THEN
    RAISE EXCEPTION 'FIXED64_AUDIT_ROLLBACK_VERIFY_FAILED';
  END IF;
END
$rollback_verify$;

COMMIT;
