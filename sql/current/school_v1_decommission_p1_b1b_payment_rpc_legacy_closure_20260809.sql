-- School V1 decommission P1-B1B legacy payment RPC closure.
-- Phase B1B-D only: revoke client EXECUTE from the two exact legacy signatures
-- after the V2 Pages cutover to the versioned wrappers is proven online.
-- No business RPC is called and no business row is written by this file.
--
-- Business-model expansion declaration
-- New tables/columns/status/date/identity/source/snapshot/writable facts: none.
-- Field semantics/mutability/locking/authority/history/dual-write: unchanged.
-- Changed writer reachability: the two legacy payment RPC signatures become
-- owner-only; authenticated V2 continues through the existing _v2 wrappers.
-- Approval: P1-B1B current instruction sections I, XIII and XIX.

\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
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
  v_outside_count bigint;
  v_outside_hash text;
begin
  if v_old_confirm is null or v_old_reverse is null
     or v_new_confirm is null or v_new_reverse is null then
    raise exception 'P1_B1B_PAYMENT_RPC_MISSING';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_confirm_payment_request')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_confirm_payment_request_v2')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request_v2')<>1 then
    raise exception 'P1_B1B_UNEXPECTED_PAYMENT_OVERLOAD';
  end if;

  if not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_old_confirm
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
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
       where p.oid=v_old_reverse
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and md5(pg_catalog.pg_get_functiondef(p.oid))=
           'e5513e22edbfaa9948848b55857c6655'
         and position(
           'perform public.school_require_current_app_admin();'
           in lower(pg_catalog.pg_get_functiondef(p.oid))
         )>0
     )
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_new_confirm
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and md5(pg_catalog.pg_get_functiondef(p.oid))=
           'af6f0a1abd5a3090351c6eed785ef2f5'
         and position('school_require_current_app_admin' in p.prosrc)>0
         and position('school_confirm_payment_request' in p.prosrc)>0
     )
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid=v_new_reverse
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.prosecdef and p.provolatile='v' and p.proparallel='u'
         and p.proconfig=array['search_path=pg_catalog, public']::text[]
         and md5(pg_catalog.pg_get_functiondef(p.oid))=
           '002a27499d63e31f82b104065944ba5e'
         and position('school_require_current_app_admin' in p.prosrc)>0
         and position('school_reverse_paid_payment_request' in p.prosrc)>0
     ) then
    raise exception 'P1_B1B_PAYMENT_DEFINITION_OR_SECURITY_DRIFT';
  end if;

  if pg_catalog.pg_get_function_result(v_new_confirm)
       is distinct from pg_catalog.pg_get_function_result(v_old_confirm)
     or pg_catalog.pg_get_function_result(v_new_reverse)
       is distinct from pg_catalog.pg_get_function_result(v_old_reverse) then
    raise exception 'P1_B1B_PAYMENT_RESULT_CONTRACT_DRIFT';
  end if;

  if exists (
       select 1
       from pg_catalog.pg_proc p
       cross join lateral pg_catalog.aclexplode(
         coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
       ) acl
       where p.oid in (v_old_confirm,v_old_reverse,v_new_confirm,v_new_reverse)
         and acl.grantee=0 and acl.privilege_type='EXECUTE'
     )
     or pg_catalog.has_function_privilege('anon',v_old_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_old_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_old_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_old_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_old_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_old_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_new_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_old_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_old_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_new_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_new_reverse,'EXECUTE') then
    raise exception 'P1_B1B_PAYMENT_EXECUTE_ACL_DRIFT';
  end if;

  if exists (
       select 1
       from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and position('school_confirm_payment_request' in p.prosrc)>0
         and p.oid<>v_new_confirm
     )
     or exists (
       select 1
       from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and position('school_reverse_paid_payment_request' in p.prosrc)>0
         and p.oid<>v_new_reverse
     ) then
    raise exception 'P1_B1B_UNEXPECTED_LEGACY_DATABASE_CALLER';
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
      and acl.privilege_type='EXECUTE'
  ) then
    raise exception 'P1_B1B_PUBLIC_FUNCTION_DEFAULT_ACL_FOUND';
  end if;

  select count(*),md5(coalesce(string_agg(
    p.oid::text || '|' || p.proname || '|' ||
    pg_catalog.pg_get_function_identity_arguments(p.oid) || '|' ||
    pg_catalog.pg_get_userbyid(p.proowner) || '|' ||
    md5(pg_catalog.pg_get_functiondef(p.oid)) || '|' ||
    coalesce((
      select string_agg(
        acl.grantee::text || ':' || acl.privilege_type || ':' || acl.is_grantable::text,
        ',' order by acl.grantee,acl.privilege_type,acl.is_grantable
      )
      from pg_catalog.aclexplode(
        coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
      ) acl
    ),''),
    '' order by p.oid
  ),''))
  into v_outside_count,v_outside_hash
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname not in (
      'school_confirm_payment_request',
      'school_reverse_paid_payment_request',
      'school_confirm_payment_request_v2',
      'school_reverse_paid_payment_request_v2'
    );

  if v_outside_count<>337
     or v_outside_hash<>'1a87a3edccf141efe317addc6e54653f' then
    raise exception 'P1_B1B_OUTSIDE_FUNCTION_CATALOG_DRIFT';
  end if;
