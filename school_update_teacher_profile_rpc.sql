-- school_update_teacher_profile_rpc.sql
-- RPC: public.school_update_teacher_profile
-- Purpose: Update safe teacher master-data profile fields only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.99.0-master-editable-fields-open-20260612
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test updates only teacher master-data fields and leaves no residue.
-- - Commit test used whitelisted codex-test teacher only.
-- - Wage rule, settlement, payment, lesson, contact, and payment-account fields remain unchanged.
-- - Empty names, invalid status/currency/rate, and inactive/missing business entity are rejected.
--
-- Scope:
-- - Update one school teacher row.
-- - Allowed fields: name, kana_name, display_name, department, status,
--   default_hourly_rate, default_currency, default_payment_currency,
--   default_payment_method, default_business_entity_id, note.
-- - Preserve wage rules, settlement fields, payment data, lesson data, bank
--   details, phone, email, wechat, subject, teacher_code, timestamps except updated_at.
--
-- Not supported:
-- - Editing teacher_code or default_subject_id.
-- - Editing bank, alipay, wechat pay, phone, email, or other sensitive/contact fields.
-- - Editing wage rules, wage locks, salary payments, lessons, or settlements.
-- - Creating, deleting, or merging teachers.
--
-- Review before execution:
-- - Confirm public.school_teachers has all allowed columns.
-- - Confirm status allowed values fit current product expectations.
-- - Confirm commit test uses whitelisted test teacher only.

create or replace function public.school_update_teacher_profile(
  p_teacher_id uuid,
  p_display_name text,
  p_name text,
  p_kana_name text default null,
  p_department text default null,
  p_status text default 'employed',
  p_default_hourly_rate numeric default 0,
  p_default_currency text default 'JPY',
  p_default_payment_currency text default 'JPY',
  p_default_payment_method text default null,
  p_default_business_entity_id uuid default null,
  p_note text default null
)
returns table (
  teacher_id uuid,
  teacher_code text,
  name text,
  kana_name text,
  display_name text,
  department text,
  status text,
  default_hourly_rate numeric,
  default_currency text,
  default_payment_currency text,
  default_payment_method text,
  default_business_entity_id uuid,
  note text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_teacher public.school_teachers%rowtype;
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_kana_name text := nullif(trim(coalesce(p_kana_name, '')), '');
  v_department text := nullif(trim(coalesce(p_department, '')), '');
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_default_hourly_rate numeric := coalesce(p_default_hourly_rate, 0);
  v_default_currency text := upper(nullif(trim(coalesce(p_default_currency, 'JPY')), ''));
  v_default_payment_currency text := upper(nullif(trim(coalesce(p_default_payment_currency, 'JPY')), ''));
  v_default_payment_method text := nullif(trim(coalesce(p_default_payment_method, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if p_teacher_id is null then
    raise exception '请选择要编辑的老师。';
  end if;

  if v_display_name is null then
    raise exception '老师显示名称不能为空。';
  end if;

  if v_name is null then
    raise exception '老师系统姓名不能为空。';
  end if;

  if v_status is null then
    raise exception '老师状态不能为空。';
  end if;

  if v_status not in ('employed', 'inactive', 'paused', 'resigned') then
    raise exception '老师状态无效：%。', v_status;
  end if;

  if v_default_hourly_rate < 0 then
    raise exception '默认时薪不能为负数。';
  end if;

  if v_default_currency is null or v_default_currency not in ('JPY', 'CNY') then
    raise exception '默认币种无效：%。', coalesce(v_default_currency, '未设置');
  end if;

  if v_default_payment_currency is null or v_default_payment_currency not in ('JPY', 'CNY') then
    raise exception '默认支付币种无效：%。', coalesce(v_default_payment_currency, '未设置');
  end if;

  if p_default_business_entity_id is not null
    and not exists (
      select 1
      from public.school_business_entities b
      where b.id = p_default_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
    raise exception '业务归属不存在或已停用。';
  end if;

  select *
  into v_teacher
  from public.school_teachers t
  where t.id = p_teacher_id
    and coalesce(t.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '老师不存在。';
  end if;

  update public.school_teachers t
  set
    name = v_name,
    kana_name = v_kana_name,
    display_name = v_display_name,
    department = v_department,
    status = v_status,
    default_hourly_rate = v_default_hourly_rate,
    default_currency = v_default_currency,
    default_payment_currency = v_default_payment_currency,
    default_payment_method = v_default_payment_method,
    default_business_entity_id = p_default_business_entity_id,
    note = v_note,
    updated_at = v_now
  where t.id = v_teacher.id;

  return query
  select
    t.id,
    t.teacher_code,
    t.name,
    t.kana_name,
    t.display_name,
    t.department,
    t.status,
    t.default_hourly_rate,
    t.default_currency,
    t.default_payment_currency,
    t.default_payment_method,
    t.default_business_entity_id,
    t.note,
    t.updated_at
  from public.school_teachers t
  where t.id = v_teacher.id;
end;
$$;

comment on function public.school_update_teacher_profile(
  uuid,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  text,
  text,
  uuid,
  text
) is
  'Updates safe school teacher master-data fields only; does not modify wage rules, wage locks, payment, lesson, contact, or payment-account data.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This draft intentionally does not include executable test insert/update/delete
-- statements outside the function definition.
