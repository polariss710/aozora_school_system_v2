-- school_lesson_void_dependent_read_rpcs.sql
-- Purpose: Update lesson-derived read RPCs to exclude soft-voided planned lessons.
-- Status: EXECUTED ON SUPABASE. Read-verified after execution.
-- Version: v2.63.0-lesson-planned-void-schema-rpc-20260609
--
-- Scope:
-- - Replace read-only summary functions that aggregate school_lesson_records.
-- - Exclude lesson_type = planned rows when voided_at is not null.
-- - Do not write business data.

create or replace function public.school_get_lesson_management_stats(
  p_year_month text,
  p_student_id uuid default null,
  p_teacher_id uuid default null,
  p_subject_id uuid default null,
  p_lesson_type text default null,
  p_status text default null,
  p_business_entity_id uuid default null
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
  with filtered as (
    select
      lesson.id,
      lesson.planned_lesson_id,
      lesson.lesson_type,
      lesson.status,
      coalesce(lesson.is_billable, false) as is_billable,
      coalesce(lesson.duration_hours, 0)::numeric as duration_hours,
      coalesce(lesson.lesson_fee,
        coalesce(lesson.unit_price, 0) * coalesce(lesson.duration_hours, 0),
        0
      )::numeric as fee_jpy
    from public.school_list_r1d_e_c_student_month_lessons(
      null,
      p_year_month
    ) resolved
    join public.school_lesson_records lesson on lesson.id = resolved.lesson_id
    where (p_student_id is null or lesson.student_id = p_student_id)
      and (p_teacher_id is null or lesson.teacher_id = p_teacher_id)
      and (p_subject_id is null or lesson.subject_id = p_subject_id)
      and (p_lesson_type is null or lesson.lesson_type = p_lesson_type)
      and (p_status is null or lesson.status = p_status)
      and (p_business_entity_id is null or lesson.business_entity_id = p_business_entity_id)
      and not (lesson.lesson_type = 'planned' and lesson.voided_at is not null)
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
  from filtered f;
$$;

comment on function public.school_get_lesson_management_stats(
  text,
  uuid,
  uuid,
  uuid,
  text,
  text,
  uuid
) is
  'Returns lesson management summary stats. Soft-voided planned lessons are excluded from planned totals and record_count.';

create or replace function public.school_get_student_monthly_settlement_summary(
  p_student_id uuid,
  p_year_month text
)
returns table (
  student_id uuid,
  year_month text,
  exchange_rate numeric,
  carryover_cny numeric,
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  planned_fee_cny numeric,
  planned_total_cny numeric,
  actual_fee_jpy numeric,
  actual_fee_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  final_due_cny numeric,
  locked_carryover_cny numeric
)
language sql
stable
as $$
  with student_base as (
    select
      s.id as student_id,
      coalesce(s.preset_exchange_rate, 0)::numeric as exchange_rate,
      coalesce(s.previous_balance_cny, 0)::numeric as fallback_carryover_cny
    from public.school_students s
    where s.id = p_student_id
  ),
  carryover as (
    select
      coalesce(
        (
          select c.amount_cny
          from public.school_student_settlement_carryovers c
          where c.student_id = p_student_id
            and c.to_year_month = p_year_month
            and coalesce(c.status, 'active') = 'active'
          order by c.updated_at desc nulls last, c.created_at desc nulls last
          limit 1
        ),
        (select fallback_carryover_cny from student_base),
        0
      )::numeric as carryover_cny
  ),
  lessons as (
    select
      l.id,
      l.planned_lesson_id,
      l.lesson_type,
      l.status,
      coalesce(l.is_billable, false) as is_billable,
      coalesce(l.duration_hours, 0)::numeric as duration_hours,
      coalesce(l.lesson_fee, coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)::numeric as fee_jpy
    from public.school_list_r1d_e_c_student_month_lessons(
      p_student_id,
      p_year_month
    ) resolved
    join public.school_lesson_records l on l.id = resolved.lesson_id
    where l.student_id = p_student_id
      and not (l.lesson_type = 'planned' and l.voided_at is not null)
  ),
  lesson_summary as (
    select
      coalesce(sum(f.duration_hours) filter (
        where f.lesson_type = 'planned'
      ), 0)::numeric as planned_hours,

      coalesce(sum(f.duration_hours) filter (
        where f.lesson_type = 'actual'
          and f.is_billable = true
          and f.status in ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric as actual_hours,

      coalesce(sum(f.fee_jpy) filter (
        where f.lesson_type = 'planned'
      ), 0)::numeric as planned_fee_jpy,

      coalesce(sum(f.fee_jpy) filter (
        where f.lesson_type = 'actual'
          and f.is_billable = true
          and f.status in ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric as actual_fee_jpy
    from lessons f
  ),
  income_summary as (
    select
      coalesce(sum(i.amount) filter (
        where coalesce(i.payment_currency, i.currency) = 'JPY'
      ), 0)::numeric as received_jpy,
      coalesce(sum(i.amount) filter (
        where coalesce(i.payment_currency, i.currency) = 'CNY'
      ), 0)::numeric as received_cny
    from public.school_income_records i
    where i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = p_year_month
      and i.income_category = 'tuition'
      and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ),
  locked as (
    select
      m.carryover_amount_cny
    from public.school_student_monthly_settlements m
    where m.student_id = p_student_id
      and m.year_month = p_year_month
      and m.settlement_status = 'locked'
    order by m.locked_at desc nulls last, m.updated_at desc nulls last, m.created_at desc nulls last
    limit 1
  ),
  calculated as (
    select
      sb.student_id,
      p_year_month as year_month,
      sb.exchange_rate,
      coalesce(c.carryover_cny, 0)::numeric as carryover_cny,
      coalesce(ls.planned_hours, 0)::numeric as planned_hours,
      coalesce(ls.actual_hours, 0)::numeric as actual_hours,
      coalesce(ls.planned_fee_jpy, 0)::numeric as planned_fee_jpy,
      (coalesce(ls.planned_fee_jpy, 0) * sb.exchange_rate)::numeric as planned_fee_cny,
      ((coalesce(ls.planned_fee_jpy, 0) * sb.exchange_rate) + coalesce(c.carryover_cny, 0))::numeric as planned_total_cny,
      coalesce(ls.actual_fee_jpy, 0)::numeric as actual_fee_jpy,
      (coalesce(ls.actual_fee_jpy, 0) * sb.exchange_rate)::numeric as actual_fee_cny,
      coalesce(inc.received_jpy, 0)::numeric as received_jpy,
      coalesce(inc.received_cny, 0)::numeric as received_cny,
      (coalesce(inc.received_cny, 0) + coalesce(inc.received_jpy, 0) * sb.exchange_rate)::numeric as received_equivalent_cny
    from student_base sb
    cross join carryover c
    cross join lesson_summary ls
    cross join income_summary inc
  )
  select
    calc.student_id,
    calc.year_month,
    calc.exchange_rate,
    calc.carryover_cny,
    calc.planned_hours,
    calc.actual_hours,
    calc.planned_fee_jpy,
    calc.planned_fee_cny,
    calc.planned_total_cny,
    calc.actual_fee_jpy,
    calc.actual_fee_cny,
    calc.received_jpy,
    calc.received_cny,
    calc.received_equivalent_cny,
    (calc.actual_fee_cny + calc.carryover_cny - calc.received_equivalent_cny)::numeric as final_due_cny,
    coalesce(
      (select l.carryover_amount_cny from locked l),
      (calc.actual_fee_cny + calc.carryover_cny - calc.received_equivalent_cny)
    )::numeric as locked_carryover_cny
  from calculated calc;
$$;

comment on function public.school_get_student_monthly_settlement_summary(uuid, text) is
  'Returns student monthly settlement summary. Soft-voided planned lessons are excluded from planned lesson totals.';
