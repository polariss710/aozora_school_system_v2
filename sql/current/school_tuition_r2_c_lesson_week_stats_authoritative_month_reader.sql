-- R2-C minimal read-only lesson week statistics correction.
-- Required psql variable: r2_c_reader_commit=0 rehearsal or 1 deploy.
-- Keeps the existing signature/return contract/ACL and makes student month
-- and occurrence-week predicates cumulative instead of mutually exclusive.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_c_reader_commit}
\else
  \echo 'R2_C_READER_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'5a4563357fcf676ed853b69115dab101'
     OR (SELECT prosecdef FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)
     OR (SELECT provolatile FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)<>'s'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)
       IS DISTINCT FROM '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_C_READER_PREFLIGHT_DEFINITION_OR_ACL_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.school_get_lesson_management_stats_filtered(
  p_year_month text,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_lesson_type text,
  p_status text,
  p_business_entity_id uuid,
  p_is_billable boolean,
  p_keyword text,
  p_week_start date
)
RETURNS TABLE (
  planned_hours numeric,actual_hours numeric,planned_fee_jpy numeric,
  actual_fee_jpy numeric,completed_count bigint,cancelled_count bigint,
  pending_makeup_count bigint,record_count bigint,
  cross_month_makeup_completed_count bigint,
  cross_month_makeup_completed_hours numeric,
  completed_lesson_count bigint,planned_uncompleted_count bigint
)
LANGUAGE sql
STABLE
SET search_path=public
AS $function$
  WITH normalized AS (
    SELECT nullif(trim(coalesce(p_keyword,'')),'') AS keyword,
      nullif(trim(coalesce(p_status,'')),'') AS status_filter,
      nullif(trim(coalesce(p_lesson_type,'')),'') AS lesson_type_filter
  ),
  filtered AS (
    SELECT l.id,l.planned_lesson_id,l.lesson_type,l.status,l.year_month,
      coalesce(l.is_billable,false) AS is_billable,
      coalesce(l.duration_hours,0)::numeric AS duration_hours,
      coalesce(l.lesson_fee,
        coalesce(l.unit_price,0)*coalesce(l.duration_hours,0),0)::numeric AS fee_jpy,
      l.voided_at
    FROM public.school_lesson_records l
    LEFT JOIN public.school_students st ON st.id=l.student_id
    LEFT JOIN public.school_teachers te ON te.id=l.teacher_id
    LEFT JOIN public.school_subjects su ON su.id=l.subject_id
    LEFT JOIN public.school_business_entities be ON be.id=l.business_entity_id
    CROSS JOIN normalized n
    WHERE l.app_type='school'
      AND (p_year_month IS NULL OR l.year_month=p_year_month)
      AND (p_week_start IS NULL OR (
        l.lesson_date>=p_week_start AND l.lesson_date<p_week_start+7
      ))
      AND (p_student_id IS NULL OR l.student_id=p_student_id)
      AND (p_teacher_id IS NULL OR l.teacher_id=p_teacher_id)
      AND (p_subject_id IS NULL OR l.subject_id=p_subject_id)
      AND (n.lesson_type_filter IS NULL OR l.lesson_type=n.lesson_type_filter)
      AND (p_business_entity_id IS NULL
        OR l.business_entity_id=p_business_entity_id)
      AND (p_is_billable IS NULL
        OR coalesce(l.is_billable,false)=p_is_billable)
      AND ((n.status_filter='voided' AND l.lesson_type='planned'
            AND l.voided_at IS NOT NULL)
        OR (coalesce(n.status_filter,'')<>'voided'
          AND NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
          AND (n.status_filter IS NULL OR l.status=n.status_filter)))
      AND (n.keyword IS NULL OR lower(concat_ws(' ',
        coalesce(st.display_name,st.name),coalesce(te.display_name,te.name),
        su.name,be.name,l.lesson_content,l.note,l.import_source
      )) LIKE '%'||lower(n.keyword)||'%')
  ),
  cross_month_makeup_completed AS (
    SELECT actual.id,actual.duration_hours
    FROM filtered actual
    JOIN public.school_lesson_records source
      ON source.id=actual.planned_lesson_id
    WHERE actual.lesson_type='actual'
      AND actual.status='makeup_completed'
      AND actual.planned_lesson_id IS NOT NULL
      AND actual.voided_at IS NULL
      AND source.app_type='school'
      AND source.lesson_type='planned'
      AND source.status='pending_makeup'
      AND source.voided_at IS NULL
      AND source.year_month<>actual.year_month
  )
  SELECT
    coalesce(sum(duration_hours) FILTER (WHERE lesson_type='planned'),0)::numeric,
    coalesce(sum(duration_hours) FILTER (WHERE lesson_type='actual'
      AND is_billable AND status IN ('completed','makeup','makeup_completed')),0)::numeric,
    coalesce(sum(fee_jpy) FILTER (WHERE lesson_type='planned'),0)::numeric,
    coalesce(sum(fee_jpy) FILTER (WHERE lesson_type='actual'
      AND is_billable AND status IN ('completed','makeup','makeup_completed')),0)::numeric,
    count(*) FILTER (WHERE lesson_type='actual' AND is_billable
      AND status IN ('completed','makeup','makeup_completed'))::bigint,
    count(*) FILTER (WHERE lesson_type='actual' AND status='cancelled')::bigint,
    count(*) FILTER (WHERE lesson_type='planned' AND status='pending_makeup')::bigint,
    count(*)::bigint,
    (SELECT count(*) FROM cross_month_makeup_completed)::bigint,
    (SELECT coalesce(sum(duration_hours),0)::numeric
     FROM cross_month_makeup_completed),
    count(*) FILTER (WHERE lesson_type='actual' AND status='completed'
      AND voided_at IS NULL)::bigint,
    count(*) FILTER (WHERE lesson_type='planned' AND status='planned'
      AND voided_at IS NULL)::bigint
  FROM filtered
