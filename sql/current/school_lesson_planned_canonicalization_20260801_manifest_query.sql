-- Fixed-manifest source query for the approved 2026-08-01 legacy planned canonicalization.
-- SELECT/COPY only. The output is frozen into the checked-in TSV/VALUES artifacts;
-- the migration itself never discovers targets dynamically.
\set ON_ERROR_STOP on
\pset pager off

COPY (
  WITH target AS (
    SELECT
      lesson.*,
      to_jsonb(lesson) AS lesson_json,
      date_trunc('week',lesson.lesson_date::timestamp)::date AS target_week,
      to_char(date_trunc('week',lesson.lesson_date::timestamp)::date,'YYYY-MM') AS target_month
    FROM public.school_lesson_records lesson
    JOIN public.school_legacy_planned_settlement_evidence evidence
      ON evidence.planned_lesson_id=lesson.id
    WHERE lesson.app_type='school'
      AND lesson.lesson_type='planned'
      AND num_nonnulls(
        lesson.billing_month,lesson.billing_week_start_date,
        lesson.student_settlement_month,lesson.billing_month_source,
        lesson.billing_month_decided_at
      )=0
  )
  SELECT
    target.id AS lesson_id,
    target.lesson_type AS record_type,
    target.student_id,
    student.display_name AS student_name,
    target.lesson_date,
    target.planned_lesson_id AS source_planned_lesson_id,
    target.status,
    target.import_batch_id AS generation_batch_id,
    target.business_entity_id AS current_business_entity_id,
    current_entity.name AS current_business_entity_name,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid AS target_business_entity_id,
    target_entity.name AS target_business_entity_name,
    target.billing_month AS current_billing_month,
    target.billing_week_start_date AS current_billing_week_start_date,
    target.student_settlement_month AS current_student_settlement_month,
    target.billing_month_source AS current_billing_month_source,
    target.billing_month_decided_at AS current_billing_month_decided_at,
    target.target_month AS target_billing_month,
    target.target_week AS target_billing_week_start_date,
    target.target_month AS target_student_settlement_month,
    'approved_legacy_planned_canonicalization_20260801'::text AS target_billing_month_source,
    '2026-08-01 13:39:37.829675+00'::timestamptz AS target_billing_month_decided_at,
    evidence.evidence_source,
    evidence.evidence_version,
    evidence.recorded_at AS evidence_recorded_at,
    evidence.legacy_student_settlement_month AS legacy_evidence_month,
    EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id=target.id
    ) AS has_bill_relation,
    EXISTS (
      SELECT 1 FROM public.school_student_monthly_settlements settlement
      WHERE settlement.student_id=target.student_id
        AND settlement.business_entity_id IS NOT DISTINCT FROM target.business_entity_id
        AND settlement.year_month=evidence.legacy_student_settlement_month
        AND settlement.settlement_status='locked'
    ) AS locked_student_settlement_legacy_scope,
    EXISTS (
      SELECT 1 FROM public.school_student_monthly_settlements settlement
      WHERE settlement.student_id=target.student_id
        AND settlement.business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
        AND settlement.year_month=target.target_month
        AND settlement.settlement_status='locked'
    ) AS locked_student_settlement_target_scope,
    EXISTS (
      SELECT 1
      FROM public.school_teacher_wage_lock_details detail
      JOIN public.school_teacher_wage_locks wage_lock ON wage_lock.id=detail.lock_id
      WHERE wage_lock.status='locked'
        AND wage_lock.voided_at IS NULL
        AND detail.lesson_record_id IN (
          SELECT linked.id FROM public.school_lesson_records linked
          WHERE linked.id=target.id OR linked.planned_lesson_id=target.id
        )
    ) AS has_locked_wage,
    (SELECT count(*) FROM public.school_lesson_records linked
     WHERE linked.lesson_type='actual' AND linked.planned_lesson_id=target.id) AS linked_actual_count,
    target.updated_at AS before_updated_at,
    md5(target.lesson_json::text) AS before_row_hash,
    md5((target.lesson_json-'updated_at')::text) AS before_stable_row_hash,
    md5(((target.lesson_json || jsonb_build_object(
      'business_entity_id','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
      'billing_month',target.target_month,
      'billing_week_start_date',target.target_week,
      'student_settlement_month',target.target_month,
      'billing_month_source','approved_legacy_planned_canonicalization_20260801',
      'billing_month_decided_at','2026-08-01 13:39:37.829675+00'::timestamptz
    ))-'updated_at')::text) AS expected_after_stable_row_hash,
    false AS has_conflict,
    true AS allowed_to_execute
  FROM target
  JOIN public.school_legacy_planned_settlement_evidence evidence
    ON evidence.planned_lesson_id=target.id
  JOIN public.school_students student ON student.id=target.student_id
  JOIN public.school_business_entities current_entity ON current_entity.id=target.business_entity_id
  JOIN public.school_business_entities target_entity
    ON target_entity.id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
  WHERE evidence.approved_manifest IS TRUE
    AND evidence.evidence_source='r1d_e_b1_fixed_legacy_279'
    AND evidence.evidence_version='legacy_settlement_evidence_v1'
    AND evidence.student_id_snapshot=target.student_id
    AND evidence.business_entity_id_snapshot=target.business_entity_id
    AND evidence.lesson_identity_md5=md5(concat_ws('|',
      target.id::text,coalesce(target.student_id::text,'<NULL>'),
      coalesce(target.business_entity_id::text,'<NULL>'),
      coalesce(target.year_month,'<NULL>'),target.lesson_type,target.app_type
    ))
  ORDER BY target.id
) TO STDOUT WITH (FORMAT csv,HEADER true,DELIMITER E'\t',NULL '\N');
