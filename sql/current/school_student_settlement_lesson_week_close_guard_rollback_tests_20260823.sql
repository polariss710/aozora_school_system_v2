\set ON_ERROR_STOP on

-- Rollback tests for the student settlement lesson-week close guard.
--
-- This file is read-only with respect to business data: no business table is
-- read, written, or locked, and no writer RPC is called. It mainly evaluates
-- the stable function
-- school_get_student_settlement_month_write_eligibility_at_core at explicit
-- reference times.
--
-- It is not literally read-only against the database: it creates one helper
-- function in pg_temp (a catalog write in the temporary schema), and tests 8
-- and 9 read the pg_proc / pg_namespace system catalogs. The surrounding
-- transaction is rolled back regardless.
--
-- Run:
--   psql "$SCHOOL_SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f sql/current/school_student_settlement_lesson_week_close_guard_rollback_tests_20260823.sql

begin;
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- Helper: evaluate the guard as of a given Asia/Tokyo business date.
-- ---------------------------------------------------------------------------
create or replace function pg_temp.at_business_date(
  p_year_month text,
  p_business_date date
)
returns jsonb
language sql
stable
as $$
  select public.school_get_student_settlement_month_write_eligibility_at_core(
    p_year_month,
    (p_business_date::text || ' 12:00:00+09')::timestamptz
  );
$$;

-- ---------------------------------------------------------------------------
-- Test 1  Contract version was bumped.
-- ---------------------------------------------------------------------------
do $t1$
declare v jsonb;
begin
  v := pg_temp.at_business_date('2026-08', date '2026-09-07');
  if v->>'contract_version'
     is distinct from 'student_settlement_lesson_week_close_v2' then
    raise exception 'T1_CONTRACT_VERSION_MISMATCH: %', v->>'contract_version';
  end if;
end
$t1$;

-- ---------------------------------------------------------------------------
-- Test 2  The reported defect. 2026-08-31 is a Monday, so 2026-08 lessons run
--         through 2026-09-06. The guard must refuse 2026-09-01 .. 2026-09-06
--         and open on 2026-09-07.
-- ---------------------------------------------------------------------------
do $t2$
declare
  v jsonb;
  d date;
begin
  if extract(isodow from date '2026-08-31') <> 1 then
    raise exception 'T2_PRECONDITION_FAILED: 2026-08-31 is not a Monday';
  end if;

  for d in select generate_series(date '2026-09-01', date '2026-09-06',
                                  interval '1 day')::date
  loop
    v := pg_temp.at_business_date('2026-08', d);
    if v->>'classification' <> 'lesson_week_open'
       or (v->>'write_allowed')::boolean is not false
       or v->>'save_blocker_code' <> 'SETTLEMENT_LESSON_WEEK_NOT_CLOSED'
       or v->>'lock_blocker_code' <> 'SETTLEMENT_LESSON_WEEK_NOT_CLOSED' then
      raise exception 'T2_SHOULD_BE_BLOCKED on %: %', d, v;
    end if;
    if nullif(trim(coalesce(v->>'save_blocker_message','')),'') is null
       or nullif(trim(coalesce(v->>'lock_blocker_message','')),'') is null then
      raise exception 'T2_BLOCKER_MESSAGE_EMPTY on %: %', d, v;
    end if;
  end loop;

  v := pg_temp.at_business_date('2026-08', date '2026-09-07');
  if v->>'classification' <> 'closed'
     or (v->>'write_allowed')::boolean is not true
     or v->>'save_blocker_code' is not null
     or v->>'lock_blocker_code' is not null then
    raise exception 'T2_SHOULD_BE_OPEN on 2026-09-07: %', v;
  end if;
end
$t2$;

-- ---------------------------------------------------------------------------
-- Test 3  Independent cross-check, not a restatement of the implementation.
--
--         Derived from the attribution rule alone: a lesson belongs to month M
--         iff the Monday of its week falls in M. The last such lesson date is
--         (last Monday in M) + 6 days, so M is complete on (last Monday) + 7.
--         "Last Monday in M" is computed here by scanning M's calendar days,
--         with no reference to date_trunc('week', ...).
--
--         Asserted over every month of 2025..2028, which covers all seven
--         possible weekday alignments of a month's first day, both leap and
--         non-leap February, and months where the last day is itself a Sunday
--         (no cross-month week at all).
-- ---------------------------------------------------------------------------
do $t3$
declare
  m date;
  v_year_month text;
  v_last_monday date;
  v_expected_open date;
  v jsonb;
  v_checked integer := 0;
  v_no_cross_month integer := 0;
