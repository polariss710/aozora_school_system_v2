-- Cash DB read-only preflight/postflight for the fixed 64 historical-paid exclusion migration.
-- This file contains SELECT statements only and must never write Cash DB.
\set ON_ERROR_STOP on
\pset pager off

WITH expected(kind,id,row_hash) AS (VALUES
  ('manual','4b3f1168-af58-4c1a-a28e-6277e8fe2222'::uuid,'3309ebb08016e7f4bbf29236c0fea036'),
  ('manual','c3ee3c59-fb68-46af-8c44-8fe08cb81c1f'::uuid,'c215a4d368942f53544c80b82aad7961'),
  ('request','0cacdde8-4283-4bfc-ad1b-4c0bf99294be'::uuid,'b489b27f8e6b6d6f2c8594939da4a396'),
  ('request','1bee7599-42e0-4fc1-8a3d-47e0f64f70bc'::uuid,'51baeedcab965de79af211a5cd2870cb'),
  ('request','93c36048-754a-491b-8a52-8e987b4efc07'::uuid,'07f421b25df0b04f101712f81ba1f315'),
  ('request','a7acec4c-235c-4f41-9a9b-3957fb63a999'::uuid,'12b83549145014bf96f06ad43c185685'),
  ('synced_tx','1d89c880-afd3-484a-ba73-3f158fef44de'::uuid,'d974066d13d83bed4c2c0480bdde92d0'),
  ('synced_tx','bf23f6f2-4591-4b5d-9923-2fbf7d34e556'::uuid,'8e3fca439ceb7011fe16b5db719a13ab'),
  ('synced_tx','d479512b-9ae5-430e-b371-e530cbc281d8'::uuid,'5e2f4b9a2265594887d2bf4f3dd459c4'),
  ('synced_tx','fe6ef851-a33f-4ba9-aac9-b40fcbf9b54d'::uuid,'c53d53ae3e79ac4a676e9a58271c53e9')
), actual AS (
  SELECT 'manual'::text kind,id,md5(to_jsonb(x)::text) row_hash
  FROM public.home_cny_transactions x
  WHERE id IN (
    '4b3f1168-af58-4c1a-a28e-6277e8fe2222'::uuid,
    'c3ee3c59-fb68-46af-8c44-8fe08cb81c1f'::uuid
  )
  UNION ALL
  SELECT 'request',id,md5(to_jsonb(x)::text)
  FROM public.home_external_transaction_requests x
  WHERE id IN (
    '0cacdde8-4283-4bfc-ad1b-4c0bf99294be'::uuid,
    '1bee7599-42e0-4fc1-8a3d-47e0f64f70bc'::uuid,
    '93c36048-754a-491b-8a52-8e987b4efc07'::uuid,
    'a7acec4c-235c-4f41-9a9b-3957fb63a999'::uuid
  )
  UNION ALL
  SELECT 'synced_tx',id,md5(to_jsonb(x)::text)
  FROM public.home_cny_transactions x
  WHERE id IN (
    '1d89c880-afd3-484a-ba73-3f158fef44de'::uuid,
    'bf23f6f2-4591-4b5d-9923-2fbf7d34e556'::uuid,
    'd479512b-9ae5-430e-b371-e530cbc281d8'::uuid,
    'fe6ef851-a33f-4ba9-aac9-b40fcbf9b54d'::uuid
  )
), checked AS (
  SELECT count(*) expected_count,count(actual.id) actual_count,
         count(*) FILTER (WHERE actual.row_hash IS DISTINCT FROM expected.row_hash) mismatch_count
  FROM expected LEFT JOIN actual USING(kind,id)
)
SELECT 1/(CASE WHEN expected_count=10 AND actual_count=10 AND mismatch_count=0 THEN 1 ELSE 0 END)
  AS fixed_evidence_rows_pass
FROM checked;

