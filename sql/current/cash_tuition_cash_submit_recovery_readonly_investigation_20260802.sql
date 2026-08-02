-- Cash DB side of the School V2 tuition Cash submit recovery preflight,
-- 2026-08-02. SELECT only; never call create/approve/reject RPCs here.
\set ON_ERROR_STOP on
\pset pager off

SELECT
  external_reference_type,
  request_type,
  status,
  transaction_type,
  currency,
  count(*) AS request_count
FROM public.home_external_transaction_requests
WHERE external_source = 'aozora_school'
GROUP BY external_reference_type, request_type, status, transaction_type, currency
ORDER BY external_reference_type, request_type, status, currency;

WITH request_rows AS (
  SELECT *
  FROM public.home_external_transaction_requests
  WHERE external_source = 'aozora_school'
    AND external_reference_type = 'school_income_records'
    AND request_type = 'tuition_income_received'
), transaction_rows AS (
  SELECT id, currency, transaction_type, account_id, amount,
    external_source, external_reference_type, external_reference_id,
    external_idempotency_key
  FROM public.home_cny_transactions
  UNION ALL
  SELECT id, currency, transaction_type, account_id, amount,
    external_source, external_reference_type, external_reference_id,
    external_idempotency_key
  FROM public.home_jpy_transactions
)
SELECT
  count(*) AS tuition_request_count,
  count(*) FILTER (WHERE request_rows.status = 'pending') AS pending_count,
  count(*) FILTER (WHERE request_rows.status = 'approved') AS approved_count,
  count(*) FILTER (WHERE request_rows.status = 'rejected') AS rejected_count,
  count(*) FILTER (WHERE request_rows.status = 'approved' AND request_rows.created_transaction_id IS NULL) AS approved_missing_transaction_id,
  count(*) FILTER (WHERE request_rows.status = 'rejected' AND request_rows.created_transaction_id IS NOT NULL) AS rejected_with_transaction_id,
  count(*) FILTER (WHERE transaction_rows.id IS NULL AND request_rows.created_transaction_id IS NOT NULL) AS missing_transaction,
  count(*) FILTER (
    WHERE transaction_rows.id IS NOT NULL
      AND (
        transaction_rows.amount IS DISTINCT FROM request_rows.amount
        OR transaction_rows.currency IS DISTINCT FROM request_rows.currency
        OR transaction_rows.transaction_type IS DISTINCT FROM request_rows.transaction_type
        OR transaction_rows.account_id IS DISTINCT FROM request_rows.account_id
        OR transaction_rows.external_reference_type IS DISTINCT FROM request_rows.external_reference_type
        OR transaction_rows.external_reference_id IS DISTINCT FROM request_rows.external_reference_id
        OR transaction_rows.external_idempotency_key IS DISTINCT FROM request_rows.idempotency_key
      )
  ) AS transaction_mismatch
FROM request_rows
LEFT JOIN transaction_rows
  ON transaction_rows.id = request_rows.created_transaction_id;

SELECT count(*) AS duplicate_idempotency_groups
FROM (
  SELECT idempotency_key
  FROM public.home_external_transaction_requests
  GROUP BY idempotency_key
  HAVING count(*) > 1
) duplicate_group;

SELECT count(*) AS duplicate_active_reference_groups
FROM (
  SELECT external_source, external_reference_type, external_reference_id, request_type
  FROM public.home_external_transaction_requests
  WHERE status IN ('pending', 'approved')
  GROUP BY external_source, external_reference_type, external_reference_id, request_type
  HAVING count(*) > 1
) duplicate_group;

SELECT
  (SELECT count(*) FROM public.home_external_transaction_requests) AS request_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.home_external_transaction_requests row_value) AS request_md5,
  (SELECT count(*) FROM public.home_cny_transactions) AS cny_transaction_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.home_cny_transactions row_value) AS cny_transaction_md5,
  (SELECT count(*) FROM public.home_jpy_transactions) AS jpy_transaction_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' ORDER BY row_value.id::text), ''))
     FROM public.home_jpy_transactions row_value) AS jpy_transaction_md5;
