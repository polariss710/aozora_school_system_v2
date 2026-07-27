-- School V2 tuition P0 R1A: immutable-row trigger functions and triggers.
-- This file creates functions/triggers only; it does not change business rows.

begin;

create or replace function public.school_guard_tuition_identity_or_lesson_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'TUITION_IMMUTABLE_ROW: % rows cannot be updated or deleted.', tg_table_name;
end;
$$;

revoke all on function public.school_guard_tuition_identity_or_lesson_immutable()
  from public, anon, authenticated;

create or replace function public.school_guard_incident_quarantined_income_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'incident_quarantined' then
    raise exception 'TUITION_INCIDENT_IMMUTABLE: quarantined income rows cannot be updated or deleted.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.school_guard_incident_quarantined_income_immutable()
  from public, anon, authenticated;

drop trigger if exists school_tuition_billing_identities_immutable
  on public.school_student_tuition_billing_identities;
create trigger school_tuition_billing_identities_immutable
before update or delete on public.school_student_tuition_billing_identities
for each row execute function public.school_guard_tuition_identity_or_lesson_immutable();

drop trigger if exists school_tuition_bill_lessons_immutable
  on public.school_student_tuition_bill_lessons;
create trigger school_tuition_bill_lessons_immutable
before update or delete on public.school_student_tuition_bill_lessons
for each row execute function public.school_guard_tuition_identity_or_lesson_immutable();

drop trigger if exists school_incident_quarantined_income_immutable
  on public.school_income_records;
create trigger school_incident_quarantined_income_immutable
before update or delete on public.school_income_records
for each row execute function public.school_guard_incident_quarantined_income_immutable();

commit;
