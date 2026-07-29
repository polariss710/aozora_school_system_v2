-- School V2 tuition P0 R1D-D-B0-B planned/aircon business manifest.
-- Target: School PostgreSQL database only.
-- Boundary: read-only evidence freeze; no schema or business-row mutation.
-- Fixed venue mapping: Regus办公室 -> regus_office; Regus公共区/online excluded.
-- Aircon rule input: effective 2026-08-01, cap JPY 660/reporting hour.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT
  'transaction_and_database' AS check_name,
  current_database() AS database_name,
  current_setting('transaction_isolation') AS isolation_level,
  current_setting('transaction_read_only') AS read_only,
  transaction_timestamp() AS snapshot_at,
  to_regclass('public.school_lesson_records') IS NOT NULL AS lesson_table_exists,
  to_regclass('public.school_students') IS NOT NULL AS student_table_exists;

SELECT
  'r0_feature_gates_start' AS check_name,
  feature_key,
  state,
  CASE feature_key
    WHEN 'student_tuition_preview' THEN state = 'validation_preview_only'
    WHEN 'student_tuition_generate' THEN state = 'blocked'
    WHEN 'student_tuition_cash_submit' THEN state = 'blocked'
    ELSE false
  END AS expected_state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

SELECT
  'candidate_definition' AS check_name,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) AS definition_md5,
  md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) = '8981a2ce07abf8c28231bfaf05451368' AS expected_definition;

WITH lesson_counts AS (
  SELECT
    count(*) AS lesson_count,
    count(*) FILTER (WHERE lesson_type = 'planned') AS planned_count,
    count(*) FILTER (WHERE lesson_type = 'actual') AS actual_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND billing_month IS NOT NULL
        AND billing_week_start_date IS NOT NULL
        AND student_settlement_month IS NOT NULL
        AND billing_month_source IS NOT NULL
        AND billing_month_decided_at IS NOT NULL
    ) AS planned_complete_five_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND billing_month IS NULL
        AND billing_week_start_date IS NULL
        AND student_settlement_month IS NULL
        AND billing_month_source IS NULL
        AND billing_month_decided_at IS NULL
    ) AS planned_null_five_count,
    count(*) FILTER (
      WHERE lesson_type = 'planned'
        AND num_nonnulls(
          billing_month,
          billing_week_start_date,
          student_settlement_month,
          billing_month_source,
          billing_month_decided_at
        ) BETWEEN 1 AND 4
    ) AS planned_partial_five_count,
    count(*) FILTER (WHERE scheduled_lesson_date IS NOT NULL) AS scheduled_nonnull_count
  FROM public.school_lesson_records
)
SELECT
  'lesson_baseline' AS check_name,
  lesson_counts.*,
  planned_count = 397
    AND planned_complete_five_count = 118
    AND planned_null_five_count = 279
    AND planned_partial_five_count = 0
    AND scheduled_nonnull_count = 0 AS expected_stable_scope,
  planned_count - 397 AS planned_delta_from_b0_b_authority
FROM lesson_counts;

WITH requested_student(
  student_name,
  expected_student_id,
  aircon_unit_price_jpy,
  effective_from,
  effective_to
) AS (
  VALUES
    (
      '孙陈锋'::text,
      'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,
      330::integer,
      '2026-08-01'::date,
      NULL::date
    ),
    (
      '张倬闻'::text,
      '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
      0::integer,
      '2026-08-01'::date,
      NULL::date
    )
), matched_student AS (
  SELECT
    requested.student_name,
    requested.expected_student_id,
    requested.aircon_unit_price_jpy,
    requested.effective_from,
    requested.effective_to,
    student.id AS matched_student_id,
    student.status AS matched_status
  FROM requested_student requested
  LEFT JOIN public.school_students student
    ON student.name = requested.student_name
), resolved_student AS (
  SELECT
    student_name,
    expected_student_id,
    aircon_unit_price_jpy,
    effective_from,
    effective_to,
    count(matched_student_id) AS matched_count,
    CASE
      WHEN count(matched_student_id) = 1
      THEN min(matched_student_id::text)::uuid
      ELSE NULL::uuid
    END AS resolved_student_id,
    CASE
      WHEN count(matched_student_id) = 1
      THEN min(matched_status)
      ELSE NULL::text
    END AS resolved_status
  FROM matched_student
  GROUP BY
    student_name,
    expected_student_id,
    aircon_unit_price_jpy,
    effective_from,
    effective_to
), rate_hash AS (
  SELECT encode(
    sha256(convert_to(
      string_agg(
        concat_ws('|',
          expected_student_id::text,
          student_name,
          aircon_unit_price_jpy::text,
          effective_from::text,
          coalesce(effective_to::text, 'NULL')
        ),
        E'\n' ORDER BY expected_student_id::text
      ) || E'\n',
      'UTF8'
    )),
    'hex'
  ) AS student_rate_manifest_sha256
  FROM requested_student
)
SELECT
  'student_rate_manifest' AS check_name,
  resolved.student_name,
  resolved.expected_student_id,
  resolved.matched_count,
  resolved.resolved_student_id,
  resolved.resolved_status,
  resolved.aircon_unit_price_jpy,
  resolved.effective_from,
  resolved.effective_to,
  rate_hash.student_rate_manifest_sha256,
  resolved.matched_count = 1
    AND resolved.resolved_student_id = resolved.expected_student_id
    AND resolved.resolved_status = 'active'
    AND resolved.aircon_unit_price_jpy BETWEEN 0 AND 660
    AND rate_hash.student_rate_manifest_sha256 =
      'ed82a6c501121a825d0d279a43201a58d6d02f000a0a7273570335fc4e7ffe63'
    AS expected_student
