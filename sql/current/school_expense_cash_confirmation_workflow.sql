-- school_expense_cash_confirmation_workflow.sql
-- Status: executed on School DB 2026-06-15.
-- Purpose:
-- - Let canonical school_expense_records submit Cash expense confirmation
--   requests.
-- - Track Cash approve/reject callbacks on school_expense_records.
-- - Does not create Cash transactions, migrate legacy school_payment_requests,
--   or touch teacher_wage generation logic.

begin;

alter table public.school_expense_records
  add column if not exists cash_request_event_id uuid,
  add column if not exists cash_request_attempt_no integer not null default 0,
  add column if not exists cash_payment_amount numeric,
  add column if not exists cash_payment_currency text,
  add column if not exists cash_payment_note text;

create index if not exists school_expense_records_cash_request_event_idx
  on public.school_expense_records (cash_request_event_id)
  where cash_request_event_id is not null;

comment on column public.school_expense_records.cash_request_event_id is
  'Per-attempt external_event_id used when a school_expense_records row submits a Cash expense request.';
comment on column public.school_expense_records.cash_request_attempt_no is
  'Sequential Cash request attempt number for canonical expense_records -> Cash flow.';
comment on column public.school_expense_records.cash_payment_amount is
  'Actual payment amount submitted to Cash for this expense request attempt.';
comment on column public.school_expense_records.cash_payment_currency is
  'Actual payment currency submitted to Cash for this expense request attempt.';
comment on column public.school_expense_records.cash_payment_note is
  'Operator note submitted with the Cash expense request attempt.';

