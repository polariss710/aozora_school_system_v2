-- Cash tuition Cash hardening read-only postdeploy, 2026-08-02.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select p.oid::regprocedure as signature,
       md5(pg_get_functiondef(p.oid)) as md5,
       p.prosecdef,
       array_to_string(p.proacl, ',') as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'home_create_external_transaction_request',
    'home_approve_external_transaction_request',
    'home_reject_external_transaction_request',
    'home_create_external_cny_transaction',
    'home_create_external_jpy_transaction'
  )
order by p.oid::regprocedure::text;

select
  (select count(*) from public.home_external_transaction_requests) as request_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.home_external_transaction_requests row_value) as request_md5,
  (select count(*) from public.home_cny_transactions) as cny_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.home_cny_transactions row_value) as cny_md5,
  (select count(*) from public.home_jpy_transactions) as jpy_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.home_jpy_transactions row_value) as jpy_md5;

do $assert$
begin
  if md5(pg_get_functiondef('public.home_approve_external_transaction_request(uuid)'::regprocedure)) <> '3d9be3ed6dd2f41e9fb8ddf5ff7957bb'
     or md5(pg_get_functiondef('public.home_create_external_cny_transaction(uuid,uuid,text,date,numeric,text,text,text,uuid,text,text,text,uuid,text,text)'::regprocedure)) <> '9d4a7bbeb45aaf197f6a2107b17a2830'
     or md5(pg_get_functiondef('public.home_create_external_jpy_transaction(uuid,uuid,text,date,numeric,text,text,text,uuid,text,text,text,uuid,text,text)'::regprocedure)) <> '2575565b07d1dcdea1f614906f1738be'
     or md5(pg_get_functiondef('public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)'::regprocedure)) <> '30965c22bd2d80997b2cea39da78fc63'
     or md5(pg_get_functiondef('public.home_reject_external_transaction_request(uuid,text)'::regprocedure)) <> 'cd87567543fbf2c58aa3453eab6af5c9' then
    raise exception 'CASH_TUITION_POSTDEPLOY_FUNCTION_FAILED';
  end if;
  if has_function_privilege('anon', 'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.home_create_external_transaction_request(uuid,uuid,text,uuid,text,uuid,text,text,date,numeric,text,text,text,jsonb,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.home_approve_external_transaction_request(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.home_approve_external_transaction_request(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.home_create_external_cny_transaction(uuid,uuid,text,date,numeric,text,text,text,uuid,text,text,text,uuid,text,text)', 'EXECUTE') then
    raise exception 'CASH_TUITION_POSTDEPLOY_ACL_FAILED';
  end if;
  if (select count(*) from public.home_external_transaction_requests) <> 34
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.home_external_transaction_requests row_value) <> 'ba0571247a869843c3ddda9075ea78dd'
     or (select count(*) from public.home_cny_transactions) <> 63
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.home_cny_transactions row_value) <> '3759e3d726400d5dd2225d79c78b9ac2'
     or (select count(*) from public.home_jpy_transactions) <> 31
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.home_jpy_transactions row_value) <> '95ab7cf8a8d167e9b052d3fc6b64614b'
     or exists (select 1 from public.home_accounts where id in (
       'f2fc0000-0000-4000-8000-00000000c001','f2fc0000-0000-4000-8000-00000000c002',
       'f2fc0000-0000-4000-8000-00000000c003','f2fc0000-0000-4000-8000-00000000c004'
     )) then
    raise exception 'CASH_TUITION_POSTDEPLOY_BUSINESS_OR_RESIDUE_FAILED';
  end if;
end
$assert$;
rollback;
