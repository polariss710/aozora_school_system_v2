\set ON_ERROR_STOP on
\pset pager off
begin read only;
select p.oid::regprocedure signature,p.prosecdef,
  pg_get_userbyid(p.proowner) owner,
  p.proconfig,md5(pg_get_functiondef(p.oid)) definition_md5,
  coalesce(array_to_string(p.proacl,','),'') acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_get_student_monthly_settlement_preview',
  'school_set_student_monthly_settlement_draft_adjustment',
  'school_lock_student_monthly_settlement',
  'school_unlock_student_monthly_settlement',
  'school_relock_student_monthly_settlement',
  'school_apply_student_monthly_settlement_adjustment',
  'school_tuition_p0b2_resolve_adjustment',
  'school_tuition_p0b2_guard_draft_row',
  'school_tuition_p0b2_guard_posted_adjustment',
  'school_tuition_p0b2_guard_settlement_resolution'
) order by 1;

select c.relname,c.relrowsecurity,
  has_table_privilege('anon',c.oid,'SELECT') anon_select,
  has_table_privilege('anon',c.oid,'INSERT,UPDATE,DELETE') anon_write,
  has_table_privilege('authenticated',c.oid,'SELECT') authenticated_select,
  has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') authenticated_write,
  has_table_privilege('service_role',c.oid,'SELECT') service_select,
  has_table_privilege('service_role',c.oid,'INSERT,UPDATE,DELETE') service_write
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in (
  'school_student_monthly_settlements',
  'school_student_settlement_adjustment_drafts',
  'school_student_settlement_adjustments',
  'school_student_settlement_carryovers'
) order by c.relname;

select c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) definition
from pg_trigger t join pg_class c on c.oid=t.tgrelid
where not t.tgisinternal and (
  t.tgname like 'school_tuition_p0a_%'
  or t.tgname like 'school_tuition_p0b2_%'
) order by c.relname,t.tgname;

select conrelid::regclass relation,conname,convalidated,
  pg_get_constraintdef(oid) definition
from pg_constraint
where conname in (
  'school_student_settlement_adjustment_drafts_mode_chk',
  'school_student_settlement_adjustments_mode_chk'
) order by 1,2;

select adjustment_source,status,count(*)
from public.school_student_settlement_adjustment_drafts
group by adjustment_source,status
union all
select adjustment_source,status,count(*)
from public.school_student_settlement_adjustments
group by adjustment_source,status
order by 1,2;
rollback;
