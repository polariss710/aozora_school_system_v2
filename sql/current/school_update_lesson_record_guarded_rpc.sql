-- school_update_lesson_record_guarded_rpc.sql
-- RPC: public.school_update_lesson_record_guarded
-- Purpose: Guarded V1 update for one school lesson record.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, guard-tested, and commit-tested.
-- Version: v2.63.0-lesson-planned-void-schema-rpc-20260609
--
-- Scope:
-- - Update one public.school_lesson_records row only.
-- - Does not expose lesson_type or planned_lesson_id as editable parameters.
-- - planned rows may be edited only when current status is planned/pending_makeup,
--   voided_at is null, requested status remaining planned/pending_makeup, no
--   linked actual, and old/new student settlement months unlocked.
-- - actual rows may be edited only when current status is
--   completed/cancelled/makeup_completed, requested status is unchanged, old/new
--   student settlement months and old/new teacher wage months are unlocked, and
--   no wage lock detail references the lesson.
-- - linked actual rows cannot change student/teacher/subject/business entity in V1.
--
-- Not supported:
-- - Changing lesson_type.
-- - Changing planned_lesson_id, linking, unlinking, or rematching.
-- - Editing legacy planned rows with completed/makeup_completed status.
-- - Editing settlement, wage, payment, income, expense, account, or account
--   transaction records.
-- - Adding schema, indexes, or constraints.
--
-- Fee derivation:
-- - If p_lesson_fee is null, the RPC derives fee as round(duration_hours * unit_price)
--   for billable planned/completed/makeup_completed rows.
-- - Non-billable actual rows use lesson_fee = 0.
-- - Cancelled actual rows are fixed to is_billable = false, lesson_fee = 0, and
--   actual_minutes = 0, preserving the existing cancelled-actual write口径.
--
-- Review before execution:
-- - Confirm school_lesson_records.updated_at trigger exists.
-- - Confirm no SQL in this file writes tables other than school_lesson_records.
-- - Confirm rollback/guard/commit tests use codex-test whitelist records only,
--   except historical locked rows may be observed for guard rejection without
--   successful writes.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback tests covered editable planned updates, planned status switch between
--   planned/pending_makeup, and editable actual updates with no residue.
-- - Guard tests covered linked planned rejection, legacy planned status rejection,
--   actual status-change rejection, linked actual master-data rejection, wage
--   detail usage rejection, locked student settlement month rejection, locked
--   teacher wage month rejection, and updated_at optimistic-lock rejection.
-- - Commit test updated only whitelisted codex-test school_lesson_records row
--   bce0af13-7452-46c1-90e0-641b1dc78d3b.
-- - Student settlements, teacher wage locks/details, payment requests, income,
--   expense, accounts, and account transactions were not written by the RPC.

