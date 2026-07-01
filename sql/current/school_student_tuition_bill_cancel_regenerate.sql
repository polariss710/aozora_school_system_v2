-- school_student_tuition_bill_cancel_regenerate.sql
-- Purpose:
-- - Allow a student tuition bill to be regenerated after its pending income
--   record is guardedly cancelled before Cash submission.
-- - Keep cancelled income and cancelled bill rows as audit evidence. New bills
--   are inserted as fresh snapshots with a new notice exchange rate/amount.

\ir school_student_tuition_bill_notice_amount.sql

create or replace function public.school_cancel_pending_income_record(
  p_income_id uuid,
  p_cancel_reason text,
  p_operator text default null
)
returns table (
  income_id uuid,
  status text,
  cancelled_at timestamptz,
  cancelled_reason text,
  cancelled_by text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_cancel_reason, '')), '');
  v_operator text := nullif(trim(coalesce(p_operator, '')), '');
  v_income public.school_income_records%rowtype;
  v_latest_event public.school_personal_cash_income_linkage_events%rowtype;
  v_account_transaction_count integer := 0;
begin
  if p_income_id is null then
    raise exception '请选择要作废的收入记录。';
  end if;

  if v_reason is null then
    raise exception '请填写作废理由。';
  end if;

  select *
    into v_income
    from public.school_income_records i
   where i.id = p_income_id
     and coalesce(i.app_type, '') = 'school'
   for update;

  if not found then
    raise exception '收入记录不存在。';
  end if;

  if v_income.status = 'cancelled' or v_income.cancelled_at is not null then
    raise exception '该收入已作废，不能重复作废。';
  end if;

  if v_income.status is distinct from 'pending' then
    raise exception '只能作废待确认收入。当前状态：%。', v_income.status;
  end if;

  if v_income.account_id is not null then
    raise exception '已有入账账户的收入不能走 pending 作废。';
  end if;

  if v_income.student_payment_id is not null then
    raise exception '关联学生收款链路的收入不能通过普通 pending 作废处理。';
  end if;

  if v_income.reversed_at is not null
    or v_income.reversal_account_transaction_id is not null then
    raise exception '已撤销收入不能作废。';
  end if;

  select count(*)::integer
    into v_account_transaction_count
    from public.school_account_transactions t
   where t.related_table = 'school_income_records'
     and t.related_id = v_income.id
     and coalesce(t.app_type, '') = 'school';

  if v_account_transaction_count > 0 then
    raise exception '已有账户流水的收入不能走 pending 作废。';
  end if;

  select *
    into v_latest_event
    from public.school_personal_cash_income_linkage_events e
   where e.income_record_id = v_income.id
     and e.source_table = 'school_income_records'
     and e.source_event_type in ('tuition_income_received', 'income_received')
   order by e.attempt_no desc, e.created_at desc, e.id desc
   limit 1
   for update;

  if found then
    if v_latest_event.cash_transaction_id is not null then
      raise exception '已有 Cash transaction 的收入不能作废。';
    end if;

    if v_latest_event.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced')
      or v_latest_event.cash_request_status in ('pending', 'approved', 'synced') then
      raise exception '该收入存在待确认或已确认 Cash 请求，不能作废。';
    end if;

    if v_latest_event.sync_status in ('failed', 'blocked') then
      raise exception 'Cash failed / blocked 的收入暂不允许作废。';
    end if;

    if not (
      v_latest_event.sync_status = 'cash_rejected'
      or v_latest_event.cash_request_status = 'rejected'
    ) then
      raise exception '只有 Cash 已拒绝或没有 Cash linkage 的 pending 收入可以作废。';
    end if;
  end if;

  update public.school_income_records i
     set status = 'cancelled',
         cancelled_at = v_now,
         cancelled_reason = v_reason,
         cancelled_by = coalesce(v_operator, nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
         updated_at = v_now
   where i.id = v_income.id
   returning i.id, i.status, i.cancelled_at, i.cancelled_reason, i.cancelled_by
    into income_id, status, cancelled_at, cancelled_reason, cancelled_by;

  if v_income.source_type = 'student_tuition_bill' and v_income.source_id is not null then
    update public.school_student_tuition_bills b
       set status = 'cancelled',
           cancelled_at = coalesce(b.cancelled_at, v_now),
           cancelled_reason = coalesce(
             b.cancelled_reason,
             concat('associated income record cancelled: ', v_reason)
           ),
           updated_by = coalesce(v_operator, nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
           updated_at = v_now
     where b.id = v_income.source_id
       and b.income_record_id = v_income.id
       and b.status = 'income_created'
       and b.app_type = 'school';
  end if;

  return next;
end;
$$;

comment on function public.school_cancel_pending_income_record(uuid, text, text) is
  'Guardedly cancels/voids one pending School income record before receipt. For student_tuition_bill income, also cancels the linked tuition bill snapshot so a new bill can be generated. Does not delete income, Cash linkage events, or account transactions.';

grant execute on function public.school_cancel_pending_income_record(uuid, text, text)
  to authenticated;
