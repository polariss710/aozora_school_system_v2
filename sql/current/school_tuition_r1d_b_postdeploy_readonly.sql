-- School V2 tuition P0 R1D-B postdeploy read-only acceptance.
-- SELECT/DO-only: no DDL, DML, role change, temporary object, or write RPC.

\set ON_ERROR_STOP on

do $check$
declare
  v_column_count integer;
  v_constraint_count integer;
  v_index_count integer;
  v_new_value_count bigint;
  v_lesson_count bigint;
  v_legacy_lesson_hash text;
  v_planned_count bigint;
  v_legacy_planned_hash text;
  v_actual_count bigint;
  v_legacy_actual_hash text;
  v_trigger_count integer;
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
    raise exception 'R1D_B_POSTDEPLOY_COLUMN_SHAPE_MISMATCH: %', v_column_count;
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
    raise exception 'R1D_B_POSTDEPLOY_CONSTRAINT_SHAPE_MISMATCH: %', v_constraint_count;
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
    raise exception 'R1D_B_POSTDEPLOY_INDEX_SHAPE_MISMATCH: %', v_index_count;
  end if;

  select count(*)
    into v_new_value_count
  from public.school_lesson_records lesson
  where lesson.billing_month is not null
     or lesson.billing_week_start_date is not null
     or lesson.scheduled_lesson_date is not null
     or lesson.student_settlement_month is not null
     or lesson.billing_month_source is not null
     or lesson.billing_month_decided_at is not null;

  if v_new_value_count <> 0 then
    raise exception 'R1D_B_POSTDEPLOY_NEW_FIELDS_NOT_EMPTY: %', v_new_value_count;
  end if;

  select
    count(*),
    md5(coalesce(string_agg(
      md5((
        to_jsonb(lesson)
        - 'billing_month'
        - 'billing_week_start_date'
        - 'scheduled_lesson_date'
        - 'student_settlement_month'
        - 'billing_month_source'
        - 'billing_month_decided_at'
      )::text),
      '' order by lesson.id::text
    ), ''))
  into v_lesson_count, v_legacy_lesson_hash
  from public.school_lesson_records lesson;

  select
    count(*),
    md5(coalesce(string_agg(
      md5((
        to_jsonb(lesson)
        - 'billing_month'
        - 'billing_week_start_date'
        - 'scheduled_lesson_date'
        - 'student_settlement_month'
        - 'billing_month_source'
        - 'billing_month_decided_at'
      )::text),
      '' order by lesson.id::text
    ), ''))
  into v_planned_count, v_legacy_planned_hash
  from public.school_lesson_records lesson
  where lesson.lesson_type = 'planned';

  select
    count(*),
    md5(coalesce(string_agg(
      md5((
        to_jsonb(lesson)
        - 'billing_month'
        - 'billing_week_start_date'
        - 'scheduled_lesson_date'
        - 'student_settlement_month'
        - 'billing_month_source'
        - 'billing_month_decided_at'
      )::text),
      '' order by lesson.id::text
    ), ''))
  into v_actual_count, v_legacy_actual_hash
  from public.school_lesson_records lesson
  where lesson.lesson_type = 'actual';

  if v_lesson_count <> 626
     or v_legacy_lesson_hash <> '4fb1901c888d56cb29c05e387490ca75'
     or v_planned_count <> 397
     or v_legacy_planned_hash <> 'b11602c7d2b1bf3c87d9d4c3763c0b3e'
     or v_actual_count <> 229
     or v_legacy_actual_hash <> 'fe752c448bb4d38af498136d3149f14a' then
    raise exception 'R1D_B_POSTDEPLOY_LESSON_BASELINE_CHANGED: lesson %/%, planned %/%, actual %/%',
      v_lesson_count,
      v_legacy_lesson_hash,
      v_planned_count,
      v_legacy_planned_hash,
      v_actual_count,
      v_legacy_actual_hash;
  end if;

  select count(*)
    into v_trigger_count
  from pg_trigger trigger_row
  join pg_class table_row on table_row.oid = trigger_row.tgrelid
  join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
  where not trigger_row.tgisinternal
    and schema_row.nspname = 'public'
    and table_row.relname = 'school_lesson_records'
    and trigger_row.tgenabled = 'O'
    and trigger_row.tgname in (
      'trg_school_lesson_actual_minutes_sync',
      'trg_school_lesson_inherit_schedule_venue',
      'trg_school_lesson_records_updated_at'
    );

  if v_trigger_count <> 3 then
    raise exception 'R1D_B_POSTDEPLOY_EXISTING_TRIGGER_CHANGED: %', v_trigger_count;
  end if;
