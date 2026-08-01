-- School V2 R2-F-F2: planned billing-week invariant and authoritative lesson-management reader.
-- Required psql variable: r2_f_f2_cutover_commit=0 rehearsal or 1 deploy.
-- Code-only DDL: replaces one trigger function, adds two validated checks,
-- adds one read RPC, and replaces the two lesson-management stats overloads.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_f2_cutover_commit}
\else
  \echo 'R2_F_F2_CUTOVER_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     ))<>'08f3c60890d4afab8d9c730eec286c8d' THEN
    RAISE EXCEPTION 'R2_F_F2_PLANNED_ATTRIBUTION_TRIGGER_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_enforce_r2_e_planned_aircon()'::regprocedure
     ))<>'33d0a36904ef02f595c69caafefe4f92' THEN
    RAISE EXCEPTION 'R2_F_F2_AIRCON_TRIGGER_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'f535f4649f870097a350208b64da643e'
     OR md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text)'::regprocedure
     ))<>'e77f203f3249f0bb51cc925180cc5b43' THEN
    RAISE EXCEPTION 'R2_F_F2_STATS_BASELINE_DRIFT';
  END IF;
  IF to_regprocedure(
       'public.school_list_lesson_management_records_authoritative(text,date)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'R2_F_F2_READER_ALREADY_EXISTS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.school_lesson_records'::regclass
      AND conname IN (
        'school_lesson_records_planned_student_month_match_chk',
        'school_lesson_records_planned_date_within_billing_week_chk'
      )
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_CONSTRAINT_ALREADY_EXISTS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type='planned'
      AND lesson.billing_month IS NOT NULL
      AND lesson.student_settlement_month IS DISTINCT FROM lesson.billing_month
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type='planned'
      AND lesson.billing_week_start_date IS NOT NULL
      AND (
        lesson.lesson_date IS NULL
        OR lesson.lesson_date NOT BETWEEN lesson.billing_week_start_date
                                      AND lesson.billing_week_start_date+6
      )
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_EXISTING_PLANNED_INVARIANT_VIOLATION';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F2_GATE_BASELINE_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.school_enforce_r1d_f1_planned_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_attribution record;
  v_duration numeric;
  v_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.lesson_type IS DISTINCT FROM NEW.lesson_type
     AND (OLD.lesson_type = 'planned' OR NEW.lesson_type = 'planned') THEN
    RAISE EXCEPTION 'R1D_F1_PLANNED_LESSON_TYPE_IMMUTABLE';
  END IF;

  IF NEW.lesson_type IS DISTINCT FROM 'planned' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.lesson_date IS NULL THEN
      RAISE EXCEPTION 'R1D_F1_NEW_PLANNED_LESSON_DATE_REQUIRED';
    END IF;

    IF NEW.import_source LIKE 'lesson_planned_batch_generator%' THEN
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NULL,NEW.lesson_date);
    ELSE
      SELECT * INTO STRICT v_attribution
      FROM public.school_resolve_planned_billing_attribution(NEW.lesson_date,NULL);
    END IF;

    NEW.billing_week_start_date := v_attribution.billing_week_start_date;
    NEW.billing_month := v_attribution.billing_month;
    NEW.student_settlement_month := v_attribution.student_settlement_month;
    NEW.billing_month_source := v_attribution.billing_month_source;
    NEW.billing_month_decided_at := statement_timestamp();

    IF NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                               AND NEW.billing_week_start_date+6 THEN
      RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
    END IF;

    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_PLANNED_DURATION_NOT_DB_AUTHORITATIVE';
    END IF;
    RETURN NEW;
  END IF;

  SELECT evidence.* INTO v_evidence
  FROM public.school_legacy_planned_settlement_evidence evidence
  WHERE evidence.planned_lesson_id = OLD.id;

  IF FOUND THEN
    IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
         OLD.student_settlement_month,OLD.billing_month_source,
         OLD.billing_month_decided_at) <> 0
       OR num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
         NEW.student_settlement_month,NEW.billing_month_source,
         NEW.billing_month_decided_at) <> 0
       OR NEW.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR NEW.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR NEW.year_month IS DISTINCT FROM v_evidence.legacy_student_settlement_month
       OR md5(concat_ws('|',NEW.id::text,coalesce(NEW.student_id::text,'<NULL>'),
            coalesce(NEW.business_entity_id::text,'<NULL>'),
            coalesce(NEW.year_month,'<NULL>'),NEW.lesson_type,NEW.app_type))
          IS DISTINCT FROM v_evidence.lesson_identity_md5 THEN
      RAISE EXCEPTION 'R1D_F1_LEGACY_PLANNED_IDENTITY_OR_NULL_BUNDLE_IMMUTABLE';
    END IF;
    IF NEW.lesson_date IS DISTINCT FROM OLD.lesson_date THEN
      RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;

  IF num_nonnulls(OLD.billing_month,OLD.billing_week_start_date,
       OLD.student_settlement_month,OLD.billing_month_source,
       OLD.billing_month_decided_at) <> 5 THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_REQUIRED';
  END IF;
  IF NEW.billing_month IS DISTINCT FROM OLD.billing_month
     OR NEW.billing_week_start_date IS DISTINCT FROM OLD.billing_week_start_date
     OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
     OR NEW.billing_month_source IS DISTINCT FROM OLD.billing_month_source
     OR NEW.billing_month_decided_at IS DISTINCT FROM OLD.billing_month_decided_at THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
  END IF;
  IF NEW.student_settlement_month IS DISTINCT FROM NEW.billing_month
     OR NEW.billing_month IS DISTINCT FROM
          to_char(NEW.billing_week_start_date,'YYYY-MM') THEN
    RAISE EXCEPTION 'PLANNED_BILLING_ATTRIBUTION_IMMUTABLE';
  END IF;
  IF NEW.lesson_date IS NULL
     OR NEW.lesson_date NOT BETWEEN NEW.billing_week_start_date
                               AND NEW.billing_week_start_date+6 THEN
    RAISE EXCEPTION 'PLANNED_DATE_OUTSIDE_BILLING_WEEK';
  END IF;

  IF OLD.billing_month_source IN (
       'scheduled_date_at_create','explicit_billing_week_at_create'
     ) THEN
    v_duration := public.school_resolve_planned_duration(
      NEW.start_time::text,
      NEW.end_time::text,
      CASE WHEN NEW.start_time IS NULL AND NEW.end_time IS NULL
           THEN NEW.duration_hours ELSE NULL END
    );
    IF NEW.duration_hours IS DISTINCT FROM v_duration THEN
      RAISE EXCEPTION 'R1D_F1_CANONICAL_PLANNED_DURATION_INVALID';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.school_enforce_r1d_f1_planned_attribution()
  FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.school_enforce_r1d_f1_planned_attribution() IS
  'R1D-F1/R2-F-F2 planned attribution authority: canonical creation, immutable billing month/week/student month, week-bounded scheduled-date edits, and fail-closed legacy date edits.';

