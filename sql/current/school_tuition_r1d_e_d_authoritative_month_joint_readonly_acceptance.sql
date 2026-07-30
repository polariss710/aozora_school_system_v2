-- School V2 tuition P0 R1D-E-D: joint authoritative-month read-only acceptance.
-- This file performs no deployment, DML, write RPC, or rollback fixture.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='600s';

DO $catalog_and_frozen_boundaries$
DECLARE
  v_count bigint;
  v_hash text;
  v_record record;
BEGIN
  IF current_setting('transaction_isolation')<>'repeatable read'
     OR current_setting('transaction_read_only')<>'on' THEN
    RAISE EXCEPTION 'R1D_E_D_TRANSACTION_NOT_REPEATABLE_READ_ONLY';
  END IF;

  IF public.school_r1d_f1_planned_attribution_cutover_version()<>
       'r1d_f1_planned_attribution_v1'
     OR public.school_r1d_e_b2_actual_writer_cutover_version()<>
       'r1d_e_b2_actual_writer_v1'
     OR public.school_r1d_e_c_settlement_reader_cutover_version()<>
       'r1d_e_c_settlement_reader_v1' THEN
    RAISE EXCEPTION 'R1D_E_D_VERSION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.school_lesson_records'::regclass
        AND tgname='trg_school_lesson_r1d_f1_planned_attribution'
        AND NOT tgisinternal AND tgenabled='O')<>1
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_lesson_records'::regclass
           AND tgname='trg_school_lesson_r1d_e_b2_actual_attribution'
           AND NOT tgisinternal AND tgenabled='O')<>1 THEN
    RAISE EXCEPTION 'R1D_E_D_WRITER_TRIGGER_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure))<>
       '607a6030f28fecdcefbeb94f23306d2e'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure))<>
       'd37839bb96797fb4f7a91246eb96f0ba'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure))<>
       '78176ed41f87b8ad9ac1bba5e456a8b8'
     OR md5(pg_get_functiondef(
       'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure))<>
       '73da60c85e9f74d20b601a0d1339badf'
     OR md5(pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure))<>
       '5ae14921f400bf404eebfabcefdb631b'
     OR md5(pg_get_functiondef(
       'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure))<>
       '448346b2f3949aa9e217fc5d9b512410'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))<>
       'dca22a58c3efad550d87597385a143df' THEN
    RAISE EXCEPTION 'R1D_E_D_PLANNED_WRITER_DEFINITION_DRIFT';
  END IF;

  IF position('school_create_planned_lesson_record_r1d_f1_legacy_core' IN
       pg_get_functiondef(
       'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure))=0
     OR position('school_generate_planned_lessons_batch_r1d_f1_legacy_core' IN
       pg_get_functiondef(
       'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure))=0
     OR position('school_import_lesson_records_batch_r1d_f1_legacy_core' IN
       pg_get_functiondef(
       'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure))=0
     OR position('school_create_planned_lesson_record' IN pg_get_functiondef(
       'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure))=0
     OR position('school_generate_planned_lessons_batch' IN pg_get_functiondef(
       'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure))=0
     OR position('school_import_lesson_records_batch' IN pg_get_functiondef(
       'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure))=0
     OR position('school_update_lesson_record_guarded' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_D_PLANNED_WRITER_CALL_GRAPH_DRIFT';
  END IF;

  WITH functions AS (
    SELECT p.oid::regprocedure::text AS signature,
      md5(pg_get_functiondef(p.oid)) AS definition_md5,
      coalesce(p.proacl::text,'<NULL>') AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
      'school_create_planned_lesson_record',
      'school_create_planned_lesson_record_with_venue',
      'school_generate_planned_lessons_batch',
      'school_generate_planned_lessons_batch_with_venue',
      'school_import_lesson_records_batch',
      'school_import_lesson_records_batch_with_venue',
      'school_update_lesson_record_guarded',
      'school_update_lesson_record_guarded_with_venue']::text[])
  ) SELECT count(*),md5(string_agg(concat_ws('|',signature,definition_md5,acl),
      E'\n' ORDER BY signature)) INTO v_count,v_hash FROM functions;
  IF v_count<>8 OR v_hash<>'edf092ebf96fdd608dbd87cd93c4d047'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure))<>
       '08f3c60890d4afab8d9c730eec286c8d' THEN
    RAISE EXCEPTION 'R1D_E_D_PLANNED_WRITER_OR_TRIGGER_HASH_DRIFT';
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
      E'\n' ORDER BY signature)) INTO v_count,v_hash FROM functions;
  IF v_count<>8 OR v_hash<>'046cb8c0002528634b767a046e4626ab'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))<>
       '4a163f6691c779531a65a10be0f4422e'
     OR position('v_duration_hours <> v_planned.duration_hours' IN
       pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure))=0
     OR position('p_duration_hours >= coalesce(v_planned.duration_hours, 0)' IN
       pg_get_functiondef(
       'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure))=0
     OR position('p_duration_hours>v_remaining_hours' IN replace(
       pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure),' ',''))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_update_lesson_record_guarded' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_D_ACTUAL_WRITER_OR_CALL_GRAPH_DRIFT';
  END IF;

  IF position('TG_OP=''INSERT''' IN replace(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure),' ',''))=0
     OR position('OLD.lesson_type=''actual''' IN replace(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure),' ',''))=0
     OR position('R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' IN pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED' IN pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE' IN
       pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_CANONICAL_ACTUAL_STUDENT_MONTH_IMMUTABLE' IN
       pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_D_ACTUAL_TRIGGER_COVERAGE_DRIFT';
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
      E'\n' ORDER BY signature)) INTO v_count,v_hash FROM functions;
  IF v_count<>8 OR v_hash<>'b3818fc1119b5b2c1069d78164760e95'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure))<>
       '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure))<>
       '155e831118acbeadfd04b6640324c7cd'
     OR md5(pg_get_functiondef(
       'public.school_r1d_e_c_settlement_reader_cutover_version()'::regprocedure))<>
       '1307a4e86cccff841af55d3120a33b43' THEN
    RAISE EXCEPTION 'R1D_E_D_READER_OR_HELPER_HASH_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'school_r1d_e_c_settlement_reader_cutover_version',
      'school_resolve_r1d_e_c_lesson_student_month',
      'school_list_r1d_e_c_student_month_lessons')
      AND coalesce(p.proacl::text,'')<>'{postgres=X/postgres}'
  ) THEN
    RAISE EXCEPTION 'R1D_E_D_INTERNAL_READER_ACL_DRIFT';
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
     OR position('R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE' IN pg_get_functiondef(
       'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     OR position('school_list_r1d_e_c_student_month_lessons' IN pg_get_functiondef(
       'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_D_READER_CALL_GRAPH_DRIFT';
  END IF;

  IF EXISTS (
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
      AND (position('coalesce(student_settlement_month, year_month)' IN
             lower(pg_get_functiondef(p.oid)))>0
        OR position('l.year_month = p_year_month' IN pg_get_functiondef(p.oid))>0)
  ) OR position('created_at' IN lower(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)))>0
     OR position('updated_at' IN lower(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure)))>0 THEN
    RAISE EXCEPTION 'R1D_E_D_FORBIDDEN_READER_FALLBACK_FOUND';
  END IF;

  SELECT min(cutover_actual_count) AS actual_count,
    min(cutover_actual_uuid_md5) AS uuid_md5,
    min(cutover_identity_manifest_sha256) AS identity_sha,
    min(cutover_full_row_manifest_sha256) AS full_row_sha,
    count(DISTINCT cutover_actual_count) AS count_versions,
    count(DISTINCT cutover_actual_uuid_md5) AS uuid_versions,
    count(DISTINCT cutover_identity_manifest_sha256) AS identity_versions,
    count(DISTINCT cutover_full_row_manifest_sha256) AS full_row_versions
  INTO v_record FROM public.school_legacy_actual_settlement_evidence;
  IF v_record.actual_count<>234
     OR v_record.uuid_md5<>'891eeabf9a48d1c7b00a695b21cf8e95'
     OR v_record.identity_sha<>
       '83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c'
     OR v_record.full_row_sha<>
       'dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8'
     OR v_record.count_versions<>1 OR v_record.uuid_versions<>1
     OR v_record.identity_versions<>1 OR v_record.full_row_versions<>1
     OR EXISTS (
       SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
       LEFT JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
       WHERE a.id IS NULL OR a.student_settlement_month IS NOT NULL
          OR e.source_planned_lesson_id IS DISTINCT FROM a.planned_lesson_id
          OR e.student_id_snapshot IS DISTINCT FROM a.student_id
          OR e.business_entity_id_snapshot IS DISTINCT FROM a.business_entity_id
          OR e.teacher_id_snapshot IS DISTINCT FROM a.teacher_id
          OR e.subject_id_snapshot IS DISTINCT FROM a.subject_id
          OR e.legacy_year_month IS DISTINCT FROM a.year_month
          OR e.teacher_settlement_month_snapshot IS DISTINCT FROM
               coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM'))
          OR e.lesson_date_snapshot IS DISTINCT FROM a.lesson_date
          OR e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)
          OR e.actual_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
            a.id::text,a.planned_lesson_id::text,a.student_id::text,
            a.business_entity_id::text,coalesce(a.teacher_id::text,'<NULL>'),
            coalesce(a.subject_id::text,'<NULL>'),a.year_month,
            coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM')),
            a.lesson_date::text,a.lesson_type,a.app_type))
     ) THEN
    RAISE EXCEPTION 'R1D_E_D_ACTUAL_EVIDENCE_OR_ROW_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',
           planned_lesson_id::text,coalesce(student_id_snapshot::text,'<NULL>'),
           coalesce(business_entity_id_snapshot::text,'<NULL>'),
           legacy_student_settlement_month,'planned','school'),E'\n'
           ORDER BY planned_lesson_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_planned_settlement_evidence)<>
       '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR EXISTS (
       SELECT 1 FROM public.school_legacy_planned_settlement_evidence e
       LEFT JOIN public.school_lesson_records p ON p.id=e.planned_lesson_id
       WHERE p.id IS NULL OR p.app_type IS DISTINCT FROM 'school'
          OR p.lesson_type IS DISTINCT FROM 'planned'
          OR num_nonnulls(p.billing_month,p.billing_week_start_date,
               p.student_settlement_month,p.billing_month_source,
               p.billing_month_decided_at)<>0
          OR p.student_id IS DISTINCT FROM e.student_id_snapshot
          OR p.business_entity_id IS DISTINCT FROM e.business_entity_id_snapshot
          OR p.year_month IS DISTINCT FROM e.legacy_student_settlement_month
          OR e.lesson_identity_md5 IS DISTINCT FROM md5(concat_ws('|',p.id::text,
               coalesce(p.student_id::text,'<NULL>'),
               coalesce(p.business_entity_id::text,'<NULL>'),
               coalesce(p.year_month,'<NULL>'),p.lesson_type,p.app_type))
     ) THEN
    RAISE EXCEPTION 'R1D_E_D_PLANNED_EVIDENCE_OR_IDENTITY_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence)<>15
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',
           settlement_snapshot_id::text,student_id_snapshot::text,
           business_entity_id_snapshot::text,settlement_month_snapshot,
           settlement_status_snapshot,lesson_count::text,
           planned_lesson_count::text,actual_lesson_count::text,
           lesson_uuid_md5,amount_basis_md5,settlement_structure_md5),E'\n'
           ORDER BY settlement_snapshot_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_settlement_snapshot_basis_evidence)<>
       '68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_D_SNAPSHOT_EVIDENCE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE app_type='school' AND lesson_type='planned'
        AND num_nonnulls(billing_month,billing_week_start_date,
          student_settlement_month,billing_month_source,
          billing_month_decided_at)=0)<>279
     OR (SELECT md5(string_agg(id::text,',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE app_type='school' AND lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,
             billing_month_decided_at)=0)<>'0975fdc91b533680e5ccc909f076ac62'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE app_type='school' AND lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,
             billing_month_decided_at) BETWEEN 1 AND 4)<>0 THEN
    RAISE EXCEPTION 'R1D_E_D_PLANNED_DISTRIBUTION_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records p
    WHERE p.app_type='school' AND p.lesson_type='planned'
      AND num_nonnulls(p.billing_month,p.billing_week_start_date,
        p.student_settlement_month,p.billing_month_source,
        p.billing_month_decided_at)=5
      AND (p.billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
        OR p.student_settlement_month IS DISTINCT FROM p.billing_month
        OR extract(isodow FROM p.billing_week_start_date)<>1
        OR to_char(p.billing_week_start_date,'YYYY-MM')<>p.billing_month
        OR p.billing_month_source NOT IN ('approved_r1c_a_manifest',
          'approved_r1c_c_b_manifest','scheduled_date_at_create',
          'explicit_billing_week_at_create')
        OR p.lesson_date IS NULL
        OR p.duration_hours IS DISTINCT FROM public.school_resolve_planned_duration(
          p.start_time::text,p.end_time::text,
          CASE WHEN p.start_time IS NULL AND p.end_time IS NULL
               THEN p.duration_hours ELSE NULL END))
  ) THEN
    RAISE EXCEPTION 'R1D_E_D_CANONICAL_PLANNED_INVARIANT_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
    WHERE a.app_type='school' AND a.lesson_type='actual'
      AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                      WHERE e.actual_lesson_id=a.id)
      AND (p.app_type IS DISTINCT FROM 'school'
        OR p.lesson_type IS DISTINCT FROM 'planned'
        OR p.voided_at IS NOT NULL
        OR a.student_id IS DISTINCT FROM p.student_id
        OR a.business_entity_id IS DISTINCT FROM p.business_entity_id
        OR a.student_settlement_month IS DISTINCT FROM
             public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        OR a.year_month IS DISTINCT FROM a.student_settlement_month
        OR a.teacher_settlement_month IS DISTINCT FROM
             to_char(a.lesson_date,'YYYY-MM')
        OR num_nonnulls(a.billing_month,a.billing_week_start_date,
             a.billing_month_source,a.billing_month_decided_at)<>0)
  ) OR EXISTS (
    SELECT 1 FROM public.school_lesson_records a
    WHERE a.app_type='school' AND a.lesson_type='actual'
      AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                      WHERE e.actual_lesson_id=a.id)
      AND a.planned_lesson_id IS NULL
  ) THEN
    RAISE EXCEPTION 'R1D_E_D_CANONICAL_ACTUAL_INVARIANT_FAILED';
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
      AND l.lesson_count>0 AND l.duration_hours>0 AND l.unit_price>0
      AND l.lesson_fee>0 AND l.created_at IS NOT NULL AND l.updated_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
                      WHERE r.planned_lesson_id=l.id)
      AND NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                      WHERE (b.source_snapshot->'planned_lesson_ids') ? l.id::text)
      AND NOT EXISTS (SELECT 1
        FROM public.school_student_tuition_historical_lesson_exclusions e
        WHERE e.planned_lesson_id=l.id)
  ) SELECT count(*) AS candidate_count,
      sum(duration_hours) AS candidate_hours,
      sum(lesson_fee) AS candidate_fee,
      md5(string_agg(id::text,',' ORDER BY id::text)) AS uuid_md5,
      encode(sha256(convert_to(string_agg(concat_ws('|',id::text,
        student_id::text,billing_month,billing_week_start_date::text,
        duration_hours::text,unit_price::text,lesson_fee::text,
        billing_month_source,to_char(billing_month_decided_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),E'\n' ORDER BY student_id::text,
        billing_month,billing_week_start_date,id::text)||E'\n','UTF8')),'hex')
        AS manifest_sha
    INTO v_record FROM candidate;
  IF v_record.candidate_count<>118 OR v_record.candidate_hours<>254
     OR v_record.candidate_fee<>2474000
     OR v_record.uuid_md5<>'77f697f82e547d84dcabf88a3c868aa1'
     OR v_record.manifest_sha<>
       'f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1'
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure))<>
       '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_D_CANDIDATE_DRIFT';
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
         FROM public.school_student_tuition_bill_lessons x)<>
       '09dfee7d8833e09384fb41a84f2959e0'
     OR (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)<>42
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))
         FROM public.school_student_tuition_historical_lesson_exclusions x)<>
       '680b6e5aaa718569aee4c36fe1cdc058' THEN
    RAISE EXCEPTION 'R1D_E_D_R0_OR_FINANCIAL_CHAIN_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records a
      JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
      WHERE a.app_type='school' AND a.lesson_type='actual'
        AND a.duration_hours>p.duration_hours)<>19
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(student_duration_overage_minutes,
           student_duration_overage_fee_jpy,student_duration_overage_policy_version,
           student_duration_overage_source,student_duration_overage_decided_at)>0)<>0
     OR (SELECT count(*) FROM public.school_lesson_records a
         JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
         WHERE a.app_type='school' AND a.lesson_type='actual'
           AND a.status='makeup_completed'
           AND a.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND a.year_month IS DISTINCT FROM p.year_month)<>8
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text),''
           ORDER BY a.id::text),''))
         FROM public.school_lesson_records a
         JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
         WHERE a.app_type='school' AND a.lesson_type='actual'
           AND a.status='makeup_completed'
           AND a.created_at<=TIMESTAMPTZ '2026-07-30 03:24:07.006005+00'
           AND a.year_month IS DISTINCT FROM p.year_month)<>
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
    RAISE EXCEPTION 'R1D_E_D_OVERAGE_MAKEUP_OR_AIRCON_DRIFT';
  END IF;
