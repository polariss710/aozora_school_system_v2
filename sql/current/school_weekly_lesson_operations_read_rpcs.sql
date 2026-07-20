-- school_weekly_lesson_operations_read_rpcs.sql
-- Purpose: DB-authoritative, read-only student lesson-credit and weekly
--          registration dashboard data. No business rows are written.

create or replace function public.school_list_student_lesson_credit_balances(
  p_student_id uuid default null
)
returns table (
  student_id uuid,
  business_entity_id uuid,
  open_source_count bigint,
  open_credit_hours numeric,
  oldest_credit_date date
)
language sql
stable
set search_path = public
as $$
  with credit_sources as (
    select
      p.id,
      p.student_id,
      p.business_entity_id,
      p.lesson_date,
      greatest(
        coalesce(p.duration_hours, 0) - coalesce(sum(a.duration_hours) filter (
          where a.lesson_type = 'actual'
            and a.status in ('completed', 'makeup_completed')
        ), 0),
        0
      )::numeric as remaining_hours
    from public.school_lesson_records p
    left join public.school_lesson_records a
      on a.planned_lesson_id = p.id
     and a.app_type = 'school'
    where p.app_type = 'school'
      and p.lesson_type = 'planned'
      and p.status = 'pending_makeup'
      and p.voided_at is null
      and (p_student_id is null or p.student_id = p_student_id)
    group by p.id, p.student_id, p.business_entity_id, p.lesson_date, p.duration_hours
  )
  select
    c.student_id,
    c.business_entity_id,
    count(*) filter (where c.remaining_hours > 0)::bigint as open_source_count,
    coalesce(sum(c.remaining_hours) filter (where c.remaining_hours > 0), 0)::numeric as open_credit_hours,
    min(c.lesson_date) filter (where c.remaining_hours > 0) as oldest_credit_date
  from credit_sources c
  where c.student_id is not null
  group by c.student_id, c.business_entity_id;
$$;

comment on function public.school_list_student_lesson_credit_balances(uuid) is
  'Returns open student lesson-credit balance from pending_makeup planned sources. Completed and makeup_completed linked actual hours consume credit; cancelled actuals do not. Historical over-fulfilled sources are clipped at zero and not repaired.';

create or replace function public.school_get_weekly_lesson_operations(
  p_week_start date
)
returns table (
  student_id uuid,
  business_entity_id uuid,
  weekly_planned_count bigint,
  weekly_planned_hours numeric,
  weekly_registered_count bigint,
  weekly_completed_hours numeric,
  weekly_cancelled_count bigint,
  overdue_unregistered_count bigint,
  upcoming_unregistered_count bigint,
  open_credit_source_count bigint,
  open_credit_hours numeric,
  oldest_credit_date date
)
language sql
stable
set search_path = public
as $$
  with bounds as (
    select p_week_start as week_start, (p_week_start + 7) as week_end,
      timezone('Asia/Tokyo', now())::date as today
    where p_week_start is not null
  ),
  active_students as (
    select s.id, s.business_entity_id
    from public.school_students s
    where s.app_type = 'school'
      and coalesce(s.status, 'active') = 'active'
  ),
  weekly_sources as (
    select p.id, p.student_id, p.business_entity_id, p.lesson_date,
      coalesce(p.duration_hours, 0)::numeric as duration_hours
    from public.school_lesson_records p
    join bounds b on p.lesson_date >= b.week_start and p.lesson_date < b.week_end
    where p.app_type = 'school'
      and p.lesson_type = 'planned'
      and p.status in ('planned', 'pending_makeup', 'makeup_completed')
      and p.voided_at is null
  ),
  linked_actuals as (
    select a.planned_lesson_id,
      count(*)::bigint as registered_count,
      count(*) filter (where a.status = 'cancelled')::bigint as cancelled_count,
      coalesce(sum(a.duration_hours) filter (
        where a.status in ('completed', 'makeup_completed')
      ), 0)::numeric as completed_hours
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id is not null
    group by a.planned_lesson_id
  ),
  weekly_summary as (
    select
      w.student_id,
      w.business_entity_id,
      count(*)::bigint as planned_count,
      coalesce(sum(w.duration_hours), 0)::numeric as planned_hours,
      coalesce(sum(a.registered_count), 0)::bigint as registered_count,
      coalesce(sum(a.completed_hours), 0)::numeric as completed_hours,
      coalesce(sum(a.cancelled_count), 0)::bigint as cancelled_count,
      count(*) filter (where coalesce(a.registered_count, 0) = 0 and w.lesson_date < b.today)::bigint as overdue_unregistered_count,
      count(*) filter (where coalesce(a.registered_count, 0) = 0 and w.lesson_date >= b.today)::bigint as upcoming_unregistered_count
    from weekly_sources w
    cross join bounds b
    left join linked_actuals a on a.planned_lesson_id = w.id
    group by w.student_id, w.business_entity_id
  ),
  credits as (
    select * from public.school_list_student_lesson_credit_balances(null)
  )
  select
    s.id as student_id,
    s.business_entity_id,
    coalesce(w.planned_count, 0)::bigint,
    coalesce(w.planned_hours, 0)::numeric,
    coalesce(w.registered_count, 0)::bigint,
    coalesce(w.completed_hours, 0)::numeric,
    coalesce(w.cancelled_count, 0)::bigint,
    coalesce(w.overdue_unregistered_count, 0)::bigint,
    coalesce(w.upcoming_unregistered_count, 0)::bigint,
    coalesce(c.open_source_count, 0)::bigint,
    coalesce(c.open_credit_hours, 0)::numeric,
    c.oldest_credit_date
  from active_students s
  left join weekly_summary w on w.student_id = s.id
  left join credits c on c.student_id = s.id
  order by s.id;
$$;

comment on function public.school_get_weekly_lesson_operations(date) is
  'Returns active-student weekly planned/registration operations and all open lesson-credit balances for the Monday-starting week. All counts and hours are DB-derived; this function writes no business rows.';

revoke all on function public.school_list_student_lesson_credit_balances(uuid) from public;
grant execute on function public.school_list_student_lesson_credit_balances(uuid) to anon, authenticated, service_role;
revoke all on function public.school_get_weekly_lesson_operations(date) from public;
grant execute on function public.school_get_weekly_lesson_operations(date) to anon, authenticated, service_role;