end;
$check$;

do $check$
declare
  v_view_updatable text;
begin
  if to_regprocedure('public.school_iso_week_start(date)') is null
     or to_regprocedure('public.school_is_valid_tuition_billing_period(text,date)') is null
     or to_regprocedure('public.school_guard_tuition_billing_override_audit_immutable()') is null
     or to_regclass('public.school_lesson_date_semantics') is null
     or to_regclass('public.school_tuition_billing_attribution_override_audit') is null then
    raise exception 'R1D_B_POSTDEPLOY_OBJECT_MISSING';
  end if;

  if not exists (
    select 1
    from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.proname = 'school_iso_week_start'
      and function_row.provolatile = 'i'
      and function_row.proparallel = 's'
      and function_row.proisstrict
      and function_row.prosecdef = false
      and function_row.proconfig = array['search_path=pg_catalog']
  ) then
    raise exception 'R1D_B_POSTDEPLOY_ISO_HELPER_METADATA_MISMATCH';
  end if;

  if not exists (
    select 1
    from pg_proc function_row
    join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.proname = 'school_is_valid_tuition_billing_period'
      and function_row.provolatile = 'i'
      and function_row.proparallel = 's'
      and function_row.prosecdef = false
      and function_row.proconfig = array['search_path=pg_catalog']
  ) then
    raise exception 'R1D_B_POSTDEPLOY_PAIR_HELPER_METADATA_MISMATCH';
  end if;

  if has_function_privilege('anon', 'public.school_iso_week_start(date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.school_iso_week_start(date)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.school_iso_week_start(date)', 'EXECUTE')
     or has_function_privilege('anon', 'public.school_is_valid_tuition_billing_period(text,date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.school_is_valid_tuition_billing_period(text,date)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.school_is_valid_tuition_billing_period(text,date)', 'EXECUTE') then
    raise exception 'R1D_B_POSTDEPLOY_HELPER_PRIVILEGE_MISMATCH';
  end if;

  select is_updatable
    into v_view_updatable
  from information_schema.views
  where table_schema = 'public'
    and table_name = 'school_lesson_date_semantics';

  if v_view_updatable is distinct from 'NO'
     or has_table_privilege('anon', 'public.school_lesson_date_semantics', 'SELECT')
     or has_table_privilege('authenticated', 'public.school_lesson_date_semantics', 'SELECT')
     or not has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'SELECT')
     or has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'INSERT')
     or has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'UPDATE')
     or has_table_privilege('service_role', 'public.school_lesson_date_semantics', 'DELETE') then
    raise exception 'R1D_B_POSTDEPLOY_SEMANTIC_VIEW_ACCESS_MISMATCH';
  end if;

  if (select count(*) from public.school_lesson_date_semantics) <> 626
     or exists (
       select 1
       from public.school_lesson_date_semantics semantics
       where semantics.scheduled_lesson_date is not null
          or semantics.billing_week_start_date is not null
          or semantics.billing_month is not null
          or semantics.student_settlement_month is not null
          or semantics.billing_month_source is not null
          or semantics.billing_month_decided_at is not null
     ) then
    raise exception 'R1D_B_POSTDEPLOY_SEMANTIC_VIEW_NULL_SEMANTICS_CHANGED';
  end if;
end;
$check$;