END
$catalog_and_frozen_boundaries$;

DO $classification_and_set_equality$
DECLARE
  v_total bigint;
  v_direct_count bigint;
  v_helper_count bigint;
  v_unclassified bigint;
  v_multiclass bigint;
  v_missing bigint;
  v_extra bigint;
  v_month_mismatch bigint;
  v_class_mismatch bigint;
  v_identity_mismatch bigint;
BEGIN
  WITH base AS (
    SELECT l.*,
      num_nonnulls(l.billing_month,l.billing_week_start_date,
        l.student_settlement_month,l.billing_month_source,
        l.billing_month_decided_at) AS bundle_count,
      EXISTS (SELECT 1 FROM public.school_legacy_planned_settlement_evidence e
              WHERE e.planned_lesson_id=l.id) AS legacy_planned_evidence,
      EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
              WHERE e.actual_lesson_id=l.id) AS legacy_actual_evidence
    FROM public.school_lesson_records l WHERE l.app_type='school'
  ), classified AS (
    SELECT b.*,
      ((b.lesson_type='planned' AND b.bundle_count=5)::int
       +(b.lesson_type='planned' AND b.bundle_count=0
         AND b.legacy_planned_evidence)::int
       +(b.lesson_type='actual' AND NOT b.legacy_actual_evidence)::int
       +(b.lesson_type='actual' AND b.legacy_actual_evidence)::int) AS match_count,
      public.school_resolve_r1d_e_c_lesson_student_month(b.id) AS month,
      CASE WHEN b.lesson_type='planned' AND b.bundle_count=5
             THEN 'canonical_planned'
           WHEN b.lesson_type='planned' AND b.bundle_count=0
             AND b.legacy_planned_evidence THEN 'legacy_planned'
           WHEN b.lesson_type='actual' AND b.legacy_actual_evidence
             THEN 'legacy_actual'
           WHEN b.lesson_type='actual' AND NOT b.legacy_actual_evidence
             THEN 'canonical_actual' END AS class
    FROM base b
  ), helper AS (
    SELECT * FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
  ), diff AS (
    SELECT c.id,h.lesson_id,c.student_id AS direct_student_id,
      h.student_id AS helper_student_id,c.business_entity_id AS direct_entity_id,
      h.business_entity_id AS helper_entity_id,c.month AS direct_month,
      h.authoritative_student_month AS helper_month,c.class AS direct_class,
      h.attribution_class AS helper_class
    FROM classified c FULL JOIN helper h ON h.lesson_id=c.id
  )
  SELECT (SELECT count(*) FROM base),(SELECT count(*) FROM classified),
    (SELECT count(*) FROM helper),
    (SELECT count(*) FROM classified WHERE match_count=0),
    (SELECT count(*) FROM classified WHERE match_count>1),
    (SELECT count(*) FROM diff WHERE lesson_id IS NULL),
    (SELECT count(*) FROM diff WHERE id IS NULL),
    (SELECT count(*) FROM diff WHERE direct_month IS DISTINCT FROM helper_month),
    (SELECT count(*) FROM diff WHERE direct_class IS DISTINCT FROM helper_class),
    (SELECT count(*) FROM diff WHERE direct_student_id IS DISTINCT FROM helper_student_id
       OR direct_entity_id IS DISTINCT FROM helper_entity_id)
  INTO v_total,v_direct_count,v_helper_count,v_unclassified,v_multiclass,
    v_missing,v_extra,v_month_mismatch,v_class_mismatch,v_identity_mismatch;

  IF v_total<>v_direct_count OR v_total<>v_helper_count
     OR v_unclassified<>0 OR v_multiclass<>0 OR v_missing<>0 OR v_extra<>0
     OR v_month_mismatch<>0 OR v_class_mismatch<>0 OR v_identity_mismatch<>0 THEN
    RAISE EXCEPTION 'R1D_E_D_CLASSIFICATION_OR_SET_MISMATCH: %/%/%/%/%/%/%/%/%/%',
      v_total,v_direct_count,v_helper_count,v_unclassified,v_multiclass,
      v_missing,v_extra,v_month_mismatch,v_class_mismatch,v_identity_mismatch;
  END IF;

  IF (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
      WHERE attribution_class='legacy_planned')<>279
     OR (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
         WHERE attribution_class='legacy_actual')<>234 THEN
    RAISE EXCEPTION 'R1D_E_D_FIXED_CLASS_COUNT_DRIFT';
  END IF;