begin
  for m in select generate_series(date '2025-01-01', date '2028-12-01',
                                  interval '1 month')::date
  loop
    v_year_month := to_char(m, 'YYYY-MM');

    select max(d)::date into strict v_last_monday
    from generate_series(
      m,
      (m + interval '1 month - 1 day')::date,
      interval '1 day'
    ) d
    where extract(isodow from d) = 1;

    v_expected_open := v_last_monday + 7;

    -- Day before the expected open date: must still be refused.
    v := pg_temp.at_business_date(v_year_month, v_expected_open - 1);
    if (v->>'write_allowed')::boolean is not false then
      raise exception
        'T3_OPENED_TOO_EARLY month=% on % payload=%',
        v_year_month, v_expected_open - 1, v;
    end if;

    -- Expected open date: must be writable.
    v := pg_temp.at_business_date(v_year_month, v_expected_open);
    if (v->>'write_allowed')::boolean is not true
       or v->>'classification' <> 'closed' then
      raise exception
        'T3_DID_NOT_OPEN month=% on % payload=%',
        v_year_month, v_expected_open, v;
    end if;

    v_checked := v_checked + 1;
    if v_expected_open = (m + interval '1 month')::date then
      v_no_cross_month := v_no_cross_month + 1;
    end if;
  end loop;

  if v_checked <> 48 then
    raise exception 'T3_UNEXPECTED_MONTH_COUNT: %', v_checked;
  end if;
  -- Sanity: the degenerate "no cross-month week" case must actually occur in
  -- the sampled range, otherwise this test never exercised it.
  if v_no_cross_month = 0 then
    raise exception 'T3_NO_CROSS_MONTH_CASE_NEVER_EXERCISED';
  end if;

  raise notice 'T3 ok: % months checked, % with no cross-month week',
    v_checked, v_no_cross_month;
end
$t3$;

-- ---------------------------------------------------------------------------
-- Test 4  Regression: current month and future month behaviour is unchanged.
-- ---------------------------------------------------------------------------
do $t4$
declare v jsonb;
begin
  v := pg_temp.at_business_date('2026-08', date '2026-08-23');
  if v->>'classification' <> 'current'
     or v->>'save_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED'
     or v->>'lock_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED'
     or (v->>'write_allowed')::boolean is not false then
    raise exception 'T4_CURRENT_MONTH_REGRESSION: %', v;
  end if;

  v := pg_temp.at_business_date('2026-09', date '2026-08-23');
  if v->>'classification' <> 'future'
     or v->>'save_blocker_code' <> 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED'
     or (v->>'write_allowed')::boolean is not false then
    raise exception 'T4_FUTURE_MONTH_REGRESSION: %', v;
  end if;

  -- The first days of a month must still classify the current month as
  -- `current`, not `lesson_week_open`.
  v := pg_temp.at_business_date('2026-09', date '2026-09-01');
  if v->>'classification' <> 'current' then
    raise exception 'T4_CURRENT_MONTH_MISCLASSIFIED_ON_DAY_ONE: %', v;
  end if;
end
$t4$;

-- ---------------------------------------------------------------------------
-- Test 5  Regression: older months are never reclassified. For every business
--         date in a two-year window, any month two or more months older than
--         the business month must stay `closed`.
-- ---------------------------------------------------------------------------
do $t5$
declare
  d date;
  v jsonb;
  v_target text;
begin
  for d in select generate_series(date '2026-01-01', date '2027-12-31',
                                  interval '1 day')::date
  loop
    v_target := to_char(
      (date_trunc('month', d) - interval '2 months')::date, 'YYYY-MM');
    v := pg_temp.at_business_date(v_target, d);
    if v->>'classification' <> 'closed'
       or (v->>'write_allowed')::boolean is not true then
      raise exception
        'T5_HISTORICAL_MONTH_RECLASSIFIED business_date=% target=% payload=%',
        d, v_target, v;
    end if;
  end loop;
end
$t5$;

