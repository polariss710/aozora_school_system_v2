-- Cash tuition Cash submit technical hardening, 2026-08-02.
-- Status: deployed and rollback-tested on 2026-08-02.
-- Scope: harden canonical external request creation, approve/reject ownership,
-- approve idempotency, and least-privilege EXECUTE grants.

create or replace function public.home_create_external_transaction_request(
  p_user_id uuid,
  p_account_id uuid,
  p_external_source text,
  p_external_event_id uuid,
  p_external_reference_type text,
  p_external_reference_id uuid,
  p_request_type text,
  p_transaction_type text,
  p_transacted_at date,
  p_amount numeric,
  p_idempotency_key text,
  p_description text default null,
  p_note text default null,
  p_payload_snapshot jsonb default '{}'::jsonb,
  p_currency text default 'JPY'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_account public.home_accounts%rowtype;
  v_existing public.home_external_transaction_requests%rowtype;
  v_request_id uuid;
  v_external_source text := lower(trim(coalesce(p_external_source, '')));
  v_external_reference_type text := lower(trim(coalesce(p_external_reference_type, '')));
  v_request_type text := lower(trim(coalesce(p_request_type, '')));
  v_transaction_type text := lower(trim(coalesce(p_transaction_type, '')));
  v_currency text := upper(trim(coalesce(p_currency, 'JPY')));
  v_idempotency_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
  v_description text := coalesce(nullif(trim(coalesce(p_description, '')), ''), '外部待确认请求');
  v_note text := coalesce(p_note, '');
  v_payload_snapshot jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    return jsonb_build_object('ok', false, 'message', 'service_role is required');
  end if;

  if p_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'user_id is required');
  end if;

  if p_account_id is null then
    return jsonb_build_object('ok', false, 'message', 'account_id is required');
  end if;

  if p_external_event_id is null then
    return jsonb_build_object('ok', false, 'message', 'external_event_id is required');
  end if;

  if p_external_reference_id is null then
    return jsonb_build_object('ok', false, 'message', 'external_reference_id is required');
  end if;

  if p_transacted_at is null then
    return jsonb_build_object('ok', false, 'message', 'transacted_at is required');
  end if;

  if coalesce(p_amount, 0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'amount must be greater than 0');
  end if;

  if v_idempotency_key is null then
    return jsonb_build_object('ok', false, 'message', 'idempotency_key is required');
  end if;

  if v_currency not in ('JPY', 'CNY') then
    return jsonb_build_object('ok', false, 'message', 'currency must be JPY or CNY');
  end if;

  if v_external_source <> 'aozora_school' then
    return jsonb_build_object('ok', false, 'message', 'external_source must be aozora_school');
  end if;

  if v_external_reference_type in ('school_payment_requests', 'school_part_time_work_income_requests')
     or v_request_type in (
       'teacher_wage_payment_confirm',
       'teacher_wage_payment_reverse',
       'part_time_work_income_received'
     ) then
    return jsonb_build_object(
      'ok', false,
      'message', 'legacy business module direct Cash requests are deprecated; use school_income_records or school_expense_records'
    );
  end if;

  if v_external_reference_type not in ('school_income_records', 'school_expense_records') then
    return jsonb_build_object('ok', false, 'message', 'unsupported external_reference_type');
  end if;

  if v_request_type in ('tuition_income_received', 'income_received') then
    if v_external_reference_type <> 'school_income_records' or v_transaction_type <> 'income' then
      return jsonb_build_object('ok', false, 'message', 'income received requests must reference school_income_records and create income');
    end if;
  elsif v_request_type = 'expense_paid' then
    if v_external_reference_type <> 'school_expense_records' or v_transaction_type <> 'expense' then
      return jsonb_build_object('ok', false, 'message', 'expense_paid must reference school_expense_records and create expense');
    end if;
  else
    return jsonb_build_object('ok', false, 'message', 'unsupported request_type');
  end if;

  select *
    into v_account
    from public.home_accounts
   where id = p_account_id
     and user_id = p_user_id
     and currency = v_currency
     and is_active is true
     and allow_school_requests is true;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'school-eligible account not found, inactive, or currency mismatch');
  end if;

  v_payload_snapshot := case
    when p_payload_snapshot is null or p_payload_snapshot = '{}'::jsonb then
      jsonb_build_object(
        'external_source', v_external_source,
        'external_event_id', p_external_event_id,
        'external_reference_type', v_external_reference_type,
        'external_reference_id', p_external_reference_id,
        'request_type', v_request_type,
        'transaction_type', v_transaction_type,
        'currency', v_currency,
        'amount', p_amount,
        'account_id', p_account_id,
        'transacted_at', p_transacted_at,
        'description', v_description,
        'note', v_note
      )
    else p_payload_snapshot
  end;

  select *
    into v_existing
    from public.home_external_transaction_requests request_row
   where request_row.idempotency_key = v_idempotency_key
   limit 1;

  if found then
    if v_existing.user_id is distinct from p_user_id
       or v_existing.account_id is distinct from p_account_id
       or v_existing.external_source is distinct from v_external_source
       or v_existing.external_event_id is distinct from p_external_event_id
       or v_existing.external_reference_type is distinct from v_external_reference_type
       or v_existing.external_reference_id is distinct from p_external_reference_id
       or v_existing.request_type is distinct from v_request_type
       or v_existing.transaction_type is distinct from v_transaction_type
       or v_existing.currency is distinct from v_currency
       or v_existing.amount is distinct from p_amount
       or v_existing.transacted_at is distinct from p_transacted_at then
      return jsonb_build_object(
        'ok', false,
        'message', 'external request idempotency key already exists with different payload',
        'request_id', v_existing.id
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'inserted', false,
      'request_id', v_existing.id,
      'status', v_existing.status,
      'created_transaction_id', v_existing.created_transaction_id,
      'message', 'external transaction request already exists'
    );
  end if;

  select *
    into v_existing
    from public.home_external_transaction_requests request_row
   where request_row.external_source = v_external_source
     and request_row.external_reference_type = v_external_reference_type
     and request_row.external_reference_id = p_external_reference_id
     and request_row.request_type = v_request_type
     and request_row.status in ('pending', 'approved')
   limit 1;

  if found then
    return jsonb_build_object(
      'ok', false,
      'message', 'active or approved external transaction request already exists for this reference',
      'request_id', v_existing.id,
      'status', v_existing.status,
      'created_transaction_id', v_existing.created_transaction_id
    );
  end if;

  insert into public.home_external_transaction_requests (
    user_id, external_source, external_event_id, external_reference_type,
    external_reference_id, request_type, transaction_type, currency, amount,
    account_id, transacted_at, status, idempotency_key, payload_snapshot,
    description, note
  ) values (
    p_user_id, v_external_source, p_external_event_id, v_external_reference_type,
    p_external_reference_id, v_request_type, v_transaction_type, v_currency,
    p_amount, p_account_id, p_transacted_at, 'pending', v_idempotency_key,
    v_payload_snapshot, v_description, v_note
  )
  returning id into v_request_id;

  return jsonb_build_object(
    'ok', true,
    'inserted', true,
    'request_id', v_request_id,
    'status', 'pending',
    'message', 'external transaction request created'
  );
