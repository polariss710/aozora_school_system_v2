-- school_update_teacher_wage_rule_config_rpc.sql
-- RPC: public.school_update_teacher_wage_rule_config
-- Purpose: Update future teacher wage rule configuration fields only.
-- Status: DRAFT. Execute only after static review.
-- Version: v2.42.0-wage-rule-config-edit-20260606
--
-- Scope:
-- - Update one row in public.school_teacher_wage_rules.
-- - Allowed fields: settlement_type, hourly_rate_jpy, hourly_rate_cny,
--   exchange_rate, transport_fee_jpy, classroom_fee_jpy, is_active, note.
-- - Preserve teacher_id, student_id, subject_id, business_entity_id, created_at,
--   wage locks, wage lock details, payment requests, expenses, accounts, and
--   account transactions.
-- - This function affects only future wage locking that reads the rule config.
--
-- Not supported:
-- - Editing rule matching keys.
-- - Creating, deleting, merging, or reassigning rules.
-- - Recalculating, repairing, voiding, or rewriting historical wages.

create or replace function public.school_update_teacher_wage_rule_config(
  p_wage_rule_id uuid,
  p_settlement_type text,
  p_hourly_rate_jpy numeric,
  p_hourly_rate_cny numeric,
  p_exchange_rate numeric,
  p_transport_fee_jpy numeric,
  p_classroom_fee_jpy numeric,
  p_is_active boolean,
  p_note text default null
)
returns table (
  wage_rule_id uuid,
  teacher_id uuid,
  student_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  settlement_type text,
  hourly_rate_jpy numeric,
  hourly_rate_cny numeric,
  exchange_rate numeric,
  transport_fee_jpy numeric,
  classroom_fee_jpy numeric,
  is_active boolean,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_rule public.school_teacher_wage_rules%rowtype;
  v_settlement_type text := nullif(trim(coalesce(p_settlement_type, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_wage_rule_id is null then
    raise exception '请选择要编辑的老师工资规则。';
  end if;

  if v_settlement_type is null then
    raise exception '请选择结算类型。';
  end if;

  if v_settlement_type not in ('jpy_hourly', 'no_wage') then
    raise exception '结算类型无效：%。', v_settlement_type;
  end if;

  if p_is_active is null then
    raise exception '请选择启用状态。';
  end if;

  if p_hourly_rate_jpy is null
    or p_hourly_rate_cny is null
    or p_exchange_rate is null
    or p_transport_fee_jpy is null
    or p_classroom_fee_jpy is null then
    raise exception '费率、汇率和费用不能为空。';
  end if;

  if p_hourly_rate_jpy < 0
    or p_hourly_rate_cny < 0
    or p_exchange_rate < 0
    or p_transport_fee_jpy < 0
    or p_classroom_fee_jpy < 0 then
    raise exception '费率、汇率和费用不能为负数。';
  end if;

  if v_settlement_type = 'no_wage'
    and (
      p_hourly_rate_jpy <> 0
      or p_hourly_rate_cny <> 0
      or p_exchange_rate <> 0
      or p_transport_fee_jpy <> 0
      or p_classroom_fee_jpy <> 0
    ) then
    raise exception '无工资规则的费率、汇率和费用必须全部为 0。';
  end if;

  select *
  into v_rule
  from public.school_teacher_wage_rules r
  where r.id = p_wage_rule_id
  for update;

  if not found then
    raise exception '老师工资规则不存在。';
  end if;

  update public.school_teacher_wage_rules r
  set
    settlement_type = v_settlement_type,
    hourly_rate_jpy = p_hourly_rate_jpy,
    hourly_rate_cny = p_hourly_rate_cny,
    exchange_rate = p_exchange_rate,
    transport_fee_jpy = p_transport_fee_jpy,
    classroom_fee_jpy = p_classroom_fee_jpy,
    is_active = p_is_active,
    note = v_note,
    updated_at = v_now
  where r.id = v_rule.id;

  return query
  select
    r.id,
    r.teacher_id,
    r.student_id,
    r.subject_id,
    r.business_entity_id,
    r.settlement_type,
    r.hourly_rate_jpy,
    r.hourly_rate_cny,
    r.exchange_rate,
    r.transport_fee_jpy,
    r.classroom_fee_jpy,
    r.is_active,
    r.note,
    r.created_at,
    r.updated_at
  from public.school_teacher_wage_rules r
  where r.id = v_rule.id;
end;
$$;

comment on function public.school_update_teacher_wage_rule_config(
  uuid,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  text
) is
  'Updates only future teacher wage rule configuration fields; does not edit matching keys or historical wage/payment/account data.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
