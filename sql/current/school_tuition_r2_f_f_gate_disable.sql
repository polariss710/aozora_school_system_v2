-- School V2 R2-F-F emergency disable/rollback. Not executed during enablement.
-- Required psql variable: r2_f_f_disable_commit=0 rehearsal or 1 formal disable.
-- Does not alter Cash and never writes tuition business rows.
\set ON_ERROR_STOP on
\pset pager off
\if :{?r2_f_f_disable_commit}
\else
  \echo 'R2_F_F_DISABLE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
UPDATE public.school_feature_gates
SET state='validation_preview_only',
    reason='R2-F-F紧急回退：保留权威只读validation preview。',
    release_version='r2-f-f-disabled-20260801',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key='student_tuition_preview';
UPDATE public.school_feature_gates
SET state='blocked',
    reason='R2-F-F紧急回退：atomic generate已阻断。',
    release_version='r2-f-f-disabled-20260801',
    updated_at=statement_timestamp(),updated_by=current_user
WHERE feature_key='student_tuition_generate';
DO $verify$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_DISABLE_STATE_FAILED';
  END IF;
END
$verify$;
\if :r2_f_f_disable_commit
  COMMIT;
\else
  ROLLBACK;
\endif
