-- School V1 decommission P1-B1B additive payment RPC cutover.
-- Phase B1B-B only: create V2-only public entrypoints while preserving the
-- legacy authenticated entrypoints until the V2 Pages cutover is proven.
-- No business RPC is called and no business row is written by this file.
-- Status: executed in production 2026-08-09T14:23:31Z..14:23:41Z;
-- local synthetic parse/ACL/role/delegation/rollback/concurrency tests passed.
--
-- Business-model expansion declaration
-- New tables/columns/status/date/identity/source/snapshot/writable facts: none.
-- Field semantics/mutability/locking/authority/history/dual-write: unchanged.
-- Changed writer reachability: authenticated V2 receives two versioned
-- wrappers; the legacy signatures remain unchanged in this additive phase.
-- Approval: P1-B1B current instruction sections I, VII and X.

\set ON_ERROR_STOP on
\pset pager off

begin;

do $preflight$
declare
  v_confirm oid := to_regprocedure(
    'public.school_confirm_payment_request(uuid,uuid,date,numeric,text,text)'
  );
  v_reverse oid := to_regprocedure(
    'public.school_reverse_paid_payment_request(uuid,text,date)'
  );
begin
  if v_confirm is null or v_reverse is null then
    raise exception 'P1_B1B_LEGACY_PAYMENT_RPC_MISSING';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_confirm_payment_request')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request')<>1 then
    raise exception 'P1_B1B_UNEXPECTED_LEGACY_OVERLOAD';
  end if;

  if to_regprocedure(
       'public.school_confirm_payment_request_v2(uuid,uuid,date,numeric,text,text)'
     ) is not null
     or to_regprocedure(
       'public.school_reverse_paid_payment_request_v2(uuid,text,date)'
     ) is not null
     or exists (
       select 1
       from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and p.proname in (
           'school_confirm_payment_request_v2',
           'school_reverse_paid_payment_request_v2'
         )
     ) then
    raise exception 'P1_B1B_VERSIONED_RPC_ALREADY_EXISTS';
  end if;

  if not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_confirm
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef
         and p.provolatile='v'
         and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and md5(pg_catalog.pg_get_functiondef(p.oid))=
           'c15d26dfd81f36446b2f3e74b5ab74ed'
         and position(
           'perform public.school_require_current_app_admin();'
           in lower(pg_catalog.pg_get_functiondef(p.oid))
         )>0
     )
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_reverse
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef
         and p.provolatile='v'
         and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and md5(pg_catalog.pg_get_functiondef(p.oid))=
           'e5513e22edbfaa9948848b55857c6655'
         and position(
           'perform public.school_require_current_app_admin();'
           in lower(pg_catalog.pg_get_functiondef(p.oid))
         )>0
     ) then
    raise exception 'P1_B1B_LEGACY_DEFINITION_OR_SECURITY_DRIFT';
  end if;

  if pg_catalog.has_function_privilege('anon',v_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_reverse,'EXECUTE') then
    raise exception 'P1_B1B_LEGACY_EXECUTE_ACL_DRIFT';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_default_acl d
    join pg_catalog.pg_namespace n on n.oid=d.defaclnamespace
    cross join lateral pg_catalog.aclexplode(d.defaclacl) acl
    where d.defaclrole='postgres'::regrole
      and n.nspname='public'
      and d.defaclobjtype='f'
      and acl.grantee=0
  ) then
    raise exception 'P1_B1B_PUBLIC_FUNCTION_DEFAULT_ACL_FOUND';
  end if;
end;
$preflight$;

create function public.school_confirm_payment_request_v2(
  p_payment_request_id uuid,
  p_account_id uuid,
  p_pay_date date,
  p_amount numeric default null,
  p_note text default null,
  p_payment_method text default 'bank_transfer'
)
returns table (
  payment_request_id uuid,
  expense_id uuid,
  account_transaction_id uuid,
  status text,
  paid_at timestamptz,
  account_id uuid,
  balance_after numeric
)
language plpgsql
volatile
parallel unsafe
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_admin();

  return query
  select *
  from public.school_confirm_payment_request(
    p_payment_request_id,
    p_account_id,
    p_pay_date,
    p_amount,
    p_note,
    p_payment_method
  );
end;
$function$;

