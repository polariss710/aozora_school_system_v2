-- school_teacher_wage_expense_void_and_regenerate.sql
-- Version: v10.3.9 allow void unsubmitted teacher wage expense
--
-- Purpose:
-- - Allow one unsubmitted teacher_wage expense record to be logically voided
--   before it is submitted to Cash.
-- - Keep historical voided expense records for audit.
-- - Allow the same teacher wage lock to generate a new active expense record
--   after the previous unsubmitted expense was voided.
--
-- Scope:
-- - Adds nullable cancellation audit fields to school_expense_records.
-- - Replaces the teacher_wage source uniqueness rule with active-only
--   uniqueness.
-- - Creates public.school_void_unsubmitted_teacher_wage_expense_record.
-- - Updates public.school_create_teacher_wage_expense_record so cancelled
--   historical rows do not block regeneration.
-- - Does not touch Cash, wage locks, wage details, accounts, account
--   transactions, lessons, student settlements, income, or paid expense reversal.

alter table public.school_expense_records
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_reason text,
  add column if not exists cancelled_by text;

comment on column public.school_expense_records.cancelled_at is
  'Timestamp when a pending School expense record was logically cancelled before any Cash submission. Null for active expense records.';

comment on column public.school_expense_records.cancelled_reason is
  'Optional reason recorded when a pending School expense record is cancelled before any Cash submission.';

comment on column public.school_expense_records.cancelled_by is
  'Operator identity recorded when a pending School expense record is cancelled before any Cash submission.';

drop index if exists public.school_expense_records_teacher_wage_source_uniq;

create unique index if not exists school_expense_records_teacher_wage_source_uniq
  on public.school_expense_records (source_id)
  where source_type = 'teacher_wage'
    and source_id is not null
    and app_type = 'school'
    and cancelled_at is null
    and coalesce(status, '') not in ('cancelled', 'void', 'voided');

create or replace function public.school_void_unsubmitted_teacher_wage_expense_record(
  p_expense_record_id uuid,
  p_void_reason text default null
)
returns table (
  expense_id uuid,
  wage_lock_id uuid,
  status text,
  cancelled_at timestamptz,
  cancelled_reason text,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_reason text := nullif(trim(coalesce(p_void_reason, '')), '');
  v_now timestamptz := now();
begin
  perform public.school_require_current_app_admin();

  if p_expense_record_id is null then
    raise exception '请选择要作废的老师工资支出记录。';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
   for update;

  if not found then
    raise exception '支出记录不存在：%。', p_expense_record_id;
  end if;

  if coalesce(v_expense.app_type, '') <> 'school' then
    raise exception '只能作废 School 支出记录。';
  end if;

  if coalesce(v_expense.source_type, '') <> 'teacher_wage' then
    raise exception '本流程只允许作废老师工资支出记录。';
  end if;

  if coalesce(v_expense.status, '') = 'cancelled'
     or v_expense.cancelled_at is not null then
    raise exception '该老师工资支出记录已经作废，不能重复作废。';
  end if;

  if coalesce(v_expense.status, '') <> 'pending' then
    raise exception '只有待支付且未提交 Cash 的老师工资支出记录可以作废。当前状态：%。', v_expense.status;
  end if;

  if v_expense.cash_request_status is not null then
    raise exception '该支出记录已有 Cash 状态，不能在 School 侧直接作废：%。', v_expense.cash_request_status;
  end if;

  if v_expense.cash_request_id is not null then
    raise exception '该支出记录已关联 Cash request，不能在 School 侧直接作废。';
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception '该支出记录已关联 Cash transaction，不能作废。';
  end if;

  if v_expense.source_id is null then
    raise exception '老师工资支出记录缺少来源工资快照，不能作废。';
  end if;

  update public.school_expense_records e
     set status = 'cancelled',
         cancelled_at = v_now,
         cancelled_reason = v_reason,
         cancelled_by = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.source_id,
    v_expense.status,
    v_expense.cancelled_at,
    v_expense.cancelled_reason,
    v_expense.cash_request_status,
    'Unsubmitted teacher wage expense record cancelled. A new active expense can be generated from the same wage lock.'::text;
end;
$$;

comment on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text) is
  'Logically cancels one pending teacher_wage school_expense_records row before any Cash submission. Rejects non-teacher_wage, paid, Cash-pending, Cash-approved, Cash-rejected, and already-cancelled records.';

revoke all on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  to authenticated;

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
     and e.cancelled_at is null
     and coalesce(e.status, '') not in ('cancelled', 'void', 'voided')
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
  'Creates or returns one active pending teacher_wage school_expense_records row from one locked teacher wage snapshot. Cancelled historical rows do not block regeneration. Does not create Cash requests, Cash transactions, payment requests, account transactions, or account balance changes.';

revoke all on function public.school_create_teacher_wage_expense_record(uuid, date, text)
  from public, anon, authenticated, service_role;

grant execute on function public.school_create_teacher_wage_expense_record(uuid, date, text)
  to authenticated;
