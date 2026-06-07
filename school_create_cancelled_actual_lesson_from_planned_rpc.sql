-- school_create_cancelled_actual_lesson_from_planned_rpc.sql
-- RPC: public.school_create_cancelled_actual_lesson_from_planned
-- Purpose: Create one cancelled actual lesson linked to one planned lesson.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, guard-tested, and commit-tested.
-- Version: v2.56.0-lesson-cancelled-actual-from-planned-full-autopilot-20260607
--
-- Scope:
-- - Insert one actual row into public.school_lesson_records.
-- - Source must be one existing school planned lesson.
-- - The inserted actual row must set planned_lesson_id to the source planned id.
-- - actual status is fixed to cancelled.
-- - Cancelled actual rows are fixed to non-billable with lesson_fee = 0
--   and actual_minutes = 0.
-- - Student settlement month is inherited from planned.year_month.
-- - Teacher settlement month is derived from cancelled actual lesson date as YYYY-MM.
--
-- Not supported:
-- - Free actual creation without planned_lesson_id.
-- - completed or makeup_completed actual creation.
-- - Editing, deleting, copying, importing, or batch generation.
-- - Modifying the source planned row.
-- - Modifying student monthly settlement snapshots, teacher wage locks,
--   wage lock details, payment requests, income, expense, accounts, or
--   account transactions.
--
-- Verification:
-- - Function exists with expected signature and return columns.
-- - Rollback test inserted a codex-test cancelled actual from a codex-test
--   planned lesson and left no residue.
-- - Duplicate actual guard, locked student settlement guard, and locked teacher
--   wage guard were tested inside rollback transactions and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox
--   planned lesson 557214bb-0826-42e1-b3cb-52953045f4b5 and cancelled actual
--   lesson 8ac46deb-259b-4967-b33d-411d3b40fd8c.
-- - Source planned lesson 557214bb-0826-42e1-b3cb-52953045f4b5 kept status
--   planned. Cancelled actual lesson 8ac46deb-259b-4967-b33d-411d3b40fd8c
--   has is_billable = false, lesson_fee = 0, and actual_minutes = 0.
-- - No wage lock detail, payment request, income, expense, account, or account
--   transaction was generated.

create or replace function public.school_create_cancelled_actual_lesson_from_planned(
  p_planned_lesson_id uuid,
  p_lesson_date date default null,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default null,
  p_unit_price numeric default null,
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
  v_lesson_date date;
  v_start_time text;
  v_end_time text;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_teacher_settlement_month text;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
begin
  if p_planned_lesson_id is null then
    raise exception '请选择预定课时。';
  end if;

  select p.*
  into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;

  if v_planned.lesson_type <> 'planned' then
    raise exception '只能从 planned 课时生成取消 actual。';
  end if;

  if v_planned.status not in ('planned', 'pending_makeup') then
    raise exception '当前 planned 状态不能生成 cancelled actual：%。', coalesce(v_planned.status, '');
  end if;

  if v_planned.student_id is null then
    raise exception '预定课时缺少学生，不能生成取消 actual。';
  end if;

  if v_planned.teacher_id is null then
    raise exception '预定课时缺少老师，不能生成取消 actual。';
  end if;

  if v_planned.subject_id is null then
    raise exception '预定课时缺少科目，不能生成取消 actual。';
  end if;

  if v_planned.business_entity_id is null then
    raise exception '预定课时缺少业务归属，不能生成取消 actual。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该预定课时已有关联 actual，不能重复生成。';
  end if;

  v_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  if v_lesson_date is null then
    raise exception '请选择取消课日期。';
  end if;

  v_start_time := coalesce(nullif(trim(coalesce(p_start_time, '')), ''), nullif(trim(coalesce(v_planned.start_time, '')), ''));
  v_end_time := coalesce(nullif(trim(coalesce(p_end_time, '')), ''), nullif(trim(coalesce(v_planned.end_time, '')), ''));
  v_duration_hours := coalesce(p_duration_hours, v_planned.duration_hours, 0);
  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(nullif(trim(coalesce(p_lesson_content, '')), ''), v_planned.lesson_content);
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_duration_hours <= 0 then
    raise exception '取消课时长必须大于 0。';
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
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
    raise exception '学生默认业务归属与课时业务归属不一致。';
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
      and s.year_month = v_planned.year_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成取消 actual。';
  end if;

  v_teacher_settlement_month := to_char(v_lesson_date, 'YYYY-MM');

  if exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_teacher_settlement_month
      and w.status = 'locked'
  ) then
    raise exception '目标老师工资月份已锁定，不能生成取消 actual。';
  end if;

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
    v_lesson_date,
    v_planned.year_month,
    v_planned.student_id,
    v_planned.teacher_id,
    v_planned.subject_id,
    v_planned.business_entity_id,
    v_start_time,
    v_end_time,
    v_duration_hours,
    v_lesson_content,
    'cancelled',
    false,
    v_note,
    'school',
    v_planned.id,
    v_unit_price,
    0,
    null,
    null,
    null,
    v_lesson_count,
    0,
    v_teacher_settlement_month
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

comment on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,
  date,
  text,
  text,
  numeric,
  numeric,
  integer,
  text,
  text
) is
  'Creates one non-billable cancelled actual school lesson linked to one planned lesson. Rejects duplicate linked actuals, locked student settlement months, and locked teacher wage months; does not modify planned records or generate settlement, wage, payment, income, expense, account, or account transaction rows.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
