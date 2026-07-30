\set ON_ERROR_STOP on
\pset pager off

-- R1D-E-A-E: corrected actual/planned writer and legacy compatibility inventory.
-- This file performs catalog and business-table SELECTs in one read-only
-- repeatable-read transaction. It calls no business RPC and writes no data.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT
  transaction_timestamp() AS snapshot_at,
  current_setting('transaction_isolation') AS isolation_level,
  current_setting('transaction_read_only') AS transaction_read_only,
  current_database() AS database_name,
  current_user AS database_user;

DO $hard_boundaries$
DECLARE
  v_candidate_count bigint;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_candidate_md5 text;
  v_manifest_sha text;
  v_legacy_count bigint;
  v_legacy_md5 text;
  v_overage_count bigint;
  v_overage_ids uuid[];
  v_overage_s1_populated bigint;
BEGIN
  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'R1D-E-A: R0 feature-gate boundary changed';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D-E-A: candidate function MD5 changed';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(
          billing_month,
          billing_week_start_date,
          student_settlement_month,
          billing_month_source,
          billing_month_decided_at
        ) = 5) <> 118
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(
          billing_month,
          billing_week_start_date,
          student_settlement_month,
          billing_month_source,
          billing_month_decided_at
        ) = 0) <> 279
     OR (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type = 'planned'
        AND num_nonnulls(
          billing_month,
          billing_week_start_date,
          student_settlement_month,
          billing_month_source,
          billing_month_decided_at
        ) BETWEEN 1 AND 4) <> 0 THEN
    RAISE EXCEPTION 'R1D-E-A: fixed 118/279/partial planned boundary changed';
  END IF;

  WITH candidate AS (
    SELECT
      l.id,
      l.student_id,
      l.billing_month,
      l.billing_week_start_date,
      l.duration_hours,
      l.unit_price,
      l.lesson_fee,
      l.billing_month_source,
      l.billing_month_decided_at
    FROM public.school_lesson_records l
    WHERE l.app_type = 'school'
      AND l.lesson_type = 'planned'
      AND l.status = 'planned'
      AND l.voided_at IS NULL
      AND l.is_billable IS TRUE
      AND l.student_id IS NOT NULL
      AND l.business_entity_id IS NOT NULL
      AND l.billing_month IS NOT NULL
      AND l.billing_week_start_date IS NOT NULL
      AND extract(isodow FROM l.billing_week_start_date) = 1
      AND to_char(l.billing_week_start_date, 'YYYY-MM') = l.billing_month
      AND l.student_settlement_month = l.billing_month
      AND l.billing_month_source IN (
        'approved_r1c_a_manifest',
        'approved_r1c_c_b_manifest'
      )
      AND l.billing_month_decided_at IS NOT NULL
      AND l.lesson_date IS NOT NULL
      AND l.teacher_id IS NOT NULL
      AND l.subject_id IS NOT NULL
      AND l.lesson_count > 0
      AND l.duration_hours > 0
      AND l.unit_price > 0
      AND l.lesson_fee > 0
      AND l.created_at IS NOT NULL
      AND l.updated_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.school_student_tuition_bill_lessons r
        WHERE r.planned_lesson_id = l.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.school_student_tuition_bills b
        WHERE (b.source_snapshot -> 'planned_lesson_ids') ? l.id::text
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.school_student_tuition_historical_lesson_exclusions e
        WHERE e.planned_lesson_id = l.id
      )
  )
  SELECT
    count(*),
    sum(duration_hours),
    sum(lesson_fee),
    md5(string_agg(id::text, ',' ORDER BY id::text)),
    encode(sha256(convert_to(
      string_agg(concat_ws(
        '|',
        id::text,
        student_id::text,
        billing_month,
        billing_week_start_date::text,
        duration_hours::text,
        unit_price::text,
        lesson_fee::text,
        billing_month_source,
        to_char(
          billing_month_decided_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        )
      ), E'\n' ORDER BY student_id::text, billing_month,
        billing_week_start_date, id::text) || E'\n',
      'UTF8'
    )), 'hex')
  INTO
    v_candidate_count,
    v_candidate_hours,
    v_candidate_fee,
    v_candidate_md5,
    v_manifest_sha
  FROM candidate;

  IF v_candidate_count <> 118
     OR v_candidate_hours <> 254
     OR v_candidate_fee <> 2474000
     OR v_candidate_md5 <> '77f697f82e547d84dcabf88a3c868aa1'
     OR v_manifest_sha <> 'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1' THEN
    RAISE EXCEPTION 'R1D-E-A: fixed candidate business boundary changed';
  END IF;

  SELECT
    count(*),
    md5(string_agg(id::text, ',' ORDER BY id::text))
  INTO v_legacy_count, v_legacy_md5
  FROM public.school_lesson_records
  WHERE lesson_type = 'planned'
    AND num_nonnulls(
      billing_month,
      billing_week_start_date,
      student_settlement_month,
      billing_month_source,
      billing_month_decided_at
    ) = 0;

  IF v_legacy_count <> 279
     OR v_legacy_md5 <> '0975fdc91b533680e5ccc909f076ac62' THEN
    RAISE EXCEPTION 'R1D-E-A: fixed legacy 279 boundary changed';
  END IF;

  SELECT
    count(*),
    array_agg(a.id ORDER BY a.id),
    count(*) FILTER (
      WHERE num_nonnulls(
        a.student_duration_overage_minutes,
        a.student_duration_overage_fee_jpy,
        a.student_duration_overage_policy_version,
        a.student_duration_overage_source,
        a.student_duration_overage_decided_at
      ) > 0
    )
  INTO v_overage_count, v_overage_ids, v_overage_s1_populated
  FROM public.school_lesson_records a
  JOIN public.school_lesson_records p
    ON p.id = a.planned_lesson_id
   AND p.lesson_type = 'planned'
  WHERE a.app_type = 'school'
    AND a.lesson_type = 'actual'
    AND a.duration_hours > p.duration_hours;

  IF v_overage_count <> 19
     OR v_overage_ids <> ARRAY[
       '14f0ad66-6a72-4562-bdf6-f867f5e7901d',
       '1cb708d2-404b-4fed-a9cb-fb9b974da41c',
       '4645f239-d6f7-473f-96e0-75647cf2b937',
       '4c0214ac-6ce5-4afd-b518-e3d6bd9ab978',
       '555faff7-6658-4860-8277-22f2bc4a9c65',
       '5e0786c6-8b10-4e10-9e84-addaedd5509e',
       '6a3641db-4740-4d95-b1c9-8e3ae77516c2',
       '6e16fea8-c408-421a-adc2-05107f987f5b',
       '714c671d-b98a-464f-afe2-629ed4ba148b',
       '78301f55-e157-4219-8c29-8a87f5a8fa0b',
       '7f468446-13e2-489d-aec5-2b64aeca4f9a',
       'a13b216e-4524-4315-b5aa-c1d2cc053082',
       'a7275d9c-15f1-4829-a78e-fc48b9e88e14',
       'a97f7d25-061d-4504-a47e-53490ba81061',
       'acbc65c8-ba47-4595-b2db-244ae74f83d0',
       'ae53ba74-3cb6-4090-ac7d-d19332dcad9d',
       'b74f743a-0acc-4156-9f00-2d6dfe388ce2',
       'bb4a9aa8-f3dc-4681-a934-e049ff3dce33',
       'eefe54b0-5a01-4836-b1d1-ffcca570447d'
     ]::uuid[]
     OR v_overage_s1_populated <> 0 THEN
    RAISE EXCEPTION 'R1D-E-A-E: fixed overage-19 or S1-A NULL boundary changed';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bills x)
        <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_income_records x)
        <> '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(x) - ARRAY[
          'base_lesson_fee_jpy_snapshot',
          'aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot',
          'aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot',
          'fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot',
          'lesson_venue_code_snapshot'
        ])::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_bill_lessons x)
        <> '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions) <> 42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
         FROM public.school_student_tuition_historical_lesson_exclusions x)
        <> '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R1D-E-A: School financial-chain boundary changed';
  END IF;
