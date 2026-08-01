-- School V2 R2-F-F1: temporarily block atomic tuition generation while
-- preserving authoritative read-only preview. No tuition business rows change.
-- Required psql variable: r2_f_f1_gate_commit=0 rehearsal or 1 deploy.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f1_gate_commit}
\else
  \echo 'R2_F_F1_GATE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state IN ('enabled','blocked'))
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F1_GATE_BASELINE_DRIFT';
  END IF;
  IF position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,text)'::regprocedure
     ))=0
     OR position('R0 does not provide an enabled generation path' IN pg_get_functiondef(
       'public.school_generate_student_tuition_bill(uuid,text,numeric,text)'::regprocedure
     ))=0
     OR position('R0 does not provide an enabled income-generation path' IN pg_get_functiondef(
       'public.school_create_student_tuition_bill_income_record(uuid,date,text)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F1_LEGACY_ENTRY_NOT_PERMANENTLY_BLOCKED';
  END IF;
END
$preflight$;

UPDATE public.school_feature_gates
SET state='blocked',
    reason='R2-F-F1调查既有planned编辑后空调费未重算；atomic generate临时fail-closed。',
    release_version='r2-f-f1-investigation-20260801',
    evidence_hash='planned-aircon-edit-recalculation-under-review',
    updated_at=statement_timestamp(),
    updated_by=current_user
WHERE feature_key='student_tuition_generate';

DO $verify$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F1_GATE_TARGET_STATE_FAILED';
  END IF;
END
$verify$;

\if :r2_f_f1_gate_commit
  COMMIT;
\else
  ROLLBACK;
\endif
