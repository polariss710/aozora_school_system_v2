-- school_cancel_pending_income_record_rpc.sql
-- Purpose: Guardedly cancel/void one pending School income record before receipt.
-- Status: DRAFT ONLY. DO NOT EXECUTE until readonly prechecks and review pass.
-- Version: v10.1.6-income-pending-cancel-draft
--
-- Scope:
--   - Adds pending-income cancellation metadata to school_income_records.
--   - Extends school_income_records.status to allow cancelled.
--   - Creates public.school_cancel_pending_income_record.
--   - Does not delete income records.
--   - Does not delete Cash linkage events, metadata, or payload snapshots.
--   - Does not create account transactions.
--   - Does not modify income reversal RPCs.
--
-- Readonly precheck template before execution / commit tests:
-- with target_ids(id) as (
--   values
--     ('00000000-0000-0000-0000-000000000000'::uuid)
-- ),
-- latest_event as (
--   select distinct on (e.income_record_id)
--     e.*
--   from public.school_personal_cash_income_linkage_events e
--   join target_ids t on t.id = e.income_record_id
--   where e.source_table = 'school_income_records'
--     and e.source_event_type in ('tuition_income_received', 'income_received')
--   order by e.income_record_id, e.attempt_no desc, e.created_at desc, e.id desc
-- ),
-- tx_count as (
--   select
--     t.id as income_id,
--     count(a.*)::integer as account_transaction_count
--   from target_ids t
--   left join public.school_account_transactions a
--     on a.related_table = 'school_income_records'
--    and a.related_id = t.id
--    and coalesce(a.app_type, '') = 'school'
--   group by t.id
-- )
-- select
--   i.id,
--   i.status,
--   i.account_id,
--   i.student_payment_id,
--   i.cancelled_at,
--   i.reversed_at,
--   i.reversal_account_transaction_id,
--   coalesce(tx.account_transaction_count, 0) as account_transaction_count,
--   e.sync_status,
--   e.cash_request_status,
--   e.cash_transaction_id,
--   e.cash_request_id,
--   e.attempt_no,
--   case
--     when i.status <> 'pending' then 'NG: status not pending'
--     when i.account_id is not null then 'NG: has account_id'
--     when i.student_payment_id is not null then 'NG: has student_payment_id'
--     when i.reversed_at is not null or i.reversal_account_transaction_id is not null then 'NG: reversed'
--     when i.cancelled_at is not null then 'NG: already cancelled'
--     when coalesce(tx.account_transaction_count, 0) > 0 then 'NG: has account transaction'
--     when e.cash_transaction_id is not null then 'NG: has cash transaction'
--     when e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced') then 'NG: active/synced Cash linkage'
--     when e.sync_status in ('failed', 'blocked') then 'NG: failed/blocked Cash linkage is not cancellable in v1'
--     when e.cash_request_status in ('pending', 'approved', 'synced') then 'NG: active/approved Cash request'
--     when e.id is null then 'OK: no Cash linkage'
--     when e.sync_status = 'cash_rejected' or e.cash_request_status = 'rejected' then 'OK: rejected Cash linkage'
--     else 'NG: latest Cash linkage is not rejected'
--   end as cancel_precheck
-- from target_ids t
-- join public.school_income_records i on i.id = t.id
-- left join latest_event e on e.income_record_id = i.id
-- left join tx_count tx on tx.income_id = i.id
-- where coalesce(i.app_type, '') = 'school';

begin;

alter table public.school_income_records
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_reason text,
  add column if not exists cancelled_by text;

alter table public.school_income_records
  drop constraint if exists school_income_records_status_check;

alter table public.school_income_records
  add constraint school_income_records_status_check
    check (status in ('pending', 'received', 'reversed', 'cancelled'));

comment on column public.school_income_records.cancelled_at
  is 'Timestamp when a pending income record was cancelled/voided before receipt. Null for active income records.';

comment on column public.school_income_records.cancelled_reason
  is 'Required reason recorded when a pending income record is cancelled/voided.';

comment on column public.school_income_records.cancelled_by
  is 'Operator identity recorded when a pending income record is cancelled/voided.';

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
  'Guardedly cancels/voids one pending School income record before receipt. Requires a reason; does not delete income, does not delete Cash linkage events, and does not create account transactions.';

grant execute on function public.school_cancel_pending_income_record(uuid, text, text)
  to authenticated;

commit;

-- Rollback draft, only after confirming no cancelled income records exist:
-- begin;
-- drop function if exists public.school_cancel_pending_income_record(uuid, text, text);
-- alter table public.school_income_records
--   drop constraint if exists school_income_records_status_check;
-- alter table public.school_income_records
--   add constraint school_income_records_status_check
--     check (status in ('pending', 'received', 'reversed'));
-- alter table public.school_income_records
--   drop column if exists cancelled_at,
--   drop column if exists cancelled_reason,
--   drop column if exists cancelled_by;
-- commit;
