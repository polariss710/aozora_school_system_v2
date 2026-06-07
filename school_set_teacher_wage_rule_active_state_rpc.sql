-- school_set_teacher_wage_rule_active_state_rpc.sql
-- RPC: public.school_set_teacher_wage_rule_active_state
-- Purpose: Soft-disable or restore future-use teacher wage rule matching.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.52.0-wage-rule-soft-disable-restore-full-autopilot-20260607
--
-- Scope:
-- - Update one row in public.school_teacher_wage_rules.
-- - Allowed fields: is_active, note, updated_at.
-- - Restoring to active checks for another active rule with the same
--   teacher/student/subject/business-entity match.
-- - This function affects only future wage rule matching.
--
-- Not supported:
-- - Physical delete.
-- - Archive table or destructive cleanup.
-- - Editing matching keys, settlement type, rates, exchange rate, or fees.
-- - Recalculating, repairing, voiding, or rewriting historical wage locks,
--   wage lock details, payment requests, expenses, accounts, or account
--   transactions.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test soft-disabled whitelisted codex-test wage rule
--   8ca3d67d-886a-41b0-b480-a60264219435 and left no residue.
-- - Commit test soft-disabled and restored the same whitelisted codex-test rule.
-- - Final commit-test state: is_active = true, note =
--   codex-test / v2-test / sandbox / v2.52.0 commit restore wage rule.
-- - Matching keys, settlement type, rates, exchange rate, fees, wage locks,
--   wage lock details, payment requests, expenses, and account transactions
--   stayed unchanged.

create or replace function public.school_set_teacher_wage_rule_active_state(
  p_wage_rule_id uuid,
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
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_wage_rule_id is null then
    raise exception '请选择老师工资规则。';
  end if;

  if p_is_active is null then
    raise exception '请选择要设置的启用状态。';
  end if;

  select r.*
  into v_rule
  from public.school_teacher_wage_rules r
  where r.id = p_wage_rule_id
  for update;

  if not found then
    raise exception '老师工资规则不存在。';
  end if;

  if v_rule.is_active is not distinct from p_is_active then
    raise exception '老师工资规则已经是%状态。', case when p_is_active then '启用' else '停用' end;
  end if;

  if p_is_active is true and exists (
    select 1
    from public.school_teacher_wage_rules r
    where r.id <> v_rule.id
      and r.teacher_id is not distinct from v_rule.teacher_id
      and r.student_id is not distinct from v_rule.student_id
      and r.subject_id is not distinct from v_rule.subject_id
      and r.business_entity_id is not distinct from v_rule.business_entity_id
      and coalesce(r.is_active, true) = true
  ) then
    raise exception '相同老师、学生、科目和业务归属的启用工资规则已存在，不能恢复该规则。';
  end if;

  update public.school_teacher_wage_rules r
  set
    is_active = p_is_active,
    note = coalesce(v_note, r.note),
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

comment on function public.school_set_teacher_wage_rule_active_state(
  uuid,
  boolean,
  text
) is
  'Soft-disables or restores one teacher wage rule for future matching only. Does not delete rules or modify historical wage/payment/expense/account data.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
