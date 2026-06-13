-- school_teacher_wage_cash_confirmation_all_scope_rpc.sql
-- Status: applied on school DB, 2026-06-14.
-- Purpose:
-- - Promote teacher_wage Cash confirmation from personal + JPY only to all
--   pending teacher_wage payment requests.
-- - Store selected Cash account snapshots from the Cash-owned eligible account
--   whitelist.
-- - Support JPY payments and CNY payments while preserving the School JPY wage
--   cost.
-- - Do not mark payment requests paid, write School ledger side effects, create
--   School expenses, or create Cash transactions.

alter table public.school_personal_cash_linkage_events
  add column if not exists cash_account_type_snapshot text,
  add column if not exists school_amount_jpy numeric,
  add column if not exists payment_currency text,
  add column if not exists payment_exchange_rate numeric,
  add column if not exists payment_amount numeric,
  add column if not exists attempt_no integer;

with ranked_events as (
  select
    id,
    row_number() over (
      partition by source_table, source_id, source_event_type
      order by created_at, id
    ) as derived_attempt_no
  from public.school_personal_cash_linkage_events
)
update public.school_personal_cash_linkage_events as e
   set attempt_no = ranked_events.derived_attempt_no
  from ranked_events
 where e.id = ranked_events.id
   and e.attempt_no is null;

alter table public.school_personal_cash_linkage_events
  alter column cash_account_mapping_id drop not null,
  alter column attempt_no set default 1,
  alter column attempt_no set not null;

drop index if exists public.school_personal_cash_linkage_events_source_event_uniq;

create unique index if not exists school_personal_cash_linkage_events_source_event_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type,
    attempt_no
  );

create unique index if not exists school_personal_cash_linkage_events_active_attempt_uniq
  on public.school_personal_cash_linkage_events (
    source_table,
    source_id,
    source_event_type
  )
  where sync_status in ('pending_cash_request', 'awaiting_cash_confirmation');

alter table public.school_personal_cash_linkage_events
  drop constraint if exists school_personal_cash_linkage_events_currency_check,
  drop constraint if exists school_personal_cash_linkage_events_cash_table_check,
  drop constraint if exists school_personal_cash_linkage_events_payment_currency_check,
  drop constraint if exists school_personal_cash_linkage_events_payment_amount_check,
  drop constraint if exists school_personal_cash_linkage_events_school_amount_jpy_check,
  drop constraint if exists school_personal_cash_linkage_events_exchange_rate_check,
  drop constraint if exists school_personal_cash_linkage_events_attempt_no_check,
  add constraint school_personal_cash_linkage_events_currency_check
    check (currency in ('JPY', 'CNY')),
  add constraint school_personal_cash_linkage_events_cash_table_check
    check (cash_transaction_table in ('home_jpy_transactions', 'home_cny_transactions')),
  add constraint school_personal_cash_linkage_events_payment_currency_check
    check (payment_currency is null or payment_currency in ('JPY', 'CNY')),
  add constraint school_personal_cash_linkage_events_payment_amount_check
    check (payment_amount is null or payment_amount > 0),
  add constraint school_personal_cash_linkage_events_school_amount_jpy_check
    check (school_amount_jpy is null or school_amount_jpy > 0),
  add constraint school_personal_cash_linkage_events_exchange_rate_check
    check (payment_exchange_rate is null or payment_exchange_rate > 0),
  add constraint school_personal_cash_linkage_events_attempt_no_check
    check (attempt_no > 0);

comment on column public.school_personal_cash_linkage_events.cash_account_mapping_id is
  'Historical personal-business Cash mapping id. New all-scope teacher_wage Cash requests use Cash-owned eligible accounts directly and leave this null.';

comment on column public.school_personal_cash_linkage_events.cash_account_type_snapshot is
  'Cash account type snapshot selected from the Cash-owned School eligible account whitelist.';

comment on column public.school_personal_cash_linkage_events.school_amount_jpy is
  'School-side teacher wage cost in JPY. This remains the business cost basis even when the actual Cash payment is CNY.';

comment on column public.school_personal_cash_linkage_events.payment_currency is
  'Actual Cash payment currency selected by the user for the Cash confirmation request.';

comment on column public.school_personal_cash_linkage_events.payment_exchange_rate is
  'CNY per JPY exchange rate used to convert the School JPY wage cost into the Cash CNY payment amount. JPY payments use 1.';