end;
$preflight$;

revoke all on function public.school_confirm_payment_request(
  uuid,uuid,date,numeric,text,text
) from public,anon,authenticated,service_role;

revoke all on function public.school_reverse_paid_payment_request(
  uuid,text,date
) from public,anon,authenticated,service_role;

comment on function public.school_confirm_payment_request(
  uuid,uuid,date,numeric,text,text
) is
  'P1-B1B deprecated legacy payment implementation. Owner-only internal target for school_confirm_payment_request_v2; clients must not execute this signature directly.';

comment on function public.school_reverse_paid_payment_request(
  uuid,text,date
) is
  'P1-B1B deprecated legacy payment reversal implementation. Owner-only internal target for school_reverse_paid_payment_request_v2; clients must not execute this signature directly.';

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
  v_outside_count bigint;
  v_outside_hash text;
begin
  if exists (
       select 1
       from pg_catalog.pg_proc p
       cross join lateral pg_catalog.aclexplode(
         coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
       ) acl
       where p.oid in (v_old_confirm,v_old_reverse,v_new_confirm,v_new_reverse)
         and acl.grantee=0 and acl.privilege_type='EXECUTE'
     )
     or pg_catalog.has_function_privilege('anon',v_old_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',v_old_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_old_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_old_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',v_old_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_old_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_old_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_old_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_new_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_confirm,'EXECUTE')
     or pg_catalog.has_function_privilege('anon',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',v_new_reverse,'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',v_new_reverse,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_new_confirm,'EXECUTE')
     or not pg_catalog.has_function_privilege('postgres',v_new_reverse,'EXECUTE') then
    raise exception 'P1_B1B_LEGACY_CLOSURE_ACL_FAILED';
  end if;

  if md5(pg_catalog.pg_get_functiondef(v_old_confirm))<>
       'c15d26dfd81f36446b2f3e74b5ab74ed'
     or md5(pg_catalog.pg_get_functiondef(v_old_reverse))<>
       'e5513e22edbfaa9948848b55857c6655'
     or md5(pg_catalog.pg_get_functiondef(v_new_confirm))<>
       'af6f0a1abd5a3090351c6eed785ef2f5'
     or md5(pg_catalog.pg_get_functiondef(v_new_reverse))<>
       '002a27499d63e31f82b104065944ba5e'
     or pg_catalog.pg_get_function_result(v_new_confirm)
          is distinct from pg_catalog.pg_get_function_result(v_old_confirm)
     or pg_catalog.pg_get_function_result(v_new_reverse)
          is distinct from pg_catalog.pg_get_function_result(v_old_reverse) then
    raise exception 'P1_B1B_PAYMENT_CONTRACT_CHANGED_DURING_CLOSURE';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_confirm_payment_request')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_confirm_payment_request_v2')<>1
     or (select count(*) from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='school_reverse_paid_payment_request_v2')<>1 then
    raise exception 'P1_B1B_PAYMENT_OVERLOAD_CHANGED_DURING_CLOSURE';
  end if;

  if exists (
       select 1
       from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and position('school_confirm_payment_request' in p.prosrc)>0
         and p.oid<>v_new_confirm
     )
     or exists (
       select 1
       from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and position('school_reverse_paid_payment_request' in p.prosrc)>0
         and p.oid<>v_new_reverse
     ) then
    raise exception 'P1_B1B_UNEXPECTED_LEGACY_CALLER_AFTER_CLOSURE';
  end if;

  select count(*),md5(coalesce(string_agg(
    p.oid::text || '|' || p.proname || '|' ||
    pg_catalog.pg_get_function_identity_arguments(p.oid) || '|' ||
    pg_catalog.pg_get_userbyid(p.proowner) || '|' ||
    md5(pg_catalog.pg_get_functiondef(p.oid)) || '|' ||
    coalesce((
      select string_agg(
        acl.grantee::text || ':' || acl.privilege_type || ':' || acl.is_grantable::text,
        ',' order by acl.grantee,acl.privilege_type,acl.is_grantable
      )
      from pg_catalog.aclexplode(
        coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
      ) acl
    ),''),
    '' order by p.oid
  ),''))
  into v_outside_count,v_outside_hash
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname not in (
      'school_confirm_payment_request',
      'school_reverse_paid_payment_request',
      'school_confirm_payment_request_v2',
      'school_reverse_paid_payment_request_v2'
    );

  if v_outside_count<>337
     or v_outside_hash<>'1a87a3edccf141efe317addc6e54653f' then
    raise exception 'P1_B1B_OUTSIDE_FUNCTION_CHANGED_DURING_CLOSURE';
  end if;
end;
$postdeploy$;

notify pgrst,'reload schema';

commit;

-- Exact recovery plan (do not run without evidence of a closure-caused V2
-- critical blocker and the recovery authority already granted by P1-B1B):
-- grant execute on function public.school_confirm_payment_request(
--   uuid,uuid,date,numeric,text,text
-- ) to authenticated;
-- grant execute on function public.school_reverse_paid_payment_request(
--   uuid,text,date
-- ) to authenticated;
-- notify pgrst,'reload schema';
