\set ON_ERROR_STOP on
\pset pager off

-- Aozora V2 actual duration overage S1-C settlement consumer.
-- Consumes only frozen S1-B ordinary actual overage facts in the authoritative
-- source student month. It does not scan legacy duration differences, backfill
-- history, or modify candidate, bill, income, Cash, aircon, or lesson writers.

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
     )) <> '86b93835aaed296fb908d26ee2559eae'
     OR md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_preview(uuid,text)'::regprocedure
     )) <> '1ddcfdd0344ba0ea3cf06d12058796ba'
     OR md5(pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
     )) <> '323216425f47e1cfa2960b4341ef452c'
     OR md5(pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> '060c25ee1ab25d8d72ab5f43f32728b5' THEN
    RAISE EXCEPTION 'S1_C_SETTLEMENT_SOURCE_FUNCTION_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1' THEN
    RAISE EXCEPTION 'S1_C_S1_B_WRITER_DRIFT';
  END IF;

  IF to_regprocedure(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'S1_C_AGGREGATE_HELPER_ALREADY_EXISTS';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_student_monthly_settlements'
        AND column_name IN (
          'duration_overage_minutes',
          'duration_overage_fee_jpy',
          'duration_overage_fee_cny',
          'duration_overage_actual_count',
          'duration_overage_policy_version',
          'duration_overage_source'
        )) <> 6 THEN
    RAISE EXCEPTION 'S1_C_SETTLEMENT_SNAPSHOT_COLUMNS_MISSING';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_C_R0_MISMATCH';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE s1_c_deploy_baseline ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.school_lesson_records
   WHERE student_duration_overage_policy_version IS NOT NULL)
    AS lesson_overage_nonnull,
  (SELECT count(*) FROM public.school_student_monthly_settlements
   WHERE duration_overage_policy_version IS NOT NULL)
    AS settlement_overage_nonnull,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count;

CREATE OR REPLACE FUNCTION public.school_get_student_duration_overage_aggregate(
  p_student_id uuid,
  p_year_month text
)
RETURNS TABLE (
  duration_overage_minutes integer,
  duration_overage_fee_jpy numeric,
  duration_overage_fee_cny numeric,
  duration_overage_actual_count integer,
  aggregation_basis text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  WITH input_month AS (
    SELECT p_year_month AS year_month
    WHERE p_student_id IS NOT NULL
      AND p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  locked_snapshot AS (
    SELECT
      m.duration_overage_minutes,
      m.duration_overage_fee_jpy,
      m.duration_overage_fee_cny,
      m.duration_overage_actual_count,
      m.duration_overage_policy_version,
      m.duration_overage_source
    FROM public.school_student_monthly_settlements m
    JOIN input_month im ON im.year_month = m.year_month
    WHERE m.student_id = p_student_id
      AND m.settlement_status = 'locked'
    ORDER BY m.locked_at DESC NULLS LAST,
      m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  live_aggregate AS (
    SELECT
      coalesce(sum(l.student_duration_overage_minutes), 0)::integer
        AS duration_overage_minutes,
      coalesce(sum(l.student_duration_overage_fee_jpy), 0)::numeric
        AS duration_overage_fee_jpy,
      count(*)::integer AS duration_overage_actual_count
    FROM public.school_lesson_records l
    JOIN input_month im ON im.year_month = l.student_settlement_month
    WHERE l.app_type = 'school'
      AND l.student_id = p_student_id
      AND l.lesson_type = 'actual'
      AND l.status = 'completed'
      AND l.is_billable IS TRUE
      AND l.business_entity_id = public.school_primary_business_entity_id()
      AND l.student_duration_overage_policy_version =
        'student_duration_overage_v1'
      AND l.student_duration_overage_source = 'ordinary_actual_rpc'
      AND l.student_duration_overage_minutes > 0
      AND l.student_duration_overage_fee_jpy > 0
  ),
  exchange_rate AS (
    SELECT coalesce(s.preset_exchange_rate, 0)::numeric AS rate
    FROM public.school_students s
    WHERE s.id = p_student_id
      AND s.app_type = 'school'
  )
  SELECT
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_minutes
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_minutes
                     FROM live_aggregate a), 0)
    END::integer,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_fee_jpy
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_fee_jpy
                     FROM live_aggregate a), 0)
    END::numeric,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_fee_cny
                     FROM locked_snapshot s), 0)
      ELSE round(
        coalesce((SELECT a.duration_overage_fee_jpy
                  FROM live_aggregate a), 0)
        * coalesce((SELECT e.rate FROM exchange_rate e), 0),
        2
      )
    END::numeric,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_actual_count
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_actual_count
                     FROM live_aggregate a), 0)
    END::integer,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM locked_snapshot s
        WHERE s.duration_overage_policy_version =
              'student_duration_overage_v1'
          AND s.duration_overage_source = 'monthly_settlement_lock'
      ) THEN 'locked_snapshot'
      WHEN EXISTS (SELECT 1 FROM locked_snapshot)
        THEN 'legacy_locked_null_snapshot'
      ELSE 'live_s1_b_actual_aggregate'
    END::text;
