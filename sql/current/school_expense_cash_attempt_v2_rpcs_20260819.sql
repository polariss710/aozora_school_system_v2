-- Phase 3C2-R School expense Cash attempt V2 business wrappers and owner-only transition core.
-- Prerequisites: fingerprint helper and schema/backfill files from this phase.

create or replace function public.school_apply_expense_cash_attempt_transition_v2(
  p_action text,
  p_expense_record_id uuid,
  p_cash_request_id uuid,
  p_cash_request_status text,
  p_external_source text,
  p_request_event_id uuid,
  p_idempotency_key text,
  p_external_reference_type text,
  p_external_reference_id uuid,
  p_request_type text,
  p_transaction_type text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_cash_account_id uuid,
  p_charge_date date,
  p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null,
  p_result_at timestamptz default null,
  p_rejected_reason text default null,
  p_recovery_source text default null
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  attempt_id uuid,
  attempt_status text,
  attempt_version integer,
  callback_recovered_from_prepared boolean,
  idempotent boolean,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_action text := lower(nullif(trim(coalesce(p_action, '')), ''));
  v_currency text := upper(nullif(trim(coalesce(p_payment_currency, '')), ''));
  v_status text := lower(nullif(trim(coalesce(p_cash_request_status, '')), ''));
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
  v_now timestamptz := coalesce(p_result_at, statement_timestamp());
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_expected_fingerprint text;
  v_idempotent boolean := false;
  v_recovered boolean := false;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_expense_attempt_writer_v2_enabled'
      and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;

  if v_action not in ('submitted', 'approved', 'rejected') then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_ACTION_INVALID';
  end if;

  if p_expense_record_id is null or p_cash_request_id is null or p_request_event_id is null
     or p_external_reference_id is null or p_cash_account_id is null or p_charge_date is null
     or nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or nullif(trim(coalesce(p_request_payload_fingerprint, '')), '') is null
     or coalesce(p_payment_amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_EVIDENCE_REQUIRED';
  end if;

  if p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or p_external_reference_id is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense'
     or v_currency not in ('JPY', 'CNY') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_EXTERNAL_IDENTITY_CONFLICT';
  end if;

  if (v_action = 'submitted' and v_status <> 'pending')
     or (v_action = 'approved' and v_status <> 'approved')
     or (v_action = 'rejected' and v_status <> 'rejected') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_CASH_STATUS_CONFLICT';
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

  if v_attempt.payment_route <> 'immediate_account'
     or v_attempt.request_type <> 'expense_paid'
     or v_attempt.idempotency_key is distinct from p_idempotency_key
     or v_attempt.payment_amount is distinct from p_payment_amount
     or v_attempt.payment_currency is distinct from v_currency
     or v_attempt.cash_funding_account_id is distinct from p_cash_account_id
     or v_attempt.charge_date is distinct from p_charge_date
     or v_attempt.request_payload_fingerprint is distinct from v_expected_fingerprint
     or v_attempt.request_payload_fingerprint is distinct from p_request_payload_fingerprint then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_PAYLOAD_CONFLICT';
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
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_SUBMITTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status <> 'prepared' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_SUBMITTED_TRANSITION_FORBIDDEN';
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
  elsif v_action = 'approved' then
    if p_cash_transaction_id is null then
      raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_TRANSACTION_REQUIRED';
    end if;

    if exists (
      select 1 from public.school_expense_cash_attempts a
      where a.cash_transaction_id = p_cash_transaction_id
        and a.id <> v_attempt.id
    ) then
      raise exception using errcode = '23505', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_TRANSACTION_ALREADY_USED';
    end if;

    if v_attempt.attempt_status = 'approved_immediate' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.cash_transaction_id is distinct from p_cash_transaction_id
         or v_expense.status is distinct from 'paid'
         or v_expense.cash_request_status is distinct from 'approved'
         or v_expense.cash_transaction_id is distinct from p_cash_transaction_id then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_APPROVED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status = 'rejected' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REJECTED_CANNOT_APPROVE';
    elsif v_attempt.attempt_status = 'prepared' then
      if p_recovery_source is distinct from 'sync-cash-request-result-v2'
         or v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_APPROVED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a
         set cash_request_id = p_cash_request_id,
             submitted_at = v_now,
             cash_transaction_id = p_cash_transaction_id,
             approved_at = v_now,
             attempt_status = 'approved_immediate',
             callback_recovered_from_prepared = true,
             callback_recovered_at = v_now,
             callback_recovery_source = 'sync-cash-request-result-v2',
             latest_error_code = null,
             latest_error_message = null,
             version = a.version + 2
       where a.id = v_attempt.id
       returning * into v_attempt;
    elsif v_attempt.attempt_status = 'submitted' then
      update public.school_expense_cash_attempts a
         set cash_transaction_id = p_cash_transaction_id,
             approved_at = v_now,
             attempt_status = 'approved_immediate',
             latest_error_code = null,
             latest_error_message = null,
             version = a.version + 1
       where a.id = v_attempt.id
       returning * into v_attempt;
    else
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_APPROVED_TRANSITION_FORBIDDEN';
    end if;

    if not v_idempotent then
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
    end if;
  else
    if p_cash_transaction_id is not null then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REJECTED_TRANSACTION_FORBIDDEN';
    end if;

    if v_attempt.attempt_status = 'rejected' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_status is distinct from 'rejected'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REJECTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status = 'approved_immediate' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_APPROVED_CANNOT_REJECT';
    elsif v_attempt.attempt_status = 'prepared' then
      if p_recovery_source is distinct from 'sync-cash-request-result-v2'
         or v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REJECTED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a
         set cash_request_id = p_cash_request_id,
             submitted_at = v_now,
             rejected_at = v_now,
             attempt_status = 'rejected',
             callback_recovered_from_prepared = true,
             callback_recovered_at = v_now,
             callback_recovery_source = 'sync-cash-request-result-v2',
             latest_error_code = 'CASH_REQUEST_REJECTED',
             latest_error_message = coalesce(v_reason, 'Cash request rejected'),
             version = a.version + 2
       where a.id = v_attempt.id
       returning * into v_attempt;
    elsif v_attempt.attempt_status = 'submitted' then
      update public.school_expense_cash_attempts a
         set rejected_at = v_now,
             attempt_status = 'rejected',
             latest_error_code = 'CASH_REQUEST_REJECTED',
             latest_error_message = coalesce(v_reason, 'Cash request rejected'),
             version = a.version + 1
       where a.id = v_attempt.id
       returning * into v_attempt;
    else
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_REJECTED_TRANSITION_FORBIDDEN';
    end if;

    if not v_idempotent then
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
    v_expense.id,
    v_expense.status,
    v_expense.cash_request_id,
    v_expense.cash_request_status,
    v_expense.cash_transaction_id,
    v_attempt.id,
    v_attempt.attempt_status,
    v_attempt.version,
    v_attempt.callback_recovered_from_prepared,
    v_idempotent,
    case
      when v_idempotent then format('Cash expense attempt %s callback already applied', v_action)
      when v_recovered then format('Cash expense attempt recovered from prepared and marked %s', v_action)
      else format('Cash expense attempt marked %s', v_action)
    end;
end;
$function$;

alter function public.school_apply_expense_cash_attempt_transition_v2(
  text,uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text,text
) owner to postgres;
revoke all on function public.school_apply_expense_cash_attempt_transition_v2(
  text,uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text,text
) from public, anon, authenticated, service_role;

create or replace function public.school_request_cash_expense_payment_confirmation_v2(
  p_expense_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_actual_payment_date date,
  p_cash_account_type_snapshot text default null,
  p_payment_amount numeric default null,
  p_payment_currency text default null,
  p_note text default null,
  p_exchange_rate numeric default null,
  p_payment_rounding_mode text default null,
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
  actual_payment_date date,
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
  v_payment_amount numeric := p_payment_amount;
  v_payment_currency text := upper(nullif(trim(coalesce(p_payment_currency, '')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_rounding_mode text := lower(trim(coalesce(p_payment_rounding_mode, '')));
  v_computed_amount numeric;
  v_attempt_no integer;
  v_event_id uuid;
  v_idempotency_key text;
  v_reuse_prepared boolean := false;
  v_cash_description text;
  v_cash_payload jsonb;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_expense_attempt_writer_v2_enabled'
      and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;

  if p_expense_record_id is null or p_cash_user_id is null or p_cash_account_id is null
     or p_actual_payment_date is null or v_account_name is null then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_PREPARE_V2_REQUIRED_INPUT';
  end if;

  if p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or coalesce(p_external_reference_id, p_expense_record_id) is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_EXTERNAL_IDENTITY_CONFLICT';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_EXCHANGE_RATE_INVALID';
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

  if v_expense.status = 'paid' or v_expense.cash_transaction_id is not null
     or v_expense.cash_request_status in ('pending', 'approved', 'synced') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ACTIVE_OR_COMPLETED_REQUEST_EXISTS';
  end if;

  if v_payment_currency is null then
    v_payment_currency := upper(v_expense.currency);
  end if;
  if v_payment_currency not in ('JPY', 'CNY') or v_expense.currency not in ('JPY', 'CNY') then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_CURRENCY_INVALID';
  end if;

  if v_expense.currency <> v_payment_currency and coalesce(p_exchange_rate, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_CROSS_CURRENCY_RATE_REQUIRED';
  elsif v_expense.currency = v_payment_currency then
    if p_exchange_rate is not null and p_exchange_rate <> 1 then
      raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_SAME_CURRENCY_RATE_INVALID';
    end if;
    v_payment_amount := coalesce(v_payment_amount, v_expense.amount);
  elsif v_payment_amount is null then
    if v_rounding_mode not in ('round', 'ceil', 'floor') then
      raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_ROUNDING_MODE_REQUIRED';
    end if;
    v_computed_amount := case
      when v_expense.currency = 'JPY' and v_payment_currency = 'CNY' then v_expense.amount * p_exchange_rate
      when v_expense.currency = 'CNY' and v_payment_currency = 'JPY' then v_expense.amount / p_exchange_rate
    end;
    v_payment_amount := case v_rounding_mode
      when 'ceil' then ceil(v_computed_amount)
      when 'floor' then floor(v_computed_amount)
      else round(v_computed_amount)
    end;
  end if;

  if coalesce(v_payment_amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_PAYMENT_AMOUNT_INVALID';
  end if;

  v_reuse_prepared := v_expense.cash_request_status = 'pending_cash_request'
    and v_expense.cash_request_event_id is not null
    and v_expense.cash_request_id is null;

  if v_reuse_prepared then
    select * into v_attempt
    from public.school_expense_cash_attempts a
    where a.expense_id = v_expense.id
      and a.request_event_id = v_expense.cash_request_event_id
    for update;

    if not found or v_attempt.attempt_status <> 'prepared' then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_PREPARED_ATTEMPT_MISSING';
    end if;

    if v_attempt.payment_route <> 'immediate_account'
       or v_attempt.attempt_no is distinct from v_expense.cash_request_attempt_no
       or v_attempt.original_amount is distinct from v_expense.amount
       or v_attempt.original_currency is distinct from v_expense.currency
       or v_attempt.payment_amount is distinct from v_payment_amount
       or v_attempt.payment_currency is distinct from v_payment_currency
       or v_attempt.cash_funding_account_id is distinct from p_cash_account_id
       or v_attempt.charge_date is distinct from p_actual_payment_date
       or v_expense.cash_payment_amount is distinct from v_payment_amount
       or v_expense.cash_payment_currency is distinct from v_payment_currency
       or v_expense.cash_payment_note is distinct from v_note
       or (p_expected_request_event_id is not null and v_attempt.request_event_id is distinct from p_expected_request_event_id)
       or (p_expected_idempotency_key is not null and v_attempt.idempotency_key is distinct from p_expected_idempotency_key) then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_PREPARE_V2_PAYLOAD_CONFLICT';
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
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_PREPARE_V2_EXPECTED_EVENT_CONFLICT';
    end if;
    if p_expected_idempotency_key is not null and p_expected_idempotency_key is distinct from v_idempotency_key then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_PREPARE_V2_EXPECTED_IDEMPOTENCY_CONFLICT';
    end if;

    insert into public.school_expense_cash_attempts(
      expense_id, attempt_no, payment_route, request_type, request_event_id,
      idempotency_key, cash_funding_account_id, original_amount, original_currency,
      payment_amount, payment_currency, charge_date, attempt_status, version
    ) values (
      v_expense.id, v_attempt_no, 'immediate_account', 'expense_paid', v_event_id,
      v_idempotency_key, p_cash_account_id, v_expense.amount, v_expense.currency,
      v_payment_amount, v_payment_currency, p_actual_payment_date, 'prepared', 1
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
    format('%s %s', v_attempt.payment_amount, v_attempt.payment_currency)
  );

  v_cash_payload := jsonb_build_object(
    'external_source', 'aozora_school',
    'external_event_id', v_attempt.request_event_id,
    'external_reference_type', 'school_expense_records',
    'external_reference_id', v_expense.id,
    'request_type', 'expense_paid',
    'transaction_type', 'expense',
    'expense_record_id', v_expense.id,
    'expense_date', v_expense.expense_date,
    'actual_payment_date', v_attempt.charge_date,
    'year_month', v_expense.year_month,
    'expense_category', v_expense.expense_category,
    'source_type', v_expense.source_type,
    'source_id', v_expense.source_id,
    'payee_name_snapshot', v_expense.payee_name_snapshot,
    'description', v_expense.description,
    'original_currency', v_attempt.original_currency,
    'original_amount', v_attempt.original_amount,
    'original_amount_jpy', v_expense.amount_jpy,
    'original_amount_cny', v_expense.amount_cny,
    'actual_payment_amount', v_attempt.payment_amount,
    'actual_payment_currency', v_attempt.payment_currency,
    'account_id', v_attempt.cash_funding_account_id,
    'cash_account_name_snapshot', v_account_name,
    'cash_account_type_snapshot', v_account_type,
    'attempt_no', v_attempt.attempt_no,
    'school_expense_status', v_expense.status,
    'school_attempt_payload_fingerprint', v_attempt.request_payload_fingerprint,
    'note', v_note
  );

  return query select
    v_expense.id, v_attempt.request_event_id, v_attempt.attempt_no,
    v_attempt.idempotency_key, v_attempt.request_type, v_expense.status,
    v_expense.expense_category, v_expense.source_type, v_expense.source_id,
    v_expense.payee_name_snapshot, v_expense.year_month, v_expense.expense_date,
    v_expense.description, v_attempt.original_amount, v_attempt.original_currency,
    v_expense.amount_jpy, v_expense.amount_cny, v_attempt.payment_amount,
    v_attempt.payment_currency, p_cash_user_id, v_attempt.cash_funding_account_id,
    v_account_name, v_account_type, v_attempt.charge_date, v_expense.cash_request_id,
    v_expense.cash_request_status, v_attempt.id, v_attempt.attempt_status,
    v_attempt.version, v_attempt.request_payload_fingerprint, v_cash_description,
    v_cash_payload,
    case when v_reuse_prepared
      then 'existing prepared Cash expense attempt reused'
      else 'Cash expense attempt prepared'
    end;
end;
$function$;

alter function public.school_request_cash_expense_payment_confirmation_v2(
  uuid,uuid,uuid,text,date,text,numeric,text,text,numeric,text,text,text,uuid,text,text,uuid,text
) owner to postgres;
revoke all on function public.school_request_cash_expense_payment_confirmation_v2(
  uuid,uuid,uuid,text,date,text,numeric,text,text,numeric,text,text,text,uuid,text,text,uuid,text
) from public, anon, authenticated, service_role;
grant execute on function public.school_request_cash_expense_payment_confirmation_v2(
  uuid,uuid,uuid,text,date,text,numeric,text,text,numeric,text,text,text,uuid,text,text,uuid,text
) to service_role;

create or replace function public.school_mark_cash_expense_request_submitted_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_external_source text, p_request_event_id uuid, p_idempotency_key text,
  p_external_reference_type text, p_external_reference_id uuid, p_request_type text,
  p_transaction_type text, p_payment_amount numeric, p_payment_currency text,
  p_cash_account_id uuid, p_charge_date date, p_request_payload_fingerprint text
)
returns table (
  expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text,
  attempt_id uuid, attempt_status text, attempt_version integer, idempotent boolean, message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select x.expense_id, x.expense_status, x.cash_request_id, x.cash_request_status,
         x.attempt_id, x.attempt_status, x.attempt_version, x.idempotent, x.message
  from public.school_apply_expense_cash_attempt_transition_v2(
    'submitted', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_payment_amount, p_payment_currency, p_cash_account_id,
    p_charge_date, p_request_payload_fingerprint, null, null, null, null
  ) x;
$function$;

create or replace function public.school_mark_cash_expense_confirmed_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_external_source text, p_request_event_id uuid, p_idempotency_key text,
  p_external_reference_type text, p_external_reference_id uuid, p_request_type text,
  p_transaction_type text, p_payment_amount numeric, p_payment_currency text,
  p_cash_account_id uuid, p_charge_date date, p_request_payload_fingerprint text,
  p_cash_transaction_id uuid, p_confirmed_at timestamptz default null,
  p_recovery_source text default null
)
returns table (
  expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text,
  cash_transaction_id uuid, attempt_id uuid, attempt_status text, attempt_version integer,
  callback_recovered_from_prepared boolean, idempotent boolean, message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select x.expense_id, x.expense_status, x.cash_request_id, x.cash_request_status,
         x.cash_transaction_id, x.attempt_id, x.attempt_status, x.attempt_version,
         x.callback_recovered_from_prepared, x.idempotent, x.message
  from public.school_apply_expense_cash_attempt_transition_v2(
    'approved', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_payment_amount, p_payment_currency, p_cash_account_id,
    p_charge_date, p_request_payload_fingerprint, p_cash_transaction_id,
    p_confirmed_at, null, p_recovery_source
  ) x;
$function$;

create or replace function public.school_mark_cash_expense_rejected_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_external_source text, p_request_event_id uuid, p_idempotency_key text,
  p_external_reference_type text, p_external_reference_id uuid, p_request_type text,
  p_transaction_type text, p_payment_amount numeric, p_payment_currency text,
  p_cash_account_id uuid, p_charge_date date, p_request_payload_fingerprint text,
  p_rejected_reason text default null, p_rejected_at timestamptz default null,
  p_recovery_source text default null
)
returns table (
  expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text,
  attempt_id uuid, attempt_status text, attempt_version integer,
  callback_recovered_from_prepared boolean, idempotent boolean, message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select x.expense_id, x.expense_status, x.cash_request_id, x.cash_request_status,
         x.attempt_id, x.attempt_status, x.attempt_version,
         x.callback_recovered_from_prepared, x.idempotent, x.message
  from public.school_apply_expense_cash_attempt_transition_v2(
    'rejected', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_payment_amount, p_payment_currency, p_cash_account_id,
    p_charge_date, p_request_payload_fingerprint, null, p_rejected_at,
    p_rejected_reason, p_recovery_source
  ) x;
$function$;

alter function public.school_mark_cash_expense_request_submitted_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text
) owner to postgres;
alter function public.school_mark_cash_expense_confirmed_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text
) owner to postgres;
alter function public.school_mark_cash_expense_rejected_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,text,timestamptz,text
) owner to postgres;

revoke all on function public.school_mark_cash_expense_request_submitted_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text
) from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_confirmed_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text
) from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_rejected_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,text,timestamptz,text
) from public, anon, authenticated, service_role;

grant execute on function public.school_mark_cash_expense_request_submitted_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text
) to service_role;
grant execute on function public.school_mark_cash_expense_confirmed_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text
) to service_role;
grant execute on function public.school_mark_cash_expense_rejected_v2(
  uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,text,timestamptz,text
) to service_role;