END
$hard_boundaries$;

-- Frozen boundary disclosure.
SELECT feature_key, state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS candidate_function_md5,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE lesson_type = 'planned'
     AND num_nonnulls(
       billing_month,
       billing_week_start_date,
       student_settlement_month,
       billing_month_source,
       billing_month_decided_at
     ) = 5) AS fixed_complete_planned,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE lesson_type = 'planned'
     AND num_nonnulls(
       billing_month,
       billing_week_start_date,
       student_settlement_month,
       billing_month_source,
       billing_month_decided_at
     ) = 0) AS fixed_legacy_planned;

WITH candidate AS (
  SELECT
    l.id,
    l.student_id,
    l.billing_month,
    l.billing_week_start_date,
    l.duration_hours,
    l.unit_price,
    l.lesson_fee,
    l.billing_month_source,
    l.billing_month_decided_at
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.lesson_type = 'planned'
    AND l.status = 'planned'
    AND l.voided_at IS NULL
    AND l.is_billable IS TRUE
    AND l.student_id IS NOT NULL
    AND l.business_entity_id IS NOT NULL
    AND l.billing_month IS NOT NULL
    AND l.billing_week_start_date IS NOT NULL
    AND extract(isodow FROM l.billing_week_start_date) = 1
    AND to_char(l.billing_week_start_date, 'YYYY-MM') = l.billing_month
    AND l.student_settlement_month = l.billing_month
    AND l.billing_month_source IN (
      'approved_r1c_a_manifest',
      'approved_r1c_c_b_manifest'
    )
    AND l.billing_month_decided_at IS NOT NULL
    AND l.lesson_date IS NOT NULL
    AND l.teacher_id IS NOT NULL
    AND l.subject_id IS NOT NULL
    AND l.lesson_count > 0
    AND l.duration_hours > 0
    AND l.unit_price > 0
    AND l.lesson_fee > 0
    AND l.created_at IS NOT NULL
    AND l.updated_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons r
      WHERE r.planned_lesson_id = l.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_bills b
      WHERE (b.source_snapshot -> 'planned_lesson_ids') ? l.id::text
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
      WHERE e.planned_lesson_id = l.id
    )
)
SELECT
  count(*) AS candidate_count,
  sum(duration_hours) AS candidate_hours,
  sum(lesson_fee) AS candidate_fee_jpy,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS candidate_uuid_md5,
  encode(sha256(convert_to(
    string_agg(concat_ws(
      '|', id::text, student_id::text, billing_month,
      billing_week_start_date::text, duration_hours::text, unit_price::text,
      lesson_fee::text, billing_month_source,
      to_char(
        billing_month_decided_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
    ), E'\n' ORDER BY student_id::text, billing_month,
      billing_week_start_date, id::text) || E'\n',
    'UTF8'
  )), 'hex') AS candidate_manifest_sha256
FROM candidate;

SELECT
  count(*) AS legacy_count,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS legacy_uuid_md5
FROM public.school_lesson_records
WHERE lesson_type = 'planned'
  AND num_nonnulls(
    billing_month,
    billing_week_start_date,
    student_settlement_month,
    billing_month_source,
    billing_month_decided_at
  ) = 0;

-- Operating counts are disclosure-only and may legitimately drift.
SELECT
  count(*) AS lesson_count,
  count(*) FILTER (WHERE lesson_type = 'planned') AS planned_count,
  count(*) FILTER (WHERE lesson_type = 'actual') AS actual_count,
  count(*) FILTER (WHERE lesson_type = 'actual' AND voided_at IS NOT NULL) AS voided_actual_count,
  (SELECT count(*) FROM public.school_student_monthly_settlements) AS settlement_count
FROM public.school_lesson_records;

SELECT
  lesson_type,
  status,
  is_billable,
  count(*) AS row_count
FROM public.school_lesson_records
GROUP BY lesson_type, status, is_billable
ORDER BY lesson_type, status, is_billable;

-- student_settlement_month column, constraints, indexes and population.
SELECT
  table_schema,
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'school_lesson_records'
  AND column_name = 'student_settlement_month';

SELECT
  c.conname,
  c.contype,
  c.convalidated,
  pg_get_constraintdef(c.oid, true) AS definition
FROM pg_constraint c
WHERE c.conrelid = 'public.school_lesson_records'::regclass
  AND pg_get_constraintdef(c.oid, true) ILIKE '%student_settlement_month%'
ORDER BY c.conname;

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'school_lesson_records'
  AND indexdef ILIKE '%student_settlement_month%'
ORDER BY indexname;

SELECT
  count(*) AS actual_total,
  count(*) FILTER (WHERE student_settlement_month IS NULL) AS settlement_month_null,
  count(*) FILTER (WHERE student_settlement_month IS NOT NULL) AS settlement_month_nonnull,
  count(*) FILTER (
    WHERE student_settlement_month IS NOT NULL
      AND student_settlement_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ) AS settlement_month_invalid,
  count(*) FILTER (
    WHERE student_settlement_month = year_month
  ) AS new_matches_old_year_month,
  count(*) FILTER (
    WHERE student_settlement_month = to_char(lesson_date, 'YYYY-MM')
  ) AS new_matches_actual_date_month
FROM public.school_lesson_records
WHERE lesson_type = 'actual';

-- New-vs-old month inventory and downstream immutable/effective snapshots.
WITH actual_inventory AS (
  SELECT
    a.*,
    p.year_month AS planned_year_month,
    p.billing_month AS planned_billing_month,
    p.student_settlement_month AS planned_student_settlement_month,
    to_char(a.lesson_date, 'YYYY-MM') AS actual_date_month,
    EXISTS (
      SELECT 1
      FROM public.school_student_monthly_settlements s
      WHERE s.student_id = a.student_id
        AND s.year_month = a.year_month
        AND coalesce(s.settlement_status, '') <> 'unlocked'
    ) AS locked_in_old_month,
    EXISTS (
      SELECT 1
      FROM public.school_student_monthly_settlements s
      WHERE s.student_id = a.student_id
        AND s.year_month = p.year_month
        AND coalesce(s.settlement_status, '') <> 'unlocked'
    ) AS locked_in_source_planned_month,
    EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bill_lessons r
      WHERE r.planned_lesson_id = a.planned_lesson_id
    ) AS source_in_bill_relation,
    EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bills b
      WHERE (b.source_snapshot -> 'planned_lesson_ids') ? a.planned_lesson_id::text
    ) AS source_in_bill_json,
    EXISTS (
      SELECT 1
      FROM public.school_teacher_wage_lock_details d
      JOIN public.school_teacher_wage_locks w ON w.id = d.lock_id
      WHERE d.lesson_record_id = a.id
        AND coalesce(w.status, '') <> 'void'
        AND w.voided_at IS NULL
    ) AS in_active_wage_snapshot,
    CASE
      WHEN a.status = 'makeup_completed' THEN 'makeup'
      WHEN a.status = 'cancelled' THEN 'cancelled'
      WHEN a.status = 'completed' AND p.id IS NULL THEN 'completed_without_source'
      WHEN a.status = 'completed' AND a.duration_hours < p.duration_hours THEN 'partial_like'
      WHEN a.status = 'completed' AND a.duration_hours = p.duration_hours THEN 'ordinary_equal_duration'
      WHEN a.status = 'completed' AND a.duration_hours > p.duration_hours THEN 'ordinary_legacy_overage'
      ELSE 'other'
    END AS writer_shape
  FROM public.school_lesson_records a
  LEFT JOIN public.school_lesson_records p
    ON p.id = a.planned_lesson_id
   AND p.lesson_type = 'planned'
  WHERE a.lesson_type = 'actual'
)
SELECT
  writer_shape,
  count(*) AS actual_count,
  count(*) FILTER (WHERE planned_lesson_id IS NOT NULL) AS with_planned_link,
  count(*) FILTER (WHERE planned_student_settlement_month IS NOT NULL) AS source_authoritative_nonnull,
  count(*) FILTER (WHERE student_settlement_month IS NULL) AS new_field_null,
  count(*) FILTER (WHERE year_month = planned_year_month) AS old_matches_source_year_month,
  count(*) FILTER (WHERE year_month = actual_date_month) AS old_matches_actual_date_month,
  count(*) FILTER (WHERE planned_year_month IS DISTINCT FROM actual_date_month) AS source_vs_actual_date_diff,
  count(*) FILTER (WHERE locked_in_old_month) AS locked_in_old_month,
  count(*) FILTER (WHERE locked_in_source_planned_month) AS locked_in_source_month,
  count(*) FILTER (WHERE source_in_bill_relation) AS source_in_bill_relation,
  count(*) FILTER (WHERE source_in_bill_json) AS source_in_bill_json,
  count(*) FILTER (WHERE in_active_wage_snapshot) AS active_wage_snapshot