ALTER TABLE public.school_lesson_records
  ADD CONSTRAINT school_lesson_records_planned_student_month_match_chk
  CHECK (
    lesson_type IS DISTINCT FROM 'planned'
    OR billing_month IS NULL
    OR student_settlement_month = billing_month
  );

ALTER TABLE public.school_lesson_records
  ADD CONSTRAINT school_lesson_records_planned_date_within_billing_week_chk
  CHECK (
    lesson_type IS DISTINCT FROM 'planned'
    OR billing_week_start_date IS NULL
    OR (
      lesson_date IS NOT NULL
      AND lesson_date BETWEEN billing_week_start_date
                          AND billing_week_start_date+6
    )
  );

COMMENT ON CONSTRAINT school_lesson_records_planned_student_month_match_chk
  ON public.school_lesson_records IS
  'R2-F-F2: a canonical planned student settlement month must equal its immutable billing month.';
COMMENT ON CONSTRAINT school_lesson_records_planned_date_within_billing_week_chk
  ON public.school_lesson_records IS
  'R2-F-F2: a canonical planned scheduled lesson date must stay within its immutable Monday-start billing week.';

CREATE FUNCTION public.school_list_lesson_management_records_authoritative(
  p_year_month text,
  p_week_start date DEFAULT NULL
)
RETURNS SETOF public.school_lesson_records
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
BEGIN
  IF p_year_month IS NULL
     OR p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'LESSON_MANAGEMENT_MONTH_INVALID';
  END IF;
  IF p_week_start IS NOT NULL AND (
       extract(isodow FROM p_week_start)::integer<>1
       OR to_char(p_week_start,'YYYY-MM')<>p_year_month
     ) THEN
    RAISE EXCEPTION 'LESSON_MANAGEMENT_BILLING_WEEK_INVALID';
  END IF;

  RETURN QUERY
  WITH authority AS MATERIALIZED (
    SELECT resolved.lesson_id,resolved.attribution_class
    FROM public.school_list_r1d_e_c_student_month_lessons(NULL,p_year_month) resolved
  )
  SELECT lesson.*
  FROM authority
  JOIN public.school_lesson_records lesson ON lesson.id=authority.lesson_id
  LEFT JOIN public.school_lesson_records source
    ON source.id=lesson.planned_lesson_id
  WHERE lesson.app_type='school'
    AND (
      p_week_start IS NULL
      OR CASE
        WHEN lesson.lesson_type='planned'
             AND lesson.billing_week_start_date IS NOT NULL
          THEN lesson.billing_week_start_date=p_week_start
        WHEN lesson.lesson_type='planned'
          THEN false
        WHEN lesson.lesson_type='actual'
             AND source.lesson_type='planned'
             AND source.billing_week_start_date IS NOT NULL
          THEN source.billing_week_start_date=p_week_start
        ELSE lesson.lesson_date BETWEEN p_week_start AND p_week_start+6
      END
    )
  ORDER BY lesson.lesson_date,lesson.lesson_count NULLS LAST,
           lesson.start_time NULLS LAST,lesson.created_at,lesson.id;
