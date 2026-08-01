-- School V2 2026-08 active-student tuition candidate/preview fixed baseline.
-- SELECT and client-side TSV exports only. No RPC writer and no database write.
\set ON_ERROR_STOP on
\pset pager off
\pset footer off

SELECT clock_timestamp() AS baseline_query_at_utc;

\pset format unaligned
\pset fieldsep '\t'
\o docs/school-v2-2026-08-tuition-candidate-fixed-114-baseline-20260802.tsv
  WITH active_students AS (
    SELECT student.id AS student_id,student.name AS student_name,
           student.business_entity_id,student.preset_exchange_rate,
           entity.name AS business_entity
    FROM public.school_students student
    JOIN public.school_business_entities entity ON entity.id=student.business_entity_id
    WHERE student.app_type='school' AND student.status='active'
  ), candidate_rows AS (
    SELECT student.student_name,student.preset_exchange_rate,
           student.business_entity,candidate.*
    FROM active_students student
    CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
      student.student_id,student.business_entity_id,'2026-08',false
    ) candidate
  )
  SELECT row_number() OVER (
           ORDER BY student_name,billing_week_start_date,lesson_date,planned_lesson_id
         ) AS manifest_no,
         student_name,student_id,business_entity,business_entity_id,
         '2026-08'::text AS billing_month,preset_exchange_rate,
         billing_week_start_date,lesson_date,candidate_status,
         lesson_count,duration_hours,unit_price,
         base_lesson_fee_jpy,aircon_rate_jpy_per_hour,aircon_fee_jpy,
         lesson_total_fee_jpy,aircon_charge_status,aircon_policy_version,
         planned_lesson_id,complete_row_hash,
         md5(concat_ws('|',planned_lesson_id::text,complete_row_hash,
           candidate_billing_month,billing_week_start_date::text,
           lesson_date::text,lesson_count::text,duration_hours::text,
           base_lesson_fee_jpy::text,aircon_fee_jpy::text,
           lesson_total_fee_jpy::text)) AS before_row_hash
  FROM candidate_rows
  ORDER BY student_name,billing_week_start_date,lesson_date,planned_lesson_id;
\o

\o docs/school-v2-2026-08-tuition-active-student-baseline-20260802.tsv
  WITH active_students AS (
    SELECT student.id AS student_id,student.name AS student_name,
           student.business_entity_id,student.preset_exchange_rate,
           entity.name AS business_entity
    FROM public.school_students student
    JOIN public.school_business_entities entity ON entity.id=student.business_entity_id
    WHERE student.app_type='school' AND student.status='active'
  ), candidate_rows AS (
    SELECT student.student_id AS scope_student_id,student.student_name,
           student.business_entity_id AS scope_business_entity_id,
           student.business_entity,student.preset_exchange_rate,candidate.*
    FROM active_students student
    LEFT JOIN LATERAL public.school_list_student_tuition_charge_candidates(
      student.student_id,student.business_entity_id,'2026-08',false
    ) candidate ON true
  ), aggregate AS (
    SELECT scope_student_id AS student_id,student_name,
           scope_business_entity_id AS business_entity_id,business_entity,
           preset_exchange_rate,count(planned_lesson_id)::integer AS candidate_count,
           count(DISTINCT planned_lesson_id)::integer AS unique_candidate_count,
           coalesce(sum(lesson_count),0)::integer AS lesson_count,
           coalesce(sum(duration_hours),0) AS duration_hours,
           coalesce(sum(base_lesson_fee_jpy),0) AS base_fee_jpy,
           coalesce(sum(aircon_fee_jpy),0) AS aircon_fee_jpy,
           coalesce(sum(lesson_total_fee_jpy),0) AS total_fee_jpy,
           CASE WHEN count(planned_lesson_id)=0 THEN NULL ELSE encode(digest(
             string_agg(planned_lesson_id::text,'|' ORDER BY planned_lesson_id::text),
             'sha256'),'hex') END AS candidate_id_set_sha256
    FROM candidate_rows
    GROUP BY scope_student_id,student_name,scope_business_entity_id,
             business_entity,preset_exchange_rate
  ), locked AS (
    SELECT DISTINCT ON (student.student_id) student.student_id,
           settlement.id AS previous_locked_settlement_id,
           settlement.carryover_amount_cny AS previous_locked_carryover_cny
    FROM active_students student
    JOIN public.school_student_monthly_settlements settlement
      ON settlement.student_id=student.student_id
     AND settlement.business_entity_id=student.business_entity_id
     AND settlement.year_month='2026-07'
     AND settlement.settlement_status='locked'
    ORDER BY student.student_id,settlement.locked_at DESC NULLS LAST,
             settlement.updated_at DESC NULLS LAST,settlement.id
  ), existing AS (
    SELECT identity_row.student_id,count(*) AS identity_count,
           min(identity_row.id::text) AS identity_id,
           min(identity_row.canonical_bill_id::text) AS bill_id
    FROM public.school_student_tuition_billing_identities identity_row
    WHERE identity_row.billing_month='2026-08'
    GROUP BY identity_row.student_id
  )
  SELECT aggregate.student_name,aggregate.student_id,aggregate.business_entity,
         aggregate.business_entity_id,aggregate.preset_exchange_rate,
         aggregate.candidate_count,aggregate.unique_candidate_count,
         aggregate.lesson_count,aggregate.duration_hours,
         aggregate.base_fee_jpy,aggregate.aircon_fee_jpy,aggregate.total_fee_jpy,
         locked.previous_locked_settlement_id,
         coalesce(locked.previous_locked_carryover_cny,0) AS previous_carryover_cny,
         round(aggregate.total_fee_jpy*aggregate.preset_exchange_rate+
           coalesce(locked.previous_locked_carryover_cny,0),2) AS approved_notice_cny,
         coalesce(existing.identity_count,0) AS existing_identity_count,
         existing.identity_id AS existing_identity_id,existing.bill_id AS existing_bill_id,
         aggregate.candidate_id_set_sha256
  FROM aggregate
  LEFT JOIN locked USING(student_id)
  LEFT JOIN existing USING(student_id)
  ORDER BY aggregate.student_name,aggregate.student_id;
\o
\pset format aligned

WITH all_candidates AS (
  SELECT student.id AS student_id,candidate.planned_lesson_id
  FROM public.school_students student
  CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
    student.id,student.business_entity_id,'2026-08',false
  ) candidate
  WHERE student.app_type='school' AND student.status='active'
)
SELECT count(*) AS candidate_count,count(DISTINCT planned_lesson_id) AS unique_count,
       encode(digest(string_agg(planned_lesson_id::text,'|' ORDER BY student_id::text,
         planned_lesson_id::text),'sha256'),'hex') AS candidate_set_sha256
FROM all_candidates;

SELECT feature_key,state,release_version,evidence_hash
FROM public.school_feature_gates
WHERE feature_key IN ('student_tuition_preview','student_tuition_generate',
                      'student_tuition_cash_submit')
ORDER BY feature_key;
