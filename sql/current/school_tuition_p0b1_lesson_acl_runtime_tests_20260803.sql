-- Expected runtime permission errors are intentionally continued, then catalog
-- and residue assertions fail closed at the end.
\pset pager off
\set ON_ERROR_STOP off

\echo 'P0B1_RUNTIME_ROLE anon'
begin; set local role anon; select count(*)>=0 as select_ok from public.school_lesson_records; rollback;
begin; set local role anon; insert into public.school_lesson_records(note) values('codex-test tuition-p0b1-acl-runtime'); rollback;
begin; set local role anon; update public.school_lesson_records set note=note where false; rollback;
begin; set local role anon; delete from public.school_lesson_records where false; rollback;
begin; set local role anon; truncate public.school_lesson_records; rollback;
begin; set local role anon; select public.school_tuition_p0b1_lock_lesson_scopes('[]'::jsonb); rollback;

\echo 'P0B1_RUNTIME_ROLE authenticated'
begin; set local role authenticated; select count(*)>=0 as select_ok from public.school_lesson_records; rollback;
begin; set local role authenticated; insert into public.school_lesson_records(note) values('codex-test tuition-p0b1-acl-runtime'); rollback;
begin; set local role authenticated; update public.school_lesson_records set note=note where false; rollback;
begin; set local role authenticated; delete from public.school_lesson_records where false; rollback;
begin; set local role authenticated; truncate public.school_lesson_records; rollback;
begin; set local role authenticated; select public.school_tuition_p0b1_lock_lesson_scopes('[]'::jsonb); rollback;

\echo 'P0B1_RUNTIME_ROLE service_role'
begin; set local role service_role; select count(*)>=0 as select_ok from public.school_lesson_records; rollback;
begin; set local role service_role; insert into public.school_lesson_records(note) values('codex-test tuition-p0b1-acl-runtime'); rollback;
begin; set local role service_role; update public.school_lesson_records set note=note where false; rollback;
begin; set local role service_role; delete from public.school_lesson_records where false; rollback;
begin; set local role service_role; truncate public.school_lesson_records; rollback;
begin; set local role service_role; select public.school_tuition_p0b1_lock_lesson_scopes('[]'::jsonb); rollback;

\set ON_ERROR_STOP on
do $final$
declare r name;
begin
  foreach r in array array['anon'::name,'authenticated'::name,'service_role'::name] loop
    if has_table_privilege(r,'public.school_lesson_records','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or not has_table_privilege(r,'public.school_lesson_records','SELECT')
       or has_function_privilege(r,'public.school_tuition_p0b1_lock_lesson_scopes(jsonb)','EXECUTE') then
      raise exception 'P0B1_RUNTIME_ACL_FINAL_ASSERTION_FAILED: %',r;
    end if;
  end loop;
  if exists(select 1 from public.school_lesson_records where note='codex-test tuition-p0b1-acl-runtime') then
    raise exception 'P0B1_RUNTIME_ACL_RESIDUE';
  end if;
end
$final$;
select 'P0B1_RUNTIME_ACL_15_EXPECTED_REJECTIONS_AND_3_SELECTS_PASSED' result;