create function public.school_reverse_paid_payment_request_v2(
  p_payment_request_id uuid,
  p_reason text default null,
  p_reverse_date date default current_date
)
returns table (
  payment_request_id uuid,
  old_status text,
  new_status text,
  expense_id uuid,
  original_transaction_id uuid,
  reversal_transaction_id uuid,
  account_id uuid,
  reversal_amount numeric,
  balance_after numeric,
  reversed_at timestamptz
)
language plpgsql
volatile
parallel unsafe
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_admin();

  return query
  select *
  from public.school_reverse_paid_payment_request(
    p_payment_request_id,
    p_reason,
    p_reverse_date
  );
end;
$function$;

alter function public.school_confirm_payment_request_v2(
  uuid,uuid,date,numeric,text,text
) owner to postgres;
alter function public.school_reverse_paid_payment_request_v2(
  uuid,text,date
) owner to postgres;

revoke all on function public.school_confirm_payment_request_v2(
  uuid,uuid,date,numeric,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_confirm_payment_request_v2(
  uuid,uuid,date,numeric,text,text
) to authenticated;

revoke all on function public.school_reverse_paid_payment_request_v2(
  uuid,text,date
) from public,anon,authenticated,service_role;
grant execute on function public.school_reverse_paid_payment_request_v2(
  uuid,text,date
) to authenticated;

comment on function public.school_confirm_payment_request_v2(
  uuid,uuid,date,numeric,text,text
) is
  'P1-B1B V2 authenticated active-admin entrypoint. Delegates exactly once to the audited legacy owner implementation; payment semantics, locks, writes, result and errors are unchanged.';

comment on function public.school_reverse_paid_payment_request_v2(
  uuid,text,date
) is
  'P1-B1B V2 authenticated active-admin entrypoint. Delegates exactly once to the audited legacy owner implementation; reversal semantics, locks, writes, result and errors are unchanged.';

do $postdeploy$
declare
  v_old_confirm oid := to_regprocedure(
    'public.school_confirm_payment_request(uuid,uuid,date,numeric,text,text)'
  );
  v_old_reverse oid := to_regprocedure(
    'public.school_reverse_paid_payment_request(uuid,text,date)'
  );
  v_new_confirm oid := to_regprocedure(
    'public.school_confirm_payment_request_v2(uuid,uuid,date,numeric,text,text)'
  );
  v_new_reverse oid := to_regprocedure(
    'public.school_reverse_paid_payment_request_v2(uuid,text,date)'
  );
begin
  if v_new_confirm is null or v_new_reverse is null then
    raise exception 'P1_B1B_VERSIONED_RPC_CREATE_FAILED';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_confirm_payment_request_v2')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request_v2')<>1 then
    raise exception 'P1_B1B_UNEXPECTED_VERSIONED_OVERLOAD';
  end if;

  if pg_catalog.has_function_privilege('anon',v_new_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_old_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_old_reverse,'EXECUTE') then
    raise exception 'P1_B1B_ADDITIVE_EXECUTE_ACL_FAILED';
  end if;

  if not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_new_confirm
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and position('school_require_current_app_admin' in p.prosrc)>0
         and position('school_confirm_payment_request' in p.prosrc)>0
     )
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_new_reverse
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and position('school_require_current_app_admin' in p.prosrc)>0
         and position('school_reverse_paid_payment_request' in p.prosrc)>0
     ) then
    raise exception 'P1_B1B_VERSIONED_SECURITY_CONTRACT_FAILED';
  end if;

  if (select pg_catalog.pg_get_function_result(v_new_confirm))
       is distinct from (select pg_catalog.pg_get_function_result(v_old_confirm))
     or (select pg_catalog.pg_get_function_result(v_new_reverse))
       is distinct from (select pg_catalog.pg_get_function_result(v_old_reverse)) then
    raise exception 'P1_B1B_VERSIONED_RESULT_CONTRACT_DRIFT';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
    ) acl
    where p.oid in (v_new_confirm,v_new_reverse)
      and acl.grantee=0
      and acl.privilege_type='EXECUTE'
  ) then
    raise exception 'P1_B1B_VERSIONED_PUBLIC_EXECUTE_FOUND';
  end if;
end;
$postdeploy$;

notify pgrst,'reload schema';

commit;
