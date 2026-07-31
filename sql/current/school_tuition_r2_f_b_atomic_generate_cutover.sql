-- R2-F-B atomic tuition generation database cutover.
-- Transaction control is intentionally supplied by the deployment driver so
-- the exact same bytes can be rehearsed under ROLLBACK and deployed under COMMIT.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_b_hardening_only}
\echo 'R2_F_B_ATOMIC_GENERATE_HARDENING_FUNCTIONS_ONLY'
DO $hardening_preflight$
BEGIN
  IF to_regprocedure(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'
     ) IS NULL
     OR to_regprocedure(
       'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'
     ) IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_HARDENING_TARGET_FUNCTION_MISSING';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_B_HARDENING_R0_BASELINE_MISMATCH';
  END IF;
END
$hardening_preflight$;
\else
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_F_B_R0_GATE_BASELINE_MISMATCH';
  END IF;
END
$preflight$;

CREATE TABLE public.school_tuition_atomic_writer_context (
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  writer_source text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT school_tuition_atomic_writer_context_pkey
    PRIMARY KEY (backend_pid, transaction_id),
  CONSTRAINT school_tuition_atomic_writer_context_source_check
    CHECK (writer_source IN (
      'student_tuition_atomic_generate_v1',
      'legacy_tuition_cancel'
    ))
);

COMMENT ON TABLE public.school_tuition_atomic_writer_context IS
  'Private transaction capability used by authoritative tuition writers. It must be empty outside an active writer call and is never client writable.';

REVOKE ALL ON TABLE public.school_tuition_atomic_writer_context
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.school_guard_r0_tuition_business_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_income_record_id uuid;
  v_income_source_type text;
  v_authoritative_writer boolean := false;
BEGIN
  IF tg_table_name IN ('school_student_tuition_bills','school_income_records') THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.school_tuition_atomic_writer_context context_row
      WHERE context_row.backend_pid = pg_catalog.pg_backend_pid()
        AND context_row.transaction_id = pg_catalog.txid_current()
        AND context_row.writer_source IN (
          'student_tuition_atomic_generate_v1','legacy_tuition_cancel'
        )
    ) INTO v_authoritative_writer;
  END IF;

  IF tg_table_name = 'school_student_tuition_bills' THEN
    IF NOT v_authoritative_writer THEN
      PERFORM public.school_require_feature_gate_state(
        'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
        '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
      );
      RAISE EXCEPTION 'TUITION_DIRECT_DML_FORBIDDEN: tuition bills are writable only by the authoritative atomic writer.';
    END IF;
  ELSIF tg_table_name = 'school_income_records' THEN
    IF coalesce(CASE WHEN tg_op <> 'DELETE' THEN new.source_type END,'') = 'student_tuition_bill'
       OR coalesce(CASE WHEN tg_op <> 'INSERT' THEN old.source_type END,'') = 'student_tuition_bill' THEN
      IF NOT v_authoritative_writer THEN
        PERFORM public.school_require_feature_gate_state(
          'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
          '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
        );
        RAISE EXCEPTION 'TUITION_DIRECT_DML_FORBIDDEN: tuition income is writable only by an authoritative tuition workflow.';
      END IF;
    END IF;
  ELSIF tg_table_name = 'school_personal_cash_income_linkage_events' THEN
    v_income_record_id := coalesce(
      CASE WHEN tg_op <> 'DELETE' THEN new.income_record_id END,
      CASE WHEN tg_op <> 'INSERT' THEN old.income_record_id END
    );
    BEGIN
      SELECT income.source_type INTO STRICT v_income_source_type
      FROM public.school_income_records income
      WHERE income.id = v_income_record_id;
    EXCEPTION
      WHEN no_data_found THEN
        IF coalesce(CASE WHEN tg_op <> 'DELETE' THEN new.source_event_type END,'') = 'tuition_income_received'
           OR coalesce(CASE WHEN tg_op <> 'INSERT' THEN old.source_event_type END,'') = 'tuition_income_received' THEN
          RAISE EXCEPTION 'TUITION_CASH_SUBMISSION_BLOCKED: 学费收入来源无法验证，禁止提交 Cash。';
        END IF;
        v_income_source_type := NULL;
      WHEN OTHERS THEN
        RAISE EXCEPTION 'TUITION_CASH_SUBMISSION_BLOCKED: 学费 Cash gate 读取失败，禁止提交 Cash。';
    END;
    IF v_income_source_type = 'student_tuition_bill' THEN
      PERFORM public.school_require_feature_gate_state(
        'student_tuition_cash_submit','enabled','TUITION_CASH_SUBMISSION_BLOCKED',
        '学费收入 Cash 提交正在进行资金一致性整改，当前禁止提交。'
      );
    END IF;
  END IF;

  IF tg_op = 'DELETE' THEN RETURN old; END IF;
  RETURN new;
END
$function$;

REVOKE ALL ON FUNCTION public.school_guard_r0_tuition_business_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY school_allow_all_income_records ON public.school_income_records;

CREATE POLICY school_select_operational_income_records
ON public.school_income_records FOR SELECT TO PUBLIC
USING (status <> 'incident_quarantined' AND operational_excluded IS NOT TRUE);

CREATE POLICY school_insert_non_tuition_income_records
ON public.school_income_records FOR INSERT TO PUBLIC
WITH CHECK (
  status <> 'incident_quarantined'
  AND operational_excluded IS NOT TRUE
  AND source_type IS DISTINCT FROM 'student_tuition_bill'
);

CREATE POLICY school_update_non_tuition_income_records
ON public.school_income_records FOR UPDATE TO PUBLIC
USING (
  status <> 'incident_quarantined'
  AND operational_excluded IS NOT TRUE
  AND source_type IS DISTINCT FROM 'student_tuition_bill'
)
WITH CHECK (
  status <> 'incident_quarantined'
  AND operational_excluded IS NOT TRUE
  AND source_type IS DISTINCT FROM 'student_tuition_bill'
);

