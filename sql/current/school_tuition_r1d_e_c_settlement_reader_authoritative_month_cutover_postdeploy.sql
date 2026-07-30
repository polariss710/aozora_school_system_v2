-- School V2 tuition P0 R1D-E-C postdeploy read-only acceptance.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_c_postdeploy_existing_tx}
  \echo 'R1D_E_C_POSTDEPLOY_USING_CALLER_TRANSACTION'
\else
  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
\endif
SET LOCAL statement_timeout='300s';

DO $postdeploy$
DECLARE
  v_reader_count bigint;
  v_reader_hash text;
  v_writer_count bigint;
  v_writer_hash text;
  v_manifest record;
BEGIN
  IF public.school_r1d_e_c_settlement_reader_cutover_version()<>
       'r1d_e_c_settlement_reader_v1'
     OR to_regprocedure(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)') IS NULL
     OR to_regprocedure(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)') IS NULL
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure)
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure) THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_OBJECT_OR_SECURITY_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'school_r1d_e_c_settlement_reader_cutover_version',
      'school_resolve_r1d_e_c_lesson_student_month',
      'school_list_r1d_e_c_student_month_lessons')
      AND (has_function_privilege('anon',p.oid,'EXECUTE')
        OR has_function_privilege('authenticated',p.oid,'EXECUTE')
        OR has_function_privilege('service_role',p.oid,'EXECUTE')
        OR EXISTS (
          SELECT 1
          FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) privilege
          WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE'))
  ) THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_INTERNAL_ACL_FAILED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_get_student_monthly_settlement_summary',
      'school_get_student_monthly_settlement_preview',
      'school_get_student_monthly_settlement_wage_blockers',
      'school_assert_student_monthly_settlement_no_wage_blocker',
      'school_lock_student_monthly_settlement',
      'school_unlock_student_monthly_settlement',
      'school_relock_student_monthly_settlement',
      'school_set_student_monthly_settlement_draft_adjustment']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),
      E'\n' ORDER BY signature)) INTO v_reader_count,v_reader_hash
    FROM functions;

  IF v_reader_count<>8 OR v_reader_hash<>'b3818fc1119b5b2c1069d78164760e95'
     OR EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
         'school_get_student_monthly_settlement_summary',
         'school_get_student_monthly_settlement_preview',
         'school_get_student_monthly_settlement_wage_blockers',
         'school_assert_student_monthly_settlement_no_wage_blocker',
         'school_lock_student_monthly_settlement',
         'school_unlock_student_monthly_settlement',
         'school_relock_student_monthly_settlement',
         'school_set_student_monthly_settlement_draft_adjustment']::text[])
         AND coalesce(p.proacl::text,'')<>
           '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     ) THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_READER_CONTRACT_OR_ACL_FAILED';
  END IF;

  IF position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure))=0
     OR position('school_get_student_monthly_settlement_summary' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_preview(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_wage_blockers(text,uuid)'::regprocedure))=0
     OR position('school_get_student_monthly_settlement_wage_blockers' IN pg_get_functiondef(
       'public.school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure))=0
     OR position('school_assert_student_monthly_settlement_no_wage_blocker' IN
       pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE' IN
       pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_EIGHT_FUNCTION_COVERAGE_FAILED';
  END IF;

  IF position('l.year_month = p_year_month' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure))>0
     OR position('l.year_month = p_year_month' IN pg_get_functiondef(
       'public.school_get_student_monthly_settlement_wage_blockers(text,uuid)'::regprocedure))>0
     OR position('coalesce(student_settlement_month, year_month)' IN lower(
       pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)))>0 THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_LEGACY_FALLBACK_FOUND';
  END IF;

  PERFORM count(*)
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL);
  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE app_type='school' AND (student_id IS NULL
        OR lesson_type NOT IN ('planned','actual')))<>0 THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_UNTARGETABLE_SCHOOL_LESSON_FOUND';
  END IF;

  SELECT min(cutover_actual_count) AS actual_count,
    min(cutover_actual_uuid_md5) AS uuid_md5,
    min(cutover_identity_manifest_sha256) AS identity_sha,
    min(cutover_full_row_manifest_sha256) AS full_row_sha,
    count(DISTINCT cutover_actual_count) AS count_versions,
    count(DISTINCT cutover_actual_uuid_md5) AS uuid_versions,
    count(DISTINCT cutover_identity_manifest_sha256) AS identity_versions,
    count(DISTINCT cutover_full_row_manifest_sha256) AS full_row_versions
  INTO v_manifest FROM public.school_legacy_actual_settlement_evidence;
  IF v_manifest.actual_count<>234
     OR v_manifest.uuid_md5<>'891eeabf9a48d1c7b00a695b21cf8e95'
     OR v_manifest.identity_sha<>
       '83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c'
     OR v_manifest.full_row_sha<>
       'dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8'
     OR v_manifest.count_versions<>1 OR v_manifest.uuid_versions<>1
     OR v_manifest.identity_versions<>1 OR v_manifest.full_row_versions<>1
     OR EXISTS (
       SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
       JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
       WHERE a.student_settlement_month IS NOT NULL
          OR e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)
          OR e.actual_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
            a.id::text,a.planned_lesson_id::text,a.student_id::text,
            a.business_entity_id::text,coalesce(a.teacher_id::text,'<NULL>'),
            coalesce(a.subject_id::text,'<NULL>'),a.year_month,
            coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM')),
            a.lesson_date::text,a.lesson_type,a.app_type))
     ) THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_ACTUAL_EVIDENCE_CHANGED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_create_actual_lesson_from_planned',
      'school_create_cancelled_actual_lesson_from_planned',
      'school_create_partial_completed_actual_from_planned',
      'school_create_lesson_credit_makeup_actual',
      'school_create_makeup_completed_actual_lesson_from_planned',
      'school_create_cross_month_makeup_completed_actual_from_planned',
      'school_update_lesson_record_guarded',
      'school_update_lesson_record_guarded_with_venue']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),
      E'\n' ORDER BY signature)) INTO v_writer_count,v_writer_hash
    FROM functions;
  IF v_writer_count<>8 OR v_writer_hash<>'046cb8c0002528634b767a046e4626ab'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))<>
       '4a163f6691c779531a65a10be0f4422e' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_WRITER_CHANGED';
  END IF;

  IF public.school_r1d_f1_planned_attribution_cutover_version()<>
       'r1d_f1_planned_attribution_v1'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned' AND billing_month_source IN (
           'approved_r1c_a_manifest','approved_r1c_c_b_manifest'))<>118
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned' AND num_nonnulls(billing_month,
           billing_week_start_date,student_settlement_month,
           billing_month_source,billing_month_decided_at)=0)<>279
     OR (SELECT md5(string_agg(id::text,',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE lesson_type='planned' AND num_nonnulls(billing_month,
           billing_week_start_date,student_settlement_month,
           billing_month_source,billing_month_decided_at)=0)<>
           '0975fdc91b533680e5ccc909f076ac62'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned' AND num_nonnulls(billing_month,
           billing_week_start_date,student_settlement_month,
           billing_month_source,billing_month_decided_at) BETWEEN 1 AND 4)<>0
     OR (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',
           planned_lesson_id::text,coalesce(student_id_snapshot::text,'<NULL>'),
           coalesce(business_entity_id_snapshot::text,'<NULL>'),
           legacy_student_settlement_month,'planned','school'),E'\n'
           ORDER BY planned_lesson_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_planned_settlement_evidence)<>
           '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR (SELECT count(*)
         FROM public.school_legacy_settlement_snapshot_basis_evidence)<>15
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',
           settlement_snapshot_id::text,student_id_snapshot::text,
           business_entity_id_snapshot::text,settlement_month_snapshot,
           settlement_status_snapshot,lesson_count::text,
           planned_lesson_count::text,actual_lesson_count::text,
           lesson_uuid_md5,amount_basis_md5,settlement_structure_md5),E'\n'
           ORDER BY settlement_snapshot_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_settlement_snapshot_basis_evidence)<>
           '68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_PLANNED_OR_EVIDENCE_CHANGED';
  END IF;

  RAISE NOTICE 'R1D_E_C_POSTDEPLOY_READER_GROUP_MD5=%',v_reader_hash;
  RAISE NOTICE 'R1D_E_C_POSTDEPLOY_WRITER_GROUP_MD5=%',v_writer_hash;
