-- school_create_reimbursement_record_rpc.sql
-- RPC: public.school_create_reimbursement_record
-- Purpose: Create a paid reimbursement record with reimbursement items,
--          two account transactions, account balance updates, and expense
--          reimbursement status updates.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Verified: v2.23.6-reimbursement-create-rpc-commit-test-20260604
-- Version: v2.23.2-reimbursement-create-rpc-sql-draft-20260604
--
-- Scope:
-- - Create one paid reimbursement for selected pending paid expense records.
-- - Supports multiple selected expenses in one reimbursement.
-- - Deduct from_account current_balance and add to_account current_balance.
-- - Insert one reimbursement_out and one reimbursement_in account transaction.
-- - Mark selected expenses as reimbursement_status = 'paid'.
-- - Run all operations in one DB transaction.
--
-- Not supported in this first version:
-- - Reimbursement edit/delete/reverse/void.
-- - Partial reimbursement.
-- - Cross-currency reimbursement.
-- - Manual amount or currency override from frontend.
-- - Attachment/OCR flow.
-- - Statistics or profit calculation.
-- - teacher_wage reimbursement.
-- - Inferring reimbursements from account transactions.
-- - Fixing historical orphan reimbursement account transactions.
--
-- Review before execution:
-- - Confirm actual table columns and enum/status values.
-- - Confirm school_business_entities intentionally has no app_type column.
-- - Confirm RLS / grant policy.
-- - Confirm negative account balance policy.
-- - Confirm transaction_type values reimbursement_out / reimbursement_in.
-- - Confirm whether expense reimbursement_note should remain unchanged.