END
$classification_and_set_equality$;

DO $summary_preview_blocker_acceptance$
DECLARE
  v_scope_count bigint;
  v_mismatch_count bigint;
BEGIN
  WITH lesson_scopes AS (
    SELECT DISTINCT student_id,authoritative_student_month AS year_month
    FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
  ), scopes AS (
    SELECT student_id,year_month FROM lesson_scopes
    UNION SELECT student_id,year_month
      FROM public.school_student_monthly_settlements
    UNION SELECT student_id,coalesce(settlement_month,year_month)
      FROM public.school_income_records
      WHERE student_id IS NOT NULL AND income_category='tuition'
        AND status='received' AND coalesce(include_in_student_settlement,true)=true
        AND coalesce(settlement_month,year_month)~'^[0-9]{4}-(0[1-9]|1[0-2])$'
    UNION SELECT student_id,year_month
      FROM public.school_student_settlement_adjustment_drafts
      WHERE app_type='school' AND status='active'
    UNION SELECT student_id,to_year_month
      FROM public.school_student_settlement_carryovers
      WHERE coalesce(status,'active')='active'
  ), evaluated AS (
    SELECT sc.student_id,sc.year_month,s.business_entity_id,
      sm,pv,
      (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(
        sc.student_id,sc.year_month)) AS lesson_count,
      (SELECT coalesce(sum(l.duration_hours),0)
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) r
       JOIN public.school_lesson_records l ON l.id=r.lesson_id
       WHERE l.lesson_type='planned' AND l.voided_at IS NULL) AS planned_hours,
      (SELECT coalesce(sum(l.duration_hours),0)
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) r
       JOIN public.school_lesson_records l ON l.id=r.lesson_id
       WHERE l.lesson_type='actual' AND l.is_billable=true
         AND l.status IN ('completed','makeup','makeup_completed')) AS actual_hours,
      (SELECT coalesce(sum(coalesce(l.lesson_fee,
           coalesce(l.unit_price,0)*coalesce(l.duration_hours,0),0)),0)
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) r
       JOIN public.school_lesson_records l ON l.id=r.lesson_id
       WHERE l.lesson_type='planned' AND l.voided_at IS NULL) AS planned_fee,
      (SELECT coalesce(sum(coalesce(l.lesson_fee,
           coalesce(l.unit_price,0)*coalesce(l.duration_hours,0),0)),0)
       FROM public.school_list_r1d_e_c_student_month_lessons(
         sc.student_id,sc.year_month) r
       JOIN public.school_lesson_records l ON l.id=r.lesson_id
       WHERE l.lesson_type='actual' AND l.is_billable=true
         AND l.status IN ('completed','makeup','makeup_completed')) AS actual_fee,
      d.id AS expected_draft_id,d.adjustment_amount_cny AS expected_adjustment,
      d.adjustment_source AS expected_adjustment_source,
      d.adjustment_reason AS expected_adjustment_reason,d.note AS expected_note
    FROM scopes sc
    JOIN public.school_students s ON s.id=sc.student_id AND s.app_type='school'
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_summary(
      sc.student_id,sc.year_month) sm
    CROSS JOIN LATERAL public.school_get_student_monthly_settlement_preview(
      sc.student_id,sc.year_month) pv
    LEFT JOIN LATERAL (
      SELECT d.* FROM public.school_student_settlement_adjustment_drafts d
      WHERE d.student_id=sc.student_id AND d.year_month=sc.year_month
        AND d.app_type='school' AND d.status='active'
      ORDER BY d.updated_at DESC,d.created_at DESC LIMIT 1
    ) d ON true
  ), checked AS (
    SELECT e.*,
      (SELECT count(*) FROM public.school_get_student_monthly_settlement_wage_blockers(
        e.year_month,e.student_id)) AS blocker_rows
    FROM evaluated e
  )
  SELECT count(*),count(*) FILTER (WHERE
       (sm).student_id IS DISTINCT FROM student_id
    OR (sm).year_month IS DISTINCT FROM year_month
    OR (pv).student_id IS DISTINCT FROM student_id
    OR (pv).year_month IS DISTINCT FROM year_month
    OR (pv).business_entity_id IS DISTINCT FROM business_entity_id
    OR (pv).exchange_rate IS DISTINCT FROM (sm).exchange_rate
    OR (pv).carryover_cny IS DISTINCT FROM (sm).carryover_cny
    OR (pv).planned_hours IS DISTINCT FROM (sm).planned_hours
    OR (pv).actual_hours IS DISTINCT FROM (sm).actual_hours
    OR (pv).planned_fee_jpy IS DISTINCT FROM (sm).planned_fee_jpy
    OR (pv).planned_fee_cny IS DISTINCT FROM (sm).planned_fee_cny
    OR (pv).planned_total_cny IS DISTINCT FROM (sm).planned_total_cny
    OR (pv).actual_fee_jpy IS DISTINCT FROM (sm).actual_fee_jpy
    OR (pv).actual_fee_cny IS DISTINCT FROM (sm).actual_fee_cny
    OR (pv).received_jpy IS DISTINCT FROM (sm).received_jpy
    OR (pv).received_cny IS DISTINCT FROM (sm).received_cny
    OR (pv).received_equivalent_cny IS DISTINCT FROM (sm).received_equivalent_cny
    OR (pv).final_due_cny IS DISTINCT FROM (sm).final_due_cny
    OR (sm).planned_hours IS DISTINCT FROM planned_hours
    OR (sm).actual_hours IS DISTINCT FROM actual_hours
    OR (sm).planned_fee_jpy IS DISTINCT FROM planned_fee
    OR (sm).actual_fee_jpy IS DISTINCT FROM actual_fee
    OR (pv).draft_id IS DISTINCT FROM expected_draft_id
    OR (pv).adjustment_amount_cny IS DISTINCT FROM round(coalesce(expected_adjustment,0),2)
    OR (pv).adjustment_source IS DISTINCT FROM expected_adjustment_source
    OR (pv).adjustment_reason IS DISTINCT FROM expected_adjustment_reason
    OR (pv).adjustment_note IS DISTINCT FROM expected_note)
  INTO v_scope_count,v_mismatch_count FROM checked;

  IF v_scope_count=0 OR v_mismatch_count<>0 THEN
    RAISE EXCEPTION 'R1D_E_D_SUMMARY_PREVIEW_MISMATCH: %/%',
      v_scope_count,v_mismatch_count;
  END IF;

