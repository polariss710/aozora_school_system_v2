-- school_student_settlement_adjustment_rpcs.sql
-- Purpose: Add guarded student settlement adjustment RPC and carryover read fix.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and whitelist commit-tested.
--
-- Scope:
-- - Replace read-only settlement summary RPC so next-month carryover can read
--   the previous locked settlement snapshot when no explicit carryover row exists.
-- - Add guarded adjustment RPC that writes only:
--   public.school_student_settlement_adjustments
--   public.school_student_monthly_settlements adjustment/carryover fields
-- - Harden unlock/relock so adjusted snapshots cannot be recalculated by the
--   legacy same-row flow.
-- - Does not write lessons, income, teacher wage, payments, expenses, accounts,
--   account transactions, or carryover rows.

create or replace function public.school_get_student_monthly_settlement_summary(
  p_student_id uuid,
  p_year_month text
)
returns table (
  student_id uuid,
  year_month text,
  exchange_rate numeric,
  carryover_cny numeric,
  planned_hours numeric,
  actual_hours numeric,
  planned_fee_jpy numeric,
  planned_fee_cny numeric,
  planned_total_cny numeric,
  actual_fee_jpy numeric,
  actual_fee_cny numeric,
  received_jpy numeric,
  received_cny numeric,
  received_equivalent_cny numeric,
  final_due_cny numeric,
  locked_carryover_cny numeric
)
language sql
stable
as $$
  with input_month as (
    select
      p_year_month as year_month,
      to_char((to_date(p_year_month || '-01', 'YYYY-MM-DD') - interval '1 month')::date, 'YYYY-MM') as previous_year_month
    where p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  student_base as (
    select
      s.id as student_id,
      coalesce(s.preset_exchange_rate, 0)::numeric as exchange_rate,
      coalesce(s.previous_balance_cny, 0)::numeric as fallback_carryover_cny
    from public.school_students s
    where s.id = p_student_id
  ),
  previous_locked_settlement as (
    select
      m.carryover_amount_cny
    from public.school_student_monthly_settlements m
    join input_month im on im.previous_year_month = m.year_month
    where m.student_id = p_student_id
      and m.settlement_status = 'locked'
    order by m.locked_at desc nulls last, m.updated_at desc nulls last, m.created_at desc nulls last
    limit 1
  ),
  carryover as (
    select
      coalesce(
        (
          select c.amount_cny
          from public.school_student_settlement_carryovers c
          where c.student_id = p_student_id
            and c.to_year_month = p_year_month
            and coalesce(c.status, 'active') = 'active'
          order by c.updated_at desc nulls last, c.created_at desc nulls last
          limit 1
        ),
        (select pls.carryover_amount_cny from previous_locked_settlement pls),
        (select fallback_carryover_cny from student_base),
        0
      )::numeric as carryover_cny
  ),
  lessons as (
    select
      l.id,
      l.planned_lesson_id,
      l.lesson_type,
      l.status,
      coalesce(l.is_billable, false) as is_billable,
      coalesce(l.duration_hours, 0)::numeric as duration_hours,
      coalesce(l.lesson_fee, coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)::numeric as fee_jpy
    from public.school_lesson_records l
    where l.student_id = p_student_id
      and l.year_month = p_year_month
      and not (l.lesson_type = 'planned' and l.voided_at is not null)
  ),
  lesson_summary as (
    select
      coalesce(sum(f.duration_hours) filter (
        where f.lesson_type = 'planned'
      ), 0)::numeric as planned_hours,

      coalesce(sum(f.duration_hours) filter (
        where f.lesson_type = 'actual'
          and f.is_billable = true
          and f.status in ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric as actual_hours,

      coalesce(sum(f.fee_jpy) filter (
        where f.lesson_type = 'planned'
      ), 0)::numeric as planned_fee_jpy,

      coalesce(sum(f.fee_jpy) filter (
        where f.lesson_type = 'actual'
          and f.is_billable = true
          and f.status in ('completed', 'makeup', 'makeup_completed')
      ), 0)::numeric as actual_fee_jpy
    from lessons f
  ),
  income_summary as (
    select
      coalesce(sum(i.amount) filter (
        where coalesce(i.payment_currency, i.currency) = 'JPY'
      ), 0)::numeric as received_jpy,
      coalesce(sum(i.amount) filter (
        where coalesce(i.payment_currency, i.currency) = 'CNY'
      ), 0)::numeric as received_cny
    from public.school_income_records i
    where i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = p_year_month
      and i.income_category = 'tuition'
      and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ),
  locked as (
    select
      m.carryover_amount_cny
    from public.school_student_monthly_settlements m
    where m.student_id = p_student_id
      and m.year_month = p_year_month
      and m.settlement_status = 'locked'
    order by m.locked_at desc nulls last, m.updated_at desc nulls last, m.created_at desc nulls last
    limit 1
  ),
  calculated as (
    select
      sb.student_id,
      p_year_month as year_month,
      sb.exchange_rate,
      coalesce(c.carryover_cny, 0)::numeric as carryover_cny,
      coalesce(ls.planned_hours, 0)::numeric as planned_hours,
      coalesce(ls.actual_hours, 0)::numeric as actual_hours,
      coalesce(ls.planned_fee_jpy, 0)::numeric as planned_fee_jpy,
      (coalesce(ls.planned_fee_jpy, 0) * sb.exchange_rate)::numeric as planned_fee_cny,
      ((coalesce(ls.planned_fee_jpy, 0) * sb.exchange_rate) + coalesce(c.carryover_cny, 0))::numeric as planned_total_cny,
      coalesce(ls.actual_fee_jpy, 0)::numeric as actual_fee_jpy,
      (coalesce(ls.actual_fee_jpy, 0) * sb.exchange_rate)::numeric as actual_fee_cny,
      coalesce(inc.received_jpy, 0)::numeric as received_jpy,
      coalesce(inc.received_cny, 0)::numeric as received_cny,
      (coalesce(inc.received_cny, 0) + coalesce(inc.received_jpy, 0) * sb.exchange_rate)::numeric as received_equivalent_cny
    from student_base sb
    cross join carryover c
    cross join lesson_summary ls
    cross join income_summary inc
  )
  select
    calc.student_id,
    calc.year_month,
    calc.exchange_rate,
    calc.carryover_cny,
    calc.planned_hours,
    calc.actual_hours,
    calc.planned_fee_jpy,
    calc.planned_fee_cny,
    calc.planned_total_cny,
    calc.actual_fee_jpy,
    calc.actual_fee_cny,
    calc.received_jpy,
    calc.received_cny,
    calc.received_equivalent_cny,
    (calc.actual_fee_cny + calc.carryover_cny - calc.received_equivalent_cny)::numeric as final_due_cny,
    coalesce(
      (select l.carryover_amount_cny from locked l),
      (calc.actual_fee_cny + calc.carryover_cny - calc.received_equivalent_cny)
    )::numeric as locked_carryover_cny
  from calculated calc;
$$;

comment on function public.school_get_student_monthly_settlement_summary(uuid, text) is
  'Returns student monthly settlement summary. Soft-voided planned lessons are excluded. Carryover priority: explicit active carryover row, previous locked monthly settlement carryover, student fallback previous_balance.';

create or replace function public.school_apply_student_monthly_settlement_adjustment(
  p_settlement_id uuid,
  p_adjustment_amount_cny numeric,
  p_adjustment_source text default 'manual',
  p_adjustment_reason text default null,
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
  adjustment_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_source text := nullif(trim(coalesce(p_adjustment_source, '')), '');
  v_reason text := nullif(trim(coalesce(p_adjustment_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_adjustment_id uuid;
  v_adjustment_total numeric;
  v_adjustment_reason text;
begin
  if p_settlement_id is null then
    raise exception '请选择学生月度结算快照。';
  end if;

  if p_adjustment_amount_cny is null then
    raise exception '请填写差额调整金额。';
  end if;

  if v_source is null then
    raise exception '请填写差额调整来源。';
  end if;

  if v_reason is null then
    raise exception '请填写差额调整理由。';
  end if;

  select *
  into v_settlement
  from public.school_student_monthly_settlements
  where id = p_settlement_id
  for update;

  if not found then
    raise exception '没有找到对应的学生月度结算快照。';
  end if;

  if coalesce(v_settlement.settlement_status, '') <> 'locked' then
    raise exception '只有已锁定的学生月度结算快照可以记录差额调整。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_carryovers c
    where c.source_settlement_id = v_settlement.id
      and coalesce(c.status, 'active') = 'active'
  ) then
    raise exception '该结算已生成有效结转，不能再记录差额调整。';
  end if;

  insert into public.school_student_settlement_adjustments (
    settlement_id,
    student_id,
    year_month,
    business_entity_id,
    adjustment_amount_cny,
    adjustment_source,
    adjustment_reason,
    note,
    status,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_settlement.id,
    v_settlement.student_id,
    v_settlement.year_month,
    v_settlement.business_entity_id,
    p_adjustment_amount_cny,
    v_source,
    v_reason,
    v_note,
    'posted',
    'school',
    v_now,
    v_now
  )
  returning id into v_adjustment_id;

  select
    coalesce(sum(a.adjustment_amount_cny), 0)::numeric,
    string_agg(
      format('%s: %s (%s)', a.adjustment_source, a.adjustment_reason, a.adjustment_amount_cny),
      E'\n'
      order by a.created_at, a.id
    )
  into v_adjustment_total, v_adjustment_reason
  from public.school_student_settlement_adjustments a
  where a.settlement_id = v_settlement.id
    and a.status = 'posted';

  update public.school_student_monthly_settlements m
  set
    adjustment_amount_cny = coalesce(v_adjustment_total, 0),
    adjustment_reason = v_adjustment_reason,
    carryover_amount_cny = coalesce(m.system_difference_cny, 0) + coalesce(v_adjustment_total, 0),
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
    v_adjustment_id as adjustment_id,
    m.created_at,
    m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement.id;
end;
$$;

comment on function public.school_apply_student_monthly_settlement_adjustment(uuid, numeric, text, text, text) is
  'Records a guarded manual CNY adjustment on a locked student monthly settlement snapshot. Writes one adjustment audit row and updates only adjustment_amount_cny, adjustment_reason, carryover_amount_cny, updated_at on the settlement. Rejects unlocked snapshots and snapshots with active downstream carryovers.';

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
    from public.school_student_settlement_adjustments a
    where a.settlement_id = v_settlement.id
      and a.status = 'posted'
  ) then
    raise exception '该结算已有差额调整记录，不能通过撤销锁定重算快照。';
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
  'Soft-unlocks one locked student monthly settlement snapshot. Rejects blank reason, active carryovers, and snapshots with posted difference adjustments. Does not delete rows or mutate lessons, income, accounts, wages, carryovers, or transactions.';

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
    from public.school_student_settlement_adjustments a
    where a.settlement_id = v_settlement.id
      and a.status = 'posted'
  ) then
    raise exception '该结算已有差额调整记录，不能通过重新锁定重算快照。';
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
  'Same-row relocks one unlocked student monthly settlement snapshot by recalculating school_get_student_monthly_settlement_summary. Rejects active carryovers and snapshots with posted difference adjustments. Does not write carryovers, lessons, income, teacher wage, accounts, payments, expenses, or transactions.';
