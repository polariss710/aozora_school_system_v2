-- School V2 Phase BE-P0 formal deployment/rehearsal wrapper.
-- p0_be_permission_commit=0: rollback rehearsal; =1: reviewed production commit.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0_be_permission_commit}
\else
  \set p0_be_permission_commit 0
\endif

begin;

lock table public.school_business_entities in share row exclusive mode;
create temporary table be_p0_deploy_baseline on commit drop as
select count(*) row_count,
       md5(coalesce(string_agg(to_jsonb(be)::text,'|' order by be.id),'')) row_hash
from public.school_business_entities be;

\ir school_business_entity_p0_permission_closure_core_20260806.sql

do $verify_data_unchanged$
declare
  v_before record;
  v_after record;
begin
  select * into strict v_before from be_p0_deploy_baseline;
  select count(*) row_count,
         md5(coalesce(string_agg(to_jsonb(be)::text,'|' order by be.id),'')) row_hash
  into strict v_after
  from public.school_business_entities be;

  if v_before.row_count<>v_after.row_count or v_before.row_hash<>v_after.row_hash then
    raise exception 'BE_P0_DEPLOY_CHANGED_BUSINESS_ENTITY_ROWS';
  end if;
end;
$verify_data_unchanged$;

\if :p0_be_permission_commit
  commit;
  \echo 'BE_P0_PERMISSION_CLOSURE_COMMIT'
\else
  rollback;
  \echo 'BE_P0_PERMISSION_CLOSURE_REHEARSAL_ROLLBACK'
\endif