do $check$
begin
  if (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_B_POSTDEPLOY_OVERRIDE_AUDIT_NOT_EMPTY';
  end if;

  if has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('anon', 'public.school_tuition_billing_attribution_override_audit', 'DELETE')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('authenticated', 'public.school_tuition_billing_attribution_override_audit', 'DELETE')
     or not has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'SELECT')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'INSERT')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'UPDATE')
     or has_table_privilege('service_role', 'public.school_tuition_billing_attribution_override_audit', 'DELETE') then
    raise exception 'R1D_B_POSTDEPLOY_OVERRIDE_AUDIT_PRIVILEGE_MISMATCH';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger_row
    join pg_class table_row on table_row.oid = trigger_row.tgrelid
    join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
    where not trigger_row.tgisinternal
      and schema_row.nspname = 'public'
      and table_row.relname = 'school_tuition_billing_attribution_override_audit'
      and trigger_row.tgname = 'school_tuition_billing_override_audit_immutable'
      and trigger_row.tgenabled = 'O'
  ) then
    raise exception 'R1D_B_POSTDEPLOY_OVERRIDE_AUDIT_TRIGGER_MISSING';
  end if;
end;
$check$;

do $check$
begin
  if public.school_iso_week_start(date '2026-08-02') <> date '2026-07-27'
     or public.school_iso_week_start(date '2027-01-01') <> date '2026-12-28'
     or public.school_iso_week_start(date '2024-02-29') <> date '2024-02-26'
     or public.school_iso_week_start(null::date) is not null then
    raise exception 'R1D_B_POSTDEPLOY_ISO_HELPER_RESULT_MISMATCH';
  end if;

  if not public.school_is_valid_tuition_billing_period('2026-07', date '2026-07-27')
     or public.school_is_valid_tuition_billing_period('2026-08', date '2026-07-27')
     or not public.school_is_valid_tuition_billing_period('2026-08', date '2026-08-31')
     or public.school_is_valid_tuition_billing_period('2026-09', date '2026-08-31')
     or not public.school_is_valid_tuition_billing_period('2026-12', date '2026-12-28')
     or public.school_is_valid_tuition_billing_period('2027-01', date '2026-12-28')
     or public.school_is_valid_tuition_billing_period('2026-07', date '2026-07-28') then
    raise exception 'R1D_B_POSTDEPLOY_PAIR_HELPER_RESULT_MISMATCH';
  end if;
end;
$check$;

do $check$
declare
  v_changed_writer_count integer;
