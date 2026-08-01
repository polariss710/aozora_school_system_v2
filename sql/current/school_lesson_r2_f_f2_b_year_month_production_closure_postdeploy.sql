-- School V2 R2-F-F2-B read-only postdeploy acceptance.
\set ON_ERROR_STOP on
\pset pager off

BEGIN READ ONLY;
SET LOCAL statement_timeout='180s';

DO $assertions$
DECLARE
  v_target constant uuid:='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';
BEGIN
  IF to_regprocedure(
       'public.school_resolve_lesson_student_month_authoritative(uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION 'R2_F_F2_B_READ_WRAPPER_MISSING';
  END IF;
  IF public.school_resolve_lesson_student_month_authoritative(v_target)
       <>'2026-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_TARGET_RESOLVER_MISMATCH';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id=v_target AND lesson.lesson_type='planned'
      AND lesson.billing_week_start_date=DATE '2026-08-31'
      AND lesson.billing_month='2026-08'
      AND lesson.student_settlement_month='2026-08'
      AND lesson.lesson_date=DATE '2026-09-06'
      AND lesson.year_month='2026-09'
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_B_TARGET_FACT_DRIFT';
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
      ) lesson WHERE lesson.id=v_target)<>0
     OR (SELECT count(*) FROM public.school_list_student_tuition_candidates(
        (SELECT student_id FROM public.school_lesson_records WHERE id=v_target),
        (SELECT business_entity_id FROM public.school_lesson_records WHERE id=v_target),
        '2026-08',true
      ) candidate WHERE candidate.planned_lesson_id=v_target)<>1
     OR (SELECT count(*) FROM public.school_list_student_tuition_candidates(
        (SELECT student_id FROM public.school_lesson_records WHERE id=v_target),
        (SELECT business_entity_id FROM public.school_lesson_records WHERE id=v_target),
        '2026-09',true
      ) candidate WHERE candidate.planned_lesson_id=v_target)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_TARGET_READER_OR_CANDIDATE_MISMATCH';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F2_B_GATE_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.lesson_type='planned' AND lesson.billing_month IS NOT NULL
      AND (lesson.student_settlement_month IS DISTINCT FROM lesson.billing_month
        OR lesson.billing_month IS DISTINCT FROM
             to_char(lesson.billing_week_start_date,'YYYY-MM')
        OR lesson.lesson_date NOT BETWEEN lesson.billing_week_start_date
                                      AND lesson.billing_week_start_date+6)
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_B_PLANNED_INVARIANT_FAILED';
  END IF;

  IF position('and s.year_month = v_year_month' IN pg_get_functiondef(
       'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure
     ))>0
     OR position('and s.year_month = r.year_month' IN pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure
     ))>0
     OR position('and s.year_month = r.year_month' IN pg_get_functiondef(
       'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure
     ))>0
     OR position('v_planned.year_month' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))>0 AND position('school_resolve_r1d_e_c_lesson_student_month' IN
       pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))=0
     OR position('and s.year_month = v_planned.year_month' IN pg_get_functiondef(
       'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure
     ))>0
     OR position('and s.year_month = v_planned.year_month' IN pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     ))>0
     OR position('coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date' IN
       pg_get_functiondef(
       'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
     ))>0
     OR position('coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date' IN
       pg_get_functiondef(
       'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure
     ))>0
     OR position('coalesce(source.billing_month,source.year_month)' IN
       pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))>0
     OR position('coalesce(actual.student_settlement_month,actual.year_month)' IN
       pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))>0
     OR position('where (p_year_month is null or year_month = p_year_month)' IN
       lower(pg_get_functiondef(
       'public.school_get_lesson_management_stats(text,uuid,uuid,uuid,text,text,uuid)'::regprocedure
     )))>0
     OR position('and p.year_month >=' IN lower(pg_get_functiondef(
       'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
     )))>0
     OR position('m.year_month = c.year_month' IN pg_get_functiondef(
       'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
     ))>0
     OR position('s.year_month = c.year_month' IN pg_get_functiondef(
       'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
     ))>0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ILLEGAL_DEPLOYED_YEAR_MONTH_DEPENDENCY';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records)<>662
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_lesson_records t)<>'afee1af53686091a9e2353734d2b7cd9'
     OR (SELECT count(*) FROM public.school_student_tuition_bills)<>9
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_student_tuition_bills t)<>'0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records)<>42
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_income_records t)<>'2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)<>121
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_student_tuition_bill_lessons t)<>'285172fedeb923c67ea9a179480d8692'
     OR (SELECT count(*) FROM public.school_student_tuition_billing_identities)<>7
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_student_tuition_billing_identities t)<>'4d91a5a1074f90389822fc367a7e5467'
     OR (SELECT count(*) FROM public.school_student_monthly_settlements)<>17
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_student_monthly_settlements t)<>'1d7328654f6488952dba20640072c3e2'
     OR (SELECT count(*) FROM public.school_teacher_wage_locks)<>95
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_teacher_wage_locks t)<>'7bbe108d3ac73d4f21530793bf141bc6'
     OR (SELECT count(*) FROM public.school_account_transactions)<>185
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_account_transactions t)<>'8f4f6c4365035f6c36bac59ba986b28b'
     OR (SELECT count(*) FROM public.school_personal_cash_income_linkage_events)<>35
     OR (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id::text))
         FROM public.school_personal_cash_income_linkage_events t)<>'6e76a4dc2fc2954b28b7ad0a8d203ba0' THEN
    RAISE EXCEPTION 'R2_F_F2_B_BUSINESS_FINGERPRINT_DRIFT';
  END IF;