FROM actual_inventory
GROUP BY writer_shape
ORDER BY writer_shape;

WITH actual_inventory AS (
  SELECT
    a.id,
    a.student_settlement_month,
    a.year_month,
    to_char(a.lesson_date, 'YYYY-MM') AS actual_date_month,
    p.year_month AS planned_year_month,
    p.billing_month AS planned_billing_month,
    p.student_settlement_month AS planned_student_settlement_month
  FROM public.school_lesson_records a
  LEFT JOIN public.school_lesson_records p
    ON p.id = a.planned_lesson_id
   AND p.lesson_type = 'planned'
  WHERE a.lesson_type = 'actual'
)
SELECT
  count(*) AS actual_total,
  count(*) FILTER (WHERE planned_year_month IS NOT NULL) AS with_source_planned,
  count(*) FILTER (WHERE student_settlement_month IS NULL) AS new_field_null,
  count(*) FILTER (WHERE year_month = planned_year_month) AS old_matches_source_year_month,
  count(*) FILTER (WHERE year_month IS DISTINCT FROM planned_year_month) AS old_differs_source_year_month,
  count(*) FILTER (WHERE year_month = actual_date_month) AS old_matches_actual_date_month,
  count(*) FILTER (WHERE year_month IS DISTINCT FROM actual_date_month) AS old_differs_actual_date_month,
  count(*) FILTER (WHERE planned_year_month = actual_date_month) AS source_matches_actual_date_month,
  count(*) FILTER (WHERE planned_year_month IS DISTINCT FROM actual_date_month) AS source_differs_actual_date_month,
  count(*) FILTER (WHERE planned_student_settlement_month IS NOT NULL) AS source_new_month_nonnull,
  count(*) FILTER (
    WHERE planned_student_settlement_month IS NOT NULL
      AND year_month = planned_student_settlement_month
  ) AS old_matches_source_authoritative_month,
  count(*) FILTER (
    WHERE planned_student_settlement_month IS NOT NULL
      AND year_month IS DISTINCT FROM planned_student_settlement_month
  ) AS old_differs_source_authoritative_month
