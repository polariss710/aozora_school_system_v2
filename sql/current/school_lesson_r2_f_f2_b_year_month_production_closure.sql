-- School V2 R2-F-F2-B: remove raw lesson year_month from production decisions.
-- Required psql variable: r2_f_f2_b_commit=0 rehearsal or 1 deploy.
-- Code-only DDL. No lesson, settlement, bill, income, wage, account or Cash DML.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f2_b_commit}
\else
  \echo 'R2_F_F2_B_COMMIT_VARIABLE_REQUIRED'
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
    RAISE EXCEPTION 'R2_F_F2_B_GATE_BASELINE_DRIFT';
  END IF;
  IF to_regprocedure(
       'public.school_resolve_lesson_student_month_authoritative(uuid)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'R2_F_F2_B_READ_WRAPPER_ALREADY_EXISTS';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure
     ))<>'861ec1c37c3ff9a8f87a21f9a4a638fa'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     ))<>'c3a139cf723376d0c741c46b94f87be6'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure
     ))<>'414662e9cf6d0d196c99cd0789f5705e'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     ))<>'6ae23d24b310a749082811fcdaf44131'
     OR md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))<>'149634304f5407de81f23717b913be7e'
     OR md5(pg_get_functiondef(
       'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure
     ))<>'ec7bdebb8b2eacf0527c603a32650af9'
     OR md5(pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     ))<>'12ed369b1af2de6860ae88ce143312a3'
     OR md5(pg_get_functiondef(
       'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
     ))<>'74ff81a3e22fe546f7cae962eaf516f2'
     OR md5(pg_get_functiondef(
       'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure
     ))<>'bcb6e07b8d39c6a1591d5c18e4d31f4b'
     OR md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'15965ecfe27a29f1f9e5a43d38216813'
     OR md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats(text,uuid,uuid,uuid,text,text,uuid)'::regprocedure
     ))<>'8fa87223c7e947f1253d79b5be25e84f'
     OR md5(pg_get_functiondef(
       'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
     ))<>'7a621ebd6800612b26bfb2661ec12c1a' THEN
    RAISE EXCEPTION 'R2_F_F2_B_FUNCTION_BASELINE_DRIFT';
  END IF;
END
$preflight$;

CREATE FUNCTION pg_temp.r2_f_f2_b_patch_function(
  p_signature text,
  p_expected_md5 text,
  p_old_fragment text,
  p_new_fragment text,
  p_expected_occurrences integer
)
RETURNS text
LANGUAGE plpgsql
AS $patcher$
DECLARE
  v_oid regprocedure;
  v_definition text;
  v_occurrences integer;
BEGIN
  v_oid:=to_regprocedure(p_signature);
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'R2_F_F2_B_FUNCTION_MISSING: %',p_signature;
  END IF;
  v_definition:=pg_get_functiondef(v_oid);
  IF md5(v_definition)<>p_expected_md5 THEN
    RAISE EXCEPTION 'R2_F_F2_B_FUNCTION_DRIFT: %',p_signature;
  END IF;
  v_occurrences:=(length(v_definition)-length(replace(
    v_definition,p_old_fragment,''
  )))/length(p_old_fragment);
  IF v_occurrences<>p_expected_occurrences THEN
    RAISE EXCEPTION 'R2_F_F2_B_FRAGMENT_COUNT: %, expected %, got %',
      p_signature,p_expected_occurrences,v_occurrences;
  END IF;
  EXECUTE replace(v_definition,p_old_fragment,p_new_fragment);
  RETURN md5(pg_get_functiondef(v_oid));
END
$patcher$;

SELECT 'single_planned_core' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)',
    '861ec1c37c3ff9a8f87a21f9a4a638fa',
    'and s.year_month = v_year_month',
    $new$and s.year_month = (
        select attribution.billing_month
        from public.school_resolve_planned_billing_attribution(
          p_lesson_date,
          null
        ) attribution
      )$new$,
    1
  ) AS function_md5;

SELECT 'batch_planned_core' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)',
    'c3a139cf723376d0c741c46b94f87be6',
    'and s.year_month = r.year_month',
    $new$and s.year_month = (
        select attribution.billing_month
        from public.school_resolve_planned_billing_attribution(
          null,
          r.lesson_date
        ) attribution
      )$new$,
    1
  ) AS function_md5;

SELECT 'import_planned_core' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)',
    '414662e9cf6d0d196c99cd0789f5705e',
    'and s.year_month = r.year_month',
    $new$and s.year_month = (
        select attribution.billing_month
        from public.school_resolve_planned_billing_attribution(
          r.lesson_date,
          null
        ) attribution
      )$new$,
    1
  ) AS function_md5;

SELECT 'guarded_update_core' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)',
    '6ae23d24b310a749082811fcdaf44131',
    'and s.year_month = v_year_month',
    $new$and s.year_month = case
        when v_lesson.lesson_type = 'planned' then v_old_year_month
        else v_year_month
      end$new$,
    1
  ) AS function_md5;

