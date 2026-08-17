-- Phase 2C-C extended local contract: Preview, forward, reversal, projection and zero-side-effects.
-- Disposable PostgreSQL only. Every write is rolled back.
\set ON_ERROR_STOP on

begin;
create temporary table phase2cc_assertions(label text primary key);
create function pg_temp.phase2cc_assert(p_ok boolean,p_label text)
returns void language plpgsql as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2cc_assertions values(p_label);
end
$function$;
create function pg_temp.phase2cc_expect_error(p_sql text,p_pattern text,p_label text)
returns void language plpgsql as $function$
begin
  begin execute p_sql; raise exception 'EXPECTED_ERROR_MISSING: %',p_label;
  exception when others then
    if sqlerrm like 'EXPECTED_ERROR_MISSING:%' or position(p_pattern in sqlerrm)=0 then raise; end if;
  end;
  insert into phase2cc_assertions values(p_label);
end
$function$;

create temporary table phase2cc_before(object_name text primary key,row_hash text);
insert into phase2cc_before values
  ('locked_settlement',(select md5(to_jsonb(row_value)::text)
    from public.school_student_monthly_settlements row_value
    where id='60000000-0000-4000-8000-000000000001')),
  ('bill',(select md5(to_jsonb(row_value)::text)
    from public.school_student_tuition_bills row_value
    where id='07a02092-9503-47d1-9000-106f7e3de7e5')),
  ('revision',(select md5(to_jsonb(row_value)::text)
    from public.school_student_tuition_generation_revisions row_value
    where id='96000000-0000-4000-8000-202608031004')),
  ('income',(select md5(to_jsonb(row_value)::text)
    from public.school_income_records row_value
    where id='91756564-c48d-4a1d-b6bc-88a041660e46')),
  ('cash',(select md5(to_jsonb(row_value)::text)
    from public.school_personal_cash_income_linkage_events row_value
    where id='9de972ff-8e66-470a-8b05-e430ef51562f')),
  ('package',(select md5(to_jsonb(row_value)::text)
    from public.school_student_package_credit_lots row_value
    where id='2a000000-0000-4000-8000-202608170002'));

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select public.school_preview_lesson_clearance(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000101',30,'2026-02-10',null
) preview \gset preview_
reset role;
select pg_temp.phase2cc_assert(
  (:'preview_preview'::jsonb->>'pending_before_minutes')::integer=120
  and (:'preview_preview'::jsonb->>'pending_after_minutes')::integer=90
  and (:'preview_preview'::jsonb->>'overtime_before_minutes')::integer=120
  and (:'preview_preview'::jsonb->>'overtime_after_minutes')::integer=90
  and (:'preview_preview'::jsonb->>'pending_amount_jpy')::numeric=-5000
  and (:'preview_preview'::jsonb->>'overtime_amount_jpy')::numeric=5000
  and (:'preview_preview'::jsonb->>'financial_net_amount_jpy')::numeric=0,
  'Preview returns DB-authoritative same-price minutes and two-sided JPY evidence');
select pg_temp.phase2cc_assert(
  (select count(*)=0 from public.school_lesson_clearances),
  'Preview and FIFO readers write zero clearance rows');

select pg_temp.phase2cc_expect_error($sql$
  select public.school_preview_lesson_clearance(
    'overtime_offset','30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',30,'2026-02-10',null)$sql$,
  'LESSON_CLEARANCE_OVERTIME_SOURCE_INVALID',
  'Preview rejects a cancelled/non-overage actual exactly like the writer');
select pg_temp.phase2cc_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'overtime_offset','8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9',
    '40000000-0000-4000-8000-000000000101',15,'2026-02-10',
    'manual_business_choice','P002 forbidden','P002 forbidden',null,
    'extended-p002-forbidden','90000000-0000-4000-8000-000000000001','owner')$sql$,
  'LESSON_CLEARANCE_PACKAGE_SOURCE_FORBIDDEN','P002 cannot become a clearance source');

select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000006',
  '40000000-0000-4000-8000-000000000102',30,'2026-02-10',
  null,null,'locked same-price forward evidence',null,
  'extended-locked-offset','90000000-0000-4000-8000-000000000001','admin'
) \gset locked_
select pg_temp.phase2cc_assert(:'locked_requires_forward_adjustment'::boolean
  and (select financial_year_month='2026-02'
       from public.school_lesson_clearances where id=:'locked_clearance_id'::uuid)
  and (select forward_adjustment_direction='none' and forward_adjustment_amount_jpy=0
       from public.school_lesson_clearance_details where clearance_id=:'locked_clearance_id'::uuid),
  'Locked same-price offset forwards to operation month and preserves zero net amount');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select count(*) forward_count,min(source_manifest_sha256) forward_manifest
from public.school_list_lesson_clearance_forward_manifest(
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001','2026-02'
) \gset forward_
reset role;
select pg_temp.phase2cc_assert(:'forward_forward_count'::integer=1
  and :'forward_forward_manifest' ~ '^[0-9a-f]{64}$',
  'Future settlement forward manifest contains the locked clearance evidence');