exception
  when unique_violation then
    select *
      into v_existing
      from public.home_external_transaction_requests request_row
     where request_row.idempotency_key = v_idempotency_key
        or (
          request_row.external_source = v_external_source
          and request_row.external_event_id = p_external_event_id
          and request_row.request_type = v_request_type
        )
        or (
          request_row.external_source = v_external_source
          and request_row.external_reference_type = v_external_reference_type
          and request_row.external_reference_id = p_external_reference_id
          and request_row.request_type = v_request_type
          and request_row.status in ('pending', 'approved')
        )
     order by (request_row.idempotency_key = v_idempotency_key) desc
     limit 1;

    if found then
      if v_existing.user_id is distinct from p_user_id
         or v_existing.account_id is distinct from p_account_id
         or v_existing.external_source is distinct from v_external_source
         or v_existing.external_event_id is distinct from p_external_event_id
         or v_existing.external_reference_type is distinct from v_external_reference_type
         or v_existing.external_reference_id is distinct from p_external_reference_id
         or v_existing.request_type is distinct from v_request_type
         or v_existing.transaction_type is distinct from v_transaction_type
         or v_existing.currency is distinct from v_currency
         or v_existing.amount is distinct from p_amount
         or v_existing.transacted_at is distinct from p_transacted_at then
        return jsonb_build_object(
          'ok', false,
          'message', 'external transaction request already exists with different payload',
          'request_id', v_existing.id
        );
      end if;

      return jsonb_build_object(
        'ok', true,
        'inserted', false,
        'request_id', v_existing.id,
        'status', v_existing.status,
        'created_transaction_id', v_existing.created_transaction_id,
        'message', 'external transaction request already exists'
      );
    end if;

    raise;
