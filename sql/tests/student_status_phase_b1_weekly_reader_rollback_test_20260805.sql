-- Phase B1 rollback-only deployment rehearsal and weekly reader matrix.
-- All written rows use fixed b101-b104 UUIDs and codex-test markers.
-- The replacement function and every fixture row are rolled back.
\set ON_ERROR_STOP on
\pset pager off

begin;

\ir ../current/school_student_status_phase_b1_weekly_reader_deploy_20260805.sql

do $phase_b1_test$
declare
  v_be uuid;
  v_teacher uuid;
  v_subject uuid;
  v_actor uuid;
  v_row record;
  v_before jsonb;
  v_after jsonb;
  v_target_count integer;
begin
  select id into v_be
  from public.school_business_entities
  where coalesce(is_active, true)
  order by created_at, id
  limit 1;

  select id, default_subject_id into v_teacher, v_subject
  from public.school_teachers
  where app_type = 'school'
    and coalesce(status, 'active') not in ('inactive', 'retired')
    and default_subject_id is not null
  order by created_at, id
  limit 1;

  select user_id into v_actor
  from public.school_app_memberships
  where role = 'admin' and is_active
  order by created_at, user_id
  limit 1;

  if v_be is null or v_teacher is null or v_subject is null or v_actor is null then
    raise exception 'PHASE_B1_FIXTURE_PREREQUISITE_MISSING';
  end if;

  insert into public.school_students (
    id, name, status, app_type, business_entity_id, note
  ) values
    ('b1010000-0000-4000-8000-000000000011', 'codex-test-b1-active', 'active', 'school', v_be, 'codex-test phase-b1 rollback'),
    ('b1010000-0000-4000-8000-000000000012', 'codex-test-b1-paused', 'paused', 'school', v_be, 'codex-test phase-b1 rollback'),
    ('b1010000-0000-4000-8000-000000000013', 'codex-test-b1-left', 'withdrawn', 'school', v_be, 'codex-test phase-b1 rollback'),
    ('b1010000-0000-4000-8000-000000000014', 'codex-test-b1-legacy-no-event', 'graduated', 'school', v_be, 'codex-test phase-b1 rollback');

  insert into public.school_student_status_events (
    id, student_id, effective_month, status, reason, row_version,
    created_by_user_id, created_by_membership_id
  ) values
    ('b1040000-0000-4000-8000-000000000012', 'b1010000-0000-4000-8000-000000000012', '2025-07-01', 'paused',
      'codex-test phase-b1 paused event', 'b1040000-0000-4000-8000-000000000112', v_actor, v_actor),
    ('b1040000-0000-4000-8000-000000000013', 'b1010000-0000-4000-8000-000000000013', '2025-07-01', 'left',
      'codex-test phase-b1 left event', 'b1040000-0000-4000-8000-000000000113', v_actor, v_actor);

  insert into public.school_lesson_records (
    id, lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, app_type, unit_price, lesson_fee, lesson_count,
    lesson_delivery_mode, lesson_venue, note
  ) values
    ('b1020000-0000-4000-8000-000000000011', 'planned', '2025-06-30', '2025-06', 'b1010000-0000-4000-8000-000000000011', v_teacher, v_subject, v_be, '10:00', '12:00', 2, 'codex-test active planned', 'planned', true, 'school', 1000, 2000, 1, 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1020000-0000-4000-8000-000000000012', 'planned', '2025-07-02', '2025-07', 'b1010000-0000-4000-8000-000000000012', v_teacher, v_subject, v_be, '10:00', '12:00', 2, 'codex-test paused planned', 'planned', true, 'school', 1000, 2000, 1, 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1020000-0000-4000-8000-000000000013', 'planned', '2025-07-01', '2025-07', 'b1010000-0000-4000-8000-000000000013', v_teacher, v_subject, v_be, '13:00', '15:00', 2, 'codex-test left planned', 'planned', true, 'school', 1000, 2000, 1, 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1020000-0000-4000-8000-000000000014', 'planned', '2025-07-03', '2025-07', 'b1010000-0000-4000-8000-000000000014', v_teacher, v_subject, v_be, '15:00', '17:00', 2, 'codex-test legacy planned', 'planned', true, 'school', 1000, 2000, 1, 'online', 'Zoom', 'codex-test phase-b1 rollback');

  insert into public.school_lesson_records (
    id, lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, app_type, unit_price, lesson_fee, lesson_count,
    planned_lesson_id, teacher_settlement_month, lesson_delivery_mode,
    lesson_venue, note
  ) values
    ('b1030000-0000-4000-8000-000000000011', 'actual', '2025-06-30', '2025-06', 'b1010000-0000-4000-8000-000000000011', v_teacher, v_subject, v_be, '10:00', '12:00', 2, 'codex-test completed actual', 'completed', true, 'school', 1000, 2000, 1, 'b1020000-0000-4000-8000-000000000011', '2025-06', 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1030000-0000-4000-8000-000000000012', 'actual', '2025-07-02', '2025-07', 'b1010000-0000-4000-8000-000000000012', v_teacher, v_subject, v_be, '10:00', '12:00', 2, 'codex-test paused completed actual', 'completed', true, 'school', 1000, 2000, 1, 'b1020000-0000-4000-8000-000000000012', '2025-07', 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1030000-0000-4000-8000-000000000013', 'actual', '2025-07-01', '2025-07', 'b1010000-0000-4000-8000-000000000013', v_teacher, v_subject, v_be, '13:00', '15:00', 2, 'codex-test left cancelled actual', 'cancelled', true, 'school', 1000, 2000, 1, 'b1020000-0000-4000-8000-000000000013', '2025-07', 'online', 'Zoom', 'codex-test phase-b1 rollback'),
    ('b1030000-0000-4000-8000-000000000014', 'actual', '2025-07-03', '2025-07', 'b1010000-0000-4000-8000-000000000014', v_teacher, v_subject, v_be, '15:00', '17:00', 2, 'codex-test legacy makeup actual', 'makeup_completed', false, 'school', 0, 0, 1, 'b1020000-0000-4000-8000-000000000014', '2025-07', 'online', 'Zoom', 'codex-test phase-b1 rollback');

  select count(*) into v_target_count
  from public.school_get_weekly_lesson_operations('2025-06-30') w
  where w.student_id in (
    'b1010000-0000-4000-8000-000000000011',
    'b1010000-0000-4000-8000-000000000012',
    'b1010000-0000-4000-8000-000000000013',
    'b1010000-0000-4000-8000-000000000014'
  );
  if v_target_count <> 4 then
    raise exception 'PHASE_B1_DUPLICATE_OR_MISSING_ROWS: %', v_target_count;
  end if;

  select * into v_row from public.school_get_weekly_lesson_operations('2025-06-30')
  where student_id = 'b1010000-0000-4000-8000-000000000011';
  if v_row.business_entity_id is distinct from v_be or v_row.weekly_planned_count <> 1
     or v_row.weekly_planned_hours <> 2 or v_row.weekly_registered_count <> 1
     or v_row.weekly_completed_hours <> 2 or v_row.weekly_cancelled_count <> 0 then
    raise exception 'PHASE_B1_ACTIVE_AGGREGATE_MISMATCH: %', to_jsonb(v_row);
  end if;

  select * into v_row from public.school_get_weekly_lesson_operations('2025-06-30')
  where student_id = 'b1010000-0000-4000-8000-000000000012';
  if v_row.business_entity_id is distinct from v_be or v_row.weekly_planned_count <> 1
     or v_row.weekly_planned_hours <> 2 or v_row.weekly_registered_count <> 1
     or v_row.weekly_completed_hours <> 2 or v_row.weekly_cancelled_count <> 0 then
    raise exception 'PHASE_B1_PAUSED_AGGREGATE_MISMATCH: %', to_jsonb(v_row);
  end if;

  select * into v_row from public.school_get_weekly_lesson_operations('2025-06-30')
  where student_id = 'b1010000-0000-4000-8000-000000000013';
  if v_row.business_entity_id is distinct from v_be or v_row.weekly_planned_count <> 1
     or v_row.weekly_planned_hours <> 2 or v_row.weekly_registered_count <> 1
     or v_row.weekly_completed_hours <> 0 or v_row.weekly_cancelled_count <> 1 then
    raise exception 'PHASE_B1_LEFT_CANCELLED_AGGREGATE_MISMATCH: %', to_jsonb(v_row);
  end if;

  select * into v_row from public.school_get_weekly_lesson_operations('2025-06-30')
  where student_id = 'b1010000-0000-4000-8000-000000000014';
  if v_row.business_entity_id is distinct from v_be or v_row.weekly_planned_count <> 1
     or v_row.weekly_planned_hours <> 2 or v_row.weekly_registered_count <> 1
     or v_row.weekly_completed_hours <> 2 or v_row.weekly_cancelled_count <> 0 then
    raise exception 'PHASE_B1_LEGACY_MAKEUP_AGGREGATE_MISMATCH: %', to_jsonb(v_row);
  end if;

  select to_jsonb(w) into v_before
  from public.school_get_weekly_lesson_operations('2025-06-30') w
  where w.student_id = 'b1010000-0000-4000-8000-000000000011';

  insert into public.school_student_status_events (
    id, student_id, effective_month, status, reason, row_version,
    created_by_user_id, created_by_membership_id
  ) values (
    'b1040000-0000-4000-8000-000000000011', 'b1010000-0000-4000-8000-000000000011',
    '2025-07-01', 'paused', 'codex-test phase-b1 active-to-paused',
    'b1040000-0000-4000-8000-000000000111', v_actor, v_actor
  );

  select to_jsonb(w) into v_after
  from public.school_get_weekly_lesson_operations('2025-06-30') w
  where w.student_id = 'b1010000-0000-4000-8000-000000000011';
  if v_before is distinct from v_after then
    raise exception 'PHASE_B1_STATUS_EVENT_CHANGED_HISTORY: before=% after=%', v_before, v_after;
  end if;

  select count(*) into v_target_count
  from public.school_get_weekly_lesson_operations('2025-12-01') w
  where w.student_id in (
    'b1010000-0000-4000-8000-000000000011',
    'b1010000-0000-4000-8000-000000000012',
    'b1010000-0000-4000-8000-000000000013',
    'b1010000-0000-4000-8000-000000000014'
  ) and (
    w.weekly_planned_count <> 0 or w.weekly_planned_hours <> 0
    or w.weekly_registered_count <> 0 or w.weekly_completed_hours <> 0
    or w.weekly_cancelled_count <> 0
  );
  if v_target_count <> 0 then
    raise exception 'PHASE_B1_EMPTY_WEEK_NONZERO_RESULTS: %', v_target_count;
  end if;

  if exists (
    select 1
    from public.school_get_weekly_lesson_operations('2025-06-30') w
    where w.student_id in (
      'b1010000-0000-4000-8000-000000000011',
      'b1010000-0000-4000-8000-000000000012',
      'b1010000-0000-4000-8000-000000000013',
      'b1010000-0000-4000-8000-000000000014'
    ) and (w.overdue_unregistered_count <> 0 or w.upcoming_unregistered_count <> 0)
  ) then
    raise exception 'PHASE_B1_REGISTRATION_CLASSIFICATION_CHANGED';
  end if;
end;
$phase_b1_test$;

select md5(pg_get_functiondef('public.school_get_weekly_lesson_operations(date)'::regprocedure))
  as rehearsed_function_md5;

rollback;

do $phase_b1_residue$
begin
  if exists (select 1 from public.school_students where id::text like 'b1010000-%')
     or exists (select 1 from public.school_lesson_records where id::text like 'b1020000-%' or id::text like 'b1030000-%')
     or exists (select 1 from public.school_student_status_events where id::text like 'b1040000-%') then
    raise exception 'PHASE_B1_FIXTURE_RESIDUE';
  end if;
end;
$phase_b1_residue$;

select 'STUDENT_STATUS_PHASE_B1_WEEKLY_READER_ROLLBACK_PASS' result;
