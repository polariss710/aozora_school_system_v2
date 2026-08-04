-- school_teacher_wage_rejected_expense_void_guard.sql
-- Version: v10.3.66 allow void rejected teacher wage expense
--
-- Purpose:
-- - Allow a pending teacher_wage expense record to be cancelled after Cash
--   rejects its request, as long as no Cash transaction was created.
-- - Keep rejected Cash request metadata for audit.
-- - Tighten school_void_teacher_wage_lock so canonical active teacher_wage
--   expense records block wage snapshot voiding at the DB/RPC layer.
--
-- Scope:
-- - Replaces public.school_void_unsubmitted_teacher_wage_expense_record.
-- - Replaces public.school_void_teacher_wage_lock.
-- - Does not touch Cash DB, Cash requests, Cash transactions, account
--   transactions, wage generation, wage details, lessons, income, or
--   historical business data.

begin;

create or replace function public.school_void_unsubmitted_teacher_wage_expense_record(
  p_expense_record_id uuid,
  p_void_reason text default null
)
returns table (
  expense_id uuid,
  wage_lock_id uuid,
  status text,
  cancelled_at timestamptz,
  cancelled_reason text,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_reason text := nullif(trim(coalesce(p_void_reason, '')), '');
  v_now timestamptz := now();
begin
  perform public.school_require_current_app_admin();

  if p_expense_record_id is null then
    raise exception '请选择要作废的老师工资支出记录。';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
   for update;

  if not found then
    raise exception '支出记录不存在：%。', p_expense_record_id;
  end if;

  if coalesce(v_expense.app_type, '') <> 'school' then
    raise exception '只能作废 School 支出记录。';
  end if;

  if coalesce(v_expense.source_type, '') <> 'teacher_wage' then
    raise exception '本流程只允许作废老师工资支出记录。';
  end if;

  if coalesce(v_expense.status, '') = 'cancelled'
     or v_expense.cancelled_at is not null then
    raise exception '该老师工资支出记录已经作废，不能重复作废。';
  end if;

  if coalesce(v_expense.status, '') <> 'pending' then
    raise exception '只有待支付且未生成 Cash 流水的老师工资支出记录可以作废。当前状态：%。', v_expense.status;
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception '该支出记录已关联 Cash transaction，不能作废。';
  end if;

  if v_expense.cash_request_status is not null
     and v_expense.cash_request_status <> 'rejected' then
    raise exception '该支出记录已有未终止 Cash 状态，不能在 School 侧直接作废：%。', v_expense.cash_request_status;
  end if;

  if v_expense.cash_request_id is not null
     and coalesce(v_expense.cash_request_status, '') <> 'rejected' then
    raise exception '该支出记录已关联未拒绝的 Cash request，不能在 School 侧直接作废。';
  end if;

  if v_expense.source_id is null then
    raise exception '老师工资支出记录缺少来源工资快照，不能作废。';
  end if;

  update public.school_expense_records e
     set status = 'cancelled',
         cancelled_at = v_now,
         cancelled_reason = v_reason,
         cancelled_by = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.source_id,
    v_expense.status,
    v_expense.cancelled_at,
    v_expense.cancelled_reason,
    v_expense.cash_request_status,
    case
      when v_expense.cash_request_status = 'rejected'
        then 'Rejected teacher wage expense record cancelled. Cash request metadata was preserved for audit.'
      else 'Unsubmitted teacher wage expense record cancelled. A new active expense can be generated from the same wage lock.'
    end::text;
end;
$$;

comment on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text) is
  'Logically cancels one pending teacher_wage school_expense_records row before Cash transaction creation. Allows rejected Cash requests with no Cash transaction, preserves rejected request metadata, and rejects non-teacher_wage, paid, active Cash-pending/approved/synced, and already-cancelled records.';

revoke all on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  to authenticated;

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
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_lock public.school_teacher_wage_locks%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
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
  v_active_teacher_wage_expense_count integer;
  v_paid_expense_via_payment_count integer;
  v_salary_payment_expense_count integer;
  v_account_tx_via_payment_count integer;
  v_direct_wage_account_tx_count integer;
begin
  v_actor := public.school_require_current_app_admin();

  if v_source <> 'v2_wage_detail' then
    raise exception using
      errcode = '22023',
      message = 'P0_TEACHER_WAGE_VOID_SOURCE_INVALID';
  end if;

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
    into v_active_teacher_wage_expense_count
    from public.school_expense_records e
   where e.source_type = 'teacher_wage'
     and e.source_id = v_lock.id
     and e.app_type = 'school'
     and e.cancelled_at is null
     and coalesce(e.status, '') not in ('cancelled', 'void', 'voided');

  if v_active_teacher_wage_expense_count > 0 then
    raise exception '该工资快照已生成有效老师工资支出记录，不能撤销。请先按支出记录流程处理。';
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
         voided_by = v_actor::text,
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
  'Voids one unpaid teacher wage snapshot with reason/operator/source audit. Rejects any active teacher_wage payment request, canonical teacher_wage expense, or account-transaction dependency and preserves wage detail rows.';

revoke all on function public.school_void_teacher_wage_lock(uuid,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_void_teacher_wage_lock(uuid,text,text,text)
  to authenticated;

commit;