end;
$function$;

create or replace function public.home_approve_external_transaction_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_request public.home_external_transaction_requests%rowtype;
  v_transaction_result jsonb;
  v_transaction_id uuid;
  v_transaction_exists boolean;
begin
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'message', 'request_id is required');
  end if;

  select *
    into v_request
    from public.home_external_transaction_requests request_row
   where request_row.id = p_request_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'external transaction request not found');
  end if;

  if coalesce(auth.role(), '') <> 'service_role' then
    if auth.uid() is null then
      return jsonb_build_object('ok', false, 'message', 'authenticated request owner is required');
    end if;
    if auth.uid() is distinct from v_request.user_id then
      return jsonb_build_object('ok', false, 'message', 'authenticated user does not match request owner');
    end if;
  end if;

  if v_request.status = 'approved' then
    if v_request.created_transaction_id is null then
      return jsonb_build_object('ok', false, 'message', 'approved request is missing its transaction id');
    end if;

    if v_request.currency = 'JPY' then
      select exists (
        select 1
          from public.home_jpy_transactions transaction_row
         where transaction_row.id = v_request.created_transaction_id
           and transaction_row.user_id = v_request.user_id
           and transaction_row.account_id = v_request.account_id
           and transaction_row.amount = v_request.amount
           and transaction_row.external_source_id = v_request.external_event_id
           and transaction_row.external_idempotency_key = v_request.idempotency_key
      ) into v_transaction_exists;
    elsif v_request.currency = 'CNY' then
      select exists (
        select 1
          from public.home_cny_transactions transaction_row
         where transaction_row.id = v_request.created_transaction_id
           and transaction_row.user_id = v_request.user_id
           and transaction_row.account_id = v_request.account_id
           and transaction_row.amount = v_request.amount
           and transaction_row.external_source_id = v_request.external_event_id
           and transaction_row.external_idempotency_key = v_request.idempotency_key
      ) into v_transaction_exists;
    else
      v_transaction_exists := false;
    end if;

    if not coalesce(v_transaction_exists, false) then
      return jsonb_build_object('ok', false, 'message', 'approved request transaction does not match the canonical request');
    end if;

    return jsonb_build_object(
      'ok', true,
      'request_id', v_request.id,
      'status', 'approved',
      'currency', v_request.currency,
      'transaction_id', v_request.created_transaction_id,
      'transaction_inserted', false,
      'message', 'external transaction request already approved'
    );
  end if;

  if v_request.status <> 'pending' then
    return jsonb_build_object('ok', false, 'message', 'only pending requests can be approved', 'status', v_request.status);
  end if;

  if v_request.currency = 'JPY' then
    select public.home_create_external_jpy_transaction(
      v_request.user_id, v_request.account_id, v_request.transaction_type,
      v_request.transacted_at, v_request.amount, v_request.description,
      v_request.note, v_request.external_source, v_request.external_event_id,
      v_request.request_type, v_request.idempotency_key,
      v_request.external_reference_type, v_request.external_reference_id,
      v_request.note, md5(v_request.payload_snapshot::text)
    ) into v_transaction_result;
  elsif v_request.currency = 'CNY' then
    select public.home_create_external_cny_transaction(
      v_request.user_id, v_request.account_id, v_request.transaction_type,
      v_request.transacted_at, v_request.amount, v_request.description,
      v_request.note, v_request.external_source, v_request.external_event_id,
      v_request.request_type, v_request.idempotency_key,
      v_request.external_reference_type, v_request.external_reference_id,
      v_request.note, md5(v_request.payload_snapshot::text)
    ) into v_transaction_result;
  else
    return jsonb_build_object('ok', false, 'message', 'unsupported request currency', 'currency', v_request.currency);
  end if;

  if coalesce((v_transaction_result ->> 'ok')::boolean, false) is not true then
    return v_transaction_result;
  end if;

  v_transaction_id := (v_transaction_result ->> 'transaction_id')::uuid;

  update public.home_external_transaction_requests
     set status = 'approved',
         approved_at = now(),
         created_transaction_id = v_transaction_id,
         updated_at = now()
   where id = v_request.id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_request.id,
    'status', 'approved',
    'currency', v_request.currency,
    'transaction_id', v_transaction_id,
    'transaction_inserted', coalesce((v_transaction_result ->> 'inserted')::boolean, false),
    'message', 'external transaction request approved'
  );
