-- Phase 2C-D2-A2 production postdeploy read-only acceptance.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
  pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer,p.provolatile,
  p.proconfig,p.proacl,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') service_role_execute
from pg_proc p
where p.oid=
  'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'::regprocedure;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select membership.user_id from public.school_app_memberships membership
    where membership.is_active is true and membership.role='admin'
    order by membership.created_at,membership.user_id limit 1),
  'role','authenticated')::text,true);

with payload as (
  select public.school_list_lesson_clearance_pending_balances_v3(null,false) value
)
select value->>'contract_version' contract_version,
  jsonb_array_length(value->'items') source_count,
  value->'summary'->>'remaining_minutes' remaining_minutes,
  value->'summary'->>'operational_partial_actual_date_count' partial_date_count,
  value->'summary'->>'operational_week_monday_count' week_monday_count,
  value->'summary'->>'operational_ambiguous_evidence_count' ambiguous_count
from payload;

with payload as (
  select public.school_list_lesson_clearance_pending_balances_v3(null,false) value
)
select jsonb_pretty(item) target_payload
from payload,jsonb_array_elements(value->'items') item
where item->>'pending_source_planned_id'=
  '8870f57f-bca5-4114-90db-ee592cca2f45';

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
rollback;
