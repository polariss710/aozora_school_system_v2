-- School V2 ordinary-expense P0 permission closure rollback matrix.
-- All fixture rows, ACL changes, RLS changes and writer calls roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;

\ir school_p0_expense_permission_closure_core_20260804.sql

insert into auth.users (
  id, aud, role, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e4100000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-expense-operator"}'::jsonb,now(),now()),
  ('e4100000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-expense-read-only"}'::jsonb,now(),now()),
  ('e4100000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-expense-inactive-admin"}'::jsonb,now(),now()),
  ('e4100000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-expense-active-admin"}'::jsonb,now(),now()),
  ('e4100000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"p0-expense-no-membership"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id, role, is_active, created_by_user_id, updated_by_user_id, note
)
values
  ('e4100000-0000-4000-8000-000000000001','operator',true,'e4100000-0000-4000-8000-000000000001','e4100000-0000-4000-8000-000000000001','codex-test p0-expense operator'),
  ('e4100000-0000-4000-8000-000000000002','read_only',true,'e4100000-0000-4000-8000-000000000002','e4100000-0000-4000-8000-000000000002','codex-test p0-expense read-only'),
  ('e4100000-0000-4000-8000-000000000003','admin',false,'e4100000-0000-4000-8000-000000000003','e4100000-0000-4000-8000-000000000003','codex-test p0-expense inactive admin'),
  ('e4100000-0000-4000-8000-000000000004','admin',true,'e4100000-0000-4000-8000-000000000004','e4100000-0000-4000-8000-000000000004','codex-test p0-expense active admin');

insert into public.school_accounts (
  id, account_code, name, account_type, currency, business_entity_id,
  opening_balance, current_balance, is_company_account, is_active, note, app_type
)
values (
  'e4100000-0000-4000-8000-000000000100',
  'CODEX-P0-EXPENSE',
  'codex-test p0 expense account',
  'cash',
  'JPY',
  public.school_primary_business_entity_id(),
  100000,
  100000,
  true,
  true,
  'codex-test p0-expense rollback-only',
  'school'
);

insert into public.school_expense_records (
  id, business_entity_id, expense_date, year_month, expense_category,
  description, currency, amount, amount_jpy, status, app_type,
  cash_request_attempt_no, note
)
values
  (
    'e4100000-0000-4000-8000-000000000201',
    public.school_primary_business_entity_id(),
    current_date,
    to_char(current_date, 'YYYY-MM'),
    'other',
    'codex-test p0 cash prepare and reject',
    'JPY',
    500,
    500,
    'pending',
    'school',
    0,
    'codex-test p0-expense rollback-only'
  ),
  (
    'e4100000-0000-4000-8000-000000000202',
    public.school_primary_business_entity_id(),
    current_date,
    to_char(current_date, 'YYYY-MM'),
    'other',
    'codex-test p0 cash confirm',
    'JPY',
    600,
    600,
    'pending',
    'school',
    1,
    'codex-test p0-expense rollback-only'
  );

set local role authenticated;

do $ordinary_role_matrix$
declare
  v_actor uuid;
  v_denied boolean;
  v_created record;
  v_expense_count bigint;
  v_transaction_count bigint;
  v_balance numeric;
begin
  foreach v_actor in array array[
    'e4100000-0000-4000-8000-000000000001'::uuid,
    'e4100000-0000-4000-8000-000000000002'::uuid,
    'e4100000-0000-4000-8000-000000000003'::uuid,
    'e4100000-0000-4000-8000-000000000005'::uuid
  ] loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_actor, 'role', 'authenticated')::text,
      true
    );
    v_denied := false;
    begin
      perform *
      from public.school_create_expense_record(
        current_date,
        public.school_primary_business_entity_id(),
        'e4100000-0000-4000-8000-000000000100',
        'other',
        'codex-test denied role',
        'JPY',
        100,
        null,
        'cash',
        true,
        null,
        '待确认',
        null,
        null,
        null,
        'codex-test p0-expense rollback-only'
      );
    exception when insufficient_privilege then
      if sqlerrm = 'P0G1_ACTIVE_ADMIN_REQUIRED' then
        v_denied := true;
      else
        raise;
      end if;
    end;
    if not v_denied then
      raise exception 'P0_EXPENSE_NON_ADMIN_ACCEPTED: %', v_actor;
    end if;
  end loop;

  v_actor := 'e4100000-0000-4000-8000-000000000004'::uuid;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_actor, 'role', 'authenticated')::text,
    true
  );

  select * into v_created
  from public.school_create_expense_record(
    current_date,
    public.school_primary_business_entity_id(),
    'e4100000-0000-4000-8000-000000000100',
    'other',
    'codex-test active admin paid expense',
    'JPY',
    1234,
    null,
    'cash',
    true,
    null,
    '待确认',
    null,
    null,
    null,
    'codex-test p0-expense rollback-only'
  );

  if v_created.expense_status <> 'paid'
     or v_created.transaction_type <> 'expense_adjust'
     or v_created.new_balance <> 98766 then
    raise exception 'P0_EXPENSE_ACTIVE_ADMIN_RESULT_INVALID';
  end if;

  select count(*) into v_expense_count
  from public.school_expense_records
  where id = v_created.expense_id
    and status = 'paid'
    and amount = 1234;

  select count(*) into v_transaction_count
  from public.school_account_transactions
  where related_table = 'school_expense_records'
    and related_id = v_created.expense_id
    and amount = -1234;

  select current_balance into v_balance
  from public.school_accounts
  where id = 'e4100000-0000-4000-8000-000000000100';

  if v_expense_count <> 1 or v_transaction_count <> 1 or v_balance <> 98766 then
    raise exception 'P0_EXPENSE_PAID_LEDGER_RESULT_INVALID';
  end if;

  begin
    perform *
    from public.school_create_expense_record(
      current_date,
      public.school_primary_business_entity_id(),
      'e4100000-0000-4000-8000-000000000100',
      'teacher_wage',
      'codex-test forced failure',
      'JPY',
      999,
      null,
      'cash',
      true,
      null,
      '待确认',
      null,
      null,
      null,
      'codex-test p0-expense rollback-only'
    );
    raise exception 'P0_EXPENSE_FAILURE_PATH_ACCEPTED';
  exception when others then
    if sqlerrm = 'P0_EXPENSE_FAILURE_PATH_ACCEPTED' then
      raise;
    end if;
  end;

  select count(*) into v_expense_count
  from public.school_expense_records
  where note = 'codex-test p0-expense rollback-only';
  select count(*) into v_transaction_count
  from public.school_account_transactions
  where account_id = 'e4100000-0000-4000-8000-000000000100';
  select current_balance into v_balance
  from public.school_accounts
  where id = 'e4100000-0000-4000-8000-000000000100';

  if v_expense_count <> 3 or v_transaction_count <> 1 or v_balance <> 98766 then
    raise exception 'P0_EXPENSE_FAILURE_PATH_NOT_ATOMIC';
  end if;
