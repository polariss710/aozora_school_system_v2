-- school_cleanup_single_entity_default_student_20260713.sql
-- Guarded one-time cleanup for two confirmed whitelist-test rows:
-- - student f8db8d17-6a14-4f5b-9a21-2ac5f3b8c0af
-- - planned lesson fdbae3f3-a6e3-42a1-9639-47232e742963
-- Default execution rolls back. Pass -v cleanup_commit=1 only for the authorized cleanup.

\if :{?cleanup_commit}
\else
  \set cleanup_commit 0
\endif

begin;

do $$
declare
  v_student_id constant uuid := 'f8db8d17-6a14-4f5b-9a21-2ac5f3b8c0af'::uuid;
  v_lesson_id constant uuid := 'fdbae3f3-a6e3-42a1-9639-47232e742963'::uuid;
  v_business_entity_id constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid;
  v_teacher_id constant uuid := 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid;
  v_subject_id constant uuid := '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid;
  v_student public.school_students%rowtype;
  v_lesson public.school_lesson_records%rowtype;
  r record;
  v_count bigint;
  v_deleted_count integer;
begin
  select *
    into v_student
  from public.school_students
  where id = v_student_id
  for update;

  if not found
     or v_student.name <> 'codex-test-single-entity-default-student-20260713'
     or v_student.display_name <> 'codex-test-single-entity-default-student-20260713'
     or v_student.note <> 'codex-test single business entity commit smoke'
     or v_student.app_type <> 'school'
     or v_student.business_entity_id is distinct from v_business_entity_id
     or v_student.status <> 'active'
     or v_student.previous_balance_cny <> 0
     or v_student.preset_exchange_rate <> 0 then
    raise exception 'target student does not match the approved whitelist cleanup fingerprint';
  end if;

  select *
    into v_lesson
  from public.school_lesson_records
  where id = v_lesson_id
  for update;

  if not found
     or v_lesson.student_id is distinct from v_student_id
     or v_lesson.business_entity_id is distinct from v_business_entity_id
     or v_lesson.teacher_id is distinct from v_teacher_id
     or v_lesson.subject_id is distinct from v_subject_id
     or v_lesson.note <> 'codex-test-v10.3.75-venue-commit'
     or v_lesson.lesson_content <> 'codex-test venue commit lesson'
     or v_lesson.lesson_type <> 'planned'
     or v_lesson.status <> 'planned'
     or v_lesson.year_month <> '2027-08'
     or v_lesson.lesson_date <> date '2027-08-09'
     or v_lesson.start_time <> '09:00'
     or v_lesson.end_time <> '10:00'
     or v_lesson.duration_hours <> 1
     or v_lesson.actual_minutes is not null
     or v_lesson.lesson_fee <> 0
     or v_lesson.unit_price <> 0
     or v_lesson.planned_lesson_id is not null
     or v_lesson.voided_at is not null then
    raise exception 'target lesson does not match the approved whitelist cleanup fingerprint';
  end if;

  for r in
    select c.table_schema, c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema
     and t.table_name = c.table_name
    where c.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and c.data_type = 'uuid'
    order by c.table_name, c.ordinal_position
  loop
    execute format(
      'select count(*) from %I.%I where %I = $1',
      r.table_schema,
      r.table_name,
      r.column_name
    )
    into v_count
    using v_student_id;

    if v_count > 0 and not (
      (r.table_name = 'school_students' and r.column_name = 'id' and v_count = 1)
      or (r.table_name = 'school_lesson_records' and r.column_name = 'student_id' and v_count = 1)
    ) then
      raise exception 'unexpected student UUID reference: %.% column %, count %', r.table_schema, r.table_name, r.column_name, v_count;
    end if;
  end loop;

  for r in
    select c.table_schema, c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema
     and t.table_name = c.table_name
    where c.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and c.data_type = 'uuid'
    order by c.table_name, c.ordinal_position
  loop
    execute format(
      'select count(*) from %I.%I where %I = $1',
      r.table_schema,
      r.table_name,
      r.column_name
    )
    into v_count
    using v_lesson_id;

    if v_count > 0 and not (
      r.table_name = 'school_lesson_records'
      and r.column_name = 'id'
      and v_count = 1
    ) then
      raise exception 'unexpected lesson UUID reference: %.% column %, count %', r.table_schema, r.table_name, r.column_name, v_count;
    end if;
  end loop;

  select count(*)
    into v_count
  from public.school_students
  where name = 'codex-test-single-entity-default-student-20260713'
     or display_name = 'codex-test-single-entity-default-student-20260713';

  if v_count <> 1 then
    raise exception 'expected exactly one student marker row, found %', v_count;
  end if;

  select count(*)
    into v_count
  from public.school_lesson_records
  where note = 'codex-test-v10.3.75-venue-commit'
     or lesson_content = 'codex-test venue commit lesson';

  if v_count <> 1 then
    raise exception 'expected exactly one lesson marker row, found %', v_count;
  end if;

  delete from public.school_lesson_records
  where id = v_lesson_id
    and student_id = v_student_id
    and note = 'codex-test-v10.3.75-venue-commit'
    and lesson_content = 'codex-test venue commit lesson';

  get diagnostics v_deleted_count = row_count;
  if v_deleted_count <> 1 then
    raise exception 'expected exactly one lesson delete, deleted %', v_deleted_count;
  end if;

  delete from public.school_students
  where id = v_student_id
    and name = 'codex-test-single-entity-default-student-20260713'
    and display_name = 'codex-test-single-entity-default-student-20260713'
    and note = 'codex-test single business entity commit smoke';

  get diagnostics v_deleted_count = row_count;
  if v_deleted_count <> 1 then
    raise exception 'expected exactly one student delete, deleted %', v_deleted_count;
  end if;
end $$;

select
  (select count(*) from public.school_students where id = 'f8db8d17-6a14-4f5b-9a21-2ac5f3b8c0af'::uuid) as student_remaining_count,
  (select count(*) from public.school_lesson_records where id = 'fdbae3f3-a6e3-42a1-9639-47232e742963'::uuid) as lesson_remaining_count,
  (select count(*) from public.school_students where name = 'codex-test-single-entity-default-student-20260713' or display_name = 'codex-test-single-entity-default-student-20260713') as student_marker_remaining_count,
  (select count(*) from public.school_lesson_records where note = 'codex-test-v10.3.75-venue-commit' or lesson_content = 'codex-test venue commit lesson') as lesson_marker_remaining_count;

\if :cleanup_commit
  commit;
\else
  rollback;
\endif
