-- Phase 2C-C functional contract matrix. All writes roll back in a disposable DB.
-- Requires the Phase 2C-C local bootstrap + formal schema/backend migrations.
\set ON_ERROR_STOP on

begin;
create temporary table phase2ca_assertions(label text primary key);
create function pg_temp.phase2ca_assert(p_ok boolean,p_label text)
returns void language plpgsql as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2ca_assertions values(p_label);
end
$function$;
create function pg_temp.phase2ca_expect_error(p_sql text,p_pattern text,p_label text)
returns void language plpgsql as $function$
begin
  begin
    execute p_sql;
    raise exception 'EXPECTED_ERROR_MISSING: %',p_label;
  exception when others then
    if sqlerrm like 'EXPECTED_ERROR_MISSING:%'
       or position(p_pattern in sqlerrm)=0 then raise; end if;
  end;
  insert into phase2ca_assertions values(p_label);
end
$function$;

select pg_temp.phase2ca_assert(
  (select pending_source_planned_id='30000000-0000-4000-8000-000000000006'
	   from public.school_suggest_lesson_clearance_targets_core(
     '40000000-0000-4000-8000-000000000101')
   order by recommendation_rank limit 1),
  '03 recommendation is deterministic FIFO by authoritative/fallback creation time');
select pg_temp.phase2ca_assert(
  (select count(*)=0 from public.school_lesson_clearances),
  '03 suggestion reader writes zero rows');

-- FIFO first target is the locked historical P6; admin creates forward fact.
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000006',
  '40000000-0000-4000-8000-000000000102',60,'2026-02-10',
  null,null,'FIFO first locked source',null,'contract-fifo-first',
  '90000000-0000-4000-8000-000000000001','admin'
) \gset fifo_
select pg_temp.phase2ca_assert(
  :'fifo_recommended_pending_source_id'::uuid='30000000-0000-4000-8000-000000000006'
  and not :'fifo_deviated_from_recommendation'::boolean,
  '01 caller explicitly selected FIFO first target');
select pg_temp.phase2ca_assert(:'fifo_requires_forward_adjustment'::boolean,
  '20 locked historical month creates forward adjustment only');

select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000101',30,'2026-02-10',
  'manual_business_choice','confirmed non-FIFO target','cross teacher and subject',
  null,'contract-non-fifo-1','90000000-0000-4000-8000-000000000001','owner'
) \gset nonfifo_
select pg_temp.phase2ca_assert(:'nonfifo_deviated_from_recommendation'::boolean,
  '02 non-FIFO target persists deviation reason');
select pg_temp.phase2ca_assert(exists(
  select 1 from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  join public.school_lesson_records pending on pending.id=detail.pending_source_planned_id
  join public.school_lesson_records overtime on overtime.id=detail.overtime_source_actual_id
  where header.id=:'nonfifo_clearance_id'::uuid
    and pending.teacher_id<>overtime.teacher_id),
  '04 cross-teacher clearance succeeds');
select pg_temp.phase2ca_assert(exists(
  select 1 from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  join public.school_lesson_records pending on pending.id=detail.pending_source_planned_id
  join public.school_lesson_records overtime on overtime.id=detail.overtime_source_actual_id
  where header.id=:'nonfifo_clearance_id'::uuid
    and pending.subject_id<>overtime.subject_id),
  '05 cross-subject clearance succeeds');

select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000002',
    '40000000-0000-4000-8000-000000000101',15,'2026-02-10',
    null,null,'missing FIFO deviation',null,'contract-deviation-missing',
    '90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED',
  '02 deviation without reason is rejected');
select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000004',
    '40000000-0000-4000-8000-000000000101',15,'2026-02-10',
    'manual_business_choice','cross student','must reject',null,
    'contract-cross-student','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_STUDENT_MISMATCH','06 cross-student clearance rejected');
select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000009',
    '40000000-0000-4000-8000-000000000101',15,'2026-02-10',
    'manual_business_choice','cross entity','must reject',null,
    'contract-cross-entity','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_BUSINESS_ENTITY_MISMATCH','07 cross-entity clearance rejected');
