-- Read-only shadow matrix under the real active-admin membership.
\set ON_ERROR_STOP on
\pset pager off

begin read only;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

select target_month,resolved_status,count(*)
from (
  select d.target_month,r.resolved_status
  from (values ('2026-06-01'::date),('2026-07-01'::date),('2026-08-01'::date),
               (date_trunc('month',current_timestamp at time zone 'Asia/Tokyo'))::date) d(target_month)
  cross join lateral public.school_list_student_month_candidates_v1(d.target_month,true,null) r
) q group by target_month,resolved_status order by target_month,resolved_status;

select target_month,include_inactive,count(*) candidate_count
from (values ('2026-06-01'::date),('2026-07-01'::date),('2026-08-01'::date)) d(target_month)
cross join (values(false),(true)) i(include_inactive)
cross join lateral public.school_list_student_month_candidates_v1(d.target_month,i.include_inactive,null) r
group by target_month,include_inactive order by target_month,include_inactive;

select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-06-01');
select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-07-01');
select * from public.school_resolve_student_status_at_month_v1('cff85c52-6acc-4b0f-8c92-3db280a5dd77','2026-08-01');

select count(*) selected_override_count
from public.school_list_student_month_candidates_v1('2026-07-01',false,'cff85c52-6acc-4b0f-8c92-3db280a5dd77')
where student_id='cff85c52-6acc-4b0f-8c92-3db280a5dd77' and is_selected_override;

select p_target_month,count(*) filter(where is_diff) diff_count
from (values ('2026-06-01'::date),
             ((date_trunc('month',current_timestamp at time zone 'Asia/Tokyo'))::date)) d(p_target_month)
cross join lateral public.school_list_student_status_shadow_v1(d.p_target_month)
group by p_target_month order by p_target_month;

rollback;
select 'STUDENT_STATUS_PHASE_A_SHADOW_READ_ONLY_PASS' result;
