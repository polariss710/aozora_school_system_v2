-- School V2 tuition P0 R1D-E-B2: authoritative actual student settlement month cutover.
-- Required psql variable: r1d_e_b2_commit=0 for rehearsal or 1 for deployment.
-- The evidence seed, writer replacement, and direct-table invariant are one transaction.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_e_b2_commit}
\else
  \echo 'R1D_E_B2_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '240s';

-- Prevent an actual row from crossing the evidence/writer boundary while the
-- cutover snapshot and trigger are installed.
LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
  v_actual_count bigint;
  v_actual_hash text;
  v_settlement_count bigint;
  v_settlement_hash text;
BEGIN
  IF to_regclass('public.school_legacy_actual_settlement_evidence') IS NOT NULL
     OR to_regprocedure('public.school_guard_r1d_e_b2_actual_evidence_immutable()') IS NOT NULL
     OR to_regprocedure('public.school_resolve_r1d_e_b2_actual_student_month(uuid)') IS NOT NULL
     OR to_regprocedure('public.school_enforce_r1d_e_b2_actual_attribution()') IS NOT NULL
     OR to_regprocedure('public.school_r1d_e_b2_actual_writer_cutover_version()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger
                WHERE tgrelid='public.school_lesson_records'::regclass
                  AND tgname='trg_school_lesson_r1d_e_b2_actual_attribution') THEN
    RAISE EXCEPTION 'R1D_E_B2_TARGET_OBJECT_ALREADY_EXISTS';
  END IF;

  IF public.school_r1d_f1_planned_attribution_cutover_version()
       <> 'r1d_f1_planned_attribution_v1'
     OR to_regprocedure('public.school_enforce_r1d_f1_planned_attribution()') IS NULL
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_lesson_records'::regclass
           AND tgname='trg_school_lesson_r1d_f1_planned_attribution'
           AND NOT tgisinternal AND tgenabled='O') <> 1 THEN
    RAISE EXCEPTION 'R1D_E_B2_F1_NOT_AUTHORITATIVE';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked')) <> 3
     OR md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' THEN
    RAISE EXCEPTION 'R1D_E_B2_R0_OR_CANDIDATE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type='planned'
        AND num_nonnulls(billing_month,billing_week_start_date,
          student_settlement_month,billing_month_source,billing_month_decided_at)=0) <> 279
     OR (SELECT md5(string_agg(id::text,',' ORDER BY id::text))
         FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)=0)
        <> '0975fdc91b533680e5ccc909f076ac62'
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND num_nonnulls(billing_month,billing_week_start_date,
             student_settlement_month,billing_month_source,billing_month_decided_at)
             BETWEEN 1 AND 4) <> 0
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE lesson_type='planned'
           AND billing_month_source IN (
             'approved_r1c_a_manifest','approved_r1c_c_b_manifest')) <> 118 THEN
    RAISE EXCEPTION 'R1D_E_B2_PLANNED_118_279_0_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',planned_lesson_id::text,
           coalesce(student_id_snapshot::text,'<NULL>'),
           coalesce(business_entity_id_snapshot::text,'<NULL>'),
           legacy_student_settlement_month,'planned','school'),E'\n'
           ORDER BY planned_lesson_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_planned_settlement_evidence)
        <> '34f75d8135a230ee544cc3ca050ed5a39ea9cb542b825155fb14939c66973627'
     OR (SELECT count(*) FROM public.school_legacy_settlement_snapshot_basis_evidence) <> 15
     OR (SELECT encode(sha256(convert_to(string_agg(concat_ws('|',settlement_snapshot_id::text,
           student_id_snapshot::text,business_entity_id_snapshot::text,
           settlement_month_snapshot,settlement_status_snapshot,lesson_count::text,
           planned_lesson_count::text,actual_lesson_count::text,lesson_uuid_md5,
           amount_basis_md5,settlement_structure_md5),E'\n'
           ORDER BY settlement_snapshot_id::text)||E'\n','UTF8')),'hex')
         FROM public.school_legacy_settlement_snapshot_basis_evidence)
        <> '68b3b73007e6962071fdc85e621b0d57848d1909b24203b5c28d0741a324cb26' THEN
    RAISE EXCEPTION 'R1D_E_B2_E_B1_EVIDENCE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE lesson_type='actual') = 0
     OR EXISTS (SELECT 1 FROM public.school_lesson_records
                WHERE lesson_type='actual'
                  AND (app_type<>'school' OR planned_lesson_id IS NULL
                    OR student_settlement_month IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.school_lesson_records a
                LEFT JOIN public.school_lesson_records p ON p.id=a.planned_lesson_id
                WHERE a.lesson_type='actual'
                  AND (p.id IS NULL OR p.lesson_type<>'planned' OR p.app_type<>'school')) THEN
    RAISE EXCEPTION 'R1D_E_B2_EXISTING_ACTUAL_BOUNDARY_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(student_duration_overage_minutes,
        student_duration_overage_fee_jpy,student_duration_overage_policy_version,
        student_duration_overage_source,student_duration_overage_decided_at)>0) <> 0 THEN
    RAISE EXCEPTION 'R1D_E_B2_OVERAGE_FIELDS_CHANGED';
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
  IF v_actual_count<>8 OR v_actual_hash<>'4986090e0ba4e4706ea9ca4abd9580c5'
     OR md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))<>'da156f6c951b233a2878ecb100b2748b'
     OR position('v_duration_hours <> v_planned.duration_hours' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTUAL_WRITER_BASELINE_CHANGED';
  END IF;

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
    RAISE EXCEPTION 'R1D_E_B2_SETTLEMENT_READER_CHANGED';
  END IF;
END
$preflight$;

CREATE TABLE public.school_legacy_actual_settlement_evidence (
  actual_lesson_id uuid PRIMARY KEY
    REFERENCES public.school_lesson_records(id) ON DELETE RESTRICT,
  source_planned_lesson_id uuid NOT NULL
    REFERENCES public.school_lesson_records(id) ON DELETE RESTRICT,
  student_id_snapshot uuid NOT NULL,
  business_entity_id_snapshot uuid NOT NULL,
  teacher_id_snapshot uuid,
  subject_id_snapshot uuid,
  legacy_year_month text NOT NULL,
  teacher_settlement_month_snapshot text NOT NULL,
  lesson_date_snapshot date NOT NULL,
  actual_identity_md5 text NOT NULL,
  actual_full_row_md5 text NOT NULL,
  cutover_actual_count bigint NOT NULL,
  cutover_actual_uuid_md5 text NOT NULL,
  cutover_identity_manifest_sha256 text NOT NULL,
  cutover_full_row_manifest_sha256 text NOT NULL,
  evidence_source text NOT NULL DEFAULT 'r1d_e_b2_all_existing_actual_at_cutover',
  evidence_version text NOT NULL DEFAULT 'actual_legacy_settlement_evidence_v1',
  recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT school_legacy_actual_month_chk
    CHECK (legacy_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
      AND teacher_settlement_month_snapshot ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT school_legacy_actual_md5_chk
    CHECK (actual_identity_md5 ~ '^[0-9a-f]{32}$'
      AND actual_full_row_md5 ~ '^[0-9a-f]{32}$'
      AND cutover_actual_uuid_md5 ~ '^[0-9a-f]{32}$'),
  CONSTRAINT school_legacy_actual_sha_chk
    CHECK (cutover_identity_manifest_sha256 ~ '^[0-9a-f]{64}$'
      AND cutover_full_row_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT school_legacy_actual_count_chk CHECK (cutover_actual_count>0),
  CONSTRAINT school_legacy_actual_source_chk
    CHECK (evidence_source='r1d_e_b2_all_existing_actual_at_cutover'),
  CONSTRAINT school_legacy_actual_version_chk
    CHECK (evidence_version='actual_legacy_settlement_evidence_v1')
);

COMMENT ON TABLE public.school_legacy_actual_settlement_evidence IS
  'R1D-E-B2 immutable evidence for every actual row existing at the atomic writer cutover. It is not a created_at heuristic and never accepts later actual rows.';

WITH evidence_rows AS (
  SELECT a.id AS actual_lesson_id,a.planned_lesson_id AS source_planned_lesson_id,
    a.student_id AS student_id_snapshot,a.business_entity_id AS business_entity_id_snapshot,
    a.teacher_id AS teacher_id_snapshot,a.subject_id AS subject_id_snapshot,
    a.year_month AS legacy_year_month,
    coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM'))
      AS teacher_settlement_month_snapshot,
    a.lesson_date AS lesson_date_snapshot,
    md5(concat_ws('|',a.id::text,a.planned_lesson_id::text,a.student_id::text,
      a.business_entity_id::text,coalesce(a.teacher_id::text,'<NULL>'),
      coalesce(a.subject_id::text,'<NULL>'),a.year_month,
      coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM')),
      a.lesson_date::text,a.lesson_type,a.app_type)) AS actual_identity_md5,
    md5(to_jsonb(a)::text) AS actual_full_row_md5
  FROM public.school_lesson_records a
  WHERE a.lesson_type='actual' AND a.app_type='school'
), manifest AS (
  SELECT count(*) AS actual_count,
    md5(string_agg(actual_lesson_id::text,',' ORDER BY actual_lesson_id::text)) AS uuid_md5,
    encode(sha256(convert_to(string_agg(concat_ws('|',actual_lesson_id::text,
      actual_identity_md5),E'\n' ORDER BY actual_lesson_id::text)||E'\n','UTF8')),'hex')
      AS identity_sha,
    encode(sha256(convert_to(string_agg(concat_ws('|',actual_lesson_id::text,
      actual_full_row_md5),E'\n' ORDER BY actual_lesson_id::text)||E'\n','UTF8')),'hex')
      AS full_row_sha
  FROM evidence_rows
)
INSERT INTO public.school_legacy_actual_settlement_evidence (
  actual_lesson_id,source_planned_lesson_id,student_id_snapshot,
  business_entity_id_snapshot,teacher_id_snapshot,subject_id_snapshot,
  legacy_year_month,teacher_settlement_month_snapshot,lesson_date_snapshot,
  actual_identity_md5,actual_full_row_md5,cutover_actual_count,
  cutover_actual_uuid_md5,cutover_identity_manifest_sha256,
  cutover_full_row_manifest_sha256
)
SELECT e.actual_lesson_id,e.source_planned_lesson_id,e.student_id_snapshot,
  e.business_entity_id_snapshot,e.teacher_id_snapshot,e.subject_id_snapshot,
  e.legacy_year_month,e.teacher_settlement_month_snapshot,e.lesson_date_snapshot,
  e.actual_identity_md5,e.actual_full_row_md5,m.actual_count,m.uuid_md5,
  m.identity_sha,m.full_row_sha
FROM evidence_rows e CROSS JOIN manifest m;

CREATE FUNCTION public.school_guard_r1d_e_b2_actual_evidence_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION 'R1D_E_B2_ACTUAL_EVIDENCE_IMMUTABLE: % is forbidden',TG_OP;
END
$function$;

REVOKE ALL ON FUNCTION public.school_guard_r1d_e_b2_actual_evidence_immutable()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_school_legacy_actual_evidence_row_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.school_legacy_actual_settlement_evidence
FOR EACH ROW EXECUTE FUNCTION public.school_guard_r1d_e_b2_actual_evidence_immutable();
CREATE TRIGGER trg_school_legacy_actual_evidence_truncate_immutable
BEFORE TRUNCATE ON public.school_legacy_actual_settlement_evidence
FOR EACH STATEMENT EXECUTE FUNCTION public.school_guard_r1d_e_b2_actual_evidence_immutable();

ALTER TABLE public.school_legacy_actual_settlement_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_legacy_actual_settlement_evidence FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.school_legacy_actual_settlement_evidence
  FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE public.school_legacy_actual_settlement_evidence TO service_role;

CREATE FUNCTION public.school_r1d_e_b2_actual_writer_cutover_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path=pg_catalog
AS $function$
  SELECT 'r1d_e_b2_actual_writer_v1'::text
$function$;
REVOKE ALL ON FUNCTION public.school_r1d_e_b2_actual_writer_cutover_version()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.school_resolve_r1d_e_b2_actual_student_month(
  p_planned_lesson_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_source public.school_lesson_records%ROWTYPE;
  v_evidence public.school_legacy_planned_settlement_evidence%ROWTYPE;
BEGIN
  IF p_planned_lesson_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_REQUIRED';
  END IF;

  SELECT p.* INTO v_source
  FROM public.school_lesson_records p
  WHERE p.id=p_planned_lesson_id;
  IF NOT FOUND OR v_source.app_type<>'school' OR v_source.lesson_type<>'planned'
     OR v_source.voided_at IS NOT NULL
     OR v_source.status NOT IN ('planned','pending_makeup','makeup_completed')
     OR v_source.student_id IS NULL OR v_source.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_INVALID';
  END IF;

  IF num_nonnulls(v_source.billing_month,v_source.billing_week_start_date,
       v_source.student_settlement_month,v_source.billing_month_source,
       v_source.billing_month_decided_at)=5 THEN
    IF v_source.student_settlement_month IS DISTINCT FROM v_source.billing_month
       OR v_source.billing_month_source NOT IN (
         'approved_r1c_a_manifest','approved_r1c_c_b_manifest',
         'scheduled_date_at_create','explicit_billing_week_at_create')
       OR extract(isodow FROM v_source.billing_week_start_date)<>1
       OR to_char(v_source.billing_week_start_date,'YYYY-MM')<>v_source.billing_month THEN
      RAISE EXCEPTION 'R1D_E_B2_CANONICAL_SOURCE_ATTRIBUTION_INVALID';
    END IF;
    RETURN v_source.student_settlement_month;
  END IF;

  IF num_nonnulls(v_source.billing_month,v_source.billing_week_start_date,
       v_source.student_settlement_month,v_source.billing_month_source,
       v_source.billing_month_decided_at)=0 THEN
    SELECT e.* INTO v_evidence
    FROM public.school_legacy_planned_settlement_evidence e
    WHERE e.planned_lesson_id=v_source.id;
    IF NOT FOUND OR v_evidence.approved_manifest IS DISTINCT FROM true
       OR v_evidence.evidence_source<>'r1d_e_b1_fixed_legacy_279'
       OR v_evidence.evidence_version<>'legacy_settlement_evidence_v1'
       OR v_source.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR v_source.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR v_source.year_month IS DISTINCT FROM v_evidence.legacy_student_settlement_month
       OR v_evidence.lesson_identity_md5 IS DISTINCT FROM md5(concat_ws('|',
         v_source.id::text,coalesce(v_source.student_id::text,'<NULL>'),
         coalesce(v_source.business_entity_id::text,'<NULL>'),
         coalesce(v_source.year_month,'<NULL>'),v_source.lesson_type,v_source.app_type)) THEN
      RAISE EXCEPTION 'R1D_E_B2_LEGACY_SOURCE_EVIDENCE_MISMATCH';
    END IF;
    RETURN v_evidence.legacy_student_settlement_month;
  END IF;

  RAISE EXCEPTION 'R1D_E_B2_PARTIAL_SOURCE_ATTRIBUTION_REJECTED';
END
$function$;

REVOKE ALL ON FUNCTION public.school_resolve_r1d_e_b2_actual_student_month(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.school_enforce_r1d_e_b2_actual_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $function$
DECLARE
  v_source public.school_lesson_records%ROWTYPE;
  v_evidence public.school_legacy_actual_settlement_evidence%ROWTYPE;
  v_student_month text;
  v_old_teacher_month text;
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
    SELECT p.* INTO v_source FROM public.school_lesson_records p
    WHERE p.id=NEW.planned_lesson_id;
    IF NOT FOUND OR v_source.status NOT IN ('planned','pending_makeup') THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STATUS_INVALID';
    END IF;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(
      NEW.planned_lesson_id);
    IF NEW.student_id IS DISTINCT FROM v_source.student_id
       OR NEW.business_entity_id IS DISTINCT FROM v_source.business_entity_id THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_MISMATCH';
    END IF;
    IF num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
         NEW.billing_month_source,NEW.billing_month_decided_at)<>0 THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_BILLING_BUNDLE_FORBIDDEN';
    END IF;

    NEW.student_settlement_month:=v_student_month;
    NEW.year_month:=v_student_month;
    NEW.teacher_settlement_month:=to_char(NEW.lesson_date,'YYYY-MM');

    IF EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
               WHERE s.student_id=NEW.student_id
                 AND s.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                 AND s.year_month=v_student_month AND s.settlement_status='locked') THEN
      RAISE EXCEPTION 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
    END IF;
    IF EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
               WHERE w.teacher_id=NEW.teacher_id
                 AND w.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                 AND w.settlement_month=NEW.teacher_settlement_month
                 AND w.status='locked') THEN
      RAISE EXCEPTION 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
    END IF;
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
     OR NEW.planned_lesson_id IS DISTINCT FROM OLD.planned_lesson_id
     OR NEW.student_id IS DISTINCT FROM OLD.student_id
     OR NEW.business_entity_id IS DISTINCT FROM OLD.business_entity_id THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE';
  END IF;

  SELECT e.* INTO v_evidence
  FROM public.school_legacy_actual_settlement_evidence e
  WHERE e.actual_lesson_id=OLD.id;

  IF FOUND THEN
    IF OLD.student_settlement_month IS NOT NULL OR NEW.student_settlement_month IS NOT NULL
       OR NEW.planned_lesson_id IS DISTINCT FROM v_evidence.source_planned_lesson_id
       OR NEW.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR NEW.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR NEW.teacher_id IS DISTINCT FROM v_evidence.teacher_id_snapshot
       OR NEW.subject_id IS DISTINCT FROM v_evidence.subject_id_snapshot
       OR NEW.year_month IS DISTINCT FROM v_evidence.legacy_year_month
       OR NEW.teacher_settlement_month IS DISTINCT FROM
          v_evidence.teacher_settlement_month_snapshot
       OR NEW.lesson_date IS DISTINCT FROM v_evidence.lesson_date_snapshot
       OR md5(concat_ws('|',NEW.id::text,NEW.planned_lesson_id::text,
          NEW.student_id::text,NEW.business_entity_id::text,
          coalesce(NEW.teacher_id::text,'<NULL>'),coalesce(NEW.subject_id::text,'<NULL>'),
          NEW.year_month,NEW.teacher_settlement_month,NEW.lesson_date::text,
          NEW.lesson_type,NEW.app_type)) IS DISTINCT FROM v_evidence.actual_identity_md5 THEN
      RAISE EXCEPTION 'R1D_E_B2_LEGACY_ACTUAL_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF (to_jsonb(NEW)-ARRAY['note','lesson_content','lesson_delivery_mode',
          'lesson_venue','updated_at']) IS DISTINCT FROM
       (to_jsonb(OLD)-ARRAY['note','lesson_content','lesson_delivery_mode',
          'lesson_venue','updated_at']) THEN
      RAISE EXCEPTION 'R1D_E_B2_LEGACY_ACTUAL_ONLY_NONATTRIBUTION_CONTENT_EDIT_ALLOWED';
    END IF;
    v_student_month:=v_evidence.legacy_year_month;
    v_old_teacher_month:=v_evidence.teacher_settlement_month_snapshot;
    v_new_teacher_month:=v_old_teacher_month;
  ELSE
    IF OLD.student_settlement_month IS NULL
       OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
       OR num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
            NEW.billing_month_source,NEW.billing_month_decided_at)<>0 THEN
      RAISE EXCEPTION 'R1D_E_B2_CANONICAL_ACTUAL_STUDENT_MONTH_IMMUTABLE';
    END IF;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(
      OLD.planned_lesson_id);
    IF v_student_month IS DISTINCT FROM OLD.student_settlement_month THEN
      RAISE EXCEPTION 'R1D_E_B2_CANONICAL_ACTUAL_SOURCE_MONTH_DRIFT';
    END IF;
    NEW.year_month:=OLD.student_settlement_month;
    NEW.teacher_settlement_month:=to_char(NEW.lesson_date,'YYYY-MM');
    v_old_teacher_month:=OLD.teacher_settlement_month;
    v_new_teacher_month:=NEW.teacher_settlement_month;
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
             WHERE s.student_id=OLD.student_id
               AND s.business_entity_id IS NOT DISTINCT FROM OLD.business_entity_id
               AND s.year_month=v_student_month AND s.settlement_status='locked') THEN
    RAISE EXCEPTION 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details d
             JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
             WHERE d.lesson_record_id=OLD.id AND w.status='locked'
               AND w.voided_at IS NULL) THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTIVE_WAGE_DETAIL_LOCKED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
             WHERE w.teacher_id=OLD.teacher_id
               AND w.business_entity_id IS NOT DISTINCT FROM OLD.business_entity_id
               AND w.settlement_month=v_old_teacher_month AND w.status='locked')
     OR EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
                WHERE w.teacher_id=NEW.teacher_id
                  AND w.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                  AND w.settlement_month=v_new_teacher_month AND w.status='locked') THEN
    RAISE EXCEPTION 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.school_enforce_r1d_e_b2_actual_attribution()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution
