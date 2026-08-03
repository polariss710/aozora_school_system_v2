\set ON_ERROR_STOP on
\pset pager off
\if :{?p0c_scenario}
\else
  \echo 'P0C_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='8s';
set local statement_timeout='30s';
select set_config('tuition.p0c_scenario',:'p0c_scenario',true);
do $a$
declare v_scenario text:=current_setting('tuition.p0c_scenario');
begin
  if v_scenario='active_lesson_claim_race' then
    perform public.school_assert_active_tuition_lesson_claim('c0c00000-0000-4000-8000-000000001101');
  elsif v_scenario='active_carryover_claim_race' then
    perform public.school_assert_active_tuition_carryover_claim('c0c00000-0000-4000-8000-00000000b001');
  elsif v_scenario='reissue_vs_settlement_mutation' then
    perform public.school_lock_student_tuition_operation(
      'c0c00000-0000-4000-8000-00000000a001',
      'c0c00000-0000-4000-8000-00000000e001',date '2020-07-01');
  else
    perform public.school_lock_student_tuition_operation(
      'c0c00000-0000-4000-8000-00000000a001',
      'c0c00000-0000-4000-8000-00000000e001',date '2020-08-01');
  end if;
end;
$a$;
select :'p0c_scenario' scenario,'session_a_lock_acquired' event,clock_timestamp() ts;
select pg_sleep(3);
rollback;
select :'p0c_scenario' scenario,'session_a_rolled_back' event,clock_timestamp() ts;