CREATE POLICY school_delete_non_tuition_income_records
ON public.school_income_records FOR DELETE TO PUBLIC
USING (
  status <> 'incident_quarantined'
  AND operational_excluded IS NOT TRUE
  AND source_type IS DISTINCT FROM 'student_tuition_bill'
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE
ON public.school_student_tuition_bills
FROM anon, authenticated, service_role;

ALTER TABLE public.school_student_tuition_bill_lessons
  DROP CONSTRAINT school_tuition_bill_lessons_r2_e_aircon_context_check;

ALTER TABLE public.school_student_tuition_bill_lessons
  ADD CONSTRAINT school_tuition_bill_lessons_r2_f_b_fee_context_check
  CHECK (
    fee_calculation_version_snapshot IS NULL
    OR (
      aircon_rate_id_snapshot IS NULL
      AND lesson_fee_jpy_snapshot = base_lesson_fee_jpy_snapshot + aircon_fee_jpy_snapshot
      AND (
        (fee_calculation_version_snapshot = 'planned_weekend_aircon_v1'
         AND aircon_fee_jpy_snapshot =
           aircon_unit_price_jpy_snapshot * aircon_billable_hours_snapshot)
        OR
        (fee_calculation_version_snapshot = 'legacy_base_only'
         AND aircon_unit_price_jpy_snapshot = 0
         AND aircon_billable_hours_snapshot = 0
         AND aircon_fee_jpy_snapshot = 0)
      )
    )
  ) NOT VALID;

ALTER TABLE public.school_student_tuition_bill_lessons
  VALIDATE CONSTRAINT school_tuition_bill_lessons_r2_f_b_fee_context_check;
\endif

CREATE OR REPLACE FUNCTION public.school_build_student_tuition_generation_snapshot(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
RETURNS TABLE (
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  carryover_evidence jsonb,
  candidate_count integer,
  total_lesson_count integer,
  total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,
  total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  candidate_uuid_md5 text,
  candidate_manifest_sha256 text,
  generation_manifest_sha256 text,
  candidates jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_student public.school_students%ROWTYPE;
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_locked_count integer;
  v_settlement_row_count integer;
  v_active_bill_count integer;
  v_settlement_income_count integer;
  v_active_carryover_count integer;
  v_active_draft_count integer;
  v_previous_preview record;
  v_overage record;
  v_carryover numeric;
  v_carryover_evidence jsonb;
  v_carryover_evidence_sha text;
  v_count integer;
  v_distinct_count integer;
  v_lesson_count integer;
  v_hours numeric;
  v_base numeric;
  v_aircon numeric;
  v_total numeric;
  v_uuid_md5 text;
  v_candidate_manifest text;
  v_generation_manifest text;
  v_candidates jsonb;
  v_contract_valid boolean;
  v_amount_cny numeric;
BEGIN
  IF p_student_id IS NULL THEN RAISE EXCEPTION 'R2_F_B_STUDENT_REQUIRED'; END IF;
  IF v_month IS NULL OR v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate <= 0 THEN
    RAISE EXCEPTION 'R2_F_B_EXCHANGE_RATE_INVALID';
  END IF;

  SELECT student.* INTO v_student
  FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND THEN RAISE EXCEPTION 'R2_F_B_STUDENT_NOT_FOUND'; END IF;
  IF coalesce(v_student.status,'') IN ('inactive','disabled','archived') THEN
    RAISE EXCEPTION 'R2_F_B_STUDENT_INACTIVE';
  END IF;
  IF v_student.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_BUSINESS_ENTITY_REQUIRED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id=p_student_id
      AND settlement.business_entity_id=v_student.business_entity_id
      AND settlement.year_month=v_month
      AND settlement.settlement_status='locked'
  ) THEN
    RAISE EXCEPTION 'R2_F_B_TARGET_SETTLEMENT_LOCKED';
  END IF;

  v_previous_month := pg_catalog.to_char(
    (pg_catalog.to_date(v_month||'-01','YYYY-MM-DD')-interval '1 month')::date,
    'YYYY-MM'
  );

  SELECT count(*)::integer INTO v_locked_count
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked';
  IF v_locked_count > 1 THEN
    RAISE EXCEPTION 'R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS';
  END IF;

  SELECT settlement.* INTO v_previous_settlement
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked'
  ORDER BY settlement.locked_at DESC NULLS LAST,
    settlement.updated_at DESC NULLS LAST,settlement.created_at DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    v_carryover := pg_catalog.round(coalesce(v_previous_settlement.carryover_amount_cny,0),2);
    v_carryover_evidence := jsonb_build_object(
      'mode','locked_settlement_v1',
      'settlement_month',v_previous_month,
      'settlement_id',v_previous_settlement.id,
      'settlement_status',v_previous_settlement.settlement_status,
      'locked_at',v_previous_settlement.locked_at,
      'updated_at',v_previous_settlement.updated_at,
      'carryover_amount_cny',v_carryover
    );
  ELSE
    SELECT count(*)::integer INTO v_settlement_row_count
    FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id=p_student_id
      AND settlement.business_entity_id=v_student.business_entity_id
      AND settlement.year_month=v_previous_month;
    SELECT count(*)::integer INTO v_active_bill_count
    FROM public.school_student_tuition_bills bill
    WHERE bill.student_id=p_student_id
      AND bill.business_entity_id=v_student.business_entity_id
      AND bill.billing_month=v_previous_month
      AND bill.status <> 'cancelled';
    SELECT count(*)::integer INTO v_settlement_income_count
    FROM public.school_income_records income
    WHERE income.student_id=p_student_id
      AND coalesce(income.settlement_month,income.year_month)=v_previous_month
      AND income.income_category='tuition'
      AND income.status <> 'cancelled'
      AND coalesce(income.include_in_student_settlement,true);
    SELECT count(*)::integer INTO v_active_carryover_count
    FROM public.school_student_settlement_carryovers carryover
    WHERE carryover.student_id=p_student_id
      AND carryover.to_year_month=v_month
      AND coalesce(carryover.status,'active')='active';
    SELECT count(*)::integer INTO v_active_draft_count
    FROM public.school_student_settlement_adjustment_drafts draft
    WHERE draft.student_id=p_student_id AND draft.year_month=v_previous_month
      AND draft.app_type='school' AND draft.status='active';
    SELECT * INTO STRICT v_previous_preview
    FROM public.school_get_student_monthly_settlement_preview(
      p_student_id,v_previous_month
    );
    SELECT * INTO STRICT v_overage
    FROM public.school_get_student_duration_overage_aggregate(
      p_student_id,v_previous_month
    );

    IF v_settlement_row_count<>0 OR v_active_bill_count<>0
       OR v_settlement_income_count<>0 OR v_active_carryover_count<>0
       OR v_active_draft_count<>0
       OR coalesce(v_previous_preview.carryover_cny,0)<>0
       OR coalesce(v_previous_preview.planned_fee_jpy,0)<>0
       OR coalesce(v_previous_preview.received_jpy,0)<>0
       OR coalesce(v_previous_preview.received_cny,0)<>0
       OR coalesce(v_previous_preview.adjustment_amount_cny,0)<>0
       OR coalesce(v_overage.duration_overage_actual_count,0)<>0
       OR coalesce(v_overage.duration_overage_minutes,0)<>0
       OR coalesce(v_overage.duration_overage_fee_jpy,0)<>0
       OR coalesce(v_overage.duration_overage_fee_cny,0)<>0 THEN
      RAISE EXCEPTION 'R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED';
    END IF;

    v_carryover := 0;
    v_carryover_evidence := jsonb_build_object(
      'mode','zero_carryover_verified_v1',
      'settlement_month',v_previous_month,
      'settlement_row_count',v_settlement_row_count,
      'active_bill_count',v_active_bill_count,
      'settlement_income_count',v_settlement_income_count,
      'active_carryover_count',v_active_carryover_count,
      'active_adjustment_draft_count',v_active_draft_count,
      'planned_fee_jpy',coalesce(v_previous_preview.planned_fee_jpy,0),
      'received_jpy',coalesce(v_previous_preview.received_jpy,0),
      'received_cny',coalesce(v_previous_preview.received_cny,0),
      'inherited_carryover_cny',coalesce(v_previous_preview.carryover_cny,0),
      'adjustment_amount_cny',coalesce(v_previous_preview.adjustment_amount_cny,0),
      'duration_overage_actual_count',coalesce(v_overage.duration_overage_actual_count,0),
      'duration_overage_minutes',coalesce(v_overage.duration_overage_minutes,0),
      'duration_overage_fee_jpy',coalesce(v_overage.duration_overage_fee_jpy,0),
      'duration_overage_fee_cny',coalesce(v_overage.duration_overage_fee_cny,0)
    );
  END IF;

  v_carryover_evidence_sha := encode(sha256(convert_to(v_carryover_evidence::text,'UTF8')),'hex');

  WITH candidate_rows AS MATERIALIZED (
    SELECT candidate.*,
      lesson.teacher_id,lesson.subject_id,lesson.updated_at AS source_updated_at,
      coalesce(lesson.aircon_billable_hours_snapshot,0)::numeric AS aircon_billable_hours,
      lesson.lesson_venue_id,lesson.lesson_venue AS lesson_venue_code
    FROM public.school_list_student_tuition_charge_candidates(
      p_student_id,v_student.business_entity_id,v_month,false
    ) candidate
    JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
  ), canonical_lines AS (
    SELECT detail.*,
      jsonb_build_object(
        'planned_lesson_id',detail.planned_lesson_id,
        'student_id',detail.student_id,
        'business_entity_id',detail.business_entity_id,
        'billing_month',detail.candidate_billing_month,
        'billing_week_start_date',detail.billing_week_start_date,
        'lesson_date',detail.lesson_date,
        'teacher_id',detail.teacher_id,
        'subject_id',detail.subject_id,
        'lesson_count',detail.lesson_count,
        'duration_hours',detail.duration_hours,
        'unit_price_jpy',detail.unit_price,
        'base_lesson_fee_jpy',detail.base_lesson_fee_jpy,
        'aircon_rate_jpy_per_hour',detail.aircon_rate_jpy_per_hour,
        'aircon_billable_hours',detail.aircon_billable_hours,
        'aircon_fee_jpy',detail.aircon_fee_jpy,
        'course_total_jpy',detail.lesson_total_fee_jpy,
        'fee_policy_version',coalesce(detail.aircon_policy_version,'legacy_base_only'),
        'aircon_charge_status',detail.aircon_charge_status,
        'lesson_venue_id',detail.lesson_venue_id,
        'lesson_venue_code',detail.lesson_venue_code,
        'source_lesson_updated_at',detail.source_updated_at,
        'complete_row_hash',detail.complete_row_hash
      ) AS canonical_line
    FROM candidate_rows detail
  ), hashed_lines AS (
    SELECT line.*,
      encode(sha256(convert_to(line.canonical_line::text,'UTF8')),'hex')
        AS candidate_line_hash
    FROM canonical_lines line
  ), aggregated AS (
    SELECT count(*)::integer AS candidate_count,
      count(DISTINCT detail.planned_lesson_id)::integer AS distinct_count,
      coalesce(sum(detail.lesson_count),0)::integer AS lesson_count,
      coalesce(sum(detail.duration_hours),0)::numeric AS hours,
      coalesce(sum(detail.base_lesson_fee_jpy),0)::numeric AS base_fee,
      coalesce(sum(detail.aircon_fee_jpy),0)::numeric AS aircon_fee,
      coalesce(sum(detail.lesson_total_fee_jpy),0)::numeric AS total_fee,
      md5(string_agg(detail.planned_lesson_id::text,',' ORDER BY detail.planned_lesson_id::text)) AS uuid_md5,
      encode(sha256(convert_to(
        string_agg(detail.candidate_line_hash,E'\n'
          ORDER BY detail.billing_week_start_date,detail.lesson_date,
          detail.planned_lesson_id)||E'\n','UTF8')),'hex') AS candidate_manifest,
      jsonb_agg(detail.canonical_line||jsonb_build_object(
        'candidate_line_hash',detail.candidate_line_hash
      ) ORDER BY detail.billing_week_start_date,detail.lesson_date,
        detail.planned_lesson_id) AS candidates,
      bool_and(detail.student_id=p_student_id
        AND detail.business_entity_id=v_student.business_entity_id
        AND detail.candidate_billing_month=v_month
        AND detail.billing_week_start_date IS NOT NULL
        AND extract(isodow FROM detail.billing_week_start_date)=1
        AND to_char(detail.billing_week_start_date,'YYYY-MM')=v_month
        AND detail.lesson_total_fee_jpy=detail.base_lesson_fee_jpy+detail.aircon_fee_jpy
        AND detail.aircon_rate_jpy_per_hour>=0
        AND detail.aircon_billable_hours>=0
        AND detail.aircon_fee_jpy>=0
        AND (coalesce(detail.aircon_policy_version,'legacy_base_only')<>'planned_weekend_aircon_v1'
             OR detail.aircon_fee_jpy=detail.aircon_rate_jpy_per_hour*detail.aircon_billable_hours)
      ) AS contract_valid
    FROM hashed_lines detail
  )
  SELECT aggregated.candidate_count,aggregated.distinct_count,
    aggregated.lesson_count,aggregated.hours,aggregated.base_fee,
    aggregated.aircon_fee,aggregated.total_fee,aggregated.uuid_md5,
    aggregated.candidate_manifest,aggregated.candidates,
    aggregated.contract_valid
  INTO v_count,v_distinct_count,v_lesson_count,v_hours,v_base,v_aircon,
    v_total,v_uuid_md5,v_candidate_manifest,v_candidates,v_contract_valid
  FROM aggregated;

  IF v_count IS NULL OR v_count<=0 THEN RAISE EXCEPTION 'R2_F_B_CANDIDATES_EMPTY'; END IF;
  IF v_count IS DISTINCT FROM v_distinct_count THEN RAISE EXCEPTION 'R2_F_B_DUPLICATE_CANDIDATE_UUID'; END IF;
  IF v_contract_valid IS DISTINCT FROM true OR v_total IS DISTINCT FROM v_base+v_aircon THEN
    RAISE EXCEPTION 'R2_F_B_CANDIDATE_CONTRACT_MISMATCH';
  END IF;

  v_amount_cny := round(v_total*p_billing_exchange_rate+v_carryover,2);
  IF v_amount_cny<=0 THEN RAISE EXCEPTION 'R2_F_B_BILLING_AMOUNT_INVALID'; END IF;

  v_generation_manifest := encode(sha256(convert_to(concat_ws('|',
    'student_tuition_atomic_generate_v1',p_student_id::text,
    v_student.business_entity_id::text,v_month,v_candidate_manifest,
    v_uuid_md5,v_count::text,v_lesson_count::text,v_hours::text,
    v_base::text,v_aircon::text,v_total::text,p_billing_exchange_rate::text,
    v_previous_month,coalesce(v_previous_settlement.id::text,'zero'),
    v_carryover::text,v_carryover_evidence_sha,v_amount_cny::text
  ),'UTF8')),'hex');

  RETURN QUERY SELECT p_student_id,v_student.business_entity_id,v_month,
    v_previous_month,v_previous_settlement.id,v_carryover,v_carryover_evidence,
    v_count,v_lesson_count,v_hours,v_base,v_aircon,v_total,
    p_billing_exchange_rate,v_amount_cny,v_uuid_md5,v_candidate_manifest,
    v_generation_manifest,v_candidates;
END
$function$;

REVOKE ALL ON FUNCTION public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)
  FROM PUBLIC, anon, authenticated, service_role;

\if :{?r2_f_b_hardening_only}
\else
DROP FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric);