select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000003',
    '40000000-0000-4000-8000-000000000101',15,'2026-02-10',
    'manual_business_choice','price mismatch','must reject',null,
    'contract-price-mismatch','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_PRICE_POLICY_REQUIRED','09 different-price clearance rejected stably');

select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000101',30,'2026-02-10',
  'manual_business_choice','confirmed non-FIFO target','partial same-price offset',
  null,'contract-partial-1','90000000-0000-4000-8000-000000000001','owner'
) \gset partial_
select pg_temp.phase2ca_assert(:'partial_pending_remaining_minutes'::integer=90
  and :'partial_overtime_remaining_minutes'::integer=60,
  '08/10 same-price partial clearance preserves both residual balances');

select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000104',30,'2026-02-10',
  'manual_business_choice','second allocation','same pending second allocation',
  null,'contract-same-pending-2','90000000-0000-4000-8000-000000000001','owner'
) \gset repeated_
select pg_temp.phase2ca_assert(:'repeated_pending_remaining_minutes'::integer=60,
  '11 one pending source supports multiple bounded allocations');
select pg_temp.phase2ca_assert(
  (select count(*)=2 from public.school_lesson_clearance_details
   where pending_source_planned_id='30000000-0000-4000-8000-000000000001'),
  '11 multiple pending allocations remain append-only facts');
select pg_temp.phase2ca_assert(
  (select count(distinct pending_source_planned_id)=2
   from public.school_lesson_clearance_details
   where overtime_source_actual_id='40000000-0000-4000-8000-000000000101'),
  '12 one overtime source can be allocated to multiple pending sources');

select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000002',
    '40000000-0000-4000-8000-000000000101',75,'2026-02-10',
    'manual_business_choice','excess allocation','must reject',null,
    'contract-excess-1','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT','13 excess allocation rejected');

-- Exact replay returns the same row and does not allocate twice.
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000104',30,'2026-02-10',
  'manual_business_choice','second allocation','same pending second allocation',
  null,'contract-same-pending-2','90000000-0000-4000-8000-000000000001','owner'
) \gset replay_
select pg_temp.phase2ca_assert(:'replay_clearance_id'::uuid=:'repeated_clearance_id'::uuid
  and :'replay_idempotent_replay'::boolean
  and (select count(*)=1 from public.school_lesson_clearances
       where idempotency_key='contract-same-pending-2'),
  '16 idempotency replay returns same clearance without duplicate allocation');

insert into public.school_student_settlement_lesson_variance_claims(
  claim_status,source_type,source_planned_lesson_id
) values('active','unused_planned_credit_v1',
  '30000000-0000-4000-8000-000000000003');
select pg_temp.phase2ca_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','30000000-0000-4000-8000-000000000003',
    '40000000-0000-4000-8000-000000000103',15,'2026-02-10',
    'manual_business_choice','claimed source','must reject',null,
    'contract-claim-first','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED',
  '17 active claim blocks subsequent clearance');
insert into public.school_student_settlement_lesson_variance_claims(
  claim_status,source_type,source_actual_lesson_id
) values('active','actual_duration_overage_charge_v1',
  '40000000-0000-4000-8000-000000000103');