END
$postdeploy$;

DO $protected_boundaries$
DECLARE
  v_candidate_count bigint;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_candidate_md5 text;
  v_candidate_sha text;
BEGIN
  WITH candidate AS (
    SELECT l.id,l.student_id,l.billing_month,l.billing_week_start_date,
      l.duration_hours,l.unit_price,l.lesson_fee,l.billing_month_source,
      l.billing_month_decided_at
    FROM public.school_lesson_records l
    WHERE l.app_type='school' AND l.lesson_type='planned' AND l.status='planned'
      AND l.voided_at IS NULL AND l.is_billable IS true
      AND l.student_id IS NOT NULL AND l.business_entity_id IS NOT NULL
      AND l.billing_month IS NOT NULL AND l.billing_week_start_date IS NOT NULL
      AND extract(isodow FROM l.billing_week_start_date)=1
      AND to_char(l.billing_week_start_date,'YYYY-MM')=l.billing_month
      AND l.student_settlement_month=l.billing_month
      AND l.billing_month_source IN (
        'approved_r1c_a_manifest','approved_r1c_c_b_manifest')
      AND l.billing_month_decided_at IS NOT NULL AND l.lesson_date IS NOT NULL
      AND l.teacher_id IS NOT NULL AND l.subject_id IS NOT NULL
      AND l.lesson_count>0 AND l.duration_hours>0 AND l.unit_price>0
      AND l.lesson_fee>0 AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
                      WHERE r.planned_lesson_id=l.id)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                      WHERE (b.source_snapshot->'planned_lesson_ids') ? l.id::text)
      AND NOT EXISTS (
        SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
        WHERE e.planned_lesson_id=l.id)
  ) SELECT count(*),sum(duration_hours),sum(lesson_fee),
    md5(string_agg(id::text,',' ORDER BY id::text)),
    encode(sha256(convert_to(string_agg(concat_ws('|',id::text,
      student_id::text,billing_month,billing_week_start_date::text,
      duration_hours::text,unit_price::text,lesson_fee::text,
      billing_month_source,to_char(billing_month_decided_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),E'\n'
      ORDER BY student_id::text,billing_month,billing_week_start_date,id::text)
      ||E'\n','UTF8')),'hex')
  INTO v_candidate_count,v_candidate_hours,v_candidate_fee,
    v_candidate_md5,v_candidate_sha FROM candidate;

  IF v_candidate_count<>118 OR v_candidate_hours<>254
     OR v_candidate_fee<>2474000
     OR v_candidate_md5<>'77f697f82e547d84dcabf88a3c868aa1'
     OR v_candidate_sha<>
       'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure))<>
       '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_CANDIDATE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records a
      JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
      WHERE a.app_type='school' AND a.lesson_type='actual'
        AND a.duration_hours>p.duration_hours)<>19
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(student_duration_overage_minutes,
           student_duration_overage_fee_jpy,student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at)>0)<>0
     OR (SELECT count(*) FROM public.school_lesson_records actual
         JOIN public.school_lesson_records planned
           ON planned.id=actual.planned_lesson_id
         WHERE actual.app_type='school' AND actual.lesson_type='actual'
           AND actual.status='makeup_completed'
           AND actual.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND actual.year_month IS DISTINCT FROM planned.year_month)<>8
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(actual)::text),''
           ORDER BY actual.id::text),''))
         FROM public.school_lesson_records actual
         JOIN public.school_lesson_records planned
           ON planned.id=actual.planned_lesson_id
         WHERE actual.app_type='school' AND actual.lesson_type='actual'
           AND actual.status='makeup_completed'
           AND actual.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND actual.year_month IS DISTINCT FROM planned.year_month)<>
           '18a32469745dfcfe5535b5920df41cfd'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(base_lesson_fee_jpy,lesson_venue_id,
           aircon_charge_status,aircon_rate_id,aircon_unit_price_jpy_snapshot,
           aircon_billable_hours_snapshot,aircon_fee_jpy,aircon_calculated_at,
           fee_calculation_version,fee_block_reason_code,
           fee_components_frozen_at)>0)<>0
     OR (SELECT count(*) FROM public.school_lesson_venues)
       +(SELECT count(*) FROM public.school_student_aircon_rates)
       +(SELECT count(*) FROM public.school_planned_writer_commands)
       +(SELECT count(*) FROM public.school_venue_rate_change_audit)<>0 THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_OVERAGE_MAKEUP_AIRCON_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR (SELECT count(*) FROM public.school_student_tuition_bills)<>9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
           ORDER BY x.id::text),''))
         FROM public.school_student_tuition_bills x)<>
           '0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
           ORDER BY x.id::text),''))
         FROM public.school_income_records x)<>
           '2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)<>121
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(x)-ARRAY[
          'base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot'])::text),''
          ORDER BY x.id::text),''))
         FROM public.school_student_tuition_bill_lessons x)<>
           '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*)
         FROM public.school_student_tuition_historical_lesson_exclusions)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
           ORDER BY x.id::text),''))
         FROM public.school_student_tuition_historical_lesson_exclusions x)<>
           '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_R0_OR_FINANCIAL_CHAIN_CHANGED';
  END IF;
