-- school_unlock_relock_student_monthly_settlement_rpc.sql
-- RPCs: public.school_unlock_student_monthly_settlement,
--       public.school_relock_student_monthly_settlement
-- Purpose: Soft unlock and same-row relock V1 for student monthly settlements.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.75.0-student-settlement-unlock-relock-rpc-20260609
--
-- Scope:
-- - Unlock changes one existing locked settlement row to settlement_status = 'unlocked'.
-- - Relock recalculates the same row from public.school_get_student_monthly_settlement_summary.
-- - Keep id, student_id, year_month, created_at, unlocked_at, and unlock_reason.
-- - Keep public.school_lock_student_monthly_settlement insert-only.
--
-- Not supported:
-- - Physical delete, multi-version history, adjustment editing, automatic carryover
--   revoke/rebuild, frontend unlock/relock UI, lesson/income/account/wage writes.

create or replace function public.school_unlock_student_monthly_settlement(
  p_settlement_id uuid,
  p_reason text
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
  unlocked_at timestamptz,
  unlock_reason text,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_now timestamptz := now();
begin
  if p_settlement_id is null then
    raise exception '请选择要撤销锁定的学生月度结算。';
  end if;

  if v_reason is null then
    raise exception '请填写撤销锁定原因。';
  end if;

  select *
  into v_settlement
  from public.school_student_monthly_settlements
  where id = p_settlement_id
  for update;

  if not found then
    raise exception '没有找到对应的学生月度结算。';
  end if;

  if coalesce(v_settlement.settlement_status, '') <> 'locked' then
    raise exception '只有已锁定的学生月度结算可以撤销锁定。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_carryovers c
    where c.source_settlement_id = v_settlement.id
      and coalesce(c.status, 'active') = 'active'
  ) then
    raise exception '该结算已生成有效结转，不能撤销锁定。';
  end if;

  update public.school_student_monthly_settlements m
  set
    settlement_status = 'unlocked',
    unlocked_at = v_now,
    unlock_reason = v_reason,
    updated_at = v_now
  where m.id = v_settlement.id;

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
    m.unlocked_at,
    m.unlock_reason,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement.id;
end;
$$;

comment on function public.school_unlock_student_monthly_settlement(uuid, text) is
  'Soft-unlocks one locked student monthly settlement snapshot by setting settlement_status = unlocked, unlocked_at, and unlock_reason. Rejects blank reason and active carryovers sourced from the settlement. Does not delete rows or mutate lessons, income, accounts, wages, carryovers, or transactions.';

create or replace function public.school_relock_student_monthly_settlement(
  p_settlement_id uuid,
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
  unlocked_at timestamptz,
  unlock_reason text,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_business_entity_id uuid;
  v_summary record;
begin
  if p_settlement_id is null then
    raise exception '请选择要重新锁定的学生月度结算。';
  end if;

  select *
  into v_settlement
  from public.school_student_monthly_settlements
  where id = p_settlement_id
  for update;

  if not found then
    raise exception '没有找到对应的学生月度结算。';
  end if;

  if coalesce(v_settlement.settlement_status, '') <> 'unlocked' then
    raise exception '只有已撤销锁定的学生月度结算可以重新锁定。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_carryovers c
    where c.source_settlement_id = v_settlement.id
      and coalesce(c.status, 'active') = 'active'
  ) then
    raise exception '该结算已生成有效结转，不能重新锁定。';
  end if;

  select s.business_entity_id
  into v_business_entity_id
  from public.school_students s
  where s.id = v_settlement.student_id
    and s.app_type = 'school';

  if not found then
    raise exception '学生不存在或不属于学校业务。';
  end if;

  if v_business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能重新锁定结算。';
  end if;

  if not exists (
    select 1
    from public.school_lesson_records l
    where l.app_type = 'school'
      and l.student_id = v_settlement.student_id
      and l.year_month = v_settlement.year_month
      and not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1
    from public.school_income_records i
    where i.app_type = 'school'
      and i.student_id = v_settlement.student_id
      and coalesce(i.settlement_month, i.year_month) = v_settlement.year_month
      and i.income_category = 'tuition'
      and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception '该学生月份没有可结算的课时或学费收入，不能重新锁定。';
  end if;

  select *
  into v_summary
  from public.school_get_student_monthly_settlement_summary(
    v_settlement.student_id,
    v_settlement.year_month
  );

  if not found then
    raise exception '无法计算该学生月份的结算预览。';
  end if;

  update public.school_student_monthly_settlements m
  set
    business_entity_id = v_business_entity_id,
    preset_exchange_rate = coalesce(v_summary.exchange_rate, 0),
    planned_lesson_fee_jpy = coalesce(v_summary.planned_fee_jpy, 0),
    planned_lesson_fee_cny = coalesce(v_summary.planned_fee_cny, 0),
    actual_lesson_fee_jpy = coalesce(v_summary.actual_fee_jpy, 0),
    actual_lesson_fee_cny = coalesce(v_summary.actual_fee_cny, 0),
    previous_balance_cny = coalesce(v_summary.carryover_cny, 0),
    received_jpy = coalesce(v_summary.received_jpy, 0),
    received_cny = coalesce(v_summary.received_cny, 0),
    received_equivalent_cny = coalesce(v_summary.received_equivalent_cny, 0),
    system_difference_cny = coalesce(v_summary.final_due_cny, 0),
    adjustment_amount_cny = 0,
    adjustment_reason = null,
    carryover_amount_cny = coalesce(v_summary.final_due_cny, 0),
    settlement_status = 'locked',
    locked_at = v_now,
    note = v_note,
    updated_at = v_now
  where m.id = v_settlement.id;

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
    m.unlocked_at,
    m.unlock_reason,
    m.note,
    m.created_at,
    m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement.id;
end;
$$;

comment on function public.school_relock_student_monthly_settlement(uuid, text) is
  'Same-row relocks one unlocked student monthly settlement snapshot by recalculating school_get_student_monthly_settlement_summary and overwriting snapshot amounts. Preserves id, student_id, year_month, created_at, unlocked_at, and unlock_reason. Does not write carryovers, lessons, income, teacher wage, accounts, payments, expenses, or transactions.';