END
$summary_preview_blocker_acceptance$;

DO $locked_snapshot_acceptance$
DECLARE
  v_locked_count bigint;
  v_locked_mismatch bigint;
  v_locked_reader_sha text;
BEGIN
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
    RAISE EXCEPTION 'R1D_E_D_LOCKED_SNAPSHOT_DRIFT: %/%/%',
      v_locked_count,v_locked_mismatch,v_locked_reader_sha;
  END IF;
END
$locked_snapshot_acceptance$;

SELECT current_setting('transaction_isolation') AS transaction_isolation,
  current_setting('transaction_read_only') AS transaction_read_only,
  txid_current_if_assigned() IS NULL AS no_write_xid_assigned;

WITH planned_functions AS (
  SELECT p.oid::regprocedure::text AS signature,
    md5(pg_get_functiondef(p.oid)) AS definition_md5,
    coalesce(p.proacl::text,'<NULL>') AS acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
    'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
    'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
    'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
    'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue']::text[])
), actual_functions AS (
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
), reader_functions AS (
  SELECT p.oid::regprocedure::text AS signature,
    md5(pg_get_functiondef(p.oid)) AS definition_md5,
    coalesce(p.proacl::text,'<NULL>') AS acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
    'school_get_student_monthly_settlement_summary',
    'school_get_student_monthly_settlement_preview',
    'school_get_student_monthly_settlement_wage_blockers',
    'school_assert_student_monthly_settlement_no_wage_blocker',
    'school_lock_student_monthly_settlement','school_unlock_student_monthly_settlement',
    'school_relock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment']::text[])
)
SELECT (SELECT md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n'
          ORDER BY signature)) FROM planned_functions) AS planned_writer_group_md5,
  md5(pg_get_functiondef(
    'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure))
    AS planned_trigger_md5,
  (SELECT md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n'
          ORDER BY signature)) FROM actual_functions) AS actual_writer_group_md5,
  md5(pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))
    AS actual_trigger_md5,
  (SELECT md5(string_agg(concat_ws('|',signature,definition_md5,acl),E'\n'
          ORDER BY signature)) FROM reader_functions) AS reader_group_md5,
  md5(pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure))
    AS resolver_md5,
  md5(pg_get_functiondef(
    'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure))
    AS set_helper_md5,
  md5(pg_get_functiondef(
    'public.school_r1d_e_c_settlement_reader_cutover_version()'::regprocedure))
    AS version_helper_md5;

WITH functions AS (
  SELECT p.oid::regprocedure::text AS signature,
    md5(pg_get_functiondef(p.oid)) AS definition_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
    'school_create_planned_lesson_record','school_create_planned_lesson_record_with_venue',
    'school_generate_planned_lessons_batch','school_generate_planned_lessons_batch_with_venue',
    'school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
    'school_update_lesson_record_guarded','school_update_lesson_record_guarded_with_venue',
    'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
    'school_create_partial_completed_actual_from_planned','school_create_lesson_credit_makeup_actual',
    'school_create_makeup_completed_actual_lesson_from_planned',
    'school_create_cross_month_makeup_completed_actual_from_planned',
    'school_get_student_monthly_settlement_summary',
    'school_get_student_monthly_settlement_preview',
    'school_get_student_monthly_settlement_wage_blockers',
    'school_assert_student_monthly_settlement_no_wage_blocker',
    'school_lock_student_monthly_settlement','school_unlock_student_monthly_settlement',
    'school_relock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment']::text[])
), graph AS (
  SELECT signature,definition_md5,
    regexp_replace(pg_get_functiondef(signature::regprocedure),E'[\n\r\t ]+',' ','g')
      AS normalized_definition FROM functions
)
SELECT count(*) AS call_graph_function_count,
  encode(sha256(convert_to(string_agg(concat_ws('|',signature,definition_md5,
    normalized_definition),E'\n' ORDER BY signature)||E'\n','UTF8')),'hex')
    AS call_graph_manifest_sha256
