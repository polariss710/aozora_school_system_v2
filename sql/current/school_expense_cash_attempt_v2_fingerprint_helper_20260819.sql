-- Phase 3C2-R immutable payload fingerprint helper.
-- This file defines no table, column, backfill, gate, or business writer.

create or replace function public.school_expense_cash_attempt_payload_fingerprint_v2(
  p_expense_id uuid,
  p_attempt_no integer,
  p_request_type text,
  p_payment_route text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_original_amount numeric,
  p_original_currency text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_cash_funding_account_id uuid,
  p_charge_date date
)
returns text
language sql
immutable
strict
security invoker
set search_path = pg_catalog, public
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'external_source', 'aozora_school',
          'external_reference_type', 'school_expense_records',
          'external_reference_id', p_expense_id,
          'transaction_type', 'expense',
          'expense_id', p_expense_id,
          'attempt_no', p_attempt_no,
          'request_type', p_request_type,
          'payment_route', p_payment_route,
          'request_event_id', p_request_event_id,
          'idempotency_key', p_idempotency_key,
          'original_amount', p_original_amount,
          'original_currency', p_original_currency,
          'payment_amount', p_payment_amount,
          'payment_currency', p_payment_currency,
          'cash_funding_account_id', p_cash_funding_account_id,
          'charge_date', p_charge_date
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$function$;

alter function public.school_expense_cash_attempt_payload_fingerprint_v2(
  uuid, integer, text, text, uuid, text, numeric, text, numeric, text, uuid, date
) owner to postgres;

comment on function public.school_expense_cash_attempt_payload_fingerprint_v2(
  uuid, integer, text, text, uuid, text, numeric, text, numeric, text, uuid, date
) is
  'Owner-only immutable SHA-256 fingerprint for a School expense Cash attempt request snapshot. Constants include the canonical external source/reference and expense transaction type.';

revoke all on function public.school_expense_cash_attempt_payload_fingerprint_v2(
  uuid, integer, text, text, uuid, text, numeric, text, numeric, text, uuid, date
) from public, anon, authenticated, service_role;