$function$;

COMMENT ON FUNCTION
  public.school_get_student_duration_overage_aggregate(uuid, text)
IS 'S1-C internal aggregate. For an unlocked source month it sums only frozen S1-B ordinary actual overage minutes/JPY and converts once with the source-month student rate. For a locked month it returns the six-field settlement snapshot; legacy locked NULL snapshots return zero and are never inferred from duration, price, fee, date, legacy month, aircon, or add-ons.';

REVOKE ALL ON FUNCTION
  public.school_get_student_duration_overage_aggregate(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.school_get_student_duration_overage_aggregate(uuid, text)
  TO service_role;

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
SET search_path = pg_catalog, public
AS $function$
  WITH input_month AS (
    SELECT p_year_month AS year_month,
      to_char((to_date(p_year_month || '-01', 'YYYY-MM-DD') -
        interval '1 month')::date, 'YYYY-MM') AS previous_year_month
    WHERE p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  student_base AS (
    SELECT s.id AS student_id,
      coalesce(s.preset_exchange_rate, 0)::numeric AS exchange_rate,
      coalesce(s.previous_balance_cny, 0)::numeric AS fallback_carryover_cny
    FROM public.school_students s
    WHERE s.id = p_student_id
  ),
  previous_locked_settlement AS (
    SELECT m.carryover_amount_cny
    FROM public.school_student_monthly_settlements m
    JOIN input_month im ON im.previous_year_month = m.year_month
    WHERE m.student_id = p_student_id
      AND m.settlement_status = 'locked'
    ORDER BY m.locked_at DESC NULLS LAST,
      m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  carryover AS (
    SELECT coalesce(
      (SELECT c.amount_cny
       FROM public.school_student_settlement_carryovers c
       WHERE c.student_id = p_student_id
         AND c.to_year_month = p_year_month
         AND coalesce(c.status, 'active') = 'active'
       ORDER BY c.updated_at DESC NULLS LAST,
         c.created_at DESC NULLS LAST
       LIMIT 1),
      (SELECT pls.carryover_amount_cny
       FROM previous_locked_settlement pls),
      (SELECT fallback_carryover_cny FROM student_base),
      0
    )::numeric AS carryover_cny
  ),
  lessons AS (
    SELECT l.id, l.planned_lesson_id, l.lesson_type, l.status,
      coalesce(l.is_billable, false) AS is_billable,
      coalesce(l.duration_hours, 0)::numeric AS duration_hours,
      coalesce(l.lesson_fee,
        coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)::numeric
        AS fee_jpy
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id, p_year_month
    ) resolved
    JOIN public.school_lesson_records l ON l.id = resolved.lesson_id
    WHERE NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL)
  ),
  lesson_summary AS (
    SELECT
      coalesce(sum(f.duration_hours) FILTER (
        WHERE f.lesson_type = 'planned'), 0)::numeric AS planned_hours,
      coalesce(sum(f.duration_hours) FILTER (
        WHERE f.lesson_type = 'actual'
          AND f.is_billable = true
          AND f.status IN ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric AS actual_hours,
      coalesce(sum(f.fee_jpy) FILTER (
        WHERE f.lesson_type = 'planned'), 0)::numeric AS planned_fee_jpy,
      coalesce(sum(f.fee_jpy) FILTER (
        WHERE f.lesson_type = 'actual'
          AND f.is_billable = true
          AND f.status IN ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric AS actual_fee_jpy
    FROM lessons f
  ),
  income_summary AS (
    SELECT
      coalesce(sum(i.amount) FILTER (
        WHERE coalesce(i.payment_currency, i.currency) = 'JPY'
      ), 0)::numeric AS received_jpy,
      coalesce(sum(i.amount) FILTER (
        WHERE coalesce(i.payment_currency, i.currency) = 'CNY'
      ), 0)::numeric AS received_cny
    FROM public.school_income_records i
    WHERE i.student_id = p_student_id
      AND coalesce(i.settlement_month, i.year_month) = p_year_month
      AND i.income_category = 'tuition'
      AND i.status = 'received'
      AND coalesce(i.include_in_student_settlement, true) = true
  ),
  overage AS (
    SELECT *
    FROM public.school_get_student_duration_overage_aggregate(
      p_student_id, p_year_month
    )
  ),
  locked AS (
    SELECT m.carryover_amount_cny
    FROM public.school_student_monthly_settlements m
    WHERE m.student_id = p_student_id
      AND m.year_month = p_year_month
      AND m.settlement_status = 'locked'
    ORDER BY m.locked_at DESC NULLS LAST,
      m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  calculated AS (
    SELECT sb.student_id, p_year_month AS year_month, sb.exchange_rate,
      coalesce(c.carryover_cny, 0)::numeric AS carryover_cny,
      coalesce(ls.planned_hours, 0)::numeric AS planned_hours,
      coalesce(ls.actual_hours, 0)::numeric AS actual_hours,
      coalesce(ls.planned_fee_jpy, 0)::numeric AS planned_fee_jpy,
      (coalesce(ls.planned_fee_jpy, 0) * sb.exchange_rate)::numeric
        AS planned_fee_cny,
      coalesce(ls.actual_fee_jpy, 0)::numeric AS actual_fee_jpy,
      (coalesce(ls.actual_fee_jpy, 0) * sb.exchange_rate)::numeric
        AS actual_fee_cny,
      coalesce(o.duration_overage_fee_cny, 0)::numeric
        AS duration_overage_fee_cny,
      coalesce(inc.received_jpy, 0)::numeric AS received_jpy,
      coalesce(inc.received_cny, 0)::numeric AS received_cny,
      (coalesce(inc.received_cny, 0) +
        coalesce(inc.received_jpy, 0) * sb.exchange_rate)::numeric
        AS received_equivalent_cny
    FROM student_base sb
    CROSS JOIN carryover c
    CROSS JOIN lesson_summary ls
    CROSS JOIN income_summary inc
    CROSS JOIN overage o
  ),
  rounded AS (
    SELECT calc.student_id, calc.year_month, calc.exchange_rate,
      round(calc.carryover_cny, 2)::numeric AS carryover_cny,
      calc.planned_hours, calc.actual_hours, calc.planned_fee_jpy,
      round(calc.planned_fee_cny, 2)::numeric AS planned_fee_cny,
      calc.actual_fee_jpy,
      round(calc.actual_fee_cny, 2)::numeric AS actual_fee_cny,
      round(calc.duration_overage_fee_cny, 2)::numeric
        AS duration_overage_fee_cny,
      calc.received_jpy,
      round(calc.received_cny, 2)::numeric AS received_cny,
      round(calc.received_equivalent_cny, 2)::numeric
        AS received_equivalent_cny
    FROM calculated calc
  )
  SELECT r.student_id, r.year_month, r.exchange_rate, r.carryover_cny,
    r.planned_hours, r.actual_hours, r.planned_fee_jpy, r.planned_fee_cny,
    round(r.planned_fee_cny + r.carryover_cny, 2)::numeric
      AS planned_total_cny,
    r.actual_fee_jpy, r.actual_fee_cny, r.received_jpy, r.received_cny,
    r.received_equivalent_cny,
    round(
      r.planned_fee_cny + r.duration_overage_fee_cny + r.carryover_cny
      - r.received_equivalent_cny,
      2
    )::numeric AS final_due_cny,
    coalesce(
      (SELECT round(l.carryover_amount_cny, 2) FROM locked l),
      round(
        r.planned_fee_cny + r.duration_overage_fee_cny + r.carryover_cny
        - r.received_equivalent_cny,
        2
      )
    )::numeric AS locked_carryover_cny
  FROM rounded r;
$function$;

COMMENT ON FUNCTION
  public.school_get_student_monthly_settlement_summary(uuid, text)
IS 'S1-C authoritative student-month summary. Planned tuition remains the base receivable; only the frozen S1-B duration overage aggregate is added positively to final_due_cny. Actual totals remain informational and cannot reduce planned tuition. Locked months consume the settlement overage snapshot, while legacy locked NULL snapshots contribute zero.';

CREATE OR REPLACE FUNCTION public.school_lock_student_monthly_settlement(
  p_student_id uuid,
  p_year_month text,
  p_note text DEFAULT NULL
)
RETURNS TABLE (
  settlement_id uuid, student_id uuid, year_month text,
  business_entity_id uuid, preset_exchange_rate numeric,
  planned_lesson_fee_jpy numeric, planned_lesson_fee_cny numeric,
  actual_lesson_fee_jpy numeric, actual_lesson_fee_cny numeric,
  previous_balance_cny numeric, received_jpy numeric, received_cny numeric,
  received_equivalent_cny numeric, system_difference_cny numeric,
  adjustment_amount_cny numeric, carryover_amount_cny numeric,
  settlement_status text, locked_at timestamptz, note text,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_preview record;
  v_overage record;
  v_settlement_id uuid;
  v_adjustment_reason text;
BEGIN
  IF p_student_id IS NULL THEN
    RAISE EXCEPTION '请选择学生。';
  END IF;
  IF v_year_month IS NULL
     OR v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION '结算月份格式无效，请使用 YYYY-MM。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m
    WHERE m.student_id = p_student_id
      AND m.year_month = v_year_month
  ) THEN
    RAISE EXCEPTION '该学生月份已存在结算快照，不能重复锁定。';
  END IF;

  LOCK TABLE public.school_lesson_records IN SHARE MODE;
  LOCK TABLE public.school_teacher_wage_lock_details IN SHARE MODE;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id, v_year_month, '锁定学生月度结算'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_list_r1d_e_c_student_month_lessons(
      p_student_id, v_year_month
    ) resolved
    JOIN public.school_lesson_records l ON l.id = resolved.lesson_id
    WHERE NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.school_income_records i
    WHERE i.app_type = 'school'
      AND i.student_id = p_student_id
      AND coalesce(i.settlement_month, i.year_month) = v_year_month
      AND i.income_category = 'tuition'
      AND i.status = 'received'
      AND coalesce(i.include_in_student_settlement, true) = true
  ) THEN
    RAISE EXCEPTION '该学生月份没有可结算的课时或学费收入，不能锁定。';
  END IF;

  SELECT * INTO v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    p_student_id, v_year_month
  );
  IF NOT FOUND THEN
    RAISE EXCEPTION '无法计算该学生月份的结算预览。';
  END IF;
  IF v_preview.business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能锁定结算。';
  END IF;

  SELECT * INTO STRICT v_overage
  FROM public.school_get_student_duration_overage_aggregate(
    p_student_id, v_year_month
  );
  IF v_overage.aggregation_basis <> 'live_s1_b_actual_aggregate'
     OR v_overage.duration_overage_fee_cny IS DISTINCT FROM round(
       v_overage.duration_overage_fee_jpy
       * coalesce(v_preview.exchange_rate, 0),
       2
     ) THEN
    RAISE EXCEPTION 'S1_C_LOCK_OVERAGE_AGGREGATE_DRIFT';
  END IF;

  IF coalesce(v_preview.adjustment_amount_cny, 0) <> 0
     OR nullif(trim(coalesce(v_preview.adjustment_reason, '')), '') IS NOT NULL
     OR nullif(trim(coalesce(v_preview.adjustment_note, '')), '') IS NOT NULL THEN
    v_adjustment_reason := format(
      '%s: %s (%s)',
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, ''),
      coalesce(v_preview.adjustment_amount_cny, 0)
    );
  ELSE
    v_adjustment_reason := NULL;
  END IF;

  INSERT INTO public.school_student_monthly_settlements (
    student_id, year_month, business_entity_id, preset_exchange_rate,
    planned_lesson_fee_jpy, planned_lesson_fee_cny, actual_lesson_fee_jpy,
    actual_lesson_fee_cny, previous_balance_cny, received_jpy, received_cny,
    received_equivalent_cny, system_difference_cny, adjustment_amount_cny,
    adjustment_reason, carryover_amount_cny, settlement_status, locked_at,
    note, created_at, updated_at,
    duration_overage_minutes, duration_overage_fee_jpy,
    duration_overage_fee_cny, duration_overage_actual_count,
    duration_overage_policy_version, duration_overage_source
  ) VALUES (
    p_student_id, v_year_month, v_preview.business_entity_id,
    coalesce(v_preview.exchange_rate, 0),
    coalesce(v_preview.planned_fee_jpy, 0),
    coalesce(v_preview.planned_fee_cny, 0),
    coalesce(v_preview.actual_fee_jpy, 0),
    coalesce(v_preview.actual_fee_cny, 0),
    coalesce(v_preview.carryover_cny, 0),
    coalesce(v_preview.received_jpy, 0),
    coalesce(v_preview.received_cny, 0),
    coalesce(v_preview.received_equivalent_cny, 0),
    coalesce(v_preview.final_due_cny, 0),
    coalesce(v_preview.adjustment_amount_cny, 0),
    v_adjustment_reason,
    coalesce(v_preview.locked_carryover_cny,
      coalesce(v_preview.final_due_cny, 0)),
    'locked', v_now, v_note, v_now, v_now,
    v_overage.duration_overage_minutes,
    v_overage.duration_overage_fee_jpy,
    v_overage.duration_overage_fee_cny,
    v_overage.duration_overage_actual_count,
    'student_duration_overage_v1',
    'monthly_settlement_lock'
  ) RETURNING id INTO v_settlement_id;

  IF v_preview.draft_id IS NOT NULL THEN
    INSERT INTO public.school_student_settlement_adjustments (
      settlement_id, student_id, year_month, business_entity_id,
      adjustment_amount_cny, adjustment_source, adjustment_reason, note,
      status, app_type, created_at, updated_at
    ) VALUES (
      v_settlement_id, p_student_id, v_year_month,
      v_preview.business_entity_id,
      coalesce(v_preview.adjustment_amount_cny, 0),
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, '锁定前差额调整'),
      v_preview.adjustment_note, 'posted', 'school', v_now, v_now
    );
    UPDATE public.school_student_settlement_adjustment_drafts d SET
      status = 'consumed', settlement_id = v_settlement_id,
      consumed_at = v_now, updated_by = current_user, updated_at = v_now
    WHERE d.id = v_preview.draft_id;
  END IF;

  RETURN QUERY
  SELECT m.id, m.student_id, m.year_month, m.business_entity_id,
    m.preset_exchange_rate, m.planned_lesson_fee_jpy,
    m.planned_lesson_fee_cny, m.actual_lesson_fee_jpy,
    m.actual_lesson_fee_cny, m.previous_balance_cny, m.received_jpy,
    m.received_cny, m.received_equivalent_cny, m.system_difference_cny,
    m.adjustment_amount_cny, m.carryover_amount_cny,
    m.settlement_status, m.locked_at, m.note, m.created_at, m.updated_at
  FROM public.school_student_monthly_settlements m
  WHERE m.id = v_settlement_id;
END
$function$;

COMMENT ON FUNCTION
  public.school_lock_student_monthly_settlement(uuid, text, text)
IS 'S1-C locks the authoritative R1D-E-C settlement preview and atomically freezes the source-month S1-B duration overage aggregate into the six nullable settlement snapshot fields. Zero-overage new locks receive an explicit zero snapshot; historical settlements are not updated.';

CREATE OR REPLACE FUNCTION public.school_relock_student_monthly_settlement(
  p_settlement_id uuid,
  p_note text DEFAULT NULL
)
RETURNS TABLE (
  settlement_id uuid, student_id uuid, year_month text,
  business_entity_id uuid, preset_exchange_rate numeric,
  planned_lesson_fee_jpy numeric, planned_lesson_fee_cny numeric,
  actual_lesson_fee_jpy numeric, actual_lesson_fee_cny numeric,
  previous_balance_cny numeric, received_jpy numeric, received_cny numeric,
  received_equivalent_cny numeric, system_difference_cny numeric,
  adjustment_amount_cny numeric, carryover_amount_cny numeric,
  settlement_status text, locked_at timestamptz, unlocked_at timestamptz,
  unlock_reason text, note text, created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_preview record;
  v_overage record;
  v_adjustment_reason text;
BEGIN
  IF p_settlement_id IS NULL THEN
    RAISE EXCEPTION '请选择要重新锁定的学生月度结算。';
  END IF;
  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id = p_settlement_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '没有找到对应的学生月度结算。';
  END IF;
  IF coalesce(v_settlement.settlement_status, '') <> 'unlocked' THEN
    RAISE EXCEPTION '只有已撤销锁定的学生月度结算可以重新锁定。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_legacy_settlement_snapshot_basis_evidence e
    WHERE e.settlement_snapshot_id = v_settlement.id
  ) THEN
    RAISE EXCEPTION 'R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_settlement_adjustments a
    WHERE a.settlement_id = v_settlement.id
      AND a.status = 'posted'
  ) THEN
    RAISE EXCEPTION '该结算已有差额调整记录，不能通过重新锁定重算快照。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_student_settlement_carryovers c
    WHERE c.source_settlement_id = v_settlement.id
      AND coalesce(c.status, 'active') = 'active'
  ) THEN
    RAISE EXCEPTION '该结算已生成有效结转，不能重新锁定。';
  END IF;

  LOCK TABLE public.school_lesson_records IN SHARE MODE;
  LOCK TABLE public.school_teacher_wage_lock_details IN SHARE MODE;

  PERFORM public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id,
    v_settlement.year_month,
    '重新锁定学生月度结算'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_list_r1d_e_c_student_month_lessons(
      v_settlement.student_id, v_settlement.year_month
    ) resolved
    JOIN public.school_lesson_records l ON l.id = resolved.lesson_id
    WHERE NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.school_income_records i
    WHERE i.app_type = 'school'
      AND i.student_id = v_settlement.student_id
      AND coalesce(i.settlement_month, i.year_month) =
        v_settlement.year_month
      AND i.income_category = 'tuition'
      AND i.status = 'received'
      AND coalesce(i.include_in_student_settlement, true) = true
  ) THEN
    RAISE EXCEPTION '该学生月份没有可结算的课时或学费收入，不能重新锁定。';
  END IF;

  SELECT * INTO v_preview
  FROM public.school_get_student_monthly_settlement_preview(
    v_settlement.student_id, v_settlement.year_month
  );
  IF NOT FOUND THEN
    RAISE EXCEPTION '无法计算该学生月份的结算预览。';
  END IF;
  IF v_preview.business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能重新锁定结算。';
  END IF;

  SELECT * INTO STRICT v_overage
  FROM public.school_get_student_duration_overage_aggregate(
    v_settlement.student_id, v_settlement.year_month
  );
  IF v_overage.aggregation_basis <> 'live_s1_b_actual_aggregate'
     OR v_overage.duration_overage_fee_cny IS DISTINCT FROM round(
       v_overage.duration_overage_fee_jpy
       * coalesce(v_preview.exchange_rate, 0),
       2
     ) THEN
    RAISE EXCEPTION 'S1_C_RELOCK_OVERAGE_AGGREGATE_DRIFT';
  END IF;

  IF coalesce(v_preview.adjustment_amount_cny, 0) <> 0
     OR nullif(trim(coalesce(v_preview.adjustment_reason, '')), '') IS NOT NULL
     OR nullif(trim(coalesce(v_preview.adjustment_note, '')), '') IS NOT NULL THEN
    v_adjustment_reason := format(
      '%s: %s (%s)',
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, ''),
      coalesce(v_preview.adjustment_amount_cny, 0)
    );
  ELSE
    v_adjustment_reason := NULL;
  END IF;

  UPDATE public.school_student_monthly_settlements m SET
    business_entity_id = v_preview.business_entity_id,
    preset_exchange_rate = coalesce(v_preview.exchange_rate, 0),
    planned_lesson_fee_jpy = coalesce(v_preview.planned_fee_jpy, 0),
    planned_lesson_fee_cny = coalesce(v_preview.planned_fee_cny, 0),
    actual_lesson_fee_jpy = coalesce(v_preview.actual_fee_jpy, 0),
    actual_lesson_fee_cny = coalesce(v_preview.actual_fee_cny, 0),
    previous_balance_cny = coalesce(v_preview.carryover_cny, 0),
    received_jpy = coalesce(v_preview.received_jpy, 0),
    received_cny = coalesce(v_preview.received_cny, 0),
    received_equivalent_cny =
      coalesce(v_preview.received_equivalent_cny, 0),
    system_difference_cny = coalesce(v_preview.final_due_cny, 0),
    adjustment_amount_cny = coalesce(v_preview.adjustment_amount_cny, 0),
    adjustment_reason = v_adjustment_reason,
    carryover_amount_cny = coalesce(
      v_preview.locked_carryover_cny,
      coalesce(v_preview.final_due_cny, 0)
    ),
    duration_overage_minutes = v_overage.duration_overage_minutes,
    duration_overage_fee_jpy = v_overage.duration_overage_fee_jpy,
    duration_overage_fee_cny = v_overage.duration_overage_fee_cny,
    duration_overage_actual_count = v_overage.duration_overage_actual_count,
    duration_overage_policy_version = 'student_duration_overage_v1',
    duration_overage_source = 'monthly_settlement_lock',
    settlement_status = 'locked',
    locked_at = v_now,
    note = v_note,
    updated_at = v_now
  WHERE m.id = v_settlement.id;

  IF v_preview.draft_id IS NOT NULL THEN
    INSERT INTO public.school_student_settlement_adjustments (
      settlement_id, student_id, year_month, business_entity_id,
      adjustment_amount_cny, adjustment_source, adjustment_reason, note,
      status, app_type, created_at, updated_at
    ) VALUES (
      v_settlement.id, v_settlement.student_id, v_settlement.year_month,
      v_preview.business_entity_id,
      coalesce(v_preview.adjustment_amount_cny, 0),
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, '重新锁定前差额调整'),
      v_preview.adjustment_note, 'posted', 'school', v_now, v_now
    );
    UPDATE public.school_student_settlement_adjustment_drafts d SET
      status = 'consumed', settlement_id = v_settlement.id,
      consumed_at = v_now, updated_by = current_user, updated_at = v_now
    WHERE d.id = v_preview.draft_id;
  END IF;

  RETURN QUERY
  SELECT m.id, m.student_id, m.year_month, m.business_entity_id,
    m.preset_exchange_rate, m.planned_lesson_fee_jpy,
    m.planned_lesson_fee_cny, m.actual_lesson_fee_jpy,
    m.actual_lesson_fee_cny, m.previous_balance_cny, m.received_jpy,
    m.received_cny, m.received_equivalent_cny, m.system_difference_cny,
    m.adjustment_amount_cny, m.carryover_amount_cny,
    m.settlement_status, m.locked_at, m.unlocked_at, m.unlock_reason,
    m.note, m.created_at, m.updated_at
  FROM public.school_student_monthly_settlements m
  WHERE m.id = v_settlement.id;
