-- School V2 x Cash Phase 3D fixed approved callback and recovery.
-- Status: production deployed 2026-08-19; fixed Gate remains blocked.
-- This migration does not enable the fixed Gate and creates no business row.

lock table public.school_expense_records in share row exclusive mode;
lock table public.school_expense_cash_attempts in access exclusive mode;
lock table public.school_feature_gates in share row exclusive mode;

do $phase3d_precheck$
begin
  if exists (
    select 1 from public.school_expense_cash_attempts
    where payment_route = 'fixed_credit_card'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3D_FIXED_ATTEMPT_PREEXISTS';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_expense_attempt_writer_v2_enabled' and state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3D_IMMEDIATE_V2_GATE_NOT_ENABLED';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_fixed_credit_card_route_enabled' and state = 'blocked'
  ) then
    raise exception using errcode = '55000', message = 'PHASE3D_FIXED_GATE_NOT_BLOCKED';
  end if;
end;
$phase3d_precheck$;

alter table public.school_expense_cash_attempts
  drop constraint school_expense_cash_attempts_callback_recovery_check,
  add constraint school_expense_cash_attempts_callback_recovery_check check (
    (
      not callback_recovered_from_prepared
      and callback_recovered_at is null
      and callback_recovery_source is null
    )
    or
    (
      callback_recovered_from_prepared
      and callback_recovered_at is not null
      and callback_recovery_source = 'sync-cash-request-result-v2'
      and attempt_status in ('approved_immediate', 'approved_fixed', 'rejected')
    )
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
    if new.payment_route = 'fixed_credit_card' and not exists (
      select 1 from public.school_feature_gates g
      where g.feature_key = 'cash_fixed_credit_card_route_enabled' and g.state = 'enabled'
    ) then
      raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
    end if;
    return new;
  end if;
  if new is not distinct from old then return new; end if;

  if (to_jsonb(new)-v_allowed_columns) is distinct from (to_jsonb(old)-v_allowed_columns) then
    select string_agg(n.key,',' order by n.key) into v_unexpected_columns
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o on o.key=n.key
    where n.value is distinct from o.value and not (n.key=any(v_allowed_columns));
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_IMMUTABLE',
      detail=coalesce(v_unexpected_columns,'unknown generated or structural column');
  end if;

  if old.payment_route = 'immediate_account' then
    if old.attempt_status='prepared' and new.attempt_status='submitted' then
      if new.version<>old.version+1 or old.cash_request_id is not null or new.cash_request_id is null
         or old.submitted_at is not null or new.submitted_at is null
         or new.cash_transaction_id is not null or new.approved_at is not null
         or new.rejected_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='submitted' and new.attempt_status='approved_immediate' then
      if new.version<>old.version+1 or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or old.cash_transaction_id is not null or new.cash_transaction_id is null
         or old.approved_at is not null or new.approved_at is null
         or new.rejected_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='submitted' and new.attempt_status='rejected' then
      if new.version<>old.version+1 or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null or old.rejected_at is not null
         or new.rejected_at is null or new.approved_at is not null
         or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='prepared' and new.attempt_status in ('approved_immediate','rejected') then
      if new.version<>old.version+2 or new.cash_request_id is null or new.submitted_at is null
         or not new.callback_recovered_from_prepared or new.callback_recovered_at is null
         or new.callback_recovery_source<>'sync-cash-request-result-v2'
         or (new.attempt_status='approved_immediate' and (new.cash_transaction_id is null or new.approved_at is null or new.rejected_at is not null))
         or (new.attempt_status='rejected' and (new.cash_transaction_id is not null or new.rejected_at is null or new.approved_at is not null)) then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_ATTEMPT_RECOVERY_VERSION_CONFLICT';
      end if;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_TRANSITION_FORBIDDEN';
    end if;
  else
    if old.attempt_status='prepared' and new.attempt_status='submitted' then
      if new.version<>old.version+1 or old.cash_request_id is not null or new.cash_request_id is null
         or old.submitted_at is not null or new.submitted_at is null
         or new.cash_transaction_id is not null or new.cash_fixed_projection_id is not null
         or new.cash_fixed_item_id is not null or new.approved_at is not null
         or new.rejected_at is not null or new.funded_at is not null
         or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='submitted' and new.attempt_status='approved_fixed' then
      if new.version<>old.version+1 or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null
         or old.cash_fixed_projection_id is not null or new.cash_fixed_projection_id is null
         or old.cash_fixed_item_id is not null or new.cash_fixed_item_id is null
         or old.approved_at is not null or new.approved_at is null
         or new.rejected_at is not null or new.funded_at is not null
         or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='submitted' and new.attempt_status='rejected' then
      if new.version<>old.version+1 or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null or new.cash_fixed_projection_id is not null
         or new.cash_fixed_item_id is not null or new.approved_at is not null
         or old.rejected_at is not null or new.rejected_at is null
         or new.funded_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status='prepared' and new.attempt_status in ('approved_fixed','rejected') then
      if new.version<>old.version+2 or new.cash_request_id is null or new.submitted_at is null
         or not new.callback_recovered_from_prepared or new.callback_recovered_at is null
         or new.callback_recovery_source<>'sync-cash-request-result-v2'
         or new.cash_transaction_id is not null
         or (new.attempt_status='approved_fixed' and (new.cash_fixed_projection_id is null or new.cash_fixed_item_id is null or new.approved_at is null or new.rejected_at is not null))
         or (new.attempt_status='rejected' and (new.cash_fixed_projection_id is not null or new.cash_fixed_item_id is not null or new.approved_at is not null or new.rejected_at is null)) then
        raise exception using errcode='40001', message='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_RECOVERY_VERSION_CONFLICT';
      end if;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_ATTEMPT_TRANSITION_FORBIDDEN';
    end if;
  end if;
  new.updated_at := statement_timestamp();
  return new;
end;
$function$;

create or replace function public.school_apply_expense_cash_fixed_callback_v3(
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
  p_original_amount numeric,
  p_original_currency text,
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
  p_projection_status text default null,
  p_projection_version integer default null,
  p_projection_funding_status text default null,
  p_projection_funding_channel_id uuid default null,
  p_projection_funding_transaction_id uuid default null,
  p_fixed_item_id uuid default null,
  p_fixed_item_template_id uuid default null,
  p_fixed_item_scope text default null,
  p_fixed_item_currency text default null,
  p_fixed_item_direction text default null,
  p_fixed_item_amount numeric default null,
  p_fixed_item_month_key text default null,
  p_fixed_item_due_date date default null,
  p_fixed_item_payment_group text default null,
  p_fixed_item_status text default null,
  p_fixed_item_account_id uuid default null,
  p_fixed_item_linked_jpy_transaction_id uuid default null,
  p_fixed_item_linked_cny_transaction_id uuid default null,
  p_approved_actor uuid default null,
  p_result_at timestamptz default null,
  p_rejected_reason text default null
)
returns table (
  expense_id uuid,
  expense_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  fixed_projection_id uuid,
  fixed_item_id uuid,
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
  v_action text := lower(nullif(trim(coalesce(p_action,'')),''));
  v_status text := lower(nullif(trim(coalesce(p_cash_request_status,'')),''));
  v_original_currency text := upper(nullif(trim(coalesce(p_original_currency,'')),''));
  v_currency text := upper(nullif(trim(coalesce(p_settlement_currency,'')),''));
  v_reason text := nullif(trim(coalesce(p_rejected_reason,'')),'');
  v_now timestamptz := coalesce(p_result_at,statement_timestamp());
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_expected_fingerprint text;
  v_idempotent boolean := false;
  v_recovered boolean := false;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key='cash_expense_attempt_writer_v2_enabled' and g.state='enabled'
  ) then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;
  -- The fixed Gate intentionally is not read here. It gates only new prepare.
  if v_action not in ('submitted','approved','rejected') then
    raise exception using errcode='22023', message='SCHOOL_EXPENSE_CASH_FIXED_ACTION_INVALID';
  end if;
  if p_expense_record_id is null or p_cash_request_id is null or p_request_event_id is null
     or p_external_reference_id is null or p_card_instrument_id is null
     or p_charge_date is null or p_suggested_fixed_month is null
     or p_target_fixed_month is null or p_funding_date is null
     or coalesce(p_settlement_amount,0)<=0 or nullif(trim(coalesce(p_idempotency_key,'')),'') is null
     or nullif(trim(coalesce(p_request_payload_fingerprint,'')),'') is null then
    raise exception using errcode='22023', message='SCHOOL_EXPENSE_CASH_FIXED_EVIDENCE_REQUIRED';
  end if;
  if p_payment_route is distinct from 'fixed_credit_card'
     or p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or p_external_reference_id is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense'
     or p_account_id is not null or p_funding_account_id is not null
     or v_original_currency not in ('JPY','CNY') or v_currency not in ('JPY','CNY') then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_EXTERNAL_IDENTITY_CONFLICT';
  end if;
  if (v_action='submitted' and v_status<>'pending')
     or (v_action='approved' and v_status<>'approved')
     or (v_action='rejected' and v_status<>'rejected') then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_STATUS_CONFLICT';
  end if;

  select * into v_expense from public.school_expense_records e
  where e.id=p_expense_record_id and e.app_type='school' for update;
  if not found then raise exception using errcode='P0002', message='SCHOOL_EXPENSE_RECORD_NOT_FOUND'; end if;
  select * into v_attempt from public.school_expense_cash_attempts a
  where a.expense_id=p_expense_record_id and a.request_event_id=p_request_event_id for update;
  if not found then raise exception using errcode='P0002', message='SCHOOL_EXPENSE_CASH_ATTEMPT_NOT_FOUND'; end if;

  v_expected_fingerprint := public.school_expense_cash_attempt_payload_fingerprint_v3(
    v_attempt.expense_id,v_attempt.attempt_no,v_attempt.request_type,
    v_attempt.payment_route,v_attempt.request_event_id,v_attempt.idempotency_key,
    v_attempt.original_amount,v_attempt.original_currency,v_attempt.payment_amount,
    v_attempt.payment_currency,v_attempt.cash_funding_account_id,
    v_attempt.cash_card_instrument_id,v_attempt.charge_date,
    v_attempt.suggested_fixed_month,v_attempt.target_fixed_month,v_attempt.funding_date
  );
  if v_attempt.payment_route<>'fixed_credit_card'
     or v_attempt.idempotency_key is distinct from p_idempotency_key
     or v_attempt.original_amount is distinct from p_original_amount
     or v_attempt.original_currency is distinct from v_original_currency
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
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT';
  end if;
  if v_attempt.cash_request_id is not null and v_attempt.cash_request_id is distinct from p_cash_request_id then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_REQUEST_ID_CONFLICT';
  end if;
  if v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no
     or v_expense.cash_payment_amount is distinct from v_attempt.payment_amount
     or v_expense.cash_payment_currency is distinct from v_attempt.payment_currency then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_LATEST_STATE_CONFLICT';
  end if;

  if v_action='submitted' then
    if p_cash_transaction_id is not null or p_fixed_projection_id is not null or p_fixed_item_id is not null then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_DOWNSTREAM_FACT_FORBIDDEN';
    end if;
    if v_attempt.attempt_status='submitted' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_status is distinct from 'pending' then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status<>'prepared' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_TRANSITION_FORBIDDEN';
    else
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_PREPARED_LATEST_STATE_CONFLICT';
      end if;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,attempt_status='submitted',
        latest_error_code=null,latest_error_message=null,version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
      update public.school_expense_records e set
        cash_request_id=p_cash_request_id,cash_request_status='pending',
        cash_requested_at=coalesce(e.cash_requested_at,v_now),cash_error_message=null,updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  elsif v_action='approved' then
    if p_cash_transaction_id is not null or p_fixed_projection_id is null or p_fixed_item_id is null
       or p_projection_status is distinct from 'projected' or p_projection_version<>1
       or p_projection_funding_status is distinct from 'unfunded'
       or p_projection_funding_channel_id is null
       or p_projection_funding_transaction_id is not null
       or p_fixed_item_template_id is not null or p_fixed_item_scope is distinct from 'school'
       or p_fixed_item_currency is distinct from 'JPY' or p_fixed_item_direction is distinct from 'expense'
       or p_fixed_item_amount is distinct from p_settlement_amount
       or p_fixed_item_month_key is distinct from to_char(p_target_fixed_month,'YYYY-MM')
       or p_fixed_item_due_date is distinct from p_funding_date
       or nullif(trim(coalesce(p_fixed_item_payment_group,'')),'') is null
       or p_fixed_item_status is distinct from 'unpaid'
       or p_fixed_item_account_id is not null
       or p_fixed_item_linked_jpy_transaction_id is not null
       or p_fixed_item_linked_cny_transaction_id is not null
       or p_approved_actor is null or p_result_at is null
       or p_suggested_fixed_month is distinct from p_target_fixed_month
       or v_original_currency is distinct from v_currency
       or p_original_amount is distinct from p_settlement_amount
       or v_expense.expense_date is distinct from p_charge_date then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVAL_EVIDENCE_CONFLICT';
    end if;
    if exists (
      select 1 from public.school_expense_cash_attempts a
      where a.id<>v_attempt.id and (
        a.cash_request_id=p_cash_request_id
        or a.cash_fixed_projection_id=p_fixed_projection_id
        or a.cash_fixed_item_id=p_fixed_item_id
      )
    ) then
      raise exception using errcode='23505', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVAL_IDENTITY_ALREADY_USED';
    end if;
    if v_attempt.attempt_status='approved_fixed' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.cash_fixed_projection_id is distinct from p_fixed_projection_id
         or v_attempt.cash_fixed_item_id is distinct from p_fixed_item_id
         or v_attempt.approved_at is distinct from p_result_at
         or v_expense.status is distinct from 'paid'
         or v_expense.cash_request_status is distinct from 'approved'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status='rejected' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_CANNOT_APPROVE';
    elsif v_attempt.attempt_status='prepared' then
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,
        cash_fixed_projection_id=p_fixed_projection_id,cash_fixed_item_id=p_fixed_item_id,
        approved_at=v_now,attempt_status='approved_fixed',
        callback_recovered_from_prepared=true,callback_recovered_at=v_now,
        callback_recovery_source='sync-cash-request-result-v2',
        latest_error_code=null,latest_error_message=null,version=a.version+2
      where a.id=v_attempt.id returning * into v_attempt;
    elsif v_attempt.attempt_status='submitted' then
      update public.school_expense_cash_attempts a set
        cash_fixed_projection_id=p_fixed_projection_id,cash_fixed_item_id=p_fixed_item_id,
        approved_at=v_now,attempt_status='approved_fixed',
        latest_error_code=null,latest_error_message=null,version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_TRANSITION_FORBIDDEN';
    end if;
    if not v_idempotent then
      update public.school_expense_records e set
        status='paid',cash_request_id=p_cash_request_id,cash_request_status='approved',
        cash_transaction_id=null,cash_synced_at=v_now,cash_error_message=null,updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  else
    if p_cash_transaction_id is not null or p_fixed_projection_id is not null or p_fixed_item_id is not null then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_DOWNSTREAM_FACT_FORBIDDEN';
    end if;
    if v_attempt.attempt_status='rejected' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.rejected_at is distinct from p_result_at
         or v_expense.cash_request_status is distinct from 'rejected'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status='approved_fixed' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_CANNOT_REJECT';
    elsif v_attempt.attempt_status='prepared' then
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,rejected_at=v_now,
        attempt_status='rejected',callback_recovered_from_prepared=true,
        callback_recovered_at=v_now,callback_recovery_source='sync-cash-request-result-v2',
        latest_error_code='CASH_REQUEST_REJECTED',
        latest_error_message=coalesce(v_reason,'Cash request rejected'),version=a.version+2
      where a.id=v_attempt.id returning * into v_attempt;
    elsif v_attempt.attempt_status='submitted' then
      update public.school_expense_cash_attempts a set
        rejected_at=v_now,attempt_status='rejected',latest_error_code='CASH_REQUEST_REJECTED',
        latest_error_message=coalesce(v_reason,'Cash request rejected'),version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_TRANSITION_FORBIDDEN';
    end if;
    if not v_idempotent then
      update public.school_expense_records e set
        cash_request_id=p_cash_request_id,cash_request_status='rejected',
        cash_synced_at=v_now,cash_error_message=coalesce(v_reason,'Cash request rejected'),updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  end if;

  return query select v_expense.id,v_expense.status,v_expense.cash_request_id,
    v_expense.cash_request_status,v_expense.cash_transaction_id,
    v_attempt.cash_fixed_projection_id,v_attempt.cash_fixed_item_id,v_attempt.id,
    v_attempt.attempt_status,v_attempt.version,v_attempt.callback_recovered_from_prepared,
    v_idempotent,case
      when v_idempotent then format('fixed Cash expense attempt %s callback already applied',v_action)
      when v_recovered then format('fixed Cash expense attempt recovered from prepared and marked %s',v_action)
      else format('fixed Cash expense attempt marked %s',v_action) end;
end;
$function$;

-- Preserve the Phase 3C3-B owner-only core signature for existing wrappers,
-- but route it through the Gate-independent Phase 3D callback core.
create or replace function public.school_apply_expense_cash_fixed_attempt_transition_v2(
  p_action text,p_expense_record_id uuid,p_cash_request_id uuid,p_cash_request_status text,
  p_payment_route text,p_external_source text,p_request_event_id uuid,p_idempotency_key text,
  p_external_reference_type text,p_external_reference_id uuid,p_request_type text,
  p_transaction_type text,p_settlement_amount numeric,p_settlement_currency text,
  p_card_instrument_id uuid,p_charge_date date,p_suggested_fixed_month date,
  p_target_fixed_month date,p_funding_date date,p_account_id uuid,p_funding_account_id uuid,
  p_request_payload_fingerprint text,p_cash_transaction_id uuid default null,
  p_fixed_projection_id uuid default null,p_result_at timestamptz default null,
  p_rejected_reason text default null
)
returns table (
  expense_id uuid,expense_status text,cash_request_id uuid,cash_request_status text,
  attempt_id uuid,attempt_status text,attempt_version integer,idempotent boolean,message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select x.expense_id,x.expense_status,x.cash_request_id,x.cash_request_status,
    x.attempt_id,x.attempt_status,x.attempt_version,x.idempotent,x.message
  from public.school_apply_expense_cash_fixed_callback_v3(
    p_action,p_expense_record_id,p_cash_request_id,p_cash_request_status,
    p_payment_route,p_external_source,p_request_event_id,p_idempotency_key,
    p_external_reference_type,p_external_reference_id,p_request_type,p_transaction_type,
    p_settlement_amount,p_settlement_currency,p_settlement_amount,p_settlement_currency,
    p_card_instrument_id,p_charge_date,p_suggested_fixed_month,p_target_fixed_month,
    p_funding_date,p_account_id,p_funding_account_id,p_request_payload_fingerprint,
    p_cash_transaction_id,p_fixed_projection_id,
    null::text,null::integer,null::text,null::uuid,null::uuid,
    null::uuid,null::uuid,null::text,null::text,null::text,null::numeric,
    null::text,null::date,null::text,null::text,null::uuid,null::uuid,null::uuid,
    null::uuid,p_result_at,p_rejected_reason
  ) x;
$function$;

create or replace function public.school_mark_cash_fixed_expense_approved_v2(
  p_expense_record_id uuid,p_cash_request_id uuid,p_cash_request_status text,
  p_payment_route text,p_external_source text,p_request_event_id uuid,p_idempotency_key text,
  p_external_reference_type text,p_external_reference_id uuid,p_request_type text,
  p_transaction_type text,p_original_amount numeric,p_original_currency text,
  p_settlement_amount numeric,p_settlement_currency text,p_card_instrument_id uuid,
  p_charge_date date,p_suggested_fixed_month date,p_target_fixed_month date,p_funding_date date,
  p_account_id uuid,p_funding_account_id uuid,p_request_payload_fingerprint text,
  p_cash_transaction_id uuid,p_fixed_projection_id uuid,p_projection_status text,
  p_projection_version integer,p_projection_funding_status text,
  p_projection_funding_channel_id uuid,p_projection_funding_transaction_id uuid,
  p_fixed_item_id uuid,p_fixed_item_template_id uuid,p_fixed_item_scope text,
  p_fixed_item_currency text,p_fixed_item_direction text,p_fixed_item_amount numeric,
  p_fixed_item_month_key text,p_fixed_item_due_date date,p_fixed_item_payment_group text,
  p_fixed_item_status text,p_fixed_item_account_id uuid,
  p_fixed_item_linked_jpy_transaction_id uuid,p_fixed_item_linked_cny_transaction_id uuid,
  p_approved_actor uuid,p_approved_at timestamptz
)
returns table (
  expense_id uuid,expense_status text,cash_request_id uuid,cash_request_status text,
  cash_transaction_id uuid,fixed_projection_id uuid,fixed_item_id uuid,
  attempt_id uuid,attempt_status text,attempt_version integer,
  callback_recovered_from_prepared boolean,idempotent boolean,message text
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select * from public.school_apply_expense_cash_fixed_callback_v3(
    'approved',p_expense_record_id,p_cash_request_id,p_cash_request_status,
    p_payment_route,p_external_source,p_request_event_id,p_idempotency_key,
    p_external_reference_type,p_external_reference_id,p_request_type,p_transaction_type,
    p_original_amount,p_original_currency,p_settlement_amount,p_settlement_currency,
    p_card_instrument_id,p_charge_date,p_suggested_fixed_month,p_target_fixed_month,
    p_funding_date,p_account_id,p_funding_account_id,p_request_payload_fingerprint,
    p_cash_transaction_id,p_fixed_projection_id,p_projection_status,p_projection_version,
    p_projection_funding_status,p_projection_funding_channel_id,
    p_projection_funding_transaction_id,p_fixed_item_id,p_fixed_item_template_id,
    p_fixed_item_scope,p_fixed_item_currency,p_fixed_item_direction,p_fixed_item_amount,
    p_fixed_item_month_key,p_fixed_item_due_date,p_fixed_item_payment_group,
    p_fixed_item_status,p_fixed_item_account_id,p_fixed_item_linked_jpy_transaction_id,
    p_fixed_item_linked_cny_transaction_id,p_approved_actor,p_approved_at,null
  );
$function$;

alter function public.school_guard_expense_cash_attempt_v1() owner to postgres;
alter function public.school_apply_expense_cash_fixed_callback_v3(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz,text) owner to postgres;
alter function public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text) owner to postgres;
alter function public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz) owner to postgres;

revoke all on function public.school_guard_expense_cash_attempt_v1() from public,anon,authenticated,service_role;
revoke all on function public.school_apply_expense_cash_fixed_callback_v3(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz,text) from public,anon,authenticated,service_role;
revoke all on function public.school_apply_expense_cash_fixed_attempt_transition_v2(text,uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,timestamptz,text) from public,anon,authenticated,service_role;
revoke all on function public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz) to service_role;

comment on function public.school_mark_cash_fixed_expense_approved_v2(uuid,uuid,text,text,text,uuid,text,text,uuid,text,text,numeric,text,numeric,text,uuid,date,date,date,date,uuid,uuid,text,uuid,uuid,text,integer,text,uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,text,text,uuid,uuid,uuid,uuid,timestamptz) is
  'Phase 3D service-only fixed approved callback. Validates complete home request/projection/item evidence, writes approved_fixed plus paid expense latest-state atomically, and creates no ordinary transaction or funding fact.';