FROM actual_inventory;

-- Fixed legacy overage-19 disclosure. No inference, repair or charge is made.
SELECT
  count(*) AS legacy_overage_count,
  count(*) FILTER (WHERE a.student_settlement_month IS NULL) AS new_month_null,
  count(*) FILTER (WHERE a.year_month = p.year_month) AS old_matches_source_year_month,
  count(*) FILTER (WHERE a.year_month = to_char(a.lesson_date, 'YYYY-MM')) AS old_matches_actual_date_month,
  count(*) FILTER (
    WHERE EXISTS (
      SELECT 1 FROM public.school_student_monthly_settlements s
      WHERE s.student_id = a.student_id
        AND s.year_month = a.year_month
        AND coalesce(s.settlement_status, '') <> 'unlocked'
    )
  ) AS locked_in_old_month,
  count(*) FILTER (
    WHERE EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons r
      WHERE r.planned_lesson_id = a.planned_lesson_id
    )
  ) AS source_in_bill_relation,
  sum(a.duration_hours - p.duration_hours) AS overage_hours,
  sum(a.lesson_fee - p.lesson_fee) AS historical_fee_difference_jpy,
  count(*) FILTER (
    WHERE num_nonnulls(
      a.student_duration_overage_minutes,
      a.student_duration_overage_fee_jpy,
      a.student_duration_overage_policy_version,
      a.student_duration_overage_source,
      a.student_duration_overage_decided_at
    ) > 0
  ) AS s1_snapshot_populated
FROM public.school_lesson_records a
JOIN public.school_lesson_records p
  ON p.id = a.planned_lesson_id
 AND p.lesson_type = 'planned'
WHERE a.app_type = 'school'
  AND a.lesson_type = 'actual'
  AND a.duration_hours > p.duration_hours;

-- Settlement snapshot status and month distribution.
SELECT
  settlement_status,
  count(*) AS settlement_count,
  min(year_month) AS first_month,
  max(year_month) AS last_month
FROM public.school_student_monthly_settlements
GROUP BY settlement_status
ORDER BY settlement_status;

-- Catalog-complete inventory of functions that can touch actual lessons or
-- read lesson months. Definition text is summarized by stable MD5 plus flags.
WITH function_inventory AS (
  SELECT
    p.oid,
    p.oid::regprocedure::text AS signature,
    r.rolname AS owner,
    p.prosecdef AS security_definer,
    p.provolatile,
    p.proacl,
    pg_get_functiondef(p.oid) AS definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE n.nspname = 'public'
)
SELECT
  signature,
  owner,
  security_definer,
  provolatile,
  proacl::text AS acl,
  md5(definition) AS definition_md5,
  position('school_lesson_records' IN definition) > 0 AS touches_lesson_table,
  position('lesson_type = ''actual''' IN definition) > 0
    OR position('lesson_type=''actual''' IN definition) > 0 AS has_actual_filter,
  position('insert into public.school_lesson_records' IN lower(definition)) > 0 AS inserts_lesson,
  position('update public.school_lesson_records' IN lower(definition)) > 0 AS updates_lesson,
  position('student_settlement_month' IN definition) > 0 AS uses_student_settlement_month,
  position('.year_month' IN definition) > 0 AS uses_year_month,
  position('lesson_date' IN definition) > 0 AS uses_lesson_date,
  position('school_student_monthly_settlements' IN definition) > 0 AS touches_settlement,
  position('source_snapshot' IN definition) > 0 AS uses_json_snapshot
FROM function_inventory
WHERE signature ~ '^school_'
  AND (
    definition ILIKE '%school_lesson_records%'
    OR definition ILIKE '%school_student_monthly_settlements%'
    OR definition ILIKE '%school_student_tuition_bill_lessons%'
  )
  AND (
    definition ILIKE '%actual%'
    OR definition ILIKE '%student_settlement%'
    OR definition ILIKE '%year_month%'
    OR signature ILIKE '%lesson%'
  )
ORDER BY signature;