FROM graph;

WITH classified AS (
  SELECT r.*,l.lesson_type,l.status,l.duration_hours,l.lesson_fee,l.unit_price,
    l.is_billable,l.teacher_settlement_month,
    public.school_resolve_r1d_e_c_lesson_student_month(l.id) AS direct_month
  FROM public.school_lesson_records l
  JOIN public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
    ON r.lesson_id=l.id
), class_rollup AS (
  SELECT attribution_class,count(*) AS lesson_count,
    md5(string_agg(lesson_id::text,',' ORDER BY lesson_id::text)) AS uuid_md5,
    encode(sha256(convert_to(string_agg(concat_ws('|',lesson_id::text,
      student_id::text,business_entity_id::text,authoritative_student_month,
      attribution_class,lesson_type,status,coalesce(duration_hours::text,'<NULL>'),
      coalesce(lesson_fee::text,'<NULL>'),coalesce(unit_price::text,'<NULL>'),
      coalesce(is_billable::text,'<NULL>'),
      coalesce(teacher_settlement_month,'<NULL>')),E'\n'
      ORDER BY lesson_id::text)||E'\n','UTF8')),'hex') AS manifest_sha256
  FROM classified GROUP BY attribution_class
)
SELECT * FROM class_rollup ORDER BY attribution_class;

