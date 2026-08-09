-- Read-only production closure verification.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner_name,
  p.prosecdef,p.proconfig,
  has_function_privilege('anon',p.oid,'execute') anon_execute,
  has_function_privilege('authenticated',p.oid,'execute') authenticated_execute,
  has_function_privilege('service_role',p.oid,'execute') service_role_execute,
  md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_lock_student_monthly_settlement',
  'school_relock_student_monthly_settlement',
  'school_set_student_monthly_settlement_draft_adjustment',
  'school_set_student_settlement_source_treatment_draft',
  'school_unlock_student_monthly_settlement'
)
order by 1;

do $verify$
declare
  v_expected text[] := array[
    'school_lock_student_monthly_settlement(uuid,text,text)',
    'school_relock_student_monthly_settlement(uuid,text)',
    'school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
    'school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)',
    'school_unlock_student_monthly_settlement(uuid,text)'
  ];
  v_actual text[];
  v_signature text;
  v_oid regprocedure;
  v_definition text;
begin
  select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
  into v_actual
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'school_lock_student_monthly_settlement','school_relock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment',
    'school_set_student_settlement_source_treatment_draft',
    'school_unlock_student_monthly_settlement'
  );
  if v_actual is distinct from v_expected then
    raise exception 'SETTLEMENT_WRITER_P0_POSTDEPLOY_SIGNATURE_DRIFT';
  end if;
  foreach v_signature in array v_expected loop
    v_oid:=('public.'||v_signature)::regprocedure;
    v_definition:=pg_get_functiondef(v_oid);
    if pg_get_userbyid((select proowner from pg_proc where oid=v_oid))<>'postgres'
       or not (select prosecdef from pg_proc where oid=v_oid)
       or (select proconfig from pg_proc where oid=v_oid)
          is distinct from array['search_path=pg_catalog, public']::text[]
       or has_function_privilege('anon',v_oid,'execute')
       or has_function_privilege('authenticated',v_oid,'execute')
       or has_function_privilege('service_role',v_oid,'execute')
       or v_definition ~* '\mexecute\M' then
      raise exception 'SETTLEMENT_WRITER_P0_POSTDEPLOY_SECURITY_FAILED: %',v_signature;
    end if;
  end loop;
  if position('school_assert_tuition_settlement_month_mutable' in pg_get_functiondef(
    'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
  ))=0 then
    raise exception 'SETTLEMENT_WRITER_P0_POSTDEPLOY_ACTIVE_REVISION_GUARD_MISSING';
  end if;
  if has_function_privilege('anon',
       'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
       'execute')
     or has_function_privilege('authenticated',
       'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
       'execute')
     or not has_function_privilege('service_role',
       'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
       'execute')
     or has_function_privilege('anon',
       'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)',
       'execute')
     or has_function_privilege('authenticated',
       'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)',
       'execute')
     or not has_function_privilege('service_role',
       'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)',
       'execute') then
    raise exception 'SETTLEMENT_WRITER_P0_POSTDEPLOY_WRAPPER_ACL_FAILED';
  end if;
end
$verify$;

select r.rolname,c.relname,
  has_table_privilege(r.rolname,c.oid,'insert') insert_allowed,
  has_table_privilege(r.rolname,c.oid,'update') update_allowed,
  has_table_privilege(r.rolname,c.oid,'delete') delete_allowed
from pg_roles r
cross join pg_class c
where r.rolname in ('anon','authenticated','service_role')
  and c.oid in (
    'public.school_student_monthly_settlements'::regclass,
    'public.school_student_settlement_adjustment_drafts'::regclass,
    'public.school_student_settlement_source_treatment_drafts'::regclass
  )
order by r.rolname,c.relname;

select feature_key,state,updated_at from public.school_feature_gates
where feature_key in (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
order by feature_key;

select 'SETTLEMENT_WRITER_P0_POSTDEPLOY_PASS' result;
rollback;