FROM resolved_student resolved
CROSS JOIN rate_hash
ORDER BY resolved.expected_student_id::text;

WITH fixed_manifest(manifest_order, lesson_id) AS (
  VALUES
    (1, '23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid),
    (2, '637ba833-830f-42a6-81ed-47a6f9902523'::uuid),
    (3, '7175780c-b179-4f96-a42e-99ba11bdaed8'::uuid),
    (4, '80384c28-5044-4c56-94cd-5099aa852032'::uuid),
    (5, '920808f2-5629-4fcc-957c-6bdcee48808e'::uuid),
    (6, 'd06f136e-d4c5-44fb-ae5e-d87efa26bbfb'::uuid),
    (7, '3db3ad8b-44b6-4be7-a3ea-611362b82488'::uuid),
    (8, '6997acdc-fec4-4e14-a22b-d9f5291b1e0b'::uuid),
    (9, '69ecc019-9f8f-474e-8dc9-1dced16e41a6'::uuid),
    (10, '72ffebba-ecb3-4a96-9550-f02a5f64cf62'::uuid),
    (11, 'c0e9fd95-7833-44ef-a282-61611976b089'::uuid),
    (12, 'e6aaf546-bb9c-4e71-980e-40f78f2e1e11'::uuid),
    (13, '12d70ee9-8221-4b8e-a01c-61548340c42d'::uuid),
    (14, '1927b6ba-6ca6-4ef9-b1c0-0246067c7d41'::uuid),
    (15, '3920fdea-2f9d-4b17-abd0-f788b0d7d29e'::uuid),
    (16, '95dff1ab-544d-43be-bc0e-a95232f06935'::uuid),
    (17, 'a10744fc-173a-4b25-9bc3-99d6437797c5'::uuid),
    (18, 'a601916b-6add-4be6-adcc-5c232425f686'::uuid),
    (19, '286344d1-c603-4990-aba3-814996535319'::uuid),
    (20, '9a76aed4-058f-4801-90b5-b2637387fb3e'::uuid),
    (21, '9f755093-8f4d-4337-80ed-23d0e555c835'::uuid),
    (22, 'e2540bb3-5c1f-45bc-b964-9727a6ed3e48'::uuid),
    (23, 'ee6c1383-4259-44e0-923c-1ee6b8749820'::uuid),
    (24, 'ee86e691-2c96-48c2-ad57-512f9eef4b3c'::uuid),
    (25, '01490eb7-1bd7-430a-ba26-3ccc81d45796'::uuid),
    (26, '80e03531-5eaa-40e1-a435-0132dd62d5c0'::uuid),
    (27, '8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9'::uuid),
    (28, '9efe2def-ff59-467a-bb76-a49537ec8e0f'::uuid),
    (29, 'adc0b06c-eee3-40ca-8992-592f5d4b009b'::uuid),
    (30, 'dbe16731-803b-49db-8cc0-f826e911bb41'::uuid),
    (31, '15f8147e-5bb0-4cf9-9ba7-3e12f115774e'::uuid),
    (32, '224015ce-b435-4233-8113-0e6c712b1a18'::uuid),
    (33, '2bd402cb-fc4d-48cc-b166-400ee4945703'::uuid),
    (34, 'c1f5c7e9-70e4-4c2d-99c8-aadd986cda15'::uuid),
    (35, 'dadcf864-5343-403d-a111-e68b8617f413'::uuid),
    (36, 'f91ecdd8-7442-4879-97b6-67ad8ea99f23'::uuid),
    (37, '10b62cc8-dd74-4665-a6cd-02cc02924a65'::uuid),
    (38, '57948b80-89d9-45f2-a99f-3b92aed9f4e8'::uuid),
    (39, '68da4912-72a8-418c-b30b-335bb9896c63'::uuid),
    (40, 'a9de94c0-954b-452d-95b0-6a8b7d1a5a9e'::uuid),
    (41, 'c79e2ade-4026-4ab3-a316-ba26354abfe2'::uuid),
    (42, 'f693a3d9-fada-48f2-8203-bc33d46ee4dd'::uuid),
    (43, '5591fb92-2333-460c-95f3-85c6511d6fd4'::uuid),
    (44, '645cccaf-ae0f-41b3-84d1-e40882a8c85f'::uuid),
    (45, '82e81ecc-dd23-471e-8402-a45bd8b20eb1'::uuid),
    (46, 'bf38024e-2a5f-422c-ad41-01ec9922e701'::uuid),
    (47, 'dbd6f35a-b0ee-4af8-bcda-e065330f0413'::uuid),
    (48, 'fb066255-82b5-4eb1-9f76-a776c04becc2'::uuid),
    (49, '1eeb937e-a7ad-4e7c-955d-797b9d979882'::uuid),
    (50, '21e97cbd-3e18-4c9e-9790-981f885af03a'::uuid),
    (51, '371e41c5-a659-44a6-87e0-c3a85c9c1b75'::uuid),
    (52, '966119c6-09c8-4ac5-9c16-6cda13137d87'::uuid),
    (53, 'a9e861d3-6bd6-4b76-ba78-4cc1f3265b43'::uuid),
    (54, 'fd803263-07b6-4b1f-b668-43a482f21c89'::uuid),
    (55, '0386bf22-8619-41f2-be6c-5106b8c17cd0'::uuid),
    (56, '4254095b-9ec1-4651-a9ff-0dffb3a4520f'::uuid),
    (57, '7e833e2c-3bc0-4c6d-a1ab-204229f43a77'::uuid),
    (58, 'aea933f5-5e3b-4476-b1f0-d781d41312a3'::uuid),
    (59, 'b33f023c-4b0c-495e-8f0b-934ead526421'::uuid),
    (60, 'ff368fb5-94a8-4ea4-b3fc-d62ce499732b'::uuid),
    (61, '17e58b7d-3fb8-4874-8071-0b1f808e8430'::uuid),
    (62, '30271ef0-51ee-43ca-9103-1b5ec34255e1'::uuid),
    (63, 'a3a7dd70-1a1e-4078-bce8-d54f10fc57af'::uuid),
    (64, 'cfb5e237-51a3-48b2-a12e-e8f0628e2c51'::uuid),
    (65, 'd9d11e4b-a01c-4535-93cf-bc51cf08b900'::uuid),
    (66, 'eec50614-788d-429b-99a4-fc8938a86dda'::uuid),
    (67, '0ea530e7-12ac-41fa-9f6e-972b24662a72'::uuid),
    (68, '297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83'::uuid),
    (69, '3048b190-31e0-49b1-a255-ce73e6e15fc0'::uuid),
    (70, '70c31ae5-6083-46cb-90ad-fdc24726b6b6'::uuid),
    (71, '812979d0-43ac-4075-b38f-4c9aa455cd4b'::uuid),
    (72, 'd1961919-8c05-42e8-8a06-4ed1fabb13c0'::uuid),
    (73, '0a3a8c13-12cb-4430-a933-2941221c0c77'::uuid),
    (74, '4505777b-13e3-4187-9839-618ebe186f22'::uuid),
    (75, '895ebf6e-6bf0-419d-bf9a-418d048a42a7'::uuid),
    (76, '92a0f909-6458-4d34-9144-9d60eeede33f'::uuid),
    (77, 'c48478ef-8b3d-4c7f-bd48-cc99659e99f7'::uuid),
    (78, 'd8ed3671-6865-42b6-a4a2-06b31c9051e6'::uuid),
    (79, '0624fabe-a3c8-4930-aa41-8ed800a28eea'::uuid),
    (80, '3f5884ea-ca12-41dc-89ce-ebc67db27fe8'::uuid),
    (81, '89797ce3-58e0-4c9d-b107-79eca71e4161'::uuid),
    (82, 'a42b1b2e-4f55-4915-a20b-bd411b4d81a0'::uuid),
    (83, 'd2307a35-1f41-4402-ab4d-c03ed4305f50'::uuid),
    (84, 'fd34b0d7-86c2-4d0e-a519-de2317e0ab26'::uuid),
    (85, '207430a6-c9cd-4acb-9a7d-962c078b0623'::uuid),
    (86, '5666a624-05b5-4408-bc11-5d208851b216'::uuid),
    (87, 'a57bf7af-43e1-46ba-9bb6-9ee511b81e05'::uuid),
    (88, '73dd0453-aec2-4612-b710-071a372f88ad'::uuid),
    (89, 'bc718d5f-dc21-4e7d-914a-dd3a6debaeb6'::uuid),
    (90, 'f1a321d8-5528-4afe-8fb7-79204f49f3dc'::uuid),
    (91, '584ef4d6-fa9d-4dd8-803c-cab68ac67a67'::uuid),
    (92, 'a4cd05e7-47e7-4e0d-8af8-dad6c7505744'::uuid),
    (93, 'fc138193-f76a-476c-a394-b49d2e68dde2'::uuid),
    (94, '0f168663-afb1-49a7-90a8-39197ad7729e'::uuid),
    (95, '594a4559-c1b1-4ad1-88e6-4c7834052831'::uuid),
    (96, 'def65ad3-6f87-4889-802f-202550a9af49'::uuid),
    (97, '222c4ad5-b6fe-4e4e-b192-8db8c65b61fa'::uuid),
    (98, '6c70c4c1-1895-453d-b9b0-591e9f004f86'::uuid),
    (99, '89da310d-4f17-4a40-8315-659838aec59c'::uuid),
    (100, '9efb8862-e8c5-4f3d-9d55-b0be4317ad19'::uuid),
    (101, '37a2083e-bb28-45d1-802a-f98f4564887f'::uuid),
    (102, '63ca3a2b-7c2f-4eed-a997-71840357f8f6'::uuid),
    (103, 'a3ee5595-6dd5-4737-8605-ff5a8d7d0333'::uuid),
    (104, 'ea766c1d-f152-4b3f-9400-0d5b5aa64614'::uuid),
    (105, 'fcbf1be4-567b-4876-9cc6-19cd0d395da0'::uuid),
    (106, '1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8'::uuid),
    (107, '68bbce4e-f6bb-45c6-9798-ee72b6f75179'::uuid),
    (108, '9bdb88c1-9c08-4716-b146-e98cf149978b'::uuid),
    (109, 'fa7883c8-35e6-40bd-92d1-70adcdcce078'::uuid),
    (110, '1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9'::uuid),
    (111, '475853f0-2004-4375-ae72-013c5a86987c'::uuid),
    (112, '6e005bee-2d14-4722-8b76-9dbe7f836e12'::uuid),
    (113, 'cde683d3-06f2-46ec-8b8a-4f2ed4b4962e'::uuid),
    (114, 'e65b7d1d-45b2-4485-ae6d-7000fe92ce78'::uuid),
    (115, '02b9e85e-2e03-404d-93a6-9bfef3bf186d'::uuid),
    (116, '0d048cbf-a5f5-458c-88aa-ce0c3a1c667c'::uuid),
    (117, '196c9d86-500b-4687-a051-88dcc12fa2a9'::uuid),
    (118, 'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'::uuid)
), live_manifest AS (
  SELECT
    manifest.manifest_order,
    manifest.lesson_id AS manifest_lesson_id,
    lesson.*
  FROM fixed_manifest manifest
  LEFT JOIN public.school_lesson_records lesson
    ON lesson.id = manifest.lesson_id
), ordered_live AS (
  SELECT
    live.manifest_order,
    concat_ws('|',
      live.student_id::text,
      live.billing_month,
      live.billing_week_start_date::text,
      live.manifest_lesson_id::text
    ) AS current_sort_key,
    lag(concat_ws('|',
      live.student_id::text,
      live.billing_month,
      live.billing_week_start_date::text,
      live.manifest_lesson_id::text
    )) OVER (ORDER BY live.manifest_order) AS previous_sort_key
  FROM live_manifest live
), grouped_summary AS (
  SELECT
    live.student_id,
    live.billing_month,
    count(*) AS lesson_count,
    sum(live.duration_hours) AS duration_hours,
    sum(live.lesson_fee) AS lesson_fee_jpy
  FROM live_manifest live
  WHERE live.id IS NOT NULL
  GROUP BY live.student_id, live.billing_month
), manifest_hashes AS (
  SELECT
    md5(string_agg(
      live.manifest_lesson_id::text,
      ',' ORDER BY live.manifest_lesson_id::text
    )) AS uuid_set_md5,
    encode(sha256(convert_to(
      string_agg(
        concat_ws('|',
          coalesce(live.id::text, 'NULL'),
          coalesce(live.student_id::text, 'NULL'),
          coalesce(live.billing_month, 'NULL'),
          coalesce(live.billing_week_start_date::text, 'NULL'),
          coalesce(live.duration_hours::text, 'NULL'),
          coalesce(live.unit_price::text, 'NULL'),
          coalesce(live.lesson_fee::text, 'NULL'),
          coalesce(live.billing_month_source, 'NULL'),
          coalesce(
            to_char(
              live.billing_month_decided_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'NULL'
          )
        ),
        E'\n' ORDER BY
          live.student_id::text,
          live.billing_month,
          live.billing_week_start_date,
          live.manifest_lesson_id::text
      ) || E'\n',
      'UTF8'
    )), 'hex') AS business_manifest_sha256
  FROM live_manifest live
), invariant_counts AS (
  SELECT
    count(*) AS manifest_value_count,
    count(DISTINCT manifest_lesson_id) AS manifest_distinct_count,
    count(id) AS matched_count,
    count(*) FILTER (
      WHERE id IS NULL
    ) AS missing_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND (
          app_type IS DISTINCT FROM 'school'
          OR lesson_type IS DISTINCT FROM 'planned'
          OR status IS DISTINCT FROM 'planned'
          OR voided_at IS NOT NULL
          OR is_billable IS DISTINCT FROM true
          OR student_id NOT IN (
            '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
            'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
          )
          OR business_entity_id IS DISTINCT FROM
            '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
          OR billing_month IS NULL
          OR billing_week_start_date IS NULL
          OR student_settlement_month IS DISTINCT FROM billing_month
          OR billing_month_source NOT IN (
            'approved_r1c_a_manifest',
            'approved_r1c_c_b_manifest'
          )
          OR billing_month_decided_at IS NULL
          OR extract(isodow FROM billing_week_start_date) <> 1
          OR to_char(billing_week_start_date, 'YYYY-MM') <> billing_month
          OR lesson_date IS DISTINCT FROM billing_week_start_date
          OR scheduled_lesson_date IS NOT NULL
          OR lesson_delivery_mode IS NOT NULL
          OR lesson_venue IS NOT NULL
          OR teacher_id IS NULL
          OR subject_id IS NULL
          OR lesson_count IS NULL
          OR lesson_count <= 0
          OR duration_hours IS NULL
          OR duration_hours <= 0
          OR unit_price IS NULL
          OR unit_price <= 0
          OR lesson_fee IS NULL
          OR lesson_fee <= 0
          OR created_at IS NULL
          OR updated_at IS NULL
        )
    ) AS invalid_business_row_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_lesson_records actual
          WHERE actual.planned_lesson_id = live_manifest.id
        )
    ) AS has_actual_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_bill_lessons relation
          WHERE relation.planned_lesson_id = live_manifest.id
        )
    ) AS has_bill_relation_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_bills bill
          WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? live_manifest.id::text
        )
    ) AS has_bill_snapshot_count,
    count(*) FILTER (
      WHERE id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.school_student_tuition_historical_lesson_exclusions exclusion
          WHERE exclusion.planned_lesson_id = live_manifest.id
        )
    ) AS has_historical_exclusion_count,
    sum(duration_hours) FILTER (WHERE id IS NOT NULL) AS duration_hours,
    sum(lesson_fee) FILTER (WHERE id IS NOT NULL) AS lesson_fee_jpy
  FROM live_manifest
), non_manifest_complete AS (
  SELECT count(*) AS count_value
  FROM public.school_lesson_records lesson
  LEFT JOIN fixed_manifest manifest ON manifest.lesson_id = lesson.id
  WHERE lesson.lesson_type = 'planned'
    AND lesson.billing_month IS NOT NULL
    AND lesson.billing_week_start_date IS NOT NULL
    AND lesson.student_settlement_month IS NOT NULL
    AND lesson.billing_month_source IS NOT NULL
    AND lesson.billing_month_decided_at IS NOT NULL
    AND manifest.lesson_id IS NULL
), sort_errors AS (
  SELECT count(*) AS count_value
  FROM ordered_live
  WHERE previous_sort_key > current_sort_key
)
SELECT
  'fixed_118_manifest' AS check_name,
  invariants.manifest_value_count,
  invariants.manifest_distinct_count,
  invariants.matched_count,
  invariants.missing_count,
  invariants.invalid_business_row_count,
  invariants.has_actual_count,
  invariants.has_bill_relation_count,
  invariants.has_bill_snapshot_count,
  invariants.has_historical_exclusion_count,
  invariants.duration_hours,
  invariants.lesson_fee_jpy,
  hashes.uuid_set_md5,
  hashes.business_manifest_sha256,
  non_manifest_complete.count_value AS complete_rows_outside_manifest,
  sort_errors.count_value AS manifest_sort_errors,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'student_id', grouped.student_id,
        'billing_month', grouped.billing_month,
        'lesson_count', grouped.lesson_count,
        'duration_hours', grouped.duration_hours,
        'lesson_fee_jpy', grouped.lesson_fee_jpy
      ) ORDER BY grouped.student_id::text, grouped.billing_month
    )
    FROM grouped_summary grouped
  ) AS grouped_summary,
  invariants.manifest_value_count = 118
    AND invariants.manifest_distinct_count = 118
    AND invariants.matched_count = 118
    AND invariants.missing_count = 0
    AND invariants.invalid_business_row_count = 0
    AND invariants.has_actual_count = 0
    AND invariants.has_bill_relation_count = 0
    AND invariants.has_bill_snapshot_count = 0
    AND invariants.has_historical_exclusion_count = 0
    AND invariants.duration_hours = 254
    AND invariants.lesson_fee_jpy = 2474000
    AND hashes.uuid_set_md5 = '77f697f82e547d84dcabf88a3c868aa1'
    AND hashes.business_manifest_sha256 =
      'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
    AND non_manifest_complete.count_value = 0
    AND sort_errors.count_value = 0 AS all_expected