-- Focused writer/readers, including compatibility and guarded-edit entrypoints.
WITH selected_names(name) AS (
  VALUES
    ('school_create_actual_lesson_from_planned'),
    ('school_create_cancelled_actual_lesson_from_planned'),
    ('school_create_partial_completed_actual_from_planned'),
    ('school_create_lesson_credit_makeup_actual'),
    ('school_create_makeup_completed_actual_lesson_from_planned'),
    ('school_create_cross_month_makeup_completed_actual_from_planned'),
    ('school_update_lesson_record_guarded'),
    ('school_update_lesson_record_guarded_with_venue'),
    ('school_import_lesson_records_batch'),
    ('school_import_lesson_records_batch_with_venue'),
    ('school_backfill_actual_minutes_from_duration'),
    ('school_get_student_monthly_settlement_summary'),
    ('school_get_student_monthly_settlement_preview'),
    ('school_get_student_monthly_settlement_wage_blockers'),
    ('school_assert_student_monthly_settlement_no_wage_blocker'),
    ('school_lock_student_monthly_settlement'),
    ('school_unlock_student_monthly_settlement'),
    ('school_relock_student_monthly_settlement'),
    ('school_set_student_monthly_settlement_draft_adjustment'),
    ('school_preview_student_tuition_bill'),
    ('school_generate_student_tuition_bill')
), function_inventory AS (
  SELECT
    p.oid,
    p.proname,
    p.oid::regprocedure::text AS signature,
    r.rolname AS owner,
    p.prosecdef AS security_definer,
    p.provolatile,
    p.proacl,
    pg_get_functiondef(p.oid) AS definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE n.nspname = 'public'
)
SELECT
  s.name AS requested_name,
  f.signature,
  f.owner,
  f.security_definer,
  f.provolatile,
  f.proacl::text AS acl,
  md5(f.definition) AS definition_md5,
  coalesce(regexp_count(f.definition, 'student_settlement_month', 1, 'i'), 0) AS student_month_refs,
  coalesce(regexp_count(f.definition, 'year_month', 1, 'i'), 0) AS year_month_refs,
  coalesce(regexp_count(f.definition, 'lesson_date', 1, 'i'), 0) AS lesson_date_refs,
  coalesce(regexp_count(f.definition, 'school_student_monthly_settlements', 1, 'i'), 0) AS settlement_refs,
  coalesce(regexp_count(f.definition, 'source_snapshot', 1, 'i'), 0) AS snapshot_refs,
  coalesce(regexp_count(f.definition, 'insert[[:space:]]+into[[:space:]]+public[.]school_lesson_records', 1, 'i'), 0) AS lesson_inserts,
  coalesce(regexp_count(f.definition, 'update[[:space:]]+public[.]school_lesson_records', 1, 'i'), 0) AS lesson_updates
FROM selected_names s
LEFT JOIN function_inventory f ON f.proname = s.name
ORDER BY s.name, f.signature;

-- Trigger and view paths are listed without guessing from filenames.
SELECT
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid, true) AS trigger_definition,
  t.tgfoid::regprocedure::text AS trigger_function,
  md5(pg_get_functiondef(t.tgfoid)) AS trigger_function_md5,
  position('student_settlement_month' IN pg_get_functiondef(t.tgfoid)) > 0
    AS trigger_uses_student_settlement_month,
  position('year_month' IN pg_get_functiondef(t.tgfoid)) > 0
    AS trigger_uses_year_month
FROM pg_trigger t
WHERE t.tgrelid = 'public.school_lesson_records'::regclass
  AND NOT t.tgisinternal
ORDER BY t.tgname;

SELECT
  schemaname,
  viewname,
  md5(definition) AS definition_md5,
  position('student_settlement_month' IN definition) > 0 AS uses_student_settlement_month,
  position('year_month' IN definition) > 0 AS uses_year_month,
  position('lesson_date' IN definition) > 0 AS uses_lesson_date
FROM pg_views
WHERE schemaname = 'public'
  AND definition ILIKE '%school_lesson_records%'
ORDER BY viewname;

-- Direct-write surface: table ACL, RLS and policies.
SELECT
  c.oid::regclass::text AS table_name,
  r.rolname AS owner,
  c.relrowsecurity,
  c.relforcerowsecurity,
  c.relacl::text AS acl
FROM pg_class c
JOIN pg_roles r ON r.oid = c.relowner
WHERE c.oid IN (
  'public.school_lesson_records'::regclass,
  'public.school_student_monthly_settlements'::regclass
)
ORDER BY table_name;

SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'school_lesson_records',
    'school_student_monthly_settlements'
  )
ORDER BY tablename, policyname;

-- E-A-E correction: classify the immutable legacy-279 planned set. The set is
-- fixed by the hard-boundary count and UUID MD5 above; no later NULL row can
-- silently enter this evidence set without failing the transaction.
WITH legacy AS (
  SELECT l.*
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.lesson_type = 'planned'
    AND num_nonnulls(
      l.billing_month,
      l.billing_week_start_date,
      l.student_settlement_month,
      l.billing_month_source,
      l.billing_month_decided_at
    ) = 0
)
SELECT
  count(*) AS legacy_count,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS legacy_uuid_md5,
  min(lesson_date) AS first_lesson_date,
  max(lesson_date) AS last_lesson_date,
  min(year_month) AS first_year_month,
  max(year_month) AS last_year_month,
  count(*) FILTER (WHERE lesson_date < current_date) AS historical_date_count,
  count(*) FILTER (WHERE lesson_date = current_date) AS current_date_count,
  count(*) FILTER (WHERE lesson_date > current_date) AS future_date_count,
  count(*) FILTER (WHERE lesson_date IS NULL) AS null_date_count,
  count(*) FILTER (WHERE voided_at IS NOT NULL) AS voided_count,
  count(*) FILTER (
    WHERE num_nonnulls(
      billing_month,
      billing_week_start_date,
      student_settlement_month,
      billing_month_source,
      billing_month_decided_at
    ) <> 0
  ) AS five_field_nonnull_exception_count
FROM legacy;

WITH legacy AS (
  SELECT l.*
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.lesson_type = 'planned'
    AND num_nonnulls(
      l.billing_month,
      l.billing_week_start_date,
      l.student_settlement_month,
      l.billing_month_source,
      l.billing_month_decided_at
    ) = 0
)
SELECT
  status,
  count(*) AS row_count,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS status_uuid_md5
FROM legacy
GROUP BY status
ORDER BY status;

