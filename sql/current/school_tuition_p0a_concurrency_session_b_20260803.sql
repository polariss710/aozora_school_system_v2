-- P0-A concurrency session B. Required p0a_scenario.
-- Starts while matching session A holds the shared operation scope.
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

do $session_b$
declare
  v_scenario constant text:=current_setting('tuition.p0a_scenario');
  v_marker constant text:='codex-test tuition-p0a-concurrency-20260803';
  v_student constant uuid:='a0a00000-0000-4000-8000-00000000a100';
  v_settlement constant uuid:='a0a00000-0000-4000-8000-00000000b100';
  v_preview record;
  v_result record;
  v_started timestamptz:=clock_timestamp();
  v_elapsed numeric;
begin
  if v_scenario='generate_unlock' then
    perform * from public.school_unlock_student_monthly_settlement(v_settlement,v_marker);
  elsif v_scenario='generate_relock' then
    begin
      perform * from public.school_relock_student_monthly_settlement(v_settlement,v_marker);
      raise exception 'EXPECTED_RELOCK_STATE_REJECTION_MISSING';
    exception when others then
      if position('只有已撤销锁定' in sqlerrm)=0 then raise; end if;
    end;
  elsif v_scenario='generate_adjustment' then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',1,'manual',v_marker,v_marker);
  elsif v_scenario='generate_carryover' then
    insert into public.school_student_settlement_carryovers(
      id,student_id,from_year_month,to_year_month,amount_cny,
      source_settlement_id,source_settlement_month,status,note
    ) values (
      'a0a00000-0000-4000-8000-00000000c100',v_student,'2020-05','2020-06',
      1,v_settlement,'2020-05','active',v_marker
    );
  elsif v_scenario='mutation_pair' then
    perform * from public.school_unlock_student_monthly_settlement(v_settlement,v_marker);
  elsif v_scenario='duplicate_generate' then
    select * into strict v_preview
    from public.school_get_student_tuition_validation_preview_details(
      v_student,'2020-06',0.05);
    select * into strict v_result
    from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2020-06',0.05,v_preview.generation_manifest_sha256,v_marker,null);
    if v_result.idempotent then
      raise exception 'TUITION_P0A_SESSION_B_UNEXPECTED_IDEMPOTENT_AFTER_A_ROLLBACK';
    end if;
  else
    raise exception 'TUITION_P0A_SCENARIO_INVALID: %',v_scenario;
  end if;

  v_elapsed:=extract(epoch from clock_timestamp()-v_started);
  if v_elapsed<3 then
    raise exception 'TUITION_P0A_EXPECTED_BLOCKING_MISSING: scenario=% elapsed=%',
      v_scenario,v_elapsed;
  end if;
  raise notice 'P0A_SESSION_B_BLOCKED_THEN_COMPLETED scenario=% elapsed_seconds=% pid=%',
    v_scenario,round(v_elapsed,3),pg_backend_pid();
end
$session_b$;

rollback;
select :'p0a_scenario' as scenario,'B_ROLLED_BACK_NO_PARTIAL_WRITE' as result;
