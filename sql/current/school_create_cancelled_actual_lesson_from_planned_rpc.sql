-- School V2 canonical "cancel and move to pending makeup" writer.
-- Business-model expansion declaration:
--   new tables/columns/statuses/facts: none;
--   changed writer/mutability/time authority: exactly the 2026-08-06
--   cancellation hardening task sections II, IV, VIII, IX, X and XI.
-- This source changes one existing function and its ACL only. It performs no
-- historical data repair or backfill.
-- Phase B3 additionally removes frozen school_students.status from this
-- existing-fact fulfilment path, as explicitly approved by the 2026-08-06
-- student monthly-status writer-authority task. The Phase 20260806 permission,
-- DB-duration, zero-fee, lock, pending-makeup and concurrency contracts remain.

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
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_membership_role text;
  v_membership_active boolean;
  v_planned public.school_lesson_records%rowtype;
  v_lesson_date date;
  v_start_time text;
  v_end_time text;
  v_start_value time;
  v_end_value time;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_student_settlement_month text;
  v_teacher_settlement_month text;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
begin
  if v_actor is null then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_AUTH_REQUIRED';
  end if;

  select membership.role, membership.is_active
  into v_membership_role, v_membership_active
  from public.school_app_memberships membership
  where membership.user_id = v_actor;

  if not found then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_MEMBERSHIP_REQUIRED';
  end if;
  if v_membership_active is distinct from true then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_membership_role not in ('admin','operator') then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_ROLE_REQUIRED';
  end if;

  if p_planned_lesson_id is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_REQUIRED';
  end if;

  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);

  select planned.*
  into v_planned
  from public.school_lesson_records planned
  where planned.id = p_planned_lesson_id
    and planned.app_type = 'school'
  for update;

  if not found then
    raise exception using errcode='P0002', message='LESSON_CANCELLATION_SOURCE_NOT_FOUND';
  end if;
  if v_planned.lesson_type <> 'planned' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_TYPE_INVALID';
  end if;
  if v_planned.voided_at is not null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_VOIDED';
  end if;

  if exists (
    select 1
    from public.school_lesson_records actual
    where actual.app_type = 'school'
      and actual.lesson_type = 'actual'
      and actual.planned_lesson_id = v_planned.id
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS';
  end if;

  if v_planned.status <> 'planned' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_STATUS_INVALID';
  end if;
  if v_planned.student_id is null
     or v_planned.teacher_id is null
     or v_planned.subject_id is null
     or v_planned.business_entity_id is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_MASTER_REQUIRED';
  end if;

  v_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  if v_lesson_date is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_DATE_REQUIRED';
  end if;

  v_start_time := coalesce(
    nullif(trim(coalesce(p_start_time, '')), ''),
    nullif(trim(coalesce(v_planned.start_time, '')), '')
  );
  v_end_time := coalesce(
    nullif(trim(coalesce(p_end_time, '')), ''),
    nullif(trim(coalesce(v_planned.end_time, '')), '')
  );
  if v_start_time is null or v_end_time is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_REQUIRED';
  end if;
  if v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_START_TIME_INVALID';
  end if;
  if v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_END_TIME_INVALID';
  end if;

  v_start_value := v_start_time::time;
  v_end_value := v_end_time::time;
  if extract(minute from v_start_value)::integer % 15 <> 0
     or extract(minute from v_end_value)::integer % 15 <> 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_GRID_INVALID';
  end if;
  if v_end_value <= v_start_value then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_RANGE_INVALID';
  end if;

  v_start_time := to_char(v_start_value, 'HH24:MI');
  v_end_time := to_char(v_end_value, 'HH24:MI');
  v_duration_hours := extract(epoch from (v_end_value - v_start_value))::numeric / 3600;
  if p_duration_hours is not null
     and p_duration_hours is distinct from v_duration_hours then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_DURATION_MISMATCH';
  end if;

  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(
    nullif(trim(coalesce(p_lesson_content, '')), ''),
    v_planned.lesson_content
  );
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_unit_price < 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_UNIT_PRICE_INVALID';
  end if;
  if v_lesson_count is not null and v_lesson_count <= 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_COUNT_INVALID';
  end if;

  select student.business_entity_id
  into v_student_business_entity_id
  from public.school_students student
  where student.id = v_planned.student_id
    and student.app_type = 'school';

  if not found then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_STUDENT_INACTIVE';
  end if;
  if v_student_business_entity_id is not null
     and v_student_business_entity_id is distinct from v_planned.business_entity_id then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_STUDENT_ENTITY_MISMATCH';
  end if;
  if not exists (
    select 1
    from public.school_teachers teacher
    where teacher.id = v_planned.teacher_id
      and teacher.app_type = 'school'
      and coalesce(teacher.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TEACHER_INACTIVE';
  end if;
  if not exists (
    select 1
    from public.school_subjects subject
    where subject.id = v_planned.subject_id
      and coalesce(subject.is_active, true)
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SUBJECT_INACTIVE';
  end if;
  if not exists (
    select 1
    from public.school_business_entities entity
    where entity.id = v_planned.business_entity_id
      and coalesce(entity.is_active, true)
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_ENTITY_INACTIVE';
  end if;

  v_student_settlement_month :=
    public.school_resolve_r1d_e_c_lesson_student_month(v_planned.id);
  if v_student_settlement_month is null then
    raise exception using errcode='22023', message='LESSON_OPERATION_SCOPE_UNCLASSIFIED';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and public.school_tuition_p0a_consumed_bill_id(settlement.id) is not null
  ) then
    raise exception using errcode='P0001', message='LESSON_FINANCIAL_FACT_IMMUTABLE';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and settlement.settlement_status = 'locked'
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED';
  end if;

  v_teacher_settlement_month := to_char(v_lesson_date, 'YYYY-MM');
  if exists (
    select 1
    from public.school_teacher_wage_locks wage_lock
    where wage_lock.teacher_id = v_planned.teacher_id
      and wage_lock.business_entity_id is not distinct from v_planned.business_entity_id
      and wage_lock.settlement_month = v_teacher_settlement_month
      and wage_lock.status = 'locked'
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_TEACHER_WAGE_LOCKED';
  end if;

  insert into public.school_lesson_records (
    lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, planned_lesson_id, unit_price,
    lesson_fee, import_batch_id, import_source, imported_at, lesson_count,
    actual_minutes, teacher_settlement_month
  ) values (
    'actual', v_lesson_date, v_planned.year_month, v_planned.student_id,
    v_planned.teacher_id, v_planned.subject_id, v_planned.business_entity_id,
    v_start_time, v_end_time, v_duration_hours, v_lesson_content, 'cancelled',
    false, v_note, 'school', v_planned.id, v_unit_price, 0, null, null, null,
    v_lesson_count, 0, v_teacher_settlement_month
  ) returning id into v_actual_id;

  update public.school_lesson_records
  set status = 'pending_makeup'
  where id = v_planned.id;

  return query
  select
    actual.id, actual.lesson_type, actual.lesson_date, actual.year_month,
    actual.student_id, actual.teacher_id, actual.subject_id,
    actual.business_entity_id, actual.start_time, actual.end_time,
    actual.duration_hours, actual.unit_price, actual.lesson_fee, actual.status,
    actual.is_billable, actual.lesson_count, actual.actual_minutes,
    actual.planned_lesson_id, actual.teacher_settlement_month,
    actual.lesson_content, actual.note, actual.created_at, actual.updated_at
  from public.school_lesson_records actual
  where actual.id = v_actual_id;
end;
$function$;

revoke all on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) from public, anon, authenticated, service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) to authenticated;

comment on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) is
  'Canonical interactive cancellation writer. Active admin/operator only. Creates one non-billable cancelled actual and atomically moves the planned source to pending_makeup. DB validates the time range and saves DB-derived duration; permanently consumed tuition settlements, locked settlement/wage scopes, active P0F claims and linked actuals remain immutable.';
