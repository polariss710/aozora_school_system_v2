-- Exact rollback definition for PTW-P0-A2.
-- DO NOT EXECUTE during normal deployment or testing: this intentionally restores the insecure baseline.
-- It is retained only as the task-required recovery artifact and performs no business-row DML.
\set ON_ERROR_STOP on
\pset pager off

begin;

create temp table ptw_p0_a2_rollback_expected (
  signature text primary key,
  baseline_definition_md5 text not null,
  contract text not null
) on commit drop;

insert into ptw_p0_a2_rollback_expected values
  ('public.school_create_part_time_work_income_record(uuid)','e92c09c94fe7d4b531e947da01a94c47','operational'),
  ('public.school_create_part_time_work_income_request(uuid)','6da04693138d2762279258f10f22be3e','legacy'),
  ('public.school_create_part_time_work_planned_lesson(date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text,text)','56c86440aedda1e0e11f7e7b85e78445','operational'),
  ('public.school_delete_part_time_work_lesson(uuid,boolean)','a11fd6339801d2c55d6aa0879a75acb0','operational'),
  ('public.school_generate_part_time_work_actual_from_planned(uuid,date,time without time zone,time without time zone,integer,numeric,integer,integer,text)','d73b26b9a0a9271545a0bd25aee1cbb0','operational'),
  ('public.school_import_historical_part_time_work_batch(jsonb)','62cde1954c0a988f718253e0aaeaa3d3','historical_import'),
  ('public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)','809f3c8b4bdbe973ac522d2ca747da9b','operational'),
  ('public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamp with time zone)','f6f54981bf4fcc19f3a81f7b13948d7f','legacy'),
  ('public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamp with time zone)','c8d349502d39bc2fa5e7d40f74915f65','legacy'),
  ('public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text)','1da9702de6a9c646990b9806f7b142c1','legacy'),
  ('public.school_unlock_part_time_work_monthly_settlement(uuid)','2b03594ceb82dbba5415fb92eee1ed28','operational'),
  ('public.school_update_part_time_work_lesson(uuid,date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text)','eb69bce9c963d136202d24571504142e','operational');

create temp table ptw_p0_a2_rollback_business_baseline on commit drop as
select 'school_income_records' object_name,count(*)::bigint row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
from public.school_income_records x
union all select 'school_part_time_work_income_requests',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_income_requests x
union all select 'school_part_time_work_lessons',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_lessons x
union all select 'school_part_time_work_monthly_settlement_details',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlement_details x
union all select 'school_part_time_work_monthly_settlements',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlements x;

do $rollback_preflight$
declare
  fn_row record;
  v_oid oid;
begin
  if to_regprocedure('public.school_require_current_part_time_work_operator()') is null
     or to_regprocedure('public.school_require_current_part_time_work_admin()') is null then
    raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_GUARDS_MISSING';
  end if;
  for fn_row in select * from ptw_p0_a2_rollback_expected order by signature loop
    v_oid:=to_regprocedure(fn_row.signature);
    if v_oid is null
       or (select p.proconfig from pg_proc p where p.oid=v_oid)
          is distinct from array['search_path=pg_catalog, public']::text[] then
      raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_PREFLIGHT_MISMATCH',detail=fn_row.signature;
    end if;
    if fn_row.contract='operational'
       and position('school_require_current_part_time_work_' in (select p.prosrc from pg_proc p where p.oid=v_oid))=0 then
      raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_OPERATIONAL_GUARD_MISSING',detail=fn_row.signature;
    end if;
  end loop;
end
$rollback_preflight$;

do $restore_definitions$
declare
  fn_restore_row record;
  v_oid oid;
  v_definition text;
begin
  for fn_restore_row in select * from ptw_p0_a2_rollback_expected where contract='operational' order by signature loop
    v_oid:=to_regprocedure(fn_restore_row.signature);
    v_definition:=pg_get_functiondef(v_oid);
    v_definition:=replace(v_definition,
      E'  perform public.school_require_current_part_time_work_operator();\n','');
    v_definition:=replace(v_definition,
      E'  perform public.school_require_current_part_time_work_admin();\n','');
    v_definition:=replace(v_definition,
      'SET search_path TO ''pg_catalog'', ''public''',
      'SET search_path TO ''public''');
    execute v_definition;
  end loop;
end
$restore_definitions$;

alter function public.school_create_part_time_work_income_request(uuid) set search_path to public;
alter function public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text) set search_path to public;
alter function public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamptz) set search_path to public;
alter function public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamptz) set search_path to public;
alter function public.school_import_historical_part_time_work_batch(jsonb) set search_path to public;

grant execute on function public.school_create_part_time_work_planned_lesson(date,time,time,text,text,text,integer,numeric,integer,integer,text,text) to authenticated,service_role;
grant execute on function public.school_update_part_time_work_lesson(uuid,date,time,time,text,text,text,integer,numeric,integer,integer,text) to authenticated,service_role;
grant execute on function public.school_generate_part_time_work_actual_from_planned(uuid,date,time,time,integer,numeric,integer,integer,text) to authenticated,service_role;
grant execute on function public.school_delete_part_time_work_lesson(uuid,boolean) to authenticated,service_role;
grant execute on function public.school_lock_part_time_work_monthly_settlement(text,text,integer,text) to authenticated,service_role;
grant execute on function public.school_unlock_part_time_work_monthly_settlement(uuid) to authenticated,service_role;
grant execute on function public.school_create_part_time_work_income_record(uuid) to authenticated,service_role;
grant execute on function public.school_create_part_time_work_income_request(uuid) to authenticated,service_role;
grant execute on function public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamptz) to authenticated,service_role;
grant execute on function public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamptz) to authenticated,service_role;
revoke all on function public.school_import_historical_part_time_work_batch(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.school_import_historical_part_time_work_batch(jsonb) to service_role;

drop function public.school_require_current_part_time_work_operator();
drop function public.school_require_current_part_time_work_admin();

do $rollback_postcondition$
declare
  fn_row record;
  fingerprint_row record;
  v_oid oid;
  v_current_count bigint;
  v_current_hash text;
begin
  for fn_row in select * from ptw_p0_a2_rollback_expected order by signature loop
    v_oid:=to_regprocedure(fn_row.signature);
    if v_oid is null
       or (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid=v_oid)<>'postgres'
       or not (select p.prosecdef from pg_proc p where p.oid=v_oid)
       or md5(pg_get_functiondef(v_oid))<>fn_row.baseline_definition_md5 then
      raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_DEFINITION_MISMATCH',detail=fn_row.signature;
    end if;
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE') is distinct from (fn_row.contract<>'historical_import')
       or not has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_ACL_MISMATCH',detail=fn_row.signature;
    end if;
  end loop;
  for fingerprint_row in select * from ptw_p0_a2_rollback_business_baseline order by object_name loop
    execute format('select count(*)::bigint,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by x.id::text),'''')) from public.%I x',fingerprint_row.object_name)
      into v_current_count,v_current_hash;
    if (v_current_count,v_current_hash) is distinct from (fingerprint_row.row_count,fingerprint_row.row_hash) then
      raise exception using errcode='P0001',message='PTW_P0_A2_ROLLBACK_BUSINESS_FINGERPRINT_CHANGED',detail=fingerprint_row.object_name;
    end if;
  end loop;
end
$rollback_postcondition$;

commit;
