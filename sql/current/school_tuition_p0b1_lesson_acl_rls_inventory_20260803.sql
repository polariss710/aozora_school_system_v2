\set ON_ERROR_STOP on
\pset pager off
begin read only;
select grantee,privilege_type from information_schema.role_table_grants
where table_schema='public' and table_name='school_lesson_records'
order by grantee,privilege_type;
select polname,polroles::regrole[],polcmd,pg_get_expr(polqual,polrelid) using_expression,
  pg_get_expr(polwithcheck,polrelid) check_expression
from pg_policy where polrelid='public.school_lesson_records'::regclass order by polname;
do $verify$
declare r name;
begin
  foreach r in array array['anon'::name,'authenticated'::name,'service_role'::name] loop
    if has_table_privilege(r,'public.school_lesson_records','INSERT,UPDATE,DELETE,TRUNCATE') then
      raise exception 'P0B1_DIRECT_DML_REMAINS: %',r;
    end if;
    if not has_table_privilege(r,'public.school_lesson_records','SELECT') then
      raise exception 'P0B1_SELECT_MISSING: %',r;
    end if;
  end loop;
  if exists(select 1 from pg_policy where polrelid='public.school_lesson_records'::regclass and polcmd='*')
     or (select count(*) from pg_policy where polrelid='public.school_lesson_records'::regclass and polcmd='r')<>1 then
    raise exception 'P0B1_RLS_NOT_SELECT_ONLY';
  end if;
end
$verify$;
rollback;
