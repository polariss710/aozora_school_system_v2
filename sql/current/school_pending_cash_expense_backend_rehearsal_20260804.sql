-- Production-schema rehearsal. Every DDL/RPC change is rolled back.
\set ON_ERROR_STOP on
\pset pager off

select md5(pg_get_functiondef(
  'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'::regprocedure
)) as paid_before \gset
select md5(pg_get_functiondef(
  'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)'::regprocedure
)) as prepare_before \gset

begin;
\ir school_pending_cash_expense_identity_schema_20260804.sql
\ir school_pending_cash_expense_identity_guard_20260804.sql
\ir school_create_expense_record_rpc.sql
\ir school_create_pending_cash_expense_record_v1_rpc.sql
\ir school_expense_cash_request_backend_amount_rpc.sql

do $verify_inside$
begin
  if to_regprocedure(
    'public.school_create_pending_cash_expense_record_v1(uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text)'
  ) is null then
    raise exception 'P0_PENDING_CASH_REHEARSAL_FUNCTION_MISSING';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='school_expense_records'
      and column_name='cash_creation_event_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='school_expense_records'
      and column_name='created_by_user_id'
  ) then
    raise exception 'P0_PENDING_CASH_REHEARSAL_COLUMNS_MISSING';
  end if;
end;
$verify_inside$;

rollback;

do $verify_rollback$
begin
  if to_regprocedure(
    'public.school_create_pending_cash_expense_record_v1(uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text)'
  ) is not null then
    raise exception 'P0_PENDING_CASH_REHEARSAL_FUNCTION_PERSISTED';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='school_expense_records'
      and column_name in ('cash_creation_event_id','created_by_user_id')
  ) then
    raise exception 'P0_PENDING_CASH_REHEARSAL_COLUMNS_PERSISTED';
  end if;
end;
$verify_rollback$;

select md5(pg_get_functiondef(
  'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'::regprocedure
)) = :'paid_before' as paid_restored \gset
\if :paid_restored
\else
  \echo P0_PENDING_CASH_REHEARSAL_PAID_WRITER_NOT_RESTORED
  \quit 1
\endif

select md5(pg_get_functiondef(
  'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)'::regprocedure
)) = :'prepare_before' as prepare_restored \gset
\if :prepare_restored
\else
  \echo P0_PENDING_CASH_REHEARSAL_PREPARE_WRITER_NOT_RESTORED
  \quit 1
\endif

select 'P0_PENDING_CASH_BACKEND_REHEARSAL_ROLLBACK_PASS' as result;
