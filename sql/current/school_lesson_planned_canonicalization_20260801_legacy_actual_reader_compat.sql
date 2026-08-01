-- Reader-only compatibility required by the approved planned entity migration.
-- No actual/evidence/business row is written. Legacy actual month authority remains
-- immutable actual evidence; planned evidence only proves the pre-migration entity link.
\set ON_ERROR_STOP on
\pset pager off
\if :{?planned_actual_reader_compat_commit}
\else
  \set planned_actual_reader_compat_commit 0
\endif

BEGIN;

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     ))<>'0a6de23e218c3dadda6a4604242ee894' THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_FUNCTION_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_GATE_DRIFT';
  END IF;
  IF (SELECT count(*)
      FROM public.school_lesson_records actual
      JOIN public.school_legacy_actual_settlement_evidence actual_evidence
        ON actual_evidence.actual_lesson_id=actual.id
      JOIN public.school_lesson_records source
        ON source.id=actual_evidence.source_planned_lesson_id
      WHERE source.business_entity_id IS DISTINCT FROM actual.business_entity_id)<>142
     OR (SELECT count(*)
      FROM public.school_lesson_records actual
      JOIN public.school_legacy_actual_settlement_evidence actual_evidence
        ON actual_evidence.actual_lesson_id=actual.id
      JOIN public.school_lesson_records source
        ON source.id=actual_evidence.source_planned_lesson_id
      JOIN public.school_legacy_planned_settlement_evidence planned_evidence
        ON planned_evidence.planned_lesson_id=source.id
      WHERE source.business_entity_id IS DISTINCT FROM actual.business_entity_id
        AND source.business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        AND source.student_id=actual.student_id
        AND planned_evidence.approved_manifest IS TRUE
        AND planned_evidence.evidence_source='r1d_e_b1_fixed_legacy_279'
        AND planned_evidence.evidence_version='legacy_settlement_evidence_v1'
        AND planned_evidence.student_id_snapshot=actual.student_id
        AND planned_evidence.business_entity_id_snapshot=actual.business_entity_id
        AND planned_evidence.lesson_identity_md5=md5(concat_ws('|',
          source.id::text,coalesce(source.student_id::text,'<NULL>'),
          coalesce(planned_evidence.business_entity_id_snapshot::text,'<NULL>'),
          coalesce(source.year_month,'<NULL>'),source.lesson_type,source.app_type
        )))<>142 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_EVIDENCE_SCOPE_INVALID';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE planned_actual_reader_business_before ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_lesson_records x),
  'planned_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),''))) FROM public.school_legacy_planned_settlement_evidence x),
  'actual_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),''))) FROM public.school_legacy_actual_settlement_evidence x),
  'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x),
  'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x),
  'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x),
  'settlements',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_monthly_settlements x),
  'wage_locks',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_locks x),
  'wage_details',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_lock_details x),
  'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.feature_key),''))) FROM public.school_feature_gates x)
) fingerprint;

