-- school_void_teacher_wage_lock_rpc.sql
-- RPC: public.school_void_teacher_wage_lock
-- Purpose:
--   Guardedly void one unpaid teacher wage snapshot while preserving the
--   snapshot and detail rows for audit.
--
-- Scope:
--   - Update exactly one public.school_teacher_wage_locks row to status = void.
--   - Write void_reason / voided_by / void_source audit fields.
--   - Do not delete wage details.
--   - Do not update lessons, actual_minutes, payment requests, expenses,
--     account transactions, accounts, income, or settlements.
--
-- Guardrails:
--   - Reject missing/blank reason.
--   - Reject already voided snapshots.
--   - Reject non-locked snapshots.
--   - Reject any teacher_wage payment request, regardless of request status.
--   - Reject any linked teacher_wage expense/account-transaction evidence.
--   - Verify detail/header count and totals before voiding.

create or replace function public.school_void_teacher_wage_lock(
  p_wage_lock_id uuid,
  p_reason text,
  p_operator text default null,
  p_source text default 'v2_wage_detail'
)
returns table (
  wage_lock_id uuid,
  settlement_month text,
  teacher_id uuid,
  teacher_name text,
  business_entity_id uuid,
  business_name text,
  status text,
  voided_at timestamptz,
  void_reason text,
  voided_by text,
  void_source text,
  detail_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lock public.school_teacher_wage_locks%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_operator text := nullif(trim(coalesce(p_operator, '')), '');
  v_source text := coalesce(nullif(trim(coalesce(p_source, '')), ''), 'v2_wage_detail');
  v_now timestamptz := now();
  v_detail_count integer;
  v_detail_total_jpy numeric;
  v_detail_total_cny numeric;
  v_detail_pay_hours numeric;
  v_detail_lesson_wage_jpy numeric;
  v_detail_lesson_wage_cny numeric;
  v_detail_fee_jpy numeric;
  v_bad_detail_scope_count integer;
  v_payment_request_count integer;
  v_paid_expense_via_payment_count integer;
  v_salary_payment_expense_count integer;
  v_account_tx_via_payment_count integer;
  v_direct_wage_account_tx_count integer;
begin
  if p_wage_lock_id is null then
    raise exception '请选择要撤销的工资快照。';
  end if;

  if v_reason is null then
    raise exception '请输入撤销原因。';
  end if;

  select *
    into v_lock
    from public.school_teacher_wage_locks w
   where w.id = p_wage_lock_id
   for update;

  if not found then
    raise exception '工资快照不存在：%。', p_wage_lock_id;
  end if;

  if coalesce(v_lock.status, '') = 'void' or v_lock.voided_at is not null then
    raise exception '该工资快照已经作废，不能重复撤销。';
  end if;

  if coalesce(v_lock.status, '') <> 'locked' then
    raise exception '只有已生成且未作废的工资快照可以撤销。当前状态：%。', v_lock.status;
  end if;

  if v_lock.teacher_id is null
     or nullif(trim(coalesce(v_lock.teacher_name, '')), '') is null
     or v_lock.business_entity_id is null
     or nullif(trim(coalesce(v_lock.business_name, '')), '') is null
     or v_lock.settlement_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '工资快照老师、月份或业务归属信息不完整，不能撤销。';
  end if;

  select
    count(*)::integer,
    coalesce(sum(d.total_jpy), 0),
    coalesce(sum(d.total_cny), 0),
    coalesce(sum(d.pay_hours), 0),
    coalesce(sum(d.lesson_wage_jpy), 0),
    coalesce(sum(d.lesson_wage_cny), 0),
    coalesce(sum(coalesce(d.transport_fee_jpy, 0) + coalesce(d.classroom_fee_jpy, 0)), 0),
    count(*) filter (
      where d.business_entity_id is distinct from v_lock.business_entity_id
    )::integer
  into
    v_detail_count,
    v_detail_total_jpy,
    v_detail_total_cny,
    v_detail_pay_hours,
    v_detail_lesson_wage_jpy,
    v_detail_lesson_wage_cny,
    v_detail_fee_jpy,
    v_bad_detail_scope_count
  from public.school_teacher_wage_lock_details d
  where d.lock_id = v_lock.id;

  if v_detail_count <= 0 then
    raise exception '工资快照没有明细，不能通过本流程撤销。';
  end if;

  if v_detail_count <> coalesce(v_lock.lesson_count, 0)
    or v_detail_total_jpy <> coalesce(v_lock.total_jpy, 0)
    or v_detail_total_cny <> coalesce(v_lock.total_cny, 0)
    or v_detail_pay_hours <> coalesce(v_lock.pay_hours, 0)
    or v_detail_lesson_wage_jpy <> coalesce(v_lock.lesson_wage_jpy, 0)
    or v_detail_lesson_wage_cny <> coalesce(v_lock.lesson_wage_cny, 0)
    or v_detail_fee_jpy <> coalesce(v_lock.fee_jpy, 0)
    or v_bad_detail_scope_count <> 0 then
    raise exception '工资快照主表与明细不一致，不能通过本流程撤销。';
  end if;

  select count(*)
    into v_payment_request_count
    from public.school_payment_requests p
   where p.source_type = 'teacher_wage'
     and p.source_id = v_lock.id;

  if v_payment_request_count > 0 then
    raise exception '该工资快照已生成支付请求，不能撤销。';
  end if;

  select count(*)
    into v_paid_expense_via_payment_count
    from public.school_expense_records e
    join public.school_payment_requests p
      on p.paid_expense_id = e.id
   where p.source_type = 'teacher_wage'
     and p.source_id = v_lock.id;

  select count(*)
    into v_salary_payment_expense_count
    from public.school_expense_records e
   where e.salary_payment_id = v_lock.id;

  select count(*)
    into v_account_tx_via_payment_count
    from public.school_account_transactions t
    join public.school_payment_requests p
      on p.paid_account_transaction_id = t.id
        or p.reversal_transaction_id = t.id
   where p.source_type = 'teacher_wage'
     and p.source_id = v_lock.id;

  select count(*)
    into v_direct_wage_account_tx_count
    from public.school_account_transactions t
   where t.related_table in ('school_teacher_wage_locks', 'teacher_wage')
     and t.related_id = v_lock.id;

  if v_paid_expense_via_payment_count > 0
    or v_salary_payment_expense_count > 0
    or v_account_tx_via_payment_count > 0
    or v_direct_wage_account_tx_count > 0 then
    raise exception '该工资快照已有支出或账户流水依赖，不能撤销。';
  end if;

  update public.school_teacher_wage_locks w
     set status = 'void',
         voided_at = v_now,
         void_reason = v_reason,
         voided_by = coalesce(v_operator, nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
         void_source = v_source,
         updated_at = v_now
   where w.id = v_lock.id;

  return query
  select
    w.id,
    w.settlement_month,
    w.teacher_id,
    w.teacher_name,
    w.business_entity_id,
    w.business_name,
    w.status,
    w.voided_at,
    w.void_reason,
    w.voided_by,
    w.void_source,
    v_detail_count
  from public.school_teacher_wage_locks w
  where w.id = v_lock.id;
end;
$$;

comment on function public.school_void_teacher_wage_lock(uuid, text, text, text) is
  'Voids one unpaid teacher wage snapshot with reason/operator/source audit. Rejects any payment request, expense, or account-transaction dependency and preserves wage detail rows.';

grant execute on function public.school_void_teacher_wage_lock(uuid, text, text, text) to anon, authenticated;
