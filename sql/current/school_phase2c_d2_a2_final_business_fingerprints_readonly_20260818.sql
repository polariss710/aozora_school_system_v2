-- Phase 2C-D2-A2 final School business-data evidence. SELECT only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash from (
  select 1 n,'lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'clearances',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_clearances x
  union all select 5,'clearance_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_clearance_details x
  union all select 6,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 7,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 8,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 9,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 10,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 11,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 12,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 13,'package_lots',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_package_credit_lots x
  union all select 14,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
  union all select 15,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
) evidence order by n;

select count(*) package_lot_count,
  coalesce(sum(initial_minutes),0) initial_minutes,
  coalesce(sum(consumed_minutes),0) consumed_minutes,
  coalesce(sum(remaining_minutes),0) remaining_minutes
from public.school_student_package_credit_lots;

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;

select count(*) open_related_transactions
from pg_stat_activity activity
where activity.datname=current_database() and activity.pid<>pg_backend_pid()
  and activity.xact_start is not null and activity.state<>'idle'
  and (activity.query ilike '%school_lesson_clearances%'
    or activity.query ilike '%school_lesson_clearance_details%');

rollback;
