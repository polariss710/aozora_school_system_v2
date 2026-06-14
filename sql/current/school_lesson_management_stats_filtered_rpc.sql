-- school_lesson_management_stats_filtered_rpc.sql
-- Purpose: Add DB-sourced lesson management stats matching lesson.html filters.
-- Status: EXECUTED ON SUPABASE. Read-verified after execution.
--
-- Scope:
-- - Read-only RPC for lesson management top statistics.
-- - Supports the same core filters used by lesson.html, including billable and keyword.
-- - Does not write business data.

create or replace function public.school_get_lesson_management_stats_filtered(
  p_year_month text,
  p_student_id uuid default null,
  p_teacher_id uuid default null,
  p_subject_id uuid default null,
  p_lesson_type text default null,
  p_status text default null,
  p_business_entity_id uuid default null,
  p_is_billable boolean default null,
  p_keyword text default null
)
returns table (
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  actual_fee_jpy numeric,
  completed_count bigint,
  cancelled_count bigint,
  pending_makeup_count bigint,
  record_count bigint
)
language sql
stable
as $$
  with normalized as (
    select
      nullif(trim(coalesce(p_keyword, '')), '') as keyword,
      nullif(trim(coalesce(p_status, '')), '') as status_filter,
      nullif(trim(coalesce(p_lesson_type, '')), '') as lesson_type_filter
  ),
  filtered as (
    select
      l.id,
      l.planned_lesson_id,
      l.lesson_type,
      l.status,
      coalesce(l.is_billable, false) as is_billable,
      coalesce(l.duration_hours, 0)::numeric as duration_hours,
      coalesce(l.lesson_fee, coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)::numeric as fee_jpy
    from public.school_lesson_records l
    left join public.school_students st on st.id = l.student_id
    left join public.school_teachers te on te.id = l.teacher_id
    left join public.school_subjects su on su.id = l.subject_id
    left join public.school_business_entities be on be.id = l.business_entity_id
    cross join normalized n
    where l.app_type = 'school'
      and (p_year_month is null or l.year_month = p_year_month)
      and (p_student_id is null or l.student_id = p_student_id)
      and (p_teacher_id is null or l.teacher_id = p_teacher_id)
      and (p_subject_id is null or l.subject_id = p_subject_id)
      and (n.lesson_type_filter is null or l.lesson_type = n.lesson_type_filter)
      and (p_business_entity_id is null or l.business_entity_id = p_business_entity_id)
      and (p_is_billable is null or coalesce(l.is_billable, false) = p_is_billable)
      and (
        (n.status_filter = 'voided' and l.lesson_type = 'planned' and l.voided_at is not null)
        or (
          coalesce(n.status_filter, '') <> 'voided'
          and not (l.lesson_type = 'planned' and l.voided_at is not null)
          and (n.status_filter is null or l.status = n.status_filter)
        )
      )
      and (
        n.keyword is null
        or lower(concat_ws(
          ' ',
          coalesce(st.display_name, st.name),
          coalesce(te.display_name, te.name),
          su.name,
          be.name,
          l.lesson_content,
          l.note,
          l.import_source
        )) like '%' || lower(n.keyword) || '%'
      )
  )
  select
    coalesce(sum(duration_hours) filter (where lesson_type = 'planned'), 0)::numeric as planned_hours,
    coalesce(sum(duration_hours) filter (
      where lesson_type = 'actual'
        and is_billable = true
        and status in ('completed', 'makeup', 'makeup_completed')
    ), 0)::numeric as actual_hours,
    coalesce(sum(fee_jpy) filter (where lesson_type = 'planned'), 0)::numeric as planned_fee_jpy,
    coalesce(sum(fee_jpy) filter (
      where lesson_type = 'actual'
        and is_billable = true
        and status in ('completed', 'makeup', 'makeup_completed')
    ), 0)::numeric as actual_fee_jpy,
    count(*) filter (
      where lesson_type = 'actual'
        and is_billable = true
        and status in ('completed', 'makeup', 'makeup_completed')
    )::bigint as completed_count,
    count(*) filter (where lesson_type = 'actual' and status = 'cancelled')::bigint as cancelled_count,
    count(*) filter (where lesson_type = 'planned' and status = 'pending_makeup')::bigint as pending_makeup_count,
    count(*)::bigint as record_count
  from filtered;
$$;

comment on function public.school_get_lesson_management_stats_filtered(text, uuid, uuid, uuid, text, text, uuid, boolean, text) is
  'Returns lesson management top statistics from DB using lesson.html filters. Soft-voided planned lessons are excluded unless p_status = voided. No business data writes.';
