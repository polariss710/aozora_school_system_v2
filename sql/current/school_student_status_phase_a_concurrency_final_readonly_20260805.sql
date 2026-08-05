-- Final read-only proof after exact synthetic cleanup.
\set ON_ERROR_STOP on
\pset pager off

begin read only;
select id,student_id,effective_month,status,reason,row_version,
       created_by_user_id,created_by_membership_id,created_at,
       voided_at,replacement_event_id,md5(to_jsonb(e)::text) row_md5
from public.school_student_status_events e
order by created_at,id;

select 'students' object,count(*) row_count,md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) row_hash from public.school_students t
union all select 'lessons',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_lesson_records t
union all select 'settlements',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_monthly_settlements t
union all select 'student_income',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t where student_id is not null
union all select 'tuition_bills',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_student_tuition_bills t
union all select 'wage_details',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_lock_details t
union all select 'wage_rules',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_teacher_wage_rules t
union all select 'all_income',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_income_records t
union all select 'expenses',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_expense_records t
union all select 'accounts',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_accounts t
union all select 'account_transactions',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.school_account_transactions t
order by object;

select count(*) storage_objects,
       count(*) filter(where e.id is null) storage_orphans
from storage.objects o
left join public.school_expense_records e
  on e.id::text=split_part(o.name,'/',3) and e.app_type='school'
where o.bucket_id='school-expense-files';

select feature_key,state from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select count(*) synthetic_student_count from public.school_students where id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_event_count from public.school_student_status_events where student_id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_membership_count from public.school_app_memberships where user_id='a0520000-0000-4000-8000-000000000100';
select count(*) synthetic_user_count from auth.users where id='a0520000-0000-4000-8000-000000000100';

select count(*) lingering_test_sessions
from pg_stat_activity
where pid<>pg_backend_pid()
  and (state='idle in transaction' or wait_event_type='Lock')
  and query like '%a0520000-0000-4000-8000-000000000100%';

select tgname,tgenabled from pg_trigger
where tgrelid='public.school_student_status_events'::regclass and not tgisinternal
order by tgname;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);
select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-06-01');
select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01');
select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-08-01');
rollback;

select 'STUDENT_STATUS_CONCURRENCY_FINAL_READ_ONLY_PASS' result;