FROM invariant_counts invariants
CROSS JOIN manifest_hashes hashes
CROSS JOIN non_manifest_complete
CROSS JOIN sort_errors;

WITH eligible_candidate AS (
  SELECT lesson.id, lesson.student_id, lesson.billing_month,
         lesson.duration_hours, lesson.lesson_fee
  FROM public.school_lesson_records lesson
  WHERE lesson.app_type = 'school'
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.voided_at IS NULL
    AND lesson.is_billable IS true
    AND lesson.student_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND lesson.billing_month IS NOT NULL
    AND lesson.billing_week_start_date IS NOT NULL
    AND extract(isodow FROM lesson.billing_week_start_date) = 1
    AND to_char(lesson.billing_week_start_date, 'YYYY-MM') = lesson.billing_month
    AND lesson.student_settlement_month = lesson.billing_month
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest',
      'approved_r1c_c_b_manifest'
    )
    AND lesson.billing_month_decided_at IS NOT NULL
    AND lesson.lesson_date IS NOT NULL
    AND lesson.teacher_id IS NOT NULL
    AND lesson.subject_id IS NOT NULL
    AND lesson.lesson_count IS NOT NULL
    AND lesson.lesson_count > 0
    AND lesson.duration_hours > 0
    AND lesson.unit_price IS NOT NULL
    AND lesson.unit_price > 0
    AND lesson.lesson_fee IS NOT NULL
    AND lesson.lesson_fee > 0
    AND lesson.created_at IS NOT NULL
    AND lesson.updated_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id = lesson.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bills bill
      WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_historical_lesson_exclusions exclusion
      WHERE exclusion.planned_lesson_id = lesson.id
    )
)
SELECT
  'candidate_table_emulation' AS check_name,
  count(*) AS candidate_count,
  sum(duration_hours) AS candidate_duration_hours,
  sum(lesson_fee) AS candidate_fee_jpy,
  md5(string_agg(id::text, ',' ORDER BY id::text)) AS candidate_uuid_set_md5,
  count(*) = 118
    AND sum(duration_hours) = 254
    AND sum(lesson_fee) = 2474000
    AND md5(string_agg(id::text, ',' ORDER BY id::text)) =
      '77f697f82e547d84dcabf88a3c868aa1' AS all_expected