end;
$ordinary_role_matrix$;

do $authenticated_direct_denials$
declare
  v_denied boolean;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', 'e4100000-0000-4000-8000-000000000004'::uuid,
      'role', 'authenticated'
    )::text,
    true
  );

  v_denied := false;
  begin
    perform *
    from public.school_mark_cash_expense_confirmed(
      'e4100000-0000-4000-8000-000000000202',
      'e4100000-0000-4000-8000-000000000301',
      'e4100000-0000-4000-8000-000000000401',
      now()
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_AUTHENTICATED_CASH_WRITER_ACCEPTED';
  end if;

  if (select count(*) from public.school_expense_records) < 1 then
    raise exception 'P0_EXPENSE_AUTHENTICATED_SELECT_BROKEN';
  end if;

  v_denied := false;
  begin
    update public.school_accounts
    set current_balance = current_balance - 1
    where id = 'e4100000-0000-4000-8000-000000000100';
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_AUTHENTICATED_ACCOUNT_UPDATE_ACCEPTED';
  end if;

  v_denied := false;
  begin
    insert into public.school_account_transactions (
      id, account_id, business_entity_id, transaction_date, year_month,
      transaction_type, currency, amount, app_type
    ) values (
      'e4100000-0000-4000-8000-000000000499',
      'e4100000-0000-4000-8000-000000000100',
      public.school_primary_business_entity_id(),
      current_date,
      to_char(current_date, 'YYYY-MM'),
      'expense_adjust',
      'JPY',
      -1,
      'school'
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_AUTHENTICATED_TRANSACTION_INSERT_ACCEPTED';
  end if;

  v_denied := false;
  begin
    execute $sql$
      explain delete from public.school_expense_records
      where id = 'e4100000-0000-4000-8000-000000000201'
    $sql$;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_AUTHENTICATED_EXPENSE_DELETE_ACCEPTED';
  end if;
end;
$authenticated_direct_denials$;

reset role;
set local role anon;

do $anon_denials$
declare
  v_denied boolean;
begin
  v_denied := false;
  begin
    perform *
    from public.school_create_expense_record(
      current_date,
      public.school_primary_business_entity_id(),
      'e4100000-0000-4000-8000-000000000100',
      'other',
      'codex-test anon denied',
      'JPY',
      100,
      null,
      'cash',
      true,
      null,
      '待确认',
      null,
      null,
      null,
      'codex-test p0-expense rollback-only'
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_ANON_CREATE_ACCEPTED';
  end if;

  v_denied := false;
  begin
    insert into public.school_expense_records (
      id, expense_date, year_month, expense_category, currency, amount, status, app_type
    ) values (
      'e4100000-0000-4000-8000-000000000498',
      current_date,
      to_char(current_date, 'YYYY-MM'),
      'other',
      'JPY',
      1,
      'pending',
      'school'
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_ANON_TABLE_INSERT_ACCEPTED';
  end if;
end;
$anon_denials$;

reset role;

-- Seed the callback fixture as the database owner. Phase 2 intentionally
-- removes service_role table DML; the callback must mutate only via the
-- SECURITY DEFINER helper under test.
update public.school_expense_records
set cash_request_id = 'e4100000-0000-4000-8000-000000000302',
    cash_request_status = 'pending'
where id = 'e4100000-0000-4000-8000-000000000202';

set local role service_role;

do $service_writer_matrix$
declare
  v_first record;
  v_retry record;
  v_confirm record;
  v_denied boolean;
begin
  select * into v_first
  from public.school_request_cash_expense_payment_confirmation(
    'e4100000-0000-4000-8000-000000000201',
    'e4100000-0000-4000-8000-000000000501',
    'e4100000-0000-4000-8000-000000000502',
    'codex-test Cash account',
    'cash',
    null,
    null,
    'codex-test p0-expense rollback-only',
    null,
    null
  );

  select * into v_retry
  from public.school_request_cash_expense_payment_confirmation(
    'e4100000-0000-4000-8000-000000000201',
    'e4100000-0000-4000-8000-000000000501',
    'e4100000-0000-4000-8000-000000000502',
    'codex-test Cash account',
    'cash',
    null,
    null,
    'codex-test p0-expense rollback-only',
    null,
    null
  );

  if v_first.request_event_id is distinct from v_retry.request_event_id
     or v_first.attempt_no <> 1
     or v_retry.attempt_no <> 1
     or v_first.idempotency_key is distinct from v_retry.idempotency_key then
    raise exception 'P0_EXPENSE_CASH_PREPARE_NOT_IDEMPOTENT';
  end if;

  perform *
  from public.school_mark_cash_expense_request_submitted(
    'e4100000-0000-4000-8000-000000000201',
    'e4100000-0000-4000-8000-000000000301',
    'pending'
  );

  v_denied := false;
  begin
    perform *
    from public.school_mark_cash_expense_request_submitted(
      'e4100000-0000-4000-8000-000000000201',
      'e4100000-0000-4000-8000-000000000301',
      'approved'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_INVALID_SUBMITTED_STATUS_ACCEPTED';
  end if;

  perform *
  from public.school_mark_cash_expense_rejected(
    'e4100000-0000-4000-8000-000000000201',
    'e4100000-0000-4000-8000-000000000301',
    'codex-test rejection',
    now()
  );

  select * into v_confirm
  from public.school_mark_cash_expense_confirmed(
    'e4100000-0000-4000-8000-000000000202',
    'e4100000-0000-4000-8000-000000000302',
    'e4100000-0000-4000-8000-000000000402',
    now()
  );
  perform *
  from public.school_mark_cash_expense_confirmed(
    'e4100000-0000-4000-8000-000000000202',
    'e4100000-0000-4000-8000-000000000302',
    'e4100000-0000-4000-8000-000000000402',
    now()
  );

  if v_confirm.expense_status <> 'paid' then
    raise exception 'P0_EXPENSE_CASH_CONFIRM_RESULT_INVALID';
  end if;

  v_denied := false;
  begin
    perform *
    from public.school_mark_cash_expense_confirmed(
      'e4100000-0000-4000-8000-000000000202',
      'e4100000-0000-4000-8000-000000000302',
      'e4100000-0000-4000-8000-000000000403',
      now()
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_DIFFERENT_TRANSACTION_ACCEPTED';
  end if;

  v_denied := false;
  begin
    perform *
    from public.school_mark_cash_expense_rejected(
      'e4100000-0000-4000-8000-000000000202',
      'e4100000-0000-4000-8000-000000000399',
      'codex-test wrong request',
      now()
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'P0_EXPENSE_WRONG_REQUEST_ACCEPTED';
  end if;
end;
$service_writer_matrix$;

reset role;

do $acl_matrix$
declare
  v_create regprocedure :=
    'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'::regprocedure;
begin
  if has_function_privilege('anon', v_create, 'EXECUTE')
     or not has_function_privilege('authenticated', v_create, 'EXECUTE')
     or has_function_privilege('service_role', v_create, 'EXECUTE') then
    raise exception 'P0_EXPENSE_CREATE_ACL_INVALID';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'public'
      and p.proname in (
        'school_create_expense_record',
        'school_request_cash_expense_payment_confirmation',
        'school_mark_cash_expense_request_submitted',
        'school_mark_cash_expense_confirmed',
        'school_mark_cash_expense_rejected'
      )
      and a.grantee = 0
  ) then
    raise exception 'P0_EXPENSE_PUBLIC_EXECUTE_REMAINS';
  end if;
end;
$acl_matrix$;

select 'P0_EXPENSE_PERMISSION_CLOSURE_ROLLBACK_TEST_PASS' as result;
rollback;
