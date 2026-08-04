-- school_teacher_wage_expense_record_route.sql
-- Purpose:
-- - Prepare school_expense_records as the canonical teacher_wage expense route.
-- - Add source / Cash linkage fields needed by future expense -> Cash request flow.
-- - Add a dedicated RPC to generate one pending teacher_wage expense record from
--   one locked teacher wage snapshot.
--
-- Scope:
-- - Does not migrate existing school_payment_requests.
-- - Does not create Cash requests or Cash transactions.
-- - Does not update teacher wage locks, payment requests, accounts, or account transactions.
-- - Write RPC is granted to authenticated only; no anon grant.

alter table public.school_expense_records
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists payee_name_snapshot text,
  add column if not exists cash_request_id uuid,
  add column if not exists cash_request_status text,
  add column if not exists cash_transaction_id uuid,
  add column if not exists cash_requested_at timestamptz,
  add column if not exists cash_synced_at timestamptz,
  add column if not exists cash_error_message text;

create index if not exists school_expense_records_source_idx
  on public.school_expense_records (source_type, source_id)
  where source_type is not null and source_id is not null;

create unique index if not exists school_expense_records_teacher_wage_source_uniq
  on public.school_expense_records (source_id)
  where source_type = 'teacher_wage'
    and source_id is not null
    and app_type = 'school';

create index if not exists school_expense_records_cash_request_idx
  on public.school_expense_records (cash_request_id)
  where cash_request_id is not null;

comment on column public.school_expense_records.source_type is
  'Canonical business source type for generated expense records, for example teacher_wage. Used before any Cash request is created.';

comment on column public.school_expense_records.source_id is
  'Canonical business source id for generated expense records. For teacher_wage, this points to school_teacher_wage_locks.id.';

comment on column public.school_expense_records.payee_name_snapshot is
  'Payee display name snapshot at the time a generated expense record is created.';

comment on column public.school_expense_records.cash_request_id is
  'Cash external request id once this expense record is submitted to Cash.';

comment on column public.school_expense_records.cash_request_status is
  'Cash request status snapshot for the canonical expense -> Cash flow.';

comment on column public.school_expense_records.cash_transaction_id is
  'Cash transaction id written back after Cash approves the external request.';

comment on column public.school_expense_records.cash_requested_at is
  'Timestamp when this expense record was submitted to Cash.';

comment on column public.school_expense_records.cash_synced_at is
  'Timestamp when the Cash result was synced back to School.';

comment on column public.school_expense_records.cash_error_message is
  'Last Cash request or sync error message for this expense record.';

create or replace function public.school_create_teacher_wage_expense_record(
  p_wage_lock_id uuid,
  p_expense_date date default null,
  p_note text default null
)
returns table (
  expense_id uuid,
  wage_lock_id uuid,
  expense_status text,
  expense_category text,
  source_type text,
  source_id uuid,
  teacher_id uuid,
  payee_name_snapshot text,
  business_entity_id uuid,
  year_month text,
  currency text,
  amount numeric,
  amount_jpy numeric,
  amount_cny numeric,
  cash_request_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_wage public.school_teacher_wage_locks%rowtype;
  v_existing_expense public.school_expense_records%rowtype;
  v_expense_id uuid;
  v_expense_date date;
  v_now timestamptz := now();
  v_description text;
  v_note text;
begin
  perform public.school_require_current_app_admin();

  if p_wage_lock_id is null then
    raise exception 'wage lock id is required';
  end if;

  select *
    into v_wage
    from public.school_teacher_wage_locks
   where id = p_wage_lock_id
   for update;

  if not found then
    raise exception 'teacher wage lock not found: %', p_wage_lock_id;
  end if;

  if coalesce(v_wage.status, '') <> 'locked' then
    raise exception 'only locked teacher wage records can generate expense records. current status: %', v_wage.status;
  end if;

  if v_wage.voided_at is not null then
    raise exception 'voided teacher wage records cannot generate expense records: %', p_wage_lock_id;
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
    raise exception 'teacher wage total_jpy must be greater than 0 to generate an expense record. current total_jpy: %', v_wage.total_jpy;
  end if;

  select *
    into v_existing_expense
    from public.school_expense_records e
   where e.source_type = 'teacher_wage'
     and e.source_id = p_wage_lock_id
     and e.app_type = 'school'
   order by e.created_at asc
   limit 1;

  if v_existing_expense.id is not null then
    return query
    select
      e.id,
      p_wage_lock_id,
      e.status,
      e.expense_category,
      e.source_type,
      e.source_id,
      e.teacher_id,
      e.payee_name_snapshot,
      e.business_entity_id,
      e.year_month,
      e.currency,
      e.amount,
      e.amount_jpy,
      e.amount_cny,
      e.cash_request_status,
      e.created_at
    from public.school_expense_records e
    where e.id = v_existing_expense.id;

    return;
  end if;

  v_expense_date := coalesce(
    p_expense_date,
    (to_date(v_wage.settlement_month || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date
  );
  v_description := trim(both from concat(v_wage.settlement_month, ' ', v_wage.teacher_name, ' 老师工资'));
  v_note := nullif(trim(coalesce(p_note, '')), '');

  insert into public.school_expense_records (
    business_entity_id,
    teacher_id,
    student_id,
    salary_payment_id,
    account_id,
    expense_date,
    year_month,
    expense_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_method,
    status,
    is_business_expense,
    tax_category,
    receipt_status,
    reimbursement_status,
    reimbursement_note,
    note,
    app_type,
    source_type,
    source_id,
    payee_name_snapshot,
    cash_request_id,
    cash_request_status,
    cash_transaction_id,
    cash_requested_at,
    cash_synced_at,
    cash_error_message,
    created_at,
    updated_at
  )
  values (
    v_wage.business_entity_id,
    v_wage.teacher_id,
    null,
    null,
    null,
    v_expense_date,
    v_wage.settlement_month,
    'teacher_wage',
    v_description,
    'JPY',
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_cny, 0) * 100) / 100,
    nullif(v_wage.exchange_rate, 0),
    null,
    'pending',
    true,
    '給与',
    '无需收据',
    null,
    null,
    v_note,
    'school',
    'teacher_wage',
    v_wage.id,
    v_wage.teacher_name,
    null,
    null,
    null,
    null,
    null,
    null,
    v_now,
    v_now
  )
  returning id into v_expense_id;

  return query
  select
    e.id,
    v_wage.id,
    e.status,
    e.expense_category,
    e.source_type,
    e.source_id,
    e.teacher_id,
    e.payee_name_snapshot,
    e.business_entity_id,
    e.year_month,
    e.currency,
    e.amount,
    e.amount_jpy,
    e.amount_cny,
    e.cash_request_status,
    e.created_at
  from public.school_expense_records e
  where e.id = v_expense_id;
end;
$$;

comment on function public.school_create_teacher_wage_expense_record(uuid, date, text) is
  'Creates or returns one pending teacher_wage school_expense_records row from one locked teacher wage snapshot. Does not create Cash requests, Cash transactions, payment requests, account transactions, or account balance changes.';

revoke all on function public.school_create_teacher_wage_expense_record(uuid,date,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_create_teacher_wage_expense_record(uuid, date, text) to authenticated;
