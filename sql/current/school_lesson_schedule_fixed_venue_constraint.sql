-- school_lesson_schedule_fixed_venue_constraint.sql
-- Purpose: Restrict new/updated onsite lessons to the two contracted Regus venues.
-- Status: EXECUTED ON SCHOOL DB. Structure and historical-row counts verified.
-- Version: v10.3.78-fixed-onsite-venue-constraint-20260714
--
-- Historical compatibility:
-- - The constraint is installed NOT VALID because one real historical/current
--   lesson still uses the legacy value "池袋Regus" and must not be guessed or
--   rewritten automatically.
-- - PostgreSQL still enforces a NOT VALID check constraint for all new or
--   updated rows. Existing legacy rows remain readable until explicitly edited.
-- - No historical lesson, settlement, wage, income, expense, Cash, account, or
--   account-transaction row is updated by this file.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_lesson_records_onsite_fixed_venue_check'
      and conrelid = 'public.school_lesson_records'::regclass
  ) then
    alter table public.school_lesson_records
      add constraint school_lesson_records_onsite_fixed_venue_check
      check (
        lesson_delivery_mode is distinct from 'onsite'
        or lesson_venue in ('Regus公共区', 'Regus办公室')
      ) not valid;
  end if;
end
$$;

comment on constraint school_lesson_records_onsite_fixed_venue_check
on public.school_lesson_records is
  'New or updated onsite lessons must use Regus公共区 or Regus办公室. Installed NOT VALID only to preserve explicitly unresolved legacy venue rows.';
