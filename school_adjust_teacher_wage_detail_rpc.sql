-- school_adjust_teacher_wage_detail_rpc.sql
-- RPC: public.school_adjust_teacher_wage_detail
-- Purpose: Manually adjust one teacher wage snapshot detail with an audit row.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.86.0-teacher-wage-detail-adjustment-rpc-20260611
--
-- Scope:
-- - Update exactly one public.school_teacher_wage_lock_details row.
-- - Recalculate the parent public.school_teacher_wage_locks aggregate totals
--   from all saved detail rows in that snapshot.
-- - Insert one public.school_teacher_wage_detail_adjustments audit row.
--
-- Guardrails:
-- - Reject missing/blank reason.
-- - Reject negative or abnormal values.
-- - Reject voided/non-locked wage snapshots.
-- - Reject any wage snapshot that already has a teacher_wage payment request.
-- - Do not write payment requests, expenses, accounts, account transactions,
--   income, student settlements, lessons, or wage rules.
--
-- Verification:
-- - Rollback test used temporary codex-test wage lock
--   92000000-0000-4000-8000-000000086001 and detail
--   92000000-0000-4000-8000-000000086101, verified success, audit, parent
--   total recalculation, payment-request guard, then rolled back with zero
--   residue.
-- - Whitelist commit test used codex-test wage lock
--   92000000-0000-4000-8000-000000086002 and detail
--   92000000-0000-4000-8000-000000086102, creating audit
--   fe6b84c2-d0f1-46b7-a27f-e91da3850ad6. Protected payment, expense,
--   account transaction, income, and student settlement counts stayed unchanged.

