-- school_create_teacher_wage_rule_config_rpc.sql
-- RPC: public.school_create_teacher_wage_rule_config
-- Purpose: Create future-use teacher wage rule configuration only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.49.0-wage-rule-create-full-autopilot-20260607
--
-- Scope:
-- - Insert one row into public.school_teacher_wage_rules.
-- - Allowed fields: teacher_id, student_id, subject_id, business_entity_id,
--   settlement_type, hourly_rate_jpy, hourly_rate_cny, exchange_rate,
--   transport_fee_jpy, classroom_fee_jpy, is_active, note.
-- - This function affects only future wage locking that reads the rule config.
--
-- Not supported:
-- - Creating generic rules without a student_id in this first version.
-- - Editing, recalculating, repairing, voiding, or rewriting historical wage
--   locks, wage lock details, payment requests, expenses, accounts, or account
--   transactions.
-- - Deleting, merging, or replacing wage rules.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test inserted one codex-test wage rule and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox wage
--   rule.
-- - Duplicate active teacher/student/subject/business-entity match is rejected.
-- - Wage lock, wage detail, payment, expense, and account transaction counts
--   stayed unchanged.

create or replace function public.school_create_teacher_wage_rule_config(
  p_teacher_id uuid,
  p_student_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_settlement_type text default 'jpy_hourly',
  p_hourly_rate_jpy numeric default 0,
  p_hourly_rate_cny numeric default 0,
  p_exchange_rate numeric default 0,
  p_transport_fee_jpy numeric default 0,
  p_classroom_fee_jpy numeric default 0,
  p_is_active boolean default true,
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
  v_settlement_type text := nullif(trim(coalesce(p_settlement_type, 'jpy_hourly')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_wage_rule_id uuid;
begin
  if p_teacher_id is null then
    raise exception '请选择老师。';
  end if;

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if p_subject_id is null then
    raise exception '请选择科目。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if not exists (
    select 1
    from public.school_teachers t
    where t.id = p_teacher_id
      and coalesce(t.app_type, '') = 'school'
      and coalesce(t.status, '') not in ('inactive', 'resigned', 'retired')
  ) then
    raise exception '老师不存在或不可用于新增工资规则。';
  end if;

  if not exists (
    select 1
    from public.school_students s
    where s.id = p_student_id
      and coalesce(s.app_type, '') = 'school'
      and coalesce(s.status, '') not in ('inactive', 'graduated', 'withdrawn')
  ) then
    raise exception '学生不存在或不可用于新增工资规则。';
  end if;

  if not exists (
    select 1
    from public.school_subjects s
    where s.id = p_subject_id
      and coalesce(s.is_active, true) = true
  ) then
    raise exception '科目不存在或已停用。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = p_business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属不存在或已停用。';
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

  if p_is_active = true and exists (
    select 1
    from public.school_teacher_wage_rules r
    where r.teacher_id = p_teacher_id
      and r.student_id = p_student_id
      and r.subject_id = p_subject_id
      and r.business_entity_id = p_business_entity_id
      and coalesce(r.is_active, true) = true
  ) then
    raise exception '相同老师、学生、科目和业务归属的启用工资规则已存在。';
  end if;

  insert into public.school_teacher_wage_rules (
    teacher_id,
    student_id,
    subject_id,
    business_entity_id,
    settlement_type,
    hourly_rate_jpy,
    hourly_rate_cny,
    exchange_rate,
    transport_fee_jpy,
    classroom_fee_jpy,
    is_active,
    note
  )
  values (
    p_teacher_id,
    p_student_id,
    p_subject_id,
    p_business_entity_id,
    v_settlement_type,
    p_hourly_rate_jpy,
    p_hourly_rate_cny,
    p_exchange_rate,
    p_transport_fee_jpy,
    p_classroom_fee_jpy,
    p_is_active,
    v_note
  )
  returning id into v_wage_rule_id;

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
  where r.id = v_wage_rule_id;
end;
$$;

comment on function public.school_create_teacher_wage_rule_config(
  uuid,
  uuid,
  uuid,
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
  'Creates one future-use teacher wage rule config row. Does not recalculate or modify wage locks, wage details, payment requests, expenses, accounts, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
