-- School V2 ordinary-expense P0 permission closure core, 2026-08-04.
-- Included byte-for-byte by rollback tests and the formal deployment wrapper.
-- This file changes function/RLS/ACL/default-privilege definitions only.

do $preflight$
begin
  if to_regprocedure(
    'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'
  ) is null then
    raise exception 'P0_EXPENSE_CREATE_WRITER_MISSING';
  end if;

  if to_regprocedure(
    'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)'
  ) is null
     or to_regprocedure(
       'public.school_mark_cash_expense_request_submitted(uuid,uuid,text)'
     ) is null
     or to_regprocedure(
       'public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz)'
     ) is null
     or to_regprocedure(
       'public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz)'
     ) is null then
    raise exception 'P0_EXPENSE_CASH_WRITER_SET_INCOMPLETE';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'school_create_expense_record'
  ) <> 1 then
    raise exception 'P0_EXPENSE_CREATE_OVERLOAD_DRIFT';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'school_request_cash_expense_payment_confirmation',
        'school_mark_cash_expense_request_submitted',
        'school_mark_cash_expense_confirmed',
        'school_mark_cash_expense_rejected'
      )
  ) <> 4 then
    raise exception 'P0_EXPENSE_CASH_OVERLOAD_DRIFT';
  end if;
end;
$preflight$;

\ir school_create_expense_record_rpc.sql

alter function public.school_request_cash_expense_payment_confirmation(
  uuid, uuid, uuid, text, text, numeric, text, text, numeric, text
) set search_path = pg_catalog, public;
alter function public.school_mark_cash_expense_request_submitted(uuid, uuid, text)
  set search_path = pg_catalog, public;
alter function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz)
  set search_path = pg_catalog, public;
alter function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz)
  set search_path = pg_catalog, public;

revoke all on function public.school_request_cash_expense_payment_confirmation(
  uuid, uuid, uuid, text, text, numeric, text, text, numeric, text
) from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz)
  from public, anon, authenticated, service_role;

grant execute on function public.school_request_cash_expense_payment_confirmation(
  uuid, uuid, uuid, text, text, numeric, text, text, numeric, text
) to service_role;
grant execute on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text)
  to service_role;
grant execute on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz)
  to service_role;
grant execute on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz)
  to service_role;

revoke all privileges on table public.school_expense_records
  from public, anon, authenticated;
revoke all privileges on table public.school_accounts
  from public, anon, authenticated;
revoke all privileges on table public.school_account_transactions
  from public, anon, authenticated;

grant select on table public.school_expense_records to authenticated;
grant select on table public.school_accounts to authenticated;
grant select on table public.school_account_transactions to authenticated;

alter table public.school_expense_records enable row level security;
alter table public.school_accounts enable row level security;
alter table public.school_account_transactions enable row level security;

alter policy school_allow_all_expense_records
  on public.school_expense_records
  to service_role
  using (true)
  with check (true);
do $expense_select_policy$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'school_expense_records'
      and policyname = 'school_expense_records_authenticated_select'
  ) then
    alter policy school_expense_records_authenticated_select
      on public.school_expense_records
      to authenticated
      using (true);
  else
    create policy school_expense_records_authenticated_select
      on public.school_expense_records
      for select
      to authenticated
      using (true);
  end if;
end;
$expense_select_policy$;

alter policy school_allow_all_accounts
  on public.school_accounts
  to service_role
  using (true)
  with check (true);
do $account_select_policy$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'school_accounts'
      and policyname = 'school_accounts_authenticated_select'
  ) then
    alter policy school_accounts_authenticated_select
      on public.school_accounts
      to authenticated
      using (true);
  else
    create policy school_accounts_authenticated_select
      on public.school_accounts
      for select
      to authenticated
      using (true);
  end if;
end;
$account_select_policy$;

alter policy school_allow_all_account_transactions
  on public.school_account_transactions
  to service_role
  using (true)
  with check (true);
do $transaction_select_policy$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'school_account_transactions'
      and policyname = 'school_account_transactions_authenticated_select'
  ) then
    alter policy school_account_transactions_authenticated_select
      on public.school_account_transactions
      to authenticated
      using (true);
  else
    create policy school_account_transactions_authenticated_select
      on public.school_account_transactions
      for select
      to authenticated
      using (true);
  end if;
end;
$transaction_select_policy$;

alter default privileges for role postgres in schema public
  revoke all privileges on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on functions from public, anon, authenticated;

comment on function public.school_request_cash_expense_payment_confirmation(
  uuid, uuid, uuid, text, text, numeric, text, text, numeric, text
) is
  'Service-role-only preparation of an idempotent School expense to Cash pending-request attempt. Browser users must use the active-admin-guarded Edge Function.';
comment on function public.school_mark_cash_expense_request_submitted(uuid, uuid, text) is
  'Service-role-only School writeback after a Cash expense pending request exists.';
comment on function public.school_mark_cash_expense_confirmed(uuid, uuid, uuid, timestamptz) is
  'Service-role-only trusted callback writeback after Cash approved an expense request and created its transaction.';
comment on function public.school_mark_cash_expense_rejected(uuid, uuid, text, timestamptz) is
  'Service-role-only trusted callback writeback after Cash rejected an expense request.';
