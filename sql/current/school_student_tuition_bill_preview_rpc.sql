-- school_student_tuition_bill_preview_rpc.sql
-- Purpose:
-- - Read-only preview for student tuition bill generation.
-- - Mirrors the DB/RPC authoritative tuition bill calculation without creating
--   or updating tuition bills, income records, Cash requests, settlements,
--   lessons, account transactions, or balances.

create or replace function public.school_preview_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
returns table (
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,
  existing_income_record_id uuid,
  existing_income_status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student public.school_students%rowtype;
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
  v_billing_exchange_rate numeric := p_billing_exchange_rate;
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%rowtype;
  v_existing public.school_student_tuition_bills%rowtype;
  v_existing_income public.school_income_records%rowtype;
  v_planned_count integer;
  v_planned_hours numeric;
  v_planned_fee_jpy numeric;
  v_previous_carryover_cny numeric;
  v_billing_amount_cny numeric;
  v_existing_found boolean := false;
  v_existing_income_status text := null;
  v_message text := 'tuition bill preview';
begin
  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_billing_month is null or v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '学费月份格式无效，请使用 YYYY-MM。';
  end if;

  if v_billing_exchange_rate is null or v_billing_exchange_rate <= 0 then
    raise exception '通知汇率必须大于 0。';
  end if;

  select *
    into v_student
    from public.school_students s
   where s.id = p_student_id
     and s.app_type = 'school';

  if not found then
    raise exception '学生无效或不属于 School。';
  end if;

  if coalesce(v_student.status, '') in ('inactive', 'disabled', 'archived') then
    raise exception '学生已停用，不能生成学费应收。';
  end if;

  if v_student.business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能生成学费应收。';
  end if;

  if exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = v_student.business_entity_id
       and s.year_month = v_billing_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成新的学费应收。';
  end if;

  v_previous_month := to_char(
    (to_date(v_billing_month || '-01', 'YYYY-MM-DD') - interval '1 month')::date,
    'YYYY-MM'
  );

  select *
    into v_previous_settlement
    from public.school_student_monthly_settlements s
   where s.student_id = p_student_id
     and s.business_entity_id = v_student.business_entity_id
     and s.year_month = v_previous_month
     and s.settlement_status = 'locked'
   order by s.locked_at desc nulls last, s.updated_at desc nulls last, s.created_at desc nulls last
   limit 1;

  select
    count(*)::integer,
    coalesce(sum(coalesce(l.duration_hours, 0)), 0)::numeric,
    coalesce(sum(coalesce(l.lesson_fee, coalesce(l.unit_price, 0) * coalesce(l.duration_hours, 0), 0)), 0)::numeric
  into
    v_planned_count,
    v_planned_hours,
    v_planned_fee_jpy
  from public.school_lesson_records l
  where l.app_type = 'school'
    and l.student_id = p_student_id
    and l.business_entity_id = v_student.business_entity_id
    and l.year_month = v_billing_month
    and l.lesson_type = 'planned'
    and l.voided_at is null
    and coalesce(l.status, '') not in ('cancelled', 'voided', 'void');

  if coalesce(v_planned_count, 0) <= 0 then
    raise exception '该学生月份没有可生成学费应收的正式预定课时。';
  end if;

  if coalesce(v_planned_fee_jpy, 0) <= 0 then
    raise exception '该学生月份预定课时费为 0，不能生成学费应收。';
  end if;

  v_previous_carryover_cny := round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2);
  v_billing_amount_cny := round(v_planned_fee_jpy * v_billing_exchange_rate + v_previous_carryover_cny, 2);

  if v_billing_amount_cny <= 0 then
    raise exception '通知金额计算失败。';
  end if;

  select *
    into v_existing
    from public.school_student_tuition_bills b
   where b.student_id = p_student_id
     and b.business_entity_id = v_student.business_entity_id
     and b.billing_month = v_billing_month
     and b.status in ('draft', 'income_created')
   order by b.updated_at desc nulls last, b.created_at desc nulls last
   limit 1;

  v_existing_found := found;

  if v_existing_found and v_existing.status = 'income_created' then
    select *
      into v_existing_income
      from public.school_income_records i
     where i.id = v_existing.income_record_id
       and i.app_type = 'school';

    if found then
      v_existing_income_status := v_existing_income.status;
    end if;

    if not found or (v_existing_income.status <> 'cancelled' and v_existing_income.cancelled_at is null) then
      raise exception '该学生月份已生成收入记录，不能重复生成学费应收。';
    end if;

    v_message := 'existing income-created tuition bill has cancelled income; regenerate is allowed';
  elsif v_existing_found and v_existing.status = 'draft' then
    v_message := 'existing draft tuition bill will be recalculated';
  end if;

  return query
  select
    v_student.id,
    v_student.business_entity_id,
    v_billing_month,
    v_previous_month,
    v_previous_settlement.id,
    v_previous_carryover_cny,
    v_planned_count,
    v_planned_hours,
    v_planned_fee_jpy,
    v_planned_fee_jpy,
    'JPY'::text,
    v_billing_exchange_rate,
    v_billing_amount_cny,
    'CNY'::text,
    case when v_existing_found then v_existing.id else null end,
    case when v_existing_found then v_existing.status else null end,
    case when v_existing_found then v_existing.income_record_id else null end,
    v_existing_income_status,
    v_message;
end;
$$;

comment on function public.school_preview_student_tuition_bill(uuid, text, numeric) is
  'Read-only preview for student tuition bill generation. Calculates planned JPY tuition, previous locked CNY carryover, and CNY notification amount from the operator-entered exchange rate without writing tuition bills, income records, Cash requests, settlements, lessons, account transactions, or balances.';

revoke all on function public.school_preview_student_tuition_bill(uuid, text, numeric)
  from public, anon, authenticated;

grant execute on function public.school_preview_student_tuition_bill(uuid, text, numeric)
  to authenticated, service_role;
