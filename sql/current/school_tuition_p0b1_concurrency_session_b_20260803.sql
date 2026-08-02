-- P0-B1 concurrency session B. Starts after session A holds the scope.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0b1_scenario}
\else
  \echo 'P0B1_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='15s';
set local statement_timeout='120s';
select set_config('tuition.p0b1_scenario',:'p0b1_scenario',true);

do $b$
declare
  v_scenario constant text:=current_setting('tuition.p0b1_scenario');
  v_marker constant text:='codex-test tuition-p0b1-lesson-authority-20260803';
  v_student constant uuid:='b1b10000-0000-4000-8000-00000000a100';
  v_entity constant uuid:='b1b10000-0000-4000-8000-00000000e100';
  v_teacher constant uuid:='b1b10000-0000-4000-8000-000000007100';
  v_subject constant uuid:='b1b10000-0000-4000-8000-00000000d100';
  v_lesson1 constant uuid:='b1b10000-0000-4000-8000-000000001101';
  v_lesson2 constant uuid:='b1b10000-0000-4000-8000-000000001102';
  v_lesson3 constant uuid:='b1b10000-0000-4000-8000-000000001103';
  v_updated timestamptz;
  v_started timestamptz:=clock_timestamp();
  v_elapsed numeric;
begin
  if v_scenario='generate_edit' then
    select updated_at into strict v_updated from public.school_lesson_records where id=v_lesson1;
    perform * from public.school_update_lesson_record_guarded(
      v_lesson1,v_updated,'2020-06-10',v_student,v_teacher,v_subject,v_entity,
      '15:00','17:00',2,10000,1,'planned',true,2,v_marker,v_marker);
  elsif v_scenario='generate_void' then
    select updated_at into strict v_updated from public.school_lesson_records where id=v_lesson1;
    perform * from public.school_void_planned_lesson(v_lesson1,v_updated,v_marker);
  elsif v_scenario in ('generate_actual','settlement_actual','duplicate_actual') then
    perform * from public.school_create_actual_lesson_from_planned(
      v_lesson2,'2020-06-17','15:00','17:00',2,10000,1,2,v_marker,v_marker);
  elsif v_scenario='edit_actual' then
    perform * from public.school_create_actual_lesson_from_planned(
      v_lesson3,'2020-06-24','15:00','17:00',2,10000,1,2,v_marker,v_marker);
  else
    raise exception 'P0B1_SCENARIO_INVALID: %',v_scenario;
  end if;
  v_elapsed:=extract(epoch from clock_timestamp()-v_started);
  if v_elapsed<3 then
    raise exception 'P0B1_EXPECTED_BLOCKING_MISSING: scenario=% elapsed=%',v_scenario,v_elapsed;
  end if;
  raise notice 'P0B1_SESSION_B_BLOCKED_THEN_COMPLETED scenario=% elapsed_seconds=% pid=%',
    v_scenario,round(v_elapsed,3),pg_backend_pid();
end
$b$;
rollback;
select :'p0b1_scenario' scenario,'B_ROLLED_BACK_NO_PARTIAL_WRITE' result;
