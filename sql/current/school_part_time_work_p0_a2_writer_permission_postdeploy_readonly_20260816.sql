-- PTW-P0-A2 production postdeploy verification. SELECT-only in an explicit read-only transaction.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

with expected(regproc,contract) as (values
  ('public.school_create_part_time_work_income_record(uuid)'::regprocedure,'admin'),
  ('public.school_create_part_time_work_income_request(uuid)'::regprocedure,'retired'),
  ('public.school_create_part_time_work_planned_lesson(date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text,text)'::regprocedure,'operator'),
  ('public.school_delete_part_time_work_lesson(uuid,boolean)'::regprocedure,'operator'),
  ('public.school_generate_part_time_work_actual_from_planned(uuid,date,time without time zone,time without time zone,integer,numeric,integer,integer,text)'::regprocedure,'operator'),
  ('public.school_import_historical_part_time_work_batch(jsonb)'::regprocedure,'historical_import'),
  ('public.school_lock_part_time_work_monthly_settlement(text,text,integer,text)'::regprocedure,'admin'),
  ('public.school_mark_part_time_work_cash_income_confirmed(uuid,uuid,uuid,timestamp with time zone)'::regprocedure,'retired'),
  ('public.school_mark_part_time_work_cash_income_rejected(uuid,uuid,text,timestamp with time zone)'::regprocedure,'retired'),
  ('public.school_mark_part_time_work_cash_request_submitted(uuid,numeric,text,numeric,uuid,uuid,text,text,uuid,text,text)'::regprocedure,'retired'),
  ('public.school_unlock_part_time_work_monthly_settlement(uuid)'::regprocedure,'admin'),
  ('public.school_update_part_time_work_lesson(uuid,date,time without time zone,time without time zone,text,text,text,integer,numeric,integer,integer,text)'::regprocedure,'operator')
)
select p.oid::regprocedure as signature,e.contract,pg_get_userbyid(p.proowner) owner,
       p.prosecdef security_definer,p.provolatile volatility,p.proconfig,
       md5(pg_get_functiondef(p.oid)) definition_md5,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_exec,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_role_exec,
       position('school_require_current_part_time_work_operator' in p.prosrc)>0 operator_guard,
       position('school_require_current_part_time_work_admin' in p.prosrc)>0 admin_guard
from expected e join pg_proc p on p.oid=e.regproc::oid
order by p.oid::regprocedure::text;

select p.oid::regprocedure signature,pg_get_userbyid(p.proowner) owner,p.prosecdef,
       p.provolatile,p.proconfig,md5(pg_get_functiondef(p.oid)) definition_md5,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_exec,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_role_exec
from pg_proc p
where p.oid in (
  'public.school_require_current_part_time_work_operator()'::regprocedure,
  'public.school_require_current_part_time_work_admin()'::regprocedure
)
order by p.oid::regprocedure::text;

select object_name,row_count,row_hash from (
  select 1 sort_order,'school_income_records' object_name,count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_income_records x
  union all select 2,'school_part_time_work_income_requests',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_part_time_work_income_requests x
  union all select 3,'school_part_time_work_lessons',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_part_time_work_lessons x
  union all select 4,'school_part_time_work_monthly_settlement_details',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_part_time_work_monthly_settlement_details x
  union all select 5,'school_part_time_work_monthly_settlements',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_part_time_work_monthly_settlements x
) fingerprints order by sort_order;

select c.oid::regclass table_name,c.relrowsecurity,c.relforcerowsecurity,c.relacl
from pg_class c where c.oid in (
  'public.school_income_records'::regclass,
  'public.school_part_time_work_income_requests'::regclass,
  'public.school_part_time_work_lessons'::regclass,
  'public.school_part_time_work_monthly_settlement_details'::regclass,
  'public.school_part_time_work_monthly_settlements'::regclass
) order by c.oid::regclass::text;

select role,is_active,count(*) membership_count
from public.school_app_memberships group by role,is_active order by role,is_active;

select id,settlement_id,status,cash_request_id,cash_transaction_id,deleted_at,updated_at
from public.school_part_time_work_income_requests order by created_at;

select count(*) filter (where state='active' and pid<>pg_backend_pid() and query ilike '%part_time_work%') active_related_queries,
       count(*) filter (where xact_start is not null and pid<>pg_backend_pid() and query ilike '%part_time_work%') open_related_transactions
from pg_stat_activity;

select max(updated_at) lessons_last_update from public.school_part_time_work_lessons;
select max(updated_at) settlements_last_update from public.school_part_time_work_monthly_settlements;
select max(updated_at) income_requests_last_update from public.school_part_time_work_income_requests;

rollback;
