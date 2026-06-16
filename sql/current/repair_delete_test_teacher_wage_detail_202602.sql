-- repair_delete_test_teacher_wage_detail_202602.sql
-- Purpose:
-- - Remove one confirmed test teacher wage detail row.
-- - Recalculate the parent wage lock summary from remaining detail rows.
-- - Do not touch expense records, payment requests, Cash linkage, or source lessons.

BEGIN;

-- Repair target constants:
-- detail_id: f9d36502-7c80-492d-92ba-db31942a7170
-- lock_id:   2aa849e9-4898-425d-b861-843a0dbd8001

-- Pre-repair: target detail and parent lock.
select
  d.id as detail_id,
  d.lock_id,
  d.lesson_record_id,
  d.lesson_date,
  d.status as detail_status,
  d.pay_hours as detail_pay_hours,
  d.lesson_wage_jpy as detail_lesson_wage_jpy,
  d.lesson_wage_cny as detail_lesson_wage_cny,
  d.transport_fee_jpy as detail_transport_fee_jpy,
  d.classroom_fee_jpy as detail_classroom_fee_jpy,
  d.total_jpy as detail_total_jpy,
  d.total_cny as detail_total_cny,
  d.created_at as detail_created_at,
  l.id as lock_id,
  l.teacher_id,
  l.teacher_name,
  l.settlement_month,
  l.status as lock_status,
  l.lesson_count as lock_lesson_count,
  l.total_minutes as lock_total_minutes,
  l.pay_hours as lock_pay_hours,
  l.lesson_wage_jpy as lock_lesson_wage_jpy,
  l.lesson_wage_cny as lock_lesson_wage_cny,
  l.fee_jpy as lock_fee_jpy,
  l.total_jpy as lock_total_jpy,
  l.total_cny as lock_total_cny,
  l.locked_at,
  l.voided_at,
  l.created_at as lock_created_at,
  l.updated_at as lock_updated_at
from public.school_teacher_wage_lock_details d
join public.school_teacher_wage_locks l on l.id = d.lock_id
where d.id = 'f9d36502-7c80-492d-92ba-db31942a7170'::uuid
  and d.lock_id = '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid;

-- Pre-repair: current detail sums for the lock.
select
  d.lock_id,
  count(*) as detail_count,
  coalesce(sum(d.pay_hours), 0) as sum_pay_hours,
  coalesce(sum(d.pay_hours * 60), 0) as sum_total_minutes,
  coalesce(sum(d.lesson_wage_jpy), 0) as sum_lesson_wage_jpy,
  coalesce(sum(d.lesson_wage_cny), 0) as sum_lesson_wage_cny,
  coalesce(sum(d.transport_fee_jpy + d.classroom_fee_jpy), 0) as sum_fee_jpy,
  coalesce(sum(d.total_jpy), 0) as sum_total_jpy,
  coalesce(sum(d.total_cny), 0) as sum_total_cny
from public.school_teacher_wage_lock_details d
where d.lock_id = '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid
group by d.lock_id;

-- Pre-repair: downstream side-effect counts must all be zero.
with target as (
  select
    'f9d36502-7c80-492d-92ba-db31942a7170'::uuid as detail_id,
    '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid as lock_id
)
select
  (select count(*)
   from public.school_expense_records e
   join target t on e.source_type = 'teacher_wage' and e.source_id = t.lock_id) as teacher_wage_expense_count,
  (select count(*)
   from public.school_payment_requests p
   join target t on p.source_type = 'teacher_wage' and p.source_id = t.lock_id) as teacher_wage_payment_request_count,
  (select count(*)
   from public.school_personal_cash_linkage_events cle
   join public.school_payment_requests p on p.id = cle.payment_request_id
   join target t on p.source_type = 'teacher_wage' and p.source_id = t.lock_id) as cash_linkage_count,
  (select count(*)
   from public.school_teacher_wage_detail_adjustments a
   join target t on a.wage_detail_id = t.detail_id) as detail_adjustment_count;

do $$
declare
  v_detail_id constant uuid := 'f9d36502-7c80-492d-92ba-db31942a7170'::uuid;
  v_lock_id constant uuid := '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid;
  v_detail_count integer;
  v_detail record;
  v_lock record;
  v_downstream_count integer;
  v_deleted_count integer;
  v_new_summary record;
