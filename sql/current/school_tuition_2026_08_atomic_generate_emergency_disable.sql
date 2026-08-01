-- Emergency action: block only student_tuition_generate; preview stays enabled and Cash stays blocked.
-- Required psql variable: tuition_202608_disable_commit=0 rehearsal or 1 authorized emergency deploy.
-- This task executes rehearsal=0 only. Formal disable requires a new explicit authorization.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_202608_disable_commit}
\else
  \echo 'TUITION_202608_DISABLE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_DISABLE_BASELINE_DRIFT';
  END IF;
END
$preflight$;

UPDATE public.school_feature_gates
SET state='blocked',
    reason='2026年8月atomic generate紧急停止；preview继续开放，Cash继续禁止。',
    release_version='tuition-2026-08-emergency-disable',
    evidence_hash='manual-emergency-disable-requires-authorization',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key='student_tuition_generate' AND state='enabled';

DO $verify$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_DISABLE_FAILED';
  END IF;
END
$verify$;

\if :tuition_202608_disable_commit
  COMMIT;
  \echo 'TUITION_202608_GENERATE_GATE_DISABLED'
\else
  ROLLBACK;
  \echo 'TUITION_202608_EMERGENCY_DISABLE_REHEARSAL_ROLLED_BACK'
\endif