create or replace function public.school_request_cash_expense_payment_confirmation(
  p_expense_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text default null,
  p_payment_amount numeric default null,
  p_payment_currency text default null,
  p_note text default null
)
returns table (
  expense_id uuid,
  request_event_id uuid,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  expense_status text,
  expense_category text,
  source_type text,
  source_id uuid,
  payee_name_snapshot text,
  year_month text,
  expense_date date,
  description text,
  original_amount numeric,
  original_currency text,
  original_amount_jpy numeric,
  original_amount_cny numeric,
  payment_amount numeric,
  payment_currency text,
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
  v_expense public.school_expense_records%rowtype;
  v_now timestamptz := now();
  v_payment_amount numeric := p_payment_amount;
  v_payment_currency text := upper(nullif(trim(coalesce(p_payment_currency, '')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_reuse_pending boolean := false;
begin
  if p_expense_record_id is null then
    raise exception 'expense_record_id is required.';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception 'Cash user/account is required.';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school'
   for update;

  if not found then
    raise exception 'school expense record not found: %', p_expense_record_id;
  end if;

  if v_expense.reversed_at is not null or v_expense.status = 'reversed' then
    raise exception 'reversed expense records cannot request Cash confirmation.';
  end if;

  if v_expense.status = 'paid' then
    raise exception 'paid expense records cannot request Cash confirmation again.';
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception 'expense record already has Cash transaction: %', v_expense.cash_transaction_id;
  end if;

  if v_expense.cash_request_status in ('pending', 'approved', 'synced') then
    raise exception 'expense record already has active or completed Cash request: %', v_expense.cash_request_status;
  end if;

  if v_payment_amount is null then
    v_payment_amount := v_expense.amount;
  end if;

  if coalesce(v_payment_amount, 0) <= 0 then
    raise exception 'payment amount must be greater than 0.';
  end if;

  if v_payment_currency is null then
    v_payment_currency := upper(coalesce(v_expense.currency, 'JPY'));
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'payment currency must be JPY or CNY. current: %', v_payment_currency;
  end if;

  if v_account_name is null then
    raise exception 'Cash account name snapshot is required.';
  end if;

  v_reuse_pending :=
    v_expense.cash_request_status = 'pending_cash_request'
    and v_expense.cash_request_event_id is not null
    and v_expense.cash_request_id is null;

  if not v_reuse_pending then
    v_expense.cash_request_attempt_no := coalesce(v_expense.cash_request_attempt_no, 0) + 1;
    v_expense.cash_request_event_id := gen_random_uuid();
  end if;

  update public.school_expense_records e
     set cash_request_event_id = v_expense.cash_request_event_id,
         cash_request_attempt_no = v_expense.cash_request_attempt_no,
         cash_request_status = 'pending_cash_request',
         cash_request_id = null,
         cash_transaction_id = null,
         cash_requested_at = v_now,
         cash_payment_amount = v_payment_amount,
         cash_payment_currency = v_payment_currency,
         cash_payment_note = v_note,
         cash_error_message = null,
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.cash_request_event_id,
    v_expense.cash_request_attempt_no,
    format(
      'aozora_school:school_expense_records:%s:expense_paid:attempt:%s',
      v_expense.id,
      v_expense.cash_request_attempt_no
    ),
    'expense_paid'::text,
    v_expense.status,
    v_expense.expense_category,
    v_expense.source_type,
    v_expense.source_id,
    v_expense.payee_name_snapshot,
    v_expense.year_month,
    v_expense.expense_date,
    v_expense.description,
    v_expense.amount,
    v_expense.currency,
    v_expense.amount_jpy,
    v_expense.amount_cny,
    v_payment_amount,
    v_payment_currency,
    p_cash_user_id,
    p_cash_account_id,
    v_account_name,
    v_account_type,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    case
      when v_reuse_pending then 'existing pending Cash expense request attempt reused'
      else 'Cash expense request attempt prepared'
    end;
end;
$$;

create or replace function public.school_mark_cash_expense_request_submitted(
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_cash_request_status text default 'pending'
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_now timestamptz := now();
  v_status text := nullif(trim(coalesce(p_cash_request_status, '')), '');
begin
  if p_expense_record_id is null or p_cash_request_id is null then
    raise exception 'expense_record_id and cash_request_id are required.';
  end if;

  if v_status is distinct from 'pending' then
    raise exception 'submitted Cash request status must be pending. current status: %', p_cash_request_status;
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school'
   for update;

  if not found then
    raise exception 'school expense record not found: %', p_expense_record_id;
  end if;

  if v_expense.cash_request_status not in ('pending_cash_request', 'pending') then
    raise exception 'expense record is not waiting for Cash request submission. current status: %', v_expense.cash_request_status;
  end if;

  if v_expense.cash_request_id is not null
     and v_expense.cash_request_id is distinct from p_cash_request_id then
    raise exception 'expense record already references a different Cash request: %', v_expense.cash_request_id;
  end if;

  update public.school_expense_records e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'pending',
         cash_requested_at = coalesce(e.cash_requested_at, v_now),
         cash_error_message = null,
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.status,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    'Cash expense request submitted and awaiting confirmation'::text;
end;
$$;

create or replace function public.school_mark_cash_expense_confirmed(
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_cash_transaction_id uuid,
  p_confirmed_at timestamptz default null
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_now timestamptz := coalesce(p_confirmed_at, now());
begin
  if p_expense_record_id is null or p_cash_request_id is null or p_cash_transaction_id is null then
    raise exception 'expense_record_id, cash_request_id and cash_transaction_id are required.';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school'
   for update;

  if not found then
    raise exception 'school expense record not found: %', p_expense_record_id;
  end if;

  if v_expense.cash_request_id is not null
     and v_expense.cash_request_id is distinct from p_cash_request_id then
    raise exception 'expense record references a different Cash request: %', v_expense.cash_request_id;
  end if;

  if v_expense.cash_transaction_id is not null then
    if v_expense.cash_transaction_id = p_cash_transaction_id
       and v_expense.cash_request_status = 'approved'
       and v_expense.status = 'paid' then
      return query
      select
        v_expense.id,
        v_expense.status,
        v_expense.cash_request_id,
        v_expense.cash_request_status,
        v_expense.cash_transaction_id,
        'Cash expense confirmation already synced'::text;
      return;
    end if;

    raise exception 'expense record already has a different Cash transaction: %', v_expense.cash_transaction_id;
  end if;

  update public.school_expense_records e
     set status = 'paid',
         cash_request_id = p_cash_request_id,
         cash_request_status = 'approved',
         cash_transaction_id = p_cash_transaction_id,
         cash_synced_at = v_now,
         cash_error_message = null,
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.status,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    v_expense.cash_transaction_id,
    'Cash expense confirmation synced'::text;
end;
$$;

create or replace function public.school_mark_cash_expense_rejected(
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_rejected_reason text default null,
  p_rejected_at timestamptz default null
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_now timestamptz := coalesce(p_rejected_at, now());
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
begin
  if p_expense_record_id is null or p_cash_request_id is null then
    raise exception 'expense_record_id and cash_request_id are required.';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
     and e.app_type = 'school'
   for update;

  if not found then
    raise exception 'school expense record not found: %', p_expense_record_id;
  end if;

  if v_expense.cash_request_id is not null
     and v_expense.cash_request_id is distinct from p_cash_request_id then
    raise exception 'expense record references a different Cash request: %', v_expense.cash_request_id;
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception 'expense record already has Cash transaction and cannot be rejected: %', v_expense.cash_transaction_id;
  end if;

  update public.school_expense_records e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'rejected',
         cash_synced_at = v_now,
         cash_error_message = coalesce(v_reason, 'Cash request rejected'),
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.status,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    'Cash expense request rejection synced'::text;
end;
$$;

comment on function public.school_request_cash_expense_payment_confirmation(uuid, uuid, uuid, text, text, numeric, text, text) is
  'Prepares a canonical school_expense_records -> Cash pending expense request attempt. Does not create Cash transactions.';
comment on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text) is
  'Marks a school_expense_records Cash expense request as submitted to Cash and awaiting approval.';
comment on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz) is
  'Marks a school_expense_records row paid after Cash approved the canonical expense request.';
comment on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz) is
  'Marks a school_expense_records Cash request rejected without creating School ledger side effects.';

revoke all on function public.school_request_cash_expense_payment_confirmation(uuid, uuid, uuid, text, text, numeric, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz)
  from public, anon, authenticated, service_role;

grant execute on function public.school_request_cash_expense_payment_confirmation(uuid, uuid, uuid, text, text, numeric, text, text)
  to service_role;
grant execute on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text)
  to service_role;
grant execute on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz)
  to service_role;
grant execute on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz)
  to service_role;

commit;
