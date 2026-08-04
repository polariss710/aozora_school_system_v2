-- Whitelist commit test. Creates only fixed codex-test fixtures, exercises the
-- deployed writer, cleans every fixture in the same transaction, then commits.

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL school.makeup_actual_replacement_test_scope=
  'codex-test makeup-actual-replacement-v1-20260804';

DO $commit_test$
DECLARE
  v_marker constant text := 'codex-test makeup-actual-replacement-v1-20260804';
  v_student constant uuid := 'a4a40000-0000-4000-8000-000000000001';
  v_teacher constant uuid := 'a4a40000-0000-4000-8000-000000000003';
  v_subject constant uuid := 'a4a40000-0000-4000-8000-000000000004';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_source public.school_lesson_records%ROWTYPE;
  v_original public.school_lesson_records%ROWTYPE;
  v_wrong public.school_lesson_records%ROWTYPE;
  v_result record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.school_students WHERE id=v_student)
     OR EXISTS (SELECT 1 FROM public.school_teachers WHERE id=v_teacher)
     OR EXISTS (SELECT 1 FROM public.school_subjects WHERE id=v_subject)
     OR EXISTS (SELECT 1 FROM public.school_lesson_records WHERE student_id=v_student) THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_COMMIT_TEST_PREFLIGHT_RESIDUE';
  END IF;

  INSERT INTO public.school_subjects(id,name,category,note)
  VALUES (v_subject,'codex-test EJU日语','测试',v_marker);
  INSERT INTO public.school_teachers(
    id,name,status,app_type,default_subject_id,default_business_entity_id,note
  ) VALUES (
    v_teacher,'codex-test 王亚楠','active','school',v_subject,v_entity,v_marker
  );
  INSERT INTO public.school_students(id,name,status,app_type,business_entity_id,note)
  VALUES (v_student,'codex-test 陈红卓','active','school',v_entity,v_marker);

  SELECT created.* INTO STRICT v_source
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2026-07-20',v_student,v_teacher,v_subject,v_entity,
    '13:00','15:00',2,8500,NULL,'planned',1,
    'codex-test EJU日语',v_marker,'online','codex-test online',0
  ) created;
  SELECT created.* INTO STRICT v_original
  FROM public.school_create_partial_completed_actual_from_planned(
    v_source.id,DATE '2026-07-20','20:00','21:00',1,
    'codex-test original completed actual',v_marker
  ) created;
  SELECT created.* INTO STRICT v_wrong
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source.id,DATE '2026-07-31',v_teacher,v_subject,
    '13:00','14:00',1,'codex-test EJU日语',v_marker,1,
    'online','codex-test online'
  ) created;

  SELECT r.* INTO STRICT v_result
  FROM public.school_replace_unconsumed_makeup_actual_v1(
    v_wrong.id,v_wrong.updated_at,v_source.id,DATE '2026-08-02',
    'codex-test commit replacement',
    'REPLACE_UNCONSUMED_MAKEUP_ACTUAL'
  ) r;
  IF v_result.new_actual_id IS NULL
     OR v_result.teacher_settlement_month<>'2026-08'
     OR v_result.lesson_fee<>0
     OR v_result.remaining_makeup_hours<>0 THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_COMMIT_TEST_RESULT_FAILED';
  END IF;

  DELETE FROM public.school_lesson_records
  WHERE id=v_result.new_actual_id AND student_id=v_student AND note=v_marker;
  DELETE FROM public.school_lesson_records
  WHERE id=v_original.id AND student_id=v_student AND note=v_marker;
  DELETE FROM public.school_lesson_records
  WHERE id=v_source.id AND student_id=v_student AND note=v_marker;
  DELETE FROM public.school_students WHERE id=v_student AND note=v_marker;
  DELETE FROM public.school_teachers WHERE id=v_teacher AND note=v_marker;
  DELETE FROM public.school_subjects WHERE id=v_subject AND note=v_marker;

  IF EXISTS (SELECT 1 FROM public.school_lesson_records WHERE student_id=v_student)
     OR EXISTS (SELECT 1 FROM public.school_students WHERE id=v_student)
     OR EXISTS (SELECT 1 FROM public.school_teachers WHERE id=v_teacher)
     OR EXISTS (SELECT 1 FROM public.school_subjects WHERE id=v_subject) THEN
    RAISE EXCEPTION 'MAKEUP_REPLACEMENT_COMMIT_TEST_CLEANUP_FAILED';
  END IF;
  RAISE NOTICE 'MAKEUP_REPLACEMENT_COMMIT_TEST_IDS source=%, original=%, wrong=%, new=%',
    v_source.id,v_original.id,v_wrong.id,v_result.new_actual_id;
END
$commit_test$;

COMMIT;
\echo 'MAKEUP_REPLACEMENT_WHITELIST_COMMIT_TEST_CLEANED_AND_COMMITTED'
