\set ON_ERROR_STOP on
\pset pager off

-- Aozora V2 actual duration overage S1-A: schema-only foundation.
-- This phase adds nullable snapshot columns, CHECK constraints, and empty
-- partial indexes only. It does not activate a writer or reader, calculate an
-- overage, backfill history, or touch aircon/planned fee components.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF to_regclass('public.school_lesson_records') IS NULL
     OR to_regclass('public.school_student_monthly_settlements') IS NULL THEN
    RAISE EXCEPTION 'S1-A preflight: required table is missing';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_lesson_records'
        AND column_name IN (
          'student_duration_overage_minutes',
          'student_duration_overage_fee_jpy',
          'student_duration_overage_policy_version',
          'student_duration_overage_source',
          'student_duration_overage_decided_at'
        )) <> 0
     OR (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_student_monthly_settlements'
        AND column_name IN (
          'duration_overage_minutes',
          'duration_overage_fee_jpy',
          'duration_overage_fee_cny',
          'duration_overage_actual_count',
          'duration_overage_policy_version',
          'duration_overage_source'
        )) <> 0 THEN
    RAISE EXCEPTION 'S1-A preflight: one or more target columns already exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk'
    )
  ) OR EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'school_lesson_records_duration_overage_month_idx',
        'school_lesson_records_duration_overage_planned_uidx'
      )
  ) THEN
    RAISE EXCEPTION 'S1-A preflight: one or more target constraints/indexes already exist';
  END IF;

  IF (SELECT count(*)
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'school_lesson_records'
        AND ((column_name = 'lesson_type' AND data_type = 'text')
          OR (column_name = 'status' AND data_type = 'text')
          OR (column_name = 'is_billable' AND data_type = 'boolean')
          OR (column_name = 'planned_lesson_id' AND data_type = 'uuid')
          OR (column_name = 'student_settlement_month' AND data_type = 'text')
          OR (column_name = 'student_id' AND data_type = 'uuid')
          OR (column_name = 'business_entity_id' AND data_type = 'uuid'))) <> 7 THEN
    RAISE EXCEPTION 'S1-A preflight: lesson context column contract mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.school_lesson_records
    WHERE lesson_type = 'actual' AND status = 'completed' AND is_billable IS TRUE
  ) THEN
    RAISE EXCEPTION 'S1-A preflight: approved actual/completed/billable status contract not present';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1-A preflight: R0 feature gates mismatch';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records
      WHERE num_nonnulls(base_lesson_fee_jpy, aircon_fee_jpy, fee_calculation_version) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1-A preflight: aircon/planned fee component history unexpectedly populated';
  END IF;

  IF (SELECT count(*)
      FROM public.school_lesson_records a
      JOIN public.school_lesson_records p ON p.id = a.planned_lesson_id
      WHERE a.app_type = 'school'
        AND a.lesson_type = 'actual'
        AND p.lesson_type = 'planned'
        AND a.duration_hours > p.duration_hours) <> 19
     OR (SELECT coalesce(sum(a.lesson_fee - p.lesson_fee), 0)
      FROM public.school_lesson_records a
      JOIN public.school_lesson_records p ON p.id = a.planned_lesson_id
      WHERE a.app_type = 'school'
        AND a.lesson_type = 'actual'
        AND p.lesson_type = 'planned'
        AND a.duration_hours > p.duration_hours) <> 119600 THEN
    RAISE EXCEPTION 'S1-A preflight: fixed legacy 19 boundary mismatch';
  END IF;
END
$preflight$;

ALTER TABLE public.school_lesson_records
  ADD COLUMN student_duration_overage_minutes integer,
  ADD COLUMN student_duration_overage_fee_jpy numeric,
  ADD COLUMN student_duration_overage_policy_version text,
  ADD COLUMN student_duration_overage_source text,
  ADD COLUMN student_duration_overage_decided_at timestamptz,
  ADD CONSTRAINT school_lesson_records_duration_overage_bundle_chk
    CHECK (
      num_nonnulls(
        student_duration_overage_minutes,
        student_duration_overage_fee_jpy,
        student_duration_overage_policy_version,
        student_duration_overage_source,
        student_duration_overage_decided_at
      ) IN (0, 5)
    ),
  ADD CONSTRAINT school_lesson_records_duration_overage_context_chk
    CHECK (
      student_duration_overage_policy_version IS NULL
      OR (
        lesson_type = 'actual'
        AND status = 'completed'
        AND is_billable IS TRUE
        AND planned_lesson_id IS NOT NULL
        AND student_settlement_month IS NOT NULL
        AND student_duration_overage_policy_version = 'student_duration_overage_v1'
        AND btrim(student_duration_overage_policy_version) <> ''
        AND student_duration_overage_source = 'ordinary_actual_rpc'
        AND btrim(student_duration_overage_source) <> ''
        AND student_duration_overage_decided_at IS NOT NULL
      )
    ),
  ADD CONSTRAINT school_lesson_records_duration_overage_amount_chk
    CHECK (
      student_duration_overage_minutes IS NULL
      OR (
        student_duration_overage_minutes >= 0
        AND student_duration_overage_fee_jpy >= 0
        AND student_duration_overage_fee_jpy = round(student_duration_overage_fee_jpy)
        AND (
          (student_duration_overage_minutes = 0 AND student_duration_overage_fee_jpy = 0)
          OR (student_duration_overage_minutes > 0 AND student_duration_overage_fee_jpy > 0)
        )
      )
    );