FROM eligible_candidate;

WITH legacy_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND lesson.billing_month IS NULL
    AND lesson.billing_week_start_date IS NULL
    AND lesson.student_settlement_month IS NULL
    AND lesson.billing_month_source IS NULL
    AND lesson.billing_month_decided_at IS NULL
), partial_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND num_nonnulls(
      lesson.billing_month,
      lesson.billing_week_start_date,
      lesson.student_settlement_month,
      lesson.billing_month_source,
      lesson.billing_month_decided_at
    ) BETWEEN 1 AND 4
)
SELECT
  'legacy_279_boundary' AS check_name,
  (SELECT count(*) FROM legacy_scope) AS legacy_count,
  (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM legacy_scope)
    AS legacy_uuid_set_md5,
  (SELECT count(*) FROM partial_scope) AS partial_count,
  (SELECT count(*) FROM legacy_scope) = 279
    AND (SELECT md5(string_agg(id::text, ',' ORDER BY id::text)) FROM legacy_scope) =
      '0975fdc91b533680e5ccc909f076ac62'
    AND (SELECT count(*) FROM partial_scope) = 0 AS all_expected;

-- B0-B-E correction: distinguish the fixed historical six from the dynamic
-- whole-School pending_makeup snapshot. The global count/hash is evidence at
-- this snapshot only and is deliberately not a future hard-stop assertion.
WITH fixed_six(lesson_id) AS (
  VALUES
    ('9085ab09-a719-42b7-a517-2700b8d9ddb0'::uuid),
    ('e5eb7a47-13ea-4858-b73a-ddf5cc38c0f7'::uuid),
    ('2b49f20c-4c94-4129-abca-bd12a75c5026'::uuid),
    ('44ddcda2-dbdd-48c2-8d0a-ba59a5e65a90'::uuid),
    ('4da7e3e9-d36c-4102-b582-c67b281b5b69'::uuid),
    ('98a0f192-6e6f-4f6a-9cfc-bd2570d308fd'::uuid)
), approved_six_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND lesson.status = 'pending_makeup'
    AND lesson.student_id IN (
      '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
      'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
    )
    AND lesson.year_month IN ('2026-05', '2026-06')
), global_pending_scope AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.lesson_type = 'planned'
    AND lesson.status = 'pending_makeup'
), scope_rows(scope_name, lesson_id) AS (
  SELECT 'approved_historical_six'::text, id FROM approved_six_scope
  UNION ALL
  SELECT 'global_pending_makeup_snapshot'::text, id FROM global_pending_scope
), per_lesson_evidence AS (
  SELECT
    scope.scope_name,
    lesson.*,
    to_jsonb(lesson) AS lesson_row_json,
    coalesce(actual_link.actual_count, 0) AS linked_actual_count,
    coalesce(relation_evidence.relation_count, 0) AS bill_relation_count,
    coalesce(snapshot_evidence.snapshot_bill_count, 0) AS bill_snapshot_count,
    coalesce(exclusion_evidence.exclusion_count, 0) AS historical_exclusion_count
  FROM scope_rows scope
  JOIN public.school_lesson_records lesson ON lesson.id = scope.lesson_id
  LEFT JOIN LATERAL (
    SELECT count(*) AS actual_count
    FROM public.school_lesson_records actual
    WHERE actual.planned_lesson_id = lesson.id
  ) actual_link ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS relation_count
    FROM public.school_student_tuition_bill_lessons relation
    WHERE relation.planned_lesson_id = lesson.id
  ) relation_evidence ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS snapshot_bill_count
    FROM public.school_student_tuition_bills bill
    WHERE (bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
  ) snapshot_evidence ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS exclusion_count
    FROM public.school_student_tuition_historical_lesson_exclusions exclusion
    WHERE exclusion.planned_lesson_id = lesson.id
  ) exclusion_evidence ON true
), scope_summary AS (
  SELECT
    evidence.scope_name,
    count(*) AS row_count,
    count(DISTINCT evidence.id) AS distinct_primary_key_count,
    md5(string_agg(evidence.id::text, ',' ORDER BY evidence.id::text))
      AS uuid_set_md5,
    md5(string_agg(
      md5(evidence.lesson_row_json::text),
      '' ORDER BY evidence.id::text
    )) AS full_row_aggregate_md5,
    count(*) FILTER (
      WHERE evidence.lesson_type = 'planned'
        AND evidence.status = 'pending_makeup'
    ) AS exact_type_status_count,
    sum(evidence.linked_actual_count) AS linked_actual_row_count,
    count(*) FILTER (WHERE evidence.linked_actual_count > 0)
      AS linked_distinct_planned_count,
    count(*) FILTER (WHERE evidence.linked_actual_count > 1)
      AS duplicate_actual_link_source_count,
    count(*) FILTER (
      WHERE num_nonnulls(
        evidence.billing_month,
        evidence.billing_week_start_date,
        evidence.student_settlement_month,
        evidence.billing_month_source,
        evidence.billing_month_decided_at
      ) = 0
    ) AS inside_legacy_279_count,
    count(*) FILTER (
      WHERE evidence.billing_month IS NOT NULL
        AND evidence.billing_week_start_date IS NOT NULL
        AND evidence.student_settlement_month IS NOT NULL
        AND evidence.billing_month_source IS NOT NULL
        AND evidence.billing_month_decided_at IS NOT NULL
    ) AS inside_future_118_count,
    count(*) FILTER (WHERE evidence.bill_relation_count > 0)
      AS bill_relation_lesson_count,
    count(*) FILTER (WHERE evidence.bill_snapshot_count > 0)
      AS bill_snapshot_lesson_count,
    count(*) FILTER (WHERE evidence.historical_exclusion_count > 0)
      AS historical_exclusion_lesson_count
  FROM per_lesson_evidence evidence
  GROUP BY evidence.scope_name
), set_relationship AS (
  SELECT
    (SELECT count(*)
     FROM approved_six_scope six
     JOIN global_pending_scope global_scope ON global_scope.id = six.id)
      AS intersection_count,
    (SELECT count(*)
     FROM approved_six_scope six
     LEFT JOIN global_pending_scope global_scope ON global_scope.id = six.id
     WHERE global_scope.id IS NULL) AS six_only_count,
    (SELECT count(*)
     FROM global_pending_scope global_scope
     LEFT JOIN approved_six_scope six ON six.id = global_scope.id
     WHERE six.id IS NULL) AS global_only_count,
    (SELECT count(*)
     FROM fixed_six fixed
     FULL JOIN approved_six_scope six ON six.id = fixed.lesson_id
     WHERE fixed.lesson_id IS NULL OR six.id IS NULL)
      AS fixed_six_set_mismatch_count
)
SELECT
  'pending_makeup_scope_correction' AS check_name,
  summary.scope_name,
  'public.school_lesson_records'::text AS object_table,
  'planned lesson row'::text AS object_type,
  CASE summary.scope_name
    WHEN 'approved_historical_six' THEN
      'lesson_type=planned,status=pending_makeup,two fixed students,year_month in 2026-05/06'
    ELSE 'lesson_type=planned,status=pending_makeup,whole School snapshot'
  END AS filter_definition,
  summary.row_count,
  summary.distinct_primary_key_count,
  summary.uuid_set_md5,
  summary.full_row_aggregate_md5,
  summary.exact_type_status_count,
  summary.linked_actual_row_count,
  summary.linked_distinct_planned_count,
  summary.duplicate_actual_link_source_count,
  summary.inside_legacy_279_count,
  summary.inside_future_118_count,
  summary.bill_relation_lesson_count,
  summary.bill_snapshot_lesson_count,
  summary.historical_exclusion_lesson_count,
  relationship.intersection_count,
  relationship.six_only_count,
  relationship.global_only_count,
  relationship.fixed_six_set_mismatch_count,
  true AS same_object_type,
  true AS directly_comparable,
  summary.scope_name = 'global_pending_makeup_snapshot' AS dynamic_snapshot_only,
  summary.row_count = summary.distinct_primary_key_count
    AND summary.exact_type_status_count = summary.row_count
    AS scope_definition_consistent,
  CASE summary.scope_name
    WHEN 'approved_historical_six' THEN
      summary.row_count = 6
      AND relationship.fixed_six_set_mismatch_count = 0
      AND relationship.intersection_count = 6
      AND relationship.six_only_count = 0
    ELSE
      relationship.intersection_count = 6
      AND relationship.six_only_count = 0
      AND relationship.global_only_count = summary.row_count - 6
  END AS set_relationship_consistent
