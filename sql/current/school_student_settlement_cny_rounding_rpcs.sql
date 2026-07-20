-- school_student_settlement_cny_rounding_rpcs.sql
-- Purpose: Normalize student monthly settlement CNY values to 2 decimal places in DB/RPC.
-- Status: EXECUTED ON SUPABASE 2026-06-28 via SCHOOL_SUPABASE_DB_URL.
--
-- Scope:
-- - Replaces public.school_get_student_monthly_settlement_summary so all
--   externally returned CNY amounts are rounded to 2 decimal places.
-- - Replaces public.school_get_student_monthly_settlement_preview so draft
--   adjustment and locked carryover preview use the same 2-decimal CNY basis.
-- - Replaces public.school_set_student_monthly_settlement_draft_adjustment so
--   persisted draft adjustment CNY amounts are rounded to 2 decimal places.
-- - Does not modify historical data, lessons, income, teacher wage, accounts,
--   payments, expenses, account transactions, or carryover rows.

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
      coalesce(ls.actual_fee_jpy, 0)::numeric as actual_fee_jpy,
      (coalesce(ls.actual_fee_jpy, 0) * sb.exchange_rate)::numeric as actual_fee_cny,
      coalesce(inc.received_jpy, 0)::numeric as received_jpy,
      coalesce(inc.received_cny, 0)::numeric as received_cny,
      (coalesce(inc.received_cny, 0) + coalesce(inc.received_jpy, 0) * sb.exchange_rate)::numeric as received_equivalent_cny
    from student_base sb
    cross join carryover c
    cross join lesson_summary ls
    cross join income_summary inc
  ),
  rounded as (
    select
      calc.student_id,
      calc.year_month,
      calc.exchange_rate,
      round(calc.carryover_cny, 2)::numeric as carryover_cny,
      calc.planned_hours,
      calc.actual_hours,
      calc.planned_fee_jpy,
      round(calc.planned_fee_cny, 2)::numeric as planned_fee_cny,
      calc.actual_fee_jpy,
      round(calc.actual_fee_cny, 2)::numeric as actual_fee_cny,
      calc.received_jpy,
      round(calc.received_cny, 2)::numeric as received_cny,
      round(calc.received_equivalent_cny, 2)::numeric as received_equivalent_cny
    from calculated calc
  )
  select
    r.student_id,
    r.year_month,
    r.exchange_rate,
    r.carryover_cny,
    r.planned_hours,
    r.actual_hours,
    r.planned_fee_jpy,
    r.planned_fee_cny,
    round(r.planned_fee_cny + r.carryover_cny, 2)::numeric as planned_total_cny,
    r.actual_fee_jpy,
    r.actual_fee_cny,
    r.received_jpy,
    r.received_cny,
    r.received_equivalent_cny,
    round(r.planned_fee_cny + r.carryover_cny - r.received_equivalent_cny, 2)::numeric as final_due_cny,
    coalesce(
      (select round(l.carryover_amount_cny, 2) from locked l),
      round(r.planned_fee_cny + r.carryover_cny - r.received_equivalent_cny, 2)
    )::numeric as locked_carryover_cny
  from rounded r;
$$;

comment on function public.school_get_student_monthly_settlement_summary(uuid, text) is
  'Returns student monthly settlement summary with CNY amounts rounded to 2 decimals. Student amount due is based on active planned lesson fees plus carryover less received tuition; actual lesson fees remain fulfilment display values and do not turn cancelled or makeup credit into refunds or extra tuition. Soft-voided planned lessons are excluded. Carryover priority: explicit active carryover row, previous locked monthly settlement carryover, student fallback previous_balance.';

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
    round(coalesce(d.adjustment_amount_cny, 0), 2)::numeric as adjustment_amount_cny,
    d.adjustment_source,
    d.adjustment_reason,
    d.note as adjustment_note,
    round(coalesce(sm.final_due_cny, 0) + round(coalesce(d.adjustment_amount_cny, 0), 2), 2)::numeric as locked_carryover_cny,
    d.id as draft_id,
    d.status as draft_status,
    d.updated_at as draft_updated_at
  from summary sm
  join student_base sb on sb.student_id = sm.student_id
  left join draft d on true
  cross join lateral (select sm.student_id) s;
$$;

comment on function public.school_get_student_monthly_settlement_preview(uuid, text) is
  'Returns student monthly settlement preview including any active pre-lock difference adjustment draft. Core CNY amounts are rounded to 2 decimals in DB/RPC.';

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
  v_adjustment_amount_cny numeric := round(p_adjustment_amount_cny, 2);
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
    v_adjustment_amount_cny,
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
  'Creates or updates one active pre-lock difference adjustment draft for a student/month. Adjustment CNY amount is rounded to 2 decimals in DB/RPC. Rejects locked snapshots and downstream active teacher wage blockers.';