WITH classified AS (
  SELECT r.*,l.lesson_type,l.status,l.duration_hours,
    coalesce(l.lesson_fee,coalesce(l.unit_price,0)*coalesce(l.duration_hours,0),0)
      AS fee_jpy,l.is_billable,l.teacher_settlement_month
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
), dimensions AS (
  SELECT student_id,business_entity_id,authoritative_student_month,
    count(*) FILTER (WHERE lesson_type='planned') AS planned_count,
    count(*) FILTER (WHERE lesson_type='actual') AS actual_count,
    coalesce(sum(duration_hours) FILTER (WHERE lesson_type='planned'),0)
      AS planned_duration,
    coalesce(sum(duration_hours) FILTER (WHERE lesson_type='actual'),0)
      AS actual_duration,
    coalesce(sum(fee_jpy) FILTER (WHERE lesson_type='planned'),0) AS planned_fee,
    coalesce(sum(fee_jpy) FILTER (WHERE lesson_type='actual' AND is_billable=true
      AND status IN ('completed','makeup','makeup_completed')),0) AS billable_actual_fee,
    md5(string_agg(lesson_id::text,',' ORDER BY lesson_id::text)) AS lesson_uuid_md5,
    string_agg(DISTINCT attribution_class,',' ORDER BY attribution_class)
      AS attribution_classes,
    string_agg(DISTINCT coalesce(teacher_settlement_month,'<NULL>'),','
      ORDER BY coalesce(teacher_settlement_month,'<NULL>')) AS teacher_months
  FROM classified GROUP BY student_id,business_entity_id,authoritative_student_month
)
SELECT count(*) AS student_entity_month_count,
  encode(sha256(convert_to(string_agg(concat_ws('|',student_id::text,
    business_entity_id::text,authoritative_student_month,planned_count::text,
    actual_count::text,planned_duration::text,actual_duration::text,
    planned_fee::text,billable_actual_fee::text,lesson_uuid_md5,
    attribution_classes,teacher_months),E'\n' ORDER BY student_id::text,
    business_entity_id::text,authoritative_student_month)||E'\n','UTF8')),'hex')
    AS student_entity_month_manifest_sha256
FROM dimensions;

WITH direct AS (
  SELECT l.id,l.student_id,l.business_entity_id,
    public.school_resolve_r1d_e_c_lesson_student_month(l.id) AS month,
    CASE WHEN l.lesson_type='planned' AND num_nonnulls(l.billing_month,
      l.billing_week_start_date,l.student_settlement_month,l.billing_month_source,
      l.billing_month_decided_at)=5 THEN 'canonical_planned'
    WHEN l.lesson_type='planned' THEN 'legacy_planned'
    WHEN EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                WHERE e.actual_lesson_id=l.id) THEN 'legacy_actual'
    ELSE 'canonical_actual' END AS class
  FROM public.school_lesson_records l WHERE l.app_type='school'
), helper AS (
  SELECT * FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
), diff AS (
  SELECT d.id,h.lesson_id,d.student_id AS direct_student,
    h.student_id AS helper_student,d.business_entity_id AS direct_entity,
    h.business_entity_id AS helper_entity,d.month AS direct_month,
    h.authoritative_student_month AS helper_month,d.class AS direct_class,
    h.attribution_class AS helper_class
  FROM direct d FULL JOIN helper h ON h.lesson_id=d.id
)
SELECT (SELECT count(*) FROM direct) AS direct_count,
  (SELECT count(*) FROM helper) AS helper_count,
  count(*) FILTER (WHERE lesson_id IS NULL) AS helper_missing,
  count(*) FILTER (WHERE id IS NULL) AS helper_extra,
  count(*) FILTER (WHERE direct_month IS DISTINCT FROM helper_month) AS month_mismatch,
  count(*) FILTER (WHERE direct_class IS DISTINCT FROM helper_class) AS class_mismatch,
  count(*) FILTER (WHERE direct_student IS DISTINCT FROM helper_student
    OR direct_entity IS DISTINCT FROM helper_entity) AS identity_mismatch
