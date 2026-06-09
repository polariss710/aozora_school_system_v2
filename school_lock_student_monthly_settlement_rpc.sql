-- school_lock_student_monthly_settlement_rpc.sql
-- RPC: public.school_lock_student_monthly_settlement
-- Purpose: Lock one student/month realtime settlement summary into a saved snapshot.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.73.0-student-settlement-lock-rpc-20260609
--
-- Scope:
-- - Insert one row into public.school_student_monthly_settlements.
-- - Snapshot granularity is student_id + year_month, matching the existing
--   unique constraint and settlement preview V1.
-- - Values are copied from public.school_get_student_monthly_settlement_summary.
-- - business_entity_id is the student's default business_entity_id.
-- - adjustment_amount_cny is fixed to 0; carryover_amount_cny is final_due_cny.
--
-- Not supported:
-- - Unlock, relock, adjustment editing, snapshot detail rows, historical backfill.
-- - Automatic next-month carryover creation.
-- - Teacher wage, account, income, lesson, expense, payment, or transaction writes.
--
-- Verification:
-- - Function exists with expected signature and comment.
-- - Rollback test created a codex-test planned source and locked snapshot,
--   verified duplicate/no-source/no-default-business guards, then left no residue.
-- - Commit test wrote whitelisted codex-test source lesson
--   dea88720-b4dd-4395-9f9b-937d01940192 and locked snapshot
--   b15a50fa-9437-461e-9e44-e51f8747640b only.
-- - Locked guards rejected lesson edit, planned void, completed actual,
--   cancelled actual, makeup-completed actual, income create, and income reverse.
-- - Income reverse guard was tested inside rollback and left no residue.

create or replace function public.school_lock_student_monthly_settlement(
  p_student_id uuid,
  p_year_month text,
  p_note text default null
)
returns table (
  settlement_id uuid,
  student_id uuid,
  year_month text,
  business_entity_id uuid,
  preset_exchange_rate numeric,
  planned_lesson_fee_jpy numeric,
  planned_lesson_fee_cny numeric,
  actual_lesson_fee_jpy numeric,
  actual_lesson_fee_cny numeric,
  previous_balance_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  system_difference_cny numeric,
  adjustment_amount_cny numeric,
  carryover_amount_cny numeric,
  settlement_status text,
  locked_at timestamptz,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_business_entity_id uuid;
  v_now timestamptz := now();
  v_summary record;
  v_settlement_id uuid;
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_year_month is null or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效，请使用 YYYY-MM。';
  end if;

  select s.business_entity_id
  into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id
    and s.app_type = 'school';

  if not found then
    raise exception '学生不存在或不属于学校业务。';
  end if;

  if v_business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能锁定结算。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements m
    where m.student_id = p_student_id
      and m.year_month = v_year_month
  ) then
    raise exception '该学生月份已存在结算快照，不能重复锁定。';
  end if;

  if not exists (
    select 1
    from public.school_lesson_records l
    where l.app_type = 'school'
      and l.student_id = p_student_id
      and l.year_month = v_year_month
      and not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1
    from public.school_income_records i
    where i.app_type = 'school'
      and i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = v_year_month
      and i.income_category = 'tuition'
      and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception '该学生月份没有可结算的课时或学费收入，不能锁定。';
  end if;

  select *
  into v_summary
  from public.school_get_student_monthly_settlement_summary(p_student_id, v_year_month);

  if not found then
    raise exception '无法计算该学生月份的结算预览。';
  end if;

  insert into public.school_student_monthly_settlements (
    student_id,
    year_month,
    business_entity_id,
    preset_exchange_rate,
    planned_lesson_fee_jpy,
    planned_lesson_fee_cny,
    actual_lesson_fee_jpy,
    actual_lesson_fee_cny,
    previous_balance_cny,
    received_jpy,
    received_cny,
    received_equivalent_cny,
    system_difference_cny,
    adjustment_amount_cny,
    adjustment_reason,
    carryover_amount_cny,
    settlement_status,
    locked_at,
    note,
    created_at,
    updated_at
  )
  values (
    p_student_id,
    v_year_month,
    v_business_entity_id,
    coalesce(v_summary.exchange_rate, 0),
    coalesce(v_summary.planned_fee_jpy, 0),
    coalesce(v_summary.planned_fee_cny, 0),
    coalesce(v_summary.actual_fee_jpy, 0),
    coalesce(v_summary.actual_fee_cny, 0),
    coalesce(v_summary.carryover_cny, 0),
    coalesce(v_summary.received_jpy, 0),
    coalesce(v_summary.received_cny, 0),
    coalesce(v_summary.received_equivalent_cny, 0),
    coalesce(v_summary.final_due_cny, 0),
    0,
    null,
    coalesce(v_summary.final_due_cny, 0),
    'locked',
    v_now,
    v_note,
    v_now,
    v_now
  )
  returning id into v_settlement_id;

  return query
  select
    m.id as settlement_id,
    m.student_id,
    m.year_month,
    m.business_entity_id,
    m.preset_exchange_rate,
    m.planned_lesson_fee_jpy,
    m.planned_lesson_fee_cny,
    m.actual_lesson_fee_jpy,
    m.actual_lesson_fee_cny,
    m.previous_balance_cny,
    m.received_jpy,
    m.received_cny,
    m.received_equivalent_cny,
    m.system_difference_cny,
    m.adjustment_amount_cny,
    m.carryover_amount_cny,
    m.settlement_status,
    m.locked_at,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement_id;
end;
$$;

comment on function public.school_lock_student_monthly_settlement(uuid, text, text) is
  'Locks one student/month realtime settlement summary into school_student_monthly_settlements. Uses student default business entity, rejects duplicate snapshots, requires an effective source, fixes adjustment_amount_cny to 0, and does not write carryovers, lessons, income, teacher wage, account, payment, expense, or transaction rows.';
