-- Aozora School System V2 R2-E
-- Independent correction for the deployed guarded-update aircon-rate overload.
-- Required psql variable:
--   r2_e_guarded_fix_commit=0  same-byte rehearsal and explicit ROLLBACK
--   r2_e_guarded_fix_commit=1  formal correction and explicit COMMIT

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_e_guarded_fix_commit}
\else
  \echo 'R2_E_GUARDED_FIX_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

\echo 'R2_E_GUARDED_FIX_BEGIN'
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

DO $preflight$
DECLARE
  v_proc pg_proc%ROWTYPE;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid =
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure;

  IF md5(pg_get_functiondef(v_proc.oid))
       <> '11e1758978fc3288a2d9a2b1079a0cf9' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_UNEXPECTED_DEPLOYED_DEFINITION';
  END IF;
  IF v_proc.provolatile <> 'v'
     OR NOT v_proc.prosecdef
     OR v_proc.prokind <> 'f'
     OR v_proc.proowner::regrole::text <> 'postgres'
     OR v_proc.proconfig
          IS DISTINCT FROM ARRAY['search_path=public']::text[]
     OR v_proc.proacl::text <>
          '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_FUNCTION_METADATA_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_lesson_records row_value)
          <> '9a787d2819b24fe4dece792b55b35ba5'
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bills row_value)
          <> 'b91c381ea7c42d8dc60e8a6af189f86a'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_income_records row_value)
          <> '3ee88b3e883359e819a93d80ea0204b2'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bill_lessons row_value)
          <> 'ff626f1677571c76406b4bc7b5122391'
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_monthly_settlements row_value)
          <> '44446ca9a3aa8fa7672e31d9ec25352c'
     OR (SELECT count(*) FROM public.school_teacher_wage_lock_details) <> 556
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_teacher_wage_lock_details row_value)
          <> '6d68749bc1f0fbb908d2dfdb43dcc774' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_BUSINESS_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked'))
       <> 3 THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_R0_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_E_GUARDED_FIX_CREATE_OR_REPLACE'
