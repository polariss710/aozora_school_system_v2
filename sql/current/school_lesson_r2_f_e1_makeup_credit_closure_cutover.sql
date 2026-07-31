-- School V2 R2-F-E1 makeup-credit source preservation correction.
-- Usage:
--   r2_f_e1_commit=0  same-byte rehearsal with explicit ROLLBACK
--   r2_f_e1_commit=1  formal code-only DDL deployment with explicit COMMIT

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_e1_commit}
\else
  \echo 'R2_F_E1_COMMIT_VARIABLE_REQUIRED'
  \quit 3
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ) INTO STRICT v_definition;

  IF md5(v_definition)<>'3b9378e01900b0e73b9d0b1c2d1e7209'
     OR position($old$
  IF public.school_get_lesson_credit_remaining_hours(v_planned.id)<=0 THEN
    UPDATE public.school_lesson_records SET status='makeup_completed'
    WHERE id=v_planned.id;
  END IF;
$old$ IN v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_E1_MAKEUP_WRITER_DEFINITION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E1_R0_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_F_E1_REPLACE_MAKEUP_CREDIT_WRITER'
DO $replace_writer$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text := $old$
  IF public.school_get_lesson_credit_remaining_hours(v_planned.id)<=0 THEN
    UPDATE public.school_lesson_records SET status='makeup_completed'
    WHERE id=v_planned.id;
  END IF;
$old$;
  v_new text := $new$
  -- R2-F-E1: the original charged planned row is the immutable credit source.
  -- Linked completed/makeup_completed actual duration consumes its balance;
  -- the source remains pending_makeup even when the remaining balance is zero.
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ) INTO STRICT v_definition;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition
     OR position('R2-F-E1: the original charged planned row is the immutable credit source.' IN v_replaced)=0
     OR position(v_old IN v_replaced)>0 THEN
    RAISE EXCEPTION 'R2_F_E1_MAKEUP_WRITER_REPLACEMENT_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace_writer$;

COMMENT ON FUNCTION public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) IS
  'R2-F-E1 canonical lesson-credit consumer. Creates a non-billable makeup_completed actual using DB-resolved student month and actual-date teacher month; the immutable charged planned source remains pending_makeup, while linked completed duration reduces its authoritative balance to zero and prevents duplicate consumption.';

DO $verify$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('R2-F-E1: the original charged planned row is the immutable credit source.' IN v_definition)=0
     OR position($old$
  IF public.school_get_lesson_credit_remaining_hours(v_planned.id)<=0 THEN
    UPDATE public.school_lesson_records SET status='makeup_completed'
    WHERE id=v_planned.id;
  END IF;
$old$ IN v_definition)>0
     OR NOT has_function_privilege('anon',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_E1_DEPLOYED_WRITER_OR_ACL_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E1_R0_CHANGED';
  END IF;
END
$verify$;

SELECT md5(pg_get_functiondef(
  'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
)) AS makeup_credit_writer_md5;

\if :r2_f_e1_commit
  COMMIT;
  \echo 'R2_F_E1_DEPLOYMENT_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_F_E1_REHEARSAL_ROLLED_BACK'
\endif