DO $replace$
DECLARE
  v_definition text;
  v_replaced text;
  v_old text:=$old$
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
$old$;
  v_new text:=$new$
    SELECT source.* INTO v_source
    FROM public.school_lesson_records source
    WHERE source.id=v_actual_evidence.source_planned_lesson_id;
    IF NOT FOUND
       OR v_source.app_type IS DISTINCT FROM 'school'
       OR v_source.lesson_type IS DISTINCT FROM 'planned'
       OR v_source.voided_at IS NOT NULL
       OR v_source.student_id IS DISTINCT FROM v_lesson.student_id THEN
      RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
    END IF;

    IF v_source.business_entity_id IS DISTINCT FROM v_lesson.business_entity_id THEN
      -- Planned-only entity canonicalization leaves legacy actual rows untouched.
      -- The current source must be Aozora, while both immutable evidence rows must
      -- prove the same pre-migration student/entity link. Neither evidence source
      -- supplies or overrides the actual fulfilment month here.
      SELECT evidence.* INTO v_planned_evidence
      FROM public.school_legacy_planned_settlement_evidence evidence
      WHERE evidence.planned_lesson_id=v_source.id;
      IF NOT FOUND
         OR v_source.business_entity_id IS DISTINCT FROM
              '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
         OR v_planned_evidence.approved_manifest IS DISTINCT FROM true
         OR v_planned_evidence.evidence_source<>'r1d_e_b1_fixed_legacy_279'
         OR v_planned_evidence.evidence_version<>'legacy_settlement_evidence_v1'
         OR v_planned_evidence.student_id_snapshot IS DISTINCT FROM
              v_lesson.student_id
         OR v_planned_evidence.business_entity_id_snapshot IS DISTINCT FROM
              v_actual_evidence.business_entity_id_snapshot
         OR v_planned_evidence.lesson_identity_md5 IS DISTINCT FROM
              md5(concat_ws('|',v_source.id::text,
                coalesce(v_source.student_id::text,'<NULL>'),
                coalesce(v_planned_evidence.business_entity_id_snapshot::text,'<NULL>'),
                coalesce(v_source.year_month,'<NULL>'),
                v_source.lesson_type,v_source.app_type)) THEN
        RAISE EXCEPTION 'R1D_E_C_LEGACY_ACTUAL_EVIDENCE_MISMATCH';
      END IF;
    END IF;
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO v_definition;
  v_replaced:=replace(v_definition,v_old,v_new);
  IF v_replaced=v_definition
     OR position('Planned-only entity canonicalization' IN v_replaced)=0 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_REPLACE_FAILED';
  END IF;
  EXECUTE v_replaced;
END
$replace$;

COMMENT ON FUNCTION public.school_resolve_r1d_e_c_lesson_student_month(uuid) IS
  'Canonical planned rows remain authoritative. Unmigrated legacy actual fulfilment month remains immutable actual evidence; when planned-only entity canonicalization makes current entities differ, immutable planned evidence only proves the pre-migration source/student/entity link and never supplies the actual month.';

DO $verify$
DECLARE
  v_after jsonb;
BEGIN
  SELECT jsonb_build_object(
    'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_lesson_records x),
    'planned_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.planned_lesson_id::text),''))) FROM public.school_legacy_planned_settlement_evidence x),
    'actual_evidence',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.actual_lesson_id::text),''))) FROM public.school_legacy_actual_settlement_evidence x),
    'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x),
    'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x),
    'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x),
    'settlements',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_monthly_settlements x),
    'wage_locks',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_locks x),
    'wage_details',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_lock_details x),
    'gates',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.feature_key),''))) FROM public.school_feature_gates x)
  ) INTO v_after;
  IF v_after IS DISTINCT FROM (SELECT fingerprint FROM planned_actual_reader_business_before) THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_BUSINESS_ROW_CHANGED';
  END IF;
  IF (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence evidence
      WHERE public.school_resolve_r1d_e_c_lesson_student_month(evidence.actual_lesson_id)
            =evidence.legacy_year_month)<>234 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_ALL_ACTUALS_FAILED';
  END IF;
  IF (SELECT count(*) FROM public.school_list_lesson_management_records_authoritative(
       '2026-07',NULL))=0 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_PAGE_READER_FAILED';
  END IF;
  IF position('Planned-only entity canonicalization' IN pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'PLANNED_ACTUAL_READER_COMPAT_MARKER_MISSING';
  END IF;
END
$verify$;

SELECT md5(pg_get_functiondef(
  'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
)) resolver_md5;

\if :planned_actual_reader_compat_commit
  COMMIT;
  \echo 'PLANNED_ACTUAL_READER_COMPAT_COMMITTED'
\else
  ROLLBACK;
  \echo 'PLANNED_ACTUAL_READER_COMPAT_REHEARSAL_ROLLED_BACK'
\endif
