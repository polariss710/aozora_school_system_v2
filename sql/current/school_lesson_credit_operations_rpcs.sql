-- school_lesson_credit_operations_rpcs.sql
-- Purpose: authoritative student lesson-credit balance and cross-teacher/subject
--          makeup actual creation. This file contains RPCs only; it does not
--          backfill or modify historical business rows when installed.

create or replace function public.school_get_lesson_credit_remaining_hours(
  p_planned_lesson_id uuid
)
returns numeric
language sql
stable
set search_path = public
as $$
  select greatest(
    coalesce(p.duration_hours, 0)
    - coalesce(sum(a.duration_hours) filter (
      where a.lesson_type = 'actual'
        and a.status in ('completed', 'makeup_completed')
    ), 0),
    0
  )::numeric
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id = p.id
   and a.app_type = 'school'
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
    and p.lesson_type = 'planned'
  group by p.id, p.duration_hours;
$$;

comment on function public.school_get_lesson_credit_remaining_hours(uuid) is
  'Returns the non-negative unfulfilled lesson-credit hours for one planned lesson. Only completed and makeup_completed linked actual hours consume credit; cancelled actuals consume zero. Historical over-fulfilled rows return zero and are not repaired.';

create or replace function public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,
  p_lesson_date date,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_lesson_content text,
  p_note text default null,
  p_lesson_count integer default null,
  p_lesson_delivery_mode text default null,
  p_lesson_venue text default null
)
returns setof public.school_lesson_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planned public.school_lesson_records%rowtype;
  v_target_year_month text;
  v_remaining_hours numeric;
  v_actual_id uuid;
  v_teacher_id uuid;
  v_subject_id uuid;
  v_content text;
  v_note text;
  v_start_time text;
  v_end_time text;
  v_delivery_mode text;
  v_venue text;
