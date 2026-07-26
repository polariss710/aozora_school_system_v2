-- school_part_time_work_progress_read_rpc.sql
-- Purpose: make external part-time-work lesson progress DB-authoritative.
-- The displayed lesson count and cumulative hours are calculated dynamically
-- within each record kind and course series:
-- workplace_name + subject_name + class_description.
-- Existing stored fields and locked settlement snapshots are not backfilled.

create or replace function public.school_list_part_time_work_lessons(
  p_year_month text default null,
  p_workplace_name text default null,
  p_record_kind text default null
)
returns table (
  id uuid,
  record_kind text,
  planned_lesson_id uuid,
  generated_actual_id uuid,
  work_date date,
  start_time time,
  end_time time,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  planned_hours numeric,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text,
  settlement_id uuid,
  settlement_status text,
  income_request_id uuid,
  income_request_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_lessons as (
    select
      l.*,
      row_number() over (
        partition by
          l.record_kind,
          l.workplace_name,
          l.subject_name,
          coalesce(l.class_description, '')
        order by l.work_date, l.start_time nulls last, l.created_at, l.id
      )::integer as calculated_lesson_count,
      sum(
        case
          when l.record_kind = 'actual' then l.actual_hours
          else l.planned_hours
        end
      ) over (
        partition by
          l.record_kind,
          l.workplace_name,
          l.subject_name,
          coalesce(l.class_description, '')
        order by l.work_date, l.start_time nulls last, l.created_at, l.id
        rows between unbounded preceding and current row
      )::numeric as calculated_cumulative_hours
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
  )
  select
    l.id,
    l.record_kind,
    l.planned_lesson_id,
    ga.id as generated_actual_id,
    l.work_date,
    l.start_time,
    l.end_time,
    l.year_month,
    l.workplace_name,
    l.teacher_name,
    l.subject_name,
    l.class_description,
    l.planned_hours,
    l.actual_hours,
    l.calculated_lesson_count as lesson_count,
    l.calculated_cumulative_hours as cumulative_hours,
    l.hourly_rate_jpy,
    l.lesson_wage_jpy,
    l.transportation_fee_jpy,
    l.memo,
    s.id as settlement_id,
    s.status as settlement_status,
    s.income_request_id,
    ir.status as income_request_status,
    l.created_at,
    l.updated_at
  from active_lessons l
  left join public.school_part_time_work_lessons ga
    on ga.planned_lesson_id = l.id
    and ga.record_kind = 'actual'
    and ga.deleted_at is null
  left join public.school_part_time_work_monthly_settlement_details d
    on d.actual_lesson_id = l.id
    and l.record_kind = 'actual'
  left join public.school_part_time_work_monthly_settlements s
    on s.id = d.settlement_id
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  where (nullif(trim(coalesce(p_year_month, '')), '') is null or l.year_month = trim(p_year_month))
    and (nullif(trim(coalesce(p_workplace_name, '')), '') is null or l.workplace_name = trim(p_workplace_name))
    and (nullif(trim(coalesce(p_record_kind, '')), '') is null or l.record_kind = lower(trim(p_record_kind)))
  order by l.work_date, l.start_time nulls last, l.created_at, l.id;
$$;

comment on function public.school_list_part_time_work_lessons(text, text, text) is
  'Lists active external part-time work lessons. lesson_count and cumulative_hours are dynamically calculated by record kind plus workplace, subject, and class description; stored legacy values are not used for this read model.';

revoke all on function public.school_list_part_time_work_lessons(text, text, text) from public, anon;
grant execute on function public.school_list_part_time_work_lessons(text, text, text) to authenticated;
