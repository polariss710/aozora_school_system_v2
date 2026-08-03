-- P0-B2 concurrency session B. Starts while matching A holds the shared scope.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0b2_scenario}
\else
  \echo 'P0B2_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='15s';
set local statement_timeout='120s';
select set_config('tuition.p0b2_scenario',:'p0b2_scenario',true);
do $b$
declare
  v_scenario constant text:=current_setting('tuition.p0b2_scenario');
  v_marker constant text:='codex-test tuition-p0b2-concurrency-20260803';
  v_student constant uuid:='b1b10000-0000-4000-8000-00000000a100';
  v_lesson1 constant uuid:='b1b10000-0000-4000-8000-000000001101';
  v_lesson2 constant uuid:='b1b10000-0000-4000-8000-000000001102';
  v_teacher constant uuid:='b1b10000-0000-4000-8000-000000007100';
  v_subject constant uuid:='b1b10000-0000-4000-8000-00000000d100';
  v_entity constant uuid:='b1b10000-0000-4000-8000-00000000e100';
  v_updated timestamptz;
  v_preview record;
  v_result record;
  v_started timestamptz:=clock_timestamp();
  v_elapsed numeric;
begin
  if v_scenario in ('draft_edit','preview_edit') then
    select updated_at into strict v_updated
    from public.school_lesson_records where id=v_lesson1;
    perform * from public.school_update_lesson_record_guarded(
      v_lesson1,v_updated,'2020-06-10',v_student,v_teacher,v_subject,v_entity,
      '15:00','17:00',2,10000,1,'planned',true,2,v_marker,
      'codex-test tuition-p0b1-lesson-authority-20260803');
  elsif v_scenario='draft_actual' then
    perform * from public.school_create_actual_lesson_from_planned(
      v_lesson2,'2020-06-17','15:00','17:00',2,10000,1,2,v_marker,v_marker);
  elsif v_scenario='draft_lock' then
    perform * from public.school_lock_student_monthly_settlement(
      v_student,'2020-06',v_marker);
  elsif v_scenario='lock_generate' then
    select * into strict v_preview
    from public.school_get_student_tuition_validation_preview_details(
      v_student,'2020-06',0.05);
    select * into strict v_result
    from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2020-06',0.05,v_preview.generation_manifest_sha256,v_marker,null);
    if v_result.idempotent then raise exception 'P0B2_B_UNEXPECTED_IDEMPOTENT'; end if;
  elsif v_scenario='draft_pair' then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',2.345,'manual_adjustment',v_marker,v_marker);
  elsif v_scenario='unlock_draft' then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  elsif v_scenario='source_change_lock' then
    select * into strict v_preview
    from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
    if v_preview.final_due_cny<>3200 or v_preview.adjustment_amount_cny<>-3200
       or v_preview.locked_carryover_cny<>0 then
      raise exception 'P0B2_CONCURRENCY_RERESOLUTION_FAILED';
    end if;
    perform * from public.school_lock_student_monthly_settlement(
      v_student,'2020-06',v_marker);
  else
    raise exception 'P0B2_SCENARIO_INVALID: %',v_scenario;
  end if;
  v_elapsed:=extract(epoch from clock_timestamp()-v_started);
  if v_elapsed<3 then
    raise exception 'P0B2_EXPECTED_BLOCKING_MISSING scenario=% elapsed=%',
      v_scenario,v_elapsed;
  end if;
  raise notice 'P0B2_SESSION_B_BLOCKED_THEN_COMPLETED scenario=% elapsed_seconds=% pid=%',
    v_scenario,round(v_elapsed,3),pg_backend_pid();
end
$b$;
rollback;
select :'p0b2_scenario' scenario,'B_ROLLED_BACK_NO_PARTIAL_WRITE' result;