END
$assertions$;

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
  'school_resolve_lesson_student_month_authoritative',
  'school_generate_teacher_monthly_wage',
  'school_backfill_actual_minutes_from_duration'
)
ORDER BY 1;

SELECT lesson.id,lesson.lesson_date,lesson.year_month,
  lesson.billing_week_start_date,lesson.billing_month,
  lesson.student_settlement_month,
  public.school_resolve_lesson_student_month_authoritative(lesson.id)
    AS resolved_student_month
FROM public.school_lesson_records lesson
WHERE lesson.id='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';

WITH target AS (
  SELECT id,student_id,business_entity_id
  FROM public.school_lesson_records
  WHERE id='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'
)
SELECT
  (SELECT count(*) FROM
    public.school_list_lesson_management_records_authoritative(
      '2026-08',NULL
    ) lesson JOIN target ON target.id=lesson.id) AS august_month_count,
  (SELECT count(*) FROM
    public.school_list_lesson_management_records_authoritative(
      '2026-08',DATE '2026-08-31'
    ) lesson JOIN target ON target.id=lesson.id) AS august_week_count,
  (SELECT count(*) FROM
    public.school_list_lesson_management_records_authoritative(
      '2026-09',NULL
    ) lesson JOIN target ON target.id=lesson.id) AS september_month_count,
  (SELECT count(*) FROM target CROSS JOIN LATERAL
    public.school_list_student_tuition_candidates(
      target.student_id,target.business_entity_id,'2026-08',true
    ) candidate WHERE candidate.planned_lesson_id=target.id
  ) AS august_candidate_count,
  (SELECT count(*) FROM target CROSS JOIN LATERAL
    public.school_list_student_tuition_candidates(
      target.student_id,target.business_entity_id,'2026-09',true
    ) candidate WHERE candidate.planned_lesson_id=target.id
  ) AS september_candidate_count;

SELECT role_name,
  has_function_privilege(
    role_name,
    'public.school_get_lesson_management_stats(text,uuid,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  ) AS old_stats_execute,
  has_function_privilege(
    role_name,
    'public.school_list_open_lesson_credit_sources(text,text,text)',
    'EXECUTE'
  ) AS open_credit_execute
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

SELECT student.name,preview.candidate_count,preview.total_lesson_count,
  preview.total_duration_hours,preview.total_base_lesson_fee_jpy,
  preview.total_aircon_fee_jpy,preview.total_fee_jpy,
  preview.previous_carryover_cny,preview.billing_exchange_rate,
  preview.billing_amount_cny
FROM public.school_students student
CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
  student.id,'2026-08',CASE WHEN student.name='孙陈锋' THEN 0.042 ELSE 0.043 END
) preview
WHERE student.name IN ('孙陈锋','张倬闻')
ORDER BY student.name;

SELECT feature_key,state FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

COMMIT;
