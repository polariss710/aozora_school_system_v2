-- Phase 2C-D2-A2 local operational display-date contract. Transaction rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;

insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,start_time,end_time,duration_hours,unit_price,lesson_fee,is_billable,
  year_month,student_settlement_month,created_at,updated_at
) values
 ('2d2a0000-0000-4000-8000-000000000101','planned','pending_makeup',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2026-08-10','13:00','15:00',2,9000,18000,true,'2026-08','2026-08',
  '2026-08-10 00:00+00','2026-08-14 00:00+00'),
 ('2d2a0000-0000-4000-8000-000000000102','planned','pending_makeup',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2026-08-06','13:00','15:00',2,9000,18000,true,'2026-08','2026-08',
  '2026-08-06 00:00+00','2026-08-06 00:00+00'),
 ('2d2a0000-0000-4000-8000-000000000103','planned','pending_makeup',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2026-08-17','13:00','15:00',2,9000,18000,true,'2026-08','2026-08',
  '2026-08-17 00:00+00','2026-08-17 00:00+00');

insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  planned_lesson_id,lesson_date,start_time,end_time,duration_hours,actual_minutes,
  unit_price,lesson_fee,is_billable,year_month,student_settlement_month,
  teacher_settlement_month,voided_at,created_at,updated_at
) values
 ('2d2a0000-0000-4000-8000-000000000201','actual','completed',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2d2a0000-0000-4000-8000-000000000101','2026-08-14','13:00','14:00',1,60,
  9000,9000,true,'2026-08','2026-08','2026-08',null,
  '2026-08-14 01:00+00','2026-08-14 01:00+00'),
 ('2d2a0000-0000-4000-8000-000000000202','actual','cancelled',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2d2a0000-0000-4000-8000-000000000102','2026-08-06','13:00','15:00',2,0,
  0,0,false,'2026-08','2026-08','2026-08',null,
  '2026-08-06 01:00+00','2026-08-06 01:00+00'),
 ('2d2a0000-0000-4000-8000-000000000203','actual','makeup_completed',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2d2a0000-0000-4000-8000-000000000102','2026-08-09','13:00','13:30',0.5,30,
  0,0,false,'2026-08','2026-08','2026-08',null,
  '2026-08-09 01:00+00','2026-08-09 01:00+00'),
 ('2d2a0000-0000-4000-8000-000000000204','actual','completed',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '2d2a0000-0000-4000-8000-000000000103','2026-08-20','13:00','14:00',1,60,
  9000,9000,true,'2026-08','2026-08','2026-08','2026-08-20 02:00+00',
  '2026-08-20 01:00+00','2026-08-20 02:00+00');

select set_config('request.jwt.claim.sub',
  '90000000-0000-4000-8000-000000000001',true);

do $assertions$
declare
  v_v2 jsonb;
  v_v3 jsonb;
  v_row jsonb;
  v_passed integer:=0;
begin
  v_v2:=public.school_list_lesson_clearance_pending_balances_v2(null,true);
  v_v3:=public.school_list_lesson_clearance_pending_balances_v3(null,true);
  if v_v3->>'contract_version'<>'lesson_clearance_pending_balances_v3'
     or jsonb_array_length(v_v3->'items')<>jsonb_array_length(v_v2->'items') then
    raise exception 'D2_A2_LOCAL_CONTRACT_INVALID';
  end if;
  v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_v3->'items') item
  where item->>'pending_source_planned_id'='2d2a0000-0000-4000-8000-000000000101';
  if v_row->>'operational_display_date'<>'2026-08-14'
     or v_row->>'operational_display_date_basis'<>'partial_actual_date'
     or v_row->>'origin_partial_actual_id'<>'2d2a0000-0000-4000-8000-000000000201'
     or v_row->>'origin_partial_actual_date'<>'2026-08-14'
     or v_row->>'origin_evidence_status'<>'unique_valid_partial_actual' then
    raise exception 'D2_A2_LOCAL_PARTIAL_INVALID:%',v_row;
  end if;
  v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_v3->'items') item
  where item->>'pending_source_planned_id'='2d2a0000-0000-4000-8000-000000000102';
  if v_row->>'operational_display_date'<>'2026-08-03'
     or v_row->>'operational_display_date_basis'<>'source_natural_week_start'
     or v_row->>'origin_partial_actual_id' is not null
     or v_row->>'origin_evidence_status'<>'no_valid_partial_actual' then
    raise exception 'D2_A2_LOCAL_CANCELLED_MAKEUP_INVALID:%',v_row;
  end if;
  v_passed:=v_passed+1;

  select item into strict v_row from jsonb_array_elements(v_v3->'items') item
  where item->>'pending_source_planned_id'='2d2a0000-0000-4000-8000-000000000103';
  if v_row->>'operational_display_date'<>'2026-08-17'
     or v_row->>'origin_partial_actual_id' is not null
     or v_row->>'origin_evidence_status'<>'no_valid_partial_actual' then
    raise exception 'D2_A2_LOCAL_VOIDED_INVALID:%',v_row;
  end if;
  v_passed:=v_passed+1;

  if exists(
    select 1
    from jsonb_array_elements(v_v3->'items') v3_item
    join jsonb_array_elements(v_v2->'items') v2_item
      on v2_item->>'pending_source_planned_id'=v3_item->>'pending_source_planned_id'
    where (v3_item-array['operational_display_date','operational_display_date_basis',
      'origin_partial_actual_id','origin_partial_actual_date','origin_evidence_status',
      'operational_display_explanation']) is distinct from v2_item
  ) then
    raise exception 'D2_A2_LOCAL_V2_FACT_DRIFT';
  end if;
  v_passed:=v_passed+1;

  if v_passed<>5 then raise exception 'D2_A2_LOCAL_ASSERTION_COUNT:%',v_passed; end if;
  raise notice 'Phase2C-D2-A2 local passed_assertions=%',v_passed;
end
$assertions$;

select 'PHASE2C_D2_A2_LOCAL_PASS passed_assertions=5' result;
rollback;