FROM diff;

WITH cross_month AS (
  SELECT 'canonical_planned_lesson_date'::text AS fact_class,l.id,l.student_id,
    l.business_entity_id,r.authoritative_student_month AS authoritative_month,
    to_char(l.lesson_date,'YYYY-MM') AS comparison_month
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE r.attribution_class='canonical_planned'
    AND to_char(l.lesson_date,'YYYY-MM')<>r.authoritative_student_month
  UNION ALL
  SELECT 'canonical_planned_billing_week_cross_month',l.id,l.student_id,
    l.business_entity_id,r.authoritative_student_month,
    to_char(l.billing_week_start_date+6,'YYYY-MM')
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE r.attribution_class='canonical_planned'
    AND to_char(l.billing_week_start_date,'YYYY-MM')<>
        to_char(l.billing_week_start_date+6,'YYYY-MM')
  UNION ALL
  SELECT 'canonical_actual_date_teacher',l.id,l.student_id,l.business_entity_id,
    r.authoritative_student_month,
    coalesce(l.teacher_settlement_month,to_char(l.lesson_date,'YYYY-MM'))
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE r.attribution_class='canonical_actual'
    AND coalesce(l.teacher_settlement_month,to_char(l.lesson_date,'YYYY-MM'))<>
        r.authoritative_student_month
  UNION ALL
  SELECT 'legacy_planned_frozen_vs_date',l.id,l.student_id,l.business_entity_id,
    r.authoritative_student_month,to_char(l.lesson_date,'YYYY-MM')
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE r.attribution_class='legacy_planned' AND l.lesson_date IS NOT NULL
    AND to_char(l.lesson_date,'YYYY-MM')<>r.authoritative_student_month
  UNION ALL
  SELECT 'legacy_actual_frozen_vs_date',l.id,l.student_id,l.business_entity_id,
    r.authoritative_student_month,to_char(l.lesson_date,'YYYY-MM')
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL) r
  JOIN public.school_lesson_records l ON l.id=r.lesson_id
  WHERE r.attribution_class='legacy_actual' AND l.lesson_date IS NOT NULL
    AND to_char(l.lesson_date,'YYYY-MM')<>r.authoritative_student_month
), expected_classes AS (
  SELECT unnest(ARRAY['canonical_planned_lesson_date',
    'canonical_planned_billing_week_cross_month','canonical_actual_date_teacher',
    'legacy_planned_frozen_vs_date','legacy_actual_frozen_vs_date']) AS fact_class
), rollup AS (
  SELECT fact_class,count(*) AS fact_count,
    md5(string_agg(id::text,',' ORDER BY id::text)) AS uuid_md5,
    encode(sha256(convert_to(string_agg(concat_ws('|',student_id::text,
      business_entity_id::text,authoritative_month,comparison_month),E'\n'
      ORDER BY student_id::text,business_entity_id::text,authoritative_month,
      comparison_month,id::text)||E'\n','UTF8')),'hex') AS dimension_manifest_sha256,
    count(*) FILTER (WHERE EXISTS (
      SELECT 1 FROM public.school_list_r1d_e_c_student_month_lessons(
        cross_month.student_id,cross_month.comparison_month) wrong
      WHERE wrong.lesson_id=cross_month.id)) AS incorrectly_in_comparison_month,
    count(*) FILTER (WHERE NOT EXISTS (
      SELECT 1 FROM public.school_list_r1d_e_c_student_month_lessons(
        cross_month.student_id,cross_month.authoritative_month) correct
      WHERE correct.lesson_id=cross_month.id)) AS missing_from_authoritative_month
  FROM cross_month GROUP BY fact_class
)
SELECT e.fact_class,coalesce(r.fact_count,0) AS fact_count,r.uuid_md5,
  r.dimension_manifest_sha256,coalesce(r.incorrectly_in_comparison_month,0)
    AS incorrectly_in_comparison_month,
  coalesce(r.missing_from_authoritative_month,0) AS missing_from_authoritative_month
FROM expected_classes e LEFT JOIN rollup r USING (fact_class)
ORDER BY e.fact_class;

WITH lesson_scopes AS (
  SELECT DISTINCT student_id,authoritative_student_month AS year_month
  FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL)
), scopes AS (
  SELECT student_id,year_month FROM lesson_scopes
  UNION SELECT student_id,year_month FROM public.school_student_monthly_settlements
  UNION SELECT student_id,coalesce(settlement_month,year_month)
    FROM public.school_income_records
    WHERE student_id IS NOT NULL AND income_category='tuition' AND status='received'
      AND coalesce(include_in_student_settlement,true)=true
      AND coalesce(settlement_month,year_month)~'^[0-9]{4}-(0[1-9]|1[0-2])$'
  UNION SELECT student_id,year_month
    FROM public.school_student_settlement_adjustment_drafts
    WHERE app_type='school' AND status='active'
  UNION SELECT student_id,to_year_month
    FROM public.school_student_settlement_carryovers
    WHERE coalesce(status,'active')='active'
), results AS (
  SELECT sc.student_id,sc.year_month,
    (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(
      sc.student_id,sc.year_month)) AS lesson_count,
    (SELECT count(*) FROM public.school_income_records i
      WHERE i.student_id=sc.student_id
        AND coalesce(i.settlement_month,i.year_month)=sc.year_month
        AND i.income_category='tuition' AND i.status='received'
        AND coalesce(i.include_in_student_settlement,true)=true) AS income_count,
    encode(sha256(convert_to(to_jsonb(sm)::text,'UTF8')),'hex') AS summary_sha256,
    encode(sha256(convert_to(to_jsonb(pv)::text,'UTF8')),'hex') AS preview_sha256,
    encode(sha256(convert_to(coalesce((SELECT jsonb_agg(to_jsonb(w)
      ORDER BY w.student_id,w.year_month)::text
      FROM public.school_get_student_monthly_settlement_wage_blockers(
        sc.year_month,sc.student_id) w),'[]'),'UTF8')),'hex') AS blocker_sha256
  FROM scopes sc JOIN public.school_students s ON s.id=sc.student_id AND s.app_type='school'
  CROSS JOIN LATERAL public.school_get_student_monthly_settlement_summary(
    sc.student_id,sc.year_month) sm
  CROSS JOIN LATERAL public.school_get_student_monthly_settlement_preview(
    sc.student_id,sc.year_month) pv
)
SELECT count(*) AS scope_count,
  count(*) FILTER (WHERE lesson_count=0) AS zero_lesson_scope_count,
  count(*) FILTER (WHERE lesson_count=0 AND income_count>0) AS income_only_scope_count,
  encode(sha256(convert_to(string_agg(concat_ws('|',student_id::text,year_month,
    lesson_count::text,income_count::text,summary_sha256,preview_sha256,
    blocker_sha256),E'\n' ORDER BY student_id::text,year_month)||E'\n','UTF8')),'hex')
    AS summary_preview_blocker_manifest_sha256
