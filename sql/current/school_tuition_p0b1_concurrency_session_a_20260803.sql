-- P0-B1 concurrency session A. Required p0b1_scenario.
-- generate_edit | generate_void | generate_actual | settlement_actual |
-- duplicate_actual | edit_actual
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

do $a$
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
  v_preview record;
  v_result record;
  v_updated timestamptz;
begin
  if v_scenario in ('generate_edit','generate_void','generate_actual') then
    select * into strict v_preview
    from public.school_get_student_tuition_validation_preview_details(v_student,'2020-06',0.05);
    select * into strict v_result
    from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2020-06',0.05,v_preview.generation_manifest_sha256,v_marker,null);
    if v_result.idempotent then raise exception 'P0B1_A_UNEXPECTED_IDEMPOTENT'; end if;
  elsif v_scenario='settlement_actual' then
    perform * from public.school_lock_student_monthly_settlement(v_student,'2020-06',v_marker);
  elsif v_scenario='duplicate_actual' then
    perform * from public.school_create_actual_lesson_from_planned(
      v_lesson2,'2020-06-17','15:00','17:00',2,10000,1,2,v_marker,v_marker);
  elsif v_scenario='edit_actual' then
    select updated_at into strict v_updated from public.school_lesson_records where id=v_lesson3;
    perform * from public.school_update_lesson_record_guarded(
      v_lesson3,v_updated,'2020-06-24',v_student,v_teacher,v_subject,v_entity,
      '15:00','17:00',2,10000,1,'planned',true,2,v_marker,v_marker);
  else
    raise exception 'P0B1_SCENARIO_INVALID: %',v_scenario;
  end if;
  raise notice 'P0B1_SESSION_A_LOCK_HELD scenario=% pid=%',v_scenario,pg_backend_pid();
  perform pg_sleep(5);
end
$a$;
rollback;
select :'p0b1_scenario' scenario,'A_ROLLED_BACK' result;