begin
  if p_planned_lesson_id is null then
    raise exception '请选择待补课来源。';
  end if;
  select p.*
    into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
    and p.lesson_type = 'planned'
  for update;

  if not found then
    raise exception '待补课来源不存在。';
  end if;
  if v_planned.voided_at is not null then
    raise exception '待补课来源已作废。';
  end if;
  if v_planned.status <> 'pending_makeup' then
    raise exception '只有待补课预定课时可以使用课时余额。';
  end if;
  if v_planned.student_id is null or v_planned.business_entity_id is null then
    raise exception '待补课来源缺少学生或业务归属。';
  end if;

  select public.school_get_lesson_credit_remaining_hours(v_planned.id)
    into v_remaining_hours;
  p_duration_hours := coalesce(p_duration_hours, v_remaining_hours);
  if p_duration_hours is null or p_duration_hours <= 0 then
    raise exception '补课完成时长必须大于 0。';
  end if;
  if coalesce(v_remaining_hours, 0) <= 0 then
    raise exception '该待补课来源已无剩余课时。';
  end if;
  if p_duration_hours > v_remaining_hours then
    raise exception '补课时长超过剩余课时：剩余 % 小时。', v_remaining_hours;
  end if;

  p_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  v_teacher_id := coalesce(p_teacher_id, v_planned.teacher_id);
  v_subject_id := coalesce(p_subject_id, v_planned.subject_id);
  v_start_time := coalesce(nullif(trim(coalesce(p_start_time, '')), ''), v_planned.start_time);
  v_end_time := coalesce(nullif(trim(coalesce(p_end_time, '')), ''), v_planned.end_time);
  v_content := coalesce(nullif(trim(coalesce(p_lesson_content, '')), ''), v_planned.lesson_content);
  v_note := nullif(trim(coalesce(p_note, '')), '');
  v_delivery_mode := coalesce(nullif(trim(coalesce(p_lesson_delivery_mode, '')), ''), v_planned.lesson_delivery_mode);
  v_venue := coalesce(nullif(trim(coalesce(p_lesson_venue, '')), ''), v_planned.lesson_venue);

  if v_teacher_id is null or not exists (
    select 1 from public.school_teachers t
    where t.id = v_teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '请选择有效老师。';
  end if;
  if v_subject_id is null or not exists (
    select 1 from public.school_subjects s
    where s.id = v_subject_id and coalesce(s.is_active, true)
  ) then
    raise exception '请选择有效科目。';
  end if;
  if not exists (
    select 1 from public.school_business_entities b
    where b.id = v_planned.business_entity_id and coalesce(b.is_active, true)
  ) then
    raise exception '来源业务归属无效。';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id = v_planned.student_id
      and s.app_type = 'school'
      and coalesce(s.status, 'active') not in ('inactive', 'graduated')
      and (s.business_entity_id is null or s.business_entity_id = v_planned.business_entity_id)
  ) then
    raise exception '来源学生无效或业务归属不一致。';
  end if;
  if v_start_time is null or v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间必填且必须为 HH:MM。';
  end if;
  if v_end_time is null or v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间必填且必须为 HH:MM。';
  end if;
  if v_end_time::time <= v_start_time::time then
    raise exception '结束时间必须晚于开始时间。';
  end if;
  if v_content is null then
    raise exception '补课内容必填。';
  end if;
  if v_delivery_mode not in ('online', 'onsite') then
    raise exception '授课方式必须为 online 或 onsite。';
  end if;
  if v_delivery_mode = 'onsite' and v_venue not in ('Regus公共区', 'Regus办公室') then
    raise exception '线下补课场地只能为 Regus公共区 或 Regus办公室。请先在来源课时补齐场地。';
  end if;
  if p_lesson_count is not null and p_lesson_count <= 0 then
    raise exception '课次数必须大于 0。';
  end if;

  v_target_year_month := to_char(p_lesson_date, 'YYYY-MM');
  if exists (
    select 1 from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = v_target_year_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '补课实际日期所在学生月度结算已锁定。';
  end if;
  if exists (
    select 1 from public.school_teacher_wage_locks w
    where w.teacher_id = v_teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_target_year_month
      and w.status = 'locked'
  ) then
    raise exception '补课老师的目标工资月份已锁定。';
  end if;

  insert into public.school_lesson_records (
    lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, planned_lesson_id, unit_price,
    lesson_fee, lesson_count, actual_minutes, teacher_settlement_month,
    lesson_delivery_mode, lesson_venue
  ) values (
    'actual', p_lesson_date, v_target_year_month, v_planned.student_id,
    v_teacher_id, v_subject_id, v_planned.business_entity_id, v_start_time,
    v_end_time, p_duration_hours, v_content, 'makeup_completed', false,
    v_note, 'school', v_planned.id, coalesce(v_planned.unit_price, 0), 0,
    coalesce(p_lesson_count, v_planned.lesson_count), round(p_duration_hours * 60)::integer,
    v_target_year_month, v_delivery_mode, v_venue
  ) returning id into v_actual_id;

  if public.school_get_lesson_credit_remaining_hours(v_planned.id) <= 0 then
    update public.school_lesson_records
       set status = 'makeup_completed'
     where id = v_planned.id;
  end if;

  return query
  select a.* from public.school_lesson_records a where a.id = v_actual_id;
end;
$$;

comment on function public.school_create_lesson_credit_makeup_actual(uuid, date, uuid, uuid, text, text, numeric, text, text, integer, text, text) is
  'Creates a non-billable makeup_completed actual from an open pending_makeup planned credit. Student and business entity stay with the source; teacher and subject may change. The target actual month controls teacher wage settlement. Once the source credit is fully consumed, its planned status becomes makeup_completed. The source may be from an already locked month; the target student settlement and target teacher wage locks are guarded.';

revoke all on function public.school_get_lesson_credit_remaining_hours(uuid) from public;
grant execute on function public.school_get_lesson_credit_remaining_hours(uuid) to anon, authenticated, service_role;
revoke all on function public.school_create_lesson_credit_makeup_actual(uuid, date, uuid, uuid, text, text, numeric, text, text, integer, text, text) from public;
grant execute on function public.school_create_lesson_credit_makeup_actual(uuid, date, uuid, uuid, text, text, numeric, text, text, integer, text, text) to anon, authenticated, service_role;

create or replace function public.school_create_partial_completed_actual_from_planned(
  p_planned_lesson_id uuid,
  p_lesson_date date,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_lesson_content text,
  p_note text default null
)
returns setof public.school_lesson_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planned public.school_lesson_records%rowtype;
  v_target_year_month text;
  v_actual_id uuid;
  v_content text;
  v_note text;
begin
  if p_planned_lesson_id is null then
    raise exception '请选择预定课时。';
  end if;
  if p_lesson_date is null then
    raise exception '请选择实际完成日期。';
  end if;
  if p_duration_hours is null or p_duration_hours <= 0 then
    raise exception '实际完成时长必须大于 0。';
  end if;
  if p_start_time is null or p_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间必填且必须为 HH:MM。';
  end if;
  if p_end_time is null or p_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间必填且必须为 HH:MM。';
  end if;
  if p_end_time::time <= p_start_time::time then
    raise exception '结束时间必须晚于开始时间。';
  end if;

  select p.*
    into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
    and p.lesson_type = 'planned'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;
  if v_planned.voided_at is not null or v_planned.status <> 'planned' then
    raise exception '只有未处理的待上课预定课时可以登记部分完成。';
  end if;
  if p_duration_hours >= coalesce(v_planned.duration_hours, 0) then
    raise exception '部分完成时长必须小于原预定时长；完整上课请使用普通生成实际课时。';
  end if;
  if exists (
    select 1 from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该预定课时已有实际记录，不能再登记首次部分完成。';
  end if;
  if v_planned.student_id is null or v_planned.teacher_id is null
     or v_planned.subject_id is null or v_planned.business_entity_id is null then
    raise exception '预定课时缺少学生、老师、科目或业务归属。';
  end if;

  v_content := nullif(trim(coalesce(p_lesson_content, '')), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_content is null then
    raise exception '实际课时内容必填。';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id = v_planned.student_id
      and s.app_type = 'school'
      and coalesce(s.status, 'active') not in ('inactive', 'graduated')
      and (s.business_entity_id is null or s.business_entity_id = v_planned.business_entity_id)
  ) then
    raise exception '学生无效或业务归属不一致。';
  end if;
  if not exists (
    select 1 from public.school_teachers t
    where t.id = v_planned.teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;
  if not exists (
    select 1 from public.school_subjects s
    where s.id = v_planned.subject_id and coalesce(s.is_active, true)
  ) then
    raise exception '科目无效或已停用。';
  end if;
  if not exists (
    select 1 from public.school_business_entities b
    where b.id = v_planned.business_entity_id and coalesce(b.is_active, true)
  ) then
    raise exception '业务归属无效。';
  end if;

  v_target_year_month := to_char(p_lesson_date, 'YYYY-MM');
  if exists (
    select 1 from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = v_planned.year_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '来源学生月度结算已锁定，不能登记部分完成。';
  end if;
  if exists (
    select 1 from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_target_year_month
      and w.status = 'locked'
  ) then
    raise exception '实际完成老师的目标工资月份已锁定。';
  end if;

  insert into public.school_lesson_records (
    lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, planned_lesson_id, unit_price,
    lesson_fee, lesson_count, actual_minutes, teacher_settlement_month,
    lesson_delivery_mode, lesson_venue
  ) values (
    'actual', p_lesson_date, v_planned.year_month, v_planned.student_id,
    v_planned.teacher_id, v_planned.subject_id, v_planned.business_entity_id,
    p_start_time, p_end_time, p_duration_hours, v_content, 'completed',
    coalesce(v_planned.is_billable, true), v_note, 'school', v_planned.id,
    coalesce(v_planned.unit_price, 0), round(p_duration_hours * coalesce(v_planned.unit_price, 0)),
    v_planned.lesson_count, round(p_duration_hours * 60)::integer,
    v_target_year_month, v_planned.lesson_delivery_mode, v_planned.lesson_venue
  ) returning id into v_actual_id;

  update public.school_lesson_records
     set status = 'pending_makeup'
   where id = v_planned.id;

  return query
  select a.* from public.school_lesson_records a where a.id = v_actual_id;
end;
$$;

comment on function public.school_create_partial_completed_actual_from_planned(uuid, date, text, text, numeric, text, text) is
  'Creates one first completed actual shorter than its planned source and marks that source pending_makeup. The unfulfilled remainder becomes the source credit. This write is rejected for locked source student settlements and locked target teacher wage months.';

revoke all on function public.school_create_partial_completed_actual_from_planned(uuid, date, text, text, numeric, text, text) from public;
grant execute on function public.school_create_partial_completed_actual_from_planned(uuid, date, text, text, numeric, text, text) to anon, authenticated, service_role;

-- Compatibility wrappers keep the existing public signatures from becoming a
-- bypass. They intentionally ignore the legacy billable/fee inputs: all
-- lesson-credit makeup is now non-billable and may consume a source partially.
create or replace function public.school_create_makeup_completed_actual_lesson_from_planned(
  p_planned_lesson_id uuid,
  p_lesson_date date default null,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default null,
  p_unit_price numeric default null,
  p_lesson_fee numeric default null,
  p_is_billable boolean default true,
  p_lesson_count integer default null,
  p_lesson_content text default null,
  p_note text default null
)
returns table (
  lesson_id uuid, lesson_type text, lesson_date date, year_month text,
  student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid,
  start_time text, end_time text, duration_hours numeric, unit_price numeric,
  lesson_fee numeric, status text, is_billable boolean, lesson_count integer,
  actual_minutes integer, planned_lesson_id uuid, teacher_settlement_month text,
  lesson_content text, note text, created_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = public
as $$
begin
  return query
  select a.id, a.lesson_type, a.lesson_date, a.year_month, a.student_id,
    a.teacher_id, a.subject_id, a.business_entity_id, a.start_time, a.end_time,
    a.duration_hours, a.unit_price, a.lesson_fee, a.status, a.is_billable,
    a.lesson_count, a.actual_minutes, a.planned_lesson_id,
    a.teacher_settlement_month, a.lesson_content, a.note, a.created_at, a.updated_at
  from public.school_create_lesson_credit_makeup_actual(
    p_planned_lesson_id, p_lesson_date, null, null, p_start_time, p_end_time,
    p_duration_hours, p_lesson_content, p_note, p_lesson_count, null, null
  ) a;
end;
$$;

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
  lesson_id uuid, lesson_type text, lesson_date date, year_month text,
  student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid,
  start_time text, end_time text, duration_hours numeric, unit_price numeric,
  lesson_fee numeric, status text, is_billable boolean, lesson_count integer,
  actual_minutes integer, planned_lesson_id uuid, teacher_settlement_month text,
  lesson_content text, note text, created_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = public
as $$
begin
  return query
  select a.id, a.lesson_type, a.lesson_date, a.year_month, a.student_id,
    a.teacher_id, a.subject_id, a.business_entity_id, a.start_time, a.end_time,
    a.duration_hours, a.unit_price, a.lesson_fee, a.status, a.is_billable,
    a.lesson_count, a.actual_minutes, a.planned_lesson_id,
    a.teacher_settlement_month, a.lesson_content, a.note, a.created_at, a.updated_at
  from public.school_create_lesson_credit_makeup_actual(
    p_planned_lesson_id, p_lesson_date, null, null, p_start_time, p_end_time,
    p_duration_hours, p_lesson_content, p_note, p_lesson_count, null, null
  ) a;
end;
$$;

comment on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) is
  'Compatibility wrapper for school_create_lesson_credit_makeup_actual. Legacy fee and billable inputs are ignored; makeup is always non-billable student lesson-credit consumption.';
comment on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) is
  'Compatibility wrapper for school_create_lesson_credit_makeup_actual. Legacy fee and billable inputs are ignored; makeup may be cross-month and is always non-billable student lesson-credit consumption.';

revoke all on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) from public;
grant execute on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) to anon, authenticated, service_role;
revoke all on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) from public;
grant execute on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid, date, text, text, numeric, numeric, numeric, boolean, integer, text, text) to anon, authenticated, service_role;
