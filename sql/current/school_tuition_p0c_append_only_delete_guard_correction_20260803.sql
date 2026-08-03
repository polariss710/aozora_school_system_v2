\set ON_ERROR_STOP on
begin;
create function public.school_guard_p0c_generation_direct_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if session_user='postgres'
     and current_setting('tuition.p0c_fixture_cleanup',true)
       ='codex-test atomic-void-reissue-p0c-20260803' then
    return null;
  end if;
  raise exception 'TUITION_P0C_DIRECT_DELETE_FORBIDDEN';
end;
$function$;
revoke all on function public.school_guard_p0c_generation_direct_delete()
  from public,anon,authenticated,service_role;
create trigger school_tuition_generation_identity_delete_statement_guard
before delete on public.school_student_tuition_generation_identities
for each statement execute function public.school_guard_p0c_generation_direct_delete();
create trigger school_tuition_generation_revision_delete_statement_guard
before delete on public.school_student_tuition_generation_revisions
for each statement execute function public.school_guard_p0c_generation_direct_delete();
create trigger school_tuition_generation_void_event_delete_statement_guard
before delete on public.school_student_tuition_generation_void_events
for each statement execute function public.school_guard_p0c_generation_direct_delete();
commit;
