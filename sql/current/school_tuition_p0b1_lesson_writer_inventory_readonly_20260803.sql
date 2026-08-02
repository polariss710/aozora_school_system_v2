\set ON_ERROR_STOP on
\pset pager off
begin read only;

with f as (
  select p.oid,p.oid::regprocedure::text signature,p.proname,
    p.prosecdef,coalesce(array_to_string(p.proconfig,','),'') function_config,
    pg_get_functiondef(p.oid) definition,
    has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
    has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
)
select signature,prosecdef,function_config,anon_execute,authenticated_execute,service_execute,
  definition ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+public[.]school_lesson_records' direct_dml,
  definition like '%school_tuition_p0b1_lock_%' p0b1_lock,
  case
    when proname in ('school_import_lesson_records_batch','school_import_lesson_records_batch_with_venue',
      'school_backfill_actual_minutes_from_duration') then 'disabled_or_owner_only'
    when definition ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+public[.]school_lesson_records'
      or definition ~ 'school_(create|update|delete|void)[a-z0-9_]*lesson' then 'daily_or_compat_facade'
    else 'reader_or_non_lesson_writer'
  end classification
from f
where definition ~ 'school_lesson_records|school_[a-z0-9_]*lesson[a-z0-9_]*[[:space:]]*[(]'
  and (definition ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+public[.]school_lesson_records'
       or definition ~ 'school_(create|update|delete|void|import|backfill)[a-z0-9_]*lesson[a-z0-9_]*[[:space:]]*[(]')
order by signature;

select c.relrowsecurity,c.relforcerowsecurity,c.relowner::regrole owner
from pg_class c where c.oid='public.school_lesson_records'::regclass;

select t.tgname,pg_get_triggerdef(t.oid),t.tgenabled
from pg_trigger t where t.tgrelid='public.school_lesson_records'::regclass and not t.tgisinternal
order by t.tgname;
rollback;
