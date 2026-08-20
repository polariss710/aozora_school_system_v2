-- P0 Phase B: read-only resolver for Phase 3C2-R historical immediate-expense
-- Cash requests whose Home payload snapshot predates the V2 fingerprint field.
-- This migration creates functions only. It does not alter or backfill data.

create or replace function public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_home_request_user_id uuid,
  p_home_request_status text,
  p_home_approved_at timestamptz,
  p_home_rejected_at timestamptz,
  p_external_source text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_external_reference_type text,
  p_external_reference_id uuid,
  p_request_type text,
  p_transaction_type text,
  p_payment_route text,
  p_attempt_no integer,
  p_original_amount numeric,
  p_original_currency text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_cash_account_id uuid,
  p_charge_date date,
  p_cash_transaction_id uuid default null,
  p_home_transaction_id uuid default null,
  p_home_transaction_user_id uuid default null,
  p_home_transaction_type text default null,
  p_home_transaction_amount numeric default null,
  p_home_transaction_currency text default null,
  p_home_transaction_account_id uuid default null,
  p_home_transaction_date date default null,
  p_home_transaction_scope text default null,
  p_home_transaction_external_source text default null,
  p_home_transaction_event_id uuid default null,
  p_home_transaction_event_type text default null,
  p_home_transaction_reference_type text default null,
  p_home_transaction_reference_id uuid default null,
  p_home_transaction_idempotency_key text default null,
  p_home_transaction_created_by_external boolean default null
)
returns table (
  resolved_expense_id uuid,
  resolved_attempt_id uuid,
  resolved_attempt_status text,
  resolved_attempt_version integer,
  historical_shape text,
  resolved_request_payload_fingerprint text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_request_status text := lower(nullif(trim(coalesce(p_home_request_status, '')), ''));
  v_original_currency text := upper(nullif(trim(coalesce(p_original_currency, '')), ''));
  v_payment_currency text := upper(nullif(trim(coalesce(p_payment_currency, '')), ''));
  v_transaction_currency text := upper(nullif(trim(coalesce(p_home_transaction_currency, '')), ''));
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_attempt_count integer;
  v_expected_fingerprint text;
  v_historical_shape text;
begin
  if p_expense_record_id is null
     or p_cash_request_id is null
     or p_home_request_user_id is null
     or p_request_event_id is null
     or p_external_reference_id is null
     or p_cash_account_id is null
     or p_charge_date is null
     or p_attempt_no is null
     or nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or coalesce(p_original_amount, 0) <= 0
     or coalesce(p_payment_amount, 0) <= 0 then
    raise exception using
      errcode = '22023',
      message = 'HOME_REQUEST_EVIDENCE_CONFLICT',
      detail = 'Historical resolver received incomplete Home request evidence.';
  end if;

  if v_request_status not in ('approved', 'rejected') then
    raise exception using errcode = '55000', message = 'ACTION_STATUS_CONFLICT';
  end if;

  if (v_request_status = 'approved' and (p_home_approved_at is null or p_home_rejected_at is not null))
     or (v_request_status = 'rejected' and (p_home_rejected_at is null or p_home_approved_at is not null)) then
    raise exception using errcode = '55000', message = 'ACTION_STATUS_CONFLICT';
  end if;

  if p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or p_external_reference_id is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense'
     or p_payment_route is distinct from 'immediate_account'
     or v_original_currency not in ('JPY', 'CNY')
     or v_payment_currency not in ('JPY', 'CNY') then
    raise exception using errcode = '55000', message = 'HOME_REQUEST_EVIDENCE_CONFLICT';
  end if;

  select e.*
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school';

  if not found then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_RECORD_NOT_FOUND';
  end if;

  select count(*)
    into v_attempt_count
    from public.school_expense_cash_attempts a
   where a.expense_id = p_expense_record_id
     and a.request_event_id = p_request_event_id;

  if v_attempt_count = 0 then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_NOT_FOUND';
  elsif v_attempt_count <> 1 then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_AMBIGUOUS';
  end if;

  select a.*
    into v_attempt
    from public.school_expense_cash_attempts a
   where a.expense_id = p_expense_record_id
     and a.request_event_id = p_request_event_id;

  if v_attempt.id is null
     or v_attempt.expense_id is distinct from v_expense.id
     or v_attempt.cash_request_id is distinct from p_cash_request_id
     or v_attempt.request_event_id is distinct from p_request_event_id
     or v_attempt.idempotency_key is distinct from p_idempotency_key
     or v_attempt.payment_route is distinct from 'immediate_account'
     or v_attempt.request_type is distinct from 'expense_paid'
     or v_attempt.attempt_no is distinct from p_attempt_no
     or v_attempt.original_amount is distinct from p_original_amount
     or v_attempt.original_currency is distinct from v_original_currency
     or v_attempt.payment_amount is distinct from p_payment_amount
     or v_attempt.payment_currency is distinct from v_payment_currency
     or v_attempt.cash_funding_account_id is distinct from p_cash_account_id
     or v_attempt.charge_date is distinct from p_charge_date then
    raise exception using errcode = '55000', message = 'HOME_REQUEST_EVIDENCE_CONFLICT';
  end if;

  if v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no
     or v_expense.cash_payment_amount is distinct from v_attempt.payment_amount
     or v_expense.cash_payment_currency is distinct from v_attempt.payment_currency
     or v_expense.cash_request_id is distinct from v_attempt.cash_request_id then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_ATTEMPT_LINK_CONFLICT';
  end if;

  if v_attempt.callback_recovered_from_prepared
     or v_attempt.callback_recovered_at is not null
     or v_attempt.callback_recovery_source is not null
     or v_attempt.submitted_at is null then
    raise exception using errcode = '55000', message = 'HISTORICAL_FALLBACK_NOT_ELIGIBLE';
  end if;

  if v_attempt.attempt_status = 'submitted'
     and v_attempt.version = 1
     and v_attempt.cash_transaction_id is null
     and v_attempt.approved_at is null
     and v_attempt.rejected_at is null then
    v_historical_shape := 'phase3c2r_submitted_v1';
  elsif v_attempt.attempt_status = 'approved_immediate'
        and v_attempt.version in (1, 2)
        and v_attempt.cash_transaction_id is not null
        and v_attempt.approved_at is not null
        and v_attempt.rejected_at is null then
    v_historical_shape := case v_attempt.version
      when 1 then 'phase3c2r_backfilled_approved_v1'
      else 'phase3c2r_compat_recovered_approved_v2'
    end;
  elsif v_attempt.attempt_status = 'rejected'
        and v_attempt.version in (1, 2)
        and v_attempt.cash_transaction_id is null
        and v_attempt.rejected_at is not null
        and v_attempt.approved_at is null then
    v_historical_shape := case v_attempt.version
      when 1 then 'phase3c2r_backfilled_rejected_v1'
      else 'phase3c2r_compat_recovered_rejected_v2'
    end;
  else
    raise exception using errcode = '55000', message = 'HISTORICAL_FALLBACK_NOT_ELIGIBLE';
  end if;

  if (v_request_status = 'approved' and v_attempt.attempt_status = 'rejected')
     or (v_request_status = 'rejected' and v_attempt.attempt_status = 'approved_immediate') then
    raise exception using errcode = '55000', message = 'TERMINAL_CONFLICT';
  end if;

  if v_attempt.attempt_status = 'submitted' then
    if v_expense.status is distinct from 'pending'
       or v_expense.cash_request_status is distinct from 'pending'
       or v_expense.cash_transaction_id is not null
       or v_expense.cash_synced_at is not null then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_TERMINAL_STATE_CONFLICT';
    end if;
  elsif v_attempt.attempt_status = 'approved_immediate' then
    if v_request_status <> 'approved'
       or v_expense.status is distinct from 'paid'
       or v_expense.cash_request_status is distinct from 'approved'
       or v_expense.cash_transaction_id is distinct from v_attempt.cash_transaction_id
       or v_expense.cash_synced_at is null then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_TERMINAL_STATE_CONFLICT';
    end if;
  else
    if v_request_status <> 'rejected'
       or v_expense.cash_request_status is distinct from 'rejected'
       or v_expense.cash_transaction_id is not null
       or v_expense.cash_synced_at is null then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_TERMINAL_STATE_CONFLICT';
    end if;
  end if;

  v_expected_fingerprint := public.school_expense_cash_attempt_payload_fingerprint_v2(
    v_attempt.expense_id,
    v_attempt.attempt_no,
    v_attempt.request_type,
    v_attempt.payment_route,
    v_attempt.request_event_id,
    v_attempt.idempotency_key,
    v_attempt.original_amount,
    v_attempt.original_currency,
    v_attempt.payment_amount,
    v_attempt.payment_currency,
    v_attempt.cash_funding_account_id,
    v_attempt.charge_date
  );

  if v_attempt.request_payload_fingerprint is null
     or v_attempt.request_payload_fingerprint !~ '^[0-9a-f]{64}$'
     or v_attempt.request_payload_fingerprint is distinct from v_expected_fingerprint then
    raise exception using errcode = '55000', message = 'FINGERPRINT_RECOMPUTE_CONFLICT';
  end if;

  if v_request_status = 'approved' then
    if p_cash_transaction_id is null then
      raise exception using errcode = '55000', message = 'HOME_TRANSACTION_MISSING';
    end if;

    if p_home_transaction_id is distinct from p_cash_transaction_id
       or p_home_transaction_user_id is distinct from p_home_request_user_id
       or p_home_transaction_type is distinct from 'expense'
       or p_home_transaction_amount is distinct from p_payment_amount
       or v_transaction_currency is distinct from v_payment_currency
       or p_home_transaction_account_id is distinct from p_cash_account_id
       or p_home_transaction_date is distinct from p_charge_date
       or p_home_transaction_scope is distinct from 'school'
       or p_home_transaction_external_source is distinct from p_external_source
       or p_home_transaction_event_id is distinct from p_request_event_id
       or p_home_transaction_event_type is distinct from p_request_type
       or p_home_transaction_reference_type is distinct from p_external_reference_type
       or p_home_transaction_reference_id is distinct from p_external_reference_id
       or p_home_transaction_idempotency_key is distinct from p_idempotency_key
       or p_home_transaction_created_by_external is distinct from true then
      raise exception using errcode = '55000', message = 'HOME_TRANSACTION_EVIDENCE_CONFLICT';
    end if;

    if v_attempt.attempt_status = 'approved_immediate'
       and v_attempt.cash_transaction_id is distinct from p_cash_transaction_id then
      raise exception using errcode = '55000', message = 'TERMINAL_CONFLICT';
    end if;
  else
    if p_cash_transaction_id is not null
       or p_home_transaction_id is not null
       or p_home_transaction_user_id is not null
       or p_home_transaction_type is not null
       or p_home_transaction_amount is not null
       or p_home_transaction_currency is not null
       or p_home_transaction_account_id is not null
       or p_home_transaction_date is not null
       or p_home_transaction_scope is not null
       or p_home_transaction_external_source is not null
       or p_home_transaction_event_id is not null
       or p_home_transaction_event_type is not null
       or p_home_transaction_reference_type is not null
       or p_home_transaction_reference_id is not null
       or p_home_transaction_idempotency_key is not null
       or p_home_transaction_created_by_external is not null then
      raise exception using errcode = '55000', message = 'HOME_TRANSACTION_REJECTED_CONFLICT';
    end if;
  end if;

  return query
  select
    v_expense.id,
    v_attempt.id,
    v_attempt.attempt_status,
    v_attempt.version,
    v_historical_shape,
    v_expected_fingerprint;
end;
$function$;

alter function public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) owner to postgres;

