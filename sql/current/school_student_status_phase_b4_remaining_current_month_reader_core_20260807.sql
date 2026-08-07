create or replace function public.school_list_current_student_month_candidates_v1(
  p_include_inactive boolean default false,
  p_selected_student_id uuid default null
)
returns table (
  target_month date,
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  business_entity_id uuid,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_legacy_fallback boolean,
  is_active boolean,
  is_selected_override boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select current_scope.target_month,
         candidate.student_id,
         candidate.student_code,
         candidate.name,
         candidate.display_name,
         candidate.business_entity_id,
         candidate.resolved_status,
         candidate.source_event_id,
         candidate.source_effective_month,
         candidate.is_legacy_fallback,
         candidate.is_active,
         candidate.is_selected_override
  from (
    select date_trunc('month', statement_timestamp() at time zone 'Asia/Tokyo')::date target_month
  ) current_scope
  cross join lateral public.school_list_student_month_candidates_v1(
    current_scope.target_month,
    coalesce(p_include_inactive, false),
    p_selected_student_id
  ) candidate;
$function$;

revoke all on function public.school_list_current_student_month_candidates_v1(boolean,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_list_current_student_month_candidates_v1(boolean,uuid)
  to authenticated;

comment on function public.school_list_current_student_month_candidates_v1(boolean,uuid) is
  'Read-only authenticated student candidate wrapper. DB Tokyo current month is authoritative; delegates status resolution and selected override to Phase A.';