FROM scope_summary summary
CROSS JOIN set_relationship relationship
ORDER BY summary.scope_name;

WITH expected_lesson(lesson_id, lesson_date, expected_venue) AS (
  VALUES
    (
      '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid,
      '2026-08-01'::date,
      'Regus办公室'::text
    ),
    (
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'::uuid,
      '2026-08-02'::date,
      NULL::text
    )
), checked AS (
  SELECT
    expected.lesson_id,
    lesson.id AS matched_lesson_id,
    lesson.lesson_date,
    lesson.lesson_venue,
    lesson.duration_hours,
    lesson.unit_price,
    lesson.lesson_fee,
    relation.id AS relation_id,
    relation.relation_role,
    relation.tuition_bill_id,
    bill.billing_month,
    bill.status AS bill_status,
    expected.lesson_date AS expected_lesson_date,
    expected.expected_venue
  FROM expected_lesson expected
  LEFT JOIN public.school_lesson_records lesson ON lesson.id = expected.lesson_id
  LEFT JOIN public.school_student_tuition_bill_lessons relation
    ON relation.planned_lesson_id = expected.lesson_id
   AND relation.tuition_bill_id = '2a9f1c25-a060-461e-ae10-b02295dec381'::uuid
   AND relation.relation_role = 'canonical_charge'
  LEFT JOIN public.school_student_tuition_bills bill
    ON bill.id = relation.tuition_bill_id
)
SELECT
  'historical_sun_cross_month_exclusions' AS check_name,
  count(*) AS expected_rows,
  count(matched_lesson_id) AS matched_lessons,
  count(relation_id) AS canonical_relations,
  count(*) FILTER (
    WHERE lesson_date = expected_lesson_date
      AND lesson_venue IS NOT DISTINCT FROM expected_venue
      AND duration_hours = 2
      AND unit_price = 8500
      AND lesson_fee = 17000
      AND billing_month = '2026-07'
      AND bill_status = 'income_created'
  ) AS exact_fact_rows,
  count(*) = 2
    AND count(matched_lesson_id) = 2
    AND count(relation_id) = 2
    AND count(*) FILTER (
      WHERE lesson_date = expected_lesson_date
        AND lesson_venue IS NOT DISTINCT FROM expected_venue
        AND duration_hours = 2
        AND unit_price = 8500
        AND lesson_fee = 17000
        AND billing_month = '2026-07'
        AND bill_status = 'income_created'
    ) = 2 AS all_expected
