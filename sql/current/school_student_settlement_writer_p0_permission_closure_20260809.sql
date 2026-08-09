-- Student monthly settlement P0: close every browser/client core writer.
-- Execute atomically with psql -1. No business rows are written by this file.
\set ON_ERROR_STOP on

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
declare
  v_expected text[] := array[
    'school_lock_student_monthly_settlement(uuid,text,text)',
    'school_relock_student_monthly_settlement(uuid,text)',
    'school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
    'school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)',
    'school_unlock_student_monthly_settlement(uuid,text)'
  ];
  v_actual text[];
begin
  select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
  into v_actual
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'school_lock_student_monthly_settlement',
      'school_relock_student_monthly_settlement',
      'school_set_student_monthly_settlement_draft_adjustment',
      'school_set_student_settlement_source_treatment_draft',
      'school_unlock_student_monthly_settlement'
    );
  if v_actual is distinct from v_expected then
    raise exception 'SETTLEMENT_WRITER_P0_SIGNATURE_DRIFT: expected %, actual %',
      v_expected,v_actual;
  end if;
end
$preflight$;

do $lock_guard$
declare
  v_oid regprocedure :=
    'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure;
  v_definition text := pg_get_functiondef(v_oid);
  v_old text := $needle$  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, v_business_entity_id, v_year_month
  );
  if exists ($needle$;
  v_new text := $replacement$  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, v_business_entity_id, v_year_month
  );
  perform public.school_assert_tuition_settlement_month_mutable(
    p_student_id, v_year_month
  );
  if exists ($replacement$;
begin
  if position('school_assert_tuition_settlement_month_mutable' in v_definition)=0 then
    if md5(v_definition)<>'19033b559cacb99677fc1d3583f78ad3'
       or position(v_old in v_definition)=0 then
      raise exception 'SETTLEMENT_WRITER_P0_CORE_LOCK_DEFINITION_DRIFT';
    end if;
    v_definition := replace(v_definition,v_old,v_new);
    if position('school_assert_tuition_settlement_month_mutable' in v_definition)=0 then
      raise exception 'SETTLEMENT_WRITER_P0_CORE_LOCK_GUARD_PATCH_FAILED';
    end if;
    execute v_definition;
  elsif position(v_new in v_definition)=0 then
    raise exception 'SETTLEMENT_WRITER_P0_CORE_LOCK_GUARD_UNEXPECTED_SHAPE';
  end if;
end
$lock_guard$;

alter function public.school_lock_student_monthly_settlement(uuid,text,text)
  owner to postgres;
alter function public.school_set_student_monthly_settlement_draft_adjustment(
  uuid,text,numeric,text,text,text
) owner to postgres;
alter function public.school_set_student_settlement_source_treatment_draft(
  uuid,text,text,numeric,text,date,text
) owner to postgres;
alter function public.school_unlock_student_monthly_settlement(uuid,text)
  owner to postgres;
alter function public.school_relock_student_monthly_settlement(uuid,text)
  owner to postgres;

revoke all on function public.school_lock_student_monthly_settlement(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_set_student_monthly_settlement_draft_adjustment(
  uuid,text,numeric,text,text,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_set_student_settlement_source_treatment_draft(
  uuid,text,text,numeric,text,date,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_unlock_student_monthly_settlement(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_relock_student_monthly_settlement(uuid,text)
  from public,anon,authenticated,service_role;

comment on function public.school_lock_student_monthly_settlement(uuid,text,text) is
  'P0 owner-only core lock. Operational save/lock must use the service-role-only local wrapper; active successor tuition revision is rejected by the shared authoritative month-mutability guard.';
comment on function public.school_set_student_monthly_settlement_draft_adjustment(
  uuid,text,numeric,text,text,text
) is 'P0 owner-only core adjustment-draft writer. Operational save must use the service-role-only local wrapper.';
comment on function public.school_set_student_settlement_source_treatment_draft(
  uuid,text,text,numeric,text,date,text
) is 'P0 owner-only core source-treatment writer. Operational save must use the service-role-only local wrapper.';
comment on function public.school_unlock_student_monthly_settlement(uuid,text) is
  'P0 owner-only internal lifecycle writer. There is no service-role or browser operational entry point.';
comment on function public.school_relock_student_monthly_settlement(uuid,text) is
  'P0 owner-only internal lifecycle writer. There is no service-role or browser operational entry point.';

do $closure$
declare
  v_signature text;
  v_oid regprocedure;
  v_role text;
begin
  foreach v_signature in array array[
    'public.school_lock_student_monthly_settlement(uuid,text,text)',
    'public.school_relock_student_monthly_settlement(uuid,text)',
    'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
    'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)',
    'public.school_unlock_student_monthly_settlement(uuid,text)'
  ] loop
    v_oid := v_signature::regprocedure;
    if pg_get_userbyid((select proowner from pg_proc where oid=v_oid))<>'postgres'
       or not (select prosecdef from pg_proc where oid=v_oid)
       or (select proconfig from pg_proc where oid=v_oid)
            is distinct from array['search_path=pg_catalog, public']::text[] then
      raise exception 'SETTLEMENT_WRITER_P0_SECURITY_CONTRACT_FAILED: %',v_signature;
    end if;
    foreach v_role in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(v_role,v_oid,'execute') then
        raise exception 'SETTLEMENT_WRITER_P0_CLIENT_EXECUTE_REMAINS: % %',v_role,v_signature;
      end if;
    end loop;
    if coalesce((
      select bool_or(a.privilege_type='EXECUTE')
      from pg_proc p,
        lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=v_oid and a.grantee=0
    ),false) then
      raise exception 'SETTLEMENT_WRITER_P0_PUBLIC_EXECUTE_REMAINS: %',v_signature;
    end if;
  end loop;
  if position('school_assert_tuition_settlement_month_mutable' in pg_get_functiondef(
    'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
  ))=0 then
    raise exception 'SETTLEMENT_WRITER_P0_ACTIVE_REVISION_GUARD_MISSING';
  end if;
end
$closure$;

select 'SETTLEMENT_WRITER_P0_PERMISSION_CLOSURE_APPLIED' result;