select pg_temp.phase2ca_assert(
  not exists(select 1 from public.school_tuition_p0f_source_lines(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','2026-02',0.05,false)
    where source_actual_lesson_id='40000000-0000-4000-8000-000000000103')
  and exists(select 1 from public.school_tuition_p0f_source_lines(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','2026-02',0.05,true)
    where source_actual_lesson_id='40000000-0000-4000-8000-000000000103'),
  '17 source-lines preserve include-active-claimed compatibility');
select pg_temp.phase2ca_expect_error($sql$
  insert into public.school_student_settlement_lesson_variance_claims(
    claim_status,source_type,source_planned_lesson_id)
  values('active','unused_planned_credit_v1',
    '30000000-0000-4000-8000-000000000002')$sql$,
  'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_ALLOCATED',
  '17 existing clearance blocks subsequent active claim');

select pg_temp.phase2ca_assert(
  public.school_get_lesson_clearance_pending_remaining_minutes(
    '30000000-0000-4000-8000-000000000008')=90,
  '18 ordinary makeup actual minutes reduce balance before ledger allocation');
select * from public.school_create_lesson_clearance_core(
  'legacy_consolidated_fulfillment','30000000-0000-4000-8000-000000000008',
  null,90,'2026-02-10',null,null,'M006+M008 consolidated history fixture',null,
  'contract-legacy-consolidated','90000000-0000-4000-8000-000000000001','owner'
) \gset legacy_
select pg_temp.phase2ca_assert(:'legacy_pending_remaining_minutes'::integer=0,
  '38 M006+M008 historical consolidated fulfillment leaves source zero');
select pg_temp.phase2ca_assert(
  (select count(*)=1 from public.school_lesson_records
   where planned_lesson_id='30000000-0000-4000-8000-000000000008'
     and status='makeup_completed')
  and (select count(*)=1 from public.school_lesson_clearance_details
       where pending_source_planned_id='30000000-0000-4000-8000-000000000008'),
  '40 ordinary makeup remains actual-chain fact and is not duplicated in ledger');

select * from public.school_create_lesson_clearance_core(
  'administrative_writeoff','30000000-0000-4000-8000-000000000007',
  null,120,'2026-02-10',null,null,'M016 confirmed no fulfillment',
  'no_refund_no_credit','contract-m016-writeoff',
  '90000000-0000-4000-8000-000000000001','admin'
) \gset m016_
select pg_temp.phase2ca_assert(:'m016_pending_remaining_minutes'::integer=0
  and (select count(*)=0 from public.school_lesson_records
       where planned_lesson_id='30000000-0000-4000-8000-000000000007'),
  '22/39 M016 admin writeoff creates no actual, wage, refund, or credit fact');

select * from public.school_reverse_lesson_clearance_core(
  :'repeated_clearance_id','2026-02-11','reverse bounded allocation',
  'contract-reversal-1','90000000-0000-4000-8000-000000000001','admin'
) \gset reversal_
select pg_temp.phase2ca_assert(:'reversal_pending_remaining_minutes'::integer=90
  and :'reversal_overtime_remaining_minutes'::integer=60,
  '23 reversal appends restore fact and restores both derived balances');
select * from public.school_reverse_lesson_clearance_core(
  :'repeated_clearance_id','2026-02-11','reverse bounded allocation',
  'contract-reversal-1','90000000-0000-4000-8000-000000000001','admin'
) \gset reversal_replay_
select pg_temp.phase2ca_assert(
  :'reversal_replay_reversal_clearance_id'::uuid=:'reversal_reversal_clearance_id'::uuid
  and :'reversal_replay_idempotent_replay'::boolean
  and (select count(*)=1 from public.school_lesson_clearances
       where reverses_clearance_id=:'repeated_clearance_id'::uuid),
  '24 reversal idempotency does not restore twice');

select pg_temp.phase2ca_expect_error(format(
  'update public.school_lesson_clearances set business_note=%L where id=%L',
  'forbidden mutation',:'partial_clearance_id'),
  'LESSON_CLEARANCE_APPEND_ONLY','25 original clearance cannot be updated');
select pg_temp.phase2ca_expect_error(format(
  'delete from public.school_lesson_clearance_details where clearance_id=%L',
  :'partial_clearance_id'),
  'LESSON_CLEARANCE_APPEND_ONLY','25 original clearance details cannot be deleted');

select pg_temp.phase2ca_assert(
  (select not requires_forward_adjustment from public.school_lesson_clearances
   where id=:'partial_clearance_id'::uuid),
  '19 unlocked months create ordinary non-forward clearance fact');
select pg_temp.phase2ca_assert(
  (select every(forward_adjustment_direction='none'
       and forward_adjustment_amount_jpy=0
       and forward_adjustment_amount_source='same_unit_price_zero_residual_v1')
   from public.school_lesson_clearance_details),
  '08 V2 same-price ledger never computes a residual financial amount');

select count(*) as passed_contract_assertions from phase2ca_assertions;
rollback;