FROM results;

WITH locked_current AS (
  SELECT m.id,m.student_id,m.business_entity_id,m.year_month,m.settlement_status,
    m.carryover_amount_cny,m.adjustment_amount_cny,
    md5(concat_ws('|',m.preset_exchange_rate::text,
      m.planned_lesson_fee_jpy::text,m.planned_lesson_fee_cny::text,
      m.actual_lesson_fee_jpy::text,m.actual_lesson_fee_cny::text,
      m.previous_balance_cny::text,m.received_jpy::text,m.received_cny::text,
      m.received_equivalent_cny::text,m.system_difference_cny::text,
      m.adjustment_amount_cny::text,m.carryover_amount_cny::text)) AS amount_basis_md5,
    md5(to_jsonb(m)::text) AS structure_md5,
    lessons.lesson_count,lessons.planned_count,lessons.actual_count,
    lessons.lesson_uuid_md5,
    encode(sha256(convert_to(to_jsonb(sm)::text,'UTF8')),'hex') AS summary_sha256,
    encode(sha256(convert_to(to_jsonb(pv)::text,'UTF8')),'hex') AS preview_sha256
  FROM public.school_student_monthly_settlements m
  LEFT JOIN LATERAL (
    SELECT count(*) AS lesson_count,
      count(*) FILTER (WHERE l.lesson_type='planned') AS planned_count,
      count(*) FILTER (WHERE l.lesson_type='actual') AS actual_count,
      md5(string_agg(l.id::text,',' ORDER BY l.id::text)) AS lesson_uuid_md5
    FROM public.school_list_r1d_e_c_student_month_lessons(m.student_id,m.year_month) r
    JOIN public.school_lesson_records l ON l.id=r.lesson_id
    WHERE NOT (l.lesson_type='planned' AND l.voided_at IS NOT NULL)
  ) lessons ON true
  CROSS JOIN LATERAL public.school_get_student_monthly_settlement_summary(
    m.student_id,m.year_month) sm
  CROSS JOIN LATERAL public.school_get_student_monthly_settlement_preview(
    m.student_id,m.year_month) pv
  WHERE m.settlement_status='locked'
)
SELECT count(*) AS locked_snapshot_count,
  encode(sha256(convert_to(string_agg(concat_ws('|',id::text,
    lesson_count::text,planned_count::text,actual_count::text,lesson_uuid_md5,
    amount_basis_md5,structure_md5,carryover_amount_cny::text,
    adjustment_amount_cny::text,summary_sha256,preview_sha256),E'\n'
    ORDER BY id::text)||E'\n','UTF8')),'hex') AS locked_joint_manifest_sha256,
  encode(sha256(convert_to(string_agg(concat_ws('|',id::text,
    summary_sha256,preview_sha256),E'\n' ORDER BY id::text)||E'\n','UTF8')),'hex')
    AS locked_reader_baseline_sha256
FROM locked_current;

SELECT
  (SELECT count(*) FROM public.school_lesson_records) AS all_lesson_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE app_type='school') AS school_lesson_count,
  (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(NULL,NULL))
    AS classified_school_lesson_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE app_type='school' AND lesson_type='planned'
     AND billing_month_source IN ('approved_r1c_a_manifest','approved_r1c_c_b_manifest'))
    AS fixed_candidate_planned_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE app_type='school' AND lesson_type='planned'
     AND billing_month_source IN ('scheduled_date_at_create','explicit_billing_week_at_create'))
    AS post_cutover_planned_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE app_type='school' AND lesson_type='actual'
     AND NOT EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
                     WHERE e.actual_lesson_id=school_lesson_records.id))
    AS post_cutover_actual_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE app_type='school' AND lesson_type='planned'
     AND num_nonnulls(billing_month,billing_week_start_date,
       student_settlement_month,billing_month_source,billing_month_decided_at)
       BETWEEN 1 AND 4) AS partial_bundle_count;

SELECT
  (SELECT count(*) FROM public.school_feature_gates
   WHERE feature_key='student_tuition_preview' AND state='validation_preview_only')
    AS r0_preview_gate_count,
  (SELECT count(*) FROM public.school_feature_gates
   WHERE feature_key='student_tuition_generate' AND state='blocked')
    AS r0_generate_gate_count,
  (SELECT count(*) FROM public.school_feature_gates
   WHERE feature_key='student_tuition_cash_submit' AND state='blocked')
    AS r0_cash_submit_gate_count,
  (SELECT count(*) FROM public.school_student_tuition_bills) AS bill_count,
  (SELECT count(*) FROM public.school_income_records) AS income_count,
  (SELECT count(*) FROM public.school_student_tuition_bill_lessons)
    AS bill_lesson_count,
  (SELECT count(*) FROM public.school_student_tuition_historical_lesson_exclusions)
    AS historical_exclusion_count,
  (SELECT count(*) FROM public.school_lesson_records a
   JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
   WHERE a.app_type='school' AND a.lesson_type='actual'
     AND a.duration_hours>p.duration_hours) AS historical_overage_count,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE num_nonnulls(student_duration_overage_minutes,
     student_duration_overage_fee_jpy,student_duration_overage_policy_version,
     student_duration_overage_source,student_duration_overage_decided_at)>0)
    AS populated_overage_field_count,
  (SELECT count(*) FROM public.school_lesson_venues)
   +(SELECT count(*) FROM public.school_student_aircon_rates)
   +(SELECT count(*) FROM public.school_planned_writer_commands)
   +(SELECT count(*) FROM public.school_venue_rate_change_audit)
    AS aircon_config_row_count;

SELECT true AS r1d_e_d_joint_readonly_acceptance_pass;

ROLLBACK;