SELECT 'ordinary_actual_writer' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)',
    '149634304f5407de81f23717b913be7e',
    'and s.year_month = coalesce(v_overage_source_student_month, v_planned.year_month)',
    $new$and s.year_month = coalesce(
        v_overage_source_student_month,
        public.school_resolve_r1d_e_c_lesson_student_month(v_planned.id)
      )$new$,
    1
  ) AS function_md5;

SELECT 'partial_actual_writer' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)',
    'ec7bdebb8b2eacf0527c603a32650af9',
    'and s.year_month = v_planned.year_month',
    $new$and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(
        v_planned.id
      )$new$,
    1
  ) AS function_md5;

SELECT 'cancelled_actual_writer' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)',
    '12ed369b1af2de6860ae88ce143312a3',
    'and s.year_month = v_planned.year_month',
    $new$and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(
        v_planned.id
      )$new$,
    1
  ) AS function_md5;

SELECT 'fresh_planned_delete' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)',
    '74ff81a3e22fe546f7cae962eaf516f2',
    $old$coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'))$old$,
    'public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)',
    3
  ) AS function_md5;

SELECT 'planned_void' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_void_planned_lesson(uuid,timestamp with time zone,text)',
    'bcb6e07b8d39c6a1591d5c18e4d31f4b',
    $old$coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'))$old$,
    'public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)',
    1
  ) AS function_md5;

SELECT 'filtered_stats' AS object_name,
  pg_temp.r2_f_f2_b_patch_function(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)',
    '15965ecfe27a29f1f9e5a43d38216813',
    'coalesce(source.billing_month,source.year_month)',
    'public.school_resolve_r1d_e_c_lesson_student_month(source.id)',
    1
  ) AS function_md5;

