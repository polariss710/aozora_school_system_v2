-- P0-F/P0-E read-only income display contract. All four displayed amounts are
-- returned by DB authority; page JavaScript only formats them.
\set ON_ERROR_STOP on
\pset pager off

create or replace function public.school_get_tuition_income_forward_adjustment_display(
  p_income_ids uuid[]
)
returns table(
  income_id uuid,
  historical_carryover_cny numeric,
  forward_adjustment_cny numeric,
  net_carryover_impact_cny numeric,
  final_notice_amount_cny numeric
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select
    income.id,
    adjustment.source_historical_carryover_cny,
    adjustment.amount_cny,
    round(adjustment.source_historical_carryover_cny + adjustment.amount_cny, 2),
    (income.source_snapshot->>'billing_amount_cny')::numeric
  from public.school_income_records income
  join public.school_student_tuition_generation_revisions revision
    on revision.tuition_bill_id=income.source_id
  join public.school_student_tuition_generation_revision_adjustments adjustment
    on adjustment.target_revision_id=revision.id
  where income.id=any(coalesce(p_income_ids,array[]::uuid[]))
    and income.source_type='student_tuition_bill'
    and revision.lifecycle_status='active'
    and adjustment.adjustment_type='neutralize_historical_carryover_v1'
  order by income.id;
$function$;

revoke all on function public.school_get_tuition_income_forward_adjustment_display(uuid[])
  from public,anon;
grant execute on function public.school_get_tuition_income_forward_adjustment_display(uuid[])
  to authenticated,service_role;

comment on function public.school_get_tuition_income_forward_adjustment_display(uuid[]) is
  'Read-only P0-E income display authority. Returns historical carry, immutable forward adjustment, DB-computed net carry impact and frozen final notice amount.';

create or replace function public.school_get_planned_lesson_tuition_history_state(
  p_lesson_ids uuid[]
)
returns table(
  lesson_id uuid,
  tuition_revision_count integer,
  voided_tuition_revision_count integer,
  active_tuition_revision_count integer
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select
    lesson.id,
    count(distinct revision.id)::integer,
    count(distinct revision.id) filter(where revision.lifecycle_status='voided')::integer,
    count(distinct revision.id) filter(where revision.lifecycle_status='active')::integer
  from public.school_lesson_records lesson
  left join public.school_student_tuition_bill_lessons relation
    on relation.planned_lesson_id=lesson.id
  left join public.school_student_tuition_generation_revisions revision
    on revision.tuition_bill_id=relation.tuition_bill_id
  where lesson.id=any(coalesce(p_lesson_ids,array[]::uuid[]))
    and lesson.lesson_type='planned'
  group by lesson.id
  order by lesson.id;
$function$;

revoke all on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  from public,anon;
grant execute on function public.school_get_planned_lesson_tuition_history_state(uuid[])
  to authenticated,service_role;

comment on function public.school_get_planned_lesson_tuition_history_state(uuid[]) is
  'Read-only lesson-page routing facts. Any tuition revision history closes physical delete; voided history with no active revision exposes the P0-F controlled soft-void action.';
