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