WITH checked AS (
  SELECT
    (SELECT count(*) FROM public.home_cny_transactions
     WHERE id='4b3f1168-af58-4c1a-a28e-6277e8fe2222'::uuid
       AND transaction_type='income' AND created_by_external=false
       AND transacted_at='2026-05-08'::date AND currency='CNY' AND amount=8853
       AND description='彭宇晗5月课时费') AS peng_manual,
    (SELECT count(*) FROM public.home_cny_transactions
     WHERE id='c3ee3c59-fb68-46af-8c44-8fe08cb81c1f'::uuid
       AND transaction_type='income' AND created_by_external=false
       AND transacted_at='2026-05-08'::date AND currency='CNY' AND amount=21450
       AND description='李天伦5月课时费') AS li_manual,
    (SELECT count(*) FROM public.home_external_transaction_requests
     WHERE id IN (
       '0cacdde8-4283-4bfc-ad1b-4c0bf99294be'::uuid,
       '1bee7599-42e0-4fc1-8a3d-47e0f64f70bc'::uuid,
       '93c36048-754a-491b-8a52-8e987b4efc07'::uuid,
       'a7acec4c-235c-4f41-9a9b-3957fb63a999'::uuid
     ) AND status='approved' AND transaction_type='income'
       AND external_source='aozora_school'
       AND external_reference_type='school_income_records') AS approved_requests,
    (SELECT count(*) FROM public.home_cny_transactions
     WHERE id IN (
       '1d89c880-afd3-484a-ba73-3f158fef44de'::uuid,
       'bf23f6f2-4591-4b5d-9923-2fbf7d34e556'::uuid,
       'd479512b-9ae5-430e-b371-e530cbc281d8'::uuid,
       'fe6ef851-a33f-4ba9-aac9-b40fcbf9b54d'::uuid
     ) AND transaction_type='income' AND created_by_external=true
       AND external_source='aozora_school'
       AND external_reference_type='school_income_records'
       AND external_event_type='tuition_income_received') AS synced_transactions,
    (SELECT count(*) FROM public.home_cny_transactions
     WHERE transaction_type='income' AND coalesce(created_by_external,false)=false
       AND concat_ws(' ',description,note) ~* '(厦门.*(学费|课时费)|(学费|课时费).*厦门|吕同学.*(学费|课时费)|(学费|课时费).*吕同学)') AS xiamen_manual_match
)
SELECT 1/(CASE WHEN peng_manual=1 AND li_manual=1 AND approved_requests=4
                    AND synced_transactions=4 AND xiamen_manual_match=0 THEN 1 ELSE 0 END)
       AS evidence_semantics_pass,
       *
FROM checked;

WITH fingerprints AS (
  SELECT 'home_cny_transactions' object_name,count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),'')) row_hash
  FROM public.home_cny_transactions x
  UNION ALL
  SELECT 'home_external_transaction_requests',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),''))
  FROM public.home_external_transaction_requests x
  UNION ALL
  SELECT 'home_jpy_transactions',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY id::text),''))
  FROM public.home_jpy_transactions x
), checked AS (
  SELECT count(*) total,
    count(*) FILTER (WHERE object_name='home_cny_transactions' AND row_count=63 AND row_hash='3759e3d726400d5dd2225d79c78b9ac2') cny_ok,
    count(*) FILTER (WHERE object_name='home_external_transaction_requests' AND row_count=34 AND row_hash='ba0571247a869843c3ddda9075ea78dd') request_ok,
    count(*) FILTER (WHERE object_name='home_jpy_transactions' AND row_count=31 AND row_hash='95ab7cf8a8d167e9b052d3fc6b64614b') jpy_ok
  FROM fingerprints
)
SELECT 1/(CASE WHEN total=3 AND cny_ok=1 AND request_ok=1 AND jpy_ok=1 THEN 1 ELSE 0 END)
  AS full_cash_fingerprint_pass
FROM checked;

SELECT clock_timestamp() AS checked_at,
       'READ_ONLY_NO_CASH_WRITE'::text AS operation;
