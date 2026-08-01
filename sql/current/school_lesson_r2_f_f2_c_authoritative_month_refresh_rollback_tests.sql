-- School V2 R2-F-F2-C rollback-only reader/API contract tests.
-- No fixture or production business DML; the transaction always rolls back.
\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL statement_timeout='180s';

CREATE TEMPORARY TABLE r2_f_f2_c_results(
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text NOT NULL
) ON COMMIT DROP;

DO $owner_checks$
DECLARE
  v_target constant uuid:='300751ba-2ea5-41f0-97dd-45251af8e9d1';
  v_cross_month constant uuid:='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';
BEGIN
  IF public.school_resolve_lesson_student_month_authoritative(v_target)
       <>'2026-08' THEN
    RAISE EXCEPTION 'R2_F_F2_C_LEGACY_TARGET_RESOLVER_FAILED';
  END IF;
  INSERT INTO r2_f_f2_c_results VALUES
    ('legacy_planned_authority',true,
     'target legacy planned resolves to August without billing_month fallback');

  IF (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-08',NULL
      ) lesson WHERE lesson.id=v_target)<>1 THEN
    RAISE EXCEPTION 'R2_F_F2_C_AUGUST_ALL_STUDENT_SCOPE_FAILED';
  END IF;
  INSERT INTO r2_f_f2_c_results VALUES
    ('august_all_student_reader',true,
     'August all-student reader includes the target exactly once');

  IF (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-08',DATE '2026-08-31'
      ) lesson WHERE lesson.id=v_cross_month)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-09',NULL
      ) lesson WHERE lesson.id=v_cross_month)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_C_CROSS_MONTH_PLANNED_SCOPE_FAILED';
  END IF;
  INSERT INTO r2_f_f2_c_results VALUES
    ('cross_month_planned_scope',true,
     'August 31 week includes cross-month planned; September month excludes it');
END
$owner_checks$;

SET LOCAL ROLE authenticated;

DO $client_checks$
DECLARE
  v_august_count bigint;
  v_target_student_count bigint;
  v_august_reader_count bigint;
  v_target_student_reader_count bigint;
BEGIN
  SELECT stats.record_count INTO STRICT v_august_count
  FROM public.school_get_lesson_management_stats_filtered(
    '2026-08',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
  ) stats;
  SELECT stats.record_count INTO STRICT v_target_student_count
  FROM public.school_get_lesson_management_stats_filtered(
    '2026-08','881dd60c-b92b-44ae-98e1-98448567a8d2',
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
  ) stats;
  SELECT count(*) INTO STRICT v_august_reader_count
  FROM public.school_list_lesson_management_records_authoritative(
    '2026-08',NULL
  );
  SELECT count(*) INTO STRICT v_target_student_reader_count
  FROM public.school_list_lesson_management_records_authoritative(
    '2026-08',NULL
  ) lesson
  WHERE lesson.student_id='881dd60c-b92b-44ae-98e1-98448567a8d2';
  IF v_august_count<>v_august_reader_count
     OR v_target_student_count<>v_target_student_reader_count THEN
    RAISE EXCEPTION 'R2_F_F2_C_CLIENT_STATS_SCOPE_FAILED: % / %',
      v_august_count,v_target_student_count;
  END IF;
END
$client_checks$;

RESET ROLE;

INSERT INTO r2_f_f2_c_results VALUES
  ('authenticated_stats',true,
   'authenticated role reads all-student and single-student authoritative stats');

TABLE r2_f_f2_c_results ORDER BY test_name;

ROLLBACK;

SELECT
  (SELECT count(*) FROM public.school_lesson_records
   WHERE id::text LIKE 'f2fc0000-0000-4000-8000-%') AS lesson_residue,
  (SELECT count(*) FROM public.school_students
   WHERE id::text LIKE 'f2fc0000-0000-4000-8000-%') AS student_residue;
