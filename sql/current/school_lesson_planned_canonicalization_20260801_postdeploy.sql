-- SELECT-only postdeploy for the fixed 279 planned canonicalization.
\set ON_ERROR_STOP on
\pset pager off
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $verify$
DECLARE
  v_preview record;
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type='planned')<>417
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466')<>417
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND billing_month_source='approved_legacy_planned_canonicalization_20260801')<>279
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0)<>0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='actual')<>245
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='actual' AND student_settlement_month IS NULL)<>234 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_CLASSIFICATION_FAILED';
  END IF;

  IF (SELECT count(DISTINCT billing_month_decided_at)
      FROM public.school_lesson_records
      WHERE billing_month_source='approved_legacy_planned_canonicalization_20260801')<>1
     OR (SELECT min(billing_month_decided_at)
         FROM public.school_lesson_records
         WHERE billing_month_source='approved_legacy_planned_canonicalization_20260801')
        <>'2026-08-01 13:39:37.829675+00'::timestamptz THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_DECISION_TIME_FAILED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.school_lesson_records
      WHERE id='f256bca9-fac5-4909-b113-8077efd27d65'
        AND billing_week_start_date='2026-09-28'
        AND billing_month='2026-09' AND student_settlement_month='2026-09')
     OR NOT EXISTS (SELECT 1 FROM public.school_lesson_records
      WHERE id='552c54e3-2d0c-4607-962d-aad39dfff7f7'
        AND billing_week_start_date='2026-10-26'
        AND billing_month='2026-10' AND student_settlement_month='2026-10') THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_SPECIAL_IDS_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records lesson
      WHERE lesson.lesson_type='planned' AND lesson.voided_at IS NULL
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND lesson.billing_month='2026-07')<>18
     OR (SELECT sum(duration_hours) FROM public.school_lesson_records lesson
      WHERE lesson.lesson_type='planned' AND lesson.voided_at IS NULL
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND lesson.billing_month='2026-07')<>36
     OR (SELECT sum(lesson_fee) FROM public.school_lesson_records lesson
      WHERE lesson.lesson_type='planned' AND lesson.voided_at IS NULL
        AND lesson.student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND lesson.billing_month='2026-07')<>306000 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_SUN_MONTH_FAILED';
  END IF;

  IF EXISTS (
    WITH expected(week_start,row_count,hours,fee) AS (VALUES
      ('2026-07-06'::date,4::bigint,8::numeric,68000::numeric),
      ('2026-07-13'::date,4::bigint,8::numeric,68000::numeric),
      ('2026-07-20'::date,5::bigint,10::numeric,85000::numeric),
      ('2026-07-27'::date,5::bigint,10::numeric,85000::numeric)
    ), actual AS (
      SELECT billing_week_start_date week_start,count(*) row_count,
             sum(duration_hours) hours,sum(lesson_fee) fee
      FROM public.school_lesson_records
      WHERE lesson_type='planned' AND voided_at IS NULL
        AND student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
        AND billing_month='2026-07'
      GROUP BY billing_week_start_date
    )
    SELECT 1 FROM expected FULL JOIN actual USING(week_start)
    WHERE (expected.row_count,expected.hours,expected.fee)
       IS DISTINCT FROM (actual.row_count,actual.hours,actual.fee)
  ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_SUN_WEEKS_FAILED';
  END IF;

  IF (SELECT sum(open_source_count) FROM public.school_list_student_lesson_credit_balances(
       'b17abc58-2f64-4bad-bf20-c9643ead60bc'))<>6
     OR (SELECT sum(open_credit_hours) FROM public.school_list_student_lesson_credit_balances(
       'b17abc58-2f64-4bad-bf20-c9643ead60bc'))<>11 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_CREDIT_FAILED';
  END IF;

  IF (SELECT count(*) FROM (
        SELECT DISTINCT student_id,billing_month
        FROM public.school_lesson_records
        WHERE billing_month_source='approved_legacy_planned_canonicalization_20260801'
      ) scope
      CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
        scope.student_id,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466',scope.billing_month,true) candidate
      JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
      WHERE lesson.billing_month_source='approved_legacy_planned_canonicalization_20260801')<>279
     OR EXISTS (
       SELECT 1 FROM public.school_lesson_records lesson
       CROSS JOIN LATERAL public.school_list_student_tuition_candidates(
         lesson.student_id,lesson.business_entity_id,lesson.billing_month,true) candidate
       WHERE lesson.billing_month_source='approved_legacy_planned_canonicalization_20260801'
         AND candidate.planned_lesson_id=lesson.id
         AND candidate.candidate_status='candidate'
         AND (lesson.status='pending_makeup' OR EXISTS (
           SELECT 1 FROM public.school_student_tuition_bill_lessons relation
           WHERE relation.planned_lesson_id=lesson.id))
     ) THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_CANDIDATE_FAILED';
  END IF;

  SELECT * INTO STRICT v_preview
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042::numeric);
  IF v_preview.feature_state<>'enabled' OR v_preview.generate_feature_state<>'blocked' THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_PREVIEW_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'PLANNED_CANONICALIZATION_POSTDEPLOY_GATE_FAILED';
  END IF;
END
$verify$;

SELECT object_name,row_count,row_hash FROM (
  SELECT 'actual_lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) row_hash FROM public.school_lesson_records x WHERE x.lesson_type='actual'
  UNION ALL SELECT 'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x
  UNION ALL SELECT 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_income_records x
  UNION ALL SELECT 'expense',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_expense_records x
  UNION ALL SELECT 'bill_relations',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x
  UNION ALL SELECT 'billing_identities',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_tuition_billing_identities x
  UNION ALL SELECT 'student_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x
  UNION ALL SELECT 'account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_account_transactions x
  UNION ALL SELECT 'school_cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_personal_cash_income_linkage_events x
  UNION ALL SELECT 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_locks x
  UNION ALL SELECT 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),'')) FROM public.school_teacher_wage_lock_details x
  UNION ALL SELECT 'planned_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),'')) FROM public.school_legacy_planned_settlement_evidence x
  UNION ALL SELECT 'actual_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),'')) FROM public.school_legacy_actual_settlement_evidence x
  UNION ALL SELECT 'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.feature_key),'')) FROM public.school_feature_gates x
) fingerprint ORDER BY object_name;

SELECT billing_week_start_date,sum(status_count) planned_rows,sum(duration_hours) hours,
       sum(lesson_fee) fee_jpy,
       jsonb_object_agg(status,status_count ORDER BY status) status_distribution
FROM (
  SELECT billing_week_start_date,status,count(*) status_count,
         sum(duration_hours) duration_hours,sum(lesson_fee) lesson_fee
  FROM public.school_lesson_records
  WHERE lesson_type='planned' AND voided_at IS NULL
    AND student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'
    AND billing_month='2026-07'
  GROUP BY billing_week_start_date,status
) weekly
GROUP BY billing_week_start_date ORDER BY billing_week_start_date;

SELECT id,lesson_date,billing_week_start_date,billing_month,
       student_settlement_month,billing_month_source,billing_month_decided_at
FROM public.school_lesson_records
WHERE id IN ('f256bca9-fac5-4909-b113-8077efd27d65','552c54e3-2d0c-4607-962d-aad39dfff7f7')
ORDER BY id;

SELECT md5(pg_get_functiondef('public.school_enforce_r1d_f1_planned_attribution()'::regprocedure)) planned_trigger_md5,
       md5(pg_get_functiondef('public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure)) actual_source_resolver_md5,
       md5(pg_get_functiondef('public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)) lesson_month_resolver_md5,
       md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)) candidate_reader_md5;

COMMIT;