$function$;

COMMENT ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) IS 'R2-C read-only lesson statistics. Student settlement month and optional Monday-starting occurrence week are cumulative filters; the week never replaces the authoritative year_month predicate.';

REVOKE ALL ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) TO anon,authenticated,service_role;

DO $verify$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  ) INTO STRICT v_definition;
  RAISE NOTICE 'R2_C_READER_CHECKS month_null=% month_eq=% week_null=% week_gte=% week_lt=% old_branch=% acl=%',
    position('p_year_month IS NULL' IN v_definition)>0,
    position('l.year_month=p_year_month' IN v_definition)>0,
    position('p_week_start IS NULL' IN v_definition)>0,
    position('l.lesson_date>=p_week_start' IN v_definition)>0,
    position('l.lesson_date<p_week_start+7' IN v_definition)>0,
    position('p_week_start IS NOT NULL' IN v_definition)>0,
    (SELECT proacl::text FROM pg_proc WHERE oid=
      'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure);
  IF position('p_year_month IS NULL' IN v_definition)=0
     OR position('l.year_month=p_year_month' IN v_definition)=0
     OR position('p_week_start IS NULL' IN v_definition)=0
     OR position('l.lesson_date>=p_week_start' IN v_definition)=0
     OR position('l.lesson_date<p_week_start+7' IN v_definition)=0
     OR position('p_week_start IS NOT NULL' IN v_definition)>0
     OR (SELECT prosecdef FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)
     OR (SELECT provolatile FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)<>'s'
     OR (SELECT proacl::text FROM pg_proc WHERE oid=
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure)
       IS DISTINCT FROM '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'R2_C_READER_VERIFY_DEFINITION_OR_ACL_MISMATCH';
  END IF;
  RAISE NOTICE 'R2_C_READER_FUNCTION_MD5=%',md5(v_definition);
END
$verify$;

\if :r2_c_reader_commit
  COMMIT;
  \echo 'R2_C_READER_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_C_READER_REHEARSAL_ROLLED_BACK'
\endif