BEFORE INSERT OR UPDATE ON public.school_lesson_records
FOR EACH ROW EXECUTE FUNCTION public.school_enforce_r1d_e_b2_actual_attribution();

COMMENT ON TRIGGER trg_school_lesson_r1d_e_b2_actual_attribution
ON public.school_lesson_records IS
  'R1D-E-B2: authoritative student month inherited from classified source planned; teacher month follows actual date; legacy actual evidence remains null and frozen.';

CREATE OR REPLACE FUNCTION public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,
  p_lesson_date date,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_lesson_content text,
  p_note text DEFAULT NULL,
  p_lesson_count integer DEFAULT NULL,
  p_lesson_delivery_mode text DEFAULT NULL,
  p_lesson_venue text DEFAULT NULL
)
RETURNS SETOF public.school_lesson_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  v_planned public.school_lesson_records%ROWTYPE;
  v_student_settlement_month text;
  v_teacher_settlement_month text;
  v_remaining_hours numeric;
  v_actual_id uuid;
  v_teacher_id uuid;
  v_subject_id uuid;
  v_content text;
  v_note text;
  v_start_time text;
  v_end_time text;
  v_delivery_mode text;
  v_venue text;
BEGIN
  IF p_planned_lesson_id IS NULL THEN
    RAISE EXCEPTION '请选择待补课来源。';
  END IF;
  SELECT p.* INTO v_planned
  FROM public.school_lesson_records p
  WHERE p.id=p_planned_lesson_id
    AND p.app_type='school' AND p.lesson_type='planned'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '待补课来源不存在。';
  END IF;
  IF v_planned.voided_at IS NOT NULL THEN
    RAISE EXCEPTION '待补课来源已作废。';
  END IF;
  IF v_planned.status<>'pending_makeup' THEN
    RAISE EXCEPTION '只有待补课预定课时可以使用课时余额。';
  END IF;
  IF v_planned.student_id IS NULL OR v_planned.business_entity_id IS NULL THEN
    RAISE EXCEPTION '待补课来源缺少学生或业务归属。';
  END IF;

  SELECT public.school_get_lesson_credit_remaining_hours(v_planned.id)
  INTO v_remaining_hours;
  p_duration_hours:=coalesce(p_duration_hours,v_remaining_hours);
  IF p_duration_hours IS NULL OR p_duration_hours<=0 THEN
    RAISE EXCEPTION '补课完成时长必须大于 0。';
  END IF;
  IF coalesce(v_remaining_hours,0)<=0 THEN
    RAISE EXCEPTION '该待补课来源已无剩余课时。';
  END IF;
  IF p_duration_hours>v_remaining_hours THEN
    RAISE EXCEPTION '补课时长超过剩余课时：剩余 % 小时。',v_remaining_hours;
  END IF;

  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  v_teacher_id:=coalesce(p_teacher_id,v_planned.teacher_id);
  v_subject_id:=coalesce(p_subject_id,v_planned.subject_id);
  v_start_time:=coalesce(nullif(trim(coalesce(p_start_time,'')),''),v_planned.start_time);
  v_end_time:=coalesce(nullif(trim(coalesce(p_end_time,'')),''),v_planned.end_time);
  v_content:=coalesce(nullif(trim(coalesce(p_lesson_content,'')),''),v_planned.lesson_content);
  v_note:=nullif(trim(coalesce(p_note,'')),'');
  v_delivery_mode:=coalesce(nullif(trim(coalesce(p_lesson_delivery_mode,'')),''),
    v_planned.lesson_delivery_mode);
  v_venue:=coalesce(nullif(trim(coalesce(p_lesson_venue,'')),''),v_planned.lesson_venue);

  IF v_teacher_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.school_teachers t
    WHERE t.id=v_teacher_id AND t.app_type='school'
      AND coalesce(t.status,'employed') NOT IN ('inactive','retired')) THEN
    RAISE EXCEPTION '请选择有效老师。';
  END IF;
  IF v_subject_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.school_subjects s
    WHERE s.id=v_subject_id AND coalesce(s.is_active,true)) THEN
    RAISE EXCEPTION '请选择有效科目。';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_business_entities b
    WHERE b.id=v_planned.business_entity_id AND coalesce(b.is_active,true)) THEN
    RAISE EXCEPTION '来源业务归属无效。';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_students s
    WHERE s.id=v_planned.student_id AND s.app_type='school'
      AND coalesce(s.status,'active') NOT IN ('inactive','graduated')
      AND (s.business_entity_id IS NULL
        OR s.business_entity_id=v_planned.business_entity_id)) THEN
    RAISE EXCEPTION '来源学生无效或业务归属不一致。';
  END IF;
  IF v_start_time IS NULL
     OR v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION '开始时间必填且必须为 HH:MM。';
  END IF;
  IF v_end_time IS NULL
     OR v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION '结束时间必填且必须为 HH:MM。';
  END IF;
  IF v_end_time::time<=v_start_time::time THEN
    RAISE EXCEPTION '结束时间必须晚于开始时间。';
  END IF;
  IF v_content IS NULL THEN
    RAISE EXCEPTION '补课内容必填。';
  END IF;
  IF v_delivery_mode NOT IN ('online','onsite') THEN
    RAISE EXCEPTION '授课方式必须为 online 或 onsite。';
  END IF;
  IF v_delivery_mode='onsite' AND v_venue NOT IN ('Regus公共区','Regus办公室') THEN
    RAISE EXCEPTION '线下补课场地只能为 Regus公共区 或 Regus办公室。请先在来源课时补齐场地。';
  END IF;
  IF p_lesson_count IS NOT NULL AND p_lesson_count<=0 THEN
    RAISE EXCEPTION '课次数必须大于 0。';
  END IF;

  v_student_settlement_month:=
    public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
  v_teacher_settlement_month:=to_char(p_lesson_date,'YYYY-MM');
  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements s
    WHERE s.student_id=v_planned.student_id
      AND s.year_month=v_student_settlement_month
      AND s.business_entity_id IS NOT DISTINCT FROM v_planned.business_entity_id
      AND s.settlement_status='locked') THEN
    RAISE EXCEPTION '补课来源学生月度结算已锁定。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_teacher_wage_locks w
    WHERE w.teacher_id=v_teacher_id
      AND w.business_entity_id IS NOT DISTINCT FROM v_planned.business_entity_id
      AND w.settlement_month=v_teacher_settlement_month
      AND w.status='locked') THEN
    RAISE EXCEPTION '补课老师的目标工资月份已锁定。';
  END IF;

  INSERT INTO public.school_lesson_records (
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,planned_lesson_id,unit_price,
    lesson_fee,lesson_count,actual_minutes,teacher_settlement_month,
    lesson_delivery_mode,lesson_venue,student_settlement_month
  ) VALUES (
    'actual',p_lesson_date,v_student_settlement_month,v_planned.student_id,
    v_teacher_id,v_subject_id,v_planned.business_entity_id,v_start_time,
    v_end_time,p_duration_hours,v_content,'makeup_completed',false,
    v_note,'school',v_planned.id,coalesce(v_planned.unit_price,0),0,
    coalesce(p_lesson_count,v_planned.lesson_count),
    round(p_duration_hours*60)::integer,v_teacher_settlement_month,
    v_delivery_mode,v_venue,v_student_settlement_month
  ) RETURNING id INTO v_actual_id;

  IF public.school_get_lesson_credit_remaining_hours(v_planned.id)<=0 THEN
    UPDATE public.school_lesson_records SET status='makeup_completed'
    WHERE id=v_planned.id;
  END IF;

  RETURN QUERY SELECT a.* FROM public.school_lesson_records a
  WHERE a.id=v_actual_id;
