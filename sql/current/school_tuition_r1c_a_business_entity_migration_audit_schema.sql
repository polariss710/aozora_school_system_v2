-- School V2 tuition P0 R1C-A: immutable business-entity migration audit.
-- Schema only. This file never changes lesson or financial business rows.
-- Required psql variable: r1c_schema_commit=0 for rollback validation or 1 for deployment.

\set ON_ERROR_STOP on

begin;

create table if not exists public.school_business_entity_migration_batches (
  id uuid primary key,
  migration_key text not null unique,
  migration_type text not null,
  target_year_month text not null,
  from_business_entity_id uuid not null,
  to_business_entity_id uuid not null,
  source_generation_batches jsonb not null,
  expected_lesson_count integer not null,
  expected_duration_hours numeric not null,
  expected_lesson_fee_jpy numeric not null,
  manifest_hash text not null,
  evidence_source text not null,
  approval_information jsonb not null,
  execution_status text not null,
  executed_at timestamptz,
  failure_reason text,
  created_at timestamptz not null default now(),
  created_by text not null default current_user,
  constraint school_be_migration_batches_from_fkey
    foreign key (from_business_entity_id)
    references public.school_business_entities(id)
    on delete restrict,
  constraint school_be_migration_batches_to_fkey
    foreign key (to_business_entity_id)
    references public.school_business_entities(id)
    on delete restrict,
  constraint school_be_migration_batches_type_check
    check (migration_type = 'planned_lesson_business_entity'),
  constraint school_be_migration_batches_month_check
    check (target_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_be_migration_batches_distinct_entities_check
    check (from_business_entity_id <> to_business_entity_id),
  constraint school_be_migration_batches_expected_count_check
    check (expected_lesson_count > 0),
  constraint school_be_migration_batches_expected_hours_check
    check (expected_duration_hours > 0),
  constraint school_be_migration_batches_expected_fee_check
    check (expected_lesson_fee_jpy >= 0),
  constraint school_be_migration_batches_manifest_hash_check
    check (manifest_hash ~ '^[0-9a-f]{32}$'),
  constraint school_be_migration_batches_evidence_not_blank_check
    check (length(btrim(evidence_source)) > 0),
  constraint school_be_migration_batches_status_check
    check (execution_status in ('executed', 'failed')),
  constraint school_be_migration_batches_execution_state_check
    check (
      (
        execution_status = 'executed'
        and executed_at is not null
        and failure_reason is null
      )
      or (
        execution_status = 'failed'
        and executed_at is null
        and length(btrim(failure_reason)) > 0
      )
    ),
  constraint school_be_migration_batches_key_not_blank_check
    check (length(btrim(migration_key)) > 0),
  constraint school_be_migration_batches_created_by_not_blank_check
    check (length(btrim(created_by)) > 0)
);

create table if not exists public.school_business_entity_migration_items (
  id uuid primary key,
  batch_id uuid not null,
  item_order integer not null,
  lesson_record_id uuid not null,
  student_id uuid not null,
  target_year_month text not null,
  source_generation_batch_id text not null,
  from_business_entity_id uuid not null,
  to_business_entity_id uuid not null,
  original_row_snapshot jsonb not null,
  before_hash text not null,
  original_updated_at timestamptz not null,
  evidence_source text not null,
  approval_information jsonb not null,
  execution_status text not null,
  after_row_snapshot jsonb,
  after_hash text,
  executed_at timestamptz,
  failure_reason text,
  created_at timestamptz not null default now(),
  created_by text not null default current_user,
  constraint school_be_migration_items_batch_fkey
    foreign key (batch_id)
    references public.school_business_entity_migration_batches(id)
    on delete restrict,
  constraint school_be_migration_items_lesson_fkey
    foreign key (lesson_record_id)
    references public.school_lesson_records(id)
    on delete restrict,
  constraint school_be_migration_items_student_fkey
    foreign key (student_id)
    references public.school_students(id)
    on delete restrict,
  constraint school_be_migration_items_from_fkey
    foreign key (from_business_entity_id)
    references public.school_business_entities(id)
    on delete restrict,
  constraint school_be_migration_items_to_fkey
    foreign key (to_business_entity_id)
    references public.school_business_entities(id)
    on delete restrict,
  constraint school_be_migration_items_batch_order_key
    unique (batch_id, item_order),
  constraint school_be_migration_items_batch_lesson_key
    unique (batch_id, lesson_record_id),
  constraint school_be_migration_items_order_check
    check (item_order > 0),
  constraint school_be_migration_items_month_check
    check (target_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_be_migration_items_source_batch_not_blank_check
    check (length(btrim(source_generation_batch_id)) > 0),
  constraint school_be_migration_items_distinct_entities_check
    check (from_business_entity_id <> to_business_entity_id),
  constraint school_be_migration_items_before_hash_check
    check (before_hash ~ '^[0-9a-f]{32}$'),
  constraint school_be_migration_items_after_hash_check
    check (after_hash is null or after_hash ~ '^[0-9a-f]{32}$'),
  constraint school_be_migration_items_evidence_not_blank_check
    check (length(btrim(evidence_source)) > 0),
  constraint school_be_migration_items_status_check
    check (execution_status in ('executed', 'failed')),
  constraint school_be_migration_items_execution_state_check
    check (
      (
        execution_status = 'executed'
        and after_row_snapshot is not null
        and after_hash is not null
        and executed_at is not null
        and failure_reason is null
      )
      or (
        execution_status = 'failed'
        and after_row_snapshot is null
        and after_hash is null
        and executed_at is null
        and length(btrim(failure_reason)) > 0
      )
    ),
  constraint school_be_migration_items_created_by_not_blank_check
    check (length(btrim(created_by)) > 0)
);

create index if not exists school_be_migration_items_lesson_idx
  on public.school_business_entity_migration_items (lesson_record_id, created_at);

create index if not exists school_be_migration_items_student_month_idx
  on public.school_business_entity_migration_items (student_id, target_year_month, item_order);

comment on table public.school_business_entity_migration_batches is
  'Immutable audit batches for explicitly approved, fixed-manifest business-entity migrations.';
comment on table public.school_business_entity_migration_items is
  'Immutable per-row before/after evidence for fixed-manifest business-entity migrations.';
comment on column public.school_business_entity_migration_items.original_row_snapshot is
  'Complete lesson row snapshot accepted only after the fixed manifest fingerprint matches.';
comment on column public.school_business_entity_migration_items.before_hash is
  'MD5 of the complete original lesson row represented as JSONB text.';
comment on column public.school_business_entity_migration_items.after_hash is
  'MD5 of the complete migrated lesson row represented as JSONB text.';

revoke all on table public.school_business_entity_migration_batches
  from public, anon, authenticated, service_role;
revoke all on table public.school_business_entity_migration_items
  from public, anon, authenticated, service_role;
grant select, insert on table public.school_business_entity_migration_batches
  to service_role;
grant select, insert on table public.school_business_entity_migration_items
  to service_role;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_business_entity_migration_batches'::regclass
      and tgname = 'school_be_migration_batches_immutable'
      and not tgisinternal
  ) then
    create trigger school_be_migration_batches_immutable
    before update or delete on public.school_business_entity_migration_batches
    for each row execute function public.school_guard_tuition_identity_or_lesson_immutable();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_business_entity_migration_items'::regclass
      and tgname = 'school_be_migration_items_immutable'
      and not tgisinternal
  ) then
    create trigger school_be_migration_items_immutable
    before update or delete on public.school_business_entity_migration_items
    for each row execute function public.school_guard_tuition_identity_or_lesson_immutable();
  end if;
end;
$$;

\if :r1c_schema_commit
  commit;
\else
  rollback;
\endif
