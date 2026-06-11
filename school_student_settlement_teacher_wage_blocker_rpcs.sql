-- school_student_settlement_teacher_wage_blocker_rpcs.sql
-- RPCs:
-- - public.school_get_student_monthly_settlement_wage_blockers
-- - public.school_assert_student_monthly_settlement_no_wage_blocker
-- - public.school_lock_student_monthly_settlement
-- - public.school_unlock_student_monthly_settlement
-- - public.school_relock_student_monthly_settlement
-- - public.school_set_student_monthly_settlement_draft_adjustment
--
-- Purpose:
-- - Prevent student monthly settlement changes after related actual lessons
--   enter an effective teacher wage chain.
-- - Expose the same blocker state for settlement-page read-only display.
--
-- Scope:
-- - No schema changes.
-- - No amount formula changes.
-- - No actual_minutes, teacher wage, payment, expense, account, transaction,
--   income, lesson, or reimbursement writes beyond the existing settlement RPC
--   scopes.
-- - Void teacher wage snapshots are ignored as blockers.

create or replace function public.school_get_student_monthly_settlement_wage_blockers(
  p_year_month text,
  p_student_id uuid default null
)
returns table (
  student_id uuid,
  year_month text,
  wage_business_names text,
  active_wage_lock_count integer,
  wage_detail_count integer,
  payment_request_count integer,
  paid_payment_request_count integer,
  expense_count integer,
  account_transaction_count integer,
  blocker_level text,
  blocker_reason text
)
language sql
stable
security definer
set search_path = public
as $$
  with active_links as (
    select
      l.student_id,
      l.year_month,
      w.id as wage_lock_id,
      d.id as wage_detail_id,
      coalesce(nullif(trim(w.business_name), ''), '未设置业务归属') as wage_business_name,
      pr.id as payment_request_id,
      pr.status as payment_request_status,
      e.id as expense_id,
      atx.id as account_transaction_id
    from public.school_lesson_records l
    join public.school_teacher_wage_lock_details d
      on d.lesson_record_id = l.id
    join public.school_teacher_wage_locks w
      on w.id = d.lock_id
    left join public.school_payment_requests pr
      on pr.source_type = 'teacher_wage'
      and pr.source_id = w.id
    left join public.school_expense_records e
      on e.expense_category = 'teacher_wage'
      and (
        e.id = pr.paid_expense_id
        or e.salary_payment_id = pr.id
      )
    left join public.school_account_transactions atx
      on atx.id = pr.paid_account_transaction_id
      or (
        atx.related_table = 'school_expense_records'
        and atx.related_id = e.id
      )
      or (
        atx.related_table = 'school_payment_requests'
        and atx.related_id = pr.id
      )
    where l.app_type = 'school'
      and l.lesson_type = 'actual'
      and l.student_id is not null
      and l.year_month = p_year_month
      and (p_student_id is null or l.student_id = p_student_id)
      and coalesce(w.status, '') <> 'void'
      and w.voided_at is null
  ),
  aggregated as (
    select
      al.student_id,
      al.year_month,
      string_agg(distinct al.wage_business_name, '、') as wage_business_names,
      count(distinct al.wage_lock_id)::integer as active_wage_lock_count,
      count(distinct al.wage_detail_id)::integer as wage_detail_count,
      count(distinct al.payment_request_id)::integer as payment_request_count,
      count(distinct al.payment_request_id) filter (
        where al.payment_request_status = 'paid'
      )::integer as paid_payment_request_count,
      count(distinct al.expense_id)::integer as expense_count,
      count(distinct al.account_transaction_id)::integer as account_transaction_count
    from active_links al
    group by al.student_id, al.year_month
  )
  select
    a.student_id,
    a.year_month,
    a.wage_business_names,
    a.active_wage_lock_count,
    a.wage_detail_count,
    a.payment_request_count,
    a.paid_payment_request_count,
    a.expense_count,
    a.account_transaction_count,
    case
      when a.account_transaction_count > 0
        or a.expense_count > 0
        or a.paid_payment_request_count > 0
        then 'payment_completed'
      when a.payment_request_count > 0 then 'payment_requested'
      else 'wage_snapshot'
    end as blocker_level,
    case
      when a.account_transaction_count > 0
        or a.expense_count > 0
        or a.paid_payment_request_count > 0
        then format(
          '老师工资已支付，涉及%s个工资快照、%s条工资明细、%s个支付请求、%s条支出、%s条账户流水（业务归属：%s）。',
          a.active_wage_lock_count,
          a.wage_detail_count,
          a.payment_request_count,
          a.expense_count,
          a.account_transaction_count,
          coalesce(a.wage_business_names, '未设置')
        )
      when a.payment_request_count > 0 then format(
        '已生成工资支付请求，涉及%s个工资快照、%s条工资明细、%s个支付请求（业务归属：%s）。',
        a.active_wage_lock_count,
        a.wage_detail_count,
        a.payment_request_count,
        coalesce(a.wage_business_names, '未设置')
      )
      else format(
        '已生成老师工资快照，涉及%s个工资快照、%s条工资明细（业务归属：%s）。如需变更，请先撤销未支付工资快照。',
        a.active_wage_lock_count,
        a.wage_detail_count,
        coalesce(a.wage_business_names, '未设置')
      )
    end as blocker_reason
  from aggregated a
  where a.active_wage_lock_count > 0;