CREATE OR REPLACE FUNCTION public.school_get_lesson_management_stats(
  p_year_month text,
  p_student_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_lesson_type text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_business_entity_id uuid DEFAULT NULL
)
RETURNS TABLE (
  planned_hours numeric,actual_hours numeric,planned_fee_jpy numeric,
  actual_fee_jpy numeric,completed_count bigint,cancelled_count bigint,
  pending_makeup_count bigint,record_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
  WITH filtered AS (
    SELECT lesson.lesson_type,lesson.status,
      coalesce(lesson.is_billable,false) AS is_billable,
      coalesce(lesson.duration_hours,0)::numeric AS duration_hours,
      coalesce(lesson.lesson_fee,
        coalesce(lesson.unit_price,0)*coalesce(lesson.duration_hours,0),0
      )::numeric AS fee_jpy
    FROM public.school_list_r1d_e_c_student_month_lessons(
      NULL,p_year_month
    ) resolved
    JOIN public.school_lesson_records lesson ON lesson.id=resolved.lesson_id
    WHERE (p_student_id IS NULL OR lesson.student_id=p_student_id)
      AND (p_teacher_id IS NULL OR lesson.teacher_id=p_teacher_id)
      AND (p_subject_id IS NULL OR lesson.subject_id=p_subject_id)
      AND (p_lesson_type IS NULL OR lesson.lesson_type=p_lesson_type)
      AND (p_status IS NULL OR lesson.status=p_status)
      AND (p_business_entity_id IS NULL
           OR lesson.business_entity_id=p_business_entity_id)
      AND NOT (lesson.lesson_type='planned' AND lesson.voided_at IS NOT NULL)
  )
  SELECT
    coalesce(sum(duration_hours) FILTER(WHERE lesson_type='planned'),0)::numeric,
    coalesce(sum(duration_hours) FILTER(WHERE lesson_type='actual'
      AND is_billable AND status IN ('completed','makeup','makeup_completed')),0)::numeric,
    coalesce(sum(fee_jpy) FILTER(WHERE lesson_type='planned'),0)::numeric,
    coalesce(sum(fee_jpy) FILTER(WHERE lesson_type='actual'
      AND is_billable AND status IN ('completed','makeup','makeup_completed')),0)::numeric,
    count(*) FILTER(WHERE lesson_type='actual' AND is_billable
      AND status IN ('completed','makeup','makeup_completed'))::bigint,
    count(*) FILTER(WHERE lesson_type='actual' AND status='cancelled')::bigint,
    count(*) FILTER(WHERE lesson_type='planned'
      AND status='pending_makeup')::bigint,
    count(*)::bigint
  FROM filtered;
$function$;

COMMENT ON FUNCTION public.school_get_lesson_management_stats(
  text,uuid,uuid,uuid,text,text,uuid
) IS 'R2-F-F2-B compatibility statistics using the existing authoritative student-month resolver; raw lesson year_month never filters production rows.';

CREATE OR REPLACE FUNCTION public.school_list_open_lesson_credit_sources(
  p_from_month text,p_to_month text,p_target_month text
)
RETURNS TABLE (
  id uuid,lesson_date date,year_month text,student_id uuid,teacher_id uuid,
  subject_id uuid,business_entity_id uuid,start_time text,end_time text,
  duration_hours numeric,lesson_content text,note text,lesson_count integer,
  unit_price numeric,lesson_delivery_mode text,lesson_venue text,
  remaining_hours numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
  WITH args AS (
    SELECT nullif(trim(coalesce(p_from_month,'')),'') AS from_month,
      nullif(trim(coalesce(p_to_month,'')),'') AS to_month,
      nullif(trim(coalesce(p_target_month,'')),'') AS target_month
  ), sources AS (
    SELECT p.id,p.lesson_date,
      public.school_resolve_r1d_e_c_lesson_student_month(p.id) AS source_month,
      p.student_id,p.teacher_id,p.subject_id,p.business_entity_id,
      p.start_time,p.end_time,p.duration_hours,p.lesson_content,p.note,
      p.lesson_count,p.unit_price,p.lesson_delivery_mode,p.lesson_venue,
      greatest(coalesce(p.duration_hours,0)-coalesce(sum(a.duration_hours)
        FILTER(WHERE a.lesson_type='actual'
          AND a.status IN ('completed','makeup_completed')),0),0)::numeric
        AS remaining_hours
    FROM public.school_lesson_records p
    CROSS JOIN args x
    LEFT JOIN public.school_lesson_records a
      ON a.planned_lesson_id=p.id AND a.app_type='school'
    WHERE p.app_type='school' AND p.lesson_type='planned'
      AND p.status='pending_makeup' AND p.voided_at IS NULL
      AND x.from_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.to_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.from_month<=x.to_month AND x.to_month<=x.target_month
      AND public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          BETWEEN x.from_month AND x.to_month
      AND public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          <=x.target_month
    GROUP BY p.id
  )
  SELECT s.id,s.lesson_date,s.source_month AS year_month,s.student_id,
    s.teacher_id,s.subject_id,s.business_entity_id,s.start_time,s.end_time,
    s.duration_hours,s.lesson_content,s.note,s.lesson_count,s.unit_price,
    s.lesson_delivery_mode,s.lesson_venue,s.remaining_hours
  FROM sources s
  WHERE s.remaining_hours>0
  ORDER BY s.source_month,s.lesson_date,s.lesson_count NULLS LAST,
    s.start_time NULLS LAST,s.id;
$function$;

COMMENT ON FUNCTION public.school_list_open_lesson_credit_sources(text,text,text)
IS 'R2-F-F2-B compatibility contract: returned year_month is the existing resolver output, never raw planned year_month; remaining-credit rules are unchanged.';

CREATE OR REPLACE FUNCTION public.school_resolve_lesson_student_month_authoritative(
  p_lesson_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id=p_lesson_id AND lesson.app_type='school'
  ) THEN
    RAISE EXCEPTION 'LESSON_NOT_FOUND';
  END IF;
  RETURN public.school_resolve_r1d_e_c_lesson_student_month(p_lesson_id);
END
$function$;

REVOKE ALL ON FUNCTION
  public.school_resolve_lesson_student_month_authoritative(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.school_resolve_lesson_student_month_authoritative(uuid)
  TO anon,authenticated,service_role;
COMMENT ON FUNCTION
  public.school_resolve_lesson_student_month_authoritative(uuid) IS
  'Read-only R2-F-F2-B wrapper over the existing R1D-E-C authoritative lesson student-month resolver; no fallback or second month policy.';

DO $verify$
BEGIN
  IF position('school_resolve_planned_billing_attribution' IN pg_get_functiondef(
       'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure
     ))=0
     OR position('school_resolve_planned_billing_attribution' IN pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     ))=0
     OR position('school_resolve_planned_billing_attribution' IN pg_get_functiondef(
       'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure
     ))=0
     OR position('v_lesson.lesson_type = ''planned'' then v_old_year_month' IN
       pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     ))=0
     OR position('school_resolve_r1d_e_c_lesson_student_month' IN
       pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN
       pg_get_functiondef(
       'public.school_get_lesson_management_stats(text,uuid,uuid,uuid,text,text,uuid)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_OBJECT_VERIFICATION_FAILED';
  END IF;
END
$verify$;

SELECT p.oid::regprocedure::text AS function_signature,
  md5(pg_get_functiondef(p.oid)) AS function_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
  'school_create_planned_lesson_record_r1d_f1_legacy_core',
  'school_generate_planned_lessons_batch_r1d_f1_legacy_core',
  'school_import_lesson_records_batch_r1d_f1_legacy_core',
  'school_update_lesson_record_guarded',
  'school_create_actual_lesson_from_planned',
  'school_create_partial_completed_actual_from_planned',
  'school_create_cancelled_actual_lesson_from_planned',
  'school_delete_fresh_planned_lesson','school_void_planned_lesson',
  'school_get_lesson_management_stats_filtered',
  'school_get_lesson_management_stats',
  'school_list_open_lesson_credit_sources',
  'school_resolve_lesson_student_month_authoritative'
)
ORDER BY 1;

\if :r2_f_f2_b_commit
  COMMIT;
\else
  ROLLBACK;
\endif
