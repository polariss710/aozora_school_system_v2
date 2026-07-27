-- School V2 tuition P0 R1D-B rollback tests.
-- Installs the exact schema file inside one transaction and always rolls back.
-- Fixed test IDs are transaction-local and must leave zero residue.

\set ON_ERROR_STOP on

begin;

\ir school_tuition_r1d_b_date_and_billing_attribution_schema.sql

do $test$
declare
  v_column_count integer;
  v_constraint_count integer;
  v_index_count integer;
  v_writer_count integer;
begin
  select count(*)
    into v_column_count
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'school_lesson_records'
    and column_name in (
      'billing_month',
      'billing_week_start_date',
      'scheduled_lesson_date',
      'student_settlement_month',
      'billing_month_source',
      'billing_month_decided_at'
    )
    and is_nullable = 'YES'
    and column_default is null;

  if v_column_count <> 6 then
    raise exception 'R1D_B_ROLLBACK_COLUMN_SHAPE_MISMATCH: %', v_column_count;
  end if;

  select count(*)
    into v_constraint_count
  from pg_constraint constraint_row
  join pg_class table_row on table_row.oid = constraint_row.conrelid
  join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
  where schema_row.nspname = 'public'
    and table_row.relname = 'school_lesson_records'
    and constraint_row.convalidated
    and constraint_row.conname in (
      'school_lesson_records_billing_month_format_chk',
      'school_lesson_records_student_settlement_month_format_chk',
      'school_lesson_records_billing_pair_complete_chk',
      'school_lesson_records_billing_week_monday_chk',
      'school_lesson_records_billing_month_week_match_chk',
      'school_lesson_records_planned_attribution_fields_chk',
      'school_lesson_records_billing_source_metadata_chk'
    );

  if v_constraint_count <> 7 then
    raise exception 'R1D_B_ROLLBACK_CONSTRAINT_SHAPE_MISMATCH: %', v_constraint_count;
  end if;

  select count(*)
    into v_index_count
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'school_lesson_records'
    and indexname in (
      'idx_school_lesson_records_planned_billing_month',
      'idx_school_lesson_records_planned_billing_week',
      'idx_school_lesson_records_student_settlement_month',
      'idx_school_lesson_records_planned_scheduled_date'
    );

  if v_index_count <> 4 then
    raise exception 'R1D_B_ROLLBACK_INDEX_SHAPE_MISMATCH: %', v_index_count;
  end if;

  select count(*)
    into v_writer_count
  from pg_proc function_row
  join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
  where schema_row.nspname = 'public'
    and function_row.prosrc ilike '%school_lesson_records%'
    and (
      function_row.prosrc ~* '\minsert[[:space:]]+into[[:space:]]+(public\.)?school_lesson_records'
      or function_row.prosrc ~* '\mupdate[[:space:]]+(public\.)?school_lesson_records'
    );

  if v_writer_count < 10 then
    raise exception 'R1D_B_ROLLBACK_WRITER_INVENTORY_UNEXPECTED: %', v_writer_count;
  end if;

  if exists (
    select 1
    from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.prosrc ilike '%school_lesson_records%'
      and function_row.prosrc ~* '\minsert[[:space:]]+into[[:space:]]+(public\.)?school_lesson_records[[:space:]]+values'
  ) then
    raise exception 'R1D_B_ROLLBACK_POSITIONAL_LESSON_INSERT_FOUND';
  end if;
end;
$test$;

