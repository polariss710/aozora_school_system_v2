-- School V2 active-admin creation of one manual Cash pending expense.
-- Status: reviewed source; deploy only through the phase deployment wrapper.

create or replace function public.school_create_pending_cash_expense_record_v1(
  p_client_request_id uuid,
  p_expense_date date,
  p_business_entity_id uuid,
  p_expense_category text,
  p_description text,
  p_currency text,
  p_amount numeric,
  p_reimbursement_status text,
  p_exchange_rate numeric default null,
  p_is_business_expense boolean default true,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_teacher_id uuid default null,
  p_student_id uuid default null,
  p_note text default null
)
returns table (
  expense_record jsonb,
  expense_id uuid,
  expense_status text,
  cash_request_status text,
  client_request_id uuid,
  created_by_user_id uuid,
  creation_channel text,
  idempotent boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_expense public.school_expense_records%rowtype;
  v_currency text := upper(trim(coalesce(p_currency,'')));
  v_category text := lower(trim(coalesce(p_expense_category,'')));
  v_description text := nullif(trim(coalesce(p_description,'')),'');
  v_tax_category text := nullif(trim(coalesce(p_tax_category,'')),'');
  v_receipt_status text := coalesce(nullif(trim(coalesce(p_receipt_status,'')),''),'待确认');
  v_reimbursement_status text := nullif(trim(coalesce(p_reimbursement_status,'')),'');
  v_note text := nullif(trim(coalesce(p_note,'')),'');
  v_is_business_expense boolean := coalesce(p_is_business_expense,true);
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
begin
  v_actor := public.school_require_current_app_admin();

  if p_client_request_id is null then
    raise exception using
      errcode='22023',
      message='P0_PENDING_CASH_EXPENSE_CLIENT_REQUEST_ID_REQUIRED';
  end if;
  if p_expense_date is null then
    raise exception '请选择支出日期。';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception '支出金额必须大于 0。';
  end if;
  if v_description is null then
    raise exception '支出内容不能为空。';
  end if;
  if v_category='teacher_wage' then
    raise exception '老师工资支出请通过老师工资支付流程生成。';
  end if;
  if v_category not in ('classroom','other','tax_accounting','advertising','software') then
    raise exception '暂不支持该支出分类。';
  end if;
  if v_currency not in ('JPY','CNY') then
    raise exception '暂不支持该支出币种：%。',v_currency;
  end if;
  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;
  if v_receipt_status not in ('有','无需收据','待确认') then
    raise exception '收据状态无效。';
  end if;
  if v_reimbursement_status not in ('not_required','pending') then
    raise exception '报销状态无效。';
  end if;

  if v_currency='JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case when p_exchange_rate is null then null else p_amount/p_exchange_rate end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case when p_exchange_rate is null then null else p_amount*p_exchange_rate end;
  end if;
  v_year_month := to_char(p_expense_date,'YYYY-MM');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'school_create_pending_cash_expense_record_v1:'||p_client_request_id::text,
      0
    )
  );

  select e.*
    into v_expense
    from public.school_expense_records e
   where e.cash_creation_event_id=p_client_request_id
   for update;

  if found then
    if v_expense.app_type is distinct from 'school'
       or v_expense.source_type is distinct from 'manual_cash'
       or v_expense.source_id is not null
       or v_expense.created_by_user_id is null
       or v_expense.expense_date is distinct from p_expense_date
       or v_expense.year_month is distinct from v_year_month
       or v_expense.business_entity_id is distinct from p_business_entity_id
       or v_expense.expense_category is distinct from v_category
       or v_expense.description is distinct from v_description
       or v_expense.currency is distinct from v_currency
       or v_expense.amount is distinct from p_amount
       or v_expense.amount_jpy is distinct from v_amount_jpy
       or v_expense.amount_cny is distinct from v_amount_cny
       or v_expense.exchange_rate is distinct from p_exchange_rate
       or v_expense.account_id is not null
       or v_expense.payment_method is not null
       or v_expense.is_business_expense is distinct from v_is_business_expense
       or v_expense.tax_category is distinct from v_tax_category
       or v_expense.receipt_status is distinct from v_receipt_status
       or v_expense.reimbursement_status is distinct from v_reimbursement_status
       or v_expense.teacher_id is distinct from p_teacher_id
       or v_expense.student_id is distinct from p_student_id
       or v_expense.note is distinct from v_note then
      raise exception using
        errcode='23505',
        message='P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT';
    end if;

    return query select
      to_jsonb(v_expense),v_expense.id,v_expense.status,
      v_expense.cash_request_status,v_expense.cash_creation_event_id,
      v_expense.created_by_user_id,v_expense.source_type,true;
    return;
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增Cash待审批支出'
  );

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id=p_business_entity_id and b.is_active=true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;
  if p_teacher_id is not null and not exists (
    select 1 from public.school_teachers t
    where t.id=p_teacher_id and t.app_type='school'
  ) then
    raise exception '老师无效或不可用。';
  end if;
  if p_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_student_id and s.app_type='school'
  ) then
    raise exception '学生无效或不可用。';
  end if;

  insert into public.school_expense_records (
    business_entity_id,teacher_id,student_id,salary_payment_id,account_id,
    expense_date,year_month,expense_category,description,currency,amount,
    amount_jpy,amount_cny,exchange_rate,payment_method,status,
    is_business_expense,tax_category,receipt_status,reimbursement_status,
    reimbursement_note,note,app_type,source_type,source_id,
    cash_creation_event_id,created_by_user_id,
    cash_request_id,cash_request_status,cash_transaction_id,cash_requested_at,
    cash_synced_at,cash_error_message,cash_request_event_id,
    cash_request_attempt_no,cash_payment_amount,cash_payment_currency,
    cash_payment_note,created_at,updated_at
  ) values (
    p_business_entity_id,p_teacher_id,p_student_id,null,null,
    p_expense_date,v_year_month,v_category,v_description,v_currency,p_amount,
    v_amount_jpy,v_amount_cny,p_exchange_rate,null,'pending',
    v_is_business_expense,v_tax_category,v_receipt_status,v_reimbursement_status,
    null,v_note,'school','manual_cash',null,
    p_client_request_id,v_actor,
    null,null,null,null,
    null,null,null,
    0,null,null,
    null,v_now,v_now
  )
  returning * into v_expense;

  return query select
    to_jsonb(v_expense),v_expense.id,v_expense.status,
    v_expense.cash_request_status,v_expense.cash_creation_event_id,
    v_expense.created_by_user_id,v_expense.source_type,false;
end;
$function$;

comment on function public.school_create_pending_cash_expense_record_v1(
  uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text
) is
  'Active-admin-only idempotent writer for one manual Cash pending expense. It writes no School account balance, School account transaction, Cash request, or Cash transaction.';

revoke all on function public.school_create_pending_cash_expense_record_v1(
  uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_pending_cash_expense_record_v1(
  uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text
) to authenticated;
