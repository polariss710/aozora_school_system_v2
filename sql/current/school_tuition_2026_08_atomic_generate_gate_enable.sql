-- Enable only the existing public atomic tuition generate gate after acceptance.
-- Required psql variable: tuition_202608_gate_commit=0 rehearsal or 1 deploy.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_202608_gate_commit}
\else
  \echo 'TUITION_202608_GATE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
     ))<>'083bcb58c2b92f34ded07dceafbbbbfe'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'b88f6d960d920c10b914fe8e58cf38cb'
     OR md5(pg_get_functiondef(
       'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
     ))<>'11ef7b45932e6cd418c03c91da104fd0'
     OR md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'::regprocedure
     ))<>'36bdadc9af59637c9d336ce68d9afb4c' THEN
    RAISE EXCEPTION 'TUITION_202608_GATE_FUNCTION_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_GATE_BASELINE_DRIFT';
  END IF;
END
$preflight$;

UPDATE public.school_feature_gates
SET state='enabled',
    reason='2026年8月全体candidate、locked-only carryover及atomic rollback矩阵已验收；仅开放唯一atomic generate。',
    release_version='tuition-2026-08-atomic-generate-restored-20260802',
    evidence_hash='candidate-114-cb3451c2-atomic-28-pass',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key='student_tuition_generate' AND state='blocked';

DO $verify$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_GATE_ENABLE_FAILED';
  END IF;
END
$verify$;

SELECT feature_key,state,release_version,evidence_hash
FROM public.school_feature_gates
WHERE feature_key IN ('student_tuition_preview','student_tuition_generate',
                      'student_tuition_cash_submit')
ORDER BY feature_key;

\if :tuition_202608_gate_commit
  COMMIT;
  \echo 'TUITION_202608_GENERATE_GATE_ENABLED'
\else
  ROLLBACK;
  \echo 'TUITION_202608_GENERATE_GATE_REHEARSAL_ROLLED_BACK'
\endif