do $test$
begin
  if public.school_iso_week_start(date '2026-07-29') <> date '2026-07-27' then
    raise exception 'R1D_B_ISO_WEEK_ORDINARY_FAILED';
  end if;
  if public.school_iso_week_start(date '2026-08-02') <> date '2026-07-27' then
    raise exception 'R1D_B_ISO_WEEK_CROSS_MONTH_FAILED';
  end if;
  if public.school_iso_week_start(date '2027-01-01') <> date '2026-12-28' then
    raise exception 'R1D_B_ISO_WEEK_CROSS_YEAR_FAILED';
  end if;
  if public.school_iso_week_start(date '2024-02-29') <> date '2024-02-26' then
    raise exception 'R1D_B_ISO_WEEK_LEAP_DAY_FAILED';
  end if;
  if public.school_iso_week_start(null::date) is not null then
    raise exception 'R1D_B_ISO_WEEK_NULL_FAILED';
  end if;

  if not public.school_is_valid_tuition_billing_period('2026-07', date '2026-07-27') then
    raise exception 'R1D_B_VALID_PAIR_JULY_FAILED';
  end if;
  if public.school_is_valid_tuition_billing_period('2026-08', date '2026-07-27') then
    raise exception 'R1D_B_INVALID_PAIR_JULY_IN_AUGUST_ACCEPTED';
  end if;
  if not public.school_is_valid_tuition_billing_period('2026-08', date '2026-08-31') then
    raise exception 'R1D_B_VALID_PAIR_AUGUST_FAILED';
  end if;
  if public.school_is_valid_tuition_billing_period('2026-09', date '2026-08-31') then
    raise exception 'R1D_B_INVALID_PAIR_AUGUST_IN_SEPTEMBER_ACCEPTED';
  end if;
  if not public.school_is_valid_tuition_billing_period('2026-12', date '2026-12-28') then
    raise exception 'R1D_B_VALID_PAIR_CROSS_YEAR_FAILED';
  end if;
  if public.school_is_valid_tuition_billing_period('2027-01', date '2026-12-28') then
    raise exception 'R1D_B_INVALID_PAIR_CROSS_YEAR_ACCEPTED';
  end if;
  if public.school_is_valid_tuition_billing_period('2026-07', date '2026-07-28') then
    raise exception 'R1D_B_NON_MONDAY_HELPER_ACCEPTED';
  end if;
  if public.school_is_valid_tuition_billing_period(null, date '2026-07-27') then
    raise exception 'R1D_B_NULL_MONTH_HELPER_ACCEPTED';
  end if;
end;
$test$;

-- Positive row proves scheduled date and billing week are independent facts.
insert into public.school_lesson_records (
  id,
  lesson_type,
  lesson_date,
  year_month,
  start_time,
  end_time,
  duration_hours,
  status,
  is_billable,
  app_type,
  import_source,
  billing_month,
  billing_week_start_date,
  scheduled_lesson_date,
  student_settlement_month,
  billing_month_source,
  billing_month_decided_at
)
values (
  'd1000000-0000-4000-8000-202607280001',
  'planned',
  date '2099-12-31',
  '2099-12',
  '10:00',
  '12:00',
  2,
  'planned',
  true,
  'school',
  'codex-test-r1d-b-rollback-positive',
  '2026-07',
  date '2026-07-27',
  date '2030-01-01',
  '2026-07',
  'codex-test-r1d-b-rollback',
  timestamptz '2026-07-28 00:00:00+00'
);

-- Old-shape explicit-column INSERT remains compatible and leaves all new facts NULL.
insert into public.school_lesson_records (
  id,
  lesson_type,
  lesson_date,
  year_month,
  duration_hours,
  status,
  is_billable,
  app_type,
  import_source
)
values (
  'd1000000-0000-4000-8000-202607280002',
  'planned',
  date '2099-12-30',
  '2099-12',
  1,
  'planned',
  true,
  'school',
  'codex-test-r1d-b-rollback-old-writer-shape'
);

do $test$
declare
  v_row public.school_lesson_date_semantics%rowtype;
begin
  select *
    into strict v_row
  from public.school_lesson_date_semantics
  where id = 'd1000000-0000-4000-8000-202607280001';

  if v_row.scheduled_lesson_date <> date '2030-01-01'
     or v_row.billing_week_start_date <> date '2026-07-27'
     or v_row.billing_month <> '2026-07'
     or v_row.legacy_lesson_date <> date '2099-12-31'
     or v_row.legacy_planned_scheduled_date_inferred <> date '2099-12-31'
     or v_row.actual_occurred_date is not null then
    raise exception 'R1D_B_SEMANTIC_VIEW_INDEPENDENCE_FAILED';
  end if;

  if exists (
    select 1
    from public.school_lesson_records lesson
    where lesson.id = 'd1000000-0000-4000-8000-202607280002'
      and (
        lesson.billing_month is not null
        or lesson.billing_week_start_date is not null
        or lesson.scheduled_lesson_date is not null
        or lesson.student_settlement_month is not null
        or lesson.billing_month_source is not null
        or lesson.billing_month_decided_at is not null
      )
  ) then
    raise exception 'R1D_B_OLD_WRITER_SHAPE_DERIVED_NEW_FACTS';
  end if;

  if (
    select is_updatable
    from information_schema.views
    where table_schema = 'public'
      and table_name = 'school_lesson_date_semantics'
  ) <> 'NO' then
    raise exception 'R1D_B_SEMANTIC_VIEW_IS_UPDATABLE';
  end if;
end;
$test$;