FROM checked;

SELECT
  'historical_chen_jiaen_august_exclusion' AS check_name,
  bill.id AS bill_id,
  bill.student_id,
  bill.billing_month,
  bill.planned_lesson_count,
  bill.planned_lesson_hours,
  bill.planned_lesson_fee_jpy,
  bill.bill_amount_jpy,
  bill.status,
  count(relation.id) AS canonical_relation_count,
  bill.id = '1b546782-1b39-4c73-a85d-27ab1e5086ad'::uuid
    AND bill.student_id = '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid
    AND bill.billing_month = '2026-08'
    AND bill.planned_lesson_count = 12
    AND bill.planned_lesson_hours = 24
    AND bill.planned_lesson_fee_jpy = 216000
    AND bill.bill_amount_jpy = 216000
    AND bill.status = 'income_created'
    AND count(relation.id) = 12 AS all_expected
FROM public.school_student_tuition_bills bill
LEFT JOIN public.school_student_tuition_bill_lessons relation
  ON relation.tuition_bill_id = bill.id
 AND relation.relation_role = 'canonical_charge'
WHERE bill.id = '1b546782-1b39-4c73-a85d-27ab1e5086ad'::uuid
GROUP BY bill.id;

WITH sun_september_planned AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
    AND lesson.lesson_type = 'planned'
    AND (
      lesson.billing_month = '2026-09'
      OR lesson.year_month = '2026-09'
    )
), sun_september_candidate AS (
  SELECT lesson.id
  FROM public.school_lesson_records lesson
  WHERE lesson.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
    AND lesson.lesson_type = 'planned'
    AND lesson.status = 'planned'
    AND lesson.billing_month = '2026-09'
    AND lesson.business_entity_id IS NOT NULL
    AND lesson.billing_week_start_date IS NOT NULL
    AND extract(isodow FROM lesson.billing_week_start_date) = 1
    AND to_char(lesson.billing_week_start_date, 'YYYY-MM') = '2026-09'
    AND lesson.student_settlement_month = '2026-09'
    AND lesson.billing_month_source IN (
      'approved_r1c_a_manifest',
      'approved_r1c_c_b_manifest'
    )
    AND lesson.billing_month_decided_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_bill_lessons relation
      WHERE relation.planned_lesson_id = lesson.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.school_student_tuition_historical_lesson_exclusions exclusion
      WHERE exclusion.planned_lesson_id = lesson.id
    )
), sun_september_bill AS (
  SELECT bill.id
  FROM public.school_student_tuition_bills bill
  WHERE bill.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
    AND bill.billing_month = '2026-09'
    AND bill.status IN ('draft', 'income_created')
)
SELECT
  'sun_chenfeng_2026_09_missing_fact' AS check_name,
  (SELECT count(*) FROM sun_september_planned) AS planned_count,
  (SELECT count(*) FROM sun_september_candidate) AS candidate_count,
  (SELECT count(*) FROM sun_september_bill) AS active_bill_count,
  (SELECT count(*) FROM sun_september_planned) = 0
    AND (SELECT count(*) FROM sun_september_candidate) = 0
    AND (SELECT count(*) FROM sun_september_bill) = 0 AS all_expected;

SELECT
  'r0_feature_gates_end' AS check_name,
  count(*) AS matched_gate_count,
  count(*) = 3 AS all_expected
FROM public.school_feature_gates
WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
   OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
   OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked');

SELECT
  'final_read_only_state' AS check_name,
  current_setting('transaction_read_only') AS read_only,
  count(*) FILTER (WHERE lesson_type = 'planned') AS planned_count,
  count(*) FILTER (WHERE lesson_type = 'actual') AS actual_count,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND billing_month IS NOT NULL
      AND billing_week_start_date IS NOT NULL
      AND student_settlement_month IS NOT NULL
      AND billing_month_source IS NOT NULL
      AND billing_month_decided_at IS NOT NULL
  ) AS planned_complete_five_count,
  count(*) FILTER (
    WHERE lesson_type = 'planned'
      AND billing_month IS NULL
      AND billing_week_start_date IS NULL
      AND student_settlement_month IS NULL
      AND billing_month_source IS NULL
      AND billing_month_decided_at IS NULL
  ) AS planned_null_five_count,
  count(*) FILTER (WHERE scheduled_lesson_date IS NOT NULL) AS scheduled_nonnull_count
FROM public.school_lesson_records;

ROLLBACK;
