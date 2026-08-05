-- Read-only proof after Session A commit and Session B rejection.
-- Supply the exact Session A event UUID via psql -v synthetic_event_id=...
\set ON_ERROR_STOP on
\pset pager off
\if :{?synthetic_event_id}
\else
  \echo 'synthetic_event_id is required'
  \quit 3
\endif

begin read only;
select e.id,e.student_id,e.effective_month,e.status,e.reason,e.row_version,
       e.created_by_user_id,e.created_by_membership_id,e.created_at,
       e.voided_at,e.replacement_event_id
from public.school_student_status_events e
where e.student_id='a0520000-0000-4000-8000-000000000100'
order by e.created_at,e.id;

select count(*) total_event_count,
       count(*) filter(where voided_at is null) active_event_count,
       count(*) filter(where id=:'synthetic_event_id'::uuid) exact_event_count,
       count(*) filter(where reason='codex-test synthetic monthly status concurrency session B') session_b_event_count,
       1/case when count(*)=1
                    and count(*) filter(where voided_at is null)=1
                    and count(*) filter(where id=:'synthetic_event_id'::uuid)=1
                    and count(*) filter(where reason='codex-test synthetic monthly status concurrency session B')=0
              then 1 else 0 end one_success_no_half_write
from public.school_student_status_events
where student_id='a0520000-0000-4000-8000-000000000100';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);
select * from public.school_resolve_student_status_at_month_v1(
  'a0520000-0000-4000-8000-000000000100','2026-07-01'
);
reset role;

select 'lesson' object,count(*) refs from public.school_lesson_records where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'settlement',count(*) from public.school_student_monthly_settlements where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'income',count(*) from public.school_income_records where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'expense',count(*) from public.school_expense_records where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'tuition_bill',count(*) from public.school_student_tuition_bills where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'wage_detail',count(*) from public.school_teacher_wage_lock_details where student_id='a0520000-0000-4000-8000-000000000100'
union all select 'wage_rule',count(*) from public.school_teacher_wage_rules where student_id='a0520000-0000-4000-8000-000000000100'
order by object;

select i.indexname,i.indexdef
from pg_indexes i
where i.schemaname='public' and i.tablename='school_student_status_events'
  and i.indexname='school_student_status_events_active_month_uniq';
rollback;

select 'STUDENT_STATUS_CONCURRENCY_ONE_SUCCESS_ONE_REJECT_VERIFY_PASS' result;