CREATE FUNCTION public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric
)
RETURNS TABLE (
  feature_state text,student_id uuid,business_entity_id uuid,billing_month text,
  previous_settlement_month text,previous_settlement_id uuid,
  previous_carryover_cny numeric,candidate_count integer,
  total_lesson_count integer,total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,bill_amount_jpy numeric,currency text,
  billing_exchange_rate numeric,billing_amount_cny numeric,
  billing_amount_currency text,existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,existing_income_record_id uuid,
  existing_income_status text,candidate_uuid_md5 text,
  candidate_manifest_sha256 text,generation_manifest_sha256 text,
  candidates jsonb,message text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_snapshot record;
  v_existing public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_message text := 'validation preview only; no business data written';
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_preview','validation_preview_only','TUITION_PREVIEW_BLOCKED',
    '学费预览 gate 不可用，已按 fail-closed 拒绝。'
  );
  SELECT * INTO STRICT v_snapshot
  FROM public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate
  );
  SELECT bill.* INTO v_existing
  FROM public.school_student_tuition_bills bill
  WHERE bill.student_id=v_snapshot.student_id
    AND bill.business_entity_id=v_snapshot.business_entity_id
    AND bill.billing_month=v_snapshot.billing_month
    AND bill.status IN ('draft','income_created')
  ORDER BY bill.updated_at DESC NULLS LAST,bill.created_at DESC NULLS LAST
  LIMIT 1;
  IF FOUND THEN
    SELECT income.* INTO v_income FROM public.school_income_records income
    WHERE income.id=v_existing.income_record_id;
    v_message := 'existing tuition billing identity requires idempotent writer resolution';
  END IF;
  RETURN QUERY SELECT 'validation_preview_only'::text,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY'::text,
    v_snapshot.billing_exchange_rate,v_snapshot.billing_amount_cny,'CNY'::text,
    v_existing.id,v_existing.status,v_existing.income_record_id,v_income.status,
    v_snapshot.candidate_uuid_md5,v_snapshot.candidate_manifest_sha256,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidates,v_message;
