-- school_income_cash_confirmation_workflow.sql
-- Status: executed on School DB 2026-06-15; installed as the current income Cash workflow.
-- Purpose:
-- - Add School-side Cash confirmation lifecycle for income records.
-- - Cash System income creates a School income business record first, then a
--   Cash pending external request. Cash approval is the only point that creates
--   home_jpy_transactions/home_cny_transactions and changes Cash balances.
-- - This file does not write real business data by itself. DML appears only
--   inside guarded RPC bodies.

begin;

alter table public.school_income_records
  drop constraint if exists school_income_records_status_check;

alter table public.school_income_records
  add constraint school_income_records_status_check
    check (status in ('pending', 'received', 'reversed', 'cancelled'));

create table if not exists public.school_personal_cash_income_linkage_events (
  id uuid primary key default gen_random_uuid(),
  source_table text not null default 'school_income_records',
  source_id uuid not null,
  source_event_type text not null default 'income_received',
  income_record_id uuid not null references public.school_income_records(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  cash_account_mapping_id uuid,
  cash_user_id uuid not null,
  cash_account_id uuid not null,
  cash_account_name_snapshot text not null,
  cash_account_type_snapshot text,
  cash_transaction_table text not null,
  cash_transaction_id uuid,
  currency text not null,
  amount numeric not null,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
  idempotency_key text not null,
  sync_status text not null default 'pending_cash_request',
  attempt_no integer not null default 1,
  cash_request_id uuid,
  cash_request_status text,
  requested_at timestamptz,
  confirmed_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
  cash_request_last_checked_at timestamptz,
  retry_count integer not null default 0,
  last_error text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz
);

alter table public.school_personal_cash_income_linkage_events
  alter column cash_account_mapping_id drop not null,
  add column if not exists cash_account_type_snapshot text,
  add column if not exists payment_currency text,
  add column if not exists payment_exchange_rate numeric,
  add column if not exists payment_amount numeric,
  add column if not exists attempt_no integer default 1,
  add column if not exists cash_request_id uuid,
  add column if not exists cash_request_status text,
  add column if not exists requested_at timestamptz,
  add column if not exists confirmed_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejected_reason text,
  add column if not exists cash_request_last_checked_at timestamptz;

alter table public.school_personal_cash_income_linkage_events
  alter column attempt_no set default 1,
  alter column attempt_no set not null;

alter table public.school_personal_cash_income_linkage_events
  drop constraint if exists school_pc_income_events_source_table_check,
  drop constraint if exists school_pc_income_events_source_id_check,
  drop constraint if exists school_pc_income_events_event_type_check,
  drop constraint if exists school_pc_income_events_cash_table_check,
  drop constraint if exists school_pc_income_events_currency_check,
  drop constraint if exists school_pc_income_events_amount_check,
  drop constraint if exists school_pc_income_events_status_check,
  drop constraint if exists school_pc_income_events_retry_count_check,
  drop constraint if exists school_pc_income_events_idempotency_not_blank_check,
  drop constraint if exists school_pc_income_events_account_name_not_blank_check,
  drop constraint if exists school_pc_income_events_synced_id_check,
  drop constraint if exists school_pc_income_events_attempt_no_check,
  drop constraint if exists school_pc_income_events_payment_currency_check,
  drop constraint if exists school_pc_income_events_payment_amount_check,
  drop constraint if exists school_pc_income_events_exchange_rate_check,
  add constraint school_pc_income_events_source_table_check
    check (source_table = 'school_income_records'),
  add constraint school_pc_income_events_source_id_check
    check (source_id = income_record_id),
  add constraint school_pc_income_events_event_type_check
    check (source_event_type in ('tuition_income_received', 'income_received')),
  add constraint school_pc_income_events_cash_table_check
    check (cash_transaction_table in ('home_jpy_transactions', 'home_cny_transactions')),
  add constraint school_pc_income_events_currency_check
    check (currency in ('JPY', 'CNY')),
  add constraint school_pc_income_events_amount_check
    check (amount > 0),
  add constraint school_pc_income_events_status_check
    check (sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked')),
  add constraint school_pc_income_events_retry_count_check
    check (retry_count >= 0),
  add constraint school_pc_income_events_idempotency_not_blank_check
    check (length(trim(idempotency_key)) > 0),
  add constraint school_pc_income_events_account_name_not_blank_check
    check (length(trim(cash_account_name_snapshot)) > 0),
  add constraint school_pc_income_events_synced_id_check
    check (sync_status <> 'synced' or cash_transaction_id is not null),
  add constraint school_pc_income_events_attempt_no_check
    check (attempt_no > 0),
  add constraint school_pc_income_events_payment_currency_check
    check (payment_currency is null or payment_currency in ('JPY', 'CNY')),
  add constraint school_pc_income_events_payment_amount_check
    check (payment_amount is null or payment_amount > 0),
  add constraint school_pc_income_events_exchange_rate_check
    check (payment_exchange_rate is null or payment_exchange_rate > 0);

drop index if exists public.school_pc_income_events_income_event_uniq;
drop index if exists public.school_pc_income_events_source_event_uniq;

create unique index if not exists school_pc_income_events_idempotency_uniq
  on public.school_personal_cash_income_linkage_events (idempotency_key);

create unique index if not exists school_pc_income_events_source_event_attempt_uniq
  on public.school_personal_cash_income_linkage_events (
    source_table,
    source_id,
    source_event_type,
    attempt_no
  );

create unique index if not exists school_pc_income_events_active_attempt_uniq
  on public.school_personal_cash_income_linkage_events (
    source_table,
    source_id,
    source_event_type
  )
  where sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation');

create index if not exists school_pc_income_events_income_record_idx
  on public.school_personal_cash_income_linkage_events (income_record_id);

create index if not exists school_pc_income_events_status_idx
  on public.school_personal_cash_income_linkage_events (sync_status, created_at);

drop function if exists public.school_create_cash_income_confirmation(
  date,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  boolean,
  text,
  text,
  text
);

create or replace function public.school_create_cash_income_confirmation(
  p_income_date date,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_student_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_amount numeric,
  p_income_category text default 'tuition',
  p_description text default null,
  p_currency text default 'JPY',
  p_payment_currency text default 'JPY',
  p_exchange_rate numeric default null,
  p_is_taxable_income boolean default false,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_note text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  amount numeric,
  currency text,
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
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_income_id uuid;
  v_event_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_description text;
  v_note text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_request_type text;
  v_cash_transaction_table text;
  v_idempotency_key text;
begin
  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception '请选择 Cash System 账户。';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  if v_currency not in ('JPY', 'CNY') or v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'Cash System 收入币种仅支持 JPY / CNY。';
  end if;

  if v_currency <> v_payment_currency then
    raise exception 'Cash System 收入要求收入币种与 Cash 账户币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
    into v_business_entity
    from public.school_business_entities
   where id = p_business_entity_id
     and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if v_income_category = 'tuition' and p_student_id is null then
    raise exception '学费收入必须选择学生。';
  end if;

  if p_student_id is not null then
    select *
      into v_student
      from public.school_students
     where id = p_student_id
       and app_type = 'school';

    if not found then
      raise exception '学生无效或不可用。';
    end if;

    if v_student.business_entity_id is not null
       and v_student.business_entity_id is distinct from p_business_entity_id then
      raise exception '学生业务归属与收入业务归属不一致。';
    end if;
  end if;

  if v_income_category = 'tuition' and exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = p_business_entity_id
       and s.year_month = v_year_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能直接新增收入。';
  end if;

  if v_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case when p_exchange_rate is not null then p_amount / p_exchange_rate else null end;
    v_cash_transaction_table := 'home_jpy_transactions';
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case when p_exchange_rate is not null then p_amount * p_exchange_rate else null end;
    v_cash_transaction_table := 'home_cny_transactions';
  end if;

  v_request_type := case
    when v_income_category = 'tuition' then 'tuition_income_received'
    else 'income_received'
  end;

  v_description := coalesce(
    nullif(trim(p_description), ''),
    case v_income_category
      when 'tuition' then '学费收入'
      when 'material_fee' then '教材费收入'
      when 'registration_fee' then '报名费收入'
      else '其他费用收入'
    end
  );
  v_note := nullif(trim(coalesce(p_note, '')), '');

  insert into public.school_income_records (
    business_entity_id,
    student_id,
    student_payment_id,
    account_id,
    income_date,
    year_month,
    settlement_month,
    income_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_currency,
    payment_method,
    status,
    is_taxable_income,
    tax_category,
    receipt_status,
    include_in_student_settlement,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_student_id,
    null,
    null,
    p_income_date,
    v_year_month,
    v_year_month,
    v_income_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_currency,
    null,
    'pending',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    'Cash待确认',
    v_income_category = 'tuition',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  v_idempotency_key := concat(
    'aozora_school:school_income_records:',
    v_income_id::text,
    ':',
    v_request_type,
    ':attempt:1'
  );

  insert into public.school_personal_cash_income_linkage_events (
    source_table,
    source_id,
    source_event_type,
    income_record_id,
    business_entity_id,
    cash_account_mapping_id,
    cash_user_id,
    cash_account_id,
    cash_account_name_snapshot,
    cash_account_type_snapshot,
    cash_transaction_table,
    cash_transaction_id,
    currency,
    amount,
    payment_currency,
    payment_exchange_rate,
    payment_amount,
    idempotency_key,
    sync_status,
    attempt_no,
    retry_count,
    note,
    created_at,
    updated_at
  )
  values (
    'school_income_records',
    v_income_id,
    v_request_type,
    v_income_id,
    p_business_entity_id,
    null,
    p_cash_user_id,
    p_cash_account_id,
    v_cash_account_name,
    v_cash_account_type,
    v_cash_transaction_table,
    null,
    v_currency,
    p_amount,
    v_payment_currency,
    p_exchange_rate,
    p_amount,
    v_idempotency_key,
    'pending_cash_request',
    1,
    0,
    v_note,
    v_now,
    v_now
  )
  returning id into v_event_id;

  return query
  select
    i.id,
    e.id,
    e.sync_status,
    e.attempt_no,
    e.idempotency_key,
    e.source_event_type,
    e.amount,
    e.currency,
    e.payment_currency,
    e.payment_exchange_rate,
    e.payment_amount,
    e.cash_user_id,
    e.cash_account_id,
    e.cash_account_name_snapshot,
    e.cash_account_type_snapshot,
    e.cash_request_id,
    e.cash_request_status,
    'School Cash income confirmation request event is ready to submit'::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = v_event_id
  where i.id = v_income_id;
end;
$$;

create or replace function public.school_request_cash_income_confirmation(
  p_income_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_note text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  amount numeric,
  currency text,
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
  v_income public.school_income_records%rowtype;
  v_existing public.school_personal_cash_income_linkage_events%rowtype;
  v_latest public.school_personal_cash_income_linkage_events%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_request_type text;
  v_idempotency_key text;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
begin
  if p_income_record_id is null then
    raise exception 'income record id is required';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception '请选择 Cash System 账户。';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = p_income_record_id
   for update;

  if not found then
    raise exception 'income record not found: %', p_income_record_id;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'Cash income request requires pending School income. current status: %', v_income.status;
  end if;

  if v_income.account_id is not null then
    raise exception 'Cash income must not have a School account id.';
  end if;

  if v_income.currency not in ('JPY', 'CNY') or v_income.payment_currency not in ('JPY', 'CNY') then
    raise exception 'Cash income currency must be JPY or CNY.';
  end if;

  if v_income.currency is distinct from v_income.payment_currency then
    raise exception 'Cash income requires income currency and payment currency to match.';
  end if;

  v_request_type := case
    when v_income.income_category = 'tuition' then 'tuition_income_received'
    else 'income_received'
  end;

  v_cash_transaction_table := case
    when v_income.currency = 'JPY' then 'home_jpy_transactions'
    else 'home_cny_transactions'
  end;

  select *
    into v_existing
    from public.school_personal_cash_income_linkage_events e
   where e.source_table = 'school_income_records'
     and e.source_id = p_income_record_id
     and e.source_event_type = v_request_type
     and e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
   for update;

  if found then
    if v_existing.cash_user_id is distinct from p_cash_user_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.cash_account_name_snapshot is distinct from v_cash_account_name
       or v_existing.cash_account_type_snapshot is distinct from v_cash_account_type
       or v_existing.currency is distinct from v_income.currency
       or v_existing.amount is distinct from v_income.amount then
      raise exception 'existing Cash income linkage event conflicts with requested snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash income linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    v_event_id := v_existing.id;
  else
    select *
      into v_latest
      from public.school_personal_cash_income_linkage_events e
     where e.source_table = 'school_income_records'
       and e.source_id = p_income_record_id
       and e.source_event_type = v_request_type
     order by e.attempt_no desc, e.created_at desc, e.id desc
     limit 1
     for update;

    if found and v_latest.sync_status <> 'cash_rejected' then
      raise exception 'latest Cash income linkage event is not rejected or requestable: %', v_latest.sync_status;
    end if;

    v_attempt_no := coalesce(v_latest.attempt_no, 0) + 1;
    v_idempotency_key := concat(
      'aozora_school:school_income_records:',
      p_income_record_id::text,
      ':',
      v_request_type,
      ':attempt:',
      v_attempt_no::text
    );

    insert into public.school_personal_cash_income_linkage_events (
      source_table,
      source_id,
      source_event_type,
      income_record_id,
      business_entity_id,
      cash_user_id,
      cash_account_id,
      cash_account_name_snapshot,
      cash_account_type_snapshot,
      cash_transaction_table,
      currency,
      amount,
      payment_currency,
      payment_exchange_rate,
      payment_amount,
      idempotency_key,
      sync_status,
      attempt_no,
      retry_count,
      note,
      created_at,
      updated_at
    )
    values (
      'school_income_records',
      p_income_record_id,
      v_request_type,
      p_income_record_id,
      v_income.business_entity_id,
      p_cash_user_id,
      p_cash_account_id,
      v_cash_account_name,
      v_cash_account_type,
      v_cash_transaction_table,
      v_income.currency,
      v_income.amount,
      v_income.payment_currency,
      v_income.exchange_rate,
      v_income.amount,
      v_idempotency_key,
      'pending_cash_request',
      v_attempt_no,
      coalesce(v_latest.retry_count, 0) + case when found then 1 else 0 end,
      v_note,
      v_now,
      v_now
    )
    returning id into v_event_id;
  end if;

  return query
  select
    i.id,
    e.id,
    e.sync_status,
    e.attempt_no,
    e.idempotency_key,
    e.source_event_type,
    e.amount,
    e.currency,
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
      when e.sync_status = 'awaiting_cash_confirmation' then 'Cash income confirmation request already submitted'
      else 'School Cash income confirmation request event is ready to submit'
    end::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = v_event_id
  where i.id = p_income_record_id;
end;
$$;

create or replace function public.school_mark_cash_income_request_submitted(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_cash_request_status text default 'pending'
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  requested_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_income public.school_income_records%rowtype;
  v_status text := nullif(trim(coalesce(p_cash_request_status, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null or p_cash_request_id is null then
    raise exception 'event id and Cash request id are required';
  end if;

  if v_status <> 'pending' then
    raise exception 'submitted Cash request status must be pending. current status: %', p_cash_request_status;
  end if;

  select *
    into v_event
    from public.school_personal_cash_income_linkage_events
   where id = p_event_id
   for update;

  if not found then
    raise exception 'Cash income linkage event not found: %', p_event_id;
  end if;

  if v_event.source_table <> 'school_income_records'
     or v_event.source_event_type not in ('tuition_income_received', 'income_received') then
    raise exception 'unsupported Cash income linkage event source';
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'Cash income linkage event already has a Cash transaction: %', p_event_id;
  end if;

  if v_event.sync_status not in ('pending_cash_request', 'awaiting_cash_confirmation') then
    raise exception 'Cash income linkage event cannot be marked submitted from status: %', v_event.sync_status;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash income linkage event already references a different Cash request: %', v_event.cash_request_id;
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = v_event.income_record_id
   for update;

  if not found then
    raise exception 'income record not found for Cash income linkage event: %', v_event.income_record_id;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'income record must remain pending while awaiting Cash confirmation. current status: %', v_income.status;
  end if;

  update public.school_personal_cash_income_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'pending',
         sync_status = 'awaiting_cash_confirmation',
         requested_at = coalesce(e.requested_at, v_now),
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    e.income_record_id,
    e.id,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.requested_at,
    'Cash income confirmation request submitted; income remains pending until Cash approval'::text
  from public.school_personal_cash_income_linkage_events e
  where e.id = p_event_id;
end;
$$;

create or replace function public.school_mark_cash_income_confirmed(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_cash_transaction_id uuid,
  p_confirmed_at timestamptz default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  income_status text,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  cash_transaction_id uuid,
  confirmed_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_income public.school_income_records%rowtype;
  v_confirmed_at timestamptz := coalesce(p_confirmed_at, now());
  v_now timestamptz := now();
begin
  if p_event_id is null or p_cash_request_id is null or p_cash_transaction_id is null then
    raise exception 'event id, Cash request id, and Cash transaction id are required';
  end if;

  select *
    into v_event
    from public.school_personal_cash_income_linkage_events
   where id = p_event_id
   for update;

  if not found then
    raise exception 'Cash income linkage event not found: %', p_event_id;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash income linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;

  if v_event.cash_transaction_id is not null
     and v_event.cash_transaction_id is distinct from p_cash_transaction_id then
    raise exception 'Cash income linkage event already references a different Cash transaction: %', v_event.cash_transaction_id;
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = v_event.income_record_id
   for update;

  if not found then
    raise exception 'income record not found for Cash income linkage event: %', v_event.income_record_id;
  end if;

  if v_event.sync_status = 'synced' then
    if coalesce(v_income.status, '') <> 'received'
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_transaction_id is distinct from p_cash_transaction_id
       or v_event.cash_request_status is distinct from 'approved' then
      raise exception 'existing synced Cash income linkage event conflicts with approved callback: %', p_event_id;
    end if;

    return query
    select
      v_income.id,
      v_event.id,
      v_income.status,
      v_event.sync_status,
      v_event.cash_request_id,
      v_event.cash_request_status,
      v_event.cash_transaction_id,
      v_event.confirmed_at,
      'Cash income approval already reflected in School'::text;
    return;
  end if;

  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash income linkage event must be awaiting Cash confirmation before approval callback. current status: %', v_event.sync_status;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'income record must remain pending before Cash approval. current status: %', v_income.status;
  end if;

  update public.school_income_records as i
     set status = 'received',
         receipt_status = 'Cash已确认',
         updated_at = v_now
   where i.id = v_income.id;

  update public.school_personal_cash_income_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'approved',
         sync_status = 'synced',
         cash_transaction_id = p_cash_transaction_id,
         confirmed_at = v_confirmed_at,
         synced_at = v_confirmed_at,
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    i.id,
    e.id,
    i.status,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.cash_transaction_id,
    e.confirmed_at,
    'Cash income approval reflected in School; income marked received without School account ledger side effects'::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = p_event_id
  where i.id = v_income.id;
end;
$$;

create or replace function public.school_mark_cash_income_rejected(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_rejected_reason text default null,
  p_rejected_at timestamptz default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  income_status text,
  sync_status text,
  cash_request_id uuid,
  cash_request_status text,
  rejected_at timestamptz,
  rejected_reason text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_income public.school_income_records%rowtype;
  v_rejected_at timestamptz := coalesce(p_rejected_at, now());
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null or p_cash_request_id is null then
    raise exception 'event id and Cash request id are required';
  end if;

  select *
    into v_event
    from public.school_personal_cash_income_linkage_events
   where id = p_event_id
   for update;

  if not found then
    raise exception 'Cash income linkage event not found: %', p_event_id;
  end if;

  if v_event.cash_request_id is not null
     and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash income linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;

  if v_event.cash_transaction_id is not null then
    raise exception 'Cash income linkage event already has a Cash transaction and cannot be rejected: %', p_event_id;
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = v_event.income_record_id
   for update;

  if not found then
    raise exception 'income record not found for Cash income linkage event: %', v_event.income_record_id;
  end if;

  if v_event.sync_status = 'cash_rejected' then
    if coalesce(v_income.status, '') <> 'pending'
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_request_status is distinct from 'rejected' then
      raise exception 'existing rejected Cash income linkage event conflicts with rejection callback: %', p_event_id;
    end if;

    return query
    select
      v_income.id,
      v_event.id,
      v_income.status,
      v_event.sync_status,
      v_event.cash_request_id,
      v_event.cash_request_status,
      v_event.rejected_at,
      v_event.rejected_reason,
      'Cash income rejection already reflected in School'::text;
    return;
  end if;

  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash income linkage event must be awaiting Cash confirmation before rejection callback. current status: %', v_event.sync_status;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'income record must remain pending for Cash rejection. current status: %', v_income.status;
  end if;

  update public.school_income_records as i
     set receipt_status = 'Cash已拒绝',
         updated_at = v_now
   where i.id = v_income.id;

  update public.school_personal_cash_income_linkage_events as e
     set cash_request_id = p_cash_request_id,
         cash_request_status = 'rejected',
         sync_status = 'cash_rejected',
         rejected_at = v_rejected_at,
         rejected_reason = v_reason,
         cash_request_last_checked_at = v_now,
         last_error = null,
         updated_at = v_now
   where e.id = p_event_id;

  return query
  select
    i.id,
    e.id,
    i.status,
    e.sync_status,
    e.cash_request_id,
    e.cash_request_status,
    e.rejected_at,
    e.rejected_reason,
    'Cash income rejection reflected in School; income remains pending and can be retried'::text
  from public.school_income_records i
  join public.school_personal_cash_income_linkage_events e
    on e.id = p_event_id
  where i.id = v_income.id;
end;
$$;

comment on table public.school_personal_cash_income_linkage_events is
  'School-side Cash confirmation lifecycle for income records. Pending requests do not affect Cash balances; Cash approval creates the Cash transaction and then marks School income received.';

comment on function public.school_create_cash_income_confirmation(
  date,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  boolean,
  text,
  text,
  text
) is
  'Creates one pending School income record and one pending Cash income confirmation attempt. Does not write School account ledgers or Cash DB.';

comment on function public.school_request_cash_income_confirmation(uuid, uuid, uuid, text, text, text) is
  'Creates or returns one active Cash income confirmation attempt for an existing pending School income record.';

comment on function public.school_mark_cash_income_request_submitted(uuid, uuid, text) is
  'Marks a Cash income confirmation attempt as submitted to a Cash pending external request.';

comment on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz) is
  'Reflects Cash approval of an income request. Marks School income received and linkage synced without School account ledger side effects.';

comment on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz) is
  'Reflects Cash rejection of an income request. Keeps School income pending and linkage cash_rejected.';

grant execute on function public.school_create_cash_income_confirmation(
  date,
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  numeric,
  boolean,
  text,
  text,
  text
) to authenticated, service_role;

grant execute on function public.school_request_cash_income_confirmation(uuid, uuid, uuid, text, text, text)
  to authenticated, service_role;

grant execute on function public.school_mark_cash_income_request_submitted(uuid, uuid, text)
  to authenticated, service_role;

grant execute on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  to authenticated, service_role;

grant execute on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz)
  to authenticated, service_role;

commit;