comment on function public.school_apply_expense_cash_attempt_transition_v2(
  text,uuid,uuid,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,text,uuid,timestamptz,text,text
) is 'Owner-only Phase 3C2-R transition core. Locks expense then attempt, validates complete Cash evidence, and atomically updates attempt plus latest-state mirror.';
comment on function public.school_request_cash_expense_payment_confirmation_v2(
  uuid,uuid,uuid,text,date,text,numeric,text,text,numeric,text,text,text,uuid,text,text,uuid,text
) is 'Service-only Phase 3C2-R immediate-account prepare writer. Returns the only canonical Cash request payload and creates/reuses one prepared attempt.';

-- Gate-aware legacy callback definitions. While the V2 gate is blocked they retain
-- the pre-cutover behavior; once enabled they fail closed and cannot bypass attempt.
create or replace function public.school_mark_cash_expense_request_submitted(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text default 'pending'
)
returns table (expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, message text)
language plpgsql security definer set search_path = pg_catalog, public
as $function$
declare v_expense public.school_expense_records%rowtype; v_now timestamptz := now(); v_status text := nullif(trim(coalesce(p_cash_request_status, '')), '');
begin
  if exists (select 1 from public.school_feature_gates where feature_key='cash_expense_attempt_writer_v2_enabled' and state='enabled') then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_LEGACY_RPC_DISABLED';
  end if;
  if p_expense_record_id is null or p_cash_request_id is null or v_status is distinct from 'pending' then raise exception 'invalid submitted Cash request evidence'; end if;
  select * into v_expense from public.school_expense_records e where e.id=p_expense_record_id and e.app_type='school' for update;
  if not found then raise exception 'school expense record not found: %',p_expense_record_id; end if;
  if v_expense.cash_request_status not in ('pending_cash_request','pending') then raise exception 'expense record is not waiting for Cash request submission. current status: %',v_expense.cash_request_status; end if;
  if v_expense.cash_request_id is not null and v_expense.cash_request_id is distinct from p_cash_request_id then raise exception 'expense record already references a different Cash request: %',v_expense.cash_request_id; end if;
  update public.school_expense_records e set cash_request_id=p_cash_request_id,cash_request_status='pending',cash_requested_at=coalesce(e.cash_requested_at,v_now),cash_error_message=null,updated_at=v_now where e.id=v_expense.id returning * into v_expense;
  return query select v_expense.id,v_expense.status,v_expense.cash_request_id,v_expense.cash_request_status,'Cash expense request submitted and awaiting confirmation'::text;