END
$function$;

REVOKE ALL ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.school_get_student_tuition_validation_preview_details(uuid,text,numeric) IS
  'R2-F-B validation preview. Returns an opaque generation manifest over canonical candidates, exchange rate and locked-or-proven-zero carryover evidence. Writes nothing.';
\endif

CREATE OR REPLACE FUNCTION public.school_validate_tuition_bill_lessons_for_bill(p_bill_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_count integer; v_lesson_count integer; v_hours numeric;
  v_base numeric; v_aircon numeric; v_fee numeric; v_bad_rows integer;
  v_recomputed_candidate_manifest text;
BEGIN
  IF p_bill_id IS NULL THEN RETURN; END IF;
  SELECT bill.* INTO v_bill FROM public.school_student_tuition_bills bill
  WHERE bill.id=p_bill_id;
  IF NOT FOUND OR v_bill.billing_role IS NULL THEN RETURN; END IF;
  SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.canonical_bill_id=v_bill.id;

  IF v_identity.source='atomic_charge'
     AND v_identity.evidence->>'generation_source'='student_tuition_atomic_generate_v1' THEN
    SELECT count(*)::integer,coalesce(sum(rel.lesson_count_snapshot),0)::integer,
      coalesce(sum(rel.duration_hours_snapshot),0),
      coalesce(sum(rel.base_lesson_fee_jpy_snapshot),0),
      coalesce(sum(rel.aircon_fee_jpy_snapshot),0),
      coalesce(sum(rel.lesson_fee_jpy_snapshot),0),
      count(*) FILTER (WHERE
        rel.relation_role IS DISTINCT FROM 'canonical_charge'
        OR rel.student_id_snapshot IS DISTINCT FROM v_bill.student_id
        OR rel.business_entity_id_snapshot IS DISTINCT FROM v_bill.business_entity_id
        OR rel.billing_month_snapshot IS DISTINCT FROM v_bill.billing_month
        OR rel.attribution_confidence IS DISTINCT FROM 'high'
        OR rel.snapshot_source IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
        OR rel.backfill_batch_id IS NOT NULL
        OR rel.line_no>jsonb_array_length(v_bill.source_snapshot->'candidate_lines')
        OR (v_bill.source_snapshot->'planned_lesson_ids'->>(rel.line_no-1))::uuid
             IS DISTINCT FROM rel.planned_lesson_id
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'planned_lesson_id')::uuid
             IS DISTINCT FROM rel.planned_lesson_id
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'billing_month')
             IS DISTINCT FROM rel.billing_month_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'billing_week_start_date')::date
             IS DISTINCT FROM rel.week_start_date_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'lesson_date')::date
             IS DISTINCT FROM rel.scheduled_lesson_date_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'lesson_count')::integer
             IS DISTINCT FROM rel.lesson_count_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'duration_hours')::numeric
             IS DISTINCT FROM rel.duration_hours_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'unit_price_jpy')::numeric
             IS DISTINCT FROM rel.unit_price_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'base_lesson_fee_jpy')::numeric
             IS DISTINCT FROM rel.base_lesson_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_rate_jpy_per_hour')::integer
             IS DISTINCT FROM rel.aircon_unit_price_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_billable_hours')::numeric
             IS DISTINCT FROM rel.aircon_billable_hours_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_fee_jpy')::numeric
             IS DISTINCT FROM rel.aircon_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'course_total_jpy')::numeric
             IS DISTINCT FROM rel.lesson_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'fee_policy_version')
             IS DISTINCT FROM rel.fee_calculation_version_snapshot
        OR coalesce(v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'complete_row_hash','')=''
        OR coalesce(v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash','')
             !~ '^[0-9a-f]{64}$'
        OR encode(sha256(convert_to(
             ((v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1))-'candidate_line_hash')::text,
             'UTF8'
           )),'hex') IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash'
        OR rel.source_snapshot->>'complete_row_hash' IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'complete_row_hash'
        OR rel.source_snapshot->>'candidate_line_hash' IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash'
        OR (rel.source_snapshot-ARRAY[
             'generation_manifest_sha256','candidate_manifest_sha256'
           ]::text[]) IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)
        OR rel.source_snapshot->>'candidate_manifest_sha256'
             IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
        OR rel.source_snapshot->>'generation_manifest_sha256'
             IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
      )::integer
    INTO v_count,v_lesson_count,v_hours,v_base,v_aircon,v_fee,v_bad_rows
    FROM public.school_student_tuition_bill_lessons rel
    WHERE rel.tuition_bill_id=v_bill.id;

    SELECT encode(sha256(convert_to(
      string_agg(line.value->>'candidate_line_hash',E'\n' ORDER BY line.ordinality)
        ||E'\n','UTF8')),'hex')
    INTO v_recomputed_candidate_manifest
    FROM jsonb_array_elements(v_bill.source_snapshot->'candidate_lines')
      WITH ORDINALITY line(value,ordinality);

    IF v_bill.source_snapshot->>'generation_source' IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
       OR v_identity.evidence->>'generation_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
       OR v_identity.evidence->>'candidate_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_recomputed_candidate_manifest
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_identity.evidence->>'business_entity_id'
            IS DISTINCT FROM v_bill.business_entity_id::text
       OR jsonb_array_length(v_bill.source_snapshot->'candidate_lines') IS DISTINCT FROM v_count
       OR jsonb_array_length(v_bill.source_snapshot->'planned_lesson_ids') IS DISTINCT FROM v_count
       OR (v_bill.source_snapshot->>'candidate_count')::integer IS DISTINCT FROM v_count
       OR (v_bill.source_snapshot->>'total_lesson_count')::integer IS DISTINCT FROM v_lesson_count
       OR (v_bill.source_snapshot->>'total_duration_hours')::numeric IS DISTINCT FROM v_hours
       OR (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric IS DISTINCT FROM v_base
       OR (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric IS DISTINCT FROM v_aircon
       OR (v_bill.source_snapshot->>'total_fee_jpy')::numeric IS DISTINCT FROM v_fee
       OR v_count IS DISTINCT FROM v_bill.planned_lesson_count
       OR v_hours IS DISTINCT FROM v_bill.planned_lesson_hours
       OR v_fee IS DISTINCT FROM v_bill.planned_lesson_fee_jpy
       OR v_fee IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_fee IS DISTINCT FROM v_base+v_aircon OR v_bad_rows<>0 THEN
      RAISE EXCEPTION 'TUITION_ATOMIC_BILL_LESSON_MISMATCH: bill % frozen JSON and normalized relations differ.',v_bill.id;
    END IF;
  ELSE
    SELECT count(*)::integer,coalesce(sum(rel.duration_hours_snapshot),0),
      coalesce(sum(rel.lesson_fee_jpy_snapshot),0),
      count(*) FILTER (WHERE rel.relation_role IS DISTINCT FROM v_bill.billing_role
        OR rel.student_id_snapshot IS DISTINCT FROM v_bill.student_id
        OR rel.business_entity_id_snapshot IS DISTINCT FROM v_bill.business_entity_id
        OR rel.billing_month_snapshot IS DISTINCT FROM v_bill.billing_month
        OR rel.week_start_date_snapshot IS NOT NULL
        OR rel.scheduled_lesson_date_snapshot IS NOT NULL
        OR rel.attribution_confidence IS DISTINCT FROM 'medium'
        OR rel.snapshot_source IS DISTINCT FROM 'bill_json_exact_id_plus_current_source_fields_aggregate_verified'
        OR rel.line_no>jsonb_array_length(coalesce(v_bill.source_snapshot->'planned_lesson_ids','[]'::jsonb))
        OR (v_bill.source_snapshot->'planned_lesson_ids'->>(rel.line_no-1))::uuid
             IS DISTINCT FROM rel.planned_lesson_id)::integer
    INTO v_count,v_hours,v_fee,v_bad_rows
    FROM public.school_student_tuition_bill_lessons rel
    WHERE rel.tuition_bill_id=v_bill.id;
    IF v_bill.billing_role IN ('incident_duplicate','legacy_cancelled') AND EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons rel
      WHERE rel.tuition_bill_id=v_bill.id AND NOT EXISTS (
        SELECT 1 FROM public.school_student_tuition_bill_lessons canonical
        WHERE canonical.planned_lesson_id=rel.planned_lesson_id
          AND canonical.relation_role='canonical_charge')) THEN
      RAISE EXCEPTION 'TUITION_NONCANONICAL_LESSON_WITHOUT_CANONICAL: bill % contains an unconsumed lesson.',v_bill.id;
    END IF;
    IF v_count IS DISTINCT FROM v_bill.planned_lesson_count
       OR v_hours IS DISTINCT FROM v_bill.planned_lesson_hours
       OR v_fee IS DISTINCT FROM v_bill.planned_lesson_fee_jpy
       OR v_fee IS DISTINCT FROM v_bill.bill_amount_jpy OR v_bad_rows<>0 THEN
      RAISE EXCEPTION 'TUITION_BILL_LESSON_MISMATCH: normalized lessons do not match frozen bill %.',v_bill.id;
    END IF;
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.school_validate_tuition_bill_lessons_for_bill(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_validate_tuition_bill_lessons_for_bill(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic_core(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric,
  p_expected_generation_manifest_sha256 text,p_note text DEFAULT NULL,
  p_test_fail_after_step text DEFAULT NULL
)
RETURNS TABLE (
  tuition_bill_id uuid,billing_identity_id uuid,income_record_id uuid,
  student_id uuid,business_entity_id uuid,billing_month text,
  generation_manifest_sha256 text,candidate_count integer,
  total_lesson_count integer,total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,billing_exchange_rate numeric,
  previous_carryover_cny numeric,billing_amount_cny numeric,
  bill_status text,income_status text,idempotent boolean,message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_student_initial public.school_students%ROWTYPE;
  v_student public.school_students%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_snapshot record;
  v_initial_ids uuid[];
  v_locked_ids uuid[];
  v_previous_month text;
  v_lock_month text;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_now timestamptz:=clock_timestamp();
  v_operator text:=coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),current_user);
  v_line jsonb;
  v_line_no integer:=0;
BEGIN
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate<=0 THEN
    RAISE EXCEPTION 'R2_F_B_EXCHANGE_RATE_INVALID';
  END IF;
  IF p_expected_generation_manifest_sha256 IS NULL
     OR p_expected_generation_manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'R2_F_B_GENERATION_MANIFEST_INVALID';
  END IF;
  SELECT student.* INTO v_student_initial FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND OR v_student_initial.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_STUDENT_OR_ENTITY_INVALID';
  END IF;
  IF p_billing_month IS NULL OR btrim(p_billing_month)!~'^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  v_previous_month:=to_char((to_date(btrim(p_billing_month)||'-01','YYYY-MM-DD')-interval '1 month')::date,'YYYY-MM');
  FOR v_lock_month IN SELECT unnest(ARRAY[v_previous_month,btrim(p_billing_month)]) ORDER BY 1 LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws('|',
      'student_tuition_operation_v1',p_student_id::text,
      v_student_initial.business_entity_id::text,v_lock_month),0));
  END LOOP;

  SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.student_id=p_student_id
    AND identity_row.billing_month=btrim(p_billing_month)
  FOR UPDATE;
  IF FOUND THEN
    SELECT bill.* INTO v_bill FROM public.school_student_tuition_bills bill
    WHERE bill.id=v_identity.canonical_bill_id FOR UPDATE;
    SELECT income.* INTO v_income FROM public.school_income_records income
    WHERE income.id=v_bill.income_record_id FOR UPDATE;
    SELECT student.* INTO STRICT v_student FROM public.school_students student
    WHERE student.id=p_student_id AND student.app_type='school' FOR SHARE;
    BEGIN
      IF v_identity.student_id IS DISTINCT FROM p_student_id
       OR v_identity.billing_month IS DISTINCT FROM btrim(p_billing_month)
       OR v_identity.source IS DISTINCT FROM 'atomic_charge'
       OR v_identity.evidence->>'generation_source' IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
       OR v_identity.evidence->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR v_identity.evidence->>'candidate_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_identity.evidence->>'carryover_evidence_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR v_identity.evidence->>'business_entity_id'
            IS DISTINCT FROM v_student.business_entity_id::text
       OR v_bill.id IS NULL
       OR v_bill.student_id IS DISTINCT FROM p_student_id
       OR v_bill.student_id IS DISTINCT FROM v_identity.student_id
       OR v_bill.business_entity_id IS DISTINCT FROM v_student.business_entity_id
       OR v_bill.billing_month IS DISTINCT FROM btrim(p_billing_month)
       OR v_bill.billing_exchange_rate IS DISTINCT FROM p_billing_exchange_rate
       OR v_bill.source_snapshot->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR (v_bill.source_snapshot->>'billing_exchange_rate')::numeric
            IS DISTINCT FROM p_billing_exchange_rate
       OR (v_bill.source_snapshot->>'total_fee_jpy')::numeric
            IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_bill.planned_lesson_fee_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
       OR (v_bill.source_snapshot->>'previous_carryover_cny')::numeric
            IS DISTINCT FROM v_bill.previous_carryover_cny
       OR (v_bill.source_snapshot->>'previous_settlement_month')
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR nullif(v_bill.source_snapshot->>'previous_settlement_id','')::uuid
            IS DISTINCT FROM v_bill.previous_settlement_id
       OR jsonb_typeof(v_bill.source_snapshot->'carryover_evidence') IS DISTINCT FROM 'object'
       OR coalesce(v_bill.source_snapshot->>'carryover_evidence_sha256','') !~ '^[0-9a-f]{64}$'
       OR encode(sha256(convert_to(
            (v_bill.source_snapshot->'carryover_evidence')::text,'UTF8'
          )),'hex') IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='locked_settlement_v1'
            AND (
              v_bill.previous_settlement_id IS NULL
              OR nullif(v_bill.source_snapshot->'carryover_evidence'->>'settlement_id','')::uuid
                   IS DISTINCT FROM v_bill.previous_settlement_id
              OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_status'
                   IS DISTINCT FROM 'locked'
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM v_bill.previous_carryover_cny
            )
          )
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='zero_carryover_verified_v1'
            AND (
              v_bill.previous_settlement_id IS NOT NULL
              OR v_bill.previous_carryover_cny<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'settlement_row_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_bill_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'settlement_income_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_carryover_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_adjustment_draft_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'planned_fee_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'received_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'received_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'inherited_carryover_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'adjustment_amount_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_actual_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_minutes')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_fee_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_fee_cny')::numeric<>0
            )
          )
       OR coalesce(v_bill.source_snapshot->'carryover_evidence'->>'mode','')
            NOT IN ('locked_settlement_v1','zero_carryover_verified_v1')
       OR v_bill.billing_amount_cny IS DISTINCT FROM round(
            v_bill.bill_amount_jpy*p_billing_exchange_rate
              +v_bill.previous_carryover_cny,2
          )
       OR (v_bill.source_snapshot->>'billing_amount_cny')::numeric
            IS DISTINCT FROM v_bill.billing_amount_cny
       OR v_bill.status IS DISTINCT FROM 'income_created'
       OR v_income.id IS NULL OR v_income.status IS DISTINCT FROM 'pending'
       OR v_income.cancelled_at IS NOT NULL
       OR v_income.student_id IS DISTINCT FROM p_student_id
       OR v_income.business_entity_id IS DISTINCT FROM v_bill.business_entity_id
       OR v_income.source_type IS DISTINCT FROM 'student_tuition_bill'
       OR v_income.source_id IS DISTINCT FROM v_bill.id
       OR v_income.tuition_bill_id IS DISTINCT FROM v_bill.id
       OR v_income.amount IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_income.amount_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_income.source_snapshot->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR v_income.source_snapshot->>'candidate_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_income.source_snapshot->>'carryover_evidence_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR (v_income.source_snapshot->>'billing_exchange_rate')::numeric
            IS DISTINCT FROM p_billing_exchange_rate
       OR (v_income.source_snapshot->>'billing_amount_cny')::numeric
            IS DISTINCT FROM v_bill.billing_amount_cny
       OR (v_income.source_snapshot->>'previous_carryover_cny')::numeric
            IS DISTINCT FROM v_bill.previous_carryover_cny
       OR v_income.source_snapshot->>'previous_settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR nullif(v_income.source_snapshot->>'previous_settlement_id','')::uuid
            IS DISTINCT FROM v_bill.previous_settlement_id THEN
        RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
      END IF;
      PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
    END;
    RETURN QUERY SELECT v_bill.id,v_identity.id,v_income.id,v_bill.student_id,
      v_bill.business_entity_id,v_bill.billing_month,
      p_expected_generation_manifest_sha256,v_bill.planned_lesson_count,
      (v_bill.source_snapshot->>'total_lesson_count')::integer,
      v_bill.planned_lesson_hours,
      (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric,
      (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric,
      v_bill.bill_amount_jpy,v_bill.billing_exchange_rate,
      v_bill.previous_carryover_cny,v_bill.billing_amount_cny,
      v_bill.status,v_income.status,true,'existing atomic tuition generation returned idempotently'::text;
    RETURN;
  END IF;

  SELECT coalesce(array_agg(candidate.planned_lesson_id ORDER BY candidate.planned_lesson_id),'{}'::uuid[])
  INTO v_initial_ids
  FROM public.school_list_student_tuition_charge_candidates(
    p_student_id,v_student_initial.business_entity_id,btrim(p_billing_month),false
  ) candidate;
  IF cardinality(v_initial_ids)=0 THEN RAISE EXCEPTION 'R2_F_B_CANDIDATES_EMPTY'; END IF;
  PERFORM 1 FROM public.school_lesson_records lesson
  WHERE lesson.id=ANY(v_initial_ids) ORDER BY lesson.id FOR UPDATE;
  SELECT student.* INTO STRICT v_student FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school' FOR UPDATE;
  IF v_student.business_entity_id IS DISTINCT FROM v_student_initial.business_entity_id THEN
    RAISE EXCEPTION 'R2_F_B_BUSINESS_ENTITY_CHANGED_DURING_LOCK';
  END IF;
  PERFORM 1 FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month IN (v_previous_month,btrim(p_billing_month))
  ORDER BY settlement.year_month,settlement.id FOR SHARE;

  SELECT * INTO STRICT v_snapshot
  FROM public.school_build_student_tuition_generation_snapshot(
    p_student_id,btrim(p_billing_month),p_billing_exchange_rate
  );
  SELECT coalesce(array_agg(candidate.planned_lesson_id ORDER BY candidate.planned_lesson_id),'{}'::uuid[])
  INTO v_locked_ids FROM public.school_list_student_tuition_charge_candidates(
    p_student_id,v_student.business_entity_id,btrim(p_billing_month),false
  ) candidate;
  IF v_locked_ids IS DISTINCT FROM v_initial_ids THEN
    RAISE EXCEPTION 'R2_F_B_CANDIDATE_SET_CHANGED_DURING_LOCK';
  END IF;
  IF v_snapshot.generation_manifest_sha256 IS DISTINCT FROM p_expected_generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_B_STALE_GENERATION_MANIFEST';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
    WHERE relation.planned_lesson_id=ANY(v_locked_ids)
      AND relation.relation_role='canonical_charge') THEN
    RAISE EXCEPTION 'R2_F_B_PLANNED_UUID_ALREADY_FROZEN';
  END IF;

  INSERT INTO public.school_tuition_atomic_writer_context(
    backend_pid,transaction_id,writer_source
  ) VALUES (pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');

  INSERT INTO public.school_student_tuition_bills(
    student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) VALUES (
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,
    v_snapshot.total_duration_hours,v_snapshot.total_fee_jpy,
    v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,
      'student_id',v_snapshot.student_id,
      'business_entity_id',v_snapshot.business_entity_id,
      'billing_month',v_snapshot.billing_month,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence',v_snapshot.carryover_evidence,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'candidate_count',v_snapshot.candidate_count,
      'total_lesson_count',v_snapshot.total_lesson_count,
      'total_duration_hours',v_snapshot.total_duration_hours,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,
      'total_fee_jpy',v_snapshot.total_fee_jpy,
      'planned_lesson_ids',(SELECT jsonb_agg(line->'planned_lesson_id') FROM jsonb_array_elements(v_snapshot.candidates) line),
      'candidate_lines',v_snapshot.candidates,
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'
    ),v_note,'school',v_operator,v_operator,v_now,v_now,
    v_snapshot.billing_exchange_rate,v_snapshot.billing_amount_cny,v_now,
    'canonical_charge',false
  ) RETURNING * INTO v_bill;

  INSERT INTO public.school_student_tuition_billing_identities(
    student_id,billing_month,canonical_bill_id,creation_idempotency_key,
    source,created_by,evidence
  ) VALUES (
    v_snapshot.student_id,v_snapshot.billing_month,v_bill.id,
    'student_tuition_atomic_generate_v1:'||v_snapshot.generation_manifest_sha256,
    'atomic_charge',v_operator,jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'business_entity_id',v_snapshot.business_entity_id,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex')
    )
  ) RETURNING * INTO v_identity;

  FOR v_line IN SELECT value FROM jsonb_array_elements(v_snapshot.candidates) LOOP
    v_line_no:=v_line_no+1;
    INSERT INTO public.school_student_tuition_bill_lessons(
      tuition_bill_id,planned_lesson_id,relation_role,line_no,
      student_id_snapshot,business_entity_id_snapshot,billing_month_snapshot,
      week_start_date_snapshot,scheduled_lesson_date_snapshot,
      teacher_id_snapshot,subject_id_snapshot,lesson_count_snapshot,
      duration_hours_snapshot,unit_price_jpy_snapshot,lesson_fee_jpy_snapshot,
      source_lesson_updated_at,source_snapshot,attribution_confidence,
      snapshot_source,created_by,base_lesson_fee_jpy_snapshot,
      aircon_rate_id_snapshot,aircon_unit_price_jpy_snapshot,
      aircon_billable_hours_snapshot,aircon_fee_jpy_snapshot,
      fee_calculation_version_snapshot,lesson_venue_id_snapshot,
      lesson_venue_code_snapshot
    ) VALUES (
      v_bill.id,(v_line->>'planned_lesson_id')::uuid,'canonical_charge',v_line_no,
      (v_line->>'student_id')::uuid,(v_line->>'business_entity_id')::uuid,
      v_line->>'billing_month',(v_line->>'billing_week_start_date')::date,
      (v_line->>'lesson_date')::date,(v_line->>'teacher_id')::uuid,
      (v_line->>'subject_id')::uuid,(v_line->>'lesson_count')::integer,
      (v_line->>'duration_hours')::numeric,(v_line->>'unit_price_jpy')::numeric,
      (v_line->>'course_total_jpy')::numeric,
      (v_line->>'source_lesson_updated_at')::timestamptz,
      v_line||jsonb_build_object(
        'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256
      ),'high','student_tuition_atomic_generate_v1',v_operator,
      (v_line->>'base_lesson_fee_jpy')::numeric,NULL,
      (v_line->>'aircon_rate_jpy_per_hour')::integer,
      (v_line->>'aircon_billable_hours')::numeric,
      (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
      nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code'
    );
  END LOOP;

  IF p_test_fail_after_step='after_relations' THEN
    RAISE EXCEPTION 'R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS';
  END IF;

  INSERT INTO public.school_income_records(
    business_entity_id,student_id,student_payment_id,account_id,income_date,
    year_month,settlement_month,income_category,description,currency,amount,
    amount_jpy,amount_cny,exchange_rate,payment_currency,payment_method,status,
    is_taxable_income,tax_category,receipt_status,include_in_student_settlement,
    note,source_type,source_id,source_label,source_snapshot,app_type,
    created_at,updated_at,tuition_bill_id,cash_submission_blocked,operational_excluded
  ) VALUES (
    v_snapshot.business_entity_id,v_snapshot.student_id,NULL,NULL,current_date,
    v_snapshot.billing_month,v_snapshot.billing_month,'tuition',
    v_snapshot.billing_month||' 学费应收','JPY',v_snapshot.total_fee_jpy,
    v_snapshot.total_fee_jpy,NULL,NULL,'JPY',NULL,'pending',false,NULL,
    'Cash待提交',true,v_note,'student_tuition_bill',v_bill.id,
    v_snapshot.billing_month||' 学费应收',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'tuition_bill_id',v_bill.id,'billing_identity_id',v_identity.id,
      'billing_month',v_snapshot.billing_month,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_count',v_snapshot.candidate_count,
      'total_lesson_count',v_snapshot.total_lesson_count,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,
      'total_fee_jpy',v_snapshot.total_fee_jpy,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'
    ),'school',v_now,v_now,v_bill.id,false,false
  ) RETURNING * INTO v_income;

  UPDATE public.school_student_tuition_bills bill SET
    status='income_created',income_record_id=v_income.id,income_created_at=v_now,
    updated_by=v_operator,updated_at=v_now
  WHERE bill.id=v_bill.id RETURNING * INTO v_bill;

  DELETE FROM public.school_tuition_atomic_writer_context context_row
  WHERE context_row.backend_pid=pg_backend_pid()
    AND context_row.transaction_id=txid_current();

  PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);

  RETURN QUERY SELECT v_bill.id,v_identity.id,v_income.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.billing_exchange_rate,
    v_snapshot.previous_carryover_cny,v_snapshot.billing_amount_cny,
    v_bill.status,v_income.status,false,'atomic tuition bill, identity, relations and pending income created'::text;
