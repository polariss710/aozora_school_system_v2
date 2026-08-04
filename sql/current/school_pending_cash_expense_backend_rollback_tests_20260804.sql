-- School V2 manual Cash pending-expense backend rollback matrix.
-- All fixtures, writer calls, ledger effects and schema/RPC changes roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_pending_cash_expense_identity_schema_20260804.sql
\ir school_pending_cash_expense_identity_guard_20260804.sql
\ir school_create_expense_record_rpc.sql
\ir school_create_pending_cash_expense_record_v1_rpc.sql
\ir school_expense_cash_request_backend_amount_rpc.sql

insert into auth.users (
  id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('e4200000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cash-create-operator"}'::jsonb,now(),now()),
  ('e4200000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"cash-create-admin"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
  ('e4200000-0000-4000-8000-000000000001','operator',true,'e4200000-0000-4000-8000-000000000001','e4200000-0000-4000-8000-000000000001','codex-test cash-create operator'),
  ('e4200000-0000-4000-8000-000000000002','admin',true,'e4200000-0000-4000-8000-000000000002','e4200000-0000-4000-8000-000000000002','codex-test cash-create admin');

insert into public.school_accounts (
  id,account_code,name,account_type,currency,business_entity_id,
  opening_balance,current_balance,is_company_account,is_active,note,app_type
) values (
  'e4200000-0000-4000-8000-000000000100','CODEX-CASH-CREATE',
  'codex-test cash-create School account','cash','JPY',
  public.school_primary_business_entity_id(),100000,100000,true,true,
  'codex-test cash-create rollback-only','school'
);

set local role authenticated;

do $role_and_creation_matrix$
declare
  v_denied boolean := false;
  v_first record;
  v_retry record;
  v_paid record;
  v_conflict boolean := false;
  v_balance numeric;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub','e4200000-0000-4000-8000-000000000001'::uuid,'role','authenticated')::text,
    true
  );
  begin
    perform * from public.school_create_pending_cash_expense_record_v1(
      'e4200000-0000-4000-8000-000000000201',current_date,
      public.school_primary_business_entity_id(),'other','codex-test denied',
      'JPY',700,'not_required',null,true,null,'待确认',null,null,
      'codex-test cash-create rollback-only'
    );
  exception when insufficient_privilege then
    if sqlerrm='P0G1_ACTIVE_ADMIN_REQUIRED' then v_denied := true; else raise; end if;
  end;
  if not v_denied then raise exception 'P0_PENDING_CASH_NON_ADMIN_ACCEPTED'; end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub','e4200000-0000-4000-8000-000000000002'::uuid,'role','authenticated')::text,
    true
  );

  select * into v_first
  from public.school_create_pending_cash_expense_record_v1(
    'e4200000-0000-4000-8000-000000000201',current_date,
    public.school_primary_business_entity_id(),'other','codex-test pending Cash expense',
    'JPY',700,'not_required',null,true,null,'待确认',null,null,
    'codex-test cash-create rollback-only'
  );
  select * into v_retry
  from public.school_create_pending_cash_expense_record_v1(
    'e4200000-0000-4000-8000-000000000201',current_date,
    public.school_primary_business_entity_id(),'other','codex-test pending Cash expense',
    'JPY',700,'not_required',null,true,null,'待确认',null,null,
    'codex-test cash-create rollback-only'
  );

  if v_first.expense_id is distinct from v_retry.expense_id
     or v_first.idempotent
     or not v_retry.idempotent
     or v_first.expense_status <> 'pending'
     or v_first.cash_request_status is not null
     or v_first.creation_channel <> 'manual_cash'
     or v_first.created_by_user_id <> 'e4200000-0000-4000-8000-000000000002'::uuid then
    raise exception 'P0_PENDING_CASH_IDEMPOTENCY_RESULT_INVALID';
  end if;

  if not exists (
    select 1 from public.school_expense_records e
    where e.id=v_first.expense_id
      and e.account_id is null and e.payment_method is null
      and e.status='pending' and e.source_type='manual_cash'
      and e.cash_creation_event_id='e4200000-0000-4000-8000-000000000201'::uuid
      and e.created_by_user_id='e4200000-0000-4000-8000-000000000002'::uuid
      and e.cash_request_id is null and e.cash_transaction_id is null
      and e.cash_request_status is null and e.cash_request_attempt_no=0
  ) then
    raise exception 'P0_PENDING_CASH_CANONICAL_ROW_INVALID';
  end if;

  select current_balance into v_balance from public.school_accounts
  where id='e4200000-0000-4000-8000-000000000100';
  if v_balance<>100000 or exists (
    select 1 from public.school_account_transactions
    where related_table='school_expense_records' and related_id=v_first.expense_id
  ) then
    raise exception 'P0_PENDING_CASH_CHANGED_SCHOOL_LEDGER';
  end if;

  begin
    perform * from public.school_create_pending_cash_expense_record_v1(
      'e4200000-0000-4000-8000-000000000201',current_date,
      public.school_primary_business_entity_id(),'other','codex-test conflicting payload',
      'JPY',701,'not_required',null,true,null,'待确认',null,null,
      'codex-test cash-create rollback-only'
    );
  exception when unique_violation then
    if sqlerrm='P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT' then v_conflict:=true; else raise; end if;
  end;
  if not v_conflict then raise exception 'P0_PENDING_CASH_CONFLICT_ACCEPTED'; end if;

  select * into v_paid from public.school_create_expense_record(
    current_date,public.school_primary_business_entity_id(),
    'e4200000-0000-4000-8000-000000000100','other',
    'codex-test direct School expense','JPY',1234,null,'cash',true,null,
    '待确认',null,null,null,'codex-test cash-create rollback-only'
  );
  if not exists (
    select 1 from public.school_expense_records e
    where e.id=v_paid.expense_id and e.status='paid' and e.source_type='manual_school'
      and e.created_by_user_id='e4200000-0000-4000-8000-000000000002'::uuid
      and e.cash_creation_event_id is null
  ) or not exists (
    select 1 from public.school_account_transactions t
    where t.related_table='school_expense_records' and t.related_id=v_paid.expense_id
      and t.amount=-1234
  ) then
    raise exception 'P0_PAID_EXPENSE_CREATOR_AUDIT_OR_LEDGER_INVALID';
  end if;
