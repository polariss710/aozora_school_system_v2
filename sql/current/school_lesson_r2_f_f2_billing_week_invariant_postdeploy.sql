-- School V2 R2-F-F2 postdeploy acceptance. Read-only business verification.
\set ON_ERROR_STOP on
\pset pager off

BEGIN READ ONLY;
SET LOCAL statement_timeout='180s';

DO $assertions$
DECLARE
  v_target constant uuid:='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';
BEGIN
  IF (SELECT count(*) FROM pg_constraint
      WHERE conrelid='public.school_lesson_records'::regclass
        AND conname IN (
          'school_lesson_records_planned_student_month_match_chk',
          'school_lesson_records_planned_date_within_billing_week_chk'
        ) AND convalidated)<>2 THEN
    RAISE EXCEPTION 'R2_F_F2_POSTDEPLOY_CONSTRAINTS_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type='planned'
      AND lesson.billing_month IS NOT NULL
      AND (
        lesson.student_settlement_month IS DISTINCT FROM lesson.billing_month
        OR lesson.billing_month IS DISTINCT FROM
             to_char(lesson.billing_week_start_date,'YYYY-MM')
        OR lesson.lesson_date NOT BETWEEN lesson.billing_week_start_date
                                      AND lesson.billing_week_start_date+6
      )
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_POSTDEPLOY_PLANNED_INVARIANT_FAILED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id=v_target
      AND lesson.lesson_type='planned'
      AND lesson.lesson_date=DATE '2026-09-06'
      AND lesson.year_month='2026-09'
      AND lesson.billing_week_start_date=DATE '2026-08-31'
      AND lesson.billing_month='2026-08'
      AND lesson.student_settlement_month='2026-08'
      AND lesson.aircon_unit_price_jpy_snapshot=330
      AND lesson.aircon_billable_hours_snapshot=2
      AND lesson.aircon_fee_jpy=660
      AND lesson.lesson_total_fee_jpy=17660
      AND lesson.fee_calculation_version=
            'planned_weekend_venue_whole_hour_aircon_v2'
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_POSTDEPLOY_TARGET_FACT_DRIFT';
  END IF;
  IF (SELECT count(*) FROM
        public.school_list_lesson_management_records_authoritative(
          '2026-08',NULL
        ) lesson WHERE lesson.id=v_target)<>1
     OR (SELECT count(*) FROM
        public.school_list_lesson_management_records_authoritative(
          '2026-08',DATE '2026-08-31'
        ) lesson WHERE lesson.id=v_target)<>1
     OR (SELECT count(*) FROM
        public.school_list_lesson_management_records_authoritative(
          '2026-09',NULL
        ) lesson WHERE lesson.id=v_target)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_POSTDEPLOY_TARGET_READER_MISMATCH';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F2_POSTDEPLOY_GATE_DRIFT';
  END IF;
END
$assertions$;

SELECT p.oid::regprocedure::text AS signature,
  md5(pg_get_functiondef(p.oid)) AS definition_md5
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.oid IN (
    'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure,
    'public.school_list_lesson_management_records_authoritative(text,date)'::regprocedure,
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure,
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text)'::regprocedure
  )
ORDER BY signature;

SELECT lesson.id,lesson.lesson_date,lesson.year_month,
  lesson.billing_week_start_date,lesson.billing_month,
  lesson.student_settlement_month,lesson.billing_month_source,
  lesson.aircon_unit_price_jpy_snapshot,
  lesson.aircon_billable_hours_snapshot,lesson.aircon_fee_jpy,
  lesson.lesson_total_fee_jpy,lesson.fee_calculation_version,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons relation
   WHERE relation.planned_lesson_id=lesson.id) AS bill_relation_count
FROM public.school_lesson_records lesson
WHERE lesson.id='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';

SELECT student.name,preview.candidate_count,preview.total_lesson_count,
  preview.total_duration_hours,preview.total_base_lesson_fee_jpy,
  preview.total_aircon_fee_jpy,preview.total_fee_jpy,
  preview.previous_carryover_cny,preview.billing_exchange_rate,
  preview.billing_amount_cny,
  (SELECT count(*) FROM jsonb_array_elements(preview.candidates) candidate
   WHERE candidate->>'planned_lesson_id'=
     'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578') AS target_candidate_count
FROM public.school_students student
CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
  student.id,'2026-08',CASE WHEN student.name='孙陈锋' THEN 0.042 ELSE 0.043 END
) preview
WHERE student.name IN ('孙陈锋','张倬闻')
ORDER BY student.name;

SELECT feature_key,state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

COMMIT;