create or replace function public.school_create_reimbursement_record(
  p_reimbursement_date date,
  p_business_entity_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_expense_ids uuid[],
  p_note text default null
)
returns table (
  reimbursement_id uuid,
  from_account_transaction_id uuid,
  to_account_transaction_id uuid,
  from_account_id uuid,
  to_account_id uuid,
  from_account_new_balance numeric,
  to_account_new_balance numeric,
  amount numeric,
  currency text,
  year_month text,
  item_count integer,
  status text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_now timestamptz := now();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_expense_ids uuid[];
  v_input_count integer;
  v_unique_count integer;
  v_null_id_count integer;
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_expense_count integer;
  v_bad_app_type_count integer;
  v_bad_status_count integer;
  v_bad_reimbursement_status_count integer;
  v_teacher_wage_count integer;
  v_bad_business_entity_count integer;
  v_distinct_currency_count integer;
  v_used_reimbursement_item_count integer;
  v_total_amount numeric;
  v_currency text;
  v_reimbursement_id uuid;
  v_from_account_transaction_id uuid;
  v_to_account_transaction_id uuid;
  v_from_account_new_balance numeric;
  v_to_account_new_balance numeric;
begin
  perform public.school_require_current_app_admin();

  if p_reimbursement_date is null then
    raise exception '请选择报销日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_from_account_id is null or p_to_account_id is null then
    raise exception '请选择出金账户和入金账户。';
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception '出金账户和入金账户不能相同。';
  end if;

  if coalesce(cardinality(p_expense_ids), 0) = 0 then
    raise exception '请选择要报销的支出。';
  end if;

  select
    array_agg(input.expense_id order by input.expense_id),
    count(*)::integer,
    count(distinct input.expense_id)::integer,
    count(*) filter (where input.expense_id is null)::integer
  into
    v_expense_ids,
    v_input_count,
    v_unique_count,
    v_null_id_count
  from unnest(p_expense_ids) as input(expense_id);

  if v_null_id_count > 0 then
    raise exception '请选择要报销的支出。';
  end if;

  if v_input_count <> v_unique_count then
    raise exception '报销支出列表包含重复项目。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities be
  where be.id = p_business_entity_id
    and be.is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[p_from_account_id, p_to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = p_from_account_id then
      v_from_account := v_account;
    elsif v_account.id = p_to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '报销账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school' then
    raise exception '报销账户不存在或不可用。';
  end if;

  if v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '报销账户已停用。';
  end if;

  if v_from_account.business_entity_id is distinct from p_business_entity_id
    or v_to_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '报销账户必须属于同一业务归属。';
  end if;

  if v_from_account.currency is distinct from v_to_account.currency then
    raise exception '出金账户和入金账户币种必须一致。';
  end if;

  with locked_expenses as (
    select *
    from public.school_expense_records e
    where e.id = any (v_expense_ids)
    order by e.id
    for update
  )
  select
    count(*)::integer,
    count(*) filter (where coalesce(locked_expenses.app_type, '') <> 'school')::integer,
    count(*) filter (where locked_expenses.status is distinct from 'paid')::integer,
    count(*) filter (where locked_expenses.reimbursement_status is distinct from 'pending')::integer,
    count(*) filter (where locked_expenses.expense_category = 'teacher_wage')::integer,
    count(*) filter (where locked_expenses.business_entity_id is distinct from p_business_entity_id)::integer,
    count(distinct coalesce(locked_expenses.currency, ''))::integer,
    sum(coalesce(locked_expenses.amount, 0))::numeric,
    min(locked_expenses.currency)
  into
    v_expense_count,
    v_bad_app_type_count,
    v_bad_status_count,
    v_bad_reimbursement_status_count,
    v_teacher_wage_count,
    v_bad_business_entity_count,
    v_distinct_currency_count,
    v_total_amount,
    v_currency
  from locked_expenses;

  if v_expense_count <> v_unique_count then
    raise exception '支出不存在或数量不一致。';
  end if;

  if v_bad_app_type_count > 0 then
    raise exception '支出不存在或数量不一致。';
  end if;

  if v_bad_status_count > 0 then
    raise exception '只能报销已支付支出。';
  end if;

  if v_bad_reimbursement_status_count > 0 then
    raise exception '只能报销待报销支出。';
  end if;

  if v_teacher_wage_count > 0 then
    raise exception '老师工资支出不能通过报销流程处理。';
  end if;

  if v_bad_business_entity_count > 0 then
    raise exception '支出业务归属不一致。';
  end if;

  if v_distinct_currency_count <> 1 then
    raise exception '支出币种不一致。';
  end if;

  if v_from_account.currency is distinct from v_currency then
    raise exception '账户币种与支出币种不一致。';
  end if;

  if coalesce(v_total_amount, 0) <= 0 then
    raise exception '报销金额必须大于 0。';
  end if;

  select count(*)::integer
  into v_used_reimbursement_item_count
  from public.school_reimbursement_items ri
  where ri.expense_id = any (v_expense_ids);

  if v_used_reimbursement_item_count > 0 then
    raise exception '支出已关联其他报销记录。';
  end if;

  v_year_month := to_char(p_reimbursement_date, 'YYYY-MM');
  v_from_account_new_balance := coalesce(v_from_account.current_balance, 0) - v_total_amount;
  v_to_account_new_balance := coalesce(v_to_account.current_balance, 0) + v_total_amount;

  insert into public.school_reimbursements (
    reimbursement_date,
    year_month,
    business_entity_id,
    from_account_id,
    to_account_id,
    amount,
    currency,
    status,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_reimbursement_date,
    v_year_month,
    p_business_entity_id,
    p_from_account_id,
    p_to_account_id,
    v_total_amount,
    v_currency,
    'paid',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_reimbursement_id;

  insert into public.school_reimbursement_items (
    reimbursement_id,
    expense_id,
    amount,
    note,
    app_type,
    created_at,
    updated_at
  )
  select
    v_reimbursement_id,
    e.id,
    e.amount,
    nullif(trim(coalesce(e.description, '')), ''),
    'school',
    v_now,
    v_now
  from public.school_expense_records e
  where e.id = any (v_expense_ids)
  order by e.id;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = p_from_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_from_account_id,
    p_business_entity_id,
    p_reimbursement_date,
    v_year_month,
    'reimbursement_out',
    'school_reimbursements',
    v_reimbursement_id,
    v_currency,
    -v_total_amount,
    v_from_account_new_balance,
    '报销出金',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_from_account_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = p_to_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_to_account_id,
    p_business_entity_id,
    p_reimbursement_date,
    v_year_month,
    'reimbursement_in',
    'school_reimbursements',
    v_reimbursement_id,
    v_currency,
    v_total_amount,
    v_to_account_new_balance,
    '报销入金',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_to_account_transaction_id;

  update public.school_expense_records e
  set
    reimbursement_status = 'paid',
    updated_at = v_now
  where e.id = any (v_expense_ids);

  return query
  select
    v_reimbursement_id,
    v_from_account_transaction_id,
    v_to_account_transaction_id,
    p_from_account_id,
    p_to_account_id,
    v_from_account_new_balance,
    v_to_account_new_balance,
    v_total_amount,
    v_currency,
    v_year_month,
    v_unique_count,
    'paid'::text;
end;
$$;

comment on function public.school_create_reimbursement_record(
  date,
  uuid,
  uuid,
  uuid,
  uuid[],
  text
) is
  'Active-admin v2 reimbursement creation: creates paid reimbursement, items, two account transactions, account balance updates, and marks selected expenses reimbursed.';

revoke all on function public.school_create_reimbursement_record(date,uuid,uuid,uuid,uuid[],text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_create_reimbursement_record(date,uuid,uuid,uuid,uuid[],text)
  to authenticated;

-- Reference call example with placeholder IDs only. Do not run as-is.
--
-- select *
-- from public.school_create_reimbursement_record(
--   p_reimbursement_date := date '2026-06-04',
--   p_business_entity_id := '00000000-0000-0000-0000-000000000000',
--   p_from_account_id := '00000000-0000-0000-0000-000000000000',
--   p_to_account_id := '00000000-0000-0000-0000-000000000000',
--   p_expense_ids := array[
--     '00000000-0000-0000-0000-000000000001'::uuid,
--     '00000000-0000-0000-0000-000000000002'::uuid
--   ],
--   p_note := '报销确认'
-- );
