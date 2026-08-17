-- Phase 2C-C-R1 local Preview/History/Reversal read contract matrix.
-- Disposable PostgreSQL only; all clearance fixtures roll back.
\set ON_ERROR_STOP on
begin;

create temporary table phase2ccr1_assertions(label text primary key);
create function pg_temp.assert_true(p_ok boolean,p_label text)
returns void language plpgsql as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2ccr1_assertions values(p_label);
end
$function$;

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select public.school_preview_lesson_clearance_v2(
  'aa000000-0000-4000-8000-000000000001','overtime_offset',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','unlocked non-FIFO source','operator preview',null
) preview \gset operator_
reset role;

select pg_temp.assert_true(
  :'operator_preview'::jsonb->>'request_identity'='aa000000-0000-4000-8000-000000000001'
  and :'operator_preview'::jsonb->>'idempotency_key'='aa000000-0000-4000-8000-000000000001'
  and (:'operator_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and (:'operator_preview'::jsonb->'comparison'->>'cross_teacher')::boolean
  and (:'operator_preview'::jsonb->'comparison'->>'cross_subject')::boolean,
  'operator unlocked Preview returns identity and DB cross flags');
select pg_temp.assert_true(
  (:'operator_preview'::jsonb->'pending_source'->>'initial_minutes')::integer=120
  and (:'operator_preview'::jsonb->'pending_source'->>'before_remaining_minutes')::integer=120
  and (:'operator_preview'::jsonb->'pending_source'->>'after_remaining_minutes')::integer=90
  and (:'operator_preview'::jsonb->'overtime_source'->>'frozen_overtime_minutes')::integer=120
  and (:'operator_preview'::jsonb->'overtime_source'->>'after_available_minutes')::integer=90
  and (:'operator_preview'::jsonb->'financial'->>'net_amount_jpy')::numeric=0,
  'Preview minutes and JPY are DB authoritative');
select pg_temp.assert_true(
  :'operator_preview'::jsonb->>'preview_manifest_sha256' ~ '^[0-9a-f]{64}$'
  and position('30000000-0000-4000-8000-000000000001'
    in :'operator_preview'::jsonb::text)>0,
  'request/source/type/minutes are bound into the Preview contract and manifest');
select pg_temp.assert_true(
  (select count(*)=0 from public.school_lesson_clearances),
  'Preview writes zero rows');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select public.school_preview_lesson_clearance_v2(
  'aa000000-0000-4000-8000-000000000002','overtime_offset',
  '30000000-0000-4000-8000-000000000006','40000000-0000-4000-8000-000000000102',
  30,'2026-02-10',null,null,'operator locked preview',null
) preview \gset locked_operator_
reset role;
select pg_temp.assert_true(
  not (:'locked_operator_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and :'locked_operator_preview'::jsonb->'authorization'->>'blocker_code'
    ='LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED'
  and :'locked_operator_preview'::jsonb->'financial'->>'forward_destination_month'='2026-02',
  'operator locked Preview is visible but not executable');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.school_preview_lesson_clearance_v2(
  'aa000000-0000-4000-8000-000000000003','overtime_offset',
  '30000000-0000-4000-8000-000000000006','40000000-0000-4000-8000-000000000102',
  30,'2026-02-10',null,null,'admin locked preview',null
) preview \gset locked_admin_
reset role;
select pg_temp.assert_true(
  (:'locked_admin_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and (:'locked_admin_preview'::jsonb->'authorization'->>'requires_admin')::boolean
  and (:'locked_admin_preview'::jsonb->'pending_source'->>'source_locked')::boolean,
  'admin locked Preview returns exact physical lock evidence');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000003',true);
select public.school_preview_lesson_clearance_v2(
  'aa000000-0000-4000-8000-000000000004','overtime_offset',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','readonly source','readonly preview',null
) preview \gset readonly_
reset role;
select pg_temp.assert_true(
  not (:'readonly_preview'::jsonb->'authorization'->>'can_execute_for_current_actor')::boolean
  and :'readonly_preview'::jsonb->'authorization'->>'blocker_code'
    ='LESSON_CLEARANCE_ROLE_REQUIRED',
  'read_only receives a non-executable Preview');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.school_preview_lesson_clearance_v2(
  'aa000000-0000-4000-8000-000000000005','overtime_offset',
  '30000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000101',
  30,'2026-02-10','manual_choice','cross source evidence','nonfifo preview',null
) preview \gset nonfifo_
reset role;
select pg_temp.assert_true(
  (:'nonfifo_preview'::jsonb->'fifo'->>'deviation_required')::boolean
  and (:'nonfifo_preview'::jsonb->'fifo'->>'deviation_reason_valid')::boolean
  and not (:'nonfifo_preview'::jsonb->'fifo'->>'is_recommended_target')::boolean,
  'non-FIFO manual choice returns recommendation and deviation evidence');

select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000101',30,'2026-02-10',
  'manual_choice','cross source evidence','nonfifo preview',null,
  'aa000000-0000-4000-8000-000000000005',
  '90000000-0000-4000-8000-000000000001','admin'
) \gset created_

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.school_list_lesson_clearance_history_v2(null) history \gset history_
select public.school_preview_lesson_clearance_reversal_v1(
  'aa000000-0000-4000-8000-000000000006',:'created_clearance_id'::uuid,'2026-03-03'
) preview \gset reverse_
reset role;
select pg_temp.assert_true(
  jsonb_array_length(:'history_history'::jsonb)=1
  and :'history_history'::jsonb->0->>'request_identity'
    ='aa000000-0000-4000-8000-000000000005'
  and :'history_history'::jsonb->0->>'deviation_reason_code'='manual_choice'
  and (:'history_history'::jsonb->0->>'cross_teacher')::boolean
  and (:'history_history'::jsonb->0->>'cross_subject')::boolean,
  'History V2 returns snapshot selection/deviation and immutable source comparison');
select pg_temp.assert_true(
  (:'reverse_preview'::jsonb->'authorization'->>'can_reverse')::boolean
  and not (:'reverse_preview'::jsonb->'current_state'->>'already_reversed')::boolean
  and (:'reverse_preview'::jsonb->'current_state'->>'pending_after_reversal_minutes')::integer
    =(:'reverse_preview'::jsonb->'current_state'->>'pending_before_reversal_minutes')::integer+30
  and :'reverse_preview'::jsonb->>'reversal_manifest_sha256' ~ '^[0-9a-f]{64}$',
  'Reversal Preview returns eligibility, balances and manifest without writing');
select pg_temp.assert_true(
  (select count(*)=1 from public.school_lesson_clearances),
  'Reversal Preview writes zero rows');

select * from public.school_reverse_lesson_clearance_core(
  :'created_clearance_id'::uuid,'2026-03-03','local reversal fixture',
  'aa000000-0000-4000-8000-000000000006',
  '90000000-0000-4000-8000-000000000001','admin'
) \gset reversed_
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.school_preview_lesson_clearance_reversal_v1(
  'aa000000-0000-4000-8000-000000000007',:'created_clearance_id'::uuid,'2026-03-04'
) preview \gset reversed_preview_
select public.school_list_lesson_clearance_history_v2(null) history \gset reversed_history_
reset role;
select pg_temp.assert_true(
  not (:'reversed_preview_preview'::jsonb->'authorization'->>'can_reverse')::boolean
  and :'reversed_preview_preview'::jsonb->'authorization'->>'blocker_code'
    ='LESSON_CLEARANCE_ALREADY_REVERSED'
  and exists(select 1 from jsonb_array_elements(:'reversed_history_history'::jsonb) item
    where item->>'clearance_id'=:'created_clearance_id'
      and (item->>'is_reversed')::boolean),
  'already-reversed clearance is non-reversible and history links reversal');

select pg_temp.assert_true(
  (select initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
   from public.school_student_package_credit_lots
   where id='2a000000-0000-4000-8000-202608170002'),
  'P002 remains isolated');
select pg_temp.assert_true(
  (select count(*)=13 from phase2ccr1_assertions),
  'all R1 assertions recorded');

select count(*) assertion_count from phase2ccr1_assertions;
rollback;