begin
  select count(*)
    into v_detail_count
  from public.school_teacher_wage_lock_details
  where id = v_detail_id;

  if v_detail_count <> 1 then
    raise exception 'expected exactly one target detail %, found %', v_detail_id, v_detail_count;
  end if;

  select *
    into v_detail
  from public.school_teacher_wage_lock_details
  where id = v_detail_id
    and lock_id = v_lock_id;

  if not found then
    raise exception 'target detail % does not belong to lock %', v_detail_id, v_lock_id;
  end if;

  if v_detail.total_jpy <> 10000 then
    raise exception 'unexpected target total_jpy: expected 10000, found %', v_detail.total_jpy;
  end if;

  if v_detail.total_cny <> 428.18 then
    raise exception 'unexpected target total_cny: expected 428.18, found %', v_detail.total_cny;
  end if;

  if v_detail.pay_hours <> 2 then
    raise exception 'unexpected target pay_hours: expected 2, found %', v_detail.pay_hours;
  end if;

  select *
    into v_lock
  from public.school_teacher_wage_locks
  where id = v_lock_id;

  if not found then
    raise exception 'target wage lock % does not exist', v_lock_id;
  end if;

  if v_lock.status <> 'locked' then
    raise exception 'target wage lock % status must be locked, found %', v_lock_id, v_lock.status;
  end if;

  if v_lock.total_jpy <> 30000 then
    raise exception 'unexpected lock total_jpy: expected 30000, found %', v_lock.total_jpy;
  end if;

  if v_lock.total_cny <> 1284.54 then
    raise exception 'unexpected lock total_cny: expected 1284.54, found %', v_lock.total_cny;
  end if;

  if v_lock.pay_hours <> 6 then
    raise exception 'unexpected lock pay_hours: expected 6, found %', v_lock.pay_hours;
  end if;

  if v_lock.lesson_count <> 3 then
    raise exception 'unexpected lock lesson_count: expected 3, found %', v_lock.lesson_count;
  end if;

  select count(*)
    into v_downstream_count
  from public.school_expense_records
  where source_type = 'teacher_wage'
    and source_id = v_lock_id;

  if v_downstream_count <> 0 then
    raise exception 'target wage lock % has % teacher_wage expense records', v_lock_id, v_downstream_count;
  end if;

  select count(*)
    into v_downstream_count
  from public.school_payment_requests
  where source_type = 'teacher_wage'
    and source_id = v_lock_id;

  if v_downstream_count <> 0 then
    raise exception 'target wage lock % has % teacher_wage payment requests', v_lock_id, v_downstream_count;
  end if;

  select count(*)
    into v_downstream_count
  from public.school_personal_cash_linkage_events cle
  join public.school_payment_requests p on p.id = cle.payment_request_id
  where p.source_type = 'teacher_wage'
    and p.source_id = v_lock_id;

  if v_downstream_count <> 0 then
    raise exception 'target wage lock % has % Cash linkage events', v_lock_id, v_downstream_count;
  end if;

  select count(*)
    into v_downstream_count
  from public.school_teacher_wage_detail_adjustments
  where wage_detail_id = v_detail_id;

  if v_downstream_count <> 0 then
    raise exception 'target detail % has % adjustment audit rows', v_detail_id, v_downstream_count;
  end if;

  delete from public.school_teacher_wage_lock_details
  where id = v_detail_id
    and lock_id = v_lock_id;

  get diagnostics v_deleted_count = row_count;

  if v_deleted_count <> 1 then
    raise exception 'expected to delete exactly one detail %, deleted %', v_detail_id, v_deleted_count;
  end if;

  select
    count(*)::integer as lesson_count,
    coalesce(sum(d.pay_hours), 0)::numeric as pay_hours,
    coalesce(sum(d.pay_hours * 60), 0)::numeric as total_minutes,
    coalesce(sum(d.lesson_wage_jpy), 0)::numeric as lesson_wage_jpy,
    coalesce(sum(d.lesson_wage_cny), 0)::numeric as lesson_wage_cny,
    coalesce(sum(d.transport_fee_jpy + d.classroom_fee_jpy), 0)::numeric as fee_jpy,
    (
      coalesce(sum(d.lesson_wage_jpy), 0)
      + coalesce(sum(d.transport_fee_jpy + d.classroom_fee_jpy), 0)
    )::numeric as total_jpy,
    coalesce(sum(d.lesson_wage_cny), 0)::numeric as total_cny
    into v_new_summary
  from public.school_teacher_wage_lock_details d
  where d.lock_id = v_lock_id;

  if v_new_summary.lesson_count <> 2 then
    raise exception 'unexpected post-delete lesson_count: expected 2, found %', v_new_summary.lesson_count;
  end if;

  if v_new_summary.pay_hours <> 4 then
    raise exception 'unexpected post-delete pay_hours: expected 4, found %', v_new_summary.pay_hours;
  end if;

  if v_new_summary.total_jpy <> 20000 then
    raise exception 'unexpected post-delete total_jpy: expected 20000, found %', v_new_summary.total_jpy;
  end if;

  if v_new_summary.total_cny <> 856.36 then
    raise exception 'unexpected post-delete total_cny: expected 856.36, found %', v_new_summary.total_cny;
  end if;

  update public.school_teacher_wage_locks
  set
    lesson_count = v_new_summary.lesson_count,
    total_minutes = v_new_summary.total_minutes,
    pay_hours = v_new_summary.pay_hours,
    lesson_wage_jpy = v_new_summary.lesson_wage_jpy,
    lesson_wage_cny = v_new_summary.lesson_wage_cny,
    fee_jpy = v_new_summary.fee_jpy,
    total_jpy = v_new_summary.total_jpy,
    total_cny = v_new_summary.total_cny,
    updated_at = now()
  where id = v_lock_id
    and status = 'locked';

  get diagnostics v_deleted_count = row_count;

  if v_deleted_count <> 1 then
    raise exception 'expected to update exactly one wage lock %, updated %', v_lock_id, v_deleted_count;
  end if;
