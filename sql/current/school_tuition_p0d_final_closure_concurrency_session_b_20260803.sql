\set ON_ERROR_STOP on
\if :{?p0d_final_scenario}
\else
  \echo 'P0D_FINAL_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='8s';
set local statement_timeout='30s';
select set_config('tuition.p0d_final_scenario',:'p0d_final_scenario',true);
select pg_sleep(0.25);
do $b$
declare v_started timestamptz:=clock_timestamp(); v_code text;
begin
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    'd0d00000-0000-4000-8000-00000000a001','d0d00000-0000-4000-8000-00000000e001','2020-07');
  begin
    perform public.school_assert_active_tuition_previous_period_claim(
      'd0d00000-0000-4000-8000-00000000a001','d0d00000-0000-4000-8000-00000000e001','2020-07');
  exception when others then v_code:=sqlerrm; end;
  if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in coalesce(v_code,''))=0 then
    raise exception 'P0D_FINAL_CONCURRENCY_RULE_A_REJECTION_MISSING';
  end if;
  if extract(epoch from clock_timestamp()-v_started)<1 then
    raise exception 'P0D_FINAL_CONCURRENCY_DID_NOT_WAIT';
  end if;
end
$b$;
rollback;
select :'p0d_final_scenario' scenario,'session_b_waited_and_rejected_no_deadlock' result;
