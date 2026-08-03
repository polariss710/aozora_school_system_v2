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
select clock_timestamp() as session_b_started,:'p0c_scenario' scenario;
do $b$
declare
  v_scenario text:=current_setting('tuition.p0c_scenario');
  v_manifest text; v_lesson public.school_lesson_records%rowtype;
begin
  select generation_manifest_sha256 into strict v_manifest
  from public.school_student_tuition_generation_revisions
  where id='c0c00000-0000-4000-8000-000000004001';
  if v_scenario in ('void_vs_void','void_vs_generate','void_vs_cash_reservation') then
    if v_scenario='void_vs_void' then
      perform * from public.school_void_atomic_student_tuition_generation(
        'c0c00000-0000-4000-8000-000000004001','c0c00000-0000-4000-8000-000000006001',
        'c0c00000-0000-4000-8000-000000007101',v_manifest,'codex-test concurrency');
    elsif v_scenario='void_vs_generate' then
      update public.school_feature_gates set state='enabled' where feature_key='student_tuition_generate';
      perform * from public.school_generate_student_tuition_bill_atomic_core(
        'c0c00000-0000-4000-8000-00000000a001','2020-08',0.05,v_manifest,'codex-test concurrency',null);
    else
      update public.school_feature_gates set state='enabled' where feature_key='student_tuition_cash_submit';
      perform * from public.school_request_cash_income_confirmation_for_record(
        'c0c00000-0000-4000-8000-000000007101','c0c00000-0000-4000-8000-000000009001',
        'c0c00000-0000-4000-8000-000000009002','codex-test Cash','test',
        null,null,null,'codex-test concurrency',null);
    end if;
  elsif v_scenario='void_vs_lesson_edit' then
    perform public.school_tuition_p0b1_lock_existing_lesson_scope(
      'c0c00000-0000-4000-8000-000000001101',null,null,null);
  elsif v_scenario in ('reissue_vs_cash_reservation','reissue_vs_settlement_mutation','duplicate_reissue') then
    if v_scenario='reissue_vs_cash_reservation' then
      update public.school_feature_gates set state='enabled' where feature_key='student_tuition_cash_submit';
      perform * from public.school_request_cash_income_confirmation_for_record(
        'c0c00000-0000-4000-8000-000000007101','c0c00000-0000-4000-8000-000000009001',
        'c0c00000-0000-4000-8000-000000009002','codex-test Cash','test',
        null,null,null,'codex-test concurrency',null);
    elsif v_scenario='reissue_vs_settlement_mutation' then
      begin
        perform * from public.school_unlock_student_monthly_settlement(
          'c0c00000-0000-4000-8000-00000000b001','codex-test concurrency');
      exception when others then
        if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
      end;
    else
      update public.school_feature_gates set state='enabled' where feature_key='student_tuition_generate';
      perform * from public.school_generate_student_tuition_bill_atomic_core(
        'c0c00000-0000-4000-8000-00000000a001','2020-08',0.05,v_manifest,'codex-test duplicate',null);
    end if;
  elsif v_scenario='active_lesson_claim_race' then
    perform public.school_assert_active_tuition_lesson_claim('c0c00000-0000-4000-8000-000000001101');
  elsif v_scenario='active_carryover_claim_race' then
    perform public.school_assert_active_tuition_carryover_claim('c0c00000-0000-4000-8000-00000000b001');
  elsif v_scenario='historical_reader_consistency' then
    begin
      perform * from public.school_get_student_tuition_validation_preview_details(
        'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07',0.05);
      raise exception 'EXPECTED_HISTORICAL_ALREADY_BILLED_MISSING';
    exception when others then
      if position('R2_F_B_ALREADY_BILLED' in sqlerrm)=0 then raise; end if;
    end;
  else raise exception 'P0C_SCENARIO_INVALID: %',v_scenario;
  end if;
end;
$b$;
select clock_timestamp() as session_b_finished,:'p0c_scenario' scenario;
rollback;
