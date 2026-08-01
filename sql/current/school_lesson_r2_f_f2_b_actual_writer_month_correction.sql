-- School V2 R2-F-F2-B: close raw actual year_month in production lock checks.
-- Required psql variable: r2_f_f2_b_actual_writer_commit=0 rehearsal or 1 deploy.
-- Code-only DDL. No lesson, settlement, wage or other business DML.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f2_b_actual_writer_commit}
\else
  \echo 'R2_F_F2_B_ACTUAL_WRITER_COMMIT_VARIABLE_REQUIRED'
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
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_WRITER_GATE_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
     ))<>'6494cf6089a217d2bf726f42d3d0c896'
     OR md5(pg_get_functiondef(
       'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
     ))<>'8aea35bc54e24e3e5f01cb5644500be6' THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_WRITER_FUNCTION_BASELINE_DRIFT';
  END IF;
END
$preflight$;

CREATE FUNCTION pg_temp.r2_f_f2_b_actual_writer_patch(
  p_signature text,
  p_expected_md5 text,
  p_old_fragments text[],
  p_new_fragments text[],
  p_expected_occurrences integer[]
)
RETURNS text
LANGUAGE plpgsql
AS $patcher$
DECLARE
  v_oid regprocedure;
  v_definition text;
  v_occurrences integer;
  v_index integer;
BEGIN
  IF coalesce(array_length(p_old_fragments,1),0)=0
     OR array_length(p_old_fragments,1)<>array_length(p_new_fragments,1)
     OR array_length(p_old_fragments,1)<>array_length(p_expected_occurrences,1) THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_WRITER_PATCH_ARGUMENTS_INVALID';
  END IF;
  v_oid:=to_regprocedure(p_signature);
  IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid))<>p_expected_md5 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_WRITER_FUNCTION_DRIFT: %',p_signature;
  END IF;
  v_definition:=pg_get_functiondef(v_oid);
  FOR v_index IN 1..array_length(p_old_fragments,1) LOOP
    v_occurrences:=(length(v_definition)-length(replace(
      v_definition,p_old_fragments[v_index],''
    )))/length(p_old_fragments[v_index]);
    IF v_occurrences<>p_expected_occurrences[v_index] THEN
      RAISE EXCEPTION
        'R2_F_F2_B_ACTUAL_WRITER_FRAGMENT_COUNT: %, fragment %, expected %, got %',
        p_signature,v_index,p_expected_occurrences[v_index],v_occurrences;
    END IF;
    v_definition:=replace(
      v_definition,p_old_fragments[v_index],p_new_fragments[v_index]
    );
  END LOOP;
  EXECUTE v_definition;
  RETURN md5(pg_get_functiondef(v_oid));
END
$patcher$;

SELECT 'teacher_wage_student_settlement_check' AS object_name,
  pg_temp.r2_f_f2_b_actual_writer_patch(
    'public.school_generate_teacher_monthly_wage(text,uuid,uuid)',
    '6494cf6089a217d2bf726f42d3d0c896',
    ARRAY[
      'c.year_month,',
      'm.year_month = c.year_month',
      'ug.year_month'
    ],
    ARRAY[
      'public.school_resolve_r1d_e_c_lesson_student_month(c.id) as student_settlement_month,',
      'm.year_month = public.school_resolve_r1d_e_c_lesson_student_month(c.id)',
      'ug.student_settlement_month'
    ],
    ARRAY[2,2,1]
  ) AS function_md5;

SELECT 'actual_minutes_student_settlement_check' AS object_name,
  pg_temp.r2_f_f2_b_actual_writer_patch(
    'public.school_backfill_actual_minutes_from_duration(text)',
    '8aea35bc54e24e3e5f01cb5644500be6',
    ARRAY['s.year_month = c.year_month'],
    ARRAY[
      's.year_month = public.school_resolve_r1d_e_c_lesson_student_month(c.id)'
    ],
    ARRAY[1]
  ) AS function_md5;

DO $verify$
DECLARE
  v_wage_definition text:=pg_get_functiondef(
    'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
  );
  v_backfill_definition text:=pg_get_functiondef(
    'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
  );
BEGIN
  IF position('m.year_month = c.year_month' IN v_wage_definition)>0
     OR position('ug.year_month' IN v_wage_definition)>0
     OR position('school_resolve_r1d_e_c_lesson_student_month(c.id)'
          IN v_wage_definition)=0
     OR position('s.year_month = c.year_month' IN v_backfill_definition)>0
     OR position('school_resolve_r1d_e_c_lesson_student_month(c.id)'
          IN v_backfill_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_WRITER_OBJECT_VERIFICATION_FAILED';
  END IF;
END
$verify$;

SELECT p.oid::regprocedure::text AS function_signature,
  md5(pg_get_functiondef(p.oid)) AS function_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.oid IN (
  'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure,
  'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
)
ORDER BY 1;

\if :r2_f_f2_b_actual_writer_commit
  COMMIT;
\else
  ROLLBACK;
\endif