do $test$
begin
  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_month,
      billing_week_start_date
    ) values (
      'd1000000-0000-4000-8000-202607280011', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-non-monday', '2026-07', date '2026-07-28'
    );
    raise exception 'R1D_B_NON_MONDAY_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_month,
      billing_week_start_date
    ) values (
      'd1000000-0000-4000-8000-202607280012', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-month-mismatch', '2026-08', date '2026-07-27'
    );
    raise exception 'R1D_B_MONTH_WEEK_MISMATCH_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_month
    ) values (
      'd1000000-0000-4000-8000-202607280013', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-pair-left-only', '2026-07'
    );
    raise exception 'R1D_B_SINGLE_SIDED_PAIR_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_week_start_date
    ) values (
      'd1000000-0000-4000-8000-202607280014', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-pair-right-only', date '2026-07-27'
    );
    raise exception 'R1D_B_SINGLE_SIDED_PAIR_REVERSE_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_month,
      billing_week_start_date
    ) values (
      'd1000000-0000-4000-8000-202607280015', 'actual', date '2099-12-01',
      '2099-12', 1, 'completed', true, 'school',
      'codex-test-r1d-b-actual-planned-field', '2026-07', date '2026-07-27'
    );
    raise exception 'R1D_B_ACTUAL_PLANNED_FIELD_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, student_settlement_month
    ) values (
      'd1000000-0000-4000-8000-202607280016', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-invalid-month', '2026-13'
    );
    raise exception 'R1D_B_INVALID_MONTH_FORMAT_NOT_REJECTED';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.school_lesson_records (
      id, lesson_type, lesson_date, year_month, duration_hours, status,
      is_billable, app_type, import_source, billing_month,
      billing_week_start_date, billing_month_source
    ) values (
      'd1000000-0000-4000-8000-202607280017', 'planned', date '2099-12-01',
      '2099-12', 1, 'planned', true, 'school',
      'codex-test-r1d-b-source-without-time', '2026-07', date '2026-07-27',
      'codex-test-r1d-b-rollback'
    );
    raise exception 'R1D_B_INCOMPLETE_SOURCE_METADATA_NOT_REJECTED';
  exception when check_violation then
    null;
  end;
end;
$test$;

do $test$
begin
  if (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_B_OVERRIDE_AUDIT_NOT_EMPTY';
  end if;

  if has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'DELETE')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'DELETE') then
    raise exception 'R1D_B_OVERRIDE_AUDIT_UNTRUSTED_ROLE_PRIVILEGE';
  end if;

  if not has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'DELETE') then
    raise exception 'R1D_B_OVERRIDE_AUDIT_SERVICE_ROLE_PRIVILEGE_MISMATCH';
  end if;

  if has_table_privilege('anon', 'public.school_lesson_date_semantics', 'SELECT')
     or has_table_privilege('authenticated', 'public.school_lesson_date_semantics', 'SELECT')
     or not has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'SELECT')
     or has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'UPDATE') then
    raise exception 'R1D_B_SEMANTIC_VIEW_PRIVILEGE_MISMATCH';
  end if;
end;
$test$;

select
  'R1D_B_ROLLBACK_TRANSACTION_ACCEPTANCE' as check_name,
  (select count(*) from public.school_lesson_records where id in (
    'd1000000-0000-4000-8000-202607280001',
    'd1000000-0000-4000-8000-202607280002'
  )) as accepted_test_lessons,
  (select count(*) from public.school_tuition_billing_attribution_override_audit) as audit_rows,
  (select count(*) from public.school_lesson_records where billing_month is not null) as billing_rows,
  (select count(*) from public.school_lesson_records where scheduled_lesson_date is not null) as scheduled_rows;

rollback;

do $test$
begin
  if to_regprocedure('public.school_iso_week_start(date)') is not null
     or to_regprocedure('public.school_is_valid_tuition_billing_period(text,date)') is not null
     or to_regprocedure('public.school_guard_tuition_billing_override_audit_immutable()') is not null
     or to_regclass('public.school_lesson_date_semantics') is not null
     or to_regclass('public.school_tuition_billing_attribution_override_audit') is not null then
    raise exception 'R1D_B_ROLLBACK_OBJECT_RESIDUE';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'school_lesson_records'
      and column_name in (
        'billing_month',
        'billing_week_start_date',
        'scheduled_lesson_date',
        'student_settlement_month',
        'billing_month_source',
        'billing_month_decided_at'
      )
  ) then
    raise exception 'R1D_B_ROLLBACK_COLUMN_RESIDUE';
  end if;

  if exists (
    select 1
    from public.school_lesson_records
    where id::text like 'd1000000-0000-4000-8000-20260728%'
  ) then
    raise exception 'R1D_B_ROLLBACK_TEST_DATA_RESIDUE';
  end if;
end;
$test$;

select 'R1D_B_ROLLBACK_TESTS_OK' as result;
