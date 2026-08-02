-- P0-A concurrency session A. Required p0a_scenario.
-- Scenarios: generate_unlock, generate_relock, generate_adjustment,
-- generate_carryover, mutation_pair, duplicate_generate.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0a_scenario}
\else
  \echo 'P0A_SCENARIO_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='15s';
set local statement_timeout='120s';
select set_config('tuition.p0a_scenario',:'p0a_scenario',true);

do $session_a$
declare
  v_scenario constant text:=current_setting('tuition.p0a_scenario');
  v_student constant uuid:='a0a00000-0000-4000-8000-00000000a100';
  v_entity constant uuid:='a0a00000-0000-4000-8000-00000000e100';
  v_settlement constant uuid:='a0a00000-0000-4000-8000-00000000b100';
  v_preview record;
  v_result record;
begin
  if v_scenario in (
    'generate_unlock','generate_relock','generate_adjustment',
    'generate_carryover','duplicate_generate'
  ) then
    select * into strict v_preview
    from public.school_get_student_tuition_validation_preview_details(
      v_student,'2020-06',0.05);
    select * into strict v_result
    from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2020-06',0.05,v_preview.generation_manifest_sha256,
      'codex-test tuition-p0a-concurrency-20260803',null);
    if v_result.idempotent then
      raise exception 'TUITION_P0A_SESSION_A_UNEXPECTED_IDEMPOTENT';
    end if;
  elsif v_scenario='mutation_pair' then
    perform * from public.school_unlock_student_monthly_settlement(
      v_settlement,'codex-test tuition-p0a-concurrency-20260803');
  else
    raise exception 'TUITION_P0A_SCENARIO_INVALID: %',v_scenario;
  end if;
  raise notice 'P0A_SESSION_A_LOCK_HELD scenario=% pid=%',v_scenario,pg_backend_pid();
  perform pg_sleep(5);
end
$session_a$;

rollback;
select :'p0a_scenario' as scenario,'A_ROLLED_BACK' as result;
