-- School V2 PTW-P0-A2 complete part-time-work writer permission closure.
-- Status: production deployed 2026-08-16 after successful ROLLBACK rehearsal; postdeploy and negative ROLLBACK tests passed.
-- Scope: function definitions, function ACL and safe search_path only; no business-row DML.
\set ON_ERROR_STOP on
\pset pager off
\if :{?ptw_p0_a2_commit}
\else
  \set ptw_p0_a2_commit 0
\endif

-- Business-model expansion declaration
-- New tables: none.
-- New columns: none.
-- New enum/status values: none.
-- New date/month/attribution concepts: none.
-- New identity concepts: none; auth.uid() + school_app_memberships remains sole authority.
-- New source/snapshot/version concepts: none.
-- New writable facts: none.
-- Changed existing-field semantics: none.
-- Changed field mutability: none.
-- Changed writer or reader authority:
--   * four operational lesson writers require active admin/operator;
--   * three operational financial writers require active admin;
--   * four legacy writers become owner-only retired evidence;
--   * the historical importer remains service-role-only.
-- Changed locking rules: none.
-- New authoritative sources: none.
-- Legacy fallbacks or dual-read rules: none.
-- Dual-write behavior: none.
-- Historical reinterpretation: none.
-- Destructive schema changes: none.
-- Approval reference: current PTW-P0-A2 task sections II and III explicitly approve each
-- writer set, role contract, legacy retirement behavior and unchanged historical importer.

begin;

create temp table ptw_p0_a2_expected (
  signature text primary key,
  baseline_definition_md5 text not null,
  contract text not null,
  baseline_authenticated_execute boolean not null,
  baseline_service_role_execute boolean not null
) on commit drop;

insert into ptw_p0_a2_expected values
  ('public.school_create_part_time_work_income_record(uuid)',
   'e92c09c94fe7d4b531e947da01a94c47','admin',true,true),
  ('public.school_create_part_time_work_income_request(uuid)',
   '6da04693138d2762279258f10f22be3e','retired',true,true),
  ('public.school_create_part_time_work_planned_lesson(date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text,text)',
   '56c86440aedda1e0e11f7e7b85e78445','operator',true,true),
  ('public.school_delete_part_time_work_lesson(uuid,boolean)',
   'a11fd6339801d2c55d6aa0879a75acb0','operator',true,true),
  ('public.school_generate_part_time_work_actual_from_planned(uuid,date,time without time zone,time without time zone,integer,numeric,integer,integer,text)',
   'd73b26b9a0a9271545a0bd25aee1cbb0','operator',true,true),
  ('public.school_import_historical_part_time_work_batch(jsonb)',
   '62cde1954c0a988f718253e0aaeaa3d3','historical_import',false,true),
  ('public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)',
   '809f3c8b4bdbe973ac522d2ca747da9b','admin',true,true),
  ('public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamp with time zone)',
   'f6f54981bf4fcc19f3a81f7b13948d7f','retired',true,true),
  ('public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamp with time zone)',
   'c8d349502d39bc2fa5e7d40f74915f65','retired',true,true),
  ('public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text)',
   '1da9702de6a9c646990b9806f7b142c1','retired',true,true),
  ('public.school_unlock_part_time_work_monthly_settlement(uuid)',
   '2b03594ceb82dbba5415fb92eee1ed28','admin',true,true),
  ('public.school_update_part_time_work_lesson(uuid,date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text)',
   'eb69bce9c963d136202d24571504142e','operator',true,true);

create temp table ptw_p0_a2_function_baseline on commit drop as
select
  e.signature,
  p.oid,
  p.prosrc,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_result(p.oid) as function_result
from ptw_p0_a2_expected e
join pg_proc p on p.oid=to_regprocedure(e.signature);

create temp table ptw_p0_a2_business_baseline on commit drop as
select 'school_income_records' object_name,count(*)::bigint row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
from public.school_income_records x
union all
select 'school_part_time_work_income_requests',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_income_requests x
union all
select 'school_part_time_work_lessons',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_lessons x
union all
select 'school_part_time_work_monthly_settlement_details',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlement_details x
union all
select 'school_part_time_work_monthly_settlements',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlements x;