begin
  select count(*)
    into v_changed_writer_count
  from pg_proc function_row
  join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
  where schema_row.nspname = 'public'
    and function_row.prosrc ilike '%school_lesson_records%'
    and (
      function_row.prosrc ~* '\minsert[[:space:]]+into[[:space:]]+(public\.)?school_lesson_records'
      or function_row.prosrc ~* '\mupdate[[:space:]]+(public\.)?school_lesson_records'
    )
    and (
      function_row.prosrc ilike '%billing_week_start_date%'
      or function_row.prosrc ilike '%scheduled_lesson_date%'
      or function_row.prosrc ilike '%student_settlement_month%'
      or function_row.prosrc ilike '%billing_month_source%'
      or function_row.prosrc ilike '%billing_month_decided_at%'
    );

  if v_changed_writer_count <> 0 then
    raise exception 'R1D_B_POSTDEPLOY_WRITER_SWITCH_DETECTED: %', v_changed_writer_count;
  end if;

  if md5(pg_get_functiondef('public.school_classify_student_tuition_candidate(boolean,boolean,text[],boolean,boolean,text,text,timestamp with time zone,boolean,boolean)'::regprocedure))
       <> '759738bc62c558b5d29e2078b06ea297'
     or md5(pg_get_functiondef('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure))
       <> '1d9149f6e3ff02305d0963f81af9f0b9'
     or md5(pg_get_functiondef('public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure))
       <> 'ea71010c17f880ee61092bb8e01ea920' then
    raise exception 'R1D_B_POSTDEPLOY_CANDIDATE_OR_PREVIEW_DEFINITION_CHANGED';
  end if;
end;
$check$;

do $check$
begin
  if (select count(*) from public.school_student_tuition_bills) <> 9
     or (select count(*) from public.school_income_records) <> 42
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'canonical_charge') <> 85
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'incident_duplicate') <> 24
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'legacy_cancelled') <> 12
     or (select count(*) from public.school_student_tuition_bill_lessons where scheduled_lesson_date_snapshot is not null) <> 0
     or (select count(*) from public.school_student_tuition_bill_lessons where week_start_date_snapshot is not null) <> 0
     or exists (
       select 1
       from public.school_student_tuition_bill_lessons relation
       join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
       where relation.source_snapshot -> 'current_planned_lesson'
         is distinct from (
           to_jsonb(lesson)
           - 'billing_month'
           - 'billing_week_start_date'
           - 'scheduled_lesson_date'
           - 'student_settlement_month'
           - 'billing_month_source'
           - 'billing_month_decided_at'
         )
     ) then
    raise exception 'R1D_B_POSTDEPLOY_HISTORICAL_TUITION_BASELINE_CHANGED';
  end if;

  if (
    select count(*)
    from public.school_student_tuition_bills bill
    join public.school_income_records income
      on income.id = bill.income_record_id
     and income.tuition_bill_id = bill.id
     and income.source_type = 'student_tuition_bill'
     and income.source_id = bill.id
  ) <> 9 then
    raise exception 'R1D_B_POSTDEPLOY_BILL_INCOME_PAIR_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates) <> 3
     or not exists (
       select 1 from public.school_feature_gates
       where feature_key = 'student_tuition_preview'
         and state = 'validation_preview_only'
     )
     or not exists (
       select 1 from public.school_feature_gates
       where feature_key = 'student_tuition_generate'
         and state = 'blocked'
     )
     or not exists (
       select 1 from public.school_feature_gates
       where feature_key = 'student_tuition_cash_submit'
         and state = 'blocked'
     ) then
    raise exception 'R1D_B_POSTDEPLOY_R0_GATE_CHANGED';
  end if;
end;
$check$;

do $check$
begin
  if (select count(*) from public.school_business_entity_migration_batches) <> 2
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_business_entity_migration_batches row_value)
       <> '18e74c21ebf95fdf80bed6767a4e28be'
     or (select count(*) from public.school_business_entity_migration_items) <> 118
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_business_entity_migration_items row_value)
       <> '23a2f93d0db01d84ba6195573ec58790' then
    raise exception 'R1D_B_POSTDEPLOY_MIGRATION_AUDIT_BASELINE_CHANGED';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    left join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
    where item.batch_id in (
      'c1000000-0000-4000-8000-202607279999',
      'c1000000-0000-4000-8000-202607289999'
    )
      and (
        lesson.id is null
        or (
          to_jsonb(lesson)
          - 'billing_month'
          - 'billing_week_start_date'
          - 'scheduled_lesson_date'
          - 'student_settlement_month'
          - 'billing_month_source'
          - 'billing_month_decided_at'
        ) is distinct from item.after_row_snapshot
        or lesson.updated_at is distinct from item.original_updated_at
        or md5(item.original_row_snapshot::text) <> item.before_hash
        or md5(item.after_row_snapshot::text) <> item.after_hash
      )
  ) then
    raise exception 'R1D_B_POSTDEPLOY_FIXED_52_OR_66_LEGACY_ROW_CHANGED';
  end if;

  if exists (
    with scopes as (
      select distinct
        item.batch_id,
        item.student_id,
        item.to_business_entity_id,
        item.target_year_month
      from public.school_business_entity_migration_items item
      where item.batch_id in (
        'c1000000-0000-4000-8000-202607279999',
        'c1000000-0000-4000-8000-202607289999'
      )
    ),
    expected as (
      select item.batch_id, item.lesson_record_id
      from public.school_business_entity_migration_items item
      where item.batch_id in (
        'c1000000-0000-4000-8000-202607279999',
        'c1000000-0000-4000-8000-202607289999'
      )
    ),
    actual_candidates as (
      select scope.batch_id, candidate.planned_lesson_id as lesson_record_id
      from scopes scope
      cross join lateral public.school_list_student_tuition_candidates(
        scope.student_id,
        scope.to_business_entity_id,
        scope.target_year_month,
        false
      ) candidate
      where candidate.candidate_status = 'candidate'
    ),
    mismatch as (
      (select * from expected except select * from actual_candidates)
      union all
      (select * from actual_candidates except select * from expected)
    )
    select 1 from mismatch
  ) then
    raise exception 'R1D_B_POSTDEPLOY_FIXED_52_OR_66_CANDIDATE_SET_CHANGED';
  end if;

  if exists (
    with li_fixed(lesson_record_id, expected_row_hash) as (
      values
        ('f256bca9-fac5-4909-b113-8077efd27d65'::uuid, '39a3d5ccc1755499b54595b303c49cc5'),
        ('a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid, 'f7b3636134ebd23191c5b6ea37c0d204'),
        ('265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid, '6620ad1a8085077dbb8e4d4317f0af8f'),
        ('e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid, 'b707e69e1ece74e9b6edf2e44483f512'),
        ('552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid, '82a2d4d62f96c07a3bb65a2c2e8b92a1'),
        ('b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid, '3ac247e72ba1e8e55484d5bb96052a9c'),
        ('ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid, '0c32bffa1f171517a1c034b0cb6d1195'),
        ('39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid, 'c46cc189dac5ac53ba455838af5859e0'),
        ('f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid, '4fff65ea2500ba5613d3927f2cd8042c'),
        ('c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid, '91679ca8877c299bf02faaf56fdfee8c'),
        ('dc06b98c-360f-4661-a294-52ecb82830a7'::uuid, '04099067c0430d749487c2170b1ec5d8')
    )
    select 1
    from li_fixed expected
    left join public.school_lesson_records lesson on lesson.id = expected.lesson_record_id
    where lesson.id is null
       or md5((
         to_jsonb(lesson)
         - 'billing_month'
         - 'billing_week_start_date'
         - 'scheduled_lesson_date'
         - 'student_settlement_month'
         - 'billing_month_source'
         - 'billing_month_decided_at'
       )::text) <> expected.expected_row_hash
       or exists (
         select 1
         from public.school_business_entity_migration_items item
         where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
           and item.lesson_record_id = expected.lesson_record_id
       )
  ) then
    raise exception 'R1D_B_POSTDEPLOY_LI_FIXED_11_CHANGED';
  end if;
end;
$check$;

select
  'r1d_b_lesson_new_field_population' as result_set,
  count(*) as total_lessons,
  count(*) filter (where lesson_type = 'planned') as planned_lessons,
  count(*) filter (where lesson_type = 'actual') as actual_lessons,
  count(*) filter (where billing_month is not null) as billing_month_nonnull,
  count(*) filter (where billing_week_start_date is not null) as billing_week_nonnull,
  count(*) filter (where scheduled_lesson_date is not null) as scheduled_date_nonnull,
  count(*) filter (where student_settlement_month is not null) as student_settlement_nonnull,
  count(*) filter (where billing_month_source is not null) as billing_source_nonnull,
  count(*) filter (where billing_month_decided_at is not null) as billing_decided_nonnull
from public.school_lesson_records;

select
  'r1d_b_cross_month_canonical_evidence' as result_set,
  lesson.id,
  lesson.lesson_date,
  lesson.year_month,
  relation.billing_month_snapshot,
  relation.week_start_date_snapshot,
  relation.scheduled_lesson_date_snapshot,
  lesson.billing_month,
  lesson.billing_week_start_date,
  lesson.scheduled_lesson_date,
  lesson.student_settlement_month
from public.school_lesson_records lesson
join public.school_student_tuition_bill_lessons relation
  on relation.planned_lesson_id = lesson.id
 and relation.relation_role = 'canonical_charge'
where lesson.id in (
  '8b737b58-cd14-42c5-afd2-34730dcef963',
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
)
order by lesson.id;

select
  'r1d_b_helper_examples' as result_set,
  public.school_iso_week_start(date '2026-08-02') as august_second_iso_monday,
  public.school_iso_week_start(date '2027-01-01') as cross_year_iso_monday,
  public.school_is_valid_tuition_billing_period('2026-07', date '2026-07-27') as july_pair_valid,
  public.school_is_valid_tuition_billing_period('2026-08', date '2026-07-27') as july_week_in_august_valid,
  public.school_is_valid_tuition_billing_period('2026-08', date '2026-08-31') as august_pair_valid,
  public.school_is_valid_tuition_billing_period('2026-09', date '2026-08-31') as august_week_in_september_valid;

select 'R1D_B_POSTDEPLOY_READONLY_OK' as result;
