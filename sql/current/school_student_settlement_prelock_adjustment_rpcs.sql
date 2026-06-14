-- school_student_settlement_prelock_adjustment_rpcs.sql
-- Purpose: Move student monthly settlement difference adjustment to the pre-lock workflow.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and whitelist commit-tested.
--
-- Scope:
-- - Add read RPC public.school_get_student_monthly_settlement_preview.
-- - Add write RPC public.school_set_student_monthly_settlement_draft_adjustment.
-- - Rebuild lock/relock RPCs so active drafts are frozen into the settlement snapshot.
-- - Rebuild the old post-lock adjustment RPC to reject direct locked-snapshot edits.
-- - Does not write lessons, income, teacher wages, payments, expenses, accounts,
--   account transactions, or historical backfill/cleanup data.

create or replace function public.school_get_student_monthly_settlement_preview(
  p_student_id uuid,
  p_year_month text
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
language sql
stable
security definer
set search_path = public
as $$
  with student_base as (
    select
      s.id as student_id,
      s.business_entity_id
    from public.school_students s
    where s.id = p_student_id
      and s.app_type = 'school'
  ),
  summary as (
    select *
    from public.school_get_student_monthly_settlement_summary(p_student_id, p_year_month)
  ),
  draft as (
    select d.*
    from public.school_student_settlement_adjustment_drafts d
    where d.student_id = p_student_id
      and d.year_month = p_year_month
      and d.app_type = 'school'
      and d.status = 'active'
    order by d.updated_at desc, d.created_at desc
    limit 1
  )
  select
    s.student_id,
    sm.year_month,
    sb.business_entity_id,
    sm.exchange_rate,
    sm.carryover_cny,
    sm.planned_hours,
    sm.actual_hours,
    sm.planned_fee_jpy,
    sm.planned_fee_cny,
    sm.planned_total_cny,
    sm.actual_fee_jpy,
    sm.actual_fee_cny,
    sm.received_jpy,
    sm.received_cny,
    sm.received_equivalent_cny,
    sm.final_due_cny,
    coalesce(d.adjustment_amount_cny, 0)::numeric as adjustment_amount_cny,
    d.adjustment_source,
    d.adjustment_reason,
    d.note as adjustment_note,
    (coalesce(sm.final_due_cny, 0) + coalesce(d.adjustment_amount_cny, 0))::numeric as locked_carryover_cny,
    d.id as draft_id,
    d.status as draft_status,
    d.updated_at as draft_updated_at
  from summary sm
  join student_base sb on sb.student_id = sm.student_id
  left join draft d on true
  cross join lateral (select sm.student_id) s;
$$;

comment on function public.school_get_student_monthly_settlement_preview(uuid, text) is
  'Returns student monthly settlement preview including any active pre-lock difference adjustment draft. Core amounts are DB/RPC sourced.';

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
  'Creates or updates one active pre-lock difference adjustment draft for a student/month. The draft participates in preview and is frozen by lock/relock. Rejects locked snapshots.';

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
  'Locks one student/month realtime settlement preview into school_student_monthly_settlements. Active pre-lock adjustment drafts are included in adjustment_amount_cny and carryover_amount_cny, posted to the adjustment audit table, and marked consumed. Does not write carryovers, lessons, income, teacher wage, account, payment, expense, or transaction rows.';

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
  'Same-row relocks one unlocked student monthly settlement snapshot by recalculating preview with any active pre-lock adjustment draft. The draft is posted to the adjustment audit table and marked consumed. Preserves id, student_id, year_month, created_at, unlocked_at, and unlock_reason. Does not write carryovers, lessons, income, teacher wage, accounts, payments, expenses, or transactions.';

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
begin
  raise exception '差额调整请在锁定前录入或修改；已锁定结算的差额调整为只读快照。';
end;
$$;

comment on function public.school_apply_student_monthly_settlement_adjustment(uuid, numeric, text, text, text) is
  'Deprecated guard. Post-lock direct difference adjustment is no longer allowed; adjustments must be entered before lock through school_set_student_monthly_settlement_draft_adjustment and then frozen by lock/relock.';