create or replace function public.school_update_lesson_record_guarded(
  p_lesson_id uuid,
  p_expected_updated_at timestamptz,
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
  p_status text default null,
  p_is_billable boolean default true,
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
  v_lesson public.school_lesson_records%rowtype;
  v_year_month text;
  v_old_year_month text;
  v_teacher_settlement_month text;
  v_old_teacher_settlement_month text;
  v_start_time text := nullif(trim(coalesce(p_start_time, '')), '');
  v_end_time text := nullif(trim(coalesce(p_end_time, '')), '');
  v_duration_hours numeric := coalesce(p_duration_hours, 0);
  v_unit_price numeric := coalesce(p_unit_price, 0);
  v_lesson_fee numeric;
  v_status text;
  v_is_billable boolean := coalesce(p_is_billable, true);
  v_lesson_content text := nullif(trim(coalesce(p_lesson_content, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_actual_minutes integer;
  v_student_business_entity_id uuid;
begin
  if p_lesson_id is null then
    raise exception '请选择要编辑的课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本信息，请刷新后重试。';
  end if;

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

  if v_duration_hours <= 0 then
    raise exception '课时时长必须大于 0。';
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
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

  select l.*
  into v_lesson
  from public.school_lesson_records l
  where l.id = p_lesson_id
    and l.app_type = 'school'
  for update;

  if not found then
    raise exception '课时不存在。';
  end if;

  if v_lesson.updated_at is distinct from p_expected_updated_at then
    raise exception '课时已被其他操作更新，请刷新后重试。';
  end if;

  if v_lesson.lesson_type not in ('planned', 'actual') then
    raise exception '不支持编辑该课时类型：%。', coalesce(v_lesson.lesson_type, '');
  end if;

  if p_business_entity_id is distinct from v_lesson.business_entity_id then
    perform public.school_assert_new_business_entity_allowed(
      p_business_entity_id,
      '更新课时业务归属'
    );
  end if;

  v_status := nullif(trim(coalesce(p_status, v_lesson.status)), '');
  if v_status is null then
    raise exception '课时状态不能为空。';
  end if;

  v_year_month := to_char(p_lesson_date, 'YYYY-MM');
  v_old_year_month := coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'));

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

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_lesson.student_id
      and s.year_month = v_old_year_month
      and s.business_entity_id is not distinct from v_lesson.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '原学生月度结算已锁定，不能编辑课时。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.year_month = v_year_month
      and s.business_entity_id is not distinct from p_business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能编辑课时。';
  end if;

  if v_lesson.lesson_type = 'planned' then
    if v_lesson.voided_at is not null then
      raise exception '该预定课时已作废，不能编辑。';
    end if;

    if v_lesson.status not in ('planned', 'pending_makeup') then
      raise exception '当前 planned 状态不允许编辑：%。', coalesce(v_lesson.status, '');
    end if;

    if v_status not in ('planned', 'pending_makeup') then
      raise exception '预定课时状态无效：%。', coalesce(v_status, '');
    end if;

    if v_is_billable is distinct from true then
      raise exception '预定课时 V1 不支持修改计费状态。';
    end if;

    if exists (
      select 1
      from public.school_lesson_records a
      where a.app_type = 'school'
        and a.lesson_type = 'actual'
        and a.planned_lesson_id = v_lesson.id
    ) then
      raise exception '该预定课时已有 actual 关联，不能编辑。';
    end if;

    if p_lesson_fee is null then
      v_lesson_fee := round(v_duration_hours * v_unit_price);
    else
      v_lesson_fee := p_lesson_fee;
    end if;

    if v_lesson_fee < 0 then
      raise exception '课时金额不能小于 0。';
    end if;

    update public.school_lesson_records l
    set
      lesson_date = p_lesson_date,
      year_month = v_year_month,
      student_id = p_student_id,
      teacher_id = p_teacher_id,
      subject_id = p_subject_id,
      business_entity_id = p_business_entity_id,
      start_time = v_start_time,
      end_time = v_end_time,
      duration_hours = v_duration_hours,
      unit_price = v_unit_price,
      lesson_fee = v_lesson_fee,
      status = v_status,
      is_billable = true,
      lesson_count = p_lesson_count,
      actual_minutes = null,
      planned_lesson_id = null,
      teacher_settlement_month = null,
      lesson_content = v_lesson_content,
      note = v_note,
      app_type = 'school'
    where l.id = v_lesson.id;
  else
    if v_lesson.status not in ('completed', 'cancelled', 'makeup_completed') then
      raise exception '当前 actual 状态不允许编辑：%。', coalesce(v_lesson.status, '');
    end if;

    if v_status <> v_lesson.status then
      raise exception 'actual 课时 V1 不允许修改状态。';
    end if;

    if v_status in ('completed', 'makeup_completed') then
      if v_start_time is null then
        raise exception '已完成 / 补课完成 actual 必须填写开始时间。';
      end if;

      if v_end_time is null then
        raise exception '已完成 / 补课完成 actual 必须填写结束时间。';
      end if;

      if v_lesson_content is null then
        raise exception '已完成 / 补课完成 actual 必须填写课程内容。';
      end if;
    end if;

    if v_lesson.planned_lesson_id is not null and (
      p_student_id is distinct from v_lesson.student_id
      or p_teacher_id is distinct from v_lesson.teacher_id
      or p_subject_id is distinct from v_lesson.subject_id
      or p_business_entity_id is distinct from v_lesson.business_entity_id
    ) then
      raise exception '已关联预定课时的 actual V1 不允许修改学生、老师、科目或业务归属。';
    end if;

    if exists (
      select 1
      from public.school_teacher_wage_lock_details d
      join public.school_teacher_wage_locks w
        on w.id = d.lock_id
      where d.lesson_record_id = v_lesson.id
        and w.status = 'locked'
        and w.voided_at is null
    ) then
      raise exception '该 actual 已被老师工资锁定明细使用，不能编辑。';
    end if;

    v_old_teacher_settlement_month := coalesce(
      v_lesson.teacher_settlement_month,
      to_char(v_lesson.lesson_date, 'YYYY-MM')
    );
    v_teacher_settlement_month := to_char(p_lesson_date, 'YYYY-MM');

    if exists (
      select 1
      from public.school_teacher_wage_locks w
      where w.teacher_id = v_lesson.teacher_id
        and w.business_entity_id is not distinct from v_lesson.business_entity_id
        and w.settlement_month = v_old_teacher_settlement_month
        and w.status = 'locked'
    ) then
      raise exception '原老师工资月份已锁定，不能编辑 actual。';
    end if;

    if exists (
      select 1
      from public.school_teacher_wage_locks w
      where w.teacher_id = p_teacher_id
        and w.business_entity_id is not distinct from p_business_entity_id
        and w.settlement_month = v_teacher_settlement_month
        and w.status = 'locked'
    ) then
      raise exception '目标老师工资月份已锁定，不能编辑 actual。';
    end if;

    if v_lesson.status = 'cancelled' then
      v_is_billable := false;
      v_lesson_fee := 0;
      v_actual_minutes := 0;
    else
      if v_is_billable then
        if p_lesson_fee is null then
          v_lesson_fee := round(v_duration_hours * v_unit_price);
        else
          v_lesson_fee := p_lesson_fee;
        end if;
      else
        v_lesson_fee := 0;
      end if;
      v_actual_minutes := round(v_duration_hours * 60)::integer;
    end if;

    if v_lesson_fee < 0 then
      raise exception '课时金额不能小于 0。';
    end if;

    update public.school_lesson_records l
    set
      lesson_date = p_lesson_date,
      year_month = v_year_month,
      student_id = p_student_id,
      teacher_id = p_teacher_id,
      subject_id = p_subject_id,
      business_entity_id = p_business_entity_id,
      start_time = v_start_time,
      end_time = v_end_time,
      duration_hours = v_duration_hours,
      unit_price = v_unit_price,
      lesson_fee = v_lesson_fee,
      status = v_lesson.status,
      is_billable = v_is_billable,
      lesson_count = p_lesson_count,
      actual_minutes = v_actual_minutes,
      planned_lesson_id = v_lesson.planned_lesson_id,
      teacher_settlement_month = v_teacher_settlement_month,
      lesson_content = v_lesson_content,
      note = v_note,
      app_type = 'school'
    where l.id = v_lesson.id;
  end if;

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
    l.actual_minutes,
    l.planned_lesson_id,
    l.teacher_settlement_month,
    l.lesson_content,
    l.note,
    l.created_at,
    l.updated_at
  from public.school_lesson_records l
  where l.id = v_lesson.id;
end;
$$;

comment on function public.school_update_lesson_record_guarded(
  uuid,
  timestamptz,
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
  boolean,
  integer,
  text,
  text
) is
  'Guarded V1 update for one school lesson record. Preserves lesson_type and planned_lesson_id, blocks voided planned edits, linked planned edits, locked student settlement months, locked teacher wage months, wage detail snapshots, and downstream financial side effects.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
--
-- This file intentionally contains no test calls and no data repair SQL.