end;
$function$;

create or replace function public.school_mark_cash_expense_confirmed(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_transaction_id uuid, p_confirmed_at timestamptz default null
)
returns table (expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, cash_transaction_id uuid, message text)
language plpgsql security definer set search_path = pg_catalog, public
as $function$
declare v_expense public.school_expense_records%rowtype; v_now timestamptz := coalesce(p_confirmed_at,now());
begin
  if exists (select 1 from public.school_feature_gates where feature_key='cash_expense_attempt_writer_v2_enabled' and state='enabled') then raise exception using errcode='55000',message='SCHOOL_EXPENSE_CASH_LEGACY_RPC_DISABLED'; end if;
  if p_expense_record_id is null or p_cash_request_id is null or p_cash_transaction_id is null then raise exception 'expense_record_id, cash_request_id and cash_transaction_id are required.'; end if;
  select * into v_expense from public.school_expense_records e where e.id=p_expense_record_id and e.app_type='school' for update;
  if not found then raise exception 'school expense record not found: %',p_expense_record_id; end if;
  if v_expense.cash_request_id is not null and v_expense.cash_request_id is distinct from p_cash_request_id then raise exception 'expense record references a different Cash request: %',v_expense.cash_request_id; end if;
  if v_expense.cash_transaction_id is not null then
    if v_expense.cash_transaction_id=p_cash_transaction_id and v_expense.cash_request_status='approved' and v_expense.status='paid' then return query select v_expense.id,v_expense.status,v_expense.cash_request_id,v_expense.cash_request_status,v_expense.cash_transaction_id,'Cash expense confirmation already synced'::text; return; end if;
    raise exception 'expense record already has a different Cash transaction: %',v_expense.cash_transaction_id;
  end if;
  update public.school_expense_records e set status='paid',cash_request_id=p_cash_request_id,cash_request_status='approved',cash_transaction_id=p_cash_transaction_id,cash_synced_at=v_now,cash_error_message=null,updated_at=v_now where e.id=v_expense.id returning * into v_expense;
  return query select v_expense.id,v_expense.status,v_expense.cash_request_id,v_expense.cash_request_status,v_expense.cash_transaction_id,'Cash expense confirmation synced'::text;
