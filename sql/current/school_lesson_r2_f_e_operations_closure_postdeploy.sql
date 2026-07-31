-- School V2 R2-F-E read-only postdeploy acceptance.
-- No business DML; all checks run in READ ONLY and end with ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $acceptance$
DECLARE
  v_sun record;
  v_zhang record;
BEGIN
  IF position('R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' IN
       pg_get_functiondef('public.school_enforce_r2_e_planned_aircon()'::regprocedure))=0
     OR position('school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)' IN
       pg_get_functiondef(
         'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
       ))=0
     OR position('FUTURE_ACTUAL_COMPLETION_FORBIDDEN' IN
       pg_get_functiondef(
         'public.school_enforce_r2_f_e_actual_completion_date()'::regprocedure
       ))=0 THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_FUNCTION_MARKER_FAILED';
  END IF;

  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.school_lesson_records'::regclass
        AND tgname='trg_school_lesson_r2_f_e_actual_completion_date'
        AND tgenabled='O' AND NOT tgisinternal)<>1
     OR has_function_privilege('anon',
          'public.school_enforce_r2_f_e_actual_completion_date()','EXECUTE')
     OR has_function_privilege('authenticated',
          'public.school_enforce_r2_f_e_actual_completion_date()','EXECUTE')
     OR has_function_privilege('service_role',
          'public.school_enforce_r2_f_e_actual_completion_date()','EXECUTE') THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_TRIGGER_OR_ACL_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_R0_FAILED';
  END IF;

  IF (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_lesson_records x)
       IS DISTINCT FROM jsonb_build_array(656,'21ccb5b1b93f6004d061c95ed98994a9')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_monthly_settlements x)
       IS DISTINCT FROM jsonb_build_array(17,'7f78087e7b648992b95d66327a6a0a73')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x)
       IS DISTINCT FROM jsonb_build_array(9,'0f0323b79e7ff1c47ff6b90c75477a2d')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x)
       IS DISTINCT FROM jsonb_build_array(42,'2a4897b752f272b1f192045418b4940c')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x)
       IS DISTINCT FROM jsonb_build_array(121,'285172fedeb923c67ea9a179480d8692')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_billing_identities x)
       IS DISTINCT FROM jsonb_build_array(7,'4d91a5a1074f90389822fc367a7e5467')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_lock_details x)
       IS DISTINCT FROM jsonb_build_array(556,'6204dc666b3b8e0f64fac901ecf0686a')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_account_transactions x)
       IS DISTINCT FROM jsonb_build_array(185,'8f4f6c4365035f6c36bac59ba986b28b')
     OR (SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_personal_cash_income_linkage_events x)
       IS DISTINCT FROM jsonb_build_array(35,'6e76a4dc2fc2954b28b7ad0a8d203ba0') THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_BUSINESS_FINGERPRINT_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records l
      WHERE l.app_type='school' AND l.lesson_type='actual'
        AND l.status IN ('completed','makeup_completed')
        AND l.lesson_date>(statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date)<>3
     OR (SELECT md5(string_agg(l.id::text,',' ORDER BY l.id::text))
         FROM public.school_lesson_records l
         WHERE l.app_type='school' AND l.lesson_type='actual'
           AND l.status IN ('completed','makeup_completed')
           AND l.lesson_date>(statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date)
       <>'cc5a2ea4d0834349731f2c44239e259e' THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_FUTURE_ACTUAL_EVIDENCE_CHANGED';
  END IF;

  IF EXISTS (
       SELECT 1 FROM public.school_lesson_records l
       WHERE l.id IN (
         'e890424d-407d-4fc2-b8ad-84745b242cdd',
         'c582a187-32f6-4a24-bb7b-d590b25c1854',
         'dc06b98c-360f-4661-a294-52ecb82830a7'
       ) AND (
         EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
                 WHERE s.student_id=l.student_id
                   AND s.business_entity_id IS NOT DISTINCT FROM l.business_entity_id
                   AND s.year_month=coalesce(l.student_settlement_month,l.year_month)
                   AND s.settlement_status='locked')
         OR EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details d
                    JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
                    WHERE d.lesson_record_id=l.id AND w.status='locked'
                      AND w.voided_at IS NULL)
       )
     ) THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_FUTURE_ACTUAL_LOCK_CLASS_CHANGED';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.school_lesson_records l
       JOIN public.school_student_tuition_bill_lessons r
         ON r.planned_lesson_id=l.id
       WHERE l.id='1a370095-dd14-444f-8ffb-778e92e03c88'
         AND l.status='planned'
         AND l.duration_hours=2
         AND public.school_get_lesson_credit_remaining_hours(l.id)=2
         AND NOT EXISTS (SELECT 1 FROM public.school_lesson_records a
                         WHERE a.lesson_type='actual'
                           AND a.planned_lesson_id=l.id)
     ) THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_PENG_EVIDENCE_CHANGED';
  END IF;

  SELECT p.* INTO STRICT v_sun
  FROM public.school_get_student_tuition_validation_preview_details(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08',0.042
  ) p;
  SELECT p.* INTO STRICT v_zhang
  FROM public.school_get_student_tuition_validation_preview_details(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-08',0.043
  ) p;
  IF v_sun.candidate_count<>22 OR v_sun.total_lesson_count<>24
     OR v_sun.total_duration_hours<>44
     OR v_sun.total_base_lesson_fee_jpy<>374000
     OR v_sun.total_aircon_fee_jpy<>0
     OR v_sun.previous_carryover_cny<>0
     OR v_zhang.candidate_count<>30 OR v_zhang.total_lesson_count<>35
     OR v_zhang.total_duration_hours<>65
     OR v_zhang.total_base_lesson_fee_jpy<>650000
     OR v_zhang.total_aircon_fee_jpy<>0
     OR v_zhang.previous_carryover_cny<>107.50 THEN
    RAISE EXCEPTION 'R2_F_E_POSTDEPLOY_TUITION_PREVIEW_REGRESSION';
  END IF;
END
$acceptance$;

SELECT
  md5(pg_get_functiondef(
    'public.school_enforce_r2_e_planned_aircon()'::regprocedure
  )) AS planned_charge_guard_md5,
  md5(pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  )) AS guarded_update_md5,
  md5(pg_get_functiondef(
    'public.school_enforce_r2_f_e_actual_completion_date()'::regprocedure
  )) AS future_actual_guard_md5,
  3 AS retained_unlocked_future_actual_anomalies,
  true AS business_fingerprints_unchanged,
  true AS tuition_previews_unchanged,
  true AS r0_unchanged;

ROLLBACK;
\echo 'R2_F_E_POSTDEPLOY_READ_ONLY_ROLLED_BACK'
