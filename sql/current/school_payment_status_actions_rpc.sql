-- school_payment_status_actions_rpc.sql
-- Purpose:
-- - Defines payment request status action RPCs for cancel / restore.
-- - `school_cancel_payment_request(...)` moves one pending payment request to
--   cancelled.
-- - `school_restore_cancelled_payment_request(...)` moves one cancelled
--   payment request back to pending.
--
-- Current execution state:
-- - These RPCs already exist as a runtime dependency of the payment page/API.
-- - The repo previously missed tracking this SQL because the file was ignored.
-- - This checkpoint only brings the definition under version control. Do not
--   execute this file as part of the tracking cleanup.
--
-- Boundaries:
-- - Only updates `school_payment_requests.status`, `paid_at`, and `updated_at`.
-- - Does not create School expense records.
-- - Does not create School account transactions.
-- - Does not update School account balances.
-- - Does not modify teacher wage locks or wage lock details.
-- - Does not write Cash System data.
--
-- Permission note:
-- - Execute is granted to `authenticated` only. Do not grant these write RPCs
--   to `anon` without a separate security review.

create or replace function public.school_cancel_payment_request(
  p_payment_request_id uuid,
  p_reason text default null
)
returns table (
  payment_request_id uuid,
  old_status text,
  new_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_old_status text;
  v_updated_at timestamptz;
begin
  -- p_reason is reserved for future audit fields. The current schema does not persist it.
  select *
    into v_payment
    from public.school_payment_requests
   where id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if v_payment.status <> 'pending' then
    raise exception 'payment request status must be pending. current status: %', v_payment.status;
  end if;

  v_old_status := v_payment.status;
  v_updated_at := now();

  update public.school_payment_requests
     set status = 'cancelled',
         paid_at = null,
         updated_at = v_updated_at
   where id = p_payment_request_id;

  payment_request_id := p_payment_request_id;
  old_status := v_old_status;
  new_status := 'cancelled';
  updated_at := v_updated_at;
  return next;
end;
$$;

create or replace function public.school_restore_cancelled_payment_request(
  p_payment_request_id uuid
)
returns table (
  payment_request_id uuid,
  old_status text,
  new_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_old_status text;
  v_updated_at timestamptz;
begin
  select *
    into v_payment
    from public.school_payment_requests
   where id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if v_payment.status <> 'cancelled' then
    raise exception 'payment request status must be cancelled. current status: %', v_payment.status;
  end if;

  v_old_status := v_payment.status;
  v_updated_at := now();

  update public.school_payment_requests
     set status = 'pending',
         paid_at = null,
         updated_at = v_updated_at
   where id = p_payment_request_id;

  payment_request_id := p_payment_request_id;
  old_status := v_old_status;
  new_status := 'pending';
  updated_at := v_updated_at;
  return next;
end;
$$;

grant execute on function public.school_cancel_payment_request(uuid, text) to authenticated;
grant execute on function public.school_restore_cancelled_payment_request(uuid) to authenticated;