create or replace function public.school_adjust_teacher_wage_detail(
  p_wage_detail_id uuid,
  p_pay_hours numeric,
  p_transport_fee_jpy numeric,
  p_classroom_fee_jpy numeric,
  p_reason text
)
returns table (
  adjustment_id uuid,
  wage_lock_id uuid,
  wage_detail_id uuid,
  pay_hours numeric,
  lesson_wage_jpy numeric,
  lesson_wage_cny numeric,
  transport_fee_jpy numeric,
  classroom_fee_jpy numeric,
  total_jpy numeric,
  total_cny numeric,
  lock_pay_hours numeric,
  lock_lesson_wage_jpy numeric,
  lock_lesson_wage_cny numeric,
  lock_fee_jpy numeric,
  lock_total_jpy numeric,
  lock_total_cny numeric,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_detail public.school_teacher_wage_lock_details%rowtype;
  v_lock public.school_teacher_wage_locks%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_pay_hours numeric := p_pay_hours;
  v_transport_fee_jpy numeric := round(coalesce(p_transport_fee_jpy, 0));
  v_classroom_fee_jpy numeric := round(coalesce(p_classroom_fee_jpy, 0));
  v_hourly_rate_jpy numeric := 0;
  v_exchange_rate numeric := 0;
  v_new_lesson_wage_jpy numeric := 0;
  v_new_lesson_wage_cny numeric := 0;
  v_new_total_jpy numeric := 0;
  v_new_total_cny numeric := 0;
  v_new_lock_pay_hours numeric := 0;
  v_new_lock_lesson_wage_jpy numeric := 0;
  v_new_lock_lesson_wage_cny numeric := 0;
  v_new_lock_fee_jpy numeric := 0;
  v_new_lock_total_jpy numeric := 0;
  v_new_lock_total_cny numeric := 0;
  v_adjustment_id uuid;
  v_created_at timestamptz;
begin
  if p_wage_detail_id is null then
    raise exception '请选择要调整的工资明细。';
  end if;

  if v_reason is null then
    raise exception '请输入调整备注。';
  end if;

  if v_pay_hours is null then
    raise exception '请输入结算课时。';
  end if;

  if v_pay_hours < 0 or v_pay_hours > 24 then
    raise exception '结算课时必须在 0 到 24 之间。当前值：%', v_pay_hours;
  end if;

  if v_transport_fee_jpy < 0 or v_transport_fee_jpy > 1000000 then
    raise exception '交通费必须在 0 到 1,000,000 JPY 之间。当前值：%', v_transport_fee_jpy;
  end if;

  if v_classroom_fee_jpy < 0 or v_classroom_fee_jpy > 1000000 then
    raise exception '教室费必须在 0 到 1,000,000 JPY 之间。当前值：%', v_classroom_fee_jpy;
  end if;

  select *
    into v_detail
    from public.school_teacher_wage_lock_details d
   where d.id = p_wage_detail_id
   for update;

  if not found then
    raise exception '工资明细不存在：%。', p_wage_detail_id;
  end if;

  select *
    into v_lock
    from public.school_teacher_wage_locks w
   where w.id = v_detail.lock_id
   for update;

  if not found then
    raise exception '工资快照不存在：%。', v_detail.lock_id;
  end if;

  if coalesce(v_lock.status, '') <> 'locked' then
    raise exception '只有已生成且未作废的工资快照可以调整。当前状态：%。', v_lock.status;
  end if;

  if v_lock.voided_at is not null then
    raise exception '已作废的工资快照不能调整：%。', v_lock.id;
  end if;

  if exists (
    select 1
    from public.school_payment_requests p
    where p.source_type = 'teacher_wage'
      and p.source_id = v_lock.id
  ) then
    raise exception '该工资快照已生成支付请求，不能直接调整。请先按支付流程处理或另行走受控修正流程。';
  end if;

  if coalesce(v_detail.is_no_wage, false) = true
     or coalesce(v_detail.settlement_type, '') = 'no_wage' then
    v_new_lesson_wage_jpy := 0;
  else
    if coalesce(v_detail.pay_hours, 0) <= 0 then
      if v_pay_hours = 0 then
        v_new_lesson_wage_jpy := 0;
      else
        raise exception '当前明细结算课时为 0，无法从工资快照推导时给，不能自动调整为正课时。';
      end if;
    else
      v_hourly_rate_jpy := coalesce(v_detail.lesson_wage_jpy, 0) / v_detail.pay_hours;
      v_new_lesson_wage_jpy := round(v_pay_hours * v_hourly_rate_jpy);
    end if;
  end if;

  v_exchange_rate := coalesce(nullif(v_detail.exchange_rate, 0), nullif(v_lock.exchange_rate, 0), 0);
  v_new_total_jpy := v_new_lesson_wage_jpy + v_transport_fee_jpy + v_classroom_fee_jpy;
  v_new_lesson_wage_cny := round(v_new_lesson_wage_jpy * v_exchange_rate * 100) / 100;
  v_new_total_cny := round(v_new_total_jpy * v_exchange_rate * 100) / 100;

  if v_pay_hours is not distinct from coalesce(v_detail.pay_hours, 0)
     and v_transport_fee_jpy is not distinct from coalesce(v_detail.transport_fee_jpy, 0)
     and v_classroom_fee_jpy is not distinct from coalesce(v_detail.classroom_fee_jpy, 0) then
    raise exception '调整前后数值没有变化。';
  end if;

  update public.school_teacher_wage_lock_details d
     set pay_hours = v_pay_hours,
         lesson_wage_jpy = v_new_lesson_wage_jpy,
         lesson_wage_cny = v_new_lesson_wage_cny,
         transport_fee_jpy = v_transport_fee_jpy,
         classroom_fee_jpy = v_classroom_fee_jpy,
         total_jpy = v_new_total_jpy,
         total_cny = v_new_total_cny
   where d.id = v_detail.id;

  select
    coalesce(sum(d.pay_hours), 0),
    coalesce(sum(d.lesson_wage_jpy), 0),
    coalesce(sum(d.lesson_wage_cny), 0),
    coalesce(sum(coalesce(d.transport_fee_jpy, 0) + coalesce(d.classroom_fee_jpy, 0)), 0),
    coalesce(sum(d.total_jpy), 0),
    coalesce(sum(d.total_cny), 0)
  into
    v_new_lock_pay_hours,
    v_new_lock_lesson_wage_jpy,
    v_new_lock_lesson_wage_cny,
    v_new_lock_fee_jpy,
    v_new_lock_total_jpy,
    v_new_lock_total_cny
  from public.school_teacher_wage_lock_details d
  where d.lock_id = v_lock.id;

  update public.school_teacher_wage_locks w
     set pay_hours = v_new_lock_pay_hours,
         lesson_wage_jpy = v_new_lock_lesson_wage_jpy,
         lesson_wage_cny = v_new_lock_lesson_wage_cny,
         fee_jpy = v_new_lock_fee_jpy,
         total_jpy = v_new_lock_total_jpy,
         total_cny = v_new_lock_total_cny,
         updated_at = now()
   where w.id = v_lock.id;

  insert into public.school_teacher_wage_detail_adjustments (
    wage_lock_id,
    wage_detail_id,
    reason,
    old_pay_hours,
    new_pay_hours,
    old_lesson_wage_jpy,
    new_lesson_wage_jpy,
    old_lesson_wage_cny,
    new_lesson_wage_cny,
    old_transport_fee_jpy,
    new_transport_fee_jpy,
    old_classroom_fee_jpy,
    new_classroom_fee_jpy,
    old_total_jpy,
    new_total_jpy,
    old_total_cny,
    new_total_cny,
    old_lock_pay_hours,
    new_lock_pay_hours,
    old_lock_lesson_wage_jpy,
    new_lock_lesson_wage_jpy,
    old_lock_lesson_wage_cny,
    new_lock_lesson_wage_cny,
    old_lock_fee_jpy,
    new_lock_fee_jpy,
    old_lock_total_jpy,
    new_lock_total_jpy,
    old_lock_total_cny,
    new_lock_total_cny
  )
  values (
    v_lock.id,
    v_detail.id,
    v_reason,
    coalesce(v_detail.pay_hours, 0),
    v_pay_hours,
    coalesce(v_detail.lesson_wage_jpy, 0),
    v_new_lesson_wage_jpy,
    coalesce(v_detail.lesson_wage_cny, 0),
    v_new_lesson_wage_cny,
    coalesce(v_detail.transport_fee_jpy, 0),
    v_transport_fee_jpy,
    coalesce(v_detail.classroom_fee_jpy, 0),
    v_classroom_fee_jpy,
    coalesce(v_detail.total_jpy, 0),
    v_new_total_jpy,
    coalesce(v_detail.total_cny, 0),
    v_new_total_cny,
    coalesce(v_lock.pay_hours, 0),
    v_new_lock_pay_hours,
    coalesce(v_lock.lesson_wage_jpy, 0),
    v_new_lock_lesson_wage_jpy,
    coalesce(v_lock.lesson_wage_cny, 0),
    v_new_lock_lesson_wage_cny,
    coalesce(v_lock.fee_jpy, 0),
    v_new_lock_fee_jpy,
    coalesce(v_lock.total_jpy, 0),
    v_new_lock_total_jpy,
    coalesce(v_lock.total_cny, 0),
    v_new_lock_total_cny
  )
  returning
    school_teacher_wage_detail_adjustments.id,
    school_teacher_wage_detail_adjustments.created_at
  into v_adjustment_id, v_created_at;

  return query
  select
    v_adjustment_id,
    v_lock.id,
    v_detail.id,
    v_pay_hours,
    v_new_lesson_wage_jpy,
    v_new_lesson_wage_cny,
    v_transport_fee_jpy,
    v_classroom_fee_jpy,
    v_new_total_jpy,
    v_new_total_cny,
    v_new_lock_pay_hours,
    v_new_lock_lesson_wage_jpy,
    v_new_lock_lesson_wage_cny,
    v_new_lock_fee_jpy,
    v_new_lock_total_jpy,
    v_new_lock_total_cny,
    v_created_at;
end;
$$;

comment on function public.school_adjust_teacher_wage_detail(
  uuid,
  numeric,
  numeric,
  numeric,
  text
) is
  'Adjusts one teacher wage snapshot detail with a required reason, recalculates the parent wage snapshot totals from saved details, and writes an append-only audit row. Rejects voided/non-locked snapshots and snapshots with any teacher_wage payment request.';

grant execute on function public.school_adjust_teacher_wage_detail(
  uuid,
  numeric,
  numeric,
  numeric,
  text
) to anon, authenticated;
