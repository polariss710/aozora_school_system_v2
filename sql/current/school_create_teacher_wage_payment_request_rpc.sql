-- school_create_teacher_wage_payment_request_rpc.sql
-- RPC: public.school_create_teacher_wage_payment_request
-- Purpose:
-- - Create one pending teacher wage payment request from one locked teacher wage snapshot.
-- - Write only public.school_payment_requests.
-- - Do not write expenses, accounts, account transactions, income, student settlements,
--   lesson records, wage locks, or wage details.

create or replace function public.school_create_teacher_wage_payment_request(
  p_wage_lock_id uuid,
  p_due_date date default null,
  p_note text default null
)
returns table (
  payment_request_id uuid,
  wage_lock_id uuid,
  request_month text,
  payee_id uuid,
  payee_name text,
  business_entity_id uuid,
  business_name text,
  currency text,
  amount numeric,
  amount_jpy numeric,
  amount_cny numeric,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_wage public.school_teacher_wage_locks%rowtype;
  v_existing_payment_id uuid;
  v_payment_id uuid;
  v_created_at timestamptz := now();
  v_note text;
begin
  if p_wage_lock_id is null then
    raise exception 'wage lock id is required';
  end if;

  select *
    into v_wage
    from public.school_teacher_wage_locks
   where id = p_wage_lock_id
   for update;

  if not found then
    raise exception 'wage lock not found: %', p_wage_lock_id;
  end if;

  if coalesce(v_wage.status, '') <> 'locked' then
    raise exception 'only locked teacher wage records can generate payment requests. current status: %', v_wage.status;
  end if;

  if v_wage.voided_at is not null then
    raise exception 'voided teacher wage records cannot generate payment requests: %', p_wage_lock_id;
  end if;

  if v_wage.teacher_id is null then
    raise exception 'teacher wage record has no teacher_id: %', p_wage_lock_id;
  end if;

  if nullif(trim(coalesce(v_wage.teacher_name, '')), '') is null then
    raise exception 'teacher wage record has no teacher_name: %', p_wage_lock_id;
  end if;

  if v_wage.business_entity_id is null then
    raise exception 'teacher wage record has no business_entity_id: %', p_wage_lock_id;
  end if;

  if nullif(trim(coalesce(v_wage.business_name, '')), '') is null then
    raise exception 'teacher wage record has no business_name: %', p_wage_lock_id;
  end if;

  if v_wage.settlement_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'invalid teacher wage settlement month: %', v_wage.settlement_month;
  end if;

  if coalesce(v_wage.total_jpy, 0) <= 0 then
    raise exception 'teacher wage total_jpy must be greater than 0 to generate a payment request. current total_jpy: %', v_wage.total_jpy;
  end if;

  select id
    into v_existing_payment_id
    from public.school_payment_requests
   where source_type = 'teacher_wage'
     and source_id = p_wage_lock_id
   order by public.school_payment_requests.created_at asc
   limit 1;

  if v_existing_payment_id is not null then
    raise exception 'teacher wage payment request already exists for wage lock %: %', p_wage_lock_id, v_existing_payment_id;
  end if;

  v_note := coalesce(
    nullif(trim(coalesce(p_note, '')), ''),
    trim(both from concat(v_wage.settlement_month, ' ', v_wage.teacher_name, ' 工资'))
  );

  insert into public.school_payment_requests (
    source_type,
    source_id,
    request_month,
    payee_type,
    payee_id,
    payee_name,
    business_entity_id,
    business_name,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    status,
    due_date,
    paid_at,
    note,
    created_at,
    updated_at,
    paid_expense_id,
    paid_account_transaction_id,
    account_id,
    reversed_at,
    reversal_transaction_id,
    reversal_reason,
    reissued_from_payment_request_id,
    replacement_payment_request_id,
    reissue_reason,
    reissued_at
  )
  values (
    'teacher_wage',
    v_wage.id,
    v_wage.settlement_month,
    'teacher',
    v_wage.teacher_id,
    v_wage.teacher_name,
    v_wage.business_entity_id,
    v_wage.business_name,
    'JPY',
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_cny, 0) * 100) / 100,
    'pending',
    p_due_date,
    null,
    v_note,
    v_created_at,
    v_created_at,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
  )
  returning id into v_payment_id;

  return query
  select
    p.id,
    v_wage.id,
    p.request_month,
    p.payee_id,
    p.payee_name,
    p.business_entity_id,
    p.business_name,
    p.currency,
    p.amount,
    p.amount_jpy,
    p.amount_cny,
    p.status,
    p.created_at
  from public.school_payment_requests p
  where p.id = v_payment_id;
end;
$$;

comment on function public.school_create_teacher_wage_payment_request(uuid, date, text) is
  'Creates one pending teacher wage payment request from one locked teacher wage snapshot. Writes only school_payment_requests and rejects wage locks that already have any teacher_wage payment request.';

revoke all on function public.school_create_teacher_wage_payment_request(uuid,date,text)
  from public, anon, authenticated, service_role;
