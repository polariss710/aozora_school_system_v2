-- School V2 tuition Cash submit recovery preflight (read-only), 2026-08-02.
-- This file contains SELECT and client-side export only. It must never call a
-- write RPC or modify School/Cash data.
\set ON_ERROR_STOP on
\pset pager off

\pset format unaligned
\pset fieldsep '\t'
\pset footer off
\o docs/school-v2-tuition-cash-submit-recovery-baseline-20260802.tsv
WITH latest_linkage AS (
  SELECT DISTINCT ON (event.income_record_id)
    event.*
  FROM public.school_personal_cash_income_linkage_events event
  ORDER BY
    event.income_record_id,
    event.attempt_no DESC,
    event.created_at DESC,
    event.id DESC
),
bill_facts AS (
  SELECT
    bill.*,
    count(relation.id)::integer AS relation_count
  FROM public.school_student_tuition_bills bill
  LEFT JOIN public.school_student_tuition_bill_lessons relation
    ON relation.tuition_bill_id = bill.id
  GROUP BY bill.id
),
baseline AS (
  SELECT
    coalesce(student.display_name, student.name) AS student_name,
    student.id AS student_id,
    bill.billing_month,
    entity.name AS business_entity,
    identity.id AS billing_identity_id,
    bill.id AS bill_id,
    bill.status AS bill_status,
    income.id AS income_id,
    income.status AS income_status,
    income.income_category,
    income.source_type,
    income.source_id,
    income.amount_jpy,
    bill.billing_exchange_rate,
    bill.billing_amount_cny,
    bill.previous_carryover_cny,
    coalesce(
      latest.payment_currency,
      income.source_snapshot ->> 'billing_amount_currency',
      bill.source_snapshot ->> 'billing_amount_currency'
    ) AS payment_currency,
    latest.cash_request_status,
    latest.cash_request_id,
    latest.cash_transaction_id,
    latest.id AS latest_linkage_event_id,
    latest.sync_status AS latest_linkage_status,
    false AS eligible_for_cash_submit,
    CASE
      WHEN income.source_type IS DISTINCT FROM 'student_tuition_bill'
        OR income.income_category IS DISTINCT FROM 'tuition'
        THEN 'NOT_TUITION_INCOME'
      WHEN income.status = 'received'
        AND latest.sync_status IN ('synced', 'historical_confirmed')
        AND (
          latest.sync_status = 'historical_confirmed'
          OR (
            latest.cash_request_status = 'approved'
            AND latest.cash_request_id IS NOT NULL
            AND latest.cash_transaction_id IS NOT NULL
          )
        )
        THEN 'ALREADY_SYNCED'
      WHEN latest.sync_status IN ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        OR latest.cash_request_status = 'pending'
        THEN 'ALREADY_SUBMITTED'
      WHEN income.status = 'pending'
        AND latest.sync_status = 'cash_rejected'
        AND latest.cash_request_status = 'rejected'
        AND latest.cash_transaction_id IS NULL
        THEN 'REJECTED_RETRYABLE'
      WHEN income.status = 'pending'
        AND bill.status = 'income_created'
        AND identity.id IS NOT NULL
        AND income.source_type = 'student_tuition_bill'
        AND income.income_category = 'tuition'
        AND income.source_id = bill.id
        AND income.tuition_bill_id = bill.id
        AND bill.income_record_id = income.id
        AND income.account_id IS NULL
        AND income.cash_submission_blocked IS FALSE
        AND income.operational_excluded IS FALSE
        AND bill.cash_submission_blocked IS FALSE
        AND latest.id IS NULL
        THEN 'ELIGIBLE_FOR_CASH_SUBMIT'
      ELSE 'BLOCKED_CONFLICT'
    END AS classification,
    CASE
      WHEN income.status = 'pending'
        AND bill.status = 'income_created'
        AND identity.id IS NOT NULL
        AND income.source_type = 'student_tuition_bill'
        AND income.income_category = 'tuition'
        AND income.source_id = bill.id
        AND income.tuition_bill_id = bill.id
        AND bill.income_record_id = income.id
        AND income.account_id IS NULL
        AND income.cash_submission_blocked IS FALSE
        AND income.operational_excluded IS FALSE
        AND bill.cash_submission_blocked IS FALSE
        AND latest.id IS NULL
        THEN 'student_tuition_cash_submit=blocked; income/bill本体通过静态资格检查，但当前页面、Edge和DB Gate均禁止提交'
      WHEN income.status = 'received'
        AND latest.sync_status IN ('synced', 'historical_confirmed')
        THEN '已到账并同步，永久禁止再次提交'
      WHEN latest.sync_status IN ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        OR latest.cash_request_status = 'pending'
        THEN '已有active Cash request/linkage attempt'
      WHEN latest.sync_status = 'cash_rejected'
        AND latest.cash_request_status = 'rejected'
        AND latest.cash_transaction_id IS NULL
        THEN '历史attempt已拒绝；仅在批准的retry合同下可创建下一attempt'
      WHEN income.status = 'incident_quarantined'
        OR income.operational_excluded IS TRUE
        OR income.cash_submission_blocked IS TRUE
        OR bill.cash_submission_blocked IS TRUE
        THEN concat('隔离/排除/阻断：', coalesce(income.incident_type, income.status, bill.status))
      WHEN bill.status = 'cancelled' OR income.status = 'cancelled'
        THEN 'bill或income已取消'
      ELSE 'bill/income/identity/linkage状态或唯一关系不满足提交合同'
    END AS blocker,
    identity.source AS billing_identity_source,
    income.source_snapshot ->> 'generation_source' AS generation_source,
    bill.relation_count,
    coalesce((
      bill.student_id = income.student_id
      AND bill.business_entity_id = income.business_entity_id
      AND bill.billing_month = income.year_month
      AND bill.billing_month = income.settlement_month
      AND bill.id = income.source_id
      AND bill.id = income.tuition_bill_id
      AND bill.income_record_id = income.id
      AND income.currency = 'JPY'
      AND income.amount = bill.bill_amount_jpy
      AND income.amount_jpy = bill.bill_amount_jpy
      AND (income.source_snapshot ->> 'tuition_bill_id')::uuid = bill.id
      AND (income.source_snapshot ->> 'billing_identity_id')::uuid = identity.id
      AND income.source_snapshot ->> 'billing_month' = bill.billing_month
      AND coalesce(
        (income.source_snapshot ->> 'bill_amount_jpy')::numeric,
        (income.source_snapshot ->> 'total_fee_jpy')::numeric,
        (income.source_snapshot ->> 'planned_lesson_fee_jpy')::numeric
      ) = bill.bill_amount_jpy
      AND (income.source_snapshot ->> 'billing_exchange_rate')::numeric = bill.billing_exchange_rate
      AND (income.source_snapshot ->> 'billing_amount_cny')::numeric = bill.billing_amount_cny
      AND (income.source_snapshot ->> 'previous_carryover_cny')::numeric = bill.previous_carryover_cny
      AND bill.source_snapshot ->> 'student_id' = bill.student_id::text
      AND bill.source_snapshot ->> 'business_entity_id' = bill.business_entity_id::text
      AND bill.source_snapshot ->> 'billing_month' = bill.billing_month
      AND coalesce(
        (bill.source_snapshot ->> 'bill_amount_jpy')::numeric,
        (bill.source_snapshot ->> 'total_fee_jpy')::numeric,
        (bill.source_snapshot ->> 'planned_lesson_fee_jpy')::numeric
      ) = bill.bill_amount_jpy
      AND (bill.source_snapshot ->> 'billing_exchange_rate')::numeric = bill.billing_exchange_rate
      AND (bill.source_snapshot ->> 'billing_amount_cny')::numeric = bill.billing_amount_cny
      AND (bill.source_snapshot ->> 'previous_carryover_cny')::numeric = bill.previous_carryover_cny
      AND bill.relation_count = bill.planned_lesson_count
    ), false) AS frozen_snapshot_consistent,
    income.created_at AS income_created_at,
    bill.created_at AS bill_created_at
  FROM bill_facts bill
  LEFT JOIN public.school_income_records income
    ON income.id = bill.income_record_id
  LEFT JOIN public.school_students student
    ON student.id = bill.student_id
  LEFT JOIN public.school_business_entities entity
    ON entity.id = bill.business_entity_id
  LEFT JOIN public.school_student_tuition_billing_identities identity
    ON identity.canonical_bill_id = bill.id
  LEFT JOIN latest_linkage latest
    ON latest.income_record_id = income.id
)
SELECT *
FROM baseline
ORDER BY billing_month, student_name, bill_id;
\o
\pset format aligned
\pset footer on