create temp table ptw_p0_a2_table_security_baseline on commit drop as
select c.oid,c.relacl::text,c.relrowsecurity,c.relforcerowsecurity
from pg_class c
where c.oid in (
  'public.school_income_records'::regclass,
  'public.school_part_time_work_income_requests'::regclass,
  'public.school_part_time_work_lessons'::regclass,
  'public.school_part_time_work_monthly_settlement_details'::regclass,
  'public.school_part_time_work_monthly_settlements'::regclass
);

do $preflight$
declare
  fn_row record;
  v_oid oid;
  v_dml_count integer;
begin
  if (select count(*) from ptw_p0_a2_function_baseline) <> 12 then
    raise exception using errcode='P0001',message='PTW_P0_A2_WRITER_SIGNATURE_COUNT_MISMATCH';
  end if;

  select count(*) into v_dml_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname like 'school%part_time_work%'
    and lower(p.prosrc) ~ '(insert[[:space:]]+into|update[[:space:]]+public\.|delete[[:space:]]+from)';
  if v_dml_count <> 12 then
    raise exception using errcode='P0001',message='PTW_P0_A2_DML_WRITER_COUNT_MISMATCH',
      detail=format('actual=%s expected=12',v_dml_count);
  end if;

  if to_regprocedure('public.school_require_current_part_time_work_operator()') is not null
     or to_regprocedure('public.school_require_current_part_time_work_admin()') is not null then
    raise exception using errcode='P0001',message='PTW_P0_A2_GUARD_ALREADY_EXISTS';
  end if;

  for fn_row in select * from ptw_p0_a2_expected order by signature loop
    v_oid:=to_regprocedure(fn_row.signature);
    if v_oid is null then
      raise exception using errcode='P0001',message='PTW_P0_A2_WRITER_MISSING',detail=fn_row.signature;
    end if;
    if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid=v_oid) <> 'postgres'
       or not (select p.prosecdef from pg_proc p where p.oid=v_oid)
       or (select p.proconfig from pg_proc p where p.oid=v_oid) is distinct from array['search_path=public']::text[]
       or md5(pg_get_functiondef(v_oid)) <> fn_row.baseline_definition_md5 then
      raise exception using errcode='P0001',message='PTW_P0_A2_WRITER_DEFINITION_DRIFT',detail=fn_row.signature;
    end if;
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE') is distinct from fn_row.baseline_authenticated_execute
       or has_function_privilege('service_role',v_oid,'EXECUTE') is distinct from fn_row.baseline_service_role_execute
       or exists (
         select 1 from aclexplode(coalesce((select p.proacl from pg_proc p where p.oid=v_oid),
                                           acldefault('f',(select p.proowner from pg_proc p where p.oid=v_oid)))) a
         where a.grantee=0 and a.privilege_type='EXECUTE'
       ) then
      raise exception using errcode='P0001',message='PTW_P0_A2_WRITER_ACL_DRIFT',detail=fn_row.signature;
    end if;
  end loop;

  if exists (
    select 1 from public.school_part_time_work_income_requests legacy_req
    where legacy_req.deleted_at is null
      and legacy_req.status not in ('cash_rejected','rejected','cancelled','voided','reversed',
                           'historical_confirmed','received','settled','synced')
  ) or exists (
    select 1 from public.school_part_time_work_income_requests legacy_req
    where legacy_req.cash_request_id is not null or legacy_req.cash_transaction_id is not null
  ) then
    raise exception using errcode='P0001',message='PTW_P0_A2_ACTIVE_LEGACY_CASH_FLOW';
  end if;

  if exists (
    select 1 from pg_stat_activity a
    where a.pid<>pg_backend_pid()
      and a.xact_start is not null
      and a.query ilike '%part_time_work%'
  ) then
    raise exception using errcode='P0001',message='PTW_P0_A2_CONCURRENT_ACTIVITY_DETECTED';
  end if;
end
$preflight$;

