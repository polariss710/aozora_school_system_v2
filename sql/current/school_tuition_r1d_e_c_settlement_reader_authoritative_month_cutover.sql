-- School V2 tuition P0 R1D-E-C: authoritative student settlement reader cutover.
-- Required psql variable: r1d_e_c_commit=0 for rehearsal or 1 for deployment.
-- Replaces only the student settlement resolver/reader/lock boundary.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_c_commit}
\else
  \echo 'R1D_E_C_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';

-- Freeze lesson writers while the old reader baseline is checked and the
-- resolver plus readers are replaced. No business row is changed.
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

\set r1d_e_b2_postdeploy_existing_tx 1
\ir school_tuition_r1d_e_b2_actual_writer_settlement_month_cutover_postdeploy.sql
\unset r1d_e_b2_postdeploy_existing_tx

DO $preflight$
BEGIN
  IF to_regprocedure('public.school_r1d_e_c_settlement_reader_cutover_version()')
       IS NOT NULL
     OR to_regprocedure(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)') IS NOT NULL
     OR to_regprocedure(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'R1D_E_C_TARGET_OBJECT_ALREADY_EXISTS';
  END IF;
END
$preflight$;

CREATE FUNCTION public.school_r1d_e_c_settlement_reader_cutover_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SECURITY INVOKER
SET search_path=pg_catalog
AS $function$
  SELECT 'r1d_e_c_settlement_reader_v1'::text
$function$;

REVOKE ALL ON FUNCTION
  public.school_r1d_e_c_settlement_reader_cutover_version()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(
  p_lesson_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_lesson public.school_lesson_records%ROWTYPE;
  v_source public.school_lesson_records%ROWTYPE;
  v_planned_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
  v_actual_evidence public.school_legacy_actual_settlement_evidence%ROWTYPE;
  v_source_month text;
  v_duration numeric;
  v_bundle_count integer;
BEGIN
  IF p_lesson_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_ID_REQUIRED';
  END IF;

  SELECT lesson.* INTO v_lesson
  FROM public.school_lesson_records lesson
  WHERE lesson.id=p_lesson_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_NOT_FOUND';
  END IF;
  IF v_lesson.app_type IS DISTINCT FROM 'school'
     OR v_lesson.lesson_type NOT IN ('planned','actual')
     OR v_lesson.student_id IS NULL
     OR v_lesson.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_C_LESSON_BASE_IDENTITY_INVALID';
  END IF;

  IF v_lesson.lesson_type='planned' THEN
    v_bundle_count:=num_nonnulls(v_lesson.billing_month,
      v_lesson.billing_week_start_date,v_lesson.student_settlement_month,
      v_lesson.billing_month_source,v_lesson.billing_month_decided_at);

    IF v_bundle_count=5 THEN
      IF v_lesson.billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
         OR v_lesson.student_settlement_month IS DISTINCT FROM
              v_lesson.billing_month
         OR extract(isodow FROM v_lesson.billing_week_start_date)<>1
         OR to_char(v_lesson.billing_week_start_date,'YYYY-MM')<>
              v_lesson.billing_month
         OR v_lesson.billing_month_source NOT IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
           'scheduled_date_at_create','explicit_billing_week_at_create') THEN
        RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_ATTRIBUTION_INVALID';
      END IF;

      IF v_lesson.billing_month_source IN (
           'scheduled_date_at_create','explicit_billing_week_at_create') THEN
        IF v_lesson.lesson_date IS NULL THEN
          RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_DATE_REQUIRED';
        END IF;
        v_duration:=public.school_resolve_planned_duration(
          v_lesson.start_time::text,
          v_lesson.end_time::text,
          CASE WHEN v_lesson.start_time IS NULL AND v_lesson.end_time IS NULL
               THEN v_lesson.duration_hours ELSE NULL END
        );
        IF v_lesson.duration_hours IS DISTINCT FROM v_duration THEN
          RAISE EXCEPTION 'R1D_E_C_CANONICAL_PLANNED_DURATION_INVALID';
        END IF;
      END IF;
      RETURN v_lesson.student_settlement_month;
    END IF;

    IF v_bundle_count=0 THEN
      SELECT evidence.* INTO v_planned_evidence
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=v_lesson.id;

      IF NOT FOUND
         OR v_planned_evidence.approved_manifest IS DISTINCT FROM true
         OR v_planned_evidence.evidence_source<>
              'r1d_e_b1_fixed_legacy_279'
         OR v_planned_evidence.evidence_version<>
              'legacy_settlement_evidence_v1'
         OR v_lesson.student_id IS DISTINCT FROM
              v_planned_evidence.student_id_snapshot
         OR v_lesson.business_entity_id IS DISTINCT FROM
              v_planned_evidence.business_entity_id_snapshot
         OR v_lesson.year_month IS DISTINCT FROM
              v_planned_evidence.legacy_student_settlement_month
         OR v_planned_evidence.lesson_identity_md5 IS DISTINCT FROM
              md5(concat_ws('|',v_lesson.id::text,
                coalesce(v_lesson.student_id::text,'<NULL>'),
                coalesce(v_lesson.business_entity_id::text,'<NULL>'),
                coalesce(v_lesson.year_month,'<NULL>'),
                v_lesson.lesson_type,v_lesson.app_type)) THEN
        RAISE EXCEPTION 'R1D_E_C_LEGACY_PLANNED_EVIDENCE_MISMATCH';
      END IF;
      RETURN v_planned_evidence.legacy_student_settlement_month;
    END IF;

    RAISE EXCEPTION 'R1D_E_C_PARTIAL_PLANNED_ATTRIBUTION_REJECTED';
  END IF;

  SELECT evidence.* INTO v_actual_evidence
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE evidence.actual_lesson_id=v_lesson.id;

  IF FOUND THEN
    IF v_lesson.student_settlement_month IS NOT NULL
       OR v_actual_evidence.source_planned_lesson_id IS DISTINCT FROM
            v_lesson.planned_lesson_id
       OR v_actual_evidence.student_id_snapshot IS DISTINCT FROM
            v_lesson.student_id
       OR v_actual_evidence.business_entity_id_snapshot IS DISTINCT FROM
            v_lesson.business_entity_id
       OR v_actual_evidence.teacher_id_snapshot IS DISTINCT FROM
            v_lesson.teacher_id
       OR v_actual_evidence.subject_id_snapshot IS DISTINCT FROM
            v_lesson.subject_id
       OR v_actual_evidence.legacy_year_month IS DISTINCT FROM
            v_lesson.year_month
       OR v_actual_evidence.teacher_settlement_month_snapshot IS DISTINCT FROM
            coalesce(v_lesson.teacher_settlement_month,
              to_char(v_lesson.lesson_date,'YYYY-MM'))
       OR v_actual_evidence.lesson_date_snapshot IS DISTINCT FROM
            v_lesson.lesson_date
       OR v_actual_evidence.evidence_source<>
            'r1d_e_b2_all_existing_actual_at_cutover'
       OR v_actual_evidence.evidence_version<>
            'actual_legacy_settlement_evidence_v1'
       OR v_actual_evidence.actual_identity_md5 IS DISTINCT FROM
            md5(concat_ws('|',v_lesson.id::text,
              v_lesson.planned_lesson_id::text,v_lesson.student_id::text,
              v_lesson.business_entity_id::text,
              coalesce(v_lesson.teacher_id::text,'<NULL>'),
              coalesce(v_lesson.subject_id::text,'<NULL>'),v_lesson.year_month,
              coalesce(v_lesson.teacher_settlement_month,
                to_char(v_lesson.lesson_date,'YYYY-MM')),
              v_lesson.lesson_date::text,v_lesson.lesson_type,v_lesson.app_type))
       OR v_actual_evidence.actual_full_row_md5 IS DISTINCT FROM
            md5(to_jsonb(v_lesson)::text) THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;
    RETURN v_actual_evidence.legacy_year_month;
  END IF;

  IF v_lesson.planned_lesson_id IS NULL
     OR v_lesson.student_settlement_month IS NULL
     OR v_lesson.student_settlement_month !~
          '^[0-9]{4}-(0[1-9]|1[0-2])$'
     OR v_lesson.year_month IS DISTINCT FROM
          v_lesson.student_settlement_month
     OR v_lesson.lesson_date IS NULL
     OR v_lesson.teacher_settlement_month IS DISTINCT FROM
          to_char(v_lesson.lesson_date,'YYYY-MM')
     OR num_nonnulls(v_lesson.billing_month,
          v_lesson.billing_week_start_date,v_lesson.billing_month_source,
          v_lesson.billing_month_decided_at)<>0 THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_ATTRIBUTION_INVALID';
  END IF;

  SELECT source.* INTO v_source
  FROM public.school_lesson_records source
  WHERE source.id=v_lesson.planned_lesson_id;

  IF NOT FOUND
     OR v_source.app_type IS DISTINCT FROM 'school'
     OR v_source.lesson_type IS DISTINCT FROM 'planned'
     OR v_source.voided_at IS NOT NULL
     OR v_source.student_id IS DISTINCT FROM v_lesson.student_id
     OR v_source.business_entity_id IS DISTINCT FROM
          v_lesson.business_entity_id THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_SOURCE_INVALID';
  END IF;

  v_source_month:=
    public.school_resolve_r1d_e_c_lesson_student_month(v_source.id);
  IF v_lesson.student_settlement_month IS DISTINCT FROM v_source_month THEN
    RAISE EXCEPTION 'R1D_E_C_CANONICAL_ACTUAL_SOURCE_MONTH_MISMATCH';
  END IF;

  RETURN v_lesson.student_settlement_month;
END
$function$;

REVOKE ALL ON FUNCTION
  public.school_resolve_r1d_e_c_lesson_student_month(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.school_list_r1d_e_c_student_month_lessons(
  p_student_id uuid,
  p_year_month text
)
RETURNS TABLE (
  lesson_id uuid,
  student_id uuid,
  business_entity_id uuid,
  authoritative_student_month text,
  attribution_class text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_lesson record;
  v_month text;
  v_class text;
BEGIN
  IF p_year_month IS NOT NULL
     AND p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R1D_E_C_TARGET_MONTH_INVALID';
  END IF;

  FOR v_lesson IN
    SELECT lesson.id,lesson.student_id,lesson.business_entity_id,
      lesson.lesson_type,
      num_nonnulls(lesson.billing_month,lesson.billing_week_start_date,
        lesson.student_settlement_month,lesson.billing_month_source,
        lesson.billing_month_decided_at) AS bundle_count,
      EXISTS (SELECT 1
              FROM public.school_legacy_actual_settlement_evidence evidence
              WHERE evidence.actual_lesson_id=lesson.id) AS legacy_actual
    FROM public.school_lesson_records lesson
    WHERE lesson.student_id IS NOT NULL
      AND (
        (p_student_id IS NULL AND lesson.app_type='school')
        OR (p_student_id IS NOT NULL AND lesson.student_id=p_student_id)
      )
    ORDER BY lesson.id
  LOOP
    v_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id);
    v_class:=CASE
      WHEN v_lesson.lesson_type='planned' AND v_lesson.bundle_count=5
        THEN 'canonical_planned'
      WHEN v_lesson.lesson_type='planned' THEN 'legacy_planned'
      WHEN v_lesson.legacy_actual THEN 'legacy_actual'
      ELSE 'canonical_actual'
    END;

    IF p_year_month IS NULL OR v_month=p_year_month THEN
      lesson_id:=v_lesson.id;
      student_id:=v_lesson.student_id;
      business_entity_id:=v_lesson.business_entity_id;
      authoritative_student_month:=v_month;
      attribution_class:=v_class;
      RETURN NEXT;
    END IF;
  END LOOP;
END
$function$;

REVOKE ALL ON FUNCTION
  public.school_list_r1d_e_c_student_month_lessons(uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.school_get_student_monthly_settlement_summary(
  p_student_id uuid,
  p_year_month text
)
RETURNS TABLE (
  student_id uuid,
  year_month text,
  exchange_rate numeric,
  carryover_cny numeric,
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  planned_fee_cny numeric,
  planned_total_cny numeric,
  actual_fee_jpy numeric,
  actual_fee_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  final_due_cny numeric,
  locked_carryover_cny numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
  WITH input_month AS (
    SELECT p_year_month AS year_month,
      to_char((to_date(p_year_month||'-01','YYYY-MM-DD')-
        interval '1 month')::date,'YYYY-MM') AS previous_year_month
    WHERE p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  student_base AS (
    SELECT s.id AS student_id,
      coalesce(s.preset_exchange_rate,0)::numeric AS exchange_rate,
      coalesce(s.previous_balance_cny,0)::numeric AS fallback_carryover_cny
    FROM public.school_students s
    WHERE s.id=p_student_id
  ),
  previous_locked_settlement AS (
    SELECT m.carryover_amount_cny
    FROM public.school_student_monthly_settlements m
    JOIN input_month im ON im.previous_year_month=m.year_month
    WHERE m.student_id=p_student_id AND m.settlement_status='locked'
    ORDER BY m.locked_at DESC NULLS LAST,m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  carryover AS (
    SELECT coalesce(
      (SELECT c.amount_cny
       FROM public.school_student_settlement_carryovers c
       WHERE c.student_id=p_student_id AND c.to_year_month=p_year_month
         AND coalesce(c.status,'active')='active'
       ORDER BY c.updated_at DESC NULLS LAST,c.created_at DESC NULLS LAST
       LIMIT 1),
      (SELECT pls.carryover_amount_cny FROM previous_locked_settlement pls),
      (SELECT fallback_carryover_cny FROM student_base),0)::numeric
      AS carryover_cny
  ),
  lessons AS (
    SELECT l.id,l.planned_lesson_id,l.lesson_type,l.status,
      coalesce(l.is_billable,false) AS is_billable,
      coalesce(l.duration_hours,0)::numeric AS duration_hours,
      coalesce(l.lesson_fee,
        coalesce(l.unit_price,0)*coalesce(l.duration_hours,0),0)::numeric
        AS fee_jpy
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id,p_year_month) resolved
    JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
    WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
  ),
  lesson_summary AS (
    SELECT
      coalesce(sum(f.duration_hours) FILTER (
        WHERE f.lesson_type='planned'),0)::numeric AS planned_hours,
      coalesce(sum(f.duration_hours) FILTER (
        WHERE f.lesson_type='actual' AND f.is_billable=true
          AND f.status IN ('completed','makeup','makeup_completed')),0)::numeric
        AS actual_hours,
      coalesce(sum(f.fee_jpy) FILTER (
        WHERE f.lesson_type='planned'),0)::numeric AS planned_fee_jpy,
      coalesce(sum(f.fee_jpy) FILTER (
        WHERE f.lesson_type='actual' AND f.is_billable=true
          AND f.status IN ('completed','makeup','makeup_completed')),0)::numeric
        AS actual_fee_jpy
    FROM lessons f
  ),
  income_summary AS (
    SELECT coalesce(sum(i.amount) FILTER (
      WHERE coalesce(i.payment_currency,i.currency)='JPY'),0)::numeric
      AS received_jpy,
      coalesce(sum(i.amount) FILTER (
      WHERE coalesce(i.payment_currency,i.currency)='CNY'),0)::numeric
      AS received_cny
    FROM public.school_income_records i
    WHERE i.student_id=p_student_id
      AND coalesce(i.settlement_month,i.year_month)=p_year_month
      AND i.income_category='tuition' AND i.status='received'
      AND coalesce(i.include_in_student_settlement,true)=true
  ),
  locked AS (
    SELECT m.carryover_amount_cny
    FROM public.school_student_monthly_settlements m
    WHERE m.student_id=p_student_id AND m.year_month=p_year_month
      AND m.settlement_status='locked'
    ORDER BY m.locked_at DESC NULLS LAST,m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  calculated AS (
    SELECT sb.student_id,p_year_month AS year_month,sb.exchange_rate,
      coalesce(c.carryover_cny,0)::numeric AS carryover_cny,
      coalesce(ls.planned_hours,0)::numeric AS planned_hours,
      coalesce(ls.actual_hours,0)::numeric AS actual_hours,
      coalesce(ls.planned_fee_jpy,0)::numeric AS planned_fee_jpy,
      (coalesce(ls.planned_fee_jpy,0)*sb.exchange_rate)::numeric
        AS planned_fee_cny,
      coalesce(ls.actual_fee_jpy,0)::numeric AS actual_fee_jpy,
      (coalesce(ls.actual_fee_jpy,0)*sb.exchange_rate)::numeric
        AS actual_fee_cny,
      coalesce(inc.received_jpy,0)::numeric AS received_jpy,
      coalesce(inc.received_cny,0)::numeric AS received_cny,
      (coalesce(inc.received_cny,0)+
        coalesce(inc.received_jpy,0)*sb.exchange_rate)::numeric
        AS received_equivalent_cny
    FROM student_base sb CROSS JOIN carryover c
    CROSS JOIN lesson_summary ls CROSS JOIN income_summary inc
  ),
  rounded AS (
    SELECT calc.student_id,calc.year_month,calc.exchange_rate,
      round(calc.carryover_cny,2)::numeric AS carryover_cny,
      calc.planned_hours,calc.actual_hours,calc.planned_fee_jpy,
      round(calc.planned_fee_cny,2)::numeric AS planned_fee_cny,
      calc.actual_fee_jpy,
      round(calc.actual_fee_cny,2)::numeric AS actual_fee_cny,
      calc.received_jpy,round(calc.received_cny,2)::numeric AS received_cny,
      round(calc.received_equivalent_cny,2)::numeric AS received_equivalent_cny
    FROM calculated calc
  )
  SELECT r.student_id,r.year_month,r.exchange_rate,r.carryover_cny,
    r.planned_hours,r.actual_hours,r.planned_fee_jpy,r.planned_fee_cny,
    round(r.planned_fee_cny+r.carryover_cny,2)::numeric AS planned_total_cny,
    r.actual_fee_jpy,r.actual_fee_cny,r.received_jpy,r.received_cny,
    r.received_equivalent_cny,
    round(r.planned_fee_cny+r.carryover_cny-r.received_equivalent_cny,2)::numeric
      AS final_due_cny,
    coalesce((SELECT round(l.carryover_amount_cny,2) FROM locked l),
      round(r.planned_fee_cny+r.carryover_cny-r.received_equivalent_cny,2))::numeric
      AS locked_carryover_cny
  FROM rounded r;
$function$;

COMMENT ON FUNCTION public.school_get_student_monthly_settlement_summary(uuid,text)
IS 'Returns the existing student settlement amount contract using the R1D-E-C fail-closed authoritative student-month resolver. CNY rounding, income, carryover, planned/actual and void semantics are unchanged.';

CREATE OR REPLACE FUNCTION public.school_get_student_monthly_settlement_preview(
  p_student_id uuid,
  p_year_month text
)
RETURNS TABLE (
  student_id uuid,
  year_month text,
  business_entity_id uuid,
  exchange_rate numeric,
  carryover_cny numeric,
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  planned_fee_cny numeric,
  planned_total_cny numeric,
  actual_fee_jpy numeric,
  actual_fee_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  final_due_cny numeric,
  adjustment_amount_cny numeric,
  adjustment_source text,
  adjustment_reason text,
  adjustment_note text,
  locked_carryover_cny numeric,
  draft_id uuid,
  draft_status text,
  draft_updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $function$
  WITH student_base AS (
    SELECT s.id AS student_id,s.business_entity_id
    FROM public.school_students s
    WHERE s.id=p_student_id AND s.app_type='school'
  ),
  summary AS (
    SELECT *
    FROM public.school_get_student_monthly_settlement_summary(
      p_student_id,p_year_month)
  ),
  draft AS (
    SELECT d.*
    FROM public.school_student_settlement_adjustment_drafts d
    WHERE d.student_id=p_student_id AND d.year_month=p_year_month
      AND d.app_type='school' AND d.status='active'
    ORDER BY d.updated_at DESC,d.created_at DESC
    LIMIT 1
  )
  SELECT s.student_id,sm.year_month,sb.business_entity_id,sm.exchange_rate,
    sm.carryover_cny,sm.planned_hours,sm.actual_hours,sm.planned_fee_jpy,
    sm.planned_fee_cny,sm.planned_total_cny,sm.actual_fee_jpy,
    sm.actual_fee_cny,sm.received_jpy,sm.received_cny,
    sm.received_equivalent_cny,sm.final_due_cny,
    round(coalesce(d.adjustment_amount_cny,0),2)::numeric,
    d.adjustment_source,d.adjustment_reason,d.note,
    round(coalesce(sm.final_due_cny,0)+
      round(coalesce(d.adjustment_amount_cny,0),2),2)::numeric,
    d.id,d.status,d.updated_at
  FROM summary sm
  JOIN student_base sb ON sb.student_id=sm.student_id
  LEFT JOIN draft d ON true
  CROSS JOIN LATERAL (SELECT sm.student_id) s;
$function$;

COMMENT ON FUNCTION public.school_get_student_monthly_settlement_preview(uuid,text)
IS 'Returns the unchanged student settlement preview contract; lesson scope is inherited exclusively from the R1D-E-C authoritative summary resolver.';

CREATE OR REPLACE FUNCTION public.school_get_student_monthly_settlement_wage_blockers(
  p_year_month text,
  p_student_id uuid DEFAULT NULL
)
RETURNS TABLE (
  student_id uuid,
  year_month text,
  wage_business_names text,
  active_wage_lock_count integer,
  wage_detail_count integer,
  payment_request_count integer,
  paid_payment_request_count integer,
  expense_count integer,
  account_transaction_count integer,
  blocker_level text,
  blocker_reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $function$
  WITH active_links AS (
    SELECT l.student_id,p_year_month AS year_month,w.id AS wage_lock_id,
      d.id AS wage_detail_id,
      coalesce(nullif(trim(w.business_name),''),'未设置业务归属')
        AS wage_business_name,
      pr.id AS payment_request_id,pr.status AS payment_request_status,
      e.id AS expense_id,atx.id AS account_transaction_id
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id,p_year_month) resolved
    JOIN public.school_lesson_records l
      ON l.id=resolved.lesson_id AND l.lesson_type='actual'
    JOIN public.school_teacher_wage_lock_details d
      ON d.lesson_record_id=l.id
    JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
    LEFT JOIN public.school_payment_requests pr
      ON pr.source_type='teacher_wage' AND pr.source_id=w.id
    LEFT JOIN public.school_expense_records e
      ON e.expense_category='teacher_wage'
     AND (e.id=pr.paid_expense_id OR e.salary_payment_id=pr.id)
    LEFT JOIN public.school_account_transactions atx
      ON atx.id=pr.paid_account_transaction_id
      OR (atx.related_table='school_expense_records' AND atx.related_id=e.id)
      OR (atx.related_table='school_payment_requests' AND atx.related_id=pr.id)
    WHERE l.student_id IS NOT NULL
      AND coalesce(w.status,'')<>'void' AND w.voided_at IS NULL
  ),
  aggregated AS (
    SELECT al.student_id,al.year_month,
      string_agg(DISTINCT al.wage_business_name,'、') AS wage_business_names,
      count(DISTINCT al.wage_lock_id)::integer AS active_wage_lock_count,
      count(DISTINCT al.wage_detail_id)::integer AS wage_detail_count,
      count(DISTINCT al.payment_request_id)::integer AS payment_request_count,
      count(DISTINCT al.payment_request_id) FILTER (
        WHERE al.payment_request_status='paid')::integer
        AS paid_payment_request_count,
      count(DISTINCT al.expense_id)::integer AS expense_count,
      count(DISTINCT al.account_transaction_id)::integer
        AS account_transaction_count
    FROM active_links al GROUP BY al.student_id,al.year_month
  )
  SELECT a.student_id,a.year_month,a.wage_business_names,
    a.active_wage_lock_count,a.wage_detail_count,a.payment_request_count,
    a.paid_payment_request_count,a.expense_count,a.account_transaction_count,
    CASE WHEN a.account_transaction_count>0 OR a.expense_count>0
           OR a.paid_payment_request_count>0 THEN 'payment_completed'
         WHEN a.payment_request_count>0 THEN 'payment_requested'
         ELSE 'wage_snapshot' END,
    CASE
      WHEN a.account_transaction_count>0 OR a.expense_count>0
        OR a.paid_payment_request_count>0 THEN format(
          '老师工资已支付，涉及%s个工资快照、%s条工资明细、%s个支付请求、%s条支出、%s条账户流水（业务归属：%s）。',
          a.active_wage_lock_count,a.wage_detail_count,
          a.payment_request_count,a.expense_count,a.account_transaction_count,
          coalesce(a.wage_business_names,'未设置'))
      WHEN a.payment_request_count>0 THEN format(
          '已生成工资支付请求，涉及%s个工资快照、%s条工资明细、%s个支付请求（业务归属：%s）。',
          a.active_wage_lock_count,a.wage_detail_count,
          a.payment_request_count,coalesce(a.wage_business_names,'未设置'))
      ELSE format(
          '已生成老师工资快照，涉及%s个工资快照、%s条工资明细（业务归属：%s）。如需变更，请先撤销未支付工资快照。',
          a.active_wage_lock_count,a.wage_detail_count,
          coalesce(a.wage_business_names,'未设置'))
    END
  FROM aggregated a WHERE a.active_wage_lock_count>0;
$function$;

COMMENT ON FUNCTION
  public.school_get_student_monthly_settlement_wage_blockers(text,uuid)
IS 'Returns the existing teacher-wage blocker contract after selecting actual lessons by the R1D-E-C authoritative student month. Teacher wage facts and teacher months are unchanged.';

CREATE OR REPLACE FUNCTION public.school_assert_student_monthly_settlement_no_wage_blocker(
  p_student_id uuid,
  p_year_month text,
  p_action text DEFAULT '变更学生月度结算'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_blocker record;
BEGIN
  -- Force classification even when no wage detail joins the target lessons.
  PERFORM count(*)
  FROM public.school_list_r1d_e_c_student_month_lessons(
    p_student_id,p_year_month);

  SELECT * INTO v_blocker
  FROM public.school_get_student_monthly_settlement_wage_blockers(
    p_year_month,p_student_id)
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION '%已被后续老师工资链路引用：% 请先按受控流程处理老师工资快照/支付请求，不能从学生月度结算侧间接改动已进入工资链路的课时。',
      coalesce(nullif(trim(p_action),''),'变更学生月度结算'),
      v_blocker.blocker_reason;
  END IF;
END
$function$;

COMMENT ON FUNCTION
  public.school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)
IS 'Internal settlement write guard. It first fail-closes authoritative student-month classification, then preserves the existing teacher wage blocker rule.';

CREATE OR REPLACE FUNCTION public.school_lock_student_monthly_settlement(
  p_student_id uuid,
  p_year_month text,
  p_note text DEFAULT NULL
)
RETURNS TABLE (
  settlement_id uuid,student_id uuid,year_month text,business_entity_id uuid,
  preset_exchange_rate numeric,planned_lesson_fee_jpy numeric,
  planned_lesson_fee_cny numeric,actual_lesson_fee_jpy numeric,
  actual_lesson_fee_cny numeric,previous_balance_cny numeric,
  received_jpy numeric,received_cny numeric,received_equivalent_cny numeric,
  system_difference_cny numeric,adjustment_amount_cny numeric,
  carryover_amount_cny numeric,settlement_status text,locked_at timestamptz,
  note text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_year_month text:=nullif(trim(coalesce(p_year_month,'')),'');
  v_note text:=nullif(trim(coalesce(p_note,'')),'');
  v_now timestamptz:=now();
  v_preview record;
  v_settlement_id uuid;
  v_adjustment_reason text;
BEGIN
  IF p_student_id IS NULL THEN RAISE EXCEPTION '请选择学生。'; END IF;
  IF v_year_month IS NULL
     OR v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION '结算月份格式无效，请使用 YYYY-MM。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m
    WHERE m.student_id=p_student_id AND m.year_month=v_year_month) THEN
    RAISE EXCEPTION '该学生月份已存在结算快照，不能重复锁定。';
  END IF;

  -- These short transaction locks serialize the lesson set and wage-detail
  -- blocker set with the final snapshot write. They do not alter either table.
  LOCK TABLE public.school_lesson_records IN SHARE MODE;
  LOCK TABLE public.school_teacher_wage_lock_details IN SHARE MODE;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id,v_year_month,'锁定学生月度结算');

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id,v_year_month) resolved
    JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
    WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.school_income_records i
    WHERE i.app_type='school' AND i.student_id=p_student_id
      AND coalesce(i.settlement_month,i.year_month)=v_year_month
      AND i.income_category='tuition' AND i.status='received'
      AND coalesce(i.include_in_student_settlement,true)=true
  ) THEN
    RAISE EXCEPTION '该学生月份没有可结算的课时或学费收入，不能锁定。';
  END IF;

  SELECT * INTO v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    p_student_id,v_year_month);
  IF NOT FOUND THEN RAISE EXCEPTION '无法计算该学生月份的结算预览。'; END IF;
  IF v_preview.business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能锁定结算。';
  END IF;

  IF coalesce(v_preview.adjustment_amount_cny,0)<>0
     OR nullif(trim(coalesce(v_preview.adjustment_reason,'')),'') IS NOT NULL
     OR nullif(trim(coalesce(v_preview.adjustment_note,'')),'') IS NOT NULL THEN
    v_adjustment_reason:=format('%s: %s (%s)',
      coalesce(v_preview.adjustment_source,'manual'),
      coalesce(v_preview.adjustment_reason,''),
      coalesce(v_preview.adjustment_amount_cny,0));
  ELSE
    v_adjustment_reason:=NULL;
  END IF;

  INSERT INTO public.school_student_monthly_settlements (
    student_id,year_month,business_entity_id,preset_exchange_rate,
    planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
    actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
    received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
    adjustment_reason,carryover_amount_cny,settlement_status,locked_at,note,
    created_at,updated_at
  ) VALUES (
    p_student_id,v_year_month,v_preview.business_entity_id,
    coalesce(v_preview.exchange_rate,0),coalesce(v_preview.planned_fee_jpy,0),
    coalesce(v_preview.planned_fee_cny,0),coalesce(v_preview.actual_fee_jpy,0),
    coalesce(v_preview.actual_fee_cny,0),coalesce(v_preview.carryover_cny,0),
    coalesce(v_preview.received_jpy,0),coalesce(v_preview.received_cny,0),
    coalesce(v_preview.received_equivalent_cny,0),
    coalesce(v_preview.final_due_cny,0),
    coalesce(v_preview.adjustment_amount_cny,0),v_adjustment_reason,
    coalesce(v_preview.locked_carryover_cny,
      coalesce(v_preview.final_due_cny,0)),'locked',v_now,v_note,v_now,v_now
  ) RETURNING id INTO v_settlement_id;

  IF v_preview.draft_id IS NOT NULL THEN
    INSERT INTO public.school_student_settlement_adjustments (
      settlement_id,student_id,year_month,business_entity_id,
      adjustment_amount_cny,adjustment_source,adjustment_reason,note,status,
      app_type,created_at,updated_at
    ) VALUES (
      v_settlement_id,p_student_id,v_year_month,v_preview.business_entity_id,
      coalesce(v_preview.adjustment_amount_cny,0),
      coalesce(v_preview.adjustment_source,'manual'),
      coalesce(v_preview.adjustment_reason,'锁定前差额调整'),
      v_preview.adjustment_note,'posted','school',v_now,v_now
    );
    UPDATE public.school_student_settlement_adjustment_drafts d SET
      status='consumed',settlement_id=v_settlement_id,consumed_at=v_now,
      updated_by=current_user,updated_at=v_now
    WHERE d.id=v_preview.draft_id;
  END IF;

  RETURN QUERY
  SELECT m.id,m.student_id,m.year_month,m.business_entity_id,
    m.preset_exchange_rate,m.planned_lesson_fee_jpy,m.planned_lesson_fee_cny,
    m.actual_lesson_fee_jpy,m.actual_lesson_fee_cny,m.previous_balance_cny,
    m.received_jpy,m.received_cny,m.received_equivalent_cny,
    m.system_difference_cny,m.adjustment_amount_cny,m.carryover_amount_cny,
    m.settlement_status,m.locked_at,m.note,m.created_at,m.updated_at
  FROM public.school_student_monthly_settlements m
  WHERE m.id=v_settlement_id;
END
$function$;

COMMENT ON FUNCTION public.school_lock_student_monthly_settlement(uuid,text,text)
IS 'Locks the unchanged settlement snapshot contract from the authoritative R1D-E-C lesson set. Lesson and wage-detail tables are transaction-locked through classification, blocker checks and snapshot insertion.';

CREATE OR REPLACE FUNCTION public.school_unlock_student_monthly_settlement(
  p_settlement_id uuid,
  p_reason text
)
RETURNS TABLE (
  settlement_id uuid,student_id uuid,year_month text,business_entity_id uuid,
  preset_exchange_rate numeric,planned_lesson_fee_jpy numeric,
  planned_lesson_fee_cny numeric,actual_lesson_fee_jpy numeric,
  actual_lesson_fee_cny numeric,previous_balance_cny numeric,
  received_jpy numeric,received_cny numeric,received_equivalent_cny numeric,
  system_difference_cny numeric,adjustment_amount_cny numeric,
  carryover_amount_cny numeric,settlement_status text,locked_at timestamptz,
  unlocked_at timestamptz,unlock_reason text,note text,created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  v_now timestamptz:=now();
BEGIN
  IF p_settlement_id IS NULL THEN
    RAISE EXCEPTION '请选择要撤销锁定的学生月度结算。';
  END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION '请填写撤销锁定原因。'; END IF;

  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '没有找到对应的学生月度结算。'; END IF;
  IF coalesce(v_settlement.settlement_status,'')<>'locked' THEN
    RAISE EXCEPTION '只有已锁定的学生月度结算可以撤销锁定。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_legacy_settlement_snapshot_basis_evidence e
    WHERE e.settlement_snapshot_id=v_settlement.id) THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_settlement_adjustments a
    WHERE a.settlement_id=v_settlement.id AND a.status='posted') THEN
    RAISE EXCEPTION '该结算已有差额调整记录，不能通过撤销锁定重算快照。';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_settlement_carryovers c
    WHERE c.source_settlement_id=v_settlement.id
      AND coalesce(c.status,'active')='active') THEN
    RAISE EXCEPTION '该结算已生成有效结转，不能撤销锁定。';
  END IF;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id,v_settlement.year_month,'撤销学生月度结算');

  UPDATE public.school_student_monthly_settlements m SET
    settlement_status='unlocked',unlocked_at=v_now,unlock_reason=v_reason,
    updated_at=v_now
  WHERE m.id=v_settlement.id;

  RETURN QUERY
  SELECT m.id,m.student_id,m.year_month,m.business_entity_id,
    m.preset_exchange_rate,m.planned_lesson_fee_jpy,m.planned_lesson_fee_cny,
    m.actual_lesson_fee_jpy,m.actual_lesson_fee_cny,m.previous_balance_cny,
    m.received_jpy,m.received_cny,m.received_equivalent_cny,
    m.system_difference_cny,m.adjustment_amount_cny,m.carryover_amount_cny,
    m.settlement_status,m.locked_at,m.unlocked_at,m.unlock_reason,m.note,
    m.created_at,m.updated_at
  FROM public.school_student_monthly_settlements m WHERE m.id=v_settlement.id;
