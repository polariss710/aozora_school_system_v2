-- Phase 2C-C-R1 production read-RPC acceptance. No writer and no reservation.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

select membership.user_id actor_user_id
from public.school_app_memberships membership
where membership.is_active and membership.role='admin'
order by membership.created_at,membership.user_id
limit 1
\gset r1_actor_

with pending as (
  select lesson.id,lesson.student_id,lesson.business_entity_id,lesson.unit_price,
    public.school_get_lesson_clearance_pending_remaining_minutes(lesson.id) remaining_minutes
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='planned'
    and lesson.status='pending_makeup' and lesson.voided_at is null
    and not public.school_is_active_package_credit_origin(lesson.id)
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
        and claim.source_planned_lesson_id=lesson.id)
), overtime as (
  select lesson.id,lesson.student_id,lesson.business_entity_id,lesson.unit_price,
    public.school_get_lesson_clearance_overtime_remaining_minutes(lesson.id) remaining_minutes
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='actual'
    and lesson.status='completed' and lesson.is_billable is true and lesson.voided_at is null
    and lesson.student_duration_overage_policy_version='student_duration_overage_v1'
    and lesson.student_duration_overage_source='ordinary_actual_rpc'
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=lesson.id)
)
select pending.id pending_id,overtime.id overtime_id,
  least(pending.remaining_minutes,overtime.remaining_minutes,15) allocated_minutes
from pending join overtime
  on overtime.student_id=pending.student_id
 and overtime.business_entity_id=pending.business_entity_id
 and overtime.unit_price=pending.unit_price
where pending.remaining_minutes>=15 and overtime.remaining_minutes>=15
order by pending.id,overtime.id
limit 1
\gset r1_pair_

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',:'r1_actor_actor_user_id','role','authenticated')::text,
  true
);

select public.school_preview_lesson_clearance_v2(
  '2c1a0000-0000-4000-8000-202608170001',
  'overtime_offset',:'r1_pair_pending_id',:'r1_pair_overtime_id',
  :'r1_pair_allocated_minutes',current_date,null,null,
  'Phase 2C-C-R1 production read-only acceptance',null
) preview_payload
\gset r1_preview_

select public.school_list_lesson_clearance_history_v2(null) history_payload
\gset r1_history_

do $reversal_not_found$
declare v_payload jsonb;
begin
  begin
    v_payload:=public.school_preview_lesson_clearance_reversal_v1(
      '2c1a0000-0000-4000-8000-202608170002',
      '2c1a0000-0000-4000-8000-202608170003',current_date
    );
    raise exception 'PHASE2C_C_R1_REVERSAL_NOT_FOUND_EXPECTED';
  exception when others then
    if sqlerrm not like '%LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID%' then
      raise;
    end if;
  end;
end
$reversal_not_found$;

reset role;

select 1 / case when
  :'r1_preview_preview_payload'::jsonb->>'request_identity'
    ='2c1a0000-0000-4000-8000-202608170001'
  and not (:'r1_preview_preview_payload'::jsonb->>'reservation_created')::boolean
  and (:'r1_preview_preview_payload'::jsonb->>'writer_revalidation_required')::boolean
  and :'r1_preview_preview_payload'::jsonb ? 'pending_source'
  and :'r1_preview_preview_payload'::jsonb ? 'overtime_source'
  and :'r1_preview_preview_payload'::jsonb ? 'comparison'
  and :'r1_preview_preview_payload'::jsonb ? 'financial'
  and :'r1_preview_preview_payload'::jsonb ? 'authorization'
  then 1 else 0 end preview_contract_assertion;
select 1 / case when :'r1_history_history_payload'::jsonb='[]'::jsonb
  then 1 else 0 end empty_history_assertion;
select 1 / case when (select count(*) from public.school_lesson_clearances)=0
  and (select count(*) from public.school_lesson_clearance_details)=0
  then 1 else 0 end reader_zero_write_assertion;

select jsonb_pretty(:'r1_preview_preview_payload'::jsonb) preview_payload;
select jsonb_pretty(:'r1_history_history_payload'::jsonb) history_payload;
select 'LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID' reversal_preview_blocker;

rollback;
