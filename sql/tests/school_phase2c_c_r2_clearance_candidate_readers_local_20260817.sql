-- Phase 2C-C-R2 local reader contract. All test changes are in the disposable DB.
\set ON_ERROR_STOP on
\pset pager off
begin;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);

create temporary table phase2c_c_r2_payloads(
  payload_name text primary key,payload jsonb not null
) on commit drop;
insert into phase2c_c_r2_payloads values
 ('pending',public.school_list_lesson_clearance_pending_balances_v2(null,true)),
 ('overage',public.school_list_lesson_clearance_available_overages_v2(null,true)),
 ('package',public.school_list_student_package_credit_lots_v2(null)),
 ('cross_month',public.school_list_cross_month_makeup_projection_v2(null,null)),
 ('summary',public.school_get_lesson_clearance_dashboard_summary_v1(null));

do $assertions$
declare
  v_pending jsonb;
  v_overage jsonb;
  v_package jsonb;
  v_cross jsonb;
  v_summary jsonb;
  v_row jsonb;
  v_passed integer:=0;
begin
  select payload into strict v_pending from phase2c_c_r2_payloads
    where payload_name='pending';
  select payload into strict v_overage from phase2c_c_r2_payloads
    where payload_name='overage';
  select payload into strict v_package from phase2c_c_r2_payloads
    where payload_name='package';
  select payload into strict v_cross from phase2c_c_r2_payloads
    where payload_name='cross_month';
  select payload into strict v_summary from phase2c_c_r2_payloads
    where payload_name='summary';
  if v_pending->>'contract_version'<>'lesson_clearance_pending_balances_v2'
     or v_pending->>'actor_role'<>'admin' then
    raise exception 'R2_PENDING_CONTRACT_INVALID'; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='30000000-0000-4000-8000-000000000001';
  if (v_row->>'initial_credit_minutes')::int<>120
     or (v_row->>'makeup_consumed_minutes')::int<>0
     or (v_row->>'clearance_allocated_minutes')::int<>30
     or (v_row->>'clearance_reversed_minutes')::int<>15
     or (v_row->>'remaining_minutes')::int<>105
     or not (v_row->>'balance_matches_writer_helper')::boolean then
    raise exception 'R2_PENDING_DECOMPOSITION_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='30000000-0000-4000-8000-000000000008';
  if (v_row->>'makeup_consumed_minutes')::int<>30
     or (v_row->>'remaining_minutes')::int<>90 then
    raise exception 'R2_PENDING_MAKEUP_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='30000000-0000-4000-8000-000000000002';
  if not (v_row->>'active_claimed')::boolean
     or (v_row->>'active_claimed_minutes')::int<>120
     or (v_row->>'currently_allocatable_minutes')::int<>0
     or v_row->>'candidate_blocker_code'<>'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED' then
    raise exception 'R2_PENDING_CLAIM_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  if exists(select 1 from jsonb_array_elements(v_pending->'items') item
    where item->>'pending_source_planned_id'='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9') then
    raise exception 'R2_P002_LEAKED_TO_PENDING'; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='30000000-0000-4000-8000-000000000006';
  if not (v_row->>'is_locked')::boolean
     or v_row->>'lock_reason_code'<>'PHYSICAL_STUDENT_SETTLEMENT_LOCKED'
     or not (v_row->>'requires_admin')::boolean then
    raise exception 'R2_PENDING_LOCK_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_pending->'items') item
  where item->>'pending_source_planned_id'='30000000-0000-4000-8000-000000000099';
  if v_row->>'teacher_display_name' is not null
     or v_row->>'teacher_name_evidence_status'<>'unavailable'
     or v_row->>'subject_name_evidence_status'<>'unavailable' then
    raise exception 'R2_MISSING_MASTER_EVIDENCE_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  if exists(select 1 from jsonb_array_elements(v_pending->'items') item
    group by item->>'student_id',item->>'business_entity_id',item->>'fifo_rank'
    having count(*)>1) then raise exception 'R2_FIFO_RANK_NOT_STABLE'; end if;
  v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_overage->'items') item
  where item->>'overtime_source_actual_id'='40000000-0000-4000-8000-000000000101';
  if (v_row->>'frozen_overtime_minutes')::int<>120
     or (v_row->>'clearance_allocated_minutes')::int<>30
     or (v_row->>'clearance_reversed_minutes')::int<>15
     or (v_row->>'available_minutes')::int<>105
     or not (v_row->>'balance_matches_writer_helper')::boolean then
    raise exception 'R2_OVERAGE_DECOMPOSITION_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_overage->'items') item
  where item->>'overtime_source_actual_id'='40000000-0000-4000-8000-000000000102';
  if not (v_row->>'active_claimed')::boolean
     or (v_row->>'active_claimed_minutes')::int<>60
     or (v_row->>'currently_allocatable_minutes')::int<>0 then
    raise exception 'R2_OVERAGE_CLAIM_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_package->'items') item
  where item->>'package_lot_id'='2a000000-0000-4000-8000-202608170002';
  if v_row->>'package_business_type'<>'package_credit'
     or (v_row->>'initial_minutes')::int<>1200
     or (v_row->>'consumed_minutes')::int<>0
     or (v_row->>'remaining_minutes')::int<>1200
     or (v_row->>'can_consume')::boolean or (v_row->>'can_reserve')::boolean
     or not (v_row->>'read_only')::boolean then
    raise exception 'R2_PACKAGE_CONTRACT_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  if jsonb_array_length(v_cross->'items')<>1
     or (v_cross->'summary'->>'distinct_actual_count')::int<>1 then
    raise exception 'R2_CROSS_MONTH_IDENTITY_INVALID:%',v_cross; end if;
  v_row:=v_cross->'items'->0;
  if v_row->>'actual_lesson_id'<>'40000000-0000-4000-8000-000000000120'
     or v_row->>'source_month'<>'2026-01' or v_row->>'actual_month'<>'2026-02'
     or v_row->>'source_teacher_id'=v_row->>'actual_teacher_id'
     or v_row->>'source_subject_id'=v_row->>'actual_subject_id'
     or v_row->>'source_view_lesson_id'<>'30000000-0000-4000-8000-000000000020'
     or v_row->>'actual_view_lesson_id'<>'40000000-0000-4000-8000-000000000120' then
    raise exception 'R2_CROSS_MONTH_FIELDS_INVALID:%',v_row; end if; v_passed:=v_passed+1;

  if (v_summary->>'package_remaining_minutes')::int<>1200
     or (v_summary->>'history_count')::int<>2
     or (v_summary->>'pending_remaining_minutes')::int
        <(v_summary->>'pending_currently_allocatable_minutes')::int
     or (v_summary->>'available_overtime_minutes')::int
        <(v_summary->>'overage_currently_allocatable_minutes')::int then
    raise exception 'R2_DASHBOARD_SUMMARY_INVALID:%',v_summary; end if; v_passed:=v_passed+1;

  if v_passed<>13 then raise exception 'R2_ASSERTION_COUNT_INVALID:%',v_passed; end if;
  raise notice 'Phase2C-C-R2 local passed_assertions=%',v_passed;
end
$assertions$;

select 'PHASE2C_C_R2_LOCAL_PASS passed_assertions=13' result;
rollback;
