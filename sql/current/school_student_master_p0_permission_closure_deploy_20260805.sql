-- School V2 student-master P0 permission closure formal deployment/rehearsal.
-- Run with p0_student_permission_commit=0 for a real rollback rehearsal;
-- run with p0_student_permission_commit=1 for the reviewed production commit.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0_student_permission_commit}
\else
  \set p0_student_permission_commit 0
\endif

begin;

lock table public.school_students in share row exclusive mode;
create temporary table student_p0_deploy_baseline on commit drop as
select count(*) row_count,
       md5(coalesce(string_agg(to_jsonb(s)::text,'|' order by s.id),'')) row_hash
from public.school_students s;

\ir school_student_master_p0_permission_closure_core_20260805.sql

do $verify_data_unchanged$
declare
  v_before record;
  v_after record;
begin
  select * into strict v_before from student_p0_deploy_baseline;
  select count(*) row_count,
         md5(coalesce(string_agg(to_jsonb(s)::text,'|' order by s.id),'')) row_hash
  into strict v_after
  from public.school_students s;
  if v_before.row_count<>v_after.row_count or v_before.row_hash<>v_after.row_hash then
    raise exception 'STUDENT_P0_DEPLOY_CHANGED_STUDENT_ROWS';
  end if;
end;
$verify_data_unchanged$;

\if :p0_student_permission_commit
  commit;
  \echo 'STUDENT_P0_PERMISSION_CLOSURE_COMMIT'
\else
  rollback;
  \echo 'STUDENT_P0_PERMISSION_CLOSURE_REHEARSAL_ROLLBACK'
\endif