end;
$function$;

create or replace function public.school_mark_cash_expense_rejected(
  p_expense_record_id uuid, p_cash_request_id uuid, p_rejected_reason text default null, p_rejected_at timestamptz default null
)
returns table (expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, message text)
language plpgsql security definer set search_path = pg_catalog, public
as $function$
declare v_expense public.school_expense_records%rowtype; v_now timestamptz := coalesce(p_rejected_at,now()); v_reason text := nullif(trim(coalesce(p_rejected_reason,'')),'');
begin
  if exists (select 1 from public.school_feature_gates where feature_key='cash_expense_attempt_writer_v2_enabled' and state='enabled') then raise exception using errcode='55000',message='SCHOOL_EXPENSE_CASH_LEGACY_RPC_DISABLED'; end if;
  if p_expense_record_id is null or p_cash_request_id is null then raise exception 'expense_record_id and cash_request_id are required.'; end if;
  select * into v_expense from public.school_expense_records e where e.id=p_expense_record_id and e.app_type='school' for update;
  if not found then raise exception 'school expense record not found: %',p_expense_record_id; end if;
  if v_expense.cash_request_id is not null and v_expense.cash_request_id is distinct from p_cash_request_id then raise exception 'expense record references a different Cash request: %',v_expense.cash_request_id; end if;
  if v_expense.cash_transaction_id is not null then raise exception 'expense record already has Cash transaction and cannot be rejected: %',v_expense.cash_transaction_id; end if;
  update public.school_expense_records e set cash_request_id=p_cash_request_id,cash_request_status='rejected',cash_synced_at=v_now,cash_error_message=coalesce(v_reason,'Cash request rejected'),updated_at=v_now where e.id=v_expense.id returning * into v_expense;
  return query select v_expense.id,v_expense.status,v_expense.cash_request_id,v_expense.cash_request_status,'Cash expense request rejection synced'::text;
end;
$function$;

alter function public.school_mark_cash_expense_request_submitted(uuid,uuid,text) owner to postgres;
alter function public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz) owner to postgres;
alter function public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz) owner to postgres;
revoke all on function public.school_mark_cash_expense_request_submitted(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.school_mark_cash_expense_request_submitted(uuid,uuid,text) to service_role;
grant execute on function public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz) to service_role;
grant execute on function public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz) to service_role;