END
$function$;

COMMENT ON FUNCTION public.school_unlock_student_monthly_settlement(uuid,text)
IS 'Preserves existing unlock protections and authoritative wage classification; the fixed 15 R1D-E-B1 legacy snapshots are explicitly immutable.';

CREATE OR REPLACE FUNCTION public.school_relock_student_monthly_settlement(
  p_settlement_id uuid,
  p_note text DEFAULT NULL
)
RETURNS TABLE (
  settlement_id uuid,student_id uuid,year_month text,business_entity_id uuid,
  preset_exchange_rate numeric,planned_lesson_fee_jpy numeric,
  planned_lesson_fee_cny numeric,actual_lesson_fee_jpy numeric,
  actual_lesson_fee_cny numeric,previous_balance_cny numeric,
  received_jpy numeric,received_cny numeric,received_equivalent_cny numeric,
  system_difference_cny numeric,adjustment_amount_cny numeric,
  carryover_amount_cny numeric,settlement_status text,locked_at timestamptz,
  unlocked_at timestamptz,unlock_reason text,note text,created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_note text:=nullif(trim(coalesce(p_note,'')),'');
  v_now timestamptz:=now();
  v_preview record;
  v_adjustment_reason text;
BEGIN
  IF p_settlement_id IS NULL THEN
    RAISE EXCEPTION '请选择要重新锁定的学生月度结算。';
  END IF;
  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '没有找到对应的学生月度结算。'; END IF;
  IF coalesce(v_settlement.settlement_status,'')<>'unlocked' THEN
    RAISE EXCEPTION '只有已撤销锁定的学生月度结算可以重新锁定。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_legacy_settlement_snapshot_basis_evidence e
    WHERE e.settlement_snapshot_id=v_settlement.id) THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_settlement_adjustments a
    WHERE a.settlement_id=v_settlement.id AND a.status='posted') THEN
    RAISE EXCEPTION '该结算已有差额调整记录，不能通过重新锁定重算快照。';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_settlement_carryovers c
    WHERE c.source_settlement_id=v_settlement.id
      AND coalesce(c.status,'active')='active') THEN
    RAISE EXCEPTION '该结算已生成有效结转，不能重新锁定。';
  END IF;

  LOCK TABLE public.school_lesson_records IN SHARE MODE;
  LOCK TABLE public.school_teacher_wage_lock_details IN SHARE MODE;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id,v_settlement.year_month,'重新锁定学生月度结算');

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_list_r1d_e_c_student_month_lessons(
      v_settlement.student_id,v_settlement.year_month) resolved
    JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
    WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.school_income_records i
    WHERE i.app_type='school' AND i.student_id=v_settlement.student_id
      AND coalesce(i.settlement_month,i.year_month)=v_settlement.year_month
      AND i.income_category='tuition' AND i.status='received'
      AND coalesce(i.include_in_student_settlement,true)=true
  ) THEN
    RAISE EXCEPTION '该学生月份没有可结算的课时或学费收入，不能重新锁定。';
  END IF;

  SELECT * INTO v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    v_settlement.student_id,v_settlement.year_month);
  IF NOT FOUND THEN RAISE EXCEPTION '无法计算该学生月份的结算预览。'; END IF;
  IF v_preview.business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能重新锁定结算。';
  END IF;

  IF coalesce(v_preview.adjustment_amount_cny,0)<>0
     OR nullif(trim(coalesce(v_preview.adjustment_reason,'')),'') IS NOT NULL
     OR nullif(trim(coalesce(v_preview.adjustment_note,'')),'') IS NOT NULL THEN
    v_adjustment_reason:=format('%s: %s (%s)',
      coalesce(v_preview.adjustment_source,'manual'),
      coalesce(v_preview.adjustment_reason,''),
      coalesce(v_preview.adjustment_amount_cny,0));
  ELSE
    v_adjustment_reason:=NULL;
  END IF;

  UPDATE public.school_student_monthly_settlements m SET
    business_entity_id=v_preview.business_entity_id,
    preset_exchange_rate=coalesce(v_preview.exchange_rate,0),
    planned_lesson_fee_jpy=coalesce(v_preview.planned_fee_jpy,0),
    planned_lesson_fee_cny=coalesce(v_preview.planned_fee_cny,0),
    actual_lesson_fee_jpy=coalesce(v_preview.actual_fee_jpy,0),
    actual_lesson_fee_cny=coalesce(v_preview.actual_fee_cny,0),
    previous_balance_cny=coalesce(v_preview.carryover_cny,0),
    received_jpy=coalesce(v_preview.received_jpy,0),
    received_cny=coalesce(v_preview.received_cny,0),
    received_equivalent_cny=coalesce(v_preview.received_equivalent_cny,0),
    system_difference_cny=coalesce(v_preview.final_due_cny,0),
    adjustment_amount_cny=coalesce(v_preview.adjustment_amount_cny,0),
    adjustment_reason=v_adjustment_reason,
    carryover_amount_cny=coalesce(v_preview.locked_carryover_cny,
      coalesce(v_preview.final_due_cny,0)),settlement_status='locked',
    locked_at=v_now,note=v_note,updated_at=v_now
  WHERE m.id=v_settlement.id;

  IF v_preview.draft_id IS NOT NULL THEN
    INSERT INTO public.school_student_settlement_adjustments (
      settlement_id,student_id,year_month,business_entity_id,
      adjustment_amount_cny,adjustment_source,adjustment_reason,note,status,
      app_type,created_at,updated_at
    ) VALUES (
      v_settlement.id,v_settlement.student_id,v_settlement.year_month,
      v_preview.business_entity_id,coalesce(v_preview.adjustment_amount_cny,0),
      coalesce(v_preview.adjustment_source,'manual'),
      coalesce(v_preview.adjustment_reason,'重新锁定前差额调整'),
      v_preview.adjustment_note,'posted','school',v_now,v_now
    );
    UPDATE public.school_student_settlement_adjustment_drafts d SET
      status='consumed',settlement_id=v_settlement.id,consumed_at=v_now,
      updated_by=current_user,updated_at=v_now
    WHERE d.id=v_preview.draft_id;
  END IF;

  RETURN QUERY
  SELECT m.id,m.student_id,m.year_month,m.business_entity_id,
    m.preset_exchange_rate,m.planned_lesson_fee_jpy,m.planned_lesson_fee_cny,
    m.actual_lesson_fee_jpy,m.actual_lesson_fee_cny,m.previous_balance_cny,
    m.received_jpy,m.received_cny,m.received_equivalent_cny,
    m.system_difference_cny,m.adjustment_amount_cny,m.carryover_amount_cny,
    m.settlement_status,m.locked_at,m.unlocked_at,m.unlock_reason,m.note,
    m.created_at,m.updated_at
  FROM public.school_student_monthly_settlements m WHERE m.id=v_settlement.id;