revoke all on function public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) from public, anon, authenticated, service_role;

comment on function public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) is
  'Owner-only, read-only Phase 3C2-R historical immediate-expense evidence resolver. Returns a DB-recomputed fingerprint and never applies callback state.';

create or replace function public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_home_request_user_id uuid,
  p_home_request_status text,
  p_home_approved_at timestamptz,
  p_home_rejected_at timestamptz,
  p_external_source text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_external_reference_type text,
  p_external_reference_id uuid,
  p_request_type text,
  p_transaction_type text,
  p_payment_route text,
  p_attempt_no integer,
  p_original_amount numeric,
  p_original_currency text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_cash_account_id uuid,
  p_charge_date date,
  p_cash_transaction_id uuid default null,
  p_home_transaction_id uuid default null,
  p_home_transaction_user_id uuid default null,
  p_home_transaction_type text default null,
  p_home_transaction_amount numeric default null,
  p_home_transaction_currency text default null,
  p_home_transaction_account_id uuid default null,
  p_home_transaction_date date default null,
  p_home_transaction_scope text default null,
  p_home_transaction_external_source text default null,
  p_home_transaction_event_id uuid default null,
  p_home_transaction_event_type text default null,
  p_home_transaction_reference_type text default null,
  p_home_transaction_reference_id uuid default null,
  p_home_transaction_idempotency_key text default null,
  p_home_transaction_created_by_external boolean default null
)
returns table (
  resolved_expense_id uuid,
  resolved_attempt_id uuid,
  resolved_attempt_status text,
  resolved_attempt_version integer,
  historical_shape text,
  resolved_request_payload_fingerprint text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select r.*
  from public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
    p_expense_record_id,
    p_cash_request_id,
    p_home_request_user_id,
    p_home_request_status,
    p_home_approved_at,
    p_home_rejected_at,
    p_external_source,
    p_request_event_id,
    p_idempotency_key,
    p_external_reference_type,
    p_external_reference_id,
    p_request_type,
    p_transaction_type,
    p_payment_route,
    p_attempt_no,
    p_original_amount,
    p_original_currency,
    p_payment_amount,
    p_payment_currency,
    p_cash_account_id,
    p_charge_date,
    p_cash_transaction_id,
    p_home_transaction_id,
    p_home_transaction_user_id,
    p_home_transaction_type,
    p_home_transaction_amount,
    p_home_transaction_currency,
    p_home_transaction_account_id,
    p_home_transaction_date,
    p_home_transaction_scope,
    p_home_transaction_external_source,
    p_home_transaction_event_id,
    p_home_transaction_event_type,
    p_home_transaction_reference_type,
    p_home_transaction_reference_id,
    p_home_transaction_idempotency_key,
    p_home_transaction_created_by_external
  ) r;
$function$;

alter function public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) owner to postgres;

revoke all on function public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) from public, anon, authenticated, service_role;

grant execute on function public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) to service_role;

comment on function public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(
  uuid,uuid,uuid,text,timestamptz,timestamptz,text,uuid,text,text,uuid,text,text,text,integer,
  numeric,text,numeric,text,uuid,date,uuid,uuid,uuid,text,numeric,text,uuid,date,
  text,text,uuid,text,text,uuid,text,boolean
) is
  'Service-role-only read wrapper for strict Phase 3C2-R historical immediate-expense fingerprint resolution.';
