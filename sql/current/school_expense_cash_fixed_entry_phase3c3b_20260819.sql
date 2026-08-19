-- School V2 x Cash Phase 3C3-B fixed attempt entry foundation.
-- Status: draft only / not executed.
-- The production fixed Gate remains blocked. This migration creates no fixed
-- attempt and does not implement approved_fixed, funded_fixed or corrected
-- writers.

lock table public.school_expense_records in share row exclusive mode;
lock table public.school_expense_cash_attempts in access exclusive mode;
lock table public.school_feature_gates in share row exclusive mode;

do $phase3c3b_precheck$
begin
  if exists (
    select 1 from public.school_expense_cash_attempts
    where payment_route = 'fixed_credit_card'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3C3B_FIXED_ATTEMPT_PREEXISTS';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_expense_attempt_writer_v2_enabled'
      and state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3C3B_IMMEDIATE_V2_GATE_NOT_ENABLED';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_fixed_credit_card_route_enabled'
      and state = 'blocked'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3C3B_FIXED_GATE_NOT_BLOCKED';
  end if;
end;
$phase3c3b_precheck$;

create or replace function public.school_expense_cash_fixed_attempt_payload_fingerprint_v2(
  p_expense_id uuid,
  p_attempt_no integer,
  p_request_type text,
  p_payment_route text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_card_instrument_id uuid,
  p_charge_date date,
  p_suggested_fixed_month date,
  p_target_fixed_month date,
  p_funding_date date,
  p_original_amount numeric,
  p_original_currency text,
  p_payment_amount numeric,
  p_payment_currency text
)
returns text
language sql
immutable
security invoker
set search_path = pg_catalog, public
as $function$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'fingerprint_contract', 'school_expense_cash_fixed_attempt_v2',
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
          'card_instrument_id', p_card_instrument_id,
          'charge_date', p_charge_date,
          'suggested_fixed_month', p_suggested_fixed_month,
          'target_fixed_month', p_target_fixed_month,
          'funding_date', p_funding_date,
          'original_amount', p_original_amount,
          'original_currency', p_original_currency,
          'settlement_amount', p_payment_amount,
          'settlement_currency', p_payment_currency
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$function$;

create or replace function public.school_expense_cash_attempt_payload_fingerprint_v3(
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
  p_card_instrument_id uuid,
  p_charge_date date,
  p_suggested_fixed_month date,
  p_target_fixed_month date,
  p_funding_date date
)
returns text
language sql
immutable
security invoker
set search_path = pg_catalog, public
as $function$
  select case p_payment_route
    when 'immediate_account' then
      public.school_expense_cash_attempt_payload_fingerprint_v2(
        p_expense_id, p_attempt_no, p_request_type, p_payment_route,
        p_request_event_id, p_idempotency_key, p_original_amount,
        p_original_currency, p_payment_amount, p_payment_currency,
        p_cash_funding_account_id, p_charge_date
      )
    when 'fixed_credit_card' then
      public.school_expense_cash_fixed_attempt_payload_fingerprint_v2(
        p_expense_id, p_attempt_no, p_request_type, p_payment_route,
        p_request_event_id, p_idempotency_key, p_card_instrument_id,
        p_charge_date, p_suggested_fixed_month, p_target_fixed_month,
        p_funding_date, p_original_amount, p_original_currency,
        p_payment_amount, p_payment_currency
      )
    else null
  end;
$function$;

alter table public.school_expense_cash_attempts
  drop constraint school_expense_cash_attempts_payload_fingerprint_check,
  drop constraint school_expense_cash_attempts_route_contract_check,
  drop constraint school_expense_cash_attempts_status_contract_check,
  drop column request_payload_fingerprint,
  alter column cash_funding_account_id drop not null;

alter table public.school_expense_cash_attempts
  add column request_payload_fingerprint text generated always as (
    public.school_expense_cash_attempt_payload_fingerprint_v3(
      expense_id,
      attempt_no,
      request_type,
      payment_route,
      request_event_id,
      idempotency_key,
      original_amount,
      original_currency,
      payment_amount,
      payment_currency,
      cash_funding_account_id,
      cash_card_instrument_id,
      charge_date,
      suggested_fixed_month,
      target_fixed_month,
      funding_date
    )
  ) stored;

alter table public.school_expense_cash_attempts
  alter column request_payload_fingerprint set not null,
  add constraint school_expense_cash_attempts_payload_fingerprint_check
    check (request_payload_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint school_expense_cash_attempts_route_contract_check check (
    (
      payment_route = 'immediate_account'
      and cash_funding_account_id is not null
      and cash_fixed_projection_id is null
      and cash_fixed_item_id is null
      and cash_card_instrument_id is null
      and suggested_fixed_month is null
      and target_fixed_month is null
      and funding_date is null
      and funded_at is null
      and attempt_status not in ('approved_fixed', 'funded_fixed')
    )
    or
    (
      payment_route = 'fixed_credit_card'
      and cash_funding_account_id is null
      and cash_card_instrument_id is not null
      and suggested_fixed_month is not null
      and target_fixed_month is not null
      and funding_date is not null
      and original_amount = payment_amount
      and original_currency = payment_currency
      and (
        attempt_status in ('prepared', 'submitted', 'rejected')
        or (
          attempt_status = 'approved_fixed'
          and cash_fixed_projection_id is not null
          and cash_fixed_item_id is not null
          and cash_transaction_id is null
        )
        or (
          attempt_status = 'funded_fixed'
          and cash_fixed_projection_id is not null
          and cash_fixed_item_id is not null
          and cash_transaction_id is not null
          and funded_at is not null
        )
        or attempt_status = 'corrected'
      )
    )
  ),
  add constraint school_expense_cash_attempts_status_contract_check check (
    (
      attempt_status = 'prepared'
      and cash_request_id is null and submitted_at is null
      and cash_transaction_id is null and cash_fixed_projection_id is null
      and cash_fixed_item_id is null and approved_at is null
      and rejected_at is null and funded_at is null and corrected_at is null
    )
    or
    (
      attempt_status = 'submitted'
      and cash_request_id is not null and submitted_at is not null
      and cash_transaction_id is null and cash_fixed_projection_id is null
      and cash_fixed_item_id is null and approved_at is null
      and rejected_at is null and funded_at is null and corrected_at is null
    )
    or
    (
      attempt_status = 'approved_immediate'
      and payment_route = 'immediate_account'
      and cash_request_id is not null and cash_transaction_id is not null
      and submitted_at is not null and approved_at is not null
      and rejected_at is null and funded_at is null and corrected_at is null
      and cash_fixed_projection_id is null and cash_fixed_item_id is null
    )
    or
    (
      attempt_status = 'approved_fixed'
      and payment_route = 'fixed_credit_card'
      and cash_request_id is not null and cash_transaction_id is null
      and cash_fixed_projection_id is not null and cash_fixed_item_id is not null
      and submitted_at is not null and approved_at is not null
      and rejected_at is null and funded_at is null and corrected_at is null
    )
    or
    (
      attempt_status = 'funded_fixed'
      and payment_route = 'fixed_credit_card'
      and cash_request_id is not null and cash_transaction_id is not null
      and cash_fixed_projection_id is not null and cash_fixed_item_id is not null
      and submitted_at is not null and approved_at is not null
      and funded_at is not null and rejected_at is null and corrected_at is null
    )
    or
    (
      attempt_status = 'rejected'
      and cash_request_id is not null and cash_transaction_id is null
      and cash_fixed_projection_id is null and cash_fixed_item_id is null
      and submitted_at is not null and approved_at is null
      and funded_at is null and rejected_at is not null and corrected_at is null
    )
    or
    (attempt_status = 'corrected' and corrected_at is not null)
  );

create or replace function public.school_guard_expense_cash_attempt_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_allowed_columns text[] := array[
    'cash_request_id','cash_transaction_id','cash_fixed_projection_id','cash_fixed_item_id',
    'attempt_status','submitted_at','approved_at','funded_at','rejected_at','corrected_at',
    'latest_error_code','latest_error_message','request_payload_fingerprint','callback_recovered_from_prepared',
    'callback_recovered_at','callback_recovery_source','version','updated_at'
  ];
  v_unexpected_columns text;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_DELETE_FORBIDDEN';
  end if;

  if tg_op = 'INSERT' then
    if new.payment_route = 'fixed_credit_card'
       and not exists (
         select 1 from public.school_feature_gates g
         where g.feature_key = 'cash_fixed_credit_card_route_enabled'
           and g.state = 'enabled'
       ) then
      raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
    end if;
    return new;
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if (to_jsonb(new) - v_allowed_columns) is distinct from (to_jsonb(old) - v_allowed_columns) then
    select string_agg(n.key, ',' order by n.key)
    into v_unexpected_columns
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o on o.key = n.key
    where n.value is distinct from o.value
      and not (n.key = any(v_allowed_columns));
    raise exception using errcode = '55000',
      message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_IMMUTABLE',
      detail = coalesce(v_unexpected_columns, 'unknown generated or structural column');
  end if;

  if old.payment_route = 'immediate_account' then
    if old.attempt_status = 'prepared' and new.attempt_status = 'submitted' then
      if new.version <> old.version + 1
         or old.cash_request_id is not null or new.cash_request_id is null
         or old.submitted_at is not null or new.submitted_at is null
         or new.cash_transaction_id is not null or new.approved_at is not null
         or new.rejected_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'submitted' and new.attempt_status = 'approved_immediate' then
      if new.version <> old.version + 1
         or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or old.cash_transaction_id is not null or new.cash_transaction_id is null
         or old.approved_at is not null or new.approved_at is null
         or new.rejected_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'submitted' and new.attempt_status = 'rejected' then
      if new.version <> old.version + 1
         or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null
         or old.rejected_at is not null or new.rejected_at is null
         or new.approved_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'prepared'
          and new.attempt_status in ('approved_immediate', 'rejected') then
      if new.version <> old.version + 2
         or new.cash_request_id is null or new.submitted_at is null
         or not new.callback_recovered_from_prepared
         or new.callback_recovered_at is null
         or new.callback_recovery_source <> 'sync-cash-request-result-v2'
         or (new.attempt_status = 'approved_immediate' and (new.cash_transaction_id is null or new.approved_at is null or new.rejected_at is not null))
         or (new.attempt_status = 'rejected' and (new.cash_transaction_id is not null or new.rejected_at is null or new.approved_at is not null)) then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_RECOVERY_VERSION_CONFLICT';
      end if;
    else
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_TRANSITION_FORBIDDEN';
    end if;
  else
    if old.attempt_status = 'prepared' and new.attempt_status = 'submitted' then
      if new.version <> old.version + 1
         or old.cash_request_id is not null or new.cash_request_id is null
         or old.submitted_at is not null or new.submitted_at is null
         or new.cash_transaction_id is not null or new.cash_fixed_projection_id is not null
         or new.cash_fixed_item_id is not null or new.approved_at is not null
         or new.rejected_at is not null or new.funded_at is not null
         or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'submitted' and new.attempt_status = 'rejected' then
      if new.version <> old.version + 1
         or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null or new.cash_fixed_projection_id is not null
         or new.cash_fixed_item_id is not null or new.approved_at is not null
         or old.rejected_at is not null or new.rejected_at is null
         or new.funded_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_VERSION_CONFLICT';
      end if;
    else
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_TRANSITION_FORBIDDEN';
    end if;
  end if;

  new.updated_at := statement_timestamp();
  return new;
end;
$function$;

create or replace function public.school_request_cash_fixed_expense_payment_confirmation_v2(
  p_expense_record_id uuid,
  p_cash_user_id uuid,
  p_card_instrument_id uuid,
  p_charge_date date,
  p_suggested_fixed_month date,
  p_target_fixed_month date,
  p_funding_date date,
  p_note text default null,
  p_external_source text default 'aozora_school',
  p_external_reference_type text default 'school_expense_records',
  p_external_reference_id uuid default null,
  p_request_type text default 'expense_paid',
  p_transaction_type text default 'expense',
  p_expected_request_event_id uuid default null,
  p_expected_idempotency_key text default null
)
returns table (
  expense_id uuid,
  request_event_id uuid,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  payment_route text,
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
  settlement_amount numeric,
  settlement_currency text,
  cash_user_id uuid,
  card_instrument_id uuid,
  charge_date date,
  suggested_fixed_month date,
  target_fixed_month date,
  funding_date date,
  cash_request_id uuid,
  cash_request_status text,
  attempt_id uuid,
  attempt_status text,
  attempt_version integer,
  request_payload_fingerprint text,
  cash_description text,
  cash_payload_snapshot jsonb,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_now timestamptz := statement_timestamp();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_attempt_no integer;
  v_event_id uuid;
  v_idempotency_key text;
  v_reuse_attempt boolean := false;
  v_cash_description text;
  v_cash_payload jsonb;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_expense_attempt_writer_v2_enabled' and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_fixed_credit_card_route_enabled' and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
  end if;

  if p_expense_record_id is null or p_cash_user_id is null
     or p_card_instrument_id is null or p_charge_date is null
     or p_suggested_fixed_month is null or p_target_fixed_month is null
     or p_funding_date is null then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_PREPARE_REQUIRED_INPUT';
  end if;
  if p_suggested_fixed_month <> date_trunc('month', p_suggested_fixed_month)::date
     or p_target_fixed_month <> date_trunc('month', p_target_fixed_month)::date
     or p_target_fixed_month <> p_suggested_fixed_month then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_SCHEDULE_INVALID';
  end if;
  if p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or coalesce(p_external_reference_id, p_expense_record_id) is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_EXTERNAL_IDENTITY_CONFLICT';
  end if;

  select * into v_expense
  from public.school_expense_records e
  where e.id = p_expense_record_id and e.app_type = 'school'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_RECORD_NOT_FOUND';
  end if;
  if v_expense.reversed_at is not null or v_expense.status = 'reversed' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_REVERSED_FORBIDDEN';
  end if;
  if v_expense.source_type = 'manual_cash' then
    if v_expense.cash_creation_event_id is null
       or v_expense.created_by_user_id is null
       or v_expense.account_id is not null
       or v_expense.payment_method is not null then
      raise exception using errcode = '55000', message = 'P0_MANUAL_CASH_EXPENSE_AUDIT_INVARIANT_VIOLATION';
    end if;
  elsif v_expense.source_type = 'teacher_wage' then
    if v_expense.source_id is null then
      raise exception using errcode = '55000', message = 'P0_TEACHER_WAGE_EXPENSE_SOURCE_ID_REQUIRED';
    end if;
  else
    raise exception using errcode = '42501', message = 'P0_EXPENSE_CASH_REQUEST_SOURCE_NOT_ALLOWED';
  end if;
  if v_expense.currency not in ('JPY', 'CNY') or coalesce(v_expense.amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_AMOUNT_OR_CURRENCY_INVALID';
  end if;
  if v_expense.status = 'paid' or v_expense.cash_transaction_id is not null
     or v_expense.cash_request_status in ('approved', 'synced') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ACTIVE_OR_COMPLETED_REQUEST_EXISTS';
  end if;

  v_reuse_attempt := v_expense.cash_request_status in ('pending_cash_request', 'pending')
    and v_expense.cash_request_event_id is not null;

  if v_reuse_attempt then
    select * into v_attempt
    from public.school_expense_cash_attempts a
    where a.expense_id = v_expense.id
      and a.request_event_id = v_expense.cash_request_event_id
    for update;
    if not found
       or (v_expense.cash_request_status = 'pending_cash_request' and (
         v_attempt.attempt_status <> 'prepared'
         or v_expense.cash_request_id is not null
         or v_attempt.cash_request_id is not null
       ))
       or (v_expense.cash_request_status = 'pending' and (
         v_attempt.attempt_status <> 'submitted'
         or v_expense.cash_request_id is null
         or v_attempt.cash_request_id is distinct from v_expense.cash_request_id
       )) then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_REUSABLE_ATTEMPT_MISSING';
    end if;
    if v_attempt.payment_route <> 'fixed_credit_card'
       or v_attempt.attempt_no is distinct from v_expense.cash_request_attempt_no
       or v_attempt.original_amount is distinct from v_expense.amount
       or v_attempt.original_currency is distinct from v_expense.currency
       or v_attempt.payment_amount is distinct from v_expense.amount
       or v_attempt.payment_currency is distinct from v_expense.currency
       or v_attempt.cash_funding_account_id is not null
       or v_attempt.cash_card_instrument_id is distinct from p_card_instrument_id
       or v_attempt.charge_date is distinct from p_charge_date
       or v_attempt.suggested_fixed_month is distinct from p_suggested_fixed_month
       or v_attempt.target_fixed_month is distinct from p_target_fixed_month
       or v_attempt.funding_date is distinct from p_funding_date
       or v_expense.cash_payment_amount is distinct from v_expense.amount
       or v_expense.cash_payment_currency is distinct from v_expense.currency
       or v_expense.cash_payment_note is distinct from v_note
       or (p_expected_request_event_id is not null and v_attempt.request_event_id is distinct from p_expected_request_event_id)
       or (p_expected_idempotency_key is not null and v_attempt.idempotency_key is distinct from p_expected_idempotency_key) then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT';
    end if;
  else
    v_attempt_no := coalesce(v_expense.cash_request_attempt_no, 0) + 1;
    v_event_id := gen_random_uuid();
    v_idempotency_key := format(
      'aozora_school:school_expense_records:%s:expense_paid:attempt:%s',
      v_expense.id,
      v_attempt_no
    );
    if p_expected_request_event_id is not null and p_expected_request_event_id is distinct from v_event_id then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_EXPECTED_EVENT_CONFLICT';
    end if;
    if p_expected_idempotency_key is not null and p_expected_idempotency_key is distinct from v_idempotency_key then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_EXPECTED_IDEMPOTENCY_CONFLICT';
    end if;

    insert into public.school_expense_cash_attempts(
      expense_id, attempt_no, payment_route, request_type, request_event_id,
      idempotency_key, cash_funding_account_id, cash_card_instrument_id,
      original_amount, original_currency, payment_amount, payment_currency,
      charge_date, suggested_fixed_month, target_fixed_month, funding_date,
      attempt_status, version
    ) values (
      v_expense.id, v_attempt_no, 'fixed_credit_card', 'expense_paid', v_event_id,
      v_idempotency_key, null, p_card_instrument_id,
      v_expense.amount, v_expense.currency, v_expense.amount, v_expense.currency,
      p_charge_date, p_suggested_fixed_month, p_target_fixed_month, p_funding_date,
      'prepared', 1
    ) returning * into v_attempt;

    update public.school_expense_records e
    set cash_request_event_id = v_attempt.request_event_id,
        cash_request_attempt_no = v_attempt.attempt_no,
        cash_request_status = 'pending_cash_request',
        cash_request_id = null,
        cash_transaction_id = null,
        cash_requested_at = v_now,
        cash_payment_amount = v_attempt.payment_amount,
        cash_payment_currency = v_attempt.payment_currency,
        cash_payment_note = v_note,
        cash_error_message = null,
        updated_at = v_now
    where e.id = v_expense.id
    returning * into v_expense;
  end if;

  v_cash_description := concat_ws(
    ' / ',
    case v_expense.expense_category
      when 'advertising' then '广告宣传'
      when 'classroom' then '教室费用'
      when 'other' then '其他'
      when 'software' then '软件服务'
      when 'tax_accounting' then '税务会计'
      when 'teacher_wage' then '老师工资'
      else v_expense.expense_category
    end,
    nullif(trim(coalesce(v_expense.payee_name_snapshot, '')), ''),
    v_expense.year_month,
    format('%s %s', v_attempt.payment_amount, v_attempt.payment_currency),
    '信用卡固定支出'
  );

  v_cash_payload := jsonb_build_object(
    'external_source', 'aozora_school',
    'external_event_id', v_attempt.request_event_id,
    'external_reference_type', 'school_expense_records',
    'external_reference_id', v_expense.id,
    'request_type', 'expense_paid',
    'transaction_type', 'expense',
    'payment_route', 'fixed_credit_card',
    'expense_record_id', v_expense.id,
    'expense_date', v_expense.expense_date,
    'year_month', v_expense.year_month,
    'expense_category', v_expense.expense_category,
    'source_type', v_expense.source_type,
    'source_id', v_expense.source_id,
    'payee_name_snapshot', v_expense.payee_name_snapshot,
    'description', v_expense.description,
    'original_currency', v_attempt.original_currency,
    'original_amount', v_attempt.original_amount,
    'settlement_amount', v_attempt.payment_amount,
    'settlement_currency', v_attempt.payment_currency,
    'card_instrument_id', v_attempt.cash_card_instrument_id,
    'charge_date', v_attempt.charge_date,
    'suggested_fixed_month', v_attempt.suggested_fixed_month,
    'target_fixed_month', v_attempt.target_fixed_month,
    'funding_date', v_attempt.funding_date,
    'account_id', null,
    'funding_account_id', null,
    'attempt_no', v_attempt.attempt_no,
    'school_expense_status', v_expense.status,
    'school_attempt_payload_fingerprint', v_attempt.request_payload_fingerprint,
    'note', v_note
  );

  return query select
    v_expense.id, v_attempt.request_event_id, v_attempt.attempt_no,
    v_attempt.idempotency_key, v_attempt.request_type, v_attempt.payment_route,
    v_expense.status, v_expense.expense_category, v_expense.source_type,
    v_expense.source_id, v_expense.payee_name_snapshot, v_expense.year_month,
    v_expense.expense_date, v_expense.description, v_attempt.original_amount,
    v_attempt.original_currency, v_attempt.payment_amount, v_attempt.payment_currency,
    p_cash_user_id, v_attempt.cash_card_instrument_id, v_attempt.charge_date,
    v_attempt.suggested_fixed_month, v_attempt.target_fixed_month,
    v_attempt.funding_date, v_expense.cash_request_id, v_expense.cash_request_status,
    v_attempt.id, v_attempt.attempt_status, v_attempt.version,
    v_attempt.request_payload_fingerprint, v_cash_description, v_cash_payload,
    case when v_reuse_attempt
      then format('existing %s fixed Cash expense attempt reused', v_attempt.attempt_status)
      else 'fixed Cash expense attempt prepared'
    end;
end;
$function$;

create or replace function public.school_apply_expense_cash_fixed_attempt_transition_v2(
  p_action text,
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_cash_request_status text,
  p_payment_route text,
  p_external_source text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_external_reference_type text,
  p_external_reference_id uuid,
  p_request_type text,
  p_transaction_type text,
  p_settlement_amount numeric,
  p_settlement_currency text,
  p_card_instrument_id uuid,
  p_charge_date date,
  p_suggested_fixed_month date,
  p_target_fixed_month date,
  p_funding_date date,
  p_account_id uuid,
  p_funding_account_id uuid,
  p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null,
  p_fixed_projection_id uuid default null,
  p_result_at timestamptz default null,
  p_rejected_reason text default null
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  attempt_id uuid,
  attempt_status text,
  attempt_version integer,
  idempotent boolean,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_action text := lower(nullif(trim(coalesce(p_action, '')), ''));
  v_status text := lower(nullif(trim(coalesce(p_cash_request_status, '')), ''));
  v_currency text := upper(nullif(trim(coalesce(p_settlement_currency, '')), ''));
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
  v_now timestamptz := p_result_at;
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_expected_fingerprint text;
  v_idempotent boolean := false;
begin
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_expense_attempt_writer_v2_enabled' and state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_fixed_credit_card_route_enabled' and state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
  end if;
  if v_action not in ('submitted', 'rejected') then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_ACTION_INVALID';
  end if;
  if p_expense_record_id is null or p_cash_request_id is null
     or p_request_event_id is null or p_external_reference_id is null
     or p_card_instrument_id is null or p_charge_date is null
     or p_suggested_fixed_month is null or p_target_fixed_month is null
     or p_funding_date is null or coalesce(p_settlement_amount, 0) <= 0
     or nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or nullif(trim(coalesce(p_request_payload_fingerprint, '')), '') is null then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_EVIDENCE_REQUIRED';
  end if;
  if p_payment_route is distinct from 'fixed_credit_card'
     or p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or p_external_reference_id is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense'
     or p_account_id is not null or p_funding_account_id is not null
     or v_currency not in ('JPY', 'CNY') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_EXTERNAL_IDENTITY_CONFLICT';
  end if;
  if (v_action = 'submitted' and v_status <> 'pending')
     or (v_action = 'rejected' and v_status <> 'rejected') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_STATUS_CONFLICT';
  end if;
  if v_action = 'rejected' and v_now is null then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_REJECTED_AT_REQUIRED';
  end if;
  if v_action = 'submitted' then
    v_now := statement_timestamp();
  end if;
  if p_cash_transaction_id is not null or p_fixed_projection_id is not null then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_DOWNSTREAM_FACT_FORBIDDEN';
  end if;

  select * into v_expense
  from public.school_expense_records e
  where e.id = p_expense_record_id and e.app_type = 'school'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_RECORD_NOT_FOUND';
  end if;

  select * into v_attempt
  from public.school_expense_cash_attempts a
  where a.expense_id = p_expense_record_id
    and a.request_event_id = p_request_event_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_NOT_FOUND';
  end if;

  v_expected_fingerprint := public.school_expense_cash_attempt_payload_fingerprint_v3(
    v_attempt.expense_id, v_attempt.attempt_no, v_attempt.request_type,
    v_attempt.payment_route, v_attempt.request_event_id, v_attempt.idempotency_key,
    v_attempt.original_amount, v_attempt.original_currency,
    v_attempt.payment_amount, v_attempt.payment_currency,
    v_attempt.cash_funding_account_id, v_attempt.cash_card_instrument_id,
    v_attempt.charge_date, v_attempt.suggested_fixed_month,
    v_attempt.target_fixed_month, v_attempt.funding_date
  );

  if v_attempt.payment_route <> 'fixed_credit_card'
     or v_attempt.idempotency_key is distinct from p_idempotency_key
     or v_attempt.payment_amount is distinct from p_settlement_amount
     or v_attempt.payment_currency is distinct from v_currency
     or v_attempt.cash_funding_account_id is not null
     or v_attempt.cash_card_instrument_id is distinct from p_card_instrument_id
     or v_attempt.charge_date is distinct from p_charge_date
     or v_attempt.suggested_fixed_month is distinct from p_suggested_fixed_month
     or v_attempt.target_fixed_month is distinct from p_target_fixed_month
     or v_attempt.funding_date is distinct from p_funding_date
     or v_attempt.request_payload_fingerprint is distinct from v_expected_fingerprint
     or v_attempt.request_payload_fingerprint is distinct from p_request_payload_fingerprint then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT';
  end if;
  if v_attempt.cash_request_id is not null
     and v_attempt.cash_request_id is distinct from p_cash_request_id then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REQUEST_ID_CONFLICT';
  end if;
  if v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no
     or v_expense.cash_payment_amount is distinct from v_attempt.payment_amount
     or v_expense.cash_payment_currency is distinct from v_attempt.payment_currency then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_LATEST_STATE_CONFLICT';
  end if;

  if v_action = 'submitted' then
    if v_attempt.attempt_status = 'submitted' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_status is distinct from 'pending' then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status <> 'prepared' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_TRANSITION_FORBIDDEN';
    else
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_PREPARED_LATEST_STATE_CONFLICT';
      end if;
      update public.school_expense_cash_attempts a
      set cash_request_id = p_cash_request_id,
          submitted_at = v_now,
          attempt_status = 'submitted',
          latest_error_code = null,
          latest_error_message = null,
          version = a.version + 1
      where a.id = v_attempt.id
      returning * into v_attempt;

      update public.school_expense_records e
      set cash_request_id = p_cash_request_id,
          cash_request_status = 'pending',
          cash_requested_at = coalesce(e.cash_requested_at, v_now),
          cash_error_message = null,
          updated_at = v_now
      where e.id = v_expense.id
      returning * into v_expense;
    end if;
  else
    if v_attempt.attempt_status = 'rejected' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.rejected_at is distinct from p_result_at
         or v_attempt.latest_error_message is distinct from coalesce(v_reason, 'Cash request rejected')
         or v_expense.cash_request_status is distinct from 'rejected'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_REJECTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status <> 'submitted' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_REJECTED_TRANSITION_FORBIDDEN';
    else
      update public.school_expense_cash_attempts a
      set rejected_at = v_now,
          attempt_status = 'rejected',
          latest_error_code = 'CASH_REQUEST_REJECTED',
          latest_error_message = coalesce(v_reason, 'Cash request rejected'),
          version = a.version + 1
      where a.id = v_attempt.id
      returning * into v_attempt;

      update public.school_expense_records e
      set cash_request_id = p_cash_request_id,
          cash_request_status = 'rejected',
          cash_synced_at = v_now,
          cash_error_message = coalesce(v_reason, 'Cash request rejected'),
          updated_at = v_now
      where e.id = v_expense.id
      returning * into v_expense;
    end if;
  end if;

  return query select
    v_expense.id, v_expense.status, v_expense.cash_request_id,
    v_expense.cash_request_status, v_attempt.id, v_attempt.attempt_status,
    v_attempt.version, v_idempotent,
    case when v_idempotent
      then format('fixed Cash expense attempt %s callback already applied', v_action)
      else format('fixed Cash expense attempt marked %s', v_action)
    end;
end;
$function$;

create or replace function public.school_mark_cash_fixed_expense_request_submitted_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid,
  p_idempotency_key text, p_external_reference_type text,
  p_external_reference_id uuid, p_request_type text, p_transaction_type text,
  p_settlement_amount numeric, p_settlement_currency text,
  p_card_instrument_id uuid, p_charge_date date,
  p_suggested_fixed_month date, p_target_fixed_month date, p_funding_date date,
  p_account_id uuid, p_funding_account_id uuid,
  p_request_payload_fingerprint text, p_cash_transaction_id uuid default null,
  p_fixed_projection_id uuid default null
)
returns table (
  expense_id uuid, expense_status text, cash_request_id uuid,
  cash_request_status text, attempt_id uuid, attempt_status text,
  attempt_version integer, idempotent boolean, message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select * from public.school_apply_expense_cash_fixed_attempt_transition_v2(
    'submitted', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_payment_route, p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_settlement_amount, p_settlement_currency,
    p_card_instrument_id, p_charge_date, p_suggested_fixed_month,
    p_target_fixed_month, p_funding_date, p_account_id, p_funding_account_id,
    p_request_payload_fingerprint, p_cash_transaction_id,
    p_fixed_projection_id, null, null
  );
$function$;

create or replace function public.school_mark_cash_fixed_expense_rejected_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid,
  p_idempotency_key text, p_external_reference_type text,
  p_external_reference_id uuid, p_request_type text, p_transaction_type text,
  p_settlement_amount numeric, p_settlement_currency text,
  p_card_instrument_id uuid, p_charge_date date,
  p_suggested_fixed_month date, p_target_fixed_month date, p_funding_date date,
  p_account_id uuid, p_funding_account_id uuid,
  p_request_payload_fingerprint text, p_cash_transaction_id uuid default null,
  p_fixed_projection_id uuid default null, p_rejected_reason text default null,
  p_rejected_at timestamptz default null
)
returns table (
  expense_id uuid, expense_status text, cash_request_id uuid,
  cash_request_status text, attempt_id uuid, attempt_status text,
  attempt_version integer, idempotent boolean, message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select * from public.school_apply_expense_cash_fixed_attempt_transition_v2(
    'rejected', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_payment_route, p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_settlement_amount, p_settlement_currency,
    p_card_instrument_id, p_charge_date, p_suggested_fixed_month,
    p_target_fixed_month, p_funding_date, p_account_id, p_funding_account_id,
    p_request_payload_fingerprint, p_cash_transaction_id,
    p_fixed_projection_id, p_rejected_at, p_rejected_reason
  );
$function$;

alter function public.school_expense_cash_fixed_attempt_payload_fingerprint_v2(uuid,integer,text,text,uuid,text,uuid,date,date,date,date,numeric,text,numeric,text) owner to postgres;
alter function public.school_expense_cash_attempt_payload_fingerprint_v3(uuid,integer,text,text,uuid,text,numeric,text,numeric,text,uuid,uuid,date,date,date,date) owner to postgres;
alter function public.school_guard_expense_cash_attempt_v1() owner to postgres;
alter function public.school_request_cash_fixed_expense_payment_confirmation_v2(uuid,uuid,uuid,date,date,date,date,text,text,text,uuid,text,text,uuid,text) owner to postgres;
alter function public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text) owner to postgres;
alter function public.school_mark_cash_fixed_expense_request_submitted_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid) owner to postgres;
alter function public.school_mark_cash_fixed_expense_rejected_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,timestamptz) owner to postgres;

revoke all on function public.school_expense_cash_fixed_attempt_payload_fingerprint_v2(uuid,integer,text,text,uuid,text,uuid,date,date,date,date,numeric,text,numeric,text) from public, anon, authenticated, service_role;
revoke all on function public.school_expense_cash_attempt_payload_fingerprint_v3(uuid,integer,text,text,uuid,text,numeric,text,numeric,text,uuid,uuid,date,date,date,date) from public, anon, authenticated, service_role;
revoke all on function public.school_guard_expense_cash_attempt_v1() from public, anon, authenticated, service_role;
revoke all on function public.school_request_cash_fixed_expense_payment_confirmation_v2(uuid,uuid,uuid,date,date,date,date,text,text,text,uuid,text,text,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text) from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_fixed_expense_request_submitted_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_fixed_expense_rejected_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,timestamptz) from public, anon, authenticated, service_role;

grant execute on function public.school_request_cash_fixed_expense_payment_confirmation_v2(uuid,uuid,uuid,date,date,date,date,text,text,text,uuid,text,text,uuid,text) to service_role;
grant execute on function public.school_mark_cash_fixed_expense_request_submitted_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid) to service_role;
grant execute on function public.school_mark_cash_fixed_expense_rejected_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,timestamptz) to service_role;

