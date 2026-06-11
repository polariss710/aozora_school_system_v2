-- school_create_cross_month_makeup_completed_actual_from_planned_rpc.sql
-- RPC: public.school_create_cross_month_makeup_completed_actual_from_planned
-- Purpose: Create one cross-month makeup_completed actual lesson linked to one
--          previous-month pending_makeup planned lesson.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, guard-tested, and commit-tested.
-- Version: v2.93.0-actual-required-fields-20260611
--
-- Scope:
-- - Insert one actual row into public.school_lesson_records.
-- - Source must be one existing school planned lesson.
-- - Source status must be pending_makeup.
-- - Source planned lesson must not be soft-voided.
-- - The inserted actual row must set planned_lesson_id to the source planned id.
-- - actual status is fixed to makeup_completed.
-- - actual year_month is derived from p_lesson_date and must be greater than
--   source planned year_month.
-- - is_billable defaults to false; callers must pass p_is_billable = true
--   explicitly to bill the cross-month makeup result.
-- - Non-billable makeup_completed actual rows are fixed to lesson_fee = 0.
-- - actual_minutes is derived from duration_hours.
-- - Teacher settlement month is derived from p_lesson_date as YYYY-MM.
--
-- Not supported:
-- - Same-month makeup completion. Use school_create_makeup_completed_actual_lesson_from_planned.
-- - Free actual creation without planned_lesson_id.
-- - Source planned statuses other than pending_makeup.
-- - Copying planned or actual records.
-- - Modifying the source planned row.
-- - Modifying student monthly settlement snapshots, teacher wage locks,
--   wage lock details, payment requests, income, expense, accounts, or
--   account transactions.
-- - DB-level unique/index constraints. Existing linked-actual data must remain
--   untouched; duplicate prevention is enforced inside this guarded RPC.
--
-- Verification:
-- - Preflight duplicate scan found one existing historical linked-actual
--   duplicate group, so no DB-level unique/index constraint was added.
-- - Existing cross-month linked actual count was 0 before this RPC.
-- - Rollback tests created only temporary codex-test / v2-test / sandbox
--   planned sources and actuals, then rolled back with no residue. Covered:
--   successful default non-billable cross-month actual insertion, duplicate
--   linked-actual guard, same-month guard, target student settlement lock guard,
--   and target teacher wage lock guard.
-- - Whitelist commit test created source planned lesson
--   19b574d5-78e0-43fb-8248-e2cd9c2c68af and cross-month actual lesson
--   8baa4f13-f290-4332-819c-d8ba20906df4. The actual has year_month 2027-10,
--   planned_lesson_id pointing to the source, is_billable = false,
--   lesson_fee = 0, actual_minutes = 120, and teacher_settlement_month 2027-10.
-- - Commit test wrote only the two whitelisted lesson rows. Student settlements,
--   teacher wage locks/details, income, expense, accounts, account transactions,
--   and payment requests stayed unchanged.