end;
$function$;

create or replace function public.home_reject_external_transaction_request(
  p_request_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_request public.home_external_transaction_requests%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'message', 'request_id is required');
  end if;

  select *
    into v_request
    from public.home_external_transaction_requests request_row
   where request_row.id = p_request_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'external transaction request not found');
  end if;

  if coalesce(auth.role(), '') <> 'service_role' then
    if auth.uid() is null then
      return jsonb_build_object('ok', false, 'message', 'authenticated request owner is required');
    end if;
    if auth.uid() is distinct from v_request.user_id then
      return jsonb_build_object('ok', false, 'message', 'authenticated user does not match request owner');
    end if;
  end if;

  if v_request.status <> 'pending' then
    return jsonb_build_object('ok', false, 'message', 'only pending requests can be rejected', 'status', v_request.status);
  end if;

  update public.home_external_transaction_requests
     set status = 'rejected',
         rejected_at = now(),
         rejected_reason = v_reason,
         updated_at = now()
   where id = v_request.id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_request.id,
    'status', 'rejected',
    'message', 'external transaction request rejected'
  );
end;
$function$;

revoke all on function public.home_create_external_transaction_request(
  uuid, uuid, text, uuid, text, uuid, text, text, date, numeric, text, text, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.home_create_external_transaction_request(
  uuid, uuid, text, uuid, text, uuid, text, text, date, numeric, text, text, text, jsonb, text
) to service_role;

revoke all on function public.home_approve_external_transaction_request(uuid)
  from public, anon;
revoke all on function public.home_reject_external_transaction_request(uuid, text)
  from public, anon;
grant execute on function public.home_approve_external_transaction_request(uuid)
  to authenticated, service_role;
grant execute on function public.home_reject_external_transaction_request(uuid, text)
  to authenticated, service_role;

revoke all on function public.home_create_external_jpy_transaction(
  uuid, uuid, text, date, numeric, text, text, text, uuid, text, text, text, uuid, text, text
) from public, anon, authenticated;
revoke all on function public.home_create_external_cny_transaction(
  uuid, uuid, text, date, numeric, text, text, text, uuid, text, text, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.home_create_external_jpy_transaction(
  uuid, uuid, text, date, numeric, text, text, text, uuid, text, text, text, uuid, text, text
) to service_role;
grant execute on function public.home_create_external_cny_transaction(
  uuid, uuid, text, date, numeric, text, text, text, uuid, text, text, text, uuid, text, text
) to service_role;

comment on function public.home_create_external_transaction_request(
  uuid, uuid, text, uuid, text, uuid, text, text, date, numeric, text, text, text, jsonb, text
) is 'Service-role-only canonical School bridge. Concurrent duplicate creates re-read and return the same external request.';
comment on function public.home_approve_external_transaction_request(uuid)
  is 'Authenticated owner/service-role approval. Repeated approval returns the original verified transaction without a second ledger write.';
comment on function public.home_reject_external_transaction_request(uuid, text)
  is 'Authenticated owner/service-role rejection. Anonymous/null identity fails closed.';