comment on column public.school_personal_cash_linkage_events.payment_amount is
  'Actual Cash payment amount sent to Cash external transaction request.';

comment on column public.school_personal_cash_linkage_events.attempt_no is
  'Business retry attempt number for one School payment request Cash confirmation. Rejected attempts are retained as immutable history.';

drop function if exists public.school_request_cash_payment_confirmation(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
);

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
set search_path = public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_entity public.school_business_entities%rowtype;
  v_existing public.school_personal_cash_linkage_events%rowtype;
  v_latest public.school_personal_cash_linkage_events%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_idempotency_key text;
  v_school_amount_jpy numeric;
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_exchange_rate numeric;
  v_payment_amount numeric;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
begin
  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  if p_cash_user_id is null then
    raise exception 'Cash user id is required';
  end if;

  if p_cash_account_id is null then
    raise exception 'Cash account id is required';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'payment currency must be JPY or CNY. current currency: %', p_payment_currency;
  end if;

  select *
    into v_payment
    from public.school_payment_requests
   where school_payment_requests.id = p_payment_request_id
   for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if coalesce(v_payment.status, '') <> 'pending' then
    raise exception 'payment request status must be pending before Cash confirmation request. current status: %', v_payment.status;
  end if;

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests can request Cash confirmation. current source_type: %', v_payment.source_type;
  end if;

  v_school_amount_jpy := coalesce(
    nullif(v_payment.amount_jpy, 0),
    case when v_payment.currency = 'JPY' then v_payment.amount else null end
  );

  if coalesce(v_school_amount_jpy, 0) <= 0 then
    raise exception 'teacher_wage payment request must have a positive JPY cost amount';
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
  end if;

  if v_payment.reversed_at is not null then
    raise exception 'reversed payment requests cannot request Cash confirmation';
  end if;

  if v_payment.business_entity_id is null then
    raise exception 'payment request has no business_entity_id: %', p_payment_request_id;
  end if;

  select *
    into v_entity
    from public.school_business_entities
   where school_business_entities.id = v_payment.business_entity_id;

  if not found then
    raise exception 'business entity not found: %', v_payment.business_entity_id;
  end if;

  if v_entity.is_active is not true then
    raise exception 'business entity is inactive: %', v_entity.id;
  end if;

  if v_payment_currency = 'JPY' then
    v_exchange_rate := coalesce(p_exchange_rate, 1);
    if v_exchange_rate <> 1 then
      raise exception 'JPY Cash payment exchange_rate must be null or 1';
    end if;

    v_payment_amount := coalesce(p_payment_amount, v_school_amount_jpy);
    if v_payment_amount is distinct from v_school_amount_jpy then
      raise exception 'JPY Cash payment amount must match the School JPY wage amount';
    end if;

    v_cash_transaction_table := 'home_jpy_transactions';
  else
    if p_exchange_rate is null or p_exchange_rate <= 0 then
      raise exception 'CNY Cash payment requires a positive exchange_rate';
    end if;

    v_exchange_rate := p_exchange_rate;
    v_payment_amount := round(v_school_amount_jpy * v_exchange_rate, 2);

    if p_payment_amount is not null and p_payment_amount is distinct from v_payment_amount then
      raise exception 'CNY Cash payment amount does not match JPY wage amount times exchange_rate. expected: %, actual: %',
        v_payment_amount,
        p_payment_amount;
    end if;

    v_cash_transaction_table := 'home_cny_transactions';
  end if;

  if v_payment_amount <= 0 then
    raise exception 'Cash payment amount must be greater than 0';
  end if;

  select *
    into v_existing
    from public.school_personal_cash_linkage_events e
   where e.source_table = 'school_payment_requests'
     and e.source_id = p_payment_request_id
     and e.source_event_type = 'teacher_wage_payment_confirm'
     and e.sync_status in ('pending_cash_request', 'awaiting_cash_confirmation')
   for update;

  if found then
    if v_existing.payment_request_id is distinct from p_payment_request_id
       or v_existing.business_entity_id is distinct from v_payment.business_entity_id
       or v_existing.cash_user_id is distinct from p_cash_user_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.cash_account_name_snapshot is distinct from v_cash_account_name
       or v_existing.cash_account_type_snapshot is distinct from v_cash_account_type
       or v_existing.cash_transaction_table is distinct from v_cash_transaction_table
       or v_existing.currency is distinct from v_payment_currency
       or v_existing.amount is distinct from v_payment_amount
       or v_existing.school_amount_jpy is distinct from v_school_amount_jpy
       or v_existing.payment_currency is distinct from v_payment_currency
       or v_existing.payment_exchange_rate is distinct from v_exchange_rate
       or v_existing.payment_amount is distinct from v_payment_amount then
      raise exception 'existing Cash linkage event conflicts with requested Cash payment snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    if v_existing.sync_status not in ('pending_cash_request', 'awaiting_cash_confirmation') then
      raise exception 'existing Cash linkage event is not in a requestable state: %', v_existing.sync_status;
    end if;

    v_event_id := v_existing.id;
    v_attempt_no := v_existing.attempt_no;
    v_idempotency_key := v_existing.idempotency_key;
  else
    select *
      into v_latest
      from public.school_personal_cash_linkage_events e
     where e.source_table = 'school_payment_requests'
       and e.source_id = p_payment_request_id
       and e.source_event_type = 'teacher_wage_payment_confirm'
     order by e.attempt_no desc, e.created_at desc, e.id desc
     limit 1
     for update;

    if found and v_latest.sync_status <> 'cash_rejected' then
      raise exception 'latest Cash linkage event is not rejected or requestable: %', v_latest.sync_status;
    end if;

    v_attempt_no := coalesce(v_latest.attempt_no, 0) + 1;
    v_idempotency_key := concat(
      'aozora_school:school_payment_requests:',
      p_payment_request_id::text,
      ':teacher_wage_payment_confirm:attempt:',
      v_attempt_no::text
    );

    insert into public.school_personal_cash_linkage_events (
      source_table,
      source_id,
      source_event_type,
      payment_request_id,
      business_entity_id,
      cash_account_mapping_id,
      school_account_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      cash_transaction_table,
      cash_transaction_id,
      currency,
      amount,
      school_amount_jpy,
      payment_currency,
      payment_exchange_rate,
      payment_amount,
      idempotency_key,
      sync_status,
      attempt_no,
      cash_request_id,
      cash_request_status,
      requested_at,
      confirmed_at,
      rejected_at,
      rejected_reason,
      cash_request_last_checked_at,
      attempt_count,
      last_error,
      note,
      created_at,
      updated_at,
      synced_at
    )
    values (
      'school_payment_requests',
      p_payment_request_id,
      'teacher_wage_payment_confirm',
      p_payment_request_id,
      v_payment.business_entity_id,
      null,
      null,
      p_cash_user_id,
      p_cash_account_id,
      v_cash_account_name,
      v_cash_account_type,
      v_cash_transaction_table,
      null,
      v_payment_currency,
      v_payment_amount,
      v_school_amount_jpy,
      v_payment_currency,
      v_exchange_rate,
      v_payment_amount,
      v_idempotency_key,
      'pending_cash_request',
      v_attempt_no,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      0,
      null,
      v_note,
      v_now,
      v_now,
      null
    )
    returning school_personal_cash_linkage_events.id into v_event_id;
  end if;

  return query
  select
    e.payment_request_id,
    e.id,
    e.sync_status,
    e.attempt_no,
    e.idempotency_key,
    e.amount,
    e.currency,
    e.school_amount_jpy,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_account_type_snapshot,
    e.cash_request_id,
    e.cash_request_status,
    case
      when e.sync_status = 'awaiting_cash_confirmation' then 'Cash confirmation request already submitted'
      else 'School Cash confirmation request event is ready to submit'
    end::text
  from public.school_personal_cash_linkage_events e
  where e.id = v_event_id;
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
  'Creates or returns an all-scope teacher_wage Cash confirmation request event for a Cash-eligible JPY/CNY account. Does not mark the payment request paid, write School ledgers, create School expenses, or write Cash DB.';

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
) to authenticated, service_role;

comment on function public.school_mark_personal_cash_payment_request_confirmed(uuid, uuid, uuid, timestamptz) is
  'Reflects Cash approval of a teacher_wage JPY/CNY payment request. Marks the School payment request paid and linkage synced, without writing School ledgers or Cash DB.';

comment on function public.school_mark_personal_cash_payment_request_rejected(uuid, uuid, text, timestamptz) is
  'Reflects Cash rejection of a teacher_wage JPY/CNY payment request. Keeps the School payment request pending and linkage cash_rejected, without writing School ledgers or Cash DB.';
