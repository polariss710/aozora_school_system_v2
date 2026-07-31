-- School V2 R2-F-E1 legacy actual structured evidence correction.
-- Usage:
--   r2_f_e1_evidence_commit=0  same-byte rehearsal with explicit ROLLBACK
--   r2_f_e1_evidence_commit=1  formal code-only DDL deployment with COMMIT
-- The immutable v1 full-row hashes remain stored as historical audit evidence;
-- they are no longer used as an operational edit lock by the month resolver.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_e1_evidence_commit}
\else
  \echo 'R2_F_E1_EVIDENCE_COMMIT_VARIABLE_REQUIRED'
  \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
LOCK TABLE public.school_lesson_records IN SHARE MODE;

DO $preflight$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO STRICT v_definition;
  IF md5(v_definition)<>'88acc674f4884538863b9c2518908a4f'
     OR position('md5((to_jsonb(v_lesson)-''lesson_total_fee_jpy'')::text)' IN
          v_definition)=0 THEN
    RAISE EXCEPTION 'R2_F_E1_LEGACY_RESOLVER_DEFINITION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR (SELECT count(*)
         FROM public.school_legacy_actual_settlement_evidence evidence
         JOIN public.school_lesson_records actual
           ON actual.id=evidence.actual_lesson_id
         WHERE evidence.actual_full_row_md5 IS DISTINCT FROM
               md5((to_jsonb(actual)-'lesson_total_fee_jpy')::text))<>1
     OR NOT EXISTS (
       SELECT 1
       FROM public.school_legacy_actual_settlement_evidence evidence
       JOIN public.school_lesson_records actual
         ON actual.id=evidence.actual_lesson_id
       WHERE actual.id='a1977f69-69d7-45d5-a958-50138d3f80d4'
         AND evidence.source_planned_lesson_id=actual.planned_lesson_id
         AND evidence.student_id_snapshot=actual.student_id
         AND evidence.business_entity_id_snapshot=actual.business_entity_id
         AND evidence.legacy_year_month=actual.year_month
         AND evidence.actual_full_row_md5 IS DISTINCT FROM
               md5((to_jsonb(actual)-'lesson_total_fee_jpy')::text)
     ) THEN
    RAISE EXCEPTION 'R2_F_E1_LEGACY_EDIT_EVIDENCE_NOT_REPRODUCED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E1_EVIDENCE_R0_DRIFT';
  END IF;
END
$preflight$;

\echo 'R2_F_E1_REPLACE_LEGACY_ACTUAL_EVIDENCE_CONTRACT'
DO $replace_resolver$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text := $old$
  IF FOUND THEN
    IF v_lesson.student_settlement_month IS NOT NULL
       OR v_actual_evidence.source_planned_lesson_id IS DISTINCT FROM
            v_lesson.planned_lesson_id
       OR v_actual_evidence.student_id_snapshot IS DISTINCT FROM
            v_lesson.student_id
       OR v_actual_evidence.business_entity_id_snapshot IS DISTINCT FROM
            v_lesson.business_entity_id
       OR v_actual_evidence.teacher_id_snapshot IS DISTINCT FROM
            v_lesson.teacher_id
       OR v_actual_evidence.subject_id_snapshot IS DISTINCT FROM
            v_lesson.subject_id
       OR v_actual_evidence.legacy_year_month IS DISTINCT FROM
            v_lesson.year_month
       OR v_actual_evidence.teacher_settlement_month_snapshot IS DISTINCT FROM
            coalesce(v_lesson.teacher_settlement_month,
              to_char(v_lesson.lesson_date,'YYYY-MM'))
       OR v_actual_evidence.lesson_date_snapshot IS DISTINCT FROM
            v_lesson.lesson_date
       OR v_actual_evidence.evidence_source<>
            'r1d_e_b2_all_existing_actual_at_cutover'
       OR v_actual_evidence.evidence_version<>
            'actual_legacy_settlement_evidence_v1'
       OR v_actual_evidence.actual_identity_md5 IS DISTINCT FROM
            md5(concat_ws('|',v_lesson.id::text,
              v_lesson.planned_lesson_id::text,v_lesson.student_id::text,
              v_lesson.business_entity_id::text,
              coalesce(v_lesson.teacher_id::text,'<NULL>'),
              coalesce(v_lesson.subject_id::text,'<NULL>'),v_lesson.year_month,
              coalesce(v_lesson.teacher_settlement_month,
                to_char(v_lesson.lesson_date,'YYYY-MM')),
              v_lesson.lesson_date::text,v_lesson.lesson_type,v_lesson.app_type))
       OR v_lesson.lesson_total_fee_jpy IS NOT NULL
       OR v_actual_evidence.actual_full_row_md5 IS DISTINCT FROM
            md5((to_jsonb(v_lesson)-'lesson_total_fee_jpy')::text) THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;
    RETURN v_actual_evidence.legacy_year_month;
  END IF;
