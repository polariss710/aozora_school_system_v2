-- School V2 tuition P0 R1D-E-B2 postdeploy read-only acceptance.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_b2_postdeploy_existing_tx}
  \echo 'R1D_E_B2_POSTDEPLOY_USING_CALLER_TRANSACTION'
\else
  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
\endif
SET LOCAL statement_timeout='240s';

DO $postdeploy$
DECLARE
  v_manifest record;
  v_candidate_count bigint;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_candidate_md5 text;
  v_candidate_sha text;
  v_actual_count bigint;
  v_actual_hash text;
  v_trigger_hash text;
  v_settlement_count bigint;
  v_settlement_hash text;
BEGIN
  IF public.school_r1d_e_b2_actual_writer_cutover_version()
       <>'r1d_e_b2_actual_writer_v1'
     OR to_regclass('public.school_legacy_actual_settlement_evidence') IS NULL
     OR to_regprocedure('public.school_resolve_r1d_e_b2_actual_student_month(uuid)') IS NULL
     OR to_regprocedure('public.school_enforce_r1d_e_b2_actual_attribution()') IS NULL
     OR md5(pg_get_functiondef(
          'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))
          <>'4a163f6691c779531a65a10be0f4422e'
     OR position('R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' IN pg_get_functiondef(
          'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED' IN pg_get_functiondef(
          'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_lesson_records'::regclass
           AND tgname='trg_school_lesson_r1d_e_b2_actual_attribution'
           AND NOT tgisinternal AND tgenabled='O')<>1
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_legacy_actual_settlement_evidence'::regclass
           AND NOT tgisinternal AND tgenabled='O')<>2
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
             WHERE oid='public.school_legacy_actual_settlement_evidence'::regclass) THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_OBJECT_FAILED';
  END IF;

  IF NOT has_table_privilege('service_role',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_table_privilege('service_role',
       'public.school_legacy_actual_settlement_evidence','INSERT,UPDATE,DELETE,TRUNCATE')
     OR has_table_privilege('anon',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_table_privilege('authenticated',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_function_privilege('anon',
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_r1d_e_b2_actual_writer_cutover_version()','EXECUTE') THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_ACL_FAILED';
  END IF;

  SELECT min(cutover_actual_count) AS actual_count,
    min(cutover_actual_uuid_md5) AS uuid_md5,
    min(cutover_identity_manifest_sha256) AS identity_sha,
    min(cutover_full_row_manifest_sha256) AS full_row_sha,
    count(DISTINCT cutover_actual_count) AS count_versions,
    count(DISTINCT cutover_actual_uuid_md5) AS uuid_versions,
    count(DISTINCT cutover_identity_manifest_sha256) AS identity_versions,
    count(DISTINCT cutover_full_row_manifest_sha256) AS full_row_versions
  INTO v_manifest
  FROM public.school_legacy_actual_settlement_evidence;

  IF v_manifest.count_versions<>1 OR v_manifest.uuid_versions<>1
     OR v_manifest.identity_versions<>1 OR v_manifest.full_row_versions<>1
     OR v_manifest.actual_count<>(SELECT count(*)
           FROM public.school_legacy_actual_settlement_evidence)
     OR v_manifest.uuid_md5<>(SELECT md5(string_agg(actual_lesson_id::text,','
           ORDER BY actual_lesson_id::text))
           FROM public.school_legacy_actual_settlement_evidence)
     OR v_manifest.identity_sha<>(SELECT encode(sha256(convert_to(
           string_agg(concat_ws('|',actual_lesson_id::text,actual_identity_md5),E'\n'
             ORDER BY actual_lesson_id::text)||E'\n','UTF8')),'hex')
           FROM public.school_legacy_actual_settlement_evidence)
     OR v_manifest.full_row_sha<>(SELECT encode(sha256(convert_to(
           string_agg(concat_ws('|',actual_lesson_id::text,actual_full_row_md5),E'\n'
             ORDER BY actual_lesson_id::text)||E'\n','UTF8')),'hex')
           FROM public.school_legacy_actual_settlement_evidence) THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_EVIDENCE_MANIFEST_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
    JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
    WHERE a.lesson_type<>'actual' OR a.app_type<>'school'
       OR a.student_settlement_month IS NOT NULL
       OR e.source_planned_lesson_id IS DISTINCT FROM a.planned_lesson_id
       OR e.student_id_snapshot IS DISTINCT FROM a.student_id
       OR e.business_entity_id_snapshot IS DISTINCT FROM a.business_entity_id
       OR e.teacher_id_snapshot IS DISTINCT FROM a.teacher_id
       OR e.subject_id_snapshot IS DISTINCT FROM a.subject_id
       OR e.legacy_year_month IS DISTINCT FROM a.year_month
       OR e.teacher_settlement_month_snapshot IS DISTINCT FROM
          coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM'))
       OR e.lesson_date_snapshot IS DISTINCT FROM a.lesson_date
       OR e.actual_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
          a.id::text,a.planned_lesson_id::text,a.student_id::text,
          a.business_entity_id::text,coalesce(a.teacher_id::text,'<NULL>'),
          coalesce(a.subject_id::text,'<NULL>'),a.year_month,
          coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM')),
          a.lesson_date::text,a.lesson_type,a.app_type))
       OR e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)
  ) OR EXISTS (
    SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
    LEFT JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
    WHERE a.id IS NULL
  ) THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_EXISTING_ACTUAL_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.lesson_type='actual' AND a.app_type='school'
      AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                      WHERE e.actual_lesson_id=a.id)
      AND (a.planned_lesson_id IS NULL OR a.student_settlement_month IS NULL
        OR a.year_month IS DISTINCT FROM a.student_settlement_month
        OR a.teacher_settlement_month IS DISTINCT FROM to_char(a.lesson_date,'YYYY-MM')
        OR num_nonnulls(a.billing_month,a.billing_week_start_date,
             a.billing_month_source,a.billing_month_decided_at)<>0
        OR a.student_settlement_month IS DISTINCT FROM
             public.school_resolve_r1d_e_b2_actual_student_month(a.planned_lesson_id))
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.lesson_type='actual' AND a.app_type='school'
      AND a.student_settlement_month IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                      WHERE e.actual_lesson_id=a.id)
  ) THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_NEW_ACTUAL_INVARIANT_FAILED';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
      'school_create_partial_completed_actual_from_planned','school_create_lesson_credit_makeup_actual',
      'school_create_makeup_completed_actual_lesson_from_planned',
      'school_create_cross_month_makeup_completed_actual_from_planned',
      'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n'
      ORDER BY signature)) INTO v_actual_count,v_actual_hash FROM functions;
  IF v_actual_count<>8 OR v_actual_hash<>'046cb8c0002528634b767a046e4626ab'
     OR position('v_duration_hours <> v_planned.duration_hours' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure))=0
     OR position('p_duration_hours >= coalesce(v_planned.duration_hours, 0)' IN
       pg_get_functiondef('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure))=0
     OR position('p_duration_hours>v_remaining_hours' IN replace(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure),' ',''))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('R1D_E_B2_GUARDED_ACTUAL_STUDENT_MONTH_UNCLASSIFIED' IN
       pg_get_functiondef('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_update_lesson_record_guarded' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_WRITER_MATRIX_FAILED';
  END IF;
  v_trigger_hash:=md5(pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure));

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_get_student_monthly_settlement_summary','school_get_student_monthly_settlement_preview',
      'school_get_student_monthly_settlement_wage_blockers',
      'school_assert_student_monthly_settlement_no_wage_blocker',
      'school_lock_student_monthly_settlement','school_unlock_student_monthly_settlement',
      'school_relock_student_monthly_settlement',
      'school_set_student_monthly_settlement_draft_adjustment']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n'
      ORDER BY signature)) INTO v_settlement_count,v_settlement_hash FROM functions;
  IF v_settlement_count<>8 OR v_settlement_hash<>'b17b31a3dc1797159556032abdb04ac3' THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_SETTLEMENT_READER_CHANGED';
  END IF;

  IF public.school_r1d_f1_planned_attribution_cutover_version()
       <>'r1d_f1_planned_attribution_v1'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND billing_month_source IN (
             'approved_r1c_a_manifest','approved_r1c_c_b_manifest'))<>118
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0)<>279
     OR (SELECT md5(string_agg(id::text,',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0)
        <>'0975fdc91b533680e5ccc909f076ac62'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)
             BETWEEN 1 AND 4)<>0 THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_F1_OR_PLANNED_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',planned_lesson_id::text,
           coalesce(student_id_snapshot::text,'<NULL>'),
           coalesce(business_entity_id_snapshot::text,'<NULL>'),
           legacy_student_settlement_month,'planned','school'),E'\n'
           ORDER BY planned_lesson_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_planned_settlement_evidence)
        <>'34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence)<>15
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',settlement_snapshot_id::text,
           student_id_snapshot::text,business_entity_id_snapshot::text,
           settlement_month_snapshot,settlement_status_snapshot,lesson_count::text,
           planned_lesson_count::text,actual_lesson_count::text,lesson_uuid_md5,
           amount_basis_md5,settlement_structure_md5),E'\n'
           ORDER BY settlement_snapshot_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_settlement_snapshot_basis_evidence)
        <>'68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_E_B1_EVIDENCE_CHANGED';
  END IF;

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
      AND l.billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest')
      AND l.billing_month_decided_at IS NOT NULL AND l.lesson_date IS NOT NULL
      AND l.teacher_id IS NOT NULL AND l.subject_id IS NOT NULL
      AND l.lesson_count>0 AND l.duration_hours>0 AND l.unit_price>0 AND l.lesson_fee>0
      AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
                      WHERE r.planned_lesson_id=l.id)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                      WHERE (b.source_snapshot->'planned_lesson_ids') ? l.id::text)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
                      WHERE e.planned_lesson_id=l.id)
  ) SELECT count(*),sum(duration_hours),sum(lesson_fee),
    md5(string_agg(id::text,',' ORDER BY id::text)),
    encode(sha256(convert_to(string_agg(concat_ws('|',id::text,student_id::text,
      billing_month,billing_week_start_date::text,duration_hours::text,unit_price::text,
      lesson_fee::text,billing_month_source,to_char(billing_month_decided_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),E'\n' ORDER BY student_id::text,billing_month,
      billing_week_start_date,id::text)||E'\n','UTF8')),'hex')
  INTO v_candidate_count,v_candidate_hours,v_candidate_fee,v_candidate_md5,v_candidate_sha
  FROM candidate;
  IF v_candidate_count<>118 OR v_candidate_hours<>254 OR v_candidate_fee<>2474000
     OR v_candidate_md5<>'77f697f82e547d84dcabf88a3c868aa1'
     OR v_candidate_sha<>'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_CANDIDATE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records a
      JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
      WHERE a.app_type='school' AND a.lesson_type='actual'
        AND a.duration_hours>p.duration_hours)<>19
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(student_duration_overage_minutes,
           student_duration_overage_fee_jpy,student_duration_overage_policy_version,
           student_duration_overage_source,student_duration_overage_decided_at)>0)<>0
     OR (SELECT count(*) FROM public.school_lesson_records actual
         JOIN public.school_lesson_records planned ON planned.id=actual.planned_lesson_id
         WHERE actual.app_type='school' AND actual.lesson_type='actual'
           AND actual.status='makeup_completed'
           AND actual.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND actual.year_month IS DISTINCT FROM planned.year_month)<>8
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(actual)::text),''
           ORDER BY actual.id::text),''))
         FROM public.school_lesson_records actual
         JOIN public.school_lesson_records planned ON planned.id=actual.planned_lesson_id
         WHERE actual.app_type='school' AND actual.lesson_type='actual'
           AND actual.status='makeup_completed'
           AND actual.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND actual.year_month IS DISTINCT FROM planned.year_month)
        <>'18a32469745dfcfe5535b5920df41cfd'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(base_lesson_fee_jpy,lesson_venue_id,aircon_charge_status,
           aircon_rate_id,aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
           aircon_fee_jpy,aircon_calculated_at,fee_calculation_version,
           fee_block_reason_code,fee_components_frozen_at)>0)<>0
     OR (SELECT count(*) FROM public.school_lesson_venues)
       +(SELECT count(*) FROM public.school_student_aircon_rates)
       +(SELECT count(*) FROM public.school_planned_writer_commands)
       +(SELECT count(*) FROM public.school_venue_rate_change_audit)<>0 THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_OVERAGE_MAKEUP_AIRCON_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR (SELECT count(*) FROM public.school_student_tuition_bills)<>9
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
         FROM public.school_student_tuition_bills x)<>'0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT count(*) FROM public.school_income_records)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
         FROM public.school_income_records x)<>'2a4897b752f272b1f192045418b4940c'
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)<>121
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(x)-ARRAY[
          'base_lesson_fee_jpy_snapshot','aircon_rate_id_snapshot',
          'aircon_unit_price_jpy_snapshot','aircon_billable_hours_snapshot',
          'aircon_fee_jpy_snapshot','fee_calculation_version_snapshot',
          'lesson_venue_id_snapshot','lesson_venue_code_snapshot'])::text),''
          ORDER BY x.id::text),''))
         FROM public.school_student_tuition_bill_lessons x)
        <>'09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
         FROM public.school_student_tuition_historical_lesson_exclusions x)
        <>'680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R1D_E_B2_POSTDEPLOY_R0_OR_FINANCIAL_CHAIN_CHANGED';
  END IF;

  RAISE NOTICE 'R1D_E_B2_POSTDEPLOY_ACTUAL_WRITER_GROUP_MD5=%',v_actual_hash;
  RAISE NOTICE 'R1D_E_B2_POSTDEPLOY_TRIGGER_FUNCTION_MD5=%',v_trigger_hash;
END
$postdeploy$;

SELECT public.school_r1d_e_b2_actual_writer_cutover_version() AS cutover_version,
  (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)
    AS fixed_legacy_actual_rows,
  (SELECT min(cutover_actual_uuid_md5)
   FROM public.school_legacy_actual_settlement_evidence) AS fixed_actual_uuid_md5,
  (SELECT count(*) FROM public.school_lesson_records a
   WHERE a.lesson_type='actual' AND a.app_type='school'
     AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                     WHERE e.actual_lesson_id=a.id)) AS post_cutover_actual_rows,
  true AS postdeploy_pass;

\if :{?r1d_e_b2_postdeploy_existing_tx}
  \echo 'R1D_E_B2_POSTDEPLOY_COMPLETE_CALLER_MUST_ROLLBACK'
\else
  ROLLBACK;
\endif
