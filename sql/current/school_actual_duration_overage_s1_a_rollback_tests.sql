\set ON_ERROR_STOP on
\pset pager off

-- S1-A rollback tests use pg_temp copies only. No formal business row is
-- inserted, updated, or deleted. The transaction is rolled back in full.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $pretest$
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(
        student_duration_overage_minutes,
        student_duration_overage_fee_jpy,
        student_duration_overage_policy_version,
        student_duration_overage_source,
        student_duration_overage_decided_at
      ) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
      WHERE num_nonnulls(
        duration_overage_minutes,
        duration_overage_fee_jpy,
        duration_overage_fee_cny,
        duration_overage_actual_count,
        duration_overage_policy_version,
        duration_overage_source
      ) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A rollback tests: formal history is not all NULL';
  END IF;
END
$pretest$;

CREATE TEMP TABLE s1a_lesson_constraint_test
  (LIKE public.school_lesson_records INCLUDING ALL)
  ON COMMIT DROP;

CREATE TEMP TABLE s1a_settlement_constraint_test
  (LIKE public.school_student_monthly_settlements INCLUDING ALL)
  ON COMMIT DROP;

INSERT INTO pg_temp.s1a_lesson_constraint_test
  (id, lesson_type, lesson_date, year_month, duration_hours, status,
   is_billable, app_type, planned_lesson_id, student_settlement_month)
VALUES
  ('f1000000-0000-4000-8000-000000000001', 'actual', '2099-01-01', '2099-01', 2,
   'completed', true, 'school', 'f1000000-0000-4000-8000-000000000101', NULL);

INSERT INTO pg_temp.s1a_lesson_constraint_test
  (id, lesson_type, lesson_date, year_month, duration_hours, status,
   is_billable, app_type, planned_lesson_id, student_settlement_month,
   student_duration_overage_minutes, student_duration_overage_fee_jpy,
   student_duration_overage_policy_version, student_duration_overage_source,
   student_duration_overage_decided_at)
VALUES
  ('f1000000-0000-4000-8000-000000000002', 'actual', '2099-01-02', '2099-01', 2,
   'completed', true, 'school', 'f1000000-0000-4000-8000-000000000102', '2099-01',
   0, 0, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp()),
  ('f1000000-0000-4000-8000-000000000003', 'actual', '2099-01-03', '2099-01', 2.25,
   'completed', true, 'school', 'f1000000-0000-4000-8000-000000000103', '2099-01',
   15, 2500, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());

-- Existing credit workflow compatibility: multiple makeup rows may share one
-- planned source because their policy bundle is entirely NULL.
INSERT INTO pg_temp.s1a_lesson_constraint_test
  (id, lesson_type, lesson_date, year_month, duration_hours, status,
   is_billable, app_type, planned_lesson_id, student_settlement_month)
VALUES
  ('f1000000-0000-4000-8000-000000000004', 'actual', '2099-02-01', '2099-02', 1,
   'makeup_completed', false, 'school', 'f1000000-0000-4000-8000-000000000104', NULL),
  ('f1000000-0000-4000-8000-000000000005', 'actual', '2099-02-02', '2099-02', 1,
   'makeup_completed', false, 'school', 'f1000000-0000-4000-8000-000000000104', NULL);

INSERT INTO pg_temp.s1a_settlement_constraint_test
  (id, student_id, year_month)
VALUES
  ('f2000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000101', '2099-01');

INSERT INTO pg_temp.s1a_settlement_constraint_test
  (id, student_id, year_month, duration_overage_minutes,
   duration_overage_fee_jpy, duration_overage_fee_cny,
   duration_overage_actual_count, duration_overage_policy_version,
   duration_overage_source)
VALUES
  ('f2000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000102', '2099-01',
   0, 0, 0, 0, 'student_duration_overage_v1', 'monthly_settlement_lock'),
  ('f2000000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000103', '2099-01',
   15, 2500, 105.25, 1, 'student_duration_overage_v1', 'monthly_settlement_lock');

