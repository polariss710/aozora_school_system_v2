-- school_confirm_personal_cash_payment_request_rpc.sql
-- Status: executed on school DB 2026-06-13; rollback-tested and
-- whitelist commit-tested for Phase 1 personal Cash payment confirmation.
-- Purpose:
-- - Confirm one personal-business teacher wage JPY payment request using a
--   school-side Cash account mapping and create one pending school outbox event.
-- - Do not write Cash DB.
-- - Do not create school expense records, school account transactions, or
--   school account balance changes. Company / 青空塾 payment confirmation remains
--   on public.school_confirm_payment_request.

create or replace function public.school_confirm_personal_cash_payment_request(
  p_payment_request_id uuid,
  p_cash_account_mapping_id uuid,
  p_pay_date date,
  p_amount numeric default null,
  p_note text default null
)
returns table (
  payment_request_id uuid,
  linkage_event_id uuid,
  status text,
  paid_at timestamptz,
  cash_account_mapping_id uuid,
  cash_account_id uuid,
  sync_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.school_payment_requests%rowtype;
  v_entity public.school_business_entities%rowtype;
  v_mapping public.school_personal_cash_account_mappings%rowtype;
  v_amount numeric;
  v_paid_at timestamptz;
  v_now timestamptz := now();
  v_event_id uuid;
  v_sync_status text;
begin
  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  if p_cash_account_mapping_id is null then
    raise exception 'Cash account mapping id is required';
  end if;

  if p_pay_date is null then
    raise exception 'pay date is required';
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
    raise exception 'payment request status must be pending. current status: %', v_payment.status;
  end if;

  if coalesce(v_payment.source_type, '') <> 'teacher_wage' then
    raise exception 'only teacher_wage payment requests are supported. current source_type: %', v_payment.source_type;
  end if;

  if coalesce(v_payment.currency, '') <> 'JPY' then
    raise exception 'personal Cash payment confirmation supports only JPY. current currency: %', v_payment.currency;
  end if;

  if v_payment.paid_at is not null
     or v_payment.paid_expense_id is not null
     or v_payment.paid_account_transaction_id is not null
     or v_payment.account_id is not null then
    raise exception 'payment request already has payment side effects';
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

  if coalesce(v_entity.entity_type, '') <> 'personal' then
    raise exception 'personal Cash payment confirmation is allowed only for personal business entities. entity_type: %', v_entity.entity_type;
  end if;

  select *
    into v_mapping
    from public.school_personal_cash_account_mappings
   where school_personal_cash_account_mappings.id = p_cash_account_mapping_id
   for update;

  if not found then
    raise exception 'personal Cash account mapping not found: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.is_active is not true then
    raise exception 'personal Cash account mapping is inactive: %', p_cash_account_mapping_id;
  end if;

  if v_mapping.business_entity_id is distinct from v_payment.business_entity_id then
    raise exception 'Cash account mapping business entity does not match payment request';
  end if;

  if v_mapping.flow_type <> 'teacher_wage_payment'
     or v_mapping.school_currency <> 'JPY'
     or v_mapping.cash_currency <> 'JPY' then
    raise exception 'Cash account mapping is not valid for Phase 1 teacher_wage_payment JPY linkage';
  end if;

  if exists (
    select 1
      from public.school_personal_cash_linkage_events e
     where e.source_table = 'school_payment_requests'
       and e.source_id = p_payment_request_id
       and e.source_event_type = 'teacher_wage_payment_confirm'
  ) then
    raise exception 'Cash linkage event already exists for payment request: %', p_payment_request_id;
  end if;

  v_amount := coalesce(p_amount, v_payment.amount, 0);
  if v_amount <= 0 then
    raise exception 'payment amount must be greater than 0';
  end if;

  if v_amount is distinct from v_payment.amount then
    raise exception 'payment amount must equal request amount. request %, input %', v_payment.amount, v_amount;
  end if;

  v_paid_at := p_pay_date::timestamptz;

  update public.school_payment_requests
     set status = 'paid',
         paid_at = v_paid_at,
         note = case
           when p_note is null then v_payment.note
           else nullif(trim(coalesce(p_note, '')), '')
         end,
         updated_at = v_now,
         paid_expense_id = null,
         paid_account_transaction_id = null,
         account_id = null
   where school_payment_requests.id = p_payment_request_id;

  select e.id, e.sync_status
    into v_event_id, v_sync_status
    from public.school_create_personal_cash_linkage_event(
      p_payment_request_id,
      p_cash_account_mapping_id,
      p_note
    ) e;

  return query
  select
    p_payment_request_id,
    v_event_id,
    'paid'::text,
    v_paid_at,
    p_cash_account_mapping_id,
    v_mapping.cash_account_id,
    v_sync_status;
end;
$$;

comment on function public.school_confirm_personal_cash_payment_request(
  uuid,
  uuid,
  date,
  numeric,
  text
) is
  'Confirms one pending personal-business teacher wage JPY payment request by marking it paid and creating one pending school Cash linkage outbox event. Does not write Cash DB or school account ledgers.';

grant execute on function public.school_confirm_personal_cash_payment_request(
  uuid,
  uuid,
  date,
  numeric,
  text
) to authenticated;