-- Fixed gate baseline.
SELECT feature_key, state, reason, release_version, evidence_hash
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

-- Classification summary from the exported canonical tuition set.
WITH latest_linkage AS (
  SELECT DISTINCT ON (event.income_record_id) event.*
  FROM public.school_personal_cash_income_linkage_events event
  ORDER BY event.income_record_id, event.attempt_no DESC, event.created_at DESC, event.id DESC
), classified AS (
  SELECT
    CASE
      WHEN income.source_type IS DISTINCT FROM 'student_tuition_bill'
        OR income.income_category IS DISTINCT FROM 'tuition' THEN 'NOT_TUITION_INCOME'
      WHEN income.status = 'received'
        AND latest.sync_status IN ('synced', 'historical_confirmed') THEN 'ALREADY_SYNCED'
      WHEN latest.sync_status IN ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        OR latest.cash_request_status = 'pending' THEN 'ALREADY_SUBMITTED'
      WHEN income.status = 'pending'
        AND latest.sync_status = 'cash_rejected'
        AND latest.cash_request_status = 'rejected'
        AND latest.cash_transaction_id IS NULL THEN 'REJECTED_RETRYABLE'
      WHEN income.status = 'pending'
        AND bill.status = 'income_created'
        AND identity.id IS NOT NULL
        AND income.source_id = bill.id
        AND income.tuition_bill_id = bill.id
        AND bill.income_record_id = income.id
        AND income.account_id IS NULL
        AND income.cash_submission_blocked IS FALSE
        AND income.operational_excluded IS FALSE
        AND bill.cash_submission_blocked IS FALSE
        AND latest.id IS NULL THEN 'ELIGIBLE_FOR_CASH_SUBMIT'
      ELSE 'BLOCKED_CONFLICT'
    END AS classification
  FROM public.school_student_tuition_bills bill
  LEFT JOIN public.school_income_records income ON income.id = bill.income_record_id
  LEFT JOIN public.school_student_tuition_billing_identities identity ON identity.canonical_bill_id = bill.id
  LEFT JOIN latest_linkage latest ON latest.income_record_id = income.id
)
SELECT classification, count(*) AS row_count
FROM classified
GROUP BY classification
ORDER BY classification;