END
$function$;

COMMENT ON FUNCTION public.school_relock_student_monthly_settlement(uuid,text)
IS 'Relocks only non-legacy snapshots from the authoritative R1D-E-C lesson set under the same lesson/wage transaction locks as first lock. Fixed R1D-E-B1 snapshots cannot be rebuilt.';

CREATE OR REPLACE FUNCTION public.school_set_student_monthly_settlement_draft_adjustment(
  p_student_id uuid,
  p_year_month text,
  p_adjustment_amount_cny numeric,
  p_adjustment_source text DEFAULT 'manual',
  p_adjustment_reason text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS TABLE (
  student_id uuid,year_month text,business_entity_id uuid,
  exchange_rate numeric,carryover_cny numeric,planned_hours numeric,
  actual_hours numeric,planned_fee_jpy numeric,planned_fee_cny numeric,
  planned_total_cny numeric,actual_fee_jpy numeric,actual_fee_cny numeric,
  received_jpy numeric,received_cny numeric,received_equivalent_cny numeric,
  final_due_cny numeric,adjustment_amount_cny numeric,adjustment_source text,
  adjustment_reason text,adjustment_note text,locked_carryover_cny numeric,
  draft_id uuid,draft_status text,draft_updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_year_month text:=nullif(trim(coalesce(p_year_month,'')),'');
  v_source text:=nullif(trim(coalesce(p_adjustment_source,'')),'');
  v_reason text:=nullif(trim(coalesce(p_adjustment_reason,'')),'');
  v_note text:=nullif(trim(coalesce(p_note,'')),'');
  v_adjustment_amount_cny numeric:=round(p_adjustment_amount_cny,2);
  v_business_entity_id uuid;
  v_existing_status text;
  v_now timestamptz:=now();
BEGIN
  IF p_student_id IS NULL THEN RAISE EXCEPTION '请选择学生。'; END IF;
  IF v_year_month IS NULL
     OR v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION '结算月份格式无效，请使用 YYYY-MM。';
  END IF;
  IF p_adjustment_amount_cny IS NULL THEN
    RAISE EXCEPTION '请填写差额调整金额。';
  END IF;
  IF v_source IS NULL THEN RAISE EXCEPTION '请填写差额调整来源。'; END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION '请填写差额调整理由。'; END IF;

  SELECT s.business_entity_id INTO v_business_entity_id
  FROM public.school_students s
  WHERE s.id=p_student_id AND s.app_type='school';
  IF NOT FOUND THEN RAISE EXCEPTION '学生不存在或不属于学校业务。'; END IF;
  IF v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能记录差额调整。';
  END IF;

  SELECT m.settlement_status INTO v_existing_status
  FROM public.school_student_monthly_settlements m
  WHERE m.student_id=p_student_id AND m.year_month=v_year_month;
  IF FOUND AND coalesce(v_existing_status,'')<>'unlocked' THEN
    RAISE EXCEPTION '该学生月份已锁定，差额调整只能只读查看，不能再修改。';
  END IF;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id,v_year_month,'保存学生月度结算差额调整');

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id,v_year_month) resolved
    JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
    WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.school_income_records i
    WHERE i.app_type='school' AND i.student_id=p_student_id
      AND coalesce(i.settlement_month,i.year_month)=v_year_month
      AND i.income_category='tuition' AND i.status='received'
      AND coalesce(i.include_in_student_settlement,true)=true
  ) THEN
    RAISE EXCEPTION '该学生月份没有可结算的课时或学费收入，不能记录差额调整。';
  END IF;

  INSERT INTO public.school_student_settlement_adjustment_drafts (
    student_id,year_month,business_entity_id,adjustment_amount_cny,
    adjustment_source,adjustment_reason,note,status,settlement_id,app_type,
    created_by,updated_by,consumed_at,created_at,updated_at
  ) VALUES (
    p_student_id,v_year_month,v_business_entity_id,v_adjustment_amount_cny,
    v_source,v_reason,v_note,'active',NULL,'school',current_user,current_user,
    NULL,v_now,v_now
  ) ON CONFLICT ON CONSTRAINT
    school_student_settlement_adjustment_drafts_student_month_key
  DO UPDATE SET business_entity_id=excluded.business_entity_id,
    adjustment_amount_cny=excluded.adjustment_amount_cny,
    adjustment_source=excluded.adjustment_source,
    adjustment_reason=excluded.adjustment_reason,note=excluded.note,
    status='active',settlement_id=NULL,updated_by=current_user,
    consumed_at=NULL,updated_at=v_now;

  RETURN QUERY
  SELECT * FROM public.school_get_student_monthly_settlement_preview(
    p_student_id,v_year_month);
