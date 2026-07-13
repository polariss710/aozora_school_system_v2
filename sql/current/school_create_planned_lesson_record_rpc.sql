-- school_create_planned_lesson_record_rpc.sql
-- RPC: public.school_create_planned_lesson_record
-- Purpose: Create one planned lesson record only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, locked-guard-tested, and commit-tested.
-- Version: v2.54.0-lesson-planned-create-full-autopilot-20260607
--
-- Scope:
-- - Insert one planned row into public.school_lesson_records.
-- - Allowed planned fields: lesson_date, student_id, teacher_id, subject_id,
--   business_entity_id, start_time, end_time, duration_hours, unit_price,
--   lesson_fee, status, lesson_count, lesson_content, note.
-- - year_month is derived from lesson_date.
-- - lesson_type is fixed to planned; is_billable is fixed to true.
--
-- Not supported:
-- - Creating actual lessons, cancelled lessons, or makeup_completed lessons.
-- - Creating actual from planned.
-- - Editing, deleting, copying, importing, or batch operations.
-- - Modifying student monthly settlement snapshots, teacher wage locks,
--   wage lock details, payment requests, income, expense, accounts, or
--   account transactions.
--
-- Verification:
-- - Function exists with expected signature and return columns.
-- - Rollback test inserts a codex-test planned lesson and leaves no residue.
-- - Locked settlement guard was tested inside a rollback transaction and left
--   no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox
--   planned lesson 85ab1365-7929-4818-a369-4a7c935c2368.
-- - No actual lesson, wage lock detail, payment request, income, expense, or
--   account transaction is generated.

create or replace function public.school_create_planned_lesson_record(
  p_lesson_date date,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default 0,
  p_unit_price numeric default 0,
  p_lesson_fee numeric default null,
  p_status text default 'planned',
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
  v_year_month text;
  v_start_time text := nullif(trim(coalesce(p_start_time, '')), '');
  v_end_time text := nullif(trim(coalesce(p_end_time, '')), '');
  v_duration_hours numeric := coalesce(p_duration_hours, 0);
  v_unit_price numeric := coalesce(p_unit_price, 0);
  v_lesson_fee numeric;
  v_status text := nullif(trim(coalesce(p_status, 'planned')), '');
  v_lesson_content text := nullif(trim(coalesce(p_lesson_content, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_lesson_id uuid;
  v_student_business_entity_id uuid;
begin
  if p_lesson_date is null then
    raise exception '请选择课时日期。';
  end if;

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if p_teacher_id is null then
    raise exception '请选择老师。';
  end if;

  if p_subject_id is null then
    raise exception '请选择科目。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增预定课时'
  );

  if v_status not in ('planned', 'pending_makeup') then
    raise exception '预定课时状态无效：%。', coalesce(v_status, '');
  end if;

  if v_duration_hours <= 0 then
    raise exception '课时时长必须大于 0。';
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
  end if;

  if p_lesson_fee is null then
    v_lesson_fee := round(v_duration_hours * v_unit_price);
  else
    v_lesson_fee := p_lesson_fee;
  end if;

  if v_lesson_fee < 0 then
    raise exception '课时金额不能小于 0。';
  end if;

  if p_lesson_count is not null and p_lesson_count <= 0 then
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
  where s.id = p_student_id
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null
    and v_student_business_entity_id is distinct from p_business_entity_id then
    raise exception '学生默认业务归属与课时业务归属不一致。';
  end if;

  if not exists (
    select 1
    from public.school_teachers t
    where t.id = p_teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if not exists (
    select 1
    from public.school_subjects s
    where s.id = p_subject_id
      and coalesce(s.is_active, true) = true
  ) then
    raise exception '科目无效或已停用。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = p_business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;

  v_year_month := to_char(p_lesson_date, 'YYYY-MM');

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.year_month = v_year_month
      and s.business_entity_id is not distinct from p_business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能新增课时。';
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
    'planned',
    p_lesson_date,
    v_year_month,
    p_student_id,
    p_teacher_id,
    p_subject_id,
    p_business_entity_id,
    v_start_time,
    v_end_time,
    v_duration_hours,
    v_lesson_content,
    v_status,
    true,
    v_note,
    'school',
    null,
    v_unit_price,
    v_lesson_fee,
    null,
    null,
    null,
    p_lesson_count,
    null,
    null
  )
  returning id into v_lesson_id;

  return query
  select
    l.id,
    l.lesson_type,
    l.lesson_date,
    l.year_month,
    l.student_id,
    l.teacher_id,
    l.subject_id,
    l.business_entity_id,
    l.start_time,
    l.end_time,
    l.duration_hours,
    l.unit_price,
    l.lesson_fee,
    l.status,
    l.is_billable,
    l.lesson_count,
    l.lesson_content,
    l.note,
    l.created_at,
    l.updated_at
  from public.school_lesson_records l
  where l.id = v_lesson_id;
end;
$$;

comment on function public.school_create_planned_lesson_record(
  date,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  numeric,
  numeric,
  numeric,
  text,
  integer,
  text,
  text
) is
  'Creates one planned school lesson record only. Rejects locked student settlement targets and does not create actual lessons, wage details, payment requests, income, expenses, accounts, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