create function public.school_require_current_part_time_work_operator()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='PTW_WRITER_AUTH_REQUIRED';
  end if;
  select m.role,m.is_active into v_role,v_active
  from public.school_app_memberships m
  where m.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='PTW_WRITER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator') then
    raise exception using errcode='42501',message='PTW_WRITER_OPERATOR_ROLE_REQUIRED';
  end if;
  return v_actor;
end
$function$;

create function public.school_require_current_part_time_work_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='PTW_WRITER_AUTH_REQUIRED';
  end if;
  select m.role,m.is_active into v_role,v_active
  from public.school_app_memberships m
  where m.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='PTW_WRITER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='PTW_WRITER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role is distinct from 'admin' then
    raise exception using errcode='42501',message='PTW_WRITER_ADMIN_ROLE_REQUIRED';
  end if;
  return v_actor;
end
$function$;

revoke all on function public.school_require_current_part_time_work_operator()
  from public,anon,authenticated,service_role;
revoke all on function public.school_require_current_part_time_work_admin()
  from public,anon,authenticated,service_role;

comment on function public.school_require_current_part_time_work_operator() is
  'Owner-only PTW writer assertion requiring auth.uid plus active admin/operator membership.';
comment on function public.school_require_current_part_time_work_admin() is
  'Owner-only PTW financial writer assertion requiring auth.uid plus active admin membership.';

do $rewrite$
declare
  fn_rewrite_row record;
  v_oid oid;
  v_definition text;
  v_marker text:=E'\nbegin\n';
  v_guard text;
  v_position integer;
begin
  for fn_rewrite_row in
    select * from (values
      ('public.school_create_part_time_work_planned_lesson(date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text,text)',
       'perform public.school_require_current_part_time_work_operator();'),
      ('public.school_delete_part_time_work_lesson(uuid,boolean)',
       'perform public.school_require_current_part_time_work_operator();'),
      ('public.school_generate_part_time_work_actual_from_planned(uuid,date,time without time zone,time without time zone,integer,numeric,integer,integer,text)',
       'perform public.school_require_current_part_time_work_operator();'),
      ('public.school_update_part_time_work_lesson(uuid,date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text)',
       'perform public.school_require_current_part_time_work_operator();'),
      ('public.school_create_part_time_work_income_record(uuid)',
       'perform public.school_require_current_part_time_work_admin();'),
      ('public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)',
       'perform public.school_require_current_part_time_work_admin();'),
      ('public.school_unlock_part_time_work_monthly_settlement(uuid)',
       'perform public.school_require_current_part_time_work_admin();')
    ) x(signature,guard_call)
  loop
    v_oid:=to_regprocedure(fn_rewrite_row.signature);
    v_definition:=pg_get_functiondef(v_oid);
    if position('school_require_current_part_time_work_' in v_definition)>0 then
      raise exception using errcode='P0001',message='PTW_P0_A2_DUPLICATE_GUARD',detail=fn_rewrite_row.signature;
    end if;
    if position('SET search_path TO ''public''' in v_definition)=0 then
      raise exception using errcode='P0001',message='PTW_P0_A2_SEARCH_PATH_MARKER_MISSING',detail=fn_rewrite_row.signature;
    end if;
    v_definition:=replace(v_definition,
      'SET search_path TO ''public''',
      'SET search_path TO ''pg_catalog'', ''public''');
    v_position:=position(v_marker in v_definition);
    if v_position=0 then
      raise exception using errcode='P0001',message='PTW_P0_A2_TOP_LEVEL_BEGIN_MISSING',detail=fn_rewrite_row.signature;
    end if;
    v_guard:='  '||fn_rewrite_row.guard_call||E'\n';
    v_definition:=overlay(v_definition placing v_marker||v_guard
                          from v_position for char_length(v_marker));
    execute v_definition;
  end loop;
end
$rewrite$;