CREATE INDEX school_lesson_records_duration_overage_month_idx
  ON public.school_lesson_records (
    student_id,
    business_entity_id,
    student_settlement_month
  )
  WHERE student_duration_overage_policy_version = 'student_duration_overage_v1'
    AND student_duration_overage_source = 'ordinary_actual_rpc'
    AND student_duration_overage_fee_jpy > 0;

CREATE UNIQUE INDEX school_lesson_records_duration_overage_planned_uidx
  ON public.school_lesson_records (planned_lesson_id)
  WHERE student_duration_overage_policy_version = 'student_duration_overage_v1'
    AND student_duration_overage_source = 'ordinary_actual_rpc';

ALTER TABLE public.school_student_monthly_settlements
  ADD COLUMN duration_overage_minutes integer,
  ADD COLUMN duration_overage_fee_jpy numeric,
  ADD COLUMN duration_overage_fee_cny numeric,
  ADD COLUMN duration_overage_actual_count integer,
  ADD COLUMN duration_overage_policy_version text,
  ADD COLUMN duration_overage_source text,
  ADD CONSTRAINT school_student_settlements_duration_overage_bundle_chk
    CHECK (
      num_nonnulls(
        duration_overage_minutes,
        duration_overage_fee_jpy,
        duration_overage_fee_cny,
        duration_overage_actual_count,
        duration_overage_policy_version,
        duration_overage_source
      ) IN (0, 6)
    ),
  ADD CONSTRAINT school_student_settlements_duration_overage_policy_chk
    CHECK (
      duration_overage_policy_version IS NULL
      OR (
        duration_overage_policy_version = 'student_duration_overage_v1'
        AND btrim(duration_overage_policy_version) <> ''
        AND duration_overage_source = 'monthly_settlement_lock'
        AND btrim(duration_overage_source) <> ''
      )
    ),
  ADD CONSTRAINT school_student_settlements_duration_overage_amount_chk
    CHECK (
      duration_overage_minutes IS NULL
      OR (
        duration_overage_minutes >= 0
        AND duration_overage_fee_jpy >= 0
        AND duration_overage_fee_jpy = round(duration_overage_fee_jpy)
        AND duration_overage_fee_cny >= 0
        AND duration_overage_fee_cny = round(duration_overage_fee_cny, 2)
        AND duration_overage_actual_count >= 0
        AND (
          duration_overage_actual_count <> 0
          OR (
            duration_overage_minutes = 0
            AND duration_overage_fee_jpy = 0
            AND duration_overage_fee_cny = 0
          )
        )
        AND (
          greatest(
            duration_overage_minutes::numeric,
            duration_overage_fee_jpy,
            duration_overage_fee_cny
          ) = 0
          OR duration_overage_actual_count > 0
        )
      )
    );

COMMENT ON COLUMN public.school_lesson_records.student_duration_overage_minutes IS
  'S1-A inactive nullable snapshot. Positive duration-only overage minutes decided by the future ordinary actual RPC; legacy/partial/makeup/cancelled rows remain NULL.';
COMMENT ON COLUMN public.school_lesson_records.student_duration_overage_fee_jpy IS
  'S1-A inactive nullable snapshot. Pure tuition duration overage JPY only; excludes planned aircon fees and is not derived from planned lesson_fee total.';
COMMENT ON COLUMN public.school_lesson_records.student_duration_overage_policy_version IS
  'S1-A inactive policy marker. Approved value: student_duration_overage_v1. NULL is not charge eligibility.';
COMMENT ON COLUMN public.school_lesson_records.student_duration_overage_source IS
  'S1-A inactive source marker. Approved value: ordinary_actual_rpc.';
COMMENT ON COLUMN public.school_lesson_records.student_duration_overage_decided_at IS
  'S1-A inactive DB decision timestamp; no current writer populates it.';

COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_minutes IS
  'S1-A inactive locked-month aggregate snapshot; historical settlements remain NULL.';
COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_fee_jpy IS
  'S1-A inactive locked-month pure tuition overage JPY aggregate; excludes aircon.';
COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_fee_cny IS
  'S1-A inactive locked-month CNY aggregate rounded to at most two decimal places.';
COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_actual_count IS
  'S1-A inactive count of positive eligible ordinary actual snapshots in a future lock.';
COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_policy_version IS
  'S1-A inactive aggregate policy marker. Approved value: student_duration_overage_v1.';
COMMENT ON COLUMN public.school_student_monthly_settlements.duration_overage_source IS
  'S1-A inactive aggregate write source. Approved value: monthly_settlement_lock.';

COMMENT ON INDEX public.school_lesson_records_duration_overage_month_idx IS
  'S1-A empty until a future reviewed ordinary writer activates student_duration_overage_v1.';
COMMENT ON INDEX public.school_lesson_records_duration_overage_planned_uidx IS
  'S1-A new-policy ordinary idempotency only. It intentionally excludes legacy, partial, makeup, cancelled, and all-NULL rows.';

COMMIT;