END
$function$;

COMMENT ON FUNCTION
  public.school_relock_student_monthly_settlement(uuid, text)
IS 'S1-C relocks only eligible non-legacy snapshots and replaces, rather than adds to, the six-field source-month overage snapshot from the current frozen S1-B fact aggregate. Existing wage, adjustment, carryover, and legacy immutability guards remain unchanged.';

DO $postflight$
DECLARE
  v_baseline s1_c_deploy_baseline%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_baseline FROM s1_c_deploy_baseline;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE student_duration_overage_policy_version IS NOT NULL)
       <> v_baseline.lesson_overage_nonnull
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
         WHERE duration_overage_policy_version IS NOT NULL)
       <> v_baseline.settlement_overage_nonnull THEN
    RAISE EXCEPTION 'S1_C_DEPLOY_CHANGED_HISTORICAL_OVERAGE_DATA';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills)
       <> v_baseline.bill_count
     OR (SELECT count(*) FROM public.school_income_records)
       <> v_baseline.income_count THEN
    RAISE EXCEPTION 'S1_C_DEPLOY_CHANGED_BILL_OR_INCOME_DATA';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_preview(uuid,text)'::regprocedure
     )) <> '1ddcfdd0344ba0ea3cf06d12058796ba'
     OR md5(pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> 'dfeaa0243b27999724cc06bd1f1efbb6'
     OR md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1' THEN
    RAISE EXCEPTION 'S1_C_PROTECTED_FUNCTION_CHANGED';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_C_R0_CHANGED';
  END IF;
END
$postflight$;

SELECT p.oid::regprocedure::text AS signature,
       md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'school_get_student_duration_overage_aggregate',
    'school_get_student_monthly_settlement_summary',
    'school_lock_student_monthly_settlement',
    'school_relock_student_monthly_settlement'
  )
ORDER BY signature;

COMMIT;