create or replace function public.school_create_cross_month_makeup_completed_actual_from_planned(
  p_planned_lesson_id uuid,
  p_lesson_date date,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default null,
  p_unit_price numeric default null,
  p_lesson_fee numeric default null,
  p_is_billable boolean default false,
  p_lesson_count integer default null,
  p_lesson_content text default null,
  p_note text default null
)
returns table (
  lesson_id uuid,
  lesson_type text,
  lesson_date date,
  year_month text,
  student_id uuid,
  teacher_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  start_time text,
  end_time text,
  duration_hours numeric,
  unit_price numeric,
  lesson_fee numeric,
  status text,
  is_billable boolean,
  lesson_count integer,
  actual_minutes integer,
  planned_lesson_id uuid,
  teacher_settlement_month text,
  lesson_content text,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planned public.school_lesson_records%rowtype;
  v_actual_year_month text;
  v_start_time text;
  v_end_time text;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_fee numeric;
  v_is_billable boolean;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_actual_minutes integer;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
begin
  if p_planned_lesson_id is null then
    raise exception '请选择原月份待补课 planned。';
  end if;

  if p_lesson_date is null then
    raise exception '请选择跨月补课完成日期。';
  end if;

  select p.*
  into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
  for update;

  if not found then
    raise exception '原月份待补课 planned 不存在。';
  end if;

  if v_planned.lesson_type <> 'planned' then
    raise exception '跨月补课来源必须是 planned 课时。';
  end if;

  if v_planned.status <> 'pending_makeup' then
    raise exception '跨月补课来源必须是待补课 planned。';
  end if;

  if v_planned.voided_at is not null then
    raise exception '该 planned 已作废，不能登记跨月补课完成。';
  end if;

  if v_planned.year_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception '来源 planned 缺少有效年月，不能登记跨月补课完成。';
  end if;

  if v_planned.student_id is null then
    raise exception '来源 planned 缺少学生，不能登记跨月补课完成。';
  end if;

  if v_planned.teacher_id is null then
    raise exception '来源 planned 缺少老师，不能登记跨月补课完成。';
  end if;

  if v_planned.subject_id is null then
    raise exception '来源 planned 缺少科目，不能登记跨月补课完成。';
  end if;

  if v_planned.business_entity_id is null then
    raise exception '来源 planned 缺少业务归属，不能登记跨月补课完成。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该 planned 已有关联 actual，不能重复登记跨月补课完成。';
  end if;

  v_actual_year_month := to_char(p_lesson_date, 'YYYY-MM');
  if v_actual_year_month <= v_planned.year_month then
    raise exception '跨月补课完成月份必须晚于来源 planned 月份。';
  end if;

  v_start_time := coalesce(nullif(trim(coalesce(p_start_time, '')), ''), nullif(trim(coalesce(v_planned.start_time, '')), ''));
  v_end_time := coalesce(nullif(trim(coalesce(p_end_time, '')), ''), nullif(trim(coalesce(v_planned.end_time, '')), ''));
  v_duration_hours := coalesce(p_duration_hours, v_planned.duration_hours, 0);
  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_is_billable := coalesce(p_is_billable, false);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(nullif(trim(coalesce(p_lesson_content, '')), ''), v_planned.lesson_content);
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_start_time is null then
    raise exception '开始时间必填。';
  end if;

  if v_end_time is null then
    raise exception '结束时间必填。';
  end if;

  if nullif(trim(coalesce(v_lesson_content, '')), '') is null then
    raise exception '内容必填。';
  end if;

  if v_duration_hours <= 0 then
    raise exception '跨月补课完成时长必须大于 0。';
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
  end if;

  if v_is_billable then
    if p_lesson_fee is null then
      v_lesson_fee := coalesce(v_planned.lesson_fee, round(v_duration_hours * v_unit_price));
    else
      v_lesson_fee := p_lesson_fee;
    end if;
  else
    v_lesson_fee := 0;
  end if;

  if v_lesson_fee < 0 then
    raise exception '课时金额不能小于 0。';
  end if;

  if v_lesson_count is not null and v_lesson_count <= 0 then
    raise exception '课次数必须大于 0。';
  end if;

  if v_start_time is not null and v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间格式无效，请使用 HH:MM。';
  end if;

  if v_end_time is not null and v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间格式无效，请使用 HH:MM。';
  end if;

  select s.business_entity_id
  into v_student_business_entity_id
  from public.school_students s
  where s.id = v_planned.student_id
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null
    and v_student_business_entity_id is distinct from v_planned.business_entity_id then
    raise exception '学生默认业务归属与来源 planned 业务归属不一致。';
  end if;

  if not exists (
    select 1
    from public.school_teachers t
    where t.id = v_planned.teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if not exists (
    select 1
    from public.school_subjects s
    where s.id = v_planned.subject_id
      and coalesce(s.is_active, true) = true
  ) then
    raise exception '科目无效或已停用。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = v_planned.business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = v_actual_year_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '补课月份学生月度结算已锁定，不能登记跨月补课完成。';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_actual_year_month
      and w.status = 'locked'
  ) then
    raise exception '补课月份老师工资已锁定，不能登记跨月补课完成。';
  end if;

  v_actual_minutes := round(v_duration_hours * 60)::integer;

  insert into public.school_lesson_records (
    lesson_type,
    lesson_date,
    year_month,
    student_id,
    teacher_id,
    subject_id,
    business_entity_id,
    start_time,
    end_time,
    duration_hours,
    lesson_content,
    status,
    is_billable,
    note,
    app_type,
    planned_lesson_id,
    unit_price,
    lesson_fee,
    import_batch_id,
    import_source,
    imported_at,
    lesson_count,
    actual_minutes,
    teacher_settlement_month
  )
  values (
    'actual',
    p_lesson_date,
    v_actual_year_month,
    v_planned.student_id,
    v_planned.teacher_id,
    v_planned.subject_id,
    v_planned.business_entity_id,
    v_start_time,
    v_end_time,
    v_duration_hours,
    v_lesson_content,
    'makeup_completed',
    v_is_billable,
    v_note,
    'school',
    v_planned.id,
    v_unit_price,
    v_lesson_fee,
    null,
    null,
    null,
    v_lesson_count,
    v_actual_minutes,
    v_actual_year_month
  )
  returning id into v_actual_id;

  return query
  select
    a.id,
    a.lesson_type,
    a.lesson_date,
    a.year_month,
    a.student_id,
    a.teacher_id,
    a.subject_id,
    a.business_entity_id,
    a.start_time,
    a.end_time,
    a.duration_hours,
    a.unit_price,
    a.lesson_fee,
    a.status,
    a.is_billable,
    a.lesson_count,
    a.actual_minutes,
    a.planned_lesson_id,
    a.teacher_settlement_month,
    a.lesson_content,
    a.note,
    a.created_at,
    a.updated_at
  from public.school_lesson_records a
  where a.id = v_actual_id;
end;
$$;

comment on function public.school_create_cross_month_makeup_completed_actual_from_planned(
  uuid,
  date,
  text,
  text,
  numeric,
  numeric,
  numeric,
  boolean,
  integer,
  text,
  text
) is
  'Creates one cross-month makeup_completed actual school lesson linked to one previous-month pending_makeup planned lesson. Defaults to non-billable, writes the actual row into the makeup month, rejects soft-voided sources, duplicate linked actuals, same/earlier months, locked target student settlement months, and locked target teacher wage months; does not modify planned records or generate settlement, wage, payment, income, expense, account, or account transaction rows.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