END
$function$;

COMMENT ON FUNCTION
  public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
IS 'Creates or updates the unchanged rounded draft-adjustment contract only after fail-closed authoritative lesson classification for the target student month.';

DO $verify$
DECLARE
  v_reader_count bigint;
  v_reader_hash text;
  v_writer_count bigint;
  v_writer_hash text;
BEGIN
  IF public.school_r1d_e_c_settlement_reader_cutover_version()<>
       'r1d_e_c_settlement_reader_v1'
     OR to_regprocedure(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)') IS NULL
     OR to_regprocedure(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'R1D_E_C_OBJECT_VERIFY_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'school_r1d_e_c_settlement_reader_cutover_version',
      'school_resolve_r1d_e_c_lesson_student_month',
      'school_list_r1d_e_c_student_month_lessons')
      AND (
        has_function_privilege('anon',p.oid,'EXECUTE')
        OR has_function_privilege('authenticated',p.oid,'EXECUTE')
        OR has_function_privilege('service_role',p.oid,'EXECUTE')
        OR EXISTS (
          SELECT 1
          FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) privilege
          WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE')
      )
  ) THEN
    RAISE EXCEPTION 'R1D_E_C_INTERNAL_HELPER_ACL_FAILED';
  END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
        'school_get_student_monthly_settlement_summary',
        'school_get_student_monthly_settlement_preview',
        'school_get_student_monthly_settlement_wage_blockers',
        'school_assert_student_monthly_settlement_no_wage_blocker',
        'school_lock_student_monthly_settlement',
        'school_unlock_student_monthly_settlement',
        'school_relock_student_monthly_settlement',
        'school_set_student_monthly_settlement_draft_adjustment']::text[]))<>8
     OR EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
         'school_get_student_monthly_settlement_summary',
         'school_get_student_monthly_settlement_preview',
         'school_get_student_monthly_settlement_wage_blockers',
         'school_assert_student_monthly_settlement_no_wage_blocker',
         'school_lock_student_monthly_settlement',
         'school_unlock_student_monthly_settlement',
         'school_relock_student_monthly_settlement',
         'school_set_student_monthly_settlement_draft_adjustment']::text[])
         AND (NOT p.prosecdef
           OR coalesce(p.proacl::text,'')<>
             '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
           OR NOT has_function_privilege('anon',p.oid,'EXECUTE')
           OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
           OR NOT has_function_privilege('service_role',p.oid,'EXECUTE'))
     ) THEN
    RAISE EXCEPTION 'R1D_E_C_EXTERNAL_CONTRACT_OR_ACL_FAILED';
  END IF;

  IF position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure))=0
     OR position('school_get_student_monthly_settlement_summary' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_preview(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_wage_blockers(text,uuid)'::regprocedure))=0
     OR position('school_get_student_monthly_settlement_wage_blockers' IN pg_get_functiondef(
       'public.school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure))=0
     OR position('school_assert_student_monthly_settlement_no_wage_blocker' IN
       pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE' IN
       pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_C_EIGHT_FUNCTION_CALL_GRAPH_FAILED';
  END IF;

  IF position('l.year_month = p_year_month' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure))>0
     OR position('l.year_month = p_year_month' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_wage_blockers(text,uuid)'::regprocedure))>0
     OR position('coalesce(student_settlement_month, year_month)' IN lower(
       pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)))>0 THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_LESSON_MONTH_FALLBACK_REMAINS';
  END IF;

  -- Resolves every current School lesson and fails the deployment on any
  -- partial bundle, missing evidence, or identity/source/month drift.
  PERFORM count(*)
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL);

  IF (SELECT count(*)
      FROM public.school_legacy_settlement_snapshot_basis_evidence)<>15
     OR EXISTS (
       SELECT 1
       FROM public.school_legacy_settlement_snapshot_basis_evidence e
       JOIN public.school_student_monthly_settlements m
         ON m.id=e.settlement_snapshot_id
       WHERE m.settlement_status IS DISTINCT FROM 'locked'
          OR md5(to_jsonb(m)::text) IS DISTINCT FROM e.settlement_structure_md5
     ) THEN
    RAISE EXCEPTION 'R1D_E_C_LOCKED_SNAPSHOT_CHANGED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_get_student_monthly_settlement_summary',
      'school_get_student_monthly_settlement_preview',
      'school_get_student_monthly_settlement_wage_blockers',
      'school_assert_student_monthly_settlement_no_wage_blocker',
      'school_lock_student_monthly_settlement',
      'school_unlock_student_monthly_settlement',
      'school_relock_student_monthly_settlement',
      'school_set_student_monthly_settlement_draft_adjustment']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),
      E'\n' ORDER BY signature)) INTO v_reader_count,v_reader_hash
    FROM functions;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_create_actual_lesson_from_planned',
      'school_create_cancelled_actual_lesson_from_planned',
      'school_create_partial_completed_actual_from_planned',
      'school_create_lesson_credit_makeup_actual',
      'school_create_makeup_completed_actual_lesson_from_planned',
      'school_create_cross_month_makeup_completed_actual_from_planned',
      'school_update_lesson_record_guarded',
      'school_update_lesson_record_guarded_with_venue']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),
      E'\n' ORDER BY signature)) INTO v_writer_count,v_writer_hash
    FROM functions;

  IF v_reader_count<>8 OR v_writer_count<>8
     OR v_writer_hash<>'046cb8c0002528634b767a046e4626ab'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))<>
       '4a163f6691c779531a65a10be0f4422e' THEN
    RAISE EXCEPTION 'R1D_E_C_WRITER_OR_READER_GROUP_VERIFY_FAILED';
  END IF;

  RAISE NOTICE 'R1D_E_C_READER_GROUP_MD5=%',v_reader_hash;
  RAISE NOTICE 'R1D_E_C_ACTUAL_WRITER_GROUP_MD5=%',v_writer_hash;
  RAISE NOTICE 'R1D_E_C_TRIGGER_FUNCTION_MD5=%',md5(pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure));
END
$verify$;

SELECT public.school_r1d_e_c_settlement_reader_cutover_version()
    AS cutover_version,
  (SELECT count(*)
   FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL))
    AS classified_school_lessons,
  true AS cutover_verify_pass;

\if :r1d_e_c_commit
  COMMIT;
  \echo 'R1D_E_C_DEPLOYMENT_COMMITTED'
\else
  \echo 'R1D_E_C_REHEARSAL_TRANSACTION_OPEN'
\endif
