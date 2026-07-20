-- school_lesson_credit_summary_read_rpc.sql
-- Purpose: DB-authoritative aggregate open lesson-credit summary for the
-- lesson-management top cards. No lesson or financial business rows are written.

create or replace function public.school_get_lesson_credit_summary(
  p_student_id uuid default null,
  p_business_entity_id uuid default null
)
returns table (
  open_source_count bigint,
  open_credit_hours numeric
)
language sql
stable
set search_path = public
as $$
  select
    coalesce(sum(b.open_source_count), 0)::bigint as open_source_count,
    coalesce(sum(b.open_credit_hours), 0)::numeric as open_credit_hours
  from public.school_list_student_lesson_credit_balances(p_student_id) b
  where p_business_entity_id is null
    or b.business_entity_id is not distinct from p_business_entity_id;
$$;

comment on function public.school_get_lesson_credit_summary(uuid, uuid) is
  'Returns total open lesson-credit source count and hours from all pending_makeup planned sources. Optional student/business-entity filters only narrow ownership; month, teacher and subject never redefine the balance.';

revoke all on function public.school_get_lesson_credit_summary(uuid, uuid) from public;
grant execute on function public.school_get_lesson_credit_summary(uuid, uuid) to anon, authenticated, service_role;