select * from public.school_reverse_lesson_clearance_core(
  :'locked_clearance_id','2026-03-03','reverse after immutable source month',
  'extended-locked-reversal','90000000-0000-4000-8000-000000000001','admin'
) \gset reverse_
select pg_temp.phase2cc_assert(
  (select clearance_type='reversal' and requires_forward_adjustment
      and financial_year_month='2026-03'
   from public.school_lesson_clearances where id=:'reverse_reversal_clearance_id'::uuid)
  and (select balance_effect='restore'
   from public.school_lesson_clearance_details where clearance_id=:'reverse_reversal_clearance_id'::uuid)
  and (select count(*)=2 from public.school_lesson_clearances
    where id in (:'locked_clearance_id'::uuid,:'reverse_reversal_clearance_id'::uuid)),
  'Reversal appends a later operation-month forward fact without mutating original');

select * from public.school_create_lesson_clearance_core(
  'administrative_writeoff','30000000-0000-4000-8000-000000000007',null,
  30,'2026-02-10',null,null,'DB-authoritative financial adjustment',
  'financial_adjustment_required','extended-financial-writeoff',
  '90000000-0000-4000-8000-000000000001','admin'
) \gset adjustment_
select pg_temp.phase2cc_assert(
  (select forward_adjustment_direction='increase_student_due'
      and forward_adjustment_amount_jpy=5000
      and forward_adjustment_amount_source='pending_unit_price_minutes_v1'
   from public.school_lesson_clearance_details
   where clearance_id=:'adjustment_clearance_id'::uuid),
  'Administrative financial forward direction and amount are DB-authoritative');

select pg_temp.phase2cc_expect_error($sql$
  select * from public.school_create_lesson_clearance_core(
    'legacy_consolidated_fulfillment','30000000-0000-4000-8000-000000000008',
    null,15,'2026-02-10',null,null,'operator forbidden',null,
    'extended-legacy-operator','90000000-0000-4000-8000-000000000002','operator')$sql$,
  'LESSON_CLEARANCE_LEGACY_ADMIN_REQUIRED','Legacy consolidated fulfillment is admin-only');

insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  planned_lesson_id,lesson_date,duration_hours,actual_minutes,unit_price,lesson_fee,
  is_billable,year_month,student_settlement_month,teacher_settlement_month,
  created_at,updated_at
) values (
  '40000000-0000-4000-8000-000000000201','actual','makeup_completed',
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000008','2026-03-05',0.5,30,0,0,false,
  '2026-03','2026-01','2026-03',transaction_timestamp(),transaction_timestamp()
);
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000003',true);
select count(*) projection_count,count(distinct actual_lesson_id) identity_count,
  min(source_planned_lesson_id::text) source_id,
  min(student_settlement_month) student_month,min(teacher_wage_month) wage_month
from public.school_list_cross_month_makeup_projection(
  '10000000-0000-4000-8000-000000000001',null
) where actual_lesson_id='40000000-0000-4000-8000-000000000201' \gset projection_
select count(*) clearance_projection_count
from public.school_list_cross_month_makeup_projection(null,null)
where actual_lesson_id=:'locked_clearance_id'::uuid \gset projection_clearance_
reset role;
select pg_temp.phase2cc_assert(:'projection_projection_count'::integer=2
  and :'projection_identity_count'::integer=1
  and :'projection_source_id'='30000000-0000-4000-8000-000000000008'
  and :'projection_student_month'='2026-01' and :'projection_wage_month'='2026-03',
  'Cross-month makeup projects one actual UUID into source and actual months');
select pg_temp.phase2cc_assert(:'projection_clearance_clearance_projection_count'::integer=0,
  'Clearance facts never masquerade as makeup actuals');

select pg_temp.phase2cc_expect_error(format(
  'update public.school_lesson_clearance_details set allocated_minutes=15 where clearance_id=%L',
  :'locked_clearance_id'),'LESSON_CLEARANCE_APPEND_ONLY',
  'Append-only detail update is rejected');
select pg_temp.phase2cc_expect_error(
  'truncate public.school_lesson_clearance_details,public.school_lesson_clearances',
  'LESSON_CLEARANCE_APPEND_ONLY',
  'Append-only header truncate is rejected');

select pg_temp.phase2cc_assert(
  (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_student_monthly_settlements row_value
    where id='60000000-0000-4000-8000-000000000001')
    from phase2cc_before where object_name='locked_settlement')
  and (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_student_tuition_bills row_value
    where id='07a02092-9503-47d1-9000-106f7e3de7e5')
    from phase2cc_before where object_name='bill')
  and (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_student_tuition_generation_revisions row_value
    where id='96000000-0000-4000-8000-202608031004')
    from phase2cc_before where object_name='revision')
  and (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_income_records row_value
    where id='91756564-c48d-4a1d-b6bc-88a041660e46')
    from phase2cc_before where object_name='income')
  and (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_personal_cash_income_linkage_events row_value
    where id='9de972ff-8e66-470a-8b05-e430ef51562f')
    from phase2cc_before where object_name='cash')
  and (select row_hash=(select md5(to_jsonb(row_value)::text)
    from public.school_student_package_credit_lots row_value
    where id='2a000000-0000-4000-8000-202608170002')
    from phase2cc_before where object_name='package'),
  'Locked settlement, bill, revision, income, Cash and P002 lot remain byte-stable');

select count(*) passed_extended_assertions from phase2cc_assertions;
rollback;
