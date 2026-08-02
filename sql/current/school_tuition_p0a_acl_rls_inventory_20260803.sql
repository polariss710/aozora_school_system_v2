-- Read-only ACL/RLS/execute inventory for School V2 tuition P0-A.
\set ON_ERROR_STOP on
\pset pager off
begin isolation level repeatable read read only;

select c.oid::regclass::text as table_name,c.relrowsecurity,c.relforcerowsecurity,
       pg_get_userbyid(c.relowner) as owner
from pg_class c
where c.oid in (
  'public.school_student_monthly_settlements'::regclass,
  'public.school_student_settlement_adjustment_drafts'::regclass,
  'public.school_student_settlement_adjustments'::regclass,
  'public.school_student_settlement_carryovers'::regclass
) order by table_name;

select table_name,grantee,privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name in (
  'school_student_monthly_settlements',
  'school_student_settlement_adjustment_drafts',
  'school_student_settlement_adjustments',
  'school_student_settlement_carryovers'
) order by table_name,grantee,privilege_type;

select tablename,policyname,roles,cmd,qual,with_check
from pg_policies
where schemaname='public' and tablename in (
  'school_student_monthly_settlements',
  'school_student_settlement_adjustment_drafts',
  'school_student_settlement_adjustments',
  'school_student_settlement_carryovers'
) order by tablename,policyname;

select p.oid::regprocedure::text as signature,pg_get_userbyid(p.proowner) as owner,
       p.prosecdef,coalesce(array_to_string(p.proconfig,','),'') as config,
       coalesce(array_to_string(p.proacl,','),'') as acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_lock_student_monthly_settlement',
  'school_unlock_student_monthly_settlement',
  'school_relock_student_monthly_settlement',
  'school_set_student_monthly_settlement_draft_adjustment',
  'school_apply_student_monthly_settlement_adjustment',
  'school_tuition_p0a_consumed_bill_id',
  'school_assert_tuition_settlement_mutable',
  'school_assert_tuition_settlement_month_mutable',
  'school_tuition_p0a_lock_generate_scope',
  'school_tuition_p0a_lock_settlement_mutation_scope',
  'school_guard_tuition_consumed_settlement_row',
  'school_guard_tuition_consumed_settlement_child'
) and p.prokind='f'
order by signature;

select c.relname as table_name,t.tgname,pg_get_triggerdef(t.oid,true) as definition
from pg_trigger t join pg_class c on c.oid=t.tgrelid
where not t.tgisinternal and c.oid in (
  'public.school_student_monthly_settlements'::regclass,
  'public.school_student_settlement_adjustment_drafts'::regclass,
  'public.school_student_settlement_adjustments'::regclass,
  'public.school_student_settlement_carryovers'::regclass
) order by table_name,t.tgname;

do $assertions$
declare
  v_table text;
begin
  foreach v_table in array array[
    'public.school_student_monthly_settlements',
    'public.school_student_settlement_adjustment_drafts',
    'public.school_student_settlement_adjustments',
    'public.school_student_settlement_carryovers'
  ] loop
    if has_table_privilege('anon',v_table,'INSERT,UPDATE,DELETE,TRUNCATE')
       or has_table_privilege('authenticated',v_table,'INSERT,UPDATE,DELETE,TRUNCATE')
       or has_table_privilege('service_role',v_table,'INSERT,UPDATE,DELETE,TRUNCATE')
       or not has_table_privilege('anon',v_table,'SELECT')
       or not has_table_privilege('authenticated',v_table,'SELECT')
       or not has_table_privilege('service_role',v_table,'SELECT') then
      raise exception 'TUITION_P0A_TABLE_PRIVILEGE_ASSERTION_FAILED: %',v_table;
    end if;
  end loop;
  if (select count(*) from pg_policies
      where schemaname='public' and tablename in (
        'school_student_monthly_settlements',
        'school_student_settlement_adjustment_drafts',
        'school_student_settlement_adjustments',
        'school_student_settlement_carryovers'
      ) and cmd in ('INSERT','UPDATE','DELETE','ALL'))<>0 then
    raise exception 'TUITION_P0A_WRITE_POLICY_REMAINS';
  end if;
  if (select count(*) from pg_trigger t
      where not t.tgisinternal and t.tgname in (
        'school_tuition_consumed_settlement_immutable',
        'school_tuition_consumed_draft_immutable',
        'school_tuition_consumed_adjustment_immutable',
        'school_tuition_consumed_carryover_immutable'
      ))<>4 then
    raise exception 'TUITION_P0A_TRIGGER_INVENTORY_FAILED';
  end if;
end
$assertions$;

rollback;