$$;

comment on function public.school_get_student_monthly_settlement_wage_blockers(text, uuid) is
  'Returns downstream teacher-wage blockers for student monthly settlement changes. Active non-void wage snapshots, any teacher_wage payment request, paid expense, or account transaction are reported by student/month.';

create or replace function public.school_assert_student_monthly_settlement_no_wage_blocker(
  p_student_id uuid,
  p_year_month text,
  p_action text default '变更学生月度结算'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_blocker record;
begin
  select *
  into v_blocker
  from public.school_get_student_monthly_settlement_wage_blockers(p_year_month, p_student_id)
  limit 1;

  if found then
    raise exception '%已被后续老师工资链路引用：% 请先按受控流程处理老师工资快照/支付请求，不能从学生月度结算侧间接改动已进入工资链路的课时。',
      coalesce(nullif(trim(p_action), ''), '变更学生月度结算'),
      v_blocker.blocker_reason;
  end if;
end;
$$;

comment on function public.school_assert_student_monthly_settlement_no_wage_blocker(uuid, text, text) is
  'Internal settlement write guard. Raises when a student/month is referenced by active non-void teacher wage snapshots, teacher_wage payment requests, paid expenses, or account transactions.';

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
  v_now timestamptz := now();
  v_preview record;
  v_settlement_id uuid;
  v_adjustment_reason text;
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_year_month is null or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效，请使用 YYYY-MM。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements m
    where m.student_id = p_student_id
      and m.year_month = v_year_month
  ) then
    raise exception '该学生月份已存在结算快照，不能重复锁定。';
  end if;

  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id,
    v_year_month,
    '锁定学生月度结算'
  );

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
  into v_preview
  from public.school_get_student_monthly_settlement_preview(p_student_id, v_year_month);

  if not found then
    raise exception '无法计算该学生月份的结算预览。';
  end if;

  if v_preview.business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能锁定结算。';
  end if;

  if coalesce(v_preview.adjustment_amount_cny, 0) <> 0
     or nullif(trim(coalesce(v_preview.adjustment_reason, '')), '') is not null
     or nullif(trim(coalesce(v_preview.adjustment_note, '')), '') is not null then
    v_adjustment_reason := format(
      '%s: %s (%s)',
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, ''),
      coalesce(v_preview.adjustment_amount_cny, 0)
    );
  else
    v_adjustment_reason := null;
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
    v_preview.business_entity_id,
    coalesce(v_preview.exchange_rate, 0),
    coalesce(v_preview.planned_fee_jpy, 0),
    coalesce(v_preview.planned_fee_cny, 0),
    coalesce(v_preview.actual_fee_jpy, 0),
    coalesce(v_preview.actual_fee_cny, 0),
    coalesce(v_preview.carryover_cny, 0),
    coalesce(v_preview.received_jpy, 0),
    coalesce(v_preview.received_cny, 0),
    coalesce(v_preview.received_equivalent_cny, 0),
    coalesce(v_preview.final_due_cny, 0),
    coalesce(v_preview.adjustment_amount_cny, 0),
    v_adjustment_reason,
    coalesce(v_preview.locked_carryover_cny, coalesce(v_preview.final_due_cny, 0)),
    'locked',
    v_now,
    v_note,
    v_now,
    v_now
  )
  returning id into v_settlement_id;

  if v_preview.draft_id is not null then
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
      v_settlement_id,
      p_student_id,
      v_year_month,
      v_preview.business_entity_id,
      coalesce(v_preview.adjustment_amount_cny, 0),
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, '锁定前差额调整'),
      v_preview.adjustment_note,
      'posted',
      'school',
      v_now,
      v_now
    );

    update public.school_student_settlement_adjustment_drafts d
    set
      status = 'consumed',
      settlement_id = v_settlement_id,
      consumed_at = v_now,
      updated_by = current_user,
      updated_at = v_now
    where d.id = v_preview.draft_id;
  end if;

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
  'Locks one student/month realtime settlement preview into school_student_monthly_settlements. Active pre-lock adjustment drafts are included and consumed. Rejects downstream active teacher wage blockers.';

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

  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id,
    v_settlement.year_month,
    '撤销学生月度结算'
  );

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
  'Soft-unlocks one locked student monthly settlement snapshot. Rejects blank reason, posted adjustments, active carryovers, and downstream active teacher wage blockers.';

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
  v_preview record;
  v_adjustment_reason text;
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

  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id,
    v_settlement.year_month,
    '重新锁定学生月度结算'
  );

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
  into v_preview
  from public.school_get_student_monthly_settlement_preview(
    v_settlement.student_id,
    v_settlement.year_month
  );

  if not found then
    raise exception '无法计算该学生月份的结算预览。';
  end if;

  if v_preview.business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能重新锁定结算。';
  end if;

  if coalesce(v_preview.adjustment_amount_cny, 0) <> 0
     or nullif(trim(coalesce(v_preview.adjustment_reason, '')), '') is not null
     or nullif(trim(coalesce(v_preview.adjustment_note, '')), '') is not null then
    v_adjustment_reason := format(
      '%s: %s (%s)',
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, ''),
      coalesce(v_preview.adjustment_amount_cny, 0)
    );
  else
    v_adjustment_reason := null;
  end if;

  update public.school_student_monthly_settlements m
  set
    business_entity_id = v_preview.business_entity_id,
    preset_exchange_rate = coalesce(v_preview.exchange_rate, 0),
    planned_lesson_fee_jpy = coalesce(v_preview.planned_fee_jpy, 0),
    planned_lesson_fee_cny = coalesce(v_preview.planned_fee_cny, 0),
    actual_lesson_fee_jpy = coalesce(v_preview.actual_fee_jpy, 0),
    actual_lesson_fee_cny = coalesce(v_preview.actual_fee_cny, 0),
    previous_balance_cny = coalesce(v_preview.carryover_cny, 0),
    received_jpy = coalesce(v_preview.received_jpy, 0),
    received_cny = coalesce(v_preview.received_cny, 0),
    received_equivalent_cny = coalesce(v_preview.received_equivalent_cny, 0),
    system_difference_cny = coalesce(v_preview.final_due_cny, 0),
    adjustment_amount_cny = coalesce(v_preview.adjustment_amount_cny, 0),
    adjustment_reason = v_adjustment_reason,
    carryover_amount_cny = coalesce(v_preview.locked_carryover_cny, coalesce(v_preview.final_due_cny, 0)),
    settlement_status = 'locked',
    locked_at = v_now,
    note = v_note,
    updated_at = v_now
  where m.id = v_settlement.id;

  if v_preview.draft_id is not null then
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
      v_preview.business_entity_id,
      coalesce(v_preview.adjustment_amount_cny, 0),
      coalesce(v_preview.adjustment_source, 'manual'),
      coalesce(v_preview.adjustment_reason, '重新锁定前差额调整'),
      v_preview.adjustment_note,
      'posted',
      'school',
      v_now,
      v_now
    );

    update public.school_student_settlement_adjustment_drafts d
    set
      status = 'consumed',
      settlement_id = v_settlement.id,
      consumed_at = v_now,
      updated_by = current_user,
      updated_at = v_now
    where d.id = v_preview.draft_id;
  end if;

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
  'Same-row relocks one unlocked student monthly settlement snapshot. Rejects posted adjustments, active carryovers, and downstream active teacher wage blockers.';