-- ---------------------------------------------------------------------------
-- Test 6  Regression: invalid input still fails closed.
-- ---------------------------------------------------------------------------
do $t6$
declare
  v jsonb;
  v_bad text;
begin
  foreach v_bad in array array['2026-13', '2026-00', '202608', '2026-8', 'x']
  loop
    v := pg_temp.at_business_date(v_bad, date '2026-09-07');
    if v->>'classification' <> 'invalid'
       or (v->>'write_allowed')::boolean is not false
       or v->>'save_blocker_code' <> 'SETTLEMENT_MONTH_INVALID' then
      raise exception 'T6_INVALID_INPUT_NOT_FAIL_CLOSED input=% payload=%',
        v_bad, v;
    end if;
  end loop;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', null);
  if v->>'classification' <> 'invalid'
     or (v->>'write_allowed')::boolean is not false then
    raise exception 'T6_NULL_REFERENCE_TIME_NOT_FAIL_CLOSED: %', v;
  end if;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    null, '2026-09-07 12:00:00+09'::timestamptz);
  if v->>'classification' <> 'invalid'
     or (v->>'write_allowed')::boolean is not false then
    raise exception 'T6_NULL_MONTH_NOT_FAIL_CLOSED: %', v;
  end if;
end
$t6$;

-- ---------------------------------------------------------------------------
-- Test 7  Timezone: the boundary is Asia/Tokyo, not UTC. 2026-09-06 23:00 JST
--         is still blocked; 2026-09-07 00:30 JST is open. Both instants fall on
--         2026-09-06 in UTC, so a UTC-based implementation would fail this.
-- ---------------------------------------------------------------------------
do $t7$
declare v jsonb;
begin
  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-09-06 23:00:00+09'::timestamptz);
  if (v->>'write_allowed')::boolean is not false
     or v->>'business_today' <> '2026-09-06' then
    raise exception 'T7_JST_LATE_EVENING_SHOULD_BE_BLOCKED: %', v;
  end if;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-09-07 00:30:00+09'::timestamptz);
  if (v->>'write_allowed')::boolean is not true
     or v->>'business_today' <> '2026-09-07' then
    raise exception 'T7_JST_EARLY_MORNING_SHOULD_BE_OPEN: %', v;
  end if;
end
$t7$;

-- ---------------------------------------------------------------------------
-- Test 8  Permissions: the eligibility core must stay owner-only.
-- ---------------------------------------------------------------------------
do $t8$
declare
  v_oid oid;
  v_role text;
begin
  select p.oid into strict v_oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'school_get_student_settlement_month_write_eligibility_at_core';

  if (select proowner from pg_proc where oid = v_oid)
     <> 'postgres'::regrole then
    raise exception 'T8_OWNER_NOT_POSTGRES';
  end if;
  if not (select prosecdef from pg_proc where oid = v_oid) then
    raise exception 'T8_NOT_SECURITY_DEFINER';
  end if;
  if (select proconfig from pg_proc where oid = v_oid)
     is distinct from array['search_path=pg_catalog, public']::text[] then
    raise exception 'T8_SEARCH_PATH_NOT_PINNED';
  end if;

  foreach v_role in array array['public','anon','authenticated','service_role']
  loop
    if has_function_privilege(v_role, v_oid, 'EXECUTE') then
      raise exception 'T8_EXECUTE_GRANTED_TO_%', v_role;
    end if;
  end loop;
end
$t8$;

-- ---------------------------------------------------------------------------
-- Test 9  The five writers still carry the month-write assert, so the new rule
--         actually reaches every write path.
-- ---------------------------------------------------------------------------
do $t9$
declare
  v_name text;
  v_definition text;
begin
  foreach v_name in array array[
    'school_save_student_settlement_draft_local',
    'school_lock_student_monthly_settlement_local',
    'school_lock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment',
    'school_set_student_settlement_source_treatment_draft'
  ] loop
    select pg_get_functiondef(p.oid) into strict v_definition
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_name;
    if position('school_assert_student_settlement_month_write_allowed'
                in v_definition) = 0 then
      raise exception 'T9_WRITER_GUARD_MISSING: %', v_name;
    end if;
  end loop;
end
$t9$;

do $done$
begin
  raise notice 'lesson-week close guard rollback tests: all passed';
end
$done$;

rollback;
