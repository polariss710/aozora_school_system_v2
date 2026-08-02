-- Final least-privilege table ACL for the already-deployed P0-B1 cutover.
-- No business-row DML.
begin;
revoke all on public.school_lesson_records from public,anon,authenticated,service_role;
grant select on public.school_lesson_records to anon,authenticated,service_role;
do $verify$
declare r name;
begin
  foreach r in array array['anon'::name,'authenticated'::name,'service_role'::name] loop
    if has_table_privilege(r,'public.school_lesson_records','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or not has_table_privilege(r,'public.school_lesson_records','SELECT') then
      raise exception 'P0B1_TABLE_ACL_FINALIZER_FAILED: %',r;
    end if;
  end loop;
end
$verify$;
commit;
