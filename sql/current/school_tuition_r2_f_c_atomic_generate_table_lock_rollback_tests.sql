-- R2-F-C rollback-only acceptance. Extends the complete R2-F-B matrix.
\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_c_existing_tx}
  \echo 'R2_F_C_TESTS_USING_EXISTING_TRANSACTION'
\else
  BEGIN;
\endif
\set r2_f_b_existing_tx 1
\ir school_tuition_r2_f_b_atomic_generate_rollback_tests.sql

DO $lock_assert$
DECLARE
  v_lock_count integer;
  v_timeout text;
  v_select_probe bigint;
BEGIN
  SELECT count(DISTINCT lock_row.relation)::integer INTO v_lock_count
  FROM pg_locks lock_row
  WHERE lock_row.pid=pg_backend_pid()
    AND lock_row.locktype='relation'
    AND lock_row.mode='ShareLock'
    AND lock_row.granted
    AND lock_row.relation IN (
      'public.school_lesson_records'::regclass,
      'public.school_student_monthly_settlements'::regclass,
      'public.school_student_settlement_carryovers'::regclass,
      'public.school_student_settlement_adjustment_drafts'::regclass
    );
  IF v_lock_count<>4 THEN
    RAISE EXCEPTION 'R2_F_C_EXPECTED_FOUR_SHARE_LOCKS: %',v_lock_count;
  END IF;

  SELECT count(*) INTO v_select_probe FROM public.school_lesson_records;
  SELECT count(*) INTO v_select_probe FROM public.school_student_monthly_settlements;
  SELECT count(*) INTO v_select_probe FROM public.school_student_settlement_carryovers;
  SELECT count(*) INTO v_select_probe FROM public.school_student_settlement_adjustment_drafts;

  v_timeout:=current_setting('lock_timeout');
  IF v_timeout NOT IN ('10s','10000ms') THEN
    RAISE EXCEPTION 'R2_F_C_CALLER_LOCK_TIMEOUT_NOT_RESTORED: %',v_timeout;
  END IF;
END
$lock_assert$;

SELECT lock_row.relation::regclass AS table_name,lock_row.mode,lock_row.granted
FROM pg_locks lock_row
WHERE lock_row.pid=pg_backend_pid()
  AND lock_row.relation IN (
    'public.school_lesson_records'::regclass,
    'public.school_student_monthly_settlements'::regclass,
    'public.school_student_settlement_carryovers'::regclass,
    'public.school_student_settlement_adjustment_drafts'::regclass
  )
  AND lock_row.mode='ShareLock'
ORDER BY lock_row.relation::regclass::text;

ROLLBACK;

BEGIN TRANSACTION READ ONLY;
DO $residual$
BEGIN
  IF EXISTS (SELECT 1 FROM public.school_students
      WHERE id::text LIKE 'f2fb0000-0000-4000-8000-00000000a00%')
     OR EXISTS (SELECT 1 FROM public.school_lesson_records
       WHERE note='codex-test r2-f-b')
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bills
       WHERE source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1')
     OR EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_C_ROLLBACK_RESIDUE';
  END IF;
END
$residual$;

WITH fingerprints AS (
  SELECT 'bills' object,count(*)::integer row_count,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),'')) full_row_hash
  FROM public.school_student_tuition_bills t
  UNION ALL SELECT 'income',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_income_records t
  UNION ALL SELECT 'relations',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_tuition_bill_lessons t
  UNION ALL SELECT 'identities',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_tuition_billing_identities t
  UNION ALL SELECT 'settlements',count(*)::integer,
    md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))
  FROM public.school_student_monthly_settlements t
)
SELECT * FROM fingerprints ORDER BY object;

DO $final_assert$
BEGIN
  IF (SELECT count(*)<>9 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'0f0323b79e7ff1c47ff6b90c75477a2d'
      FROM public.school_student_tuition_bills t)
     OR (SELECT count(*)<>42 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'2a4897b752f272b1f192045418b4940c'
      FROM public.school_income_records t)
     OR (SELECT count(*)<>121 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'285172fedeb923c67ea9a179480d8692'
      FROM public.school_student_tuition_bill_lessons t)
     OR (SELECT count(*)<>7 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'4d91a5a1074f90389822fc367a7e5467'
      FROM public.school_student_tuition_billing_identities t)
     OR (SELECT count(*)<>15 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'8d40d937d45c64eca0ec0ba7b1c5e65d'
      FROM public.school_student_monthly_settlements t)
     OR (SELECT count(*) FROM public.school_feature_gates
       WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
          OR (feature_key='student_tuition_generate' AND state='blocked')
          OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_C_FINAL_STATE_MISMATCH';
  END IF;
END
$final_assert$;
SELECT true AS rollback_tests_pass,0 AS persisted_fixture_rows;
ROLLBACK;
\echo 'R2_F_C_ROLLBACK_TESTS_ROLLED_BACK'
