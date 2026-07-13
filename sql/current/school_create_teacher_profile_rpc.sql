-- school_create_teacher_profile_rpc.sql
-- RPC: public.school_create_teacher_profile
-- Purpose: Create future-use teacher master data only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.45.0-teacher-student-create-full-autopilot-20260606
--
-- Scope:
-- - Insert one row into public.school_teachers.
-- - Allowed fields: teacher_code, name, kana_name, display_name, department,
--   status, default_business_entity_id, note, app_type.
-- - Use existing table defaults for rates, currencies, payment method, subject,
--   bank/contact fields, timestamps, and id.
--
-- Not supported:
-- - Deleting, merging, or replacing teachers.
-- - Creating or editing wage rules, wage locks, payment requests, expenses, or
--   account transactions.
-- - Editing sensitive/contact/payment fields.
-- - Recalculating historical data.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - public.school_teachers.teacher_code has unique constraint
--   school_teachers_teacher_code_key.
-- - Rollback test inserted one codex-test teacher and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox teacher
--   efeafbbe-6d89-4f46-9d48-2970d2ec5a2f.
-- - Duplicate teacher code is rejected.
-- - Wage rule, wage lock, payment request, expense, and account transaction
--   counts stayed unchanged.

create or replace function public.school_create_teacher_profile(
  p_display_name text,
  p_teacher_code text default null,
  p_name text default null,
  p_kana_name text default null,
  p_status text default 'employed',
  p_department text default null,
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
  default_business_entity_id uuid,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_teacher_code text := nullif(trim(coalesce(p_teacher_code, '')), '');
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_kana_name text := nullif(trim(coalesce(p_kana_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, 'employed')), '');
  v_department text := nullif(trim(coalesce(p_department, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_default_business_entity_id uuid;
  v_teacher_id uuid;
begin
  if v_display_name is null then
    raise exception '老师显示名称不能为空。';
  end if;

  v_name := coalesce(v_name, v_display_name);

  if v_status is null then
    raise exception '老师状态不能为空。';
  end if;

  if v_status not in ('employed', 'inactive', 'paused', 'resigned') then
    raise exception '老师状态无效：%。', v_status;
  end if;

  v_default_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_default_business_entity_id, public.school_primary_business_entity_id()),
    '新增老师'
  );

  if v_teacher_code is not null and exists (
    select 1
    from public.school_teachers t
    where t.teacher_code = v_teacher_code
  ) then
    raise exception '老师编号已存在：%。', v_teacher_code;
  end if;

  insert into public.school_teachers (
    teacher_code,
    name,
    kana_name,
    display_name,
    department,
    status,
    default_business_entity_id,
    note,
    app_type
  )
  values (
    v_teacher_code,
    v_name,
    v_kana_name,
    v_display_name,
    v_department,
    v_status,
    v_default_business_entity_id,
    v_note,
    'school'
  )
  returning id into v_teacher_id;

  return query
  select
    t.id,
    t.teacher_code,
    t.name,
    t.kana_name,
    t.display_name,
    t.department,
    t.status,
    t.default_business_entity_id,
    t.note,
    t.created_at,
    t.updated_at
  from public.school_teachers t
  where t.id = v_teacher_id;
exception
  when unique_violation then
    raise exception '老师编号已存在：%。', v_teacher_code;
end;
$$;

comment on function public.school_create_teacher_profile(
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text
) is
  'Creates one future-use school teacher master row. Does not modify wage rules, wage locks, payment requests, expenses, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.

-- v2.101.0 teacher dialog field-scope overload.
-- Purpose: Create teacher master data through the narrowed teacher dialog.
-- Allowed exposed fields:
-- - name
-- - department: 常勤老师 / バイト老师 / 事务老师
-- - default_subject_id
-- - default_business_entity_id
-- - status: employed / paused / resigned
-- - note
-- - CNY payment info: alipay_account, wechat_account
-- - JPY payment info: bank_name, bank_branch_code, bank_branch_name, bank_account_number
--
-- Preserved/closed fields:
-- - teacher_code: system/admin identifier, not user-editable here.
-- - kana_name: legacy/profile field, not required by current business.
-- - display_name: set internally to name for lookup compatibility.
-- - default_hourly_rate/default_currency/default_payment_currency/default_payment_method:
--   wage/payment defaults remain closed from teacher profile; payment confirmation
--   uses payment-request currency plus selected account currency.
-- - bank_account_name, default_account_name, phone, email, wechat,
--   china_bank_account: historical/privacy/payment-profile fields not in this scope.
-- - wage rules, wage locks, payment requests, expenses, account transactions,
--   lessons, and historical settlement/payment chains.

create or replace function public.school_create_teacher_profile(
  p_profile jsonb
)
returns table (
  teacher_id uuid,
  teacher_code text,
  name text,
  display_name text,
  department text,
  default_subject_id uuid,
  default_business_entity_id uuid,
  status text,
  note text,
  alipay_account text,
  wechat_account text,
  bank_name text,
  bank_branch_code text,
  bank_branch_name text,
  bank_account_number text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile jsonb := coalesce(p_profile, '{}'::jsonb);
  v_name text := nullif(trim(coalesce(v_profile ->> 'name', '')), '');
  v_department text := nullif(trim(coalesce(v_profile ->> 'department', '')), '');
  v_default_subject_id uuid := nullif(trim(coalesce(v_profile ->> 'default_subject_id', '')), '')::uuid;
  v_default_business_entity_id uuid := nullif(trim(coalesce(v_profile ->> 'default_business_entity_id', '')), '')::uuid;
  v_status text := nullif(trim(coalesce(v_profile ->> 'status', 'employed')), '');
  v_note text := nullif(trim(coalesce(v_profile ->> 'note', '')), '');
  v_alipay_account text := nullif(trim(coalesce(v_profile ->> 'alipay_account', '')), '');
  v_wechat_account text := nullif(trim(coalesce(v_profile ->> 'wechat_account', '')), '');
  v_bank_name text := nullif(trim(coalesce(v_profile ->> 'bank_name', '')), '');
  v_bank_branch_code text := nullif(trim(coalesce(v_profile ->> 'bank_branch_code', '')), '');
  v_bank_branch_name text := nullif(trim(coalesce(v_profile ->> 'bank_branch_name', '')), '');
  v_bank_account_number text := nullif(trim(coalesce(v_profile ->> 'bank_account_number', '')), '');
  v_teacher_id uuid;
begin
  if v_name is null then
    raise exception '老师姓名不能为空。';
  end if;

  if v_department is null then
    raise exception '请选择老师分类。';
  end if;

  if v_department not in ('常勤老师', 'バイト老师', '事务老师') then
    raise exception '老师分类无效：%。', v_department;
  end if;

  if v_status is null then
    raise exception '请选择老师状态。';
  end if;

  if v_status not in ('employed', 'paused', 'resigned') then
    raise exception '老师状态无效：%。', v_status;
  end if;

  if v_default_subject_id is not null
    and not exists (
      select 1
      from public.school_subjects s
      where s.id = v_default_subject_id
    ) then
    raise exception '默认科目不存在。';
  end if;

  v_default_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(v_default_business_entity_id, public.school_primary_business_entity_id()),
    '新增老师'
  );

  insert into public.school_teachers (
    name,
    display_name,
    department,
    default_subject_id,
    default_business_entity_id,
    status,
    note,
    alipay_account,
    wechat_account,
    bank_name,
    bank_branch_code,
    bank_branch_name,
    bank_account_number,
    app_type
  )
  values (
    v_name,
    v_name,
    v_department,
    v_default_subject_id,
    v_default_business_entity_id,
    v_status,
    v_note,
    v_alipay_account,
    v_wechat_account,
    v_bank_name,
    v_bank_branch_code,
    v_bank_branch_name,
    v_bank_account_number,
    'school'
  )
  returning id into v_teacher_id;

  return query
  select
    t.id,
    t.teacher_code,
    t.name,
    t.display_name,
    t.department,
    t.default_subject_id,
    t.default_business_entity_id,
    t.status,
    t.note,
    t.alipay_account,
    t.wechat_account,
    t.bank_name,
    t.bank_branch_code,
    t.bank_branch_name,
    t.bank_account_number,
    t.created_at,
    t.updated_at
  from public.school_teachers t
  where t.id = v_teacher_id;
end;
$$;

comment on function public.school_create_teacher_profile(jsonb) is
  'Creates one school teacher from the narrowed teacher dialog field set. Synchronizes display_name to name and does not modify wage/payment/lesson/account chains.';
