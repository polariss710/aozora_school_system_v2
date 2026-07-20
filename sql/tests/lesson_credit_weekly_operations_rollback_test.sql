-- Whitelist rollback test only. Every inserted row is marked codex-test and
-- this script ends in ROLLBACK. It never selects, updates, or deletes real
-- business lesson/settlement/wage data.

begin;

do $$
declare
  v_be uuid;
  v_partial_actual uuid;
  v_makeup_actual uuid;
  v_cancelled_actual uuid;
  v_remaining numeric;
  v_credit_hours numeric;
  v_weekly_count bigint;
begin
  select id into v_be
  from public.school_business_entities
  where coalesce(is_active, true)
  order by created_at, id
  limit 1;
  if v_be is null then
    raise exception 'rollback test requires one active business entity';
  end if;

  insert into public.school_subjects (id, name, category, note)
  values
    ('97000000-0000-0000-0000-000000000011', 'codex-test-lesson-credit-subject-a', '测试', 'codex-test lesson-credit rollback'),
    ('97000000-0000-0000-0000-000000000012', 'codex-test-lesson-credit-subject-b', '测试', 'codex-test lesson-credit rollback');
  insert into public.school_teachers (id, name, status, app_type, default_subject_id, default_business_entity_id, note)
  values
    ('97000000-0000-0000-0000-000000000021', 'codex-test-lesson-credit-teacher-a', 'active', 'school', '97000000-0000-0000-0000-000000000011', v_be, 'codex-test lesson-credit rollback'),
    ('97000000-0000-0000-0000-000000000022', 'codex-test-lesson-credit-teacher-b', 'active', 'school', '97000000-0000-0000-0000-000000000012', v_be, 'codex-test lesson-credit rollback');
  insert into public.school_students (id, name, status, app_type, business_entity_id, note)
  values ('97000000-0000-0000-0000-000000000031', 'codex-test-lesson-credit-student', 'active', 'school', v_be, 'codex-test lesson-credit rollback');

  insert into public.school_lesson_records (
    id, lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, app_type, unit_price, lesson_fee, lesson_count,
    lesson_delivery_mode, lesson_venue, note
  ) values (
    '97000000-0000-0000-0000-000000000101', 'planned', '2027-10-02', '2027-10',
    '97000000-0000-0000-0000-000000000031', '97000000-0000-0000-0000-000000000021',
    '97000000-0000-0000-0000-000000000011', v_be, '10:00', '13:00', 3,
    'codex-test source partial', 'planned', true, 'school', 1000, 3000, 1,
    'online', 'Zoom', 'codex-test lesson-credit rollback'
  ), (
    '97000000-0000-0000-0000-000000000102', 'planned', '2027-10-04', '2027-10',
    '97000000-0000-0000-0000-000000000031', '97000000-0000-0000-0000-000000000021',
    '97000000-0000-0000-0000-000000000011', v_be, '14:00', '15:30', 1.5,
    'codex-test source cancel', 'planned', true, 'school', 1000, 1500, 2,
    'online', 'Zoom', 'codex-test lesson-credit rollback'
  );

  select a.id into v_partial_actual
  from public.school_create_partial_completed_actual_from_planned(
    '97000000-0000-0000-0000-000000000101', '2027-10-02', '10:00', '12:00', 2,
    'codex-test partial completed', 'codex-test lesson-credit rollback'
  ) a;
  if v_partial_actual is null then raise exception 'partial actual missing'; end if;
  select public.school_get_lesson_credit_remaining_hours('97000000-0000-0000-0000-000000000101') into v_remaining;
  if v_remaining <> 1 then raise exception 'expected 1 remaining hour, got %', v_remaining; end if;

  select a.id into v_makeup_actual
  from public.school_create_lesson_credit_makeup_actual(
    '97000000-0000-0000-0000-000000000101', '2027-11-03',
    '97000000-0000-0000-0000-000000000022', '97000000-0000-0000-0000-000000000012',
    '10:00', '11:00', 1, 'codex-test switched teacher subject makeup',
    'codex-test lesson-credit rollback', 1, 'online', 'Zoom'
  ) a;
  if not exists (
    select 1 from public.school_lesson_records a
    where a.id = v_makeup_actual and a.student_id = '97000000-0000-0000-0000-000000000031'
      and a.business_entity_id = v_be and a.teacher_id = '97000000-0000-0000-0000-000000000022'
      and a.subject_id = '97000000-0000-0000-0000-000000000012'
      and a.year_month = '2027-11' and a.teacher_settlement_month = '2027-11'
      and a.is_billable = false and a.lesson_fee = 0 and a.status = 'makeup_completed'
  ) then raise exception 'switched makeup result mismatch'; end if;

  select lesson_id into v_cancelled_actual
  from public.school_create_cancelled_actual_lesson_from_planned(
    '97000000-0000-0000-0000-000000000102', '2027-10-04', '14:00', '15:30',
    1.5, 1000, 2, 'codex-test cancelled', 'codex-test lesson-credit rollback'
  );
  if v_cancelled_actual is null then raise exception 'cancelled actual missing'; end if;
  select open_credit_hours into v_credit_hours
  from public.school_list_student_lesson_credit_balances('97000000-0000-0000-0000-000000000031');
  if v_credit_hours <> 1.5 then raise exception 'expected 1.5 open cancelled credit, got %', v_credit_hours; end if;
  select weekly_planned_count into v_weekly_count
  from public.school_get_weekly_lesson_operations('2027-09-27')
  where student_id = '97000000-0000-0000-0000-000000000031';
  if v_weekly_count <> 1 then raise exception 'expected one weekly planned source, got %', v_weekly_count; end if;
end;
$$;

\if :{?lesson_credit_commit_test}
  -- Commit-test cleanup is intentionally restricted to the three fixed
  -- codex-test master ids and their dependent lesson rows.
  delete from public.school_lesson_records
  where student_id = '97000000-0000-0000-0000-000000000031';
  delete from public.school_students
  where id = '97000000-0000-0000-0000-000000000031'
    and note = 'codex-test lesson-credit rollback';
  delete from public.school_teachers
  where id in ('97000000-0000-0000-0000-000000000021', '97000000-0000-0000-0000-000000000022')
    and note = 'codex-test lesson-credit rollback';
  delete from public.school_subjects
  where id in ('97000000-0000-0000-0000-000000000011', '97000000-0000-0000-0000-000000000012')
    and note = 'codex-test lesson-credit rollback';
  commit;
\else
  rollback;
\endif