revoke all on function public.school_create_part_time_work_planned_lesson(date,time,time,text,text,text,integer,numeric,integer,integer,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_part_time_work_planned_lesson(date,time,time,text,text,text,integer,numeric,integer,integer,text,text)
  to authenticated;
revoke all on function public.school_update_part_time_work_lesson(uuid,date,time,time,text,text,text,integer,numeric,integer,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_update_part_time_work_lesson(uuid,date,time,time,text,text,text,integer,numeric,integer,integer,text)
  to authenticated;
revoke all on function public.school_generate_part_time_work_actual_from_planned(uuid,date,time,time,integer,numeric,integer,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_generate_part_time_work_actual_from_planned(uuid,date,time,time,integer,numeric,integer,integer,text)
  to authenticated;
revoke all on function public.school_delete_part_time_work_lesson(uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.school_delete_part_time_work_lesson(uuid,boolean)
  to authenticated;
revoke all on function public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)
  to authenticated;
revoke all on function public.school_unlock_part_time_work_monthly_settlement(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_unlock_part_time_work_monthly_settlement(uuid)
  to authenticated;
revoke all on function public.school_create_part_time_work_income_record(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_part_time_work_income_record(uuid)
  to authenticated;

alter function public.school_create_part_time_work_income_request(uuid)
  set search_path to pg_catalog,public;
alter function public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text)
  set search_path to pg_catalog,public;
alter function public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamptz)
  set search_path to pg_catalog,public;
alter function public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamptz)
  set search_path to pg_catalog,public;

revoke all on function public.school_create_part_time_work_income_request(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamptz)
  from public,anon,authenticated,service_role;

alter function public.school_import_historical_part_time_work_batch(jsonb)
  set search_path to pg_catalog,public;
revoke all on function public.school_import_historical_part_time_work_batch(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.school_import_historical_part_time_work_batch(jsonb)
  to service_role;

do $postcondition$
declare
  fn_row record;
  fingerprint_row record;
  v_oid oid;
  v_guard_call text;
  v_guard_position integer;
  v_mutation_position integer;
  v_position integer;
  v_stripped_source text;
  v_current_count bigint;
  v_current_hash text;
begin
  for fn_row in
    select e.*,b.prosrc as baseline_source,b.identity_arguments,b.function_result
    from ptw_p0_a2_expected e
    join ptw_p0_a2_function_baseline b using(signature)
    order by e.signature
  loop
    v_oid:=to_regprocedure(fn_row.signature);
    if v_oid is null
       or (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid=v_oid)<>'postgres'
       or not (select p.prosecdef from pg_proc p where p.oid=v_oid)
       or (select p.proconfig from pg_proc p where p.oid=v_oid)
          is distinct from array['search_path=pg_catalog, public']::text[]
       or pg_get_function_identity_arguments(v_oid) is distinct from fn_row.identity_arguments
       or pg_get_function_result(v_oid) is distinct from fn_row.function_result then
      raise exception using errcode='P0001',message='PTW_P0_A2_POST_DEFINITION_MISMATCH',detail=fn_row.signature;
    end if;

    if fn_row.contract in ('operator','admin') then
      if has_function_privilege('anon',v_oid,'EXECUTE')
         or not has_function_privilege('authenticated',v_oid,'EXECUTE')
         or has_function_privilege('service_role',v_oid,'EXECUTE') then
        raise exception using errcode='P0001',message='PTW_P0_A2_OPERATIONAL_ACL_MISMATCH',detail=fn_row.signature;
      end if;
      v_guard_call:=case when fn_row.contract='operator'
        then 'perform public.school_require_current_part_time_work_operator();'
        else 'perform public.school_require_current_part_time_work_admin();' end;
      select p.prosrc into v_stripped_source from pg_proc p where p.oid=v_oid;
      v_guard_position:=position(v_guard_call in v_stripped_source);
      v_mutation_position:=0;
      foreach v_position in array array[
        position('insert into ' in lower(v_stripped_source)),
        position('update public.' in lower(v_stripped_source)),
        position('delete from ' in lower(v_stripped_source)),
        position('for update' in lower(v_stripped_source)),
        position('lock table ' in lower(v_stripped_source))
      ] loop
        if v_position>0 and (v_mutation_position=0 or v_position<v_mutation_position) then
          v_mutation_position:=v_position;
        end if;
      end loop;
      if v_guard_position=0 or v_mutation_position=0 or v_guard_position>=v_mutation_position then
        raise exception using errcode='P0001',message='PTW_P0_A2_GUARD_ORDER_MISMATCH',detail=fn_row.signature;
      end if;
      v_stripped_source:=replace(v_stripped_source,'  '||v_guard_call||E'\n','');
      if v_stripped_source is distinct from fn_row.baseline_source then
        raise exception using errcode='P0001',message='PTW_P0_A2_BUSINESS_BODY_CHANGED',detail=fn_row.signature;
      end if;
    elsif fn_row.contract='retired' then
      if has_function_privilege('anon',v_oid,'EXECUTE')
         or has_function_privilege('authenticated',v_oid,'EXECUTE')
         or has_function_privilege('service_role',v_oid,'EXECUTE')
         or (select p.prosrc from pg_proc p where p.oid=v_oid) is distinct from fn_row.baseline_source then
        raise exception using errcode='P0001',message='PTW_P0_A2_RETIRED_CONTRACT_MISMATCH',detail=fn_row.signature;
      end if;
    else
      if has_function_privilege('anon',v_oid,'EXECUTE')
         or has_function_privilege('authenticated',v_oid,'EXECUTE')
         or not has_function_privilege('service_role',v_oid,'EXECUTE')
         or (select p.prosrc from pg_proc p where p.oid=v_oid) is distinct from fn_row.baseline_source then
        raise exception using errcode='P0001',message='PTW_P0_A2_IMPORT_CONTRACT_MISMATCH',detail=fn_row.signature;
      end if;
    end if;

    if exists (
      select 1 from aclexplode(coalesce((select p.proacl from pg_proc p where p.oid=v_oid),
                                        acldefault('f',(select p.proowner from pg_proc p where p.oid=v_oid)))) a
      where a.grantee=0 and a.privilege_type='EXECUTE'
    ) then
      raise exception using errcode='P0001',message='PTW_P0_A2_PUBLIC_EXECUTE_REMAINS',detail=fn_row.signature;
    end if;
  end loop;

  if has_function_privilege('anon','public.school_require_current_part_time_work_operator()','EXECUTE')
     or has_function_privilege('authenticated','public.school_require_current_part_time_work_operator()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_part_time_work_operator()','EXECUTE')
     or has_function_privilege('anon','public.school_require_current_part_time_work_admin()','EXECUTE')
     or has_function_privilege('authenticated','public.school_require_current_part_time_work_admin()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_part_time_work_admin()','EXECUTE') then
    raise exception using errcode='P0001',message='PTW_P0_A2_HELPER_ACL_MISMATCH';
  end if;

  for fingerprint_row in select * from ptw_p0_a2_business_baseline order by object_name loop
    execute format('select count(*)::bigint,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by x.id::text),'''')) from public.%I x',fingerprint_row.object_name)
      into v_current_count,v_current_hash;
    if (v_current_count,v_current_hash) is distinct from (fingerprint_row.row_count,fingerprint_row.row_hash) then
      raise exception using errcode='P0001',message='PTW_P0_A2_BUSINESS_FINGERPRINT_CHANGED',detail=fingerprint_row.object_name;
    end if;
  end loop;

  if exists (
    select 1
    from ptw_p0_a2_table_security_baseline b
    join pg_class c on c.oid=b.oid
    where (c.relacl::text,c.relrowsecurity,c.relforcerowsecurity)
      is distinct from (b.relacl,b.relrowsecurity,b.relforcerowsecurity)
  ) then
    raise exception using errcode='P0001',message='PTW_P0_A2_TABLE_SECURITY_CHANGED';
  end if;
end
$postcondition$;

\if :ptw_p0_a2_commit
  commit;
  \echo 'PTW_P0_A2_WRITER_PERMISSION_CLOSURE_COMMIT'
\else
  rollback;
  \echo 'PTW_P0_A2_WRITER_PERMISSION_CLOSURE_REHEARSAL_ROLLBACK'
\endif
