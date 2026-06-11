-- school_lesson_actual_minutes_sync_schema.sql
-- Purpose: Keep actual_minutes synchronized for actual school lessons.
-- Scope:
-- - Derive actual_minutes from duration_hours for actual completed /
--   makeup_completed rows.
-- - Keep cancelled actual rows at 0 minutes.
-- - Leave planned / pending_makeup rows unchanged.
-- - Does not modify historical rows when installed; it only affects future
--   inserts/updates.

create or replace function public.school_sync_lesson_actual_minutes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(new.app_type, '') = 'school'
    and new.lesson_type = 'actual'
    and new.status in ('completed', 'makeup_completed')
    and coalesce(new.duration_hours, 0) > 0
  then
    new.actual_minutes := round(new.duration_hours * 60)::integer;
  elsif coalesce(new.app_type, '') = 'school'
    and new.lesson_type = 'actual'
    and new.status = 'cancelled'
  then
    new.actual_minutes := 0;
  end if;

  return new;
end;
$$;

create or replace trigger trg_school_lesson_actual_minutes_sync
before insert or update of app_type, lesson_type, status, duration_hours, actual_minutes
on public.school_lesson_records
for each row
execute function public.school_sync_lesson_actual_minutes();

comment on function public.school_sync_lesson_actual_minutes()
is 'Synchronizes school_lesson_records.actual_minutes from duration_hours for actual completed/makeup_completed lessons and keeps cancelled actual lessons at 0 minutes. Does not change wage generation formulas.';
