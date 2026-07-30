-- R2-C rollback tests. All negative writes are contained in PL/pgSQL
-- subtransactions; the outer transaction always rolls back.

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $tests$
DECLARE
  v_evidence_rejected boolean:=false;
  v_month_rejected boolean:=false;
  v_partial_rejected boolean:=false;
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records l
      JOIN public.school_legacy_planned_settlement_evidence e
        ON e.planned_lesson_id=l.id
      WHERE l.id IN (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
        AND l.lesson_type='planned'
        AND l.app_type='school'
        AND l.year_month='2026-07'
        AND l.lesson_date IN (DATE '2026-08-01',DATE '2026-08-02')
        AND num_nonnulls(l.billing_month,l.billing_week_start_date,
              l.student_settlement_month,l.billing_month_source,
              l.billing_month_decided_at)=0
        AND e.legacy_student_settlement_month='2026-07'
        AND e.lesson_identity_md5=md5(concat_ws('|',l.id::text,
          coalesce(l.student_id::text,'<NULL>'),
          coalesce(l.business_entity_id::text,'<NULL>'),
          coalesce(l.year_month,'<NULL>'),l.lesson_type,l.app_type))
        AND public.school_resolve_r1d_e_c_lesson_student_month(l.id)='2026-07')<>2 THEN
    RAISE EXCEPTION 'R2_C_TEST_CORRECTED_TARGET_STATE_MISMATCH';
  END IF;

  IF (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(
       'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07') r
      WHERE r.lesson_id IN (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      ) AND r.attribution_class='legacy_planned')<>2
     OR EXISTS (
       SELECT 1 FROM public.school_list_r1d_e_c_student_month_lessons(
         'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08') r
       WHERE r.lesson_id IN (
         '8b737b58-cd14-42c5-afd2-34730dcef963',
         '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
       )
     ) THEN
    RAISE EXCEPTION 'R2_C_TEST_JULY_AUGUST_READER_MISMATCH';
  END IF;

  BEGIN
    UPDATE public.school_legacy_planned_settlement_evidence
    SET legacy_student_settlement_month='2026-08'
    WHERE planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963';
  EXCEPTION WHEN OTHERS THEN
    v_evidence_rejected:=position('IMMUTABLE' IN upper(SQLERRM))>0;
  END;
  IF NOT v_evidence_rejected THEN
    RAISE EXCEPTION 'R2_C_TEST_IMMUTABLE_EVIDENCE_UPDATE_NOT_REJECTED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records
    SET year_month='2026-08'
    WHERE id='8b737b58-cd14-42c5-afd2-34730dcef963';
  EXCEPTION WHEN OTHERS THEN
    v_month_rejected:=position('EVIDENCE' IN upper(SQLERRM))>0
      OR position('F1' IN upper(SQLERRM))>0;
  END;
  IF NOT v_month_rejected THEN
    RAISE EXCEPTION 'R2_C_TEST_LEGACY_MONTH_WITHOUT_EVIDENCE_NOT_REJECTED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records
    SET billing_month='2026-07'
    WHERE id='685ad45e-b5da-42ca-8f43-7732e8d6e40d';
  EXCEPTION WHEN OTHERS THEN
    v_partial_rejected:=position('PARTIAL' IN upper(SQLERRM))>0
      OR position('F1' IN upper(SQLERRM))>0;
  END;
  IF NOT v_partial_rejected THEN
    RAISE EXCEPTION 'R2_C_TEST_PARTIAL_ATTRIBUTION_NOT_REJECTED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT count(*) FROM public.school_lesson_records l
         WHERE l.id IN (
           '8b737b58-cd14-42c5-afd2-34730dcef963',
           '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
         ) AND l.year_month='2026-07'
           AND num_nonnulls(l.billing_month,l.billing_week_start_date,
             l.student_settlement_month,l.billing_month_source,
             l.billing_month_decided_at)=0)<>2 THEN
    RAISE EXCEPTION 'R2_C_TEST_NEGATIVE_CASE_LEFT_RESIDUE';
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_lesson_records
             WHERE coalesce(note,'') ILIKE '%codex-test-r2-c%'
                OR coalesce(lesson_content,'') ILIKE '%codex-test-r2-c%'
                OR coalesce(import_source,'') ILIKE '%codex-test-r2-c%') THEN
    RAISE EXCEPTION 'R2_C_TEST_MARKER_RESIDUE';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'1770f3469dbc3bc030a977381b853deb'
     OR md5(pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))<>'f535f4649f870097a350208b64da643e'
     OR (SELECT count(*) FROM public.school_feature_gates
         WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
            OR (feature_key='student_tuition_generate' AND state='blocked')
            OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_legacy_planned_settlement_evidence'::regclass
           AND tgname='school_legacy_planned_evidence_row_immutable'
           AND tgenabled='O')<>1 THEN
    RAISE EXCEPTION 'R2_C_TEST_R2_B_R0_OR_TRIGGER_DRIFT';
  END IF;

  RAISE NOTICE 'R2_C_ROLLBACK_TESTS_OK';
  RAISE NOTICE 'R2_C_NEGATIVE_EVIDENCE_IMMUTABILITY=PASS';
  RAISE NOTICE 'R2_C_NEGATIVE_LEGACY_MONTH_MISMATCH=PASS';
  RAISE NOTICE 'R2_C_NEGATIVE_PARTIAL_ATTRIBUTION=PASS';
  RAISE NOTICE 'R2_C_TEST_MARKER_RESIDUE=0';
END
$tests$;

ROLLBACK;
\echo 'R2_C_ROLLBACK_TESTS_ROLLED_BACK'