create or replace function public.school_set_student_monthly_settlement_draft_adjustment(
  p_student_id uuid,
  p_year_month text,
  p_adjustment_amount_cny numeric,
  p_adjustment_source text default 'manual',
  p_adjustment_reason text default null,
  p_note text default null
)
returns table (
  student_id uuid,
  year_month text,
  business_entity_id uuid,
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
  adjustment_amount_cny numeric,
  adjustment_source text,
  adjustment_reason text,
  adjustment_note text,
  locked_carryover_cny numeric,
  draft_id uuid,
  draft_status text,
  draft_updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_source text := nullif(trim(coalesce(p_adjustment_source, '')), '');
  v_reason text := nullif(trim(coalesce(p_adjustment_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_business_entity_id uuid;
  v_existing_status text;
  v_now timestamptz := now();
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_year_month is null or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效，请使用 YYYY-MM。';
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

  select s.business_entity_id
  into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id
    and s.app_type = 'school';

  if not found then
    raise exception '学生不存在或不属于学校业务。';
  end if;

  if v_business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能记录差额调整。';
  end if;

  select m.settlement_status
  into v_existing_status
  from public.school_student_monthly_settlements m
  where m.student_id = p_student_id
    and m.year_month = v_year_month;

  if found and coalesce(v_existing_status, '') <> 'unlocked' then
    raise exception '该学生月份已锁定，差额调整只能只读查看，不能再修改。';
  end if;

  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id,
    v_year_month,
    '保存学生月度结算差额调整'
  );

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
    raise exception '该学生月份没有可结算的课时或学费收入，不能记录差额调整。';
  end if;

  insert into public.school_student_settlement_adjustment_drafts (
    student_id,
    year_month,
    business_entity_id,
    adjustment_amount_cny,
    adjustment_source,
    adjustment_reason,
    note,
    status,
    settlement_id,
    app_type,
    created_by,
    updated_by,
    consumed_at,
    created_at,
    updated_at
  )
  values (
    p_student_id,
    v_year_month,
    v_business_entity_id,
    p_adjustment_amount_cny,
    v_source,
    v_reason,
    v_note,
    'active',
    null,
    'school',
    current_user,
    current_user,
    null,
    v_now,
    v_now
  )
  on conflict on constraint school_student_settlement_adjustment_drafts_student_month_key
  do update set
    business_entity_id = excluded.business_entity_id,
    adjustment_amount_cny = excluded.adjustment_amount_cny,
    adjustment_source = excluded.adjustment_source,
    adjustment_reason = excluded.adjustment_reason,
    note = excluded.note,
    status = 'active',
    settlement_id = null,
    updated_by = current_user,
    consumed_at = null,
    updated_at = v_now;

  return query
  select *
  from public.school_get_student_monthly_settlement_preview(p_student_id, v_year_month);
end;
$$;

comment on function public.school_set_student_monthly_settlement_draft_adjustment(uuid, text, numeric, text, text, text) is
  'Creates or updates one active pre-lock difference adjustment draft for a student/month. Rejects locked snapshots and downstream active teacher wage blockers.';