END
$function$;

REVOKE ALL ON FUNCTION
  public.school_list_lesson_management_records_authoritative(text,date)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.school_list_lesson_management_records_authoritative(text,date)
  TO anon,authenticated,service_role;
COMMENT ON FUNCTION
  public.school_list_lesson_management_records_authoritative(text,date) IS
  'R2-F-F2 read-only lesson-management source: authoritative student month for all rows, immutable billing month/week for canonical planned rows, and source-planned week pairing for actual rows.';

CREATE OR REPLACE FUNCTION public.school_get_lesson_management_stats_filtered(
  p_year_month text,p_student_id uuid,p_teacher_id uuid,p_subject_id uuid,
  p_lesson_type text,p_status text,p_business_entity_id uuid,
  p_is_billable boolean,p_keyword text,p_week_start date
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
  ), filtered AS (
    SELECT lesson.id,lesson.planned_lesson_id,lesson.lesson_type,lesson.status,
      lesson.year_month,lesson.student_settlement_month,lesson.billing_month,
      coalesce(lesson.is_billable,false) AS is_billable,
      coalesce(lesson.duration_hours,0)::numeric AS duration_hours,
      coalesce(lesson.lesson_fee,
        coalesce(lesson.unit_price,0)*coalesce(lesson.duration_hours,0),0
      )::numeric AS fee_jpy,
      lesson.voided_at
    FROM public.school_list_lesson_management_records_authoritative(
      p_year_month,p_week_start
    ) lesson
    LEFT JOIN public.school_students student ON student.id=lesson.student_id
    LEFT JOIN public.school_teachers teacher ON teacher.id=lesson.teacher_id
    LEFT JOIN public.school_subjects subject ON subject.id=lesson.subject_id
    LEFT JOIN public.school_business_entities entity
      ON entity.id=lesson.business_entity_id
    CROSS JOIN normalized n
    WHERE (p_student_id IS NULL OR lesson.student_id=p_student_id)
      AND (p_teacher_id IS NULL OR lesson.teacher_id=p_teacher_id)
      AND (p_subject_id IS NULL OR lesson.subject_id=p_subject_id)
      AND (n.lesson_type_filter IS NULL
           OR lesson.lesson_type=n.lesson_type_filter)
      AND (p_business_entity_id IS NULL
           OR lesson.business_entity_id=p_business_entity_id)
      AND (p_is_billable IS NULL
           OR coalesce(lesson.is_billable,false)=p_is_billable)
      AND (
        (n.status_filter='voided' AND lesson.lesson_type='planned'
         AND lesson.voided_at IS NOT NULL)
        OR (coalesce(n.status_filter,'')<>'voided'
          AND NOT (lesson.lesson_type='planned'
                   AND lesson.voided_at IS NOT NULL)
          AND (n.status_filter IS NULL OR lesson.status=n.status_filter))
      )
      AND (n.keyword IS NULL OR lower(concat_ws(' ',
        coalesce(student.display_name,student.name),
        coalesce(teacher.display_name,teacher.name),subject.name,entity.name,
        lesson.lesson_content,lesson.note,lesson.import_source
      )) LIKE '%'||lower(n.keyword)||'%')
  ), cross_month_makeup_completed AS (
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
      AND public.school_resolve_r1d_e_c_lesson_student_month(source.id)
          <>public.school_resolve_r1d_e_c_lesson_student_month(actual.id)
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
    count(*) FILTER(WHERE lesson_type='planned' AND status='pending_makeup')::bigint,
    count(*)::bigint,
    (SELECT count(*) FROM cross_month_makeup_completed)::bigint,
    (SELECT coalesce(sum(duration_hours),0)::numeric
     FROM cross_month_makeup_completed),
    count(*) FILTER(WHERE lesson_type='actual' AND status='completed'
      AND voided_at IS NULL)::bigint,
    count(*) FILTER(WHERE lesson_type='planned' AND status='planned'
      AND voided_at IS NULL)::bigint
  FROM filtered;
$function$;

CREATE OR REPLACE FUNCTION public.school_get_lesson_management_stats_filtered(
  p_year_month text,p_student_id uuid DEFAULT NULL,p_teacher_id uuid DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,p_lesson_type text DEFAULT NULL,
  p_status text DEFAULT NULL,p_business_entity_id uuid DEFAULT NULL,
  p_is_billable boolean DEFAULT NULL,p_keyword text DEFAULT NULL
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
  SELECT * FROM public.school_get_lesson_management_stats_filtered(
    p_year_month,p_student_id,p_teacher_id,p_subject_id,p_lesson_type,p_status,
    p_business_entity_id,p_is_billable,p_keyword,NULL::date
  );
$function$;

REVOKE ALL ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text
) TO anon,authenticated,service_role;

COMMENT ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text,date
) IS 'R2-F-F2 authoritative lesson-management statistics; planned uses billing month/week and actual uses resolved student month/source planned week.';
COMMENT ON FUNCTION public.school_get_lesson_management_stats_filtered(
  text,uuid,uuid,uuid,text,text,uuid,boolean,text
) IS 'R2-F-F2 month-only compatibility overload delegating to the authoritative lesson-management statistics reader.';

DO $verify$
BEGIN
  IF position('PLANNED_DATE_OUTSIDE_BILLING_WEEK' IN pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     ))=0
     OR position('PLANNED_BILLING_ATTRIBUTION_IMMUTABLE' IN pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     ))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_list_lesson_management_records_authoritative(text,date)'::regprocedure
     ))=0
     OR position('billing_week_start_date=p_week_start' IN pg_get_functiondef(
       'public.school_list_lesson_management_records_authoritative(text,date)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R2_F_F2_OBJECT_VERIFICATION_FAILED';
  END IF;
  IF (SELECT count(*) FROM pg_constraint
      WHERE conrelid='public.school_lesson_records'::regclass
        AND conname IN (
          'school_lesson_records_planned_student_month_match_chk',
          'school_lesson_records_planned_date_within_billing_week_chk'
        ) AND convalidated)<>2 THEN
    RAISE EXCEPTION 'R2_F_F2_CONSTRAINT_VERIFICATION_FAILED';
  END IF;
END
$verify$;

\if :r2_f_f2_cutover_commit
  COMMIT;
\else
  ROLLBACK;
\endif
