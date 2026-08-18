-- Phase 2C-D2-A2 production preflight. Catalog and business facts are read only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $preflight$
begin
  if to_regprocedure(
      'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'
    ) is not null then
    raise exception 'PHASE2C_D2_A2_PREFLIGHT_READER_V3_PRESENT';
  end if;
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure
    ))<>'94dcc95f7c64325e77ea5fa326dc5d05' then
    raise exception 'PHASE2C_D2_A2_PREFLIGHT_READER_V2_DRIFT';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_D2_A2_PREFLIGHT_CLEARANCE_NOT_EMPTY';
  end if;
end
$preflight$;

select count(*) pending_count,
  coalesce(sum(public.school_get_lesson_clearance_pending_remaining_minutes(
    lesson.id)),0) pending_minutes
from public.school_lesson_records lesson
where lesson.app_type='school'
  and lesson.lesson_type='planned'
  and lesson.status='pending_makeup'
  and lesson.voided_at is null
  and not public.school_is_active_package_credit_origin(lesson.id)
  and not exists(
    select 1
    from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=lesson.id
  )
  and public.school_get_lesson_clearance_pending_remaining_minutes(lesson.id)>0;

select planned.id,planned.lesson_date,
  (planned.lesson_date-(extract(isodow from planned.lesson_date)::integer-1))::date
    natural_week_monday,
  actual_row.id origin_partial_actual_id,actual_row.lesson_date origin_partial_actual_date,
  actual_row.status origin_status,actual_row.actual_minutes,
  md5(to_jsonb(planned)::text) planned_row_md5,
  md5(to_jsonb(actual_row)::text) actual_row_md5
from public.school_lesson_records planned
join public.school_lesson_records actual_row
  on actual_row.planned_lesson_id=planned.id
where planned.id='8870f57f-bca5-4114-90db-ee592cca2f45'
  and actual_row.id='2da1ec9a-6f19-49af-a9bd-48984a255aa9';

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
rollback;
