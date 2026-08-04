-- school_deprecate_teacher_wage_payment_cash_rpc.sql
-- Status: prepared/applied for School DB, 2026-06-16.
-- Purpose:
-- - Deprecate the legacy teacher_wage -> school_payment_requests -> Cash path.
-- - Keep historical school_payment_requests readable, but prevent new Cash
--   confirmation requests from this legacy RPC.
-- - New teacher_wage payments must use:
--   teacher_wage lock -> school_expense_records -> expense Cash request.

create or replace function public.school_request_cash_payment_confirmation(
  p_payment_request_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_payment_currency text,
  p_exchange_rate numeric default null,
  p_payment_amount numeric default null,
  p_note text default null
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  amount numeric,
  currency text,
  school_amount_jpy numeric,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_source_type text;
begin
  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  select source_type
    into v_source_type
    from public.school_payment_requests
   where id = p_payment_request_id;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if coalesce(v_source_type, '') = 'teacher_wage' then
    raise exception 'teacher_wage payments must be handled through school_expense_records';
  end if;

  raise exception 'legacy school_payment_requests Cash confirmation is disabled. Use school_income_records or school_expense_records.';
end;
$$;

comment on function public.school_request_cash_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
) is
  'Deprecated legacy payment-request Cash confirmation entry. Rejects teacher_wage because new payments must use school_expense_records.';

revoke all on function public.school_request_cash_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.school_request_cash_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
) to service_role;