DO $tests$
BEGIN
  IF (SELECT count(*) FROM pg_temp.s1a_lesson_constraint_test) <> 5
     OR (SELECT count(*) FROM pg_temp.s1a_settlement_constraint_test) <> 3 THEN
    RAISE EXCEPTION 'S1-A rollback tests: positive/all-NULL cases mismatch';
  END IF;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes)
    VALUES ('f1000000-0000-4000-8000-000000000011', 'actual', '2099-03-01', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000111', '2099-03', 0);
    RAISE EXCEPTION 'S1-A rollback tests: partial lesson bundle unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000012', 'planned', '2099-03-02', '2099-03', 2,
      'planned', true, 'school', 'f1000000-0000-4000-8000-000000000112', '2099-03',
      0, 0, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: non-actual snapshot unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000013', 'actual', '2099-03-03', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000113', NULL,
      0, 0, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: missing settlement month unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000014', 'actual', '2099-03-04', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000114', '2099-03',
      0, 0, 'unknown_policy', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: unknown policy unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000015', 'actual', '2099-03-05', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000115', '2099-03',
      0, 0, 'student_duration_overage_v1', 'unknown_source', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: unknown source unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000016', 'actual', '2099-03-06', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000116', '2099-03',
      -1, 100, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: negative minutes unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000017', 'actual', '2099-03-07', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000117', '2099-03',
      1, -1, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: negative fee unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000018', 'actual', '2099-03-08', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000118', '2099-03',
      1, 10.5, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: fractional JPY unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000019', 'actual', '2099-03-09', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000119', '2099-03',
      0, 1, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: zero minutes with fee unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000020', 'actual', '2099-03-10', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000120', '2099-03',
      1, 0, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: positive minutes with zero fee unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_lesson_constraint_test
      (id, lesson_type, lesson_date, year_month, duration_hours, status, is_billable,
       app_type, planned_lesson_id, student_settlement_month,
       student_duration_overage_minutes, student_duration_overage_fee_jpy,
       student_duration_overage_policy_version, student_duration_overage_source,
       student_duration_overage_decided_at)
    VALUES ('f1000000-0000-4000-8000-000000000021', 'actual', '2099-03-11', '2099-03', 2,
      'completed', true, 'school', 'f1000000-0000-4000-8000-000000000102', '2099-03',
      0, 0, 'student_duration_overage_v1', 'ordinary_actual_rpc', statement_timestamp());
    RAISE EXCEPTION 'S1-A rollback tests: duplicate new-policy planned unexpectedly accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes)
    VALUES ('f2000000-0000-4000-8000-000000000011',
      'f2000000-0000-4000-8000-000000000111', '2099-02', 0);
    RAISE EXCEPTION 'S1-A rollback tests: partial settlement bundle unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000012',
      'f2000000-0000-4000-8000-000000000112', '2099-02',
      1, 10.5, 1, 1, 'student_duration_overage_v1', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: settlement fractional JPY unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000013',
      'f2000000-0000-4000-8000-000000000113', '2099-02',
      1, 10, 1.001, 1, 'student_duration_overage_v1', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: settlement >2-decimal CNY unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000014',
      'f2000000-0000-4000-8000-000000000114', '2099-02',
      1, 10, 1, 0, 'student_duration_overage_v1', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: positive amount with zero count unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000015',
      'f2000000-0000-4000-8000-000000000115', '2099-02',
      0, 0, 0, 0, 'unknown_policy', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: unknown settlement policy unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000016',
      'f2000000-0000-4000-8000-000000000116', '2099-02',
      -1, 10, 1, 1, 'student_duration_overage_v1', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: settlement negative minutes unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000017',
      'f2000000-0000-4000-8000-000000000117', '2099-02',
      1, -10, 1, 1, 'student_duration_overage_v1', 'monthly_settlement_lock');
    RAISE EXCEPTION 'S1-A rollback tests: settlement negative JPY unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO pg_temp.s1a_settlement_constraint_test
      (id, student_id, year_month, duration_overage_minutes,
       duration_overage_fee_jpy, duration_overage_fee_cny,
       duration_overage_actual_count, duration_overage_policy_version,
       duration_overage_source)
    VALUES ('f2000000-0000-4000-8000-000000000018',
      'f2000000-0000-4000-8000-000000000118', '2099-02',
      0, 0, 0, 0, 'student_duration_overage_v1', 'unknown_source');
    RAISE EXCEPTION 'S1-A rollback tests: unknown settlement source unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$tests$;

ROLLBACK;

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $residue$
BEGIN
  IF to_regclass('pg_temp.s1a_lesson_constraint_test') IS NOT NULL
     OR to_regclass('pg_temp.s1a_settlement_constraint_test') IS NOT NULL THEN
    RAISE EXCEPTION 'S1-A rollback tests: pg_temp residue remains';
  END IF;
  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(
        student_duration_overage_minutes,
        student_duration_overage_fee_jpy,
        student_duration_overage_policy_version,
        student_duration_overage_source,
        student_duration_overage_decided_at
      ) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
      WHERE num_nonnulls(
        duration_overage_minutes,
        duration_overage_fee_jpy,
        duration_overage_fee_cny,
        duration_overage_actual_count,
        duration_overage_policy_version,
        duration_overage_source
      ) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A rollback tests: formal-table residue remains';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 630
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(l) - ARRAY[
          'student_duration_overage_minutes',
          'student_duration_overage_fee_jpy',
          'student_duration_overage_policy_version',
          'student_duration_overage_source',
          'student_duration_overage_decided_at'
        ])::text), '' ORDER BY l.id::text), ''))
         FROM public.school_lesson_records l
         WHERE l.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
        <> 'fd8b5570f42d618f136b2f6408704ae8'
     OR (SELECT md5(coalesce(string_agg(md5((to_jsonb(s) - ARRAY[
          'duration_overage_minutes',
          'duration_overage_fee_jpy',
          'duration_overage_fee_cny',
          'duration_overage_actual_count',
          'duration_overage_policy_version',
          'duration_overage_source'
        ])::text), '' ORDER BY s.id::text), ''))
         FROM public.school_student_monthly_settlements s
         WHERE s.created_at <= TIMESTAMPTZ '2026-07-29 18:37:10.228629+00')
        <> '7925cf3018bd0e669cd29710f6593238' THEN
    RAISE EXCEPTION 'S1-A rollback tests: row-count or stable history hash changed';
  END IF;
END
$residue$;
ROLLBACK;