END
$function$;

REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;

\if :{?r2_f_b_hardening_only}
DO $hardening_postflight$
DECLARE
  v_snapshot_definition text;
  v_core_definition text;
  v_validator_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure
  ) INTO STRICT v_snapshot_definition;
  SELECT pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
  ) INTO STRICT v_core_definition;
  SELECT pg_get_functiondef(
    'public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure
  ) INTO STRICT v_validator_definition;
  IF position('canonical_line' IN v_snapshot_definition)=0
     OR position('candidate_line_hash' IN v_snapshot_definition)=0
     OR position('source_updated_at' IN v_snapshot_definition)=0
     OR position('v_bill.billing_exchange_rate IS DISTINCT FROM p_billing_exchange_rate' IN v_core_definition)=0
     OR position('carryover_evidence_sha256' IN v_core_definition)=0
     OR position('active_adjustment_draft_count' IN v_core_definition)=0
     OR position('R2_F_B_EXCHANGE_RATE_INVALID' IN v_core_definition)=0
     OR position('v_recomputed_candidate_manifest' IN v_validator_definition)=0
     OR position('complete_row_hash' IN v_validator_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_B_HARDENING_DEFINITION_INCOMPLETE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_B_HARDENING_WRITER_CONTEXT_NOT_EMPTY';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_B_HARDENING_R0_CHANGED';
  END IF;
END
$hardening_postflight$;
\else
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric,
  p_expected_generation_manifest_sha256 text,p_note text DEFAULT NULL
)
RETURNS TABLE (
  tuition_bill_id uuid,billing_identity_id uuid,income_record_id uuid,
  student_id uuid,business_entity_id uuid,billing_month text,
  generation_manifest_sha256 text,candidate_count integer,
  total_lesson_count integer,total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,billing_exchange_rate numeric,
  previous_carryover_cny numeric,billing_amount_cny numeric,
  bill_status text,income_status text,idempotent boolean,message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
    '学费应收生成功能尚未开放，当前禁止生成正式账单或收入。'
  );
  RETURN QUERY SELECT *
  FROM public.school_generate_student_tuition_bill_atomic_core(
    p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,NULL
  );
