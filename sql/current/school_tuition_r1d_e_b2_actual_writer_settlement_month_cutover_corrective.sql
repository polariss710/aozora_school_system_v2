-- School V2 tuition P0 R1D-E-B2 minimal corrective.
-- Closes UPDATE actual -> planned/non-school bypass only. Never seeds evidence.
-- Required psql variable: r1d_e_b2_corrective_commit=0 rehearsal or 1 deploy.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_b2_corrective_commit}
\else
  \echo 'R1D_E_B2_CORRECTIVE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
  v_writer_count bigint;
  v_writer_hash text;
BEGIN
  IF public.school_r1d_e_b2_actual_writer_cutover_version()
       <>'r1d_e_b2_actual_writer_v1'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     ))<>'c2a735047dd399b97cdae5bc84a7e636' THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_TRIGGER_BASELINE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR (SELECT min(cutover_actual_uuid_md5)
         FROM public.school_legacy_actual_settlement_evidence)
        <>'891eeabf9a48d1c7b00a695b21cf8e95'
     OR (SELECT min(cutover_identity_manifest_sha256)
         FROM public.school_legacy_actual_settlement_evidence)
        <>'83f9df656fc8e089ce769cac84d61338c0889ac853b2e2b544f8b2bf3678650c'
     OR (SELECT min(cutover_full_row_manifest_sha256)
         FROM public.school_legacy_actual_settlement_evidence)
        <>'dd25082aac3216cf3ba6160e3ee81f56845359aa1a603e975b864bb630d933f8'
     OR EXISTS (
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
          OR e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)
     ) THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_EVIDENCE_OR_EXISTING_ACTUAL_CHANGED';
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
      ORDER BY signature)) INTO v_writer_count,v_writer_hash FROM functions;
  IF v_writer_count<>8 OR v_writer_hash<>'046cb8c0002528634b767a046e4626ab' THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_WRITER_GROUP_CHANGED';
  END IF;
END
$preflight$;

DO $replace_trigger$
DECLARE
  v_definition text;
  v_replaced text;
  v_old_fragment text := $old$
  v_new_teacher_month text;
BEGIN
  IF NEW.lesson_type<>'actual' THEN
    RETURN NEW;
  END IF;
  IF NEW.app_type<>'school' THEN
    RAISE EXCEPTION 'R1D_E_B2_NON_SCHOOL_ACTUAL_REJECTED';
  END IF;

  IF TG_OP='INSERT' THEN
$old$;
  v_new_fragment text := $new$
  v_new_teacher_month text;
  v_has_legacy_evidence boolean;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.lesson_type<>'actual' THEN
      RETURN NEW;
    END IF;
    IF NEW.app_type<>'school' THEN
      RAISE EXCEPTION 'R1D_E_B2_NON_SCHOOL_ACTUAL_REJECTED';
    END IF;
$new$;
  v_old_update_fragment text := $old_update$
    RETURN NEW;
  END IF;

  IF OLD.lesson_type<>'actual' OR OLD.app_type<>'school'
$old_update$;
  v_new_update_fragment text := $new_update$
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
    WHERE e.actual_lesson_id=OLD.id
  ) INTO v_has_legacy_evidence;

  IF OLD.lesson_type='actual' OR v_has_legacy_evidence THEN
    IF OLD.lesson_type IS DISTINCT FROM 'actual'
       OR OLD.app_type IS DISTINCT FROM 'school'
       OR NEW.lesson_type IS DISTINCT FROM 'actual'
       OR NEW.app_type IS DISTINCT FROM 'school' THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE';
    END IF;
  ELSE
    IF NEW.lesson_type<>'actual' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED';
  END IF;

  IF OLD.lesson_type<>'actual' OR OLD.app_type<>'school'
$new_update$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)<>'c2a735047dd399b97cdae5bc84a7e636'
     OR position(v_old_fragment IN v_definition)=0
     OR position(v_old_update_fragment IN v_definition)=0 THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_SOURCE_FRAGMENT_CHANGED';
  END IF;
  v_replaced:=replace(v_definition,v_old_fragment,v_new_fragment);
  v_replaced:=replace(v_replaced,v_old_update_fragment,v_new_update_fragment);
  IF position('R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' IN v_replaced)=0
     OR position('R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED' IN v_replaced)=0
     OR position(v_old_fragment IN v_replaced)>0
     OR position(v_old_update_fragment IN v_replaced)>0 THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_REPLACEMENT_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace_trigger$;

DO $verify$
DECLARE
  v_trigger_hash text;
  v_writer_count bigint;
  v_writer_hash text;
BEGIN
  v_trigger_hash:=md5(pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure));
  IF v_trigger_hash='c2a735047dd399b97cdae5bc84a7e636'
     OR position('R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' IN pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED' IN pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR EXISTS (
       SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
       JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
       WHERE e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)
          OR a.lesson_type<>'actual' OR a.app_type<>'school'
          OR a.student_settlement_month IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_VERIFY_FAILED';
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
      ORDER BY signature)) INTO v_writer_count,v_writer_hash FROM functions;
  IF v_writer_count<>8 OR v_writer_hash<>'046cb8c0002528634b767a046e4626ab' THEN
    RAISE EXCEPTION 'R1D_E_B2_CORRECTIVE_WRITER_GROUP_VERIFY_FAILED';
  END IF;
  RAISE NOTICE 'R1D_E_B2_CORRECTIVE_TRIGGER_MD5=%',v_trigger_hash;
  RAISE NOTICE 'R1D_E_B2_CORRECTIVE_WRITER_GROUP_MD5=%',v_writer_hash;
END
$verify$;

SELECT md5(pg_get_functiondef(
    'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
  )) AS trigger_function_md5,
  true AS evidence_not_reseeded,
  true AS existing_actual_unchanged;

\if :r1d_e_b2_corrective_commit
  COMMIT;
  \echo 'R1D_E_B2_CORRECTIVE_COMMITTED'
\else
  \echo 'R1D_E_B2_CORRECTIVE_REHEARSAL_TRANSACTION_OPEN'
\endif
