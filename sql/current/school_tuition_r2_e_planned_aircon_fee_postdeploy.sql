-- R2-E postdeploy read-only acceptance. Always rolls back.
\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '180s';

DO $acceptance$
DECLARE
  v_preview record;
BEGIN
  IF to_regprocedure(
       'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'
     ) IS NULL
     OR to_regprocedure(
       'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'
     ) IS NULL
     OR to_regprocedure(
       'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'
     ) IS NULL
     OR to_regprocedure(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'
     ) IS NULL THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_REQUIRED_FUNCTION_MISSING';
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_lesson_records'
        AND column_name = 'lesson_total_fee_jpy'
        AND data_type = 'numeric'
        AND is_nullable = 'YES') <> 1
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid = 'public.school_lesson_records'::regclass
           AND tgname = 'trg_school_lesson_r2_e_planned_aircon'
           AND NOT tgisinternal AND tgenabled = 'O') <> 1 THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_SCHEMA_OR_TRIGGER_MISMATCH';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_venues) <> 0
     OR (SELECT count(*) FROM public.school_student_aircon_rates) <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE fee_calculation_version = 'planned_weekend_aircon_v1'
            OR lesson_total_fee_jpy IS NOT NULL) <> 0
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons
         WHERE fee_calculation_version_snapshot = 'planned_weekend_aircon_v1')
          <> 0 THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_HISTORY_OR_DYNAMIC_RATE_POPULATED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 654
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT count(*) FROM public.school_teacher_wage_lock_details) <> 556 THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_BUSINESS_COUNT_CHANGED';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
        ORDER BY row_value.id::text),''))
      FROM public.school_student_tuition_bills row_value)
       <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
        ORDER BY row_value.id::text),''))
         FROM public.school_income_records row_value)
       <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
        ORDER BY row_value.id::text),''))
         FROM public.school_student_tuition_bill_lessons row_value)
       <> '285172fedeb923c67ea9a179480d8692'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),''
        ORDER BY row_value.id::text),''))
         FROM public.school_student_tuition_historical_lesson_exclusions row_value)
       <> '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_FINANCIAL_HASH_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_R0_CHANGED';
  END IF;

  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.05
  );
  IF v_preview.feature_state <> 'validation_preview_only'
     OR v_preview.candidate_count <> 30
     OR v_preview.total_duration_hours <> 65
     OR v_preview.total_base_lesson_fee_jpy <> 650000
     OR v_preview.total_aircon_fee_jpy <> 0
     OR v_preview.total_fee_jpy <> 650000
     OR v_preview.bill_amount_jpy <> 650000
     OR jsonb_array_length(v_preview.candidates) <> 30 THEN
    RAISE EXCEPTION 'R2_E_POSTDEPLOY_PREVIEW_BASELINE_MISMATCH';
  END IF;
END
$acceptance$;

SELECT
  md5(pg_get_functiondef(
    'public.school_r2_e_calculate_planned_aircon_fee(date,text,numeric,numeric,integer)'::regprocedure
  )) AS calculator_md5,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS charge_candidate_md5,
  md5(pg_get_functiondef(
    'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
  )) AS preview_md5,
  md5(pg_get_functiondef(
    'public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)'::regprocedure
  )) AS preview_details_md5;

SELECT
  count(*) AS lesson_count,
  count(*) FILTER (
    WHERE fee_calculation_version = 'planned_weekend_aircon_v1'
  ) AS r2_e_populated_history,
  count(*) FILTER (
    WHERE lesson_type = 'actual'
      AND num_nonnulls(
        base_lesson_fee_jpy,aircon_charge_status,
        aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
        aircon_fee_jpy,aircon_calculated_at,fee_calculation_version,
        lesson_total_fee_jpy
      ) > 0
  ) AS actual_aircon_rows
FROM public.school_lesson_records;

ROLLBACK;