$old$;
  v_new text := $new$
  IF FOUND THEN
    -- R2-F-E1 structured legacy contract: immutable v1 row hashes remain
    -- historical audit only. Operational edits are governed by lesson,
    -- settlement and wage writers, not by to_jsonb(%ROWTYPE).
    IF v_lesson.student_settlement_month IS NOT NULL
       OR v_actual_evidence.source_planned_lesson_id IS DISTINCT FROM
            v_lesson.planned_lesson_id
       OR v_actual_evidence.student_id_snapshot IS DISTINCT FROM
            v_lesson.student_id
       OR v_actual_evidence.business_entity_id_snapshot IS DISTINCT FROM
            v_lesson.business_entity_id
       OR v_actual_evidence.legacy_year_month IS DISTINCT FROM
            v_lesson.year_month
       OR v_actual_evidence.legacy_year_month !~
            '^[0-9]{4}-(0[1-9]|1[0-2])$'
       OR v_actual_evidence.evidence_source<>
            'r1d_e_b2_all_existing_actual_at_cutover'
       OR v_actual_evidence.evidence_version<>
            'actual_legacy_settlement_evidence_v1'
       OR v_actual_evidence.actual_identity_md5 IS NULL
       OR v_actual_evidence.actual_full_row_md5 IS NULL
       OR v_actual_evidence.cutover_actual_count<>234
       OR v_actual_evidence.cutover_actual_uuid_md5 IS NULL
       OR v_actual_evidence.cutover_identity_manifest_sha256 IS NULL
       OR v_actual_evidence.cutover_full_row_manifest_sha256 IS NULL THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;

    SELECT source.* INTO v_source
    FROM public.school_lesson_records source
    WHERE source.id=v_actual_evidence.source_planned_lesson_id;
    IF NOT FOUND
       OR v_source.app_type IS DISTINCT FROM 'school'
       OR v_source.lesson_type IS DISTINCT FROM 'planned'
       OR v_source.voided_at IS NOT NULL
       OR v_source.student_id IS DISTINCT FROM v_lesson.student_id
       OR v_source.business_entity_id IS DISTINCT FROM
            v_lesson.business_entity_id THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;

    RETURN v_actual_evidence.legacy_year_month;
  END IF;
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO STRICT v_definition;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition
     OR position('R2-F-E1 structured legacy contract' IN v_replaced)=0
     OR position(v_old IN v_replaced)>0 THEN
    RAISE EXCEPTION 'R2_F_E1_LEGACY_RESOLVER_REPLACEMENT_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace_resolver$;

COMMENT ON FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(uuid)
IS 'R2-F-E1 structured legacy settlement-month resolver. Immutable v1 identity/full-row hashes remain historical audit evidence; operational edits no longer invalidate preview. Runtime authority is explicit actual/source/student/entity/legacy-month evidence and the immutable evidence source/version contract.';

DO $verify$
DECLARE
  v_proc pg_proc%ROWTYPE;
  v_resolved_count integer;
  v_canonical_count integer;
BEGIN
  SELECT p.* INTO STRICT v_proc
  FROM pg_proc p
  WHERE p.oid=
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure;
  IF position('R2-F-E1 structured legacy contract' IN
       pg_get_functiondef(v_proc.oid))=0
     OR position('to_jsonb(v_lesson)' IN pg_get_functiondef(v_proc.oid))>0
     OR v_proc.provolatile<>'s' OR NOT v_proc.prosecdef
     OR v_proc.proowner::regrole::text<>'postgres'
     OR v_proc.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, public']::text[]
     OR v_proc.proacl::text<>'{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'R2_F_E1_STRUCTURED_RESOLVER_METADATA_FAILED';
  END IF;

  SELECT count(*) INTO v_resolved_count
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE public.school_resolve_r1d_e_c_lesson_student_month(
          evidence.actual_lesson_id)=evidence.legacy_year_month;
  IF v_resolved_count<>234
     OR public.school_resolve_r1d_e_c_lesson_student_month(
          'a1977f69-69d7-45d5-a958-50138d3f80d4')<>'2026-07' THEN
    RAISE EXCEPTION 'R2_F_E1_LEGACY_OPERATIONAL_EDIT_RESOLUTION_FAILED';
  END IF;

  SELECT count(*) INTO v_canonical_count
  FROM public.school_lesson_records actual
  WHERE actual.app_type='school' AND actual.lesson_type='actual'
    AND NOT EXISTS (
      SELECT 1 FROM public.school_legacy_actual_settlement_evidence evidence
      WHERE evidence.actual_lesson_id=actual.id)
    AND public.school_resolve_r1d_e_c_lesson_student_month(actual.id)=
          actual.student_settlement_month;
  IF v_canonical_count<>10 THEN
    RAISE EXCEPTION 'R2_F_E1_CANONICAL_ACTUAL_RESOLUTION_FAILED';
  END IF;
END
$verify$;

SELECT md5(pg_get_functiondef(
  'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
)) AS legacy_actual_resolver_md5;

\if :r2_f_e1_evidence_commit
  COMMIT;
  \echo 'R2_F_E1_EVIDENCE_CORRECTION_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_F_E1_EVIDENCE_REHEARSAL_ROLLED_BACK'
\endif