WITH legacy AS (
  SELECT l.*
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.lesson_type = 'planned'
    AND num_nonnulls(
      l.billing_month,
      l.billing_week_start_date,
      l.student_settlement_month,
      l.billing_month_source,
      l.billing_month_decided_at
    ) = 0
), actual_usage AS (
  SELECT
    a.planned_lesson_id,
    count(*) AS actual_count,
    coalesce(sum(a.duration_hours) FILTER (
      WHERE a.status IN ('completed', 'makeup_completed')
    ), 0)::numeric AS consumed_hours
  FROM public.school_lesson_records a
  WHERE a.app_type = 'school'
    AND a.lesson_type = 'actual'
  GROUP BY a.planned_lesson_id
), facts AS (
  SELECT
    l.*,
    coalesce(u.actual_count, 0) AS actual_count,
    greatest(
      coalesce(l.duration_hours, 0) - coalesce(u.consumed_hours, 0),
      0
    )::numeric AS remaining_hours,
    l.student_id IS NOT NULL
      AND l.teacher_id IS NOT NULL
      AND l.subject_id IS NOT NULL
      AND l.business_entity_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.school_students s
        WHERE s.id = l.student_id
          AND s.app_type = 'school'
          AND coalesce(s.status, 'active') NOT IN ('inactive', 'graduated')
          AND (s.business_entity_id IS NULL OR s.business_entity_id = l.business_entity_id)
      )
      AND EXISTS (
        SELECT 1 FROM public.school_teachers t
        WHERE t.id = l.teacher_id
          AND t.app_type = 'school'
          AND coalesce(t.status, 'employed') NOT IN ('inactive', 'retired')
      )
      AND EXISTS (
        SELECT 1 FROM public.school_subjects s
        WHERE s.id = l.subject_id AND coalesce(s.is_active, true)
      )
      AND EXISTS (
        SELECT 1 FROM public.school_business_entities b
        WHERE b.id = l.business_entity_id AND coalesce(b.is_active, true)
      ) AS source_master_valid,
    EXISTS (
      SELECT 1 FROM public.school_student_monthly_settlements s
      WHERE s.student_id = l.student_id
        AND s.year_month = l.year_month
        AND s.business_entity_id IS NOT DISTINCT FROM l.business_entity_id
        AND s.settlement_status = 'locked'
    ) AS source_month_locked,
    EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons r
      WHERE r.planned_lesson_id = l.id
    ) AS in_bill_relation,
    EXISTS (
      SELECT 1 FROM public.school_student_tuition_bills b
      WHERE (b.source_snapshot -> 'planned_lesson_ids') ? l.id::text
    ) AS in_bill_json,
    EXISTS (
      SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
      WHERE e.planned_lesson_id = l.id
    ) AS in_historical_exclusion,
    EXISTS (
      SELECT 1
      FROM public.school_lesson_records a
      JOIN public.school_teacher_wage_lock_details d ON d.lesson_record_id = a.id
      JOIN public.school_teacher_wage_locks w ON w.id = d.lock_id
      WHERE a.planned_lesson_id = l.id
        AND a.app_type = 'school'
        AND a.lesson_type = 'actual'
        AND coalesce(w.status, '') <> 'void'
        AND w.voided_at IS NULL
    ) AS in_active_wage_snapshot
  FROM legacy l
  LEFT JOIN actual_usage u ON u.planned_lesson_id = l.id
), classified AS (
  SELECT
    f.*,
    voided_at IS NULL
      AND status IN ('planned', 'pending_makeup')
      AND actual_count = 0
      AND source_master_valid
      AND NOT source_month_locked AS ordinary_rpc_source_possible,
    voided_at IS NULL
      AND status = 'planned'
      AND actual_count = 0
      AND coalesce(duration_hours, 0) > 0
      AND source_master_valid
      AND NOT source_month_locked AS partial_rpc_source_possible,
    voided_at IS NULL
      AND status IN ('planned', 'pending_makeup')
      AND actual_count = 0
      AND source_master_valid
      AND NOT source_month_locked AS cancelled_rpc_source_possible,
    voided_at IS NULL
      AND status = 'pending_makeup'
      AND remaining_hours > 0
      AND source_master_valid AS makeup_rpc_source_possible,
    voided_at IS NULL
      AND status = 'planned'
      AND actual_count = 0 AS page_ordinary_button_visible,
    voided_at IS NULL
      AND status = 'planned'
      AND actual_count = 0 AS page_cancel_button_visible_but_dialog_rejects,
    voided_at IS NULL
      AND status = 'pending_makeup'
      AND actual_count = 0 AS page_same_month_makeup_button_visible,
    voided_at IS NULL
      AND status = 'pending_makeup'
      AND remaining_hours > 0 AS cross_month_candidate_source
  FROM facts f
)
SELECT
  count(*) AS legacy_count,
  count(*) FILTER (WHERE actual_count = 0) AS linked_actual_zero,
  count(*) FILTER (WHERE actual_count = 1) AS linked_actual_one,
  count(*) FILTER (WHERE actual_count > 1) AS linked_actual_multiple,
  count(*) FILTER (WHERE ordinary_rpc_source_possible) AS ordinary_rpc_source_possible,
  md5(string_agg(id::text, ',' ORDER BY id::text)
    FILTER (WHERE ordinary_rpc_source_possible)) AS ordinary_possible_uuid_md5,
  count(*) FILTER (WHERE partial_rpc_source_possible) AS partial_rpc_source_possible,
  md5(string_agg(id::text, ',' ORDER BY id::text)
    FILTER (WHERE partial_rpc_source_possible)) AS partial_possible_uuid_md5,
  count(*) FILTER (WHERE cancelled_rpc_source_possible) AS cancelled_rpc_source_possible,
  md5(string_agg(id::text, ',' ORDER BY id::text)
    FILTER (WHERE cancelled_rpc_source_possible)) AS cancelled_possible_uuid_md5,
  count(*) FILTER (WHERE makeup_rpc_source_possible) AS makeup_rpc_source_possible,
  md5(string_agg(id::text, ',' ORDER BY id::text)
    FILTER (WHERE makeup_rpc_source_possible)) AS makeup_possible_uuid_md5,
  count(*) FILTER (WHERE page_ordinary_button_visible) AS page_ordinary_button_visible,
  count(*) FILTER (WHERE page_cancel_button_visible_but_dialog_rejects)
    AS page_cancel_button_visible_but_dialog_rejects,
  count(*) FILTER (WHERE page_same_month_makeup_button_visible)
    AS page_same_month_makeup_button_visible,
  count(*) FILTER (WHERE cross_month_candidate_source) AS cross_month_candidate_source,
  count(*) FILTER (WHERE in_bill_relation) AS in_bill_relation,
  count(*) FILTER (WHERE in_bill_json) AS in_bill_json,
  count(*) FILTER (WHERE in_historical_exclusion) AS in_historical_exclusion,
  count(*) FILTER (WHERE source_month_locked) AS source_month_locked,
  count(*) FILTER (WHERE in_active_wage_snapshot) AS in_active_wage_snapshot,
  count(*) FILTER (WHERE remaining_hours > 0) AS positive_credit_remaining,
  count(*) FILTER (WHERE NOT source_master_valid) AS source_master_invalid