end;
$role_and_creation_matrix$;

reset role;

do $owner_immutability_matrix$
declare
  v_immutable boolean := false;
begin
  begin
    update public.school_expense_records
    set created_by_user_id='e4200000-0000-4000-8000-000000000001'
    where cash_creation_event_id='e4200000-0000-4000-8000-000000000201';
  exception when sqlstate '55000' then
    if sqlerrm='P0_EXPENSE_CREATION_AUDIT_IMMUTABLE' then v_immutable:=true; else raise; end if;
  end;
  if not v_immutable then raise exception 'P0_PENDING_CASH_AUDIT_MUTABLE'; end if;
end;
$owner_immutability_matrix$;

set local role service_role;

do $prepare_matrix$
declare
  v_prepared record;
begin
  select * into v_prepared
  from public.school_request_cash_expense_payment_confirmation(
    (select id from public.school_expense_records
     where cash_creation_event_id='e4200000-0000-4000-8000-000000000201'),
    'e4200000-0000-4000-8000-000000000301',
    'e4200000-0000-4000-8000-000000000302',
    'codex-test Cash account','cash',null,null,
    'codex-test cash-create rollback-only',null,null
  );
  if v_prepared.attempt_no<>1
     or v_prepared.expense_status<>'pending'
     or v_prepared.source_type<>'manual_cash'
     or v_prepared.payment_amount<>700
     or v_prepared.payment_currency<>'JPY' then
    raise exception 'P0_PENDING_CASH_PREPARE_RESULT_INVALID';
  end if;
end;
$prepare_matrix$;

reset role;

do $acl_matrix$
declare
  v_create regprocedure :=
    'public.school_create_pending_cash_expense_record_v1(uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text)'::regprocedure;
begin
  if has_function_privilege('anon',v_create,'EXECUTE')
     or not has_function_privilege('authenticated',v_create,'EXECUTE')
     or has_function_privilege('service_role',v_create,'EXECUTE') then
    raise exception 'P0_PENDING_CASH_CREATE_ACL_INVALID';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'P0_PENDING_CASH_PREPARE_AUTHENTICATED_EXECUTE_REMAINS';
  end if;
end;
$acl_matrix$;

select 'P0_PENDING_CASH_BACKEND_ROLLBACK_TEST_PASS' as result;
rollback;
