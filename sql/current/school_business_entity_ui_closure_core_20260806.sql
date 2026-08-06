-- School V2 Phase BE-UI: school-wide profit reader and final Profile writer ACL closure.
-- DDL/ACL only. No business row is inserted, updated, deleted, or reinterpreted.

do $preflight$
begin
  if to_regclass('public.school_app_memberships') is null
     or to_regclass('public.school_operational_income_records') is null
     or to_regclass('public.school_expense_records') is null
     or to_regclass('public.school_reimbursements') is null
     or to_regclass('public.school_payment_requests') is null
     or to_regclass('public.school_account_transactions') is null then
    raise exception 'BE_UI_PROFIT_READER_PREFLIGHT_FAILED';
  end if;

  if to_regprocedure('public.school_create_business_entity_profile(jsonb)') is null
     or to_regprocedure('public.school_create_business_entity_profile(text,text,text,text,boolean,text)') is null
     or to_regprocedure('public.school_update_business_entity_profile(uuid,jsonb)') is null
     or to_regprocedure('public.school_update_business_entity_profile(uuid,text,text,text,boolean,text)') is null then
    raise exception 'BE_UI_PROFILE_OVERLOAD_PREFLIGHT_FAILED';
  end if;
end;
$preflight$;

create or replace function public.school_get_profit_summary_schoolwide_v1(
  p_start_month text,
  p_end_month text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='BE_UI_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.school_app_memberships membership
    where membership.user_id=v_actor
      and membership.is_active
      and membership.role in ('admin','operator','read_only')
  ) then
    raise exception using errcode='42501',message='BE_UI_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;

  if p_start_month is null or p_start_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_end_month is null or p_end_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_start_month > p_end_month then
    raise exception using errcode='22023',message='BE_UI_MONTH_RANGE_INVALID';
  end if;

  with
  currencies(currency,sort_order) as (
    values ('JPY'::text,1),('CNY'::text,2)
  ),
  income_base as (
    select i.id,i.income_date,i.income_category,i.description,i.currency,
           i.amount,i.amount_jpy,i.amount_cny,i.status,i.note,i.created_at
    from public.school_operational_income_records i
    where i.app_type='school'
      and i.year_month between p_start_month and p_end_month
      and i.status='received'
      and i.currency in ('JPY','CNY')
  ),
  expense_base as (
    select e.id,e.expense_date,e.expense_category,e.description,e.currency,
           e.amount,e.amount_jpy,e.amount_cny,e.status,e.reimbursement_status,
           e.note,e.created_at
    from public.school_expense_records e
    where e.app_type='school'
      and e.year_month between p_start_month and p_end_month
      and e.status='paid'
      and e.currency in ('JPY','CNY')
  ),
  reimbursement_base as (
    select r.id,r.currency,r.amount,r.status
    from public.school_reimbursements r
    where r.app_type='school'
      and r.year_month between p_start_month and p_end_month
      and r.currency in ('JPY','CNY')
  ),
  payment_request_base as (
    select p.id,p.currency,p.amount,p.amount_jpy,p.amount_cny,p.status,p.source_type
    from public.school_payment_requests p
    where p.request_month between p_start_month and p_end_month
      and p.currency in ('JPY','CNY')
  ),
  transaction_base as (
    select t.id,t.currency,t.amount,t.transaction_type
    from public.school_account_transactions t
    where t.app_type='school'
      and t.year_month between p_start_month and p_end_month
      and t.currency in ('JPY','CNY')
  ),
  summary_rows as (
    select c.currency,c.sort_order,
           (select count(*) from income_base i where i.currency=c.currency) income_count,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(i.amount_jpy,i.amount)
                                                else coalesce(i.amount_cny,i.amount) end)
                     from income_base i where i.currency=c.currency),0) income_amount,
           (select count(*) from expense_base e where e.currency=c.currency) expense_count,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(e.amount_jpy,e.amount)
                                                else coalesce(e.amount_cny,e.amount) end)
                     from expense_base e where e.currency=c.currency),0) expense_amount,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(e.amount_jpy,e.amount)
                                                else coalesce(e.amount_cny,e.amount) end)
                     from expense_base e
                     where e.currency=c.currency and e.expense_category='teacher_wage'),0) teacher_wage_amount
    from currencies c
  ),
  audit_source(sort_order,name,profit_policy,record_count,jpy_amount,cny_amount,note) as (
    select 1,'报销记录','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '原始支出已计入支出；这里只观察资金报销流。'
    from reimbursement_base where status='paid'
    union all
    select 2,'报销撤销','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '撤销改变账户资金流，不重算经营利润。'
    from reimbursement_base where status='reversed'
    union all
    select 3,'老师工资支付请求','不重复计入利润',count(*),
           coalesce(sum(case when currency='JPY' then coalesce(amount_jpy,amount) else 0 end),0),
           coalesce(sum(case when currency='CNY' then coalesce(amount_cny,amount) else 0 end),0),
           '工资通过 teacher_wage 支出计入；支付请求只做状态参考。'
    from payment_request_base where source_type='teacher_wage' and status='paid'
    union all
    select 4,'老师工资支付撤销','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then coalesce(amount_jpy,amount) else 0 end),0),
           coalesce(sum(case when currency='CNY' then coalesce(amount_cny,amount) else 0 end),0),
           '撤销支付是资金流和状态变化，不直接进入利润。'
    from payment_request_base where source_type='teacher_wage' and status='reversed'
    union all
    select 5,'账户调整流水','不计入经营利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '余额校正单列展示，不混入经营利润。'
    from transaction_base where transaction_type in ('account_adjustment','account_adjustment_reversal')
    union all
    select 6,'账户转账/调拨流水','不计入经营利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '账户间资金移动只做审计。'
    from transaction_base where transaction_type in ('transfer_out','transfer_in','transfer_reverse_in','transfer_reverse_out')
    union all
    select 7,'其他账户流水','仅参考',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '用于观察业务流水；利润以收入和支出事实表为准。'
    from transaction_base
    where transaction_type not in (
      'account_adjustment','account_adjustment_reversal','transfer_out','transfer_in',
      'transfer_reverse_in','transfer_reverse_out'
    )
  )
  select jsonb_build_object(
    'start_month',p_start_month,
    'end_month',p_end_month,
    'summary_rows',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'currency',s.currency,
        'income_count',s.income_count,
        'income_amount',s.income_amount,
        'expense_count',s.expense_count,
        'expense_amount',s.expense_amount,
        'teacher_wage_amount',s.teacher_wage_amount,
        'profit_amount',s.income_amount-s.expense_amount
      ) order by s.sort_order),'[]'::jsonb) from summary_rows s
    ),
    'audit_rows',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'name',a.name,'profit_policy',a.profit_policy,'record_count',a.record_count,
        'jpy_amount',a.jpy_amount,'cny_amount',a.cny_amount,'note',a.note
      ) order by a.sort_order),'[]'::jsonb) from audit_source a
    ),
    'income_records',(
      select coalesce(jsonb_agg(to_jsonb(i) - 'created_at' order by i.income_date desc,i.created_at desc,i.id),'[]'::jsonb)
      from income_base i
    ),
    'expense_records',(
      select coalesce(jsonb_agg(to_jsonb(e) - 'created_at' order by e.expense_date desc,e.created_at desc,e.id),'[]'::jsonb)
      from expense_base e
    )
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.school_get_profit_summary_schoolwide_v1(text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_profit_summary_schoolwide_v1(text,text)
  to authenticated;

revoke all on function public.school_create_business_entity_profile(text,text,text,text,boolean,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_business_entity_profile(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_business_entity_profile(uuid,text,text,text,boolean,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_business_entity_profile(uuid,jsonb)
  from public,anon,authenticated,service_role;

comment on function public.school_get_profit_summary_schoolwide_v1(text,text) is
  'School-wide read-only profit authority. Aggregates all existing business scopes by original currency without changing historical attribution or mixing JPY and CNY.';
comment on function public.school_create_business_entity_profile(jsonb) is
  'Owner-only business-entity Profile writer. No interactive or service-role EXECUTE grant remains after Phase BE-UI.';
comment on function public.school_update_business_entity_profile(uuid,jsonb) is
  'Owner-only business-entity Profile writer. No interactive or service-role EXECUTE grant remains after Phase BE-UI.';