END
$protected_boundaries$;

DO $reader_baseline$
DECLARE
  v_scope_count bigint;
  v_scope_sha text;
  v_locked_count bigint;
  v_locked_mismatch bigint;
  v_locked_reader_sha text;
BEGIN
  WITH candidate AS (
    SELECT l.* FROM public.school_lesson_records l
    WHERE l.app_type='school' AND l.lesson_type='planned' AND l.status='planned'
      AND l.voided_at IS NULL AND l.is_billable IS true
      AND l.student_id IS NOT NULL AND l.business_entity_id IS NOT NULL
      AND l.billing_month IS NOT NULL AND l.billing_week_start_date IS NOT NULL
      AND extract(isodow FROM l.billing_week_start_date)=1
      AND to_char(l.billing_week_start_date,'YYYY-MM')=l.billing_month
      AND l.student_settlement_month=l.billing_month
      AND l.billing_month_source IN (
        'approved_r1c_a_manifest','approved_r1c_c_b_manifest')
      AND l.billing_month_decided_at IS NOT NULL AND l.lesson_date IS NOT NULL
      AND l.teacher_id IS NOT NULL AND l.subject_id IS NOT NULL
      AND l.lesson_count>0 AND l.duration_hours>0 AND l.unit_price>0
      AND l.lesson_fee>0 AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
                      WHERE r.planned_lesson_id=l.id)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                      WHERE (b.source_snapshot->'planned_lesson_ids') ? l.id::text)
      AND NOT EXISTS (
        SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
        WHERE e.planned_lesson_id=l.id)
  ), scopes AS (
    SELECT student_id,business_entity_id,year_month,
      string_agg(DISTINCT source,',' ORDER BY source) AS scope_source,
      string_agg(DISTINCT settlement_status,',' ORDER BY settlement_status)
        FILTER (WHERE settlement_status IS NOT NULL) AS settlement_status
    FROM (
      SELECT m.student_id,m.business_entity_id,m.year_month,
        'settlement'::text AS source,m.settlement_status
      FROM public.school_student_monthly_settlements m
      UNION ALL
      SELECT c.student_id,c.business_entity_id,c.billing_month,
        'candidate'::text,NULL::text FROM candidate c
    ) scope_rows GROUP BY student_id,business_entity_id,year_month
  ), baseline AS (
    SELECT sc.*,
      (SELECT count(*)
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) resolved
       JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
       WHERE l.business_entity_id IS NOT DISTINCT FROM sc.business_entity_id
         AND NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL))
        AS lesson_count,
      (SELECT md5(string_agg(l.id::text,',' ORDER BY l.id::text))
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) resolved
       JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
       WHERE l.business_entity_id IS NOT DISTINCT FROM sc.business_entity_id
         AND NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL))
        AS lesson_uuid_md5,
      encode(sha256(convert_to(to_jsonb(sm)::text,'UTF8')),'hex')
        AS summary_sha256,
      encode(sha256(convert_to(to_jsonb(pv)::text,'UTF8')),'hex')
        AS preview_sha256,
      encode(sha256(convert_to(coalesce((SELECT jsonb_agg(to_jsonb(w)
        ORDER BY w.student_id,w.year_month)::text
        FROM public.school_get_student_monthly_settlement_wage_blockers(
          sc.year_month,sc.student_id) w),'[]'),'UTF8')),'hex')
        AS blocker_sha256
    FROM scopes sc
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_summary(
      sc.student_id,sc.year_month) sm
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_preview(
      sc.student_id,sc.year_month) pv
  )
  SELECT count(*),encode(sha256(convert_to(string_agg(concat_ws('|',
    student_id::text,coalesce(business_entity_id::text,'<NULL>'),year_month,
    scope_source,coalesce(settlement_status,'<NULL>'),lesson_count::text,
    coalesce(lesson_uuid_md5,'<NULL>'),summary_sha256,preview_sha256,
    blocker_sha256),E'\n' ORDER BY student_id::text,
    coalesce(business_entity_id::text,'<NULL>'),year_month)||E'\n','UTF8')),'hex')
  INTO v_scope_count,v_scope_sha FROM baseline;

  IF v_scope_count<>20 OR v_scope_sha<>
       'e7280307cafec31ce1f50c1c9ced7b4cc562e7f387fd6951ec2ad05c73d81d71' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_READER_BASELINE_CHANGED: %/%',
      v_scope_count,v_scope_sha;
  END IF;

  WITH locked_current AS (
    SELECT m.id,m.student_id,m.business_entity_id,m.year_month,
      m.settlement_status,
      md5(concat_ws('|',m.preset_exchange_rate::text,
        m.planned_lesson_fee_jpy::text,m.planned_lesson_fee_cny::text,
        m.actual_lesson_fee_jpy::text,m.actual_lesson_fee_cny::text,
        m.previous_balance_cny::text,m.received_jpy::text,m.received_cny::text,
        m.received_equivalent_cny::text,m.system_difference_cny::text,
        m.adjustment_amount_cny::text,m.carryover_amount_cny::text))
        AS amount_basis_md5,
      md5(to_jsonb(m)::text) AS structure_md5,
      lessons.lesson_count,lessons.planned_count,lessons.actual_count,
      lessons.lesson_uuid_md5,
      encode(sha256(convert_to(to_jsonb(sm)::text,'UTF8')),'hex')
        AS summary_sha256,
      encode(sha256(convert_to(to_jsonb(pv)::text,'UTF8')),'hex')
        AS preview_sha256
    FROM public.school_student_monthly_settlements m
    LEFT JOIN LATERAL (
      SELECT count(*) AS lesson_count,
        count(*) FILTER (WHERE l.lesson_type='planned') AS planned_count,
        count(*) FILTER (WHERE l.lesson_type='actual') AS actual_count,
        md5(string_agg(l.id::text,',' ORDER BY l.id::text)) AS lesson_uuid_md5
      FROM public.school_list_r1d_e_c_student_month_lessons(
        m.student_id,m.year_month) resolved
      JOIN public.school_lesson_records l ON l.id=resolved.lesson_id
      WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
    ) lessons ON true
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_summary(
      m.student_id,m.year_month) sm
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_preview(
      m.student_id,m.year_month) pv
    WHERE m.settlement_status='locked'
  )
  SELECT count(*),count(*) FILTER (
      WHERE e.settlement_snapshot_id IS NULL
        OR e.student_id_snapshot IS DISTINCT FROM c.student_id
        OR e.business_entity_id_snapshot IS DISTINCT FROM c.business_entity_id
        OR e.settlement_month_snapshot IS DISTINCT FROM c.year_month
        OR e.settlement_status_snapshot IS DISTINCT FROM c.settlement_status
        OR e.lesson_count IS DISTINCT FROM c.lesson_count
        OR e.planned_lesson_count IS DISTINCT FROM c.planned_count
        OR e.actual_lesson_count IS DISTINCT FROM c.actual_count
        OR e.lesson_uuid_md5 IS DISTINCT FROM c.lesson_uuid_md5
        OR e.amount_basis_md5 IS DISTINCT FROM c.amount_basis_md5
        OR e.settlement_structure_md5 IS DISTINCT FROM c.structure_md5),
    encode(sha256(convert_to(string_agg(concat_ws('|',c.id::text,
      c.summary_sha256,c.preview_sha256),E'\n' ORDER BY c.id::text)||E'\n',
      'UTF8')),'hex')
  INTO v_locked_count,v_locked_mismatch,v_locked_reader_sha
  FROM locked_current c
  LEFT JOIN public.school_legacy_settlement_snapshot_basis_evidence e
    ON e.settlement_snapshot_id=c.id;

  IF v_locked_count<>15 OR v_locked_mismatch<>0 OR v_locked_reader_sha<>
       'b3a27028c10c11baefebeb4669c6b91758266353cb357dcc77344431c6b2d20f' THEN
    RAISE EXCEPTION 'R1D_E_C_POSTDEPLOY_LOCKED_BASELINE_CHANGED: %/%/%',
      v_locked_count,v_locked_mismatch,v_locked_reader_sha;
  END IF;

  RAISE NOTICE 'R1D_E_C_POSTDEPLOY_SCOPE_BASELINE_SHA256=%',v_scope_sha;
  RAISE NOTICE 'R1D_E_C_POSTDEPLOY_LOCKED_READER_SHA256=%',v_locked_reader_sha;
END
$reader_baseline$;

SELECT public.school_r1d_e_c_settlement_reader_cutover_version()
    AS cutover_version,
  (SELECT count(*)
   FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL))
    AS classified_school_lessons,
  (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)
    AS fixed_legacy_actual_rows,
  (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)
    AS fixed_legacy_planned_rows,
  true AS postdeploy_pass;

\if :{?r1d_e_c_postdeploy_existing_tx}
  \echo 'R1D_E_C_POSTDEPLOY_COMPLETE_CALLER_MUST_ROLLBACK'
\else
  ROLLBACK;
\endif