END
$function$;

COMMENT ON FUNCTION public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) IS
  'R1D-E-B2 canonical makeup writer. Student month is DB-resolved from the original planned source; teacher month follows actual date; remaining-credit and non-billable rules are unchanged.';

-- Preserve the complete, currently deployed guarded updater while replacing
-- only its two student-month assignments. The exact source MD5 is preflighted;
-- both the expected old fragment and the new marker are checked before DDL.
DO $replace_guarded_update$
DECLARE
  v_definition text;
  v_replaced text;
  v_old_fragment text := $old$
  v_year_month := to_char(p_lesson_date, 'YYYY-MM');
  v_old_year_month := coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'));
$old$;
  v_new_fragment text := $new$
  if v_lesson.lesson_type = 'actual' then
    select e.legacy_year_month
    into v_old_year_month
    from public.school_legacy_actual_settlement_evidence e
    where e.actual_lesson_id = v_lesson.id;
    if not found then
      v_old_year_month := v_lesson.student_settlement_month;
    end if;
    if v_old_year_month is null then
      raise exception 'R1D_E_B2_GUARDED_ACTUAL_STUDENT_MONTH_UNCLASSIFIED';
    end if;
    v_year_month := v_old_year_month;
  else
    v_year_month := to_char(p_lesson_date, 'YYYY-MM');
    v_old_year_month := coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'));
  end if;
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)<>'4721315f96a96c47b2751c5cc75b5843'
     OR position(v_old_fragment IN v_definition)=0 THEN
    RAISE EXCEPTION 'R1D_E_B2_GUARDED_UPDATE_SOURCE_FRAGMENT_CHANGED';
  END IF;
  v_replaced:=replace(v_definition,v_old_fragment,v_new_fragment);
  IF v_replaced=v_definition
     OR position('R1D_E_B2_GUARDED_ACTUAL_STUDENT_MONTH_UNCLASSIFIED'
          IN v_replaced)=0
     OR position(v_old_fragment IN v_replaced)>0 THEN
    RAISE EXCEPTION 'R1D_E_B2_GUARDED_UPDATE_REPLACEMENT_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace_guarded_update$;

