-- school_open_lesson_credit_sources_read_rpc.sql
-- Purpose: return only genuinely open pending_makeup sources for the unified
-- makeup-entry dialog. Historical status residue is read-compatible but never
-- selectable when its DB-authoritative remaining hours are zero.

create or replace function public.school_list_open_lesson_credit_sources(
  p_from_month text,
  p_to_month text,
  p_target_month text
)
returns table (
  id uuid,
  lesson_date date,
  year_month text,
  student_id uuid,
  teacher_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  start_time text,
  end_time text,
  duration_hours numeric,
  lesson_content text,
  note text,
  lesson_count integer,
  unit_price numeric,
  lesson_delivery_mode text,
  lesson_venue text,
  remaining_hours numeric
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with args as (
    select
      nullif(trim(coalesce(p_from_month, '')), '') as from_month,
      nullif(trim(coalesce(p_to_month, '')), '') as to_month,
      nullif(trim(coalesce(p_target_month, '')), '') as target_month
  ),
  sources as (
    select
      p.id,
      p.lesson_date,
      resolved.authoritative_student_month as year_month,
      p.student_id,
      p.teacher_id,
      p.subject_id,
      p.business_entity_id,
      p.start_time,
      p.end_time,
      p.duration_hours,
      p.lesson_content,
      p.note,
      p.lesson_count,
      p.unit_price,
      p.lesson_delivery_mode,
      p.lesson_venue,
      greatest(
        coalesce(p.duration_hours, 0) - coalesce(sum(a.duration_hours) filter (
          where a.lesson_type = 'actual'
            and a.status in ('completed', 'makeup_completed')
        ), 0),
        0
      )::numeric as remaining_hours
    from public.school_lesson_records p
    cross join args x
    cross join lateral (
      select public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        as authoritative_student_month
    ) resolved
    left join public.school_lesson_records a
      on a.planned_lesson_id = p.id
     and a.app_type = 'school'
    where p.app_type = 'school'
      and p.lesson_type = 'planned'
      and p.status = 'pending_makeup'
      and p.voided_at is null
      and x.from_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and x.to_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and x.target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and x.from_month <= x.to_month
      and x.to_month <= x.target_month
      and resolved.authoritative_student_month >= x.from_month
      and resolved.authoritative_student_month <= x.to_month
      and resolved.authoritative_student_month <= x.target_month
    group by p.id, resolved.authoritative_student_month
  )
  select
    s.id,
    s.lesson_date,
    s.year_month,
    s.student_id,
    s.teacher_id,
    s.subject_id,
    s.business_entity_id,
    s.start_time,
    s.end_time,
    s.duration_hours,
    s.lesson_content,
    s.note,
    s.lesson_count,
    s.unit_price,
    s.lesson_delivery_mode,
    s.lesson_venue,
    s.remaining_hours
  from sources s
  where s.remaining_hours > 0
  order by s.year_month, s.lesson_date, s.lesson_count nulls last, s.start_time nulls last, s.id;
$$;

comment on function public.school_list_open_lesson_credit_sources(text, text, text) is
  'Returns only pending_makeup planned lesson sources with positive authoritative remaining hours for a target-month makeup dialog. Fully consumed and historical over-fulfilled sources are excluded without modifying historical rows.';

revoke all on function public.school_list_open_lesson_credit_sources(text, text, text) from public;
grant execute on function public.school_list_open_lesson_credit_sources(text, text, text) to anon, authenticated, service_role;
