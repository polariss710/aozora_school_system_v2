-- Export the reviewed 2026-08 active-student final result. Read-only DB calls only.
\set ON_ERROR_STOP on
\pset pager off
\pset footer off
\pset format unaligned
\pset fieldsep '\t'
\o docs/school-v2-2026-08-tuition-active-student-final-preview-20260802.tsv

WITH target(student_name,student_id,rate) AS (VALUES
  ('孙陈锋','b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,0.042::numeric),
  ('张倬闻','7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,0.043::numeric),
  ('彭宇晗','eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,0.0435::numeric),
  ('李天伦','a7b163a0-201e-4867-9b94-372343356a80'::uuid,0.05::numeric),
  ('袁振轩','4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,0.0415::numeric),
  ('陈红卓','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,0.043::numeric)
), preview_rows AS (
  SELECT target.student_name,target.student_id,preview.business_entity_id,
         preview.candidate_count,preview.total_lesson_count,
         preview.total_duration_hours,preview.total_base_lesson_fee_jpy,
         preview.total_aircon_fee_jpy,preview.total_fee_jpy,
         preview.billing_exchange_rate,preview.previous_settlement_id,
         preview.previous_carryover_cny,preview.billing_amount_cny,
         preview.candidate_uuid_md5,preview.candidate_manifest_sha256,
         preview.generation_manifest_sha256,
         preview.existing_tuition_bill_id,preview.existing_income_record_id,
         'ELIGIBLE_WITH_CANDIDATES'::text AS classification,
         'YES'::text AS eligible_for_generation,'-'::text AS blocker
  FROM target
  CROSS JOIN LATERAL public.school_get_student_tuition_validation_preview_details(
    target.student_id,'2026-08',target.rate
  ) preview
), existing_row AS (
  SELECT student.name AS student_name,student.id AS student_id,
         student.business_entity_id,0::integer AS candidate_count,
         0::integer AS total_lesson_count,0::numeric AS total_duration_hours,
         0::numeric AS total_base_lesson_fee_jpy,0::numeric AS total_aircon_fee_jpy,
         0::numeric AS total_fee_jpy,student.preset_exchange_rate AS billing_exchange_rate,
         NULL::uuid AS previous_settlement_id,0::numeric AS previous_carryover_cny,
         0::numeric AS billing_amount_cny,NULL::text AS candidate_uuid_md5,
         NULL::text AS candidate_manifest_sha256,NULL::text AS generation_manifest_sha256,
         bill.id AS existing_tuition_bill_id,bill.income_record_id AS existing_income_record_id,
         'ALREADY_BILLED'::text AS classification,'NO'::text AS eligible_for_generation,
         '已有2026-08 billing identity/bill/income'::text AS blocker
  FROM public.school_students student
  JOIN public.school_student_tuition_billing_identities identity_row
    ON identity_row.student_id=student.id AND identity_row.billing_month='2026-08'
  JOIN public.school_student_tuition_bills bill ON bill.id=identity_row.canonical_bill_id
  WHERE student.id='881dd60c-b92b-44ae-98e1-98448567a8d2'
)
SELECT student_name,student_id,entity.name AS business_entity,business_entity_id,
       '2026-08'::text AS billing_month,candidate_count,total_lesson_count,
       total_duration_hours,total_base_lesson_fee_jpy,total_aircon_fee_jpy,
       total_fee_jpy,billing_exchange_rate,previous_settlement_id,
       previous_carryover_cny,billing_amount_cny,existing_tuition_bill_id,
       existing_income_record_id,candidate_uuid_md5,candidate_manifest_sha256,
       generation_manifest_sha256,classification,eligible_for_generation,blocker
FROM (
  SELECT * FROM preview_rows
  UNION ALL
  SELECT * FROM existing_row
) final_rows
JOIN public.school_business_entities entity ON entity.id=final_rows.business_entity_id
ORDER BY student_name,student_id;

\o
\pset format aligned
