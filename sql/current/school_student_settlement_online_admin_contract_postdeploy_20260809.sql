-- School V2 Phase A online settlement DB contract postdeploy (read-only).
\set ON_ERROR_STOP on
\pset pager off

begin transaction read only;
set local statement_timeout = '120s';

do $catalog$
declare
  v_name text;
  v_expected_count integer;
begin
  foreach v_name in array array[
    'school_assert_student_settlement_online_admin',
    'school_assert_student_monthly_settlement_online_writable',
    'school_assert_student_settlement_online_expected_facts',
    'school_get_student_monthly_settlement_online_status_core',
    'school_get_student_monthly_settlement_online_status',
    'school_save_student_monthly_settlement_draft_online_admin',
    'school_lock_student_monthly_settlement_online_admin'
  ] loop
    select count(*) into v_expected_count
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    join pg_catalog.pg_roles r on r.oid = p.proowner
    where n.nspname = 'public' and p.proname = v_name
      and r.rolname = 'postgres'
      and p.prosecdef
      and p.proconfig = array['search_path=pg_catalog, public']::text[];
    if v_expected_count <> 1 then
      raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_CATALOG_INVALID:%:%',
        v_name, v_expected_count;
    end if;
  end loop;

  if md5(pg_get_functiondef(to_regprocedure(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'
     ))) <> 'f9d85d62be938c5c92b2feb047616c3c'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'
     ))) <> '9b68480b55736c0602b28f637dcdc7a1c'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)'
     ))) <> '5982596c31fa6cbf6c99df0cc5bee732'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_unlock_student_monthly_settlement(uuid,text)'
     ))) <> '653356cc5c9c75b584d0d5cc5104397f'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_relock_student_monthly_settlement(uuid,text)'
     ))) <> '6357848be1eb6c1cf11016d01cad14cb'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)'
     ))) <> '5296dbdc64dbe2f36ccae242c5740a1c'
     or md5(pg_get_functiondef(to_regprocedure(
       'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)'
     ))) <> 'd9e07d2f330f34637fafb570743a5a59' then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_PROTECTED_DEFINITION_DRIFT';
  end if;
end
$catalog$;

do $acl$
declare
  v_role text;
begin
  foreach v_role in array array['public','anon','authenticated'] loop
    if has_function_privilege(v_role,
      'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)', 'EXECUTE') then
      raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_WRAPPER_EXPOSED:%', v_role;
    end if;
  end loop;
  if not has_function_privilege('service_role',
      'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role',
      'public.school_lock_student_monthly_settlement_online_admin(uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,uuid)', 'EXECUTE') then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_SERVICE_WRAPPER_MISSING';
  end if;
  foreach v_role in array array['public','anon','authenticated','service_role'] loop
    if has_function_privilege(v_role,
      'public.school_lock_student_monthly_settlement(uuid,text,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_unlock_student_monthly_settlement(uuid,text)', 'EXECUTE')
       or has_function_privilege(v_role,
      'public.school_relock_student_monthly_settlement(uuid,text)', 'EXECUTE') then
      raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_CORE_EXPOSED:%', v_role;
    end if;
  end loop;
  if not has_function_privilege('authenticated',
      'public.school_get_student_monthly_settlement_online_status(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon',
      'public.school_get_student_monthly_settlement_online_status(uuid,text)', 'EXECUTE')
     or has_function_privilege('service_role',
      'public.school_get_student_monthly_settlement_online_status(uuid,text)', 'EXECUTE') then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_STATUS_ACL_INVALID';
  end if;
  if has_table_privilege('anon', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('anon', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('anon', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE') then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_TABLE_DML_EXPOSED';
  end if;
end
$acl$;

-- The no_wage-only wage detail must never be returned as a settlement mutation blocker.
do $no_wage$
begin
  if exists (
    select 1
    from public.school_get_student_monthly_settlement_wage_blockers('2026-07', null) b
    where exists (
      select 1
      from public.school_list_r1d_e_c_student_month_lessons(b.student_id, b.year_month) r
      join public.school_teacher_wage_lock_details d on d.lesson_record_id = r.lesson_id
      join public.school_teacher_wage_locks w on w.id = d.lock_id
      where coalesce(w.status, '') <> 'void' and w.voided_at is null
      group by b.student_id
      having bool_and(coalesce(d.is_no_wage, false)
        or coalesce(d.settlement_type, '') = 'no_wage')
    )
  ) then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_NO_WAGE_MISCLASSIFIED';
  end if;
end
$no_wage$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select user_id from public.school_app_memberships
      where is_active and role = 'admin' order by created_at, user_id limit 1),
    'role', 'authenticated'
  )::text,
  true
);

do $effective_states$
declare
  v jsonb;
begin
  v := public.school_get_student_monthly_settlement_online_status(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc', '2026-07'
  );
  if v->'effective_state'->>'effective_status' <> 'ordinary_locked' then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_ORDINARY_STATE_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-07'
  );
  if v->'effective_state'->>'effective_status' <> 'historically_consumed_immutable' then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_CONSUMED_STATE_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-07'
  );
  if v->'effective_state'->>'effective_status' <> 'historical_zero_carry_complete' then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_HISTORICAL_ZERO_STATE_INVALID:%', v;
  end if;
  v := public.school_get_student_monthly_settlement_online_status(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc', '2026-08'
  );
  if v->'effective_state'->>'effective_status' <> 'incomplete' then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_INCOMPLETE_STATE_INVALID:%', v;
  end if;
end
$effective_states$;
reset role;

do $invariants$
begin
  if exists(select 1 from auth.users where id::text like 'a1090000-%')
     or exists(select 1 from public.school_app_memberships where user_id::text like 'a1090000-%')
     or exists(select 1 from public.school_students where id::text like 'a1090000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_monthly_settlements where student_id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_settlement_source_treatment_drafts where student_id::text like 'a1090000-%')
     or exists(select 1 from public.school_student_settlement_adjustment_drafts where student_id::text like 'a1090000-%') then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_FIXTURE_RESIDUE';
  end if;
  if (select count(*) from public.school_student_monthly_settlements) <> 18
     or (select count(*) from public.school_student_settlement_adjustment_drafts) <> 7
     or (select count(*) from public.school_student_settlement_source_treatment_drafts) <> 1
     or (select count(*) from public.school_student_monthly_settlement_historical_completion_evidenc) <> 4
     or (select count(*) from public.school_income_records) <> 55
     or (select count(*) from public.school_lesson_records) <> 744
     or (select count(*) from public.school_student_tuition_bills) <> 22
     or (select count(*) from public.school_student_tuition_generation_revisions) <> 20
     or (select count(*) from public.school_teacher_wage_locks) <> 103
     or (select count(*) from public.school_teacher_wage_lock_details) <> 612 then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_BUSINESS_COUNT_DRIFT';
  end if;
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'enabled')) <> 3 then
    raise exception 'SETTLEMENT_ONLINE_POSTDEPLOY_GATE_DRIFT';
  end if;
end
$invariants$;

select feature_key, state
from public.school_feature_gates
where feature_key like 'student_tuition_%'
order by feature_key;

select p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  r.rolname as owner,
  p.prosecdef,
  p.proconfig,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
join pg_catalog.pg_roles r on r.oid = p.proowner
where n.nspname = 'public'
  and p.proname in (
    'school_get_student_monthly_settlement_online_status',
    'school_save_student_monthly_settlement_draft_online_admin',
    'school_lock_student_monthly_settlement_online_admin'
  )
order by p.proname;

rollback;
select 'SETTLEMENT_ONLINE_PHASE_A_POSTDEPLOY_PASS' as result;
