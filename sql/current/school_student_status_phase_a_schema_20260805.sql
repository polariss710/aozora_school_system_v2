-- School V2 student monthly status Phase A schema, 2026-08-05.
-- Schema only: one append-oriented status event table and mutation guards.

create table public.school_student_status_events (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null
    references public.school_students(id) on delete restrict,
  effective_month date not null,
  status text not null,
  reason text not null,
  row_version uuid not null default gen_random_uuid(),
  created_by_user_id uuid not null
    references auth.users(id) on delete restrict,
  created_by_membership_id uuid not null
    references public.school_app_memberships(user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  voided_at timestamptz null,
  voided_by_user_id uuid null
    references auth.users(id) on delete restrict,
  voided_by_membership_id uuid null
    references public.school_app_memberships(user_id) on delete restrict,
  void_reason text null,
  replacement_event_id uuid null,
  constraint school_student_status_events_month_first_chk
    check (effective_month=date_trunc('month',effective_month)::date),
  constraint school_student_status_events_status_chk
    check (status in ('active','paused','left')),
  constraint school_student_status_events_reason_chk
    check (reason=trim(reason) and char_length(reason) between 1 and 1000),
  constraint school_student_status_events_creator_identity_chk
    check (created_by_user_id=created_by_membership_id),
  constraint school_student_status_events_void_identity_chk
    check (voided_by_user_id is null or voided_by_user_id=voided_by_membership_id),
  constraint school_student_status_events_void_reason_chk
    check (void_reason is null or (void_reason=trim(void_reason) and char_length(void_reason) between 1 and 1000)),
  constraint school_student_status_events_void_bundle_chk
    check (
      (voided_at is null and voided_by_user_id is null and voided_by_membership_id is null
       and void_reason is null and replacement_event_id is null)
      or
      (voided_at is not null and voided_by_user_id is not null and voided_by_membership_id is not null
       and void_reason is not null and replacement_event_id is not null)
    ),
  constraint school_student_status_events_replacement_not_self_chk
    check (replacement_event_id is null or replacement_event_id<>id),
  constraint school_student_status_events_replacement_fkey
    foreign key (replacement_event_id)
    references public.school_student_status_events(id)
    on delete restrict
    deferrable initially deferred
);

create unique index school_student_status_events_active_month_uniq
  on public.school_student_status_events (student_id,effective_month)
  where voided_at is null;

create unique index school_student_status_events_replacement_uniq
  on public.school_student_status_events (replacement_event_id)
  where replacement_event_id is not null;

create index school_student_status_events_resolver_idx
  on public.school_student_status_events (student_id,effective_month desc,id desc)
  where voided_at is null;

create index school_student_status_events_created_actor_idx
  on public.school_student_status_events (created_by_user_id,created_at desc);

create function public.school_guard_student_status_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_context text;
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception using errcode='42501',message='STUDENT_STATUS_EVENT_PHYSICAL_DELETE_FORBIDDEN';
  end if;

  if tg_op<>'UPDATE' then
    return new;
  end if;

  v_context:=current_setting('school.student_status_correction_context_v1',true);
  if v_context is distinct from old.id::text||':'||coalesce(new.replacement_event_id::text,'') then
    raise exception using errcode='42501',message='STUDENT_STATUS_EVENT_DIRECT_UPDATE_FORBIDDEN';
  end if;

  if old.voided_at is not null
     or new.id is distinct from old.id
     or new.student_id is distinct from old.student_id
     or new.effective_month is distinct from old.effective_month
     or new.status is distinct from old.status
     or new.reason is distinct from old.reason
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.created_by_membership_id is distinct from old.created_by_membership_id
     or new.created_at is distinct from old.created_at
     or new.voided_at is null
     or new.voided_by_user_id is null
     or new.voided_by_membership_id is null
     or new.void_reason is null
     or new.replacement_event_id is null
     or new.row_version is not distinct from old.row_version then
    raise exception using errcode='42501',message='STUDENT_STATUS_EVENT_CORRECTION_MUTATION_INVALID';
  end if;

  return new;
end;
$function$;

create trigger school_student_status_events_update_guard
before update on public.school_student_status_events
for each row execute function public.school_guard_student_status_event_mutation_v1();

create trigger school_student_status_events_delete_guard
before delete on public.school_student_status_events
for each row execute function public.school_guard_student_status_event_mutation_v1();

create trigger school_student_status_events_truncate_guard
before truncate on public.school_student_status_events
for each statement execute function public.school_guard_student_status_event_mutation_v1();

alter table public.school_student_status_events enable row level security;

revoke all on table public.school_student_status_events
  from public,anon,authenticated,service_role;
revoke all on function public.school_guard_student_status_event_mutation_v1()
  from public,anon,authenticated,service_role;

comment on table public.school_student_status_events is
  'Phase A sole authority for month-effective student status used by new resolvers. Legacy school_students.status remains an unmigrated compatibility snapshot until Phase B.';
comment on column public.school_student_status_events.effective_month is
  'Tokyo business month represented canonically as the first calendar date of that month.';
comment on column public.school_student_status_events.row_version is
  'Opaque DB-issued optimistic-lock token; changes only when the correction writer voids this event.';
comment on column public.school_student_status_events.created_by_membership_id is
  'Membership stable identity. In the current membership model this is the canonical auth user UUID and equals created_by_user_id.';
comment on column public.school_student_status_events.replacement_event_id is
  'Replacement created atomically by the dedicated correction writer; never a general edit link.';
comment on function public.school_guard_student_status_event_mutation_v1() is
  'Owner-only trigger guard: physical delete/truncate always fail and update is limited to one-way correction voiding.';
