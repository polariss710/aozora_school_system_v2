-- Diagnostic for the postdeploy catalog assertion. Always rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;
\ir school_student_settlement_registered_variance_preview_20260816.sql

select
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  md5(pg_get_functiondef(p.oid))='13fe9c288069ae785887559e6b475138' as definition_matches,
  pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer,
  p.proconfig,
  p.proconfig is not distinct from array['search_path=pg_catalog, public']::text[]
    as search_path_matches,
  coalesce(array_to_string(p.proacl,','),'') as acl,
  position('=X/' in coalesce(array_to_string(p.proacl,','),'')) as public_acl_position,
  has_function_privilege(
    'anon',p.oid::regprocedure,'EXECUTE'
  ) as anon_execute,
  has_function_privilege(
    'authenticated',p.oid::regprocedure,'EXECUTE'
  ) as authenticated_execute,
  has_function_privilege(
    'service_role',p.oid::regprocedure,'EXECUTE'
  ) as service_role_execute
from pg_proc p
where p.oid=
  'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure;

rollback;