CREATE OR REPLACE FUNCTION public.school_update_lesson_record_guarded(
  p_lesson_id uuid,p_expected_updated_at timestamptz,p_lesson_date date,
  p_student_id uuid,p_teacher_id uuid,p_subject_id uuid,p_business_entity_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_unit_price numeric,
  p_lesson_fee numeric,p_status text,p_is_billable boolean,p_lesson_count integer,
  p_lesson_content text,p_note text,p_aircon_rate_jpy_per_hour integer
)
RETURNS TABLE (
  lesson_id uuid,lesson_type text,lesson_date date,year_month text,
  student_id uuid,teacher_id uuid,subject_id uuid,business_entity_id uuid,
  start_time text,end_time text,duration_hours numeric,unit_price numeric,
  lesson_fee numeric,status text,is_billable boolean,lesson_count integer,
  actual_minutes integer,planned_lesson_id uuid,teacher_settlement_month text,
  lesson_content text,note text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_id uuid;
  v_type text;
BEGIN
  SELECT lesson.lesson_type INTO STRICT v_type
  FROM public.school_lesson_records lesson
  WHERE lesson.id = p_lesson_id;
  IF v_type <> 'planned' THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_ONLY_ALLOWED_FOR_PLANNED';
  END IF;
  IF p_aircon_rate_jpy_per_hour IS NULL
     OR p_aircon_rate_jpy_per_hour < 0 THEN
    RAISE EXCEPTION 'R2_E_AIRCON_RATE_INVALID';
  END IF;
  SELECT updated.lesson_id INTO STRICT v_id
  FROM public.school_update_lesson_record_guarded(
    p_lesson_id,p_expected_updated_at,p_lesson_date,p_student_id,p_teacher_id,
    p_subject_id,p_business_entity_id,p_start_time,p_end_time,p_duration_hours,
    p_unit_price,p_lesson_fee,p_status,p_is_billable,p_lesson_count,
    p_lesson_content,p_note
  ) updated;
  UPDATE public.school_lesson_records lesson
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE lesson.id = v_id;
  RETURN QUERY
  SELECT
    l.id,l.lesson_type,l.lesson_date,l.year_month,l.student_id,l.teacher_id,
    l.subject_id,l.business_entity_id,l.start_time,l.end_time,l.duration_hours,
    l.unit_price,l.lesson_fee,l.status,l.is_billable,l.lesson_count,
    l.actual_minutes,l.planned_lesson_id,l.teacher_settlement_month,
    l.lesson_content,l.note,l.created_at,l.updated_at
  FROM public.school_lesson_records l WHERE l.id = v_id;
END
$function$;

\echo 'R2_E_GUARDED_FIXTURE_WRITE_CALL'
DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_fixture public.school_lesson_records%ROWTYPE;
  v_created public.school_lesson_records%ROWTYPE;
  v_saved public.school_lesson_records%ROWTYPE;
  v_updated record;
  v_fixture_id uuid;
BEGIN
  SELECT function_row.* INTO STRICT v_proc
  FROM pg_proc function_row
  WHERE function_row.oid =
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure;

  IF md5(pg_get_functiondef(v_proc.oid))
       = '11e1758978fc3288a2d9a2b1079a0cf9'
     OR pg_get_functiondef(v_proc.oid)
          NOT LIKE '%SELECT lesson.lesson_type INTO STRICT v_type%'
     OR pg_get_functiondef(v_proc.oid)
          NOT LIKE '%WHERE lesson.id = p_lesson_id%'
     OR pg_get_functiondef(v_proc.oid)
          NOT LIKE '%WHERE lesson.id = v_id%' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_DEFINITION_NOT_CORRECTED';
  END IF;
  IF v_proc.provolatile <> 'v'
     OR NOT v_proc.prosecdef
     OR v_proc.prokind <> 'f'
     OR v_proc.proowner::regrole::text <> 'postgres'
     OR v_proc.proconfig
          IS DISTINCT FROM ARRAY['search_path=public']::text[]
     OR v_proc.proacl::text <>
          '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_METADATA_CHANGED';
  END IF;

  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  JOIN public.school_students student ON student.id = lesson.student_id
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.student_id IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND student.business_entity_id IS NOT DISTINCT FROM lesson.business_entity_id
  ORDER BY lesson.id
  LIMIT 1;

  BEGIN
    SELECT created.* INTO STRICT v_created
    FROM public.school_create_planned_lesson_record_with_venue(
      DATE '2042-08-02',
      v_fixture.student_id,
      v_fixture.teacher_id,
      v_fixture.subject_id,
      v_fixture.business_entity_id,
      '21:00','23:00',0,8500,NULL,'planned',1,
      'codex-test R2-E guarded correction',
      'codex-test r2-e guarded correction',
      NULL,NULL,0
    ) created;
    v_fixture_id := v_created.id;
    RAISE NOTICE 'R2_E_GUARDED_FIXTURE_ID=%',v_fixture_id;

    SELECT updated.* INTO STRICT v_updated
    FROM public.school_update_lesson_record_guarded(
      v_created.id,
      v_created.updated_at,
      v_created.lesson_date,
      v_created.student_id,
      v_created.teacher_id,
      v_created.subject_id,
      v_created.business_entity_id,
      v_created.start_time,
      v_created.end_time,
      v_created.duration_hours,
      v_created.unit_price,
      v_created.lesson_fee,
      v_created.status,
      v_created.is_billable,
      v_created.lesson_count,
      v_created.lesson_content,
      'codex-test r2-e guarded corrected update',
      330
    ) updated;

    SELECT lesson.* INTO STRICT v_saved
    FROM public.school_lesson_records lesson
    WHERE lesson.id = v_fixture_id;
    IF v_updated.lesson_id IS DISTINCT FROM v_fixture_id
       OR v_updated.lesson_type IS DISTINCT FROM 'planned'
       OR v_saved.lesson_type IS DISTINCT FROM 'planned'
       OR v_saved.aircon_unit_price_jpy_snapshot IS DISTINCT FROM 330
       OR v_saved.base_lesson_fee_jpy
            IS DISTINCT FROM v_saved.lesson_fee
       OR v_saved.lesson_total_fee_jpy
            IS DISTINCT FROM v_saved.base_lesson_fee_jpy
              + v_saved.aircon_fee_jpy
       OR v_saved.note IS DISTINCT FROM
            'codex-test r2-e guarded corrected update' THEN
      RAISE EXCEPTION 'R2_E_GUARDED_FIXTURE_WRITE_MISMATCH';
    END IF;

    RAISE NOTICE
      'R2_E_GUARDED_FIXTURE_RESULT id=%, base=%, rate=%, aircon=%, total=%',
      v_fixture_id,
      v_saved.base_lesson_fee_jpy,
      v_saved.aircon_unit_price_jpy_snapshot,
      v_saved.aircon_fee_jpy,
      v_saved.lesson_total_fee_jpy;
    RAISE EXCEPTION 'R2_E_GUARDED_FIXTURE_SUBTX_DONE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'R2_E_GUARDED_FIXTURE_SUBTX_DONE' THEN
      RAISE;
    END IF;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records lesson
    WHERE lesson.id = v_fixture_id
  ) THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIXTURE_SUBTX_RESIDUE';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_lesson_records row_value)
          <> '9a787d2819b24fe4dece792b55b35ba5'
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bills row_value)
          <> 'b91c381ea7c42d8dc60e8a6af189f86a'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_income_records row_value)
          <> '3ee88b3e883359e819a93d80ea0204b2'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_tuition_bill_lessons row_value)
          <> 'ff626f1677571c76406b4bc7b5122391'
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_student_monthly_settlements row_value)
          <> '44446ca9a3aa8fa7672e31d9ec25352c'
     OR (SELECT count(*) FROM public.school_teacher_wage_lock_details) <> 556
     OR (SELECT md5(jsonb_agg(to_jsonb(row_value)
          ORDER BY row_value.id)::text)
         FROM public.school_teacher_wage_lock_details row_value)
          <> '6d68749bc1f0fbb908d2dfdb43dcc774' THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_BUSINESS_DATA_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked'))
       <> 3 THEN
    RAISE EXCEPTION 'R2_E_GUARDED_FIX_R0_CHANGED';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure
  )) AS corrected_definition_md5,
  654 AS business_lesson_count,
  0 AS persisted_fixture_rows;

\if :r2_e_guarded_fix_commit
  \echo 'R2_E_GUARDED_FIX_COMMIT'
  COMMIT;
\else
  \echo 'R2_E_GUARDED_FIX_ROLLBACK'
  ROLLBACK;
\endif
