-- School V2 R2-F-F2-C: keep filtered lesson stats on the public authoritative
-- student-month resolver contract for browser/authenticated callers.
-- Required psql variable: r2_f_f2_c_commit=0 rehearsal or 1 deploy.
-- Code-only DDL. No lesson, settlement, bill, income, wage, account or Cash DML.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f2_c_commit}
\else
  \echo 'R2_F_F2_C_COMMIT_VARIABLE_REQUIRED'
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
    RAISE EXCEPTION 'R2_F_F2_C_GATE_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'9456529c3cfb0d597f106d5ea6806832' THEN
    RAISE EXCEPTION 'R2_F_F2_C_FILTERED_STATS_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_resolve_lesson_student_month_authoritative(uuid)'::regprocedure
     ))<>'fdc96abda53507cb9fd979809ebc0b10' THEN
    RAISE EXCEPTION 'R2_F_F2_C_PUBLIC_RESOLVER_BASELINE_DRIFT';
  END IF;
END
$preflight$;

DO $replace$
DECLARE
  v_signature regprocedure :=
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure;
  v_definition text := pg_get_functiondef(v_signature);
  v_old constant text :=
    'public.school_resolve_r1d_e_c_lesson_student_month(';
  v_new constant text :=
    'public.school_resolve_lesson_student_month_authoritative(';
  v_occurrences integer;
BEGIN
  v_occurrences:=(length(v_definition)-length(replace(
    v_definition,v_old,''
  )))/length(v_old);
  IF v_occurrences<>2 THEN
    RAISE EXCEPTION 'R2_F_F2_C_PRIVATE_RESOLVER_COUNT: expected 2, got %',
      v_occurrences;
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$replace$;

DO $verify$
DECLARE
  v_definition text := pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  );
  v_public_fragment constant text :=
    'public.school_resolve_lesson_student_month_authoritative(';
  v_public_count integer;
BEGIN
  v_public_count:=(length(v_definition)-length(replace(
    v_definition,v_public_fragment,''
  )))/length(v_public_fragment);
  IF position('public.school_resolve_r1d_e_c_lesson_student_month(' IN
       v_definition)>0 OR v_public_count<>2 THEN
    RAISE EXCEPTION 'R2_F_F2_C_FILTERED_STATS_VERIFICATION_FAILED';
  END IF;
END
$verify$;

SELECT
  'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)' AS function_signature,
  md5(pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  )) AS function_md5;

\if :r2_f_f2_c_commit
  COMMIT;
\else
  ROLLBACK;
\endif
