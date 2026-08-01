-- School V2 R2-F-F2-B: complete actual-side month resolution in lesson stats.
-- Required psql variable: r2_f_f2_b_actual_stats_commit=0 rehearsal or 1 deploy.
-- Code-only DDL. No lesson, settlement, bill, income, wage, account or Cash DML.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f2_b_actual_stats_commit}
\else
  \echo 'R2_F_F2_B_ACTUAL_STATS_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_STATS_GATE_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'61a862e0c5c021248caf586fc6b04b96' THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_STATS_FUNCTION_BASELINE_DRIFT';
  END IF;
END
$preflight$;

DO $replace$
DECLARE
  v_signature regprocedure :=
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure;
  v_definition text;
  v_old_fragment constant text :=
    'coalesce(actual.student_settlement_month,actual.year_month)';
  v_new_fragment constant text :=
    'public.school_resolve_r1d_e_c_lesson_student_month(actual.id)';
  v_occurrences integer;
BEGIN
  v_definition:=pg_get_functiondef(v_signature);
  v_occurrences:=(length(v_definition)-length(replace(
    v_definition,v_old_fragment,''
  )))/length(v_old_fragment);
  IF v_occurrences<>1 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_STATS_FRAGMENT_COUNT: expected 1, got %',
      v_occurrences;
  END IF;
  EXECUTE replace(v_definition,v_old_fragment,v_new_fragment);
END
$replace$;

DO $verify$
DECLARE
  v_definition text := pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  );
BEGIN
  IF position('coalesce(actual.student_settlement_month,actual.year_month)'
       IN v_definition)>0
     OR position(
       'school_resolve_r1d_e_c_lesson_student_month(actual.id)'
       IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_STATS_OBJECT_VERIFICATION_FAILED';
  END IF;
END
$verify$;

SELECT
  'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)' AS function_signature,
  md5(pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  )) AS function_md5;

\if :r2_f_f2_b_actual_stats_commit
  COMMIT;
\else
  ROLLBACK;
\endif