END
$function$;

REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text) IS
  'R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.';
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text) IS
  'Owner-only atomic core used by the gated wrapper and rollback-only database-owner tests. Never granted to client roles.';

CREATE OR REPLACE FUNCTION public.school_cancel_pending_income_record(
  p_income_id uuid,p_cancel_reason text,p_operator text DEFAULT NULL
)
RETURNS TABLE (income_id uuid,status text,cancelled_at timestamptz,
  cancelled_reason text,cancelled_by text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_now timestamptz:=now();
  v_reason text:=nullif(btrim(coalesce(p_cancel_reason,'')),'');
  v_operator text:=nullif(btrim(coalesce(p_operator,'')),'');
  v_income public.school_income_records%ROWTYPE;
  v_latest_event public.school_personal_cash_income_linkage_events%ROWTYPE;
  v_account_transaction_count integer:=0;
  v_legacy_tuition boolean:=false;
BEGIN
  IF p_income_id IS NULL THEN RAISE EXCEPTION '请选择要作废的收入记录。'; END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION '请填写作废理由。'; END IF;
  SELECT income.* INTO v_income FROM public.school_income_records income
  WHERE income.id=p_income_id AND coalesce(income.app_type,'')='school' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '收入记录不存在。'; END IF;
  IF v_income.source_type='student_tuition_bill'
     AND v_income.source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1' THEN
    RAISE EXCEPTION 'TUITION_ATOMIC_CANCEL_FORBIDDEN: atomic tuition bill/income cannot use the generic cancellation workflow.';
  END IF;
  v_legacy_tuition:=v_income.source_type='student_tuition_bill';
  IF v_legacy_tuition THEN
    PERFORM public.school_require_feature_gate_state(
      'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
      '历史学费作废在正式生成 gate 开放前保持阻断。'
    );
    INSERT INTO public.school_tuition_atomic_writer_context(
      backend_pid,transaction_id,writer_source
    ) VALUES (pg_backend_pid(),txid_current(),'legacy_tuition_cancel');
  END IF;
  IF v_income.status='cancelled' OR v_income.cancelled_at IS NOT NULL THEN
    RAISE EXCEPTION '该收入已作废，不能重复作废。';
  END IF;
  IF v_income.status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION '只能作废待确认收入。当前状态：%。',v_income.status;
  END IF;
  IF v_income.account_id IS NOT NULL THEN RAISE EXCEPTION '已有入账账户的收入不能走 pending 作废。'; END IF;
  IF v_income.student_payment_id IS NOT NULL THEN RAISE EXCEPTION '关联学生收款链路的收入不能通过普通 pending 作废处理。'; END IF;
  IF v_income.reversed_at IS NOT NULL OR v_income.reversal_account_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION '已撤销收入不能作废。';
  END IF;
  SELECT count(*)::integer INTO v_account_transaction_count
  FROM public.school_account_transactions transaction_row
  WHERE transaction_row.related_table='school_income_records'
    AND transaction_row.related_id=v_income.id
    AND coalesce(transaction_row.app_type,'')='school';
  IF v_account_transaction_count>0 THEN RAISE EXCEPTION '已有账户流水的收入不能走 pending 作废。'; END IF;
  SELECT event_row.* INTO v_latest_event
  FROM public.school_personal_cash_income_linkage_events event_row
  WHERE event_row.income_record_id=v_income.id
    AND event_row.source_table='school_income_records'
    AND event_row.source_event_type IN ('tuition_income_received','income_received')
  ORDER BY event_row.attempt_no DESC,event_row.created_at DESC,event_row.id DESC
  LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    IF v_latest_event.cash_transaction_id IS NOT NULL THEN RAISE EXCEPTION '已有 Cash transaction 的收入不能作废。'; END IF;
    IF v_latest_event.sync_status IN ('pending','pending_cash_request','awaiting_cash_confirmation','synced')
       OR v_latest_event.cash_request_status IN ('pending','approved','synced') THEN
      RAISE EXCEPTION '该收入存在待确认或已确认 Cash 请求，不能作废。';
    END IF;
    IF v_latest_event.sync_status IN ('failed','blocked') THEN RAISE EXCEPTION 'Cash failed / blocked 的收入暂不允许作废。'; END IF;
    IF NOT (v_latest_event.sync_status='cash_rejected' OR v_latest_event.cash_request_status='rejected') THEN
      RAISE EXCEPTION '只有 Cash 已拒绝或没有 Cash linkage 的 pending 收入可以作废。';
    END IF;
  END IF;
  UPDATE public.school_income_records income SET status='cancelled',cancelled_at=v_now,
    cancelled_reason=v_reason,
    cancelled_by=coalesce(v_operator,nullif(current_setting('request.jwt.claim.sub',true),''),current_user),
    updated_at=v_now WHERE income.id=v_income.id
  RETURNING income.id,income.status,income.cancelled_at,income.cancelled_reason,income.cancelled_by
  INTO income_id,status,cancelled_at,cancelled_reason,cancelled_by;
  IF v_legacy_tuition AND v_income.source_id IS NOT NULL THEN
    UPDATE public.school_student_tuition_bills bill SET status='cancelled',
      cancelled_at=coalesce(bill.cancelled_at,v_now),
      cancelled_reason=coalesce(bill.cancelled_reason,'associated income record cancelled: '||v_reason),
      updated_by=coalesce(v_operator,nullif(current_setting('request.jwt.claim.sub',true),''),current_user),
      updated_at=v_now
    WHERE bill.id=v_income.source_id AND bill.income_record_id=v_income.id
      AND bill.status='income_created' AND bill.app_type='school';
  END IF;
  IF v_legacy_tuition THEN
    DELETE FROM public.school_tuition_atomic_writer_context context_row
    WHERE context_row.backend_pid=pg_backend_pid()
      AND context_row.transaction_id=txid_current();
  END IF;
  RETURN NEXT;
END
$function$;

COMMENT ON FUNCTION public.school_cancel_pending_income_record(uuid,text,text) IS
  'Guardedly cancels ordinary pending School income and preserves the legacy tuition cancellation path behind the generate gate. R2-F-B atomic tuition income is permanently rejected.';

DO $postflight$
BEGIN
  IF EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_B_WRITER_CONTEXT_NOT_EMPTY';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_B_R0_GATE_CHANGED';
  END IF;
END
$postflight$;
\endif