-- Cross-object anomaly counters. Every counter should be zero for active
-- canonical rows. Cancelled/incident rows are intentionally excluded here.
WITH active AS (
  SELECT bill.*, income.id AS joined_income_id, income.source_type,
    income.source_id, income.tuition_bill_id, income.status AS income_status,
    income.amount, income.amount_jpy, income.currency AS income_currency,
    income.student_id AS income_student_id,
    income.business_entity_id AS income_business_entity_id,
    income.year_month AS income_year_month,
    income.settlement_month AS income_settlement_month,
    income.source_snapshot AS income_source_snapshot
  FROM public.school_student_tuition_bills bill
  JOIN public.school_income_records income ON income.id = bill.income_record_id
  WHERE bill.status = 'income_created'
    AND income.status <> 'incident_quarantined'
    AND income.operational_excluded IS FALSE
), relation_counts AS (
  SELECT tuition_bill_id, count(*)::integer AS relation_count
  FROM public.school_student_tuition_bill_lessons
  GROUP BY tuition_bill_id
)
SELECT
  count(*) FILTER (WHERE identity.id IS NULL) AS missing_identity,
  count(*) FILTER (WHERE active.source_type <> 'student_tuition_bill') AS wrong_source_type,
  count(*) FILTER (WHERE active.source_id <> active.id OR active.tuition_bill_id <> active.id) AS wrong_source_id,
  count(*) FILTER (WHERE active.joined_income_id <> active.income_record_id) AS wrong_bill_income_link,
  count(*) FILTER (WHERE active.student_id <> active.income_student_id) AS student_mismatch,
  count(*) FILTER (WHERE active.business_entity_id <> active.income_business_entity_id) AS business_entity_mismatch,
  count(*) FILTER (WHERE active.billing_month <> active.income_year_month OR active.billing_month <> active.income_settlement_month) AS month_mismatch,
  count(*) FILTER (WHERE active.income_currency <> 'JPY' OR active.amount <> active.bill_amount_jpy OR active.amount_jpy <> active.bill_amount_jpy) AS jpy_amount_mismatch,
  count(*) FILTER (WHERE coalesce(rel.relation_count, 0) <> active.planned_lesson_count) AS relation_count_mismatch,
  count(*) FILTER (WHERE (active.income_source_snapshot ->> 'billing_exchange_rate')::numeric <> active.billing_exchange_rate) AS billing_rate_mismatch,
  count(*) FILTER (WHERE (active.income_source_snapshot ->> 'billing_amount_cny')::numeric <> active.billing_amount_cny) AS billing_amount_mismatch,
  count(*) FILTER (WHERE (active.income_source_snapshot ->> 'previous_carryover_cny')::numeric <> active.previous_carryover_cny) AS carryover_mismatch
FROM active
LEFT JOIN public.school_student_tuition_billing_identities identity
  ON identity.canonical_bill_id = active.id
LEFT JOIN relation_counts rel
  ON rel.tuition_bill_id = active.id;

-- Linkage uniqueness and terminal-state checks.
SELECT
  count(*) FILTER (
    WHERE income.status = 'pending'
      AND (event.cash_request_id IS NOT NULL OR event.cash_transaction_id IS NOT NULL)
  ) AS pending_income_with_cash_ids,
  count(*) FILTER (
    WHERE income.status = 'received'
      AND event.sync_status = 'synced'
      AND (event.cash_request_id IS NULL OR event.cash_transaction_id IS NULL)
  ) AS synced_income_missing_cash_ids,
  count(*) FILTER (
    WHERE event.sync_status = 'cash_rejected'
      AND event.cash_transaction_id IS NOT NULL
  ) AS rejected_with_transaction
FROM public.school_income_records income
LEFT JOIN public.school_personal_cash_income_linkage_events event
  ON event.income_record_id = income.id
WHERE income.source_type = 'student_tuition_bill';

SELECT
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.school_student_tuition_bills row_value) AS bill_md5,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.school_income_records row_value) AS income_md5,
  (SELECT count(*) FROM public.school_student_tuition_billing_identities) AS identity_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.school_student_tuition_billing_identities row_value) AS identity_md5,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons) AS relation_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.school_student_tuition_bill_lessons row_value) AS relation_md5,
  (SELECT count(*) FROM public.school_personal_cash_income_linkage_events) AS linkage_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.school_personal_cash_income_linkage_events row_value) AS linkage_md5;
