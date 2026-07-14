-- school_lesson_schedule_venue_schema.sql
-- Purpose: Add optional lesson delivery mode and venue fields for read-only
--          weekly schedule display and classroom conflict detection.
-- Scope:
-- - Schema only. No RPC/function definitions.
-- - No historical lesson backfill or business-data update.
-- - Existing rows remain NULL / NULL until explicitly edited through guarded RPCs.

alter table public.school_lesson_records
  add column if not exists lesson_delivery_mode text;

alter table public.school_lesson_records
  add column if not exists lesson_venue text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_lesson_records_delivery_mode_chk'
      and conrelid = 'public.school_lesson_records'::regclass
  ) then
    alter table public.school_lesson_records
      add constraint school_lesson_records_delivery_mode_chk
      check (
        lesson_delivery_mode is null
        or lesson_delivery_mode in ('onsite', 'online')
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_lesson_records_onsite_venue_chk'
      and conrelid = 'public.school_lesson_records'::regclass
  ) then
    alter table public.school_lesson_records
      add constraint school_lesson_records_onsite_venue_chk
      check (
        lesson_delivery_mode is distinct from 'onsite'
        or nullif(btrim(coalesce(lesson_venue, '')), '') is not null
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_lesson_records_venue_length_chk'
      and conrelid = 'public.school_lesson_records'::regclass
  ) then
    alter table public.school_lesson_records
      add constraint school_lesson_records_venue_length_chk
      check (
        lesson_venue is null
        or char_length(btrim(lesson_venue)) between 1 and 100
      );
  end if;
end
$$;

create index if not exists idx_school_lesson_records_schedule_venue
  on public.school_lesson_records (
    lesson_date,
    lesson_venue,
    start_time,
    end_time
  )
  where app_type = 'school'
    and lesson_delivery_mode = 'onsite'
    and lesson_venue is not null
    and voided_at is null;

comment on column public.school_lesson_records.lesson_delivery_mode is
  'Optional explicit lesson delivery mode. Supported values: onsite and online. NULL preserves historical rows without inferred backfill.';

comment on column public.school_lesson_records.lesson_venue is
  'Optional explicit venue or online platform label. Required for onsite lessons by constraint; historical rows remain NULL until explicitly edited.';

comment on index public.idx_school_lesson_records_schedule_venue is
  'Supports read-only weekly onsite venue scheduling and time-conflict detection without changing lesson write semantics.';
