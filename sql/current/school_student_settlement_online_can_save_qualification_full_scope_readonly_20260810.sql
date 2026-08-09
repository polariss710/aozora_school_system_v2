\set ON_ERROR_STOP on

-- Phase C-R1 production read-only drift scan. The scope set is the union of
-- every existing settlement-relevant fact; it deliberately adds no calendar
-- close/open policy.
begin transaction read only;
set local statement_timeout = '120s';

with scope_sources as (
  select student_id, coalesce(student_settlement_month, billing_month, year_month) year_month
  from public.school_lesson_records
  where student_id is not null
    and coalesce(student_settlement_month, billing_month, year_month) is not null
  union
  select student_id, coalesce(settlement_month, year_month)
  from public.school_income_records
  where student_id is not null and coalesce(settlement_month, year_month) is not null
  union select student_id, year_month from public.school_student_monthly_settlements
  union select student_id, year_month from public.school_student_settlement_adjustment_drafts
  union select student_id, year_month from public.school_student_settlement_source_treatment_drafts
  union select student_id, settlement_month
    from public.school_student_monthly_settlement_historical_completion_evidenc
  union select student_id, previous_settlement_month
    from public.school_student_tuition_bills where previous_settlement_month is not null
  union
  select student_id, to_char((billing_month::date - interval '1 month')::date, 'YYYY-MM')
  from public.school_student_tuition_generation_identities
), scopes as (
  select distinct source.student_id, source.year_month
  from scope_sources source
  join public.school_students student
    on student.id = source.student_id and student.app_type = 'school'
  where source.year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
), results as (
  select scope.student_id, scope.year_month, student.name,
    eligibility.payload->'effective_state'->>'effective_status' effective_status,
    coalesce((eligibility.payload->>'source_facts_available')::boolean, false)
      source_facts_available,
    coalesce((eligibility.payload->>'can_save')::boolean, false) can_save,
    coalesce(nullif(eligibility.payload->>'save_blocker_code', ''), 'NONE')
      save_blocker_code,
    coalesce((status.payload->>'can_lock')::boolean, false) can_lock
  from scopes scope
  join public.school_students student on student.id = scope.student_id
  cross join lateral public.school_get_student_settlement_online_save_eligibility_core(
    scope.student_id, scope.year_month
  ) eligibility(payload)
  cross join lateral public.school_get_student_monthly_settlement_online_status_core(
    scope.student_id, scope.year_month
  ) status(payload)
)
select year_month, name, student_id, effective_status, source_facts_available,
  can_save, save_blocker_code, can_lock
from results
order by year_month, name, student_id;

commit;