FROM classified;

-- Planned writer inventory. Reference counts are evidence only: zero for all
-- five fields means new planned rows can still enter as five-NULL.
WITH selected_names(name, writer_kind) AS (
  VALUES
    ('school_create_planned_lesson_record', 'single_create'),
    ('school_create_planned_lesson_record_with_venue', 'single_create_wrapper'),
    ('school_generate_planned_lessons_batch', 'batch_generate'),
    ('school_generate_planned_lessons_batch_with_venue', 'batch_generate_wrapper'),
    ('school_import_lesson_records_batch', 'batch_import'),
    ('school_import_lesson_records_batch_with_venue', 'batch_import_wrapper'),
    ('school_update_lesson_record_guarded', 'guarded_edit'),
    ('school_update_lesson_record_guarded_with_venue', 'guarded_edit_wrapper')
), functions AS (
  SELECT
    p.proname,
    p.oid::regprocedure::text AS signature,
    pg_get_functiondef(p.oid) AS definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
)
SELECT
  s.writer_kind,
  s.name AS requested_name,
  f.signature,
  md5(f.definition) AS definition_md5,
  coalesce(regexp_count(f.definition, 'insert[[:space:]]+into[[:space:]]+public[.]school_lesson_records', 1, 'i'), 0)
    AS lesson_insert_refs,
  coalesce(regexp_count(f.definition, 'update[[:space:]]+public[.]school_lesson_records', 1, 'i'), 0)
    AS lesson_update_refs,
  coalesce(regexp_count(f.definition, 'billing_month', 1, 'i'), 0) AS billing_month_refs,
  coalesce(regexp_count(f.definition, 'billing_week_start_date', 1, 'i'), 0) AS billing_week_refs,
  coalesce(regexp_count(f.definition, 'student_settlement_month', 1, 'i'), 0) AS student_month_refs,
  coalesce(regexp_count(f.definition, 'billing_month_source', 1, 'i'), 0) AS source_refs,
  coalesce(regexp_count(f.definition, 'billing_month_decided_at', 1, 'i'), 0) AS decided_at_refs,
  coalesce(regexp_count(f.definition, 'school_planned_writer_commands', 1, 'i'), 0) AS command_ledger_refs
FROM selected_names s
LEFT JOIN functions f ON f.proname = s.name
ORDER BY s.writer_kind, f.signature;

WITH functions AS (
  SELECT
    p.proname,
    p.oid::regprocedure::text AS signature,
    pg_get_functiondef(p.oid) AS definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
)
SELECT
  (SELECT count(*) FROM public.school_planned_writer_commands) AS command_ledger_rows,
  count(*) FILTER (WHERE definition ILIKE '%school_planned_writer_commands%')
    AS functions_referencing_command_ledger,
  count(*) FILTER (
    WHERE proname ILIKE '%copy%planned%'
       OR proname ILIKE '%planned%copy%'
       OR proname ILIKE '%duplicate%planned%'
       OR proname ILIKE '%planned%duplicate%'
  ) AS copy_or_duplicate_named_functions,
  count(*) FILTER (
    WHERE definition ~* 'insert[[:space:]]+into[[:space:]]+public[.]school_lesson_records'
      AND definition ~* 'planned'
  ) AS catalog_functions_inserting_planned_like_rows,
  count(*) FILTER (
    WHERE definition ~* 'update[[:space:]]+public[.]school_lesson_records'
      AND definition ~* 'planned'
  ) AS catalog_functions_updating_planned_like_rows
FROM functions;

WITH planned AS (
  SELECT
    id,
    created_at,
    num_nonnulls(
      billing_month,
      billing_week_start_date,
      student_settlement_month,
      billing_month_source,
      billing_month_decided_at
    ) AS field_count
  FROM public.school_lesson_records
  WHERE app_type = 'school' AND lesson_type = 'planned'
)
SELECT
  min(created_at) FILTER (WHERE field_count = 0) AS legacy_created_min,
  max(created_at) FILTER (WHERE field_count = 0) AS legacy_created_max,
  min(created_at) FILTER (WHERE field_count = 5) AS complete_created_min,
  max(created_at) FILTER (WHERE field_count = 5) AS complete_created_max,
  count(*) FILTER (
    WHERE field_count = 0
      AND created_at >= (SELECT min(created_at) FROM planned WHERE field_count = 5)
  ) AS legacy_created_at_or_after_first_complete,
  count(*) FILTER (WHERE created_at IS NULL) AS created_at_null_count
FROM planned;