COMMENT ON FUNCTION public.school_update_lesson_record_guarded(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text
) IS
  'R1D-E-B2 guarded lesson updater. Canonical actual keeps its student month/year_month while actual date changes only teacher month; legacy actual uses immutable cutover evidence and the table invariant fails closed.';

DO $verify$
DECLARE
  v_manifest record;
  v_actual_count bigint;
  v_actual_hash text;
BEGIN
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
     OR v_manifest.actual_count<>(SELECT count(*) FROM public.school_lesson_records
                                  WHERE lesson_type='actual' AND app_type='school')
     OR v_manifest.actual_count<>(SELECT count(*)
           FROM public.school_legacy_actual_settlement_evidence)
     OR v_manifest.uuid_md5<>(SELECT md5(string_agg(id::text,',' ORDER BY id::text))
           FROM public.school_lesson_records
           WHERE lesson_type='actual' AND app_type='school')
     OR EXISTS (
       SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
       JOIN public.school_lesson_records a ON a.id=e.actual_lesson_id
       WHERE a.student_settlement_month IS NOT NULL
          OR e.source_planned_lesson_id IS DISTINCT FROM a.planned_lesson_id
          OR e.student_id_snapshot IS DISTINCT FROM a.student_id
          OR e.business_entity_id_snapshot IS DISTINCT FROM a.business_entity_id
          OR e.teacher_id_snapshot IS DISTINCT FROM a.teacher_id
          OR e.subject_id_snapshot IS DISTINCT FROM a.subject_id
          OR e.legacy_year_month IS DISTINCT FROM a.year_month
          OR e.teacher_settlement_month_snapshot IS DISTINCT FROM
             coalesce(a.teacher_settlement_month,to_char(a.lesson_date,'YYYY-MM'))
          OR e.lesson_date_snapshot IS DISTINCT FROM a.lesson_date
          OR e.actual_full_row_md5 IS DISTINCT FROM md5(to_jsonb(a)::text)) THEN
    RAISE EXCEPTION 'R1D_E_B2_EVIDENCE_OR_EXISTING_ACTUAL_VERIFY_FAILED';
  END IF;

  IF to_regprocedure('public.school_r1d_e_b2_actual_writer_cutover_version()') IS NULL
     OR public.school_r1d_e_b2_actual_writer_cutover_version()
          <>'r1d_e_b2_actual_writer_v1'
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_lesson_records'::regclass
           AND tgname='trg_school_lesson_r1d_e_b2_actual_attribution'
           AND NOT tgisinternal AND tgenabled='O')<>1
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_legacy_actual_settlement_evidence'::regclass
           AND NOT tgisinternal AND tgenabled='O')<>2
     OR position('R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE' IN pg_get_functiondef(
          'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR position('R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED' IN pg_get_functiondef(
          'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure))=0
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity
             FROM pg_class WHERE oid=
               'public.school_legacy_actual_settlement_evidence'::regclass) THEN
    RAISE EXCEPTION 'R1D_E_B2_OBJECT_VERIFY_FAILED';
  END IF;

  IF NOT has_table_privilege('service_role',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_table_privilege('service_role',
       'public.school_legacy_actual_settlement_evidence','INSERT,UPDATE,DELETE,TRUNCATE')
     OR has_table_privilege('anon',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_table_privilege('authenticated',
       'public.school_legacy_actual_settlement_evidence','SELECT')
     OR has_function_privilege('service_role',
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)','EXECUTE')
     OR has_function_privilege('authenticated',
       'public.school_r1d_e_b2_actual_writer_cutover_version()','EXECUTE') THEN
    RAISE EXCEPTION 'R1D_E_B2_PRIVILEGE_VERIFY_FAILED';
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
  IF v_actual_count<>8
     OR position('v_duration_hours <> v_planned.duration_hours' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_create_lesson_credit_makeup_actual' IN pg_get_functiondef(
       'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure))=0
     OR position('school_update_lesson_record_guarded' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'R1D_E_B2_WRITER_OR_WRAPPER_VERIFY_FAILED';
  END IF;

  RAISE NOTICE 'R1D_E_B2_CUTOVER_ACTUAL_COUNT=%',v_manifest.actual_count;
  RAISE NOTICE 'R1D_E_B2_CUTOVER_ACTUAL_UUID_MD5=%',v_manifest.uuid_md5;
  RAISE NOTICE 'R1D_E_B2_CUTOVER_IDENTITY_SHA256=%',v_manifest.identity_sha;
  RAISE NOTICE 'R1D_E_B2_CUTOVER_FULL_ROW_SHA256=%',v_manifest.full_row_sha;
  RAISE NOTICE 'R1D_E_B2_ACTUAL_WRITER_GROUP_MD5=%',v_actual_hash;
END
$verify$;

SELECT public.school_r1d_e_b2_actual_writer_cutover_version() AS cutover_version,
  (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)
    AS legacy_actual_evidence_rows,
  true AS existing_actual_rows_unchanged,
  true AS ordinary_duration_equality_guard_present;

\if :r1d_e_b2_commit
  COMMIT;
  \echo 'R1D_E_B2_DEPLOYMENT_COMMITTED'
\else
  \echo 'R1D_E_B2_REHEARSAL_TRANSACTION_OPEN'
\endif
