-- School V2 ordinary-expense P0 permission closure read-only postdeploy.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $verify$
declare
  v_signature regprocedure;
begin
  v_signature :=
    'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'::regprocedure;

  if has_function_privilege('anon', v_signature, 'EXECUTE')
     or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
     or has_function_privilege('service_role', v_signature, 'EXECUTE') then
    raise exception 'P0_EXPENSE_CREATE_ACL_INVALID';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_roles r on r.oid = p.proowner
    where p.oid = v_signature
      and r.rolname = 'postgres'
      and p.prosecdef
      and p.proconfig @> array['search_path=pg_catalog, public']
      and pg_get_functiondef(p.oid) like '%school_require_current_app_admin()%'
      and pg_get_functiondef(p.oid) like '%pg_try_advisory_xact_lock%'
  ) then
    raise exception 'P0_EXPENSE_CREATE_CONTRACT_INVALID';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'school_create_expense_record'
  ) <> 1 then
    raise exception 'P0_EXPENSE_CREATE_OVERLOAD_INVALID';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'school_request_cash_expense_payment_confirmation',
        'school_mark_cash_expense_request_submitted',
        'school_mark_cash_expense_confirmed',
        'school_mark_cash_expense_rejected'
      )
  ) <> 4 then
    raise exception 'P0_EXPENSE_CASH_OVERLOAD_INVALID';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'school_request_cash_expense_payment_confirmation',
        'school_mark_cash_expense_request_submitted',
        'school_mark_cash_expense_confirmed',
        'school_mark_cash_expense_rejected'
      )
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or not has_function_privilege('service_role', p.oid, 'EXECUTE')
        or not p.prosecdef
        or not p.proconfig @> array['search_path=pg_catalog, public']
      )
  ) then
    raise exception 'P0_EXPENSE_CASH_WRITER_CONTRACT_INVALID';
  end if;

  if exists (
    select 1
    from (values
      ('school_expense_records'),
      ('school_accounts'),
      ('school_account_transactions')
    ) as target(table_name)
    cross join (values ('anon'), ('authenticated')) as role_name(grantee)
    where has_table_privilege(
      role_name.grantee,
      format('public.%I', target.table_name),
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  ) then
    raise exception 'P0_EXPENSE_TABLE_DML_ACL_INVALID';
  end if;

  if exists (
    select 1
    from (values
      ('school_expense_records'),
      ('school_accounts'),
      ('school_account_transactions')
    ) as target(table_name)
    where has_table_privilege('anon', format('public.%I', target.table_name), 'SELECT')
       or not has_table_privilege('authenticated', format('public.%I', target.table_name), 'SELECT')
  ) then
    raise exception 'P0_EXPENSE_TABLE_SELECT_ACL_INVALID';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'school_expense_records',
        'school_accounts',
        'school_account_transactions'
      )
      and cmd <> 'SELECT'
      and roles && array['public', 'anon', 'authenticated']::name[]
  )
  or (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'school_expense_records',
        'school_accounts',
        'school_account_transactions'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ) <> 3 then
    raise exception 'P0_EXPENSE_RLS_POLICY_INVALID';
  end if;

  if exists (
    select 1
    from pg_default_acl d
    left join pg_namespace n on n.oid = d.defaclnamespace
    cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and n.nspname = 'public'
      and a.grantee in (
        0,
        'anon'::regrole::oid,
        'authenticated'::regrole::oid
      )
  ) then
    raise exception 'P0_EXPENSE_DEFAULT_ACL_INVALID';
  end if;
end;
$verify$;

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;

select p.oid::regprocedure::text as signature,
       r.rolname as owner,
       p.prosecdef,
       p.proconfig,
       p.proacl,
       md5(pg_get_functiondef(p.oid)) as definition_md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_roles r on r.oid = p.proowner
where n.nspname = 'public'
  and p.proname in (
    'school_create_expense_record',
    'school_request_cash_expense_payment_confirmation',
    'school_mark_cash_expense_request_submitted',
    'school_mark_cash_expense_confirmed',
    'school_mark_cash_expense_rejected'
  )
order by p.oid::regprocedure::text;

select 'P0_EXPENSE_PERMISSION_CLOSURE_POSTDEPLOY_PASS' as result;
rollback;