-- Every locked snapshot is fingerprinted against both the current summary
-- basis (student + old year_month) and current detail basis (plus entity).
WITH locked AS (
  SELECT *
  FROM public.school_student_monthly_settlements
  WHERE settlement_status = 'locked'
)
SELECT
  s.id AS snapshot_id,
  s.student_id,
  s.business_entity_id,
  s.year_month,
  s.settlement_status,
  s.created_at,
  s.locked_at,
  summary_basis.lesson_count AS current_summary_lesson_count,
  summary_basis.planned_count AS current_summary_planned_count,
  summary_basis.actual_count AS current_summary_actual_count,
  summary_basis.lesson_uuid_md5 AS current_summary_lesson_uuid_md5,
  detail_basis.lesson_count AS current_detail_lesson_count,
  detail_basis.planned_count AS current_detail_planned_count,
  detail_basis.actual_count AS current_detail_actual_count,
  detail_basis.lesson_uuid_md5 AS current_detail_lesson_uuid_md5,
  md5(concat_ws(
    '|',
    s.preset_exchange_rate::text,
    s.planned_lesson_fee_jpy::text,
    s.planned_lesson_fee_cny::text,
    s.actual_lesson_fee_jpy::text,
    s.actual_lesson_fee_cny::text,
    s.previous_balance_cny::text,
    s.received_jpy::text,
    s.received_cny::text,
    s.received_equivalent_cny::text,
    s.system_difference_cny::text,
    s.adjustment_amount_cny::text,
    s.carryover_amount_cny::text
  )) AS snapshot_amount_md5,
  md5(to_jsonb(s)::text) AS snapshot_structure_md5,
  blockers.posted_adjustment_count,
  blockers.active_carryover_count,
  blockers.active_wage_lock_count,
  blockers.live_relock_source_count,
  blockers.posted_adjustment_count = 0
    AND blockers.active_carryover_count = 0
    AND blockers.active_wage_lock_count = 0 AS unlock_currently_allowed,
  false AS relock_currently_allowed_while_locked,
  blockers.posted_adjustment_count = 0
    AND blockers.active_carryover_count = 0
    AND blockers.active_wage_lock_count = 0
    AND blockers.live_relock_source_count > 0 AS relock_after_successful_unlock_possible,
  true AS relock_recomputes_from_live_old_year_month_basis
FROM locked s
LEFT JOIN LATERAL (
  SELECT
    count(*) AS lesson_count,
    count(*) FILTER (WHERE l.lesson_type = 'planned') AS planned_count,
    count(*) FILTER (WHERE l.lesson_type = 'actual') AS actual_count,
    md5(string_agg(l.id::text, ',' ORDER BY l.id::text)) AS lesson_uuid_md5
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.student_id = s.student_id
    AND l.year_month = s.year_month
    AND NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL)
) summary_basis ON true
LEFT JOIN LATERAL (
  SELECT
    count(*) AS lesson_count,
    count(*) FILTER (WHERE l.lesson_type = 'planned') AS planned_count,
    count(*) FILTER (WHERE l.lesson_type = 'actual') AS actual_count,
    md5(string_agg(l.id::text, ',' ORDER BY l.id::text)) AS lesson_uuid_md5
  FROM public.school_lesson_records l
  WHERE l.app_type = 'school'
    AND l.student_id = s.student_id
    AND l.business_entity_id IS NOT DISTINCT FROM s.business_entity_id
    AND l.year_month = s.year_month
    AND NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL)
) detail_basis ON true
LEFT JOIN LATERAL (
  SELECT
    (SELECT count(*) FROM public.school_student_settlement_adjustments a
     WHERE a.settlement_id = s.id AND a.status = 'posted') AS posted_adjustment_count,
    (SELECT count(*) FROM public.school_student_settlement_carryovers c
     WHERE c.source_settlement_id = s.id
       AND coalesce(c.status, 'active') = 'active') AS active_carryover_count,
    (SELECT count(DISTINCT w.id)
     FROM public.school_lesson_records l
     JOIN public.school_teacher_wage_lock_details d ON d.lesson_record_id = l.id
     JOIN public.school_teacher_wage_locks w ON w.id = d.lock_id
     WHERE l.app_type = 'school'
       AND l.lesson_type = 'actual'
       AND l.student_id = s.student_id
       AND l.year_month = s.year_month
       AND coalesce(w.status, '') <> 'void'
       AND w.voided_at IS NULL) AS active_wage_lock_count,
    ((SELECT count(*) FROM public.school_lesson_records l
      WHERE l.app_type = 'school'
        AND l.student_id = s.student_id
        AND l.year_month = s.year_month
        AND NOT (l.lesson_type = 'planned' AND l.voided_at IS NOT NULL))
     +
     (SELECT count(*) FROM public.school_income_records i
      WHERE i.app_type = 'school'
        AND i.student_id = s.student_id
        AND coalesce(i.settlement_month, i.year_month) = s.year_month
        AND i.income_category = 'tuition'
        AND i.status = 'received'
        AND coalesce(i.include_in_student_settlement, true) = true))
      AS live_relock_source_count
) blockers ON true
ORDER BY s.year_month, s.student_id, s.id;

SELECT
  count(*) AS locked_snapshot_count,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS locked_snapshot_uuid_md5,
  md5(string_agg(md5(to_jsonb(s)::text), ',' ORDER BY id::text))
    AS locked_snapshot_structure_set_md5
FROM public.school_student_monthly_settlements s
WHERE settlement_status = 'locked';

-- Compact financial-chain proof after inventory reads.
SELECT
  (SELECT count(*) FROM public.school_student_tuition_bills) AS tuition_bill_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
   FROM public.school_student_tuition_bills x) AS tuition_bill_md5,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
   FROM public.school_income_records x) AS income_md5,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons) AS bill_lesson_count,
  (SELECT md5(coalesce(string_agg(md5((to_jsonb(x) - ARRAY[
      'base_lesson_fee_jpy_snapshot',
      'aircon_rate_id_snapshot',
      'aircon_unit_price_jpy_snapshot',
      'aircon_billable_hours_snapshot',
      'aircon_fee_jpy_snapshot',
      'fee_calculation_version_snapshot',
      'lesson_venue_id_snapshot',
      'lesson_venue_code_snapshot'
    ])::text), '' ORDER BY x.id::text), ''))
   FROM public.school_student_tuition_bill_lessons x) AS bill_lesson_legacy_projection_md5,
  (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)
    AS historical_exclusion_count,
  (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))
   FROM public.school_student_tuition_historical_lesson_exclusions x)
    AS historical_exclusion_md5;

SELECT
  current_setting('transaction_isolation') AS final_isolation_level,
  current_setting('transaction_read_only') AS final_transaction_read_only,
  true AS ready_for_explicit_rollback;

ROLLBACK;