comment on function public.school_expense_cash_fixed_attempt_payload_fingerprint_v2(uuid,integer,text,text,uuid,text,uuid,date,date,date,date,numeric,text,numeric,text) is
  'Phase 3C3-B fixed-route SHA-256 authority. Covers School expense/attempt identity, card, charge/schedule, exact settlement, event, idempotency and canonical external reference; funding account is intentionally absent.';
comment on function public.school_request_cash_fixed_expense_payment_confirmation_v2(uuid,uuid,uuid,date,date,date,date,text,text,text,uuid,text,text,uuid,text) is
  'Phase 3C3-B service-only fixed prepare writer. Requires both Gates, locks the expense, freezes the home DB schedule, creates/reuses one prepared attempt and atomically updates the expense latest-state mirror.';
comment on function public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text) is
  'Owner-only Phase 3C3-B fixed submitted/rejected transition core. It accepts no approval/funding action and requires full null-account/no-downstream evidence.';
comment on column public.school_expense_cash_attempts.cash_funding_account_id is
  'Required for immediate_account attempts and required NULL for fixed_credit_card attempts; School never selects or backfills the future fixed funding account.';
comment on column public.school_expense_cash_attempts.request_payload_fingerprint is
  'Database-generated route-specific SHA-256. Existing immediate rows retain the V2 fingerprint contract; fixed rows use the Phase 3C3-B fixed fingerprint contract.';
