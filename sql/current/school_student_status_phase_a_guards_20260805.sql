-- School V2 student monthly status Phase A technical mutation guards, 2026-08-05.
-- Guard-only file: no business writer RPC and no data repair.

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

revoke all on function public.school_guard_student_status_event_mutation_v1()
  from public,anon,authenticated,service_role;

comment on function public.school_guard_student_status_event_mutation_v1() is
  'Owner-only trigger guard: physical delete/truncate always fail and update is limited to one-way correction voiding.';
