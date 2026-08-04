-- Trigger-only immutable creation-identity guard for school_expense_records.

create or replace function public.school_guard_expense_creation_audit_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if new.cash_creation_event_id is distinct from old.cash_creation_event_id
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.source_type is distinct from old.source_type then
    raise exception using
      errcode='55000',
      message='P0_EXPENSE_CREATION_AUDIT_IMMUTABLE';
  end if;
  return new;
end;
$function$;

revoke all on function public.school_guard_expense_creation_audit_immutable_v1()
  from public,anon,authenticated,service_role;

create or replace trigger school_guard_expense_creation_audit_immutable_v1
before update of cash_creation_event_id,created_by_user_id,source_type
on public.school_expense_records
for each row
execute function public.school_guard_expense_creation_audit_immutable_v1();

comment on function public.school_guard_expense_creation_audit_immutable_v1() is
  'Trigger-only guard that prevents changes to future expense creation identity, creator, and creation channel.';