end $$;

-- Post-repair: target detail must be gone.
select
  count(*) as target_detail_remaining_count
from public.school_teacher_wage_lock_details
where id = 'f9d36502-7c80-492d-92ba-db31942a7170'::uuid;

-- Post-repair: updated wage lock summary.
select
  l.id as lock_id,
  l.teacher_id,
  l.teacher_name,
  l.settlement_month,
  l.status,
  l.lesson_count,
  l.total_minutes,
  l.pay_hours,
  l.lesson_wage_jpy,
  l.lesson_wage_cny,
  l.fee_jpy,
  l.total_jpy,
  l.total_cny,
  l.locked_at,
  l.voided_at,
  l.created_at,
  l.updated_at
from public.school_teacher_wage_locks l
where l.id = '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid;

-- Post-repair: remaining detail sums for the lock.
select
  d.lock_id,
  count(*) as detail_count,
  coalesce(sum(d.pay_hours), 0) as sum_pay_hours,
  coalesce(sum(d.pay_hours * 60), 0) as sum_total_minutes,
  coalesce(sum(d.lesson_wage_jpy), 0) as sum_lesson_wage_jpy,
  coalesce(sum(d.lesson_wage_cny), 0) as sum_lesson_wage_cny,
  coalesce(sum(d.transport_fee_jpy + d.classroom_fee_jpy), 0) as sum_fee_jpy,
  coalesce(sum(d.total_jpy), 0) as sum_total_jpy,
  coalesce(sum(d.total_cny), 0) as sum_total_cny
from public.school_teacher_wage_lock_details d
where d.lock_id = '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid
group by d.lock_id;

-- Post-repair: downstream side-effect counts must remain zero.
with target as (
  select
    'f9d36502-7c80-492d-92ba-db31942a7170'::uuid as detail_id,
    '2aa849e9-4898-425d-b861-843a0dbd8001'::uuid as lock_id
)
select
  (select count(*)
   from public.school_expense_records e
   join target t on e.source_type = 'teacher_wage' and e.source_id = t.lock_id) as teacher_wage_expense_count,
  (select count(*)
   from public.school_payment_requests p
   join target t on p.source_type = 'teacher_wage' and p.source_id = t.lock_id) as teacher_wage_payment_request_count,
  (select count(*)
   from public.school_personal_cash_linkage_events cle
   join public.school_payment_requests p on p.id = cle.payment_request_id
   join target t on p.source_type = 'teacher_wage' and p.source_id = t.lock_id) as cash_linkage_count,
  (select count(*)
   from public.school_teacher_wage_detail_adjustments a
   join target t on a.wage_detail_id = t.detail_id) as detail_adjustment_count;

COMMIT;
