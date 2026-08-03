-- P0-E rollback test against the committed fixed whitelist fixture.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $tests$
declare
  v_student constant uuid:='d0d00000-0000-4000-8000-00000000a001';
  v_entity constant uuid:='d0d00000-0000-4000-8000-00000000e001';
  v_settlement constant uuid:='d0d00000-0000-4000-8000-00000000b001';
  v_generation constant uuid:='d0d00000-0000-4000-8000-000000003001';
  v_revision1 constant uuid:='d0d00000-0000-4000-8000-000000004001';
  v_bill1 constant uuid:='d0d00000-0000-4000-8000-000000006001';
  v_income1 constant uuid:='d0d00000-0000-4000-8000-000000007101';
  v_manifest1 text; v_base record; v_preview record; v_void record; v_reissue record;
  v_duplicate record; v_cash record; v_state record; v_resolver record;
  v_error text; v_marker constant text:='codex-test tuition-p0e-forward-adjustment-20260803';
begin
  select generation_manifest_sha256 into strict v_manifest1
  from public.school_student_tuition_generation_revisions where id=v_revision1;

  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('clear_balance',null,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>-107.50
     or v_resolver.resolved_carryover_cny<>0 then
    raise exception 'P0E_P0B2_CLEAR_BALANCE_REGRESSION';
  end if;
  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('carry_final_balance',null,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>0
     or v_resolver.resolved_carryover_cny<>107.50 then
    raise exception 'P0E_P0B2_CARRY_BALANCE_REGRESSION';
  end if;
  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('manual_adjustment',-7.50,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>-7.50
     or v_resolver.resolved_carryover_cny<>100 then
    raise exception 'P0E_P0B2_MANUAL_REGRESSION';
  end if;
  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment('clear_balance',0,107.50);
    raise exception 'P0E_P0B2_CLEAR_ACCEPTED_NON_NULL';
  exception when others then
    if sqlerrm not like '%SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE%' then raise; end if;
  end;
  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment('manual_adjustment',null,107.50);
    raise exception 'P0E_P0B2_MANUAL_ACCEPTED_NULL';
  exception when others then
    if sqlerrm not like '%SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED%' then raise; end if;
  end;

  begin
    perform * from public.school_relock_student_monthly_settlement(v_settlement,v_marker);
    raise exception 'P0E_RULE_A_RELOCK_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE%' then raise; end if;
  end;
  begin
    update public.school_student_monthly_settlements set carryover_amount_cny=999 where id=v_settlement;
    raise exception 'P0E_DIRECT_SETTLEMENT_UPDATE_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE%' then raise; end if;
  end;

  select * into strict v_void from public.school_void_atomic_student_tuition_generation_local(
    v_revision1,v_bill1,v_income1,v_manifest1,v_marker||' rollback Void');
  begin
    perform * from public.school_relock_student_monthly_settlement(v_settlement,v_marker);
    raise exception 'P0E_RULE_B_RELOCK_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_CONSUMED_SETTLEMENT_IMMUTABLE%' then raise; end if;
  end;

  select * into strict v_preview from public.school_get_atomic_tuition_reissue_preview_p0e(
    v_generation,v_revision1,v_student,v_entity,'2020-08',0.043,null,null);
  if v_preview.source_historical_carryover_cny<>107.50
     or v_preview.adjustment_amount_cny<>0
     or v_preview.final_billing_amount_cny<>28057.50
     or v_preview.adjustment_type is not null then
    raise exception 'P0E_INHERITED_CARRY_PREVIEW_INVALID';
  end if;

  select * into strict v_preview from public.school_get_atomic_tuition_reissue_preview_p0e(
    v_generation,v_revision1,v_student,v_entity,'2020-08',0.043,
    'neutralize_historical_carryover_v1',v_marker||' rollback adjustment');
  if v_preview.total_fee_jpy<>650000 or v_preview.exchange_amount_cny<>27950
     or v_preview.source_historical_carryover_cny<>107.50
     or v_preview.adjustment_amount_cny<>-107.50
     or v_preview.final_billing_amount_cny<>27950
     or v_preview.generation_manifest_sha256!~'^[0-9a-f]{64}$'
     or v_preview.line_manifest_sha256!~'^[0-9a-f]{64}$' then
    raise exception 'P0E_NEUTRALIZE_PREVIEW_INVALID';
  end if;

  select * into strict v_base from public.school_build_student_tuition_generation_snapshot(
    v_student,'2020-08',0.043);
  begin
    perform * from public.school_reissue_atomic_student_tuition_generation_local(
      v_generation,v_revision1,v_student,v_entity,'2020-08',v_base.candidate_manifest_sha256,
      v_base.generation_manifest_sha256,0.043,v_base.total_fee_jpy,v_base.billing_amount_cny,v_marker);
    raise exception 'P0E_ORDINARY_REISSUE_BYPASS_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED%' then raise; end if;
  end;

  select * into strict v_reissue
  from public.school_reissue_atomic_student_tuition_generation_p0e_local(
    v_generation,v_revision1,v_student,v_entity,'2020-08',
    v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,0.043,
    v_preview.total_fee_jpy,v_preview.exchange_amount_cny,v_preview.source_settlement_id,
    v_preview.source_historical_carryover_cny,v_preview.adjustment_type,
    v_preview.adjustment_amount_cny,v_preview.line_manifest_sha256,
    v_preview.final_billing_amount_cny,v_preview.reason,v_marker||' rollback Reissue');
  if v_reissue.idempotent or v_reissue.final_billing_amount_cny<>27950
     or v_reissue.adjustment_amount_cny<>-107.50 then
    raise exception 'P0E_REISSUE_RESULT_INVALID';
  end if;
  if (select count(*) from public.school_student_tuition_generation_revision_adjustments
      where generation_identity_id=v_generation)<>1 then
    raise exception 'P0E_ADJUSTMENT_CARDINALITY_INVALID';
  end if;
  perform public.school_validate_tuition_identity_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_bill_income_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_adjustment_for_bill(v_reissue.tuition_bill_id);

  select * into strict v_duplicate
  from public.school_reissue_atomic_student_tuition_generation_p0e_local(
    v_generation,v_revision1,v_student,v_entity,'2020-08',
    v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,0.043,
    v_preview.total_fee_jpy,v_preview.exchange_amount_cny,v_preview.source_settlement_id,
    v_preview.source_historical_carryover_cny,v_preview.adjustment_type,
    v_preview.adjustment_amount_cny,v_preview.line_manifest_sha256,
    v_preview.final_billing_amount_cny,v_preview.reason,v_marker||' duplicate');
  if not v_duplicate.idempotent or v_duplicate.tuition_bill_id<>v_reissue.tuition_bill_id then
    raise exception 'P0E_DUPLICATE_NOT_IDEMPOTENT';
  end if;

  begin
    perform * from public.school_reissue_atomic_student_tuition_generation_p0e_local(
      v_generation,v_revision1,v_student,v_entity,'2020-08',
      v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,0.043,
      v_preview.total_fee_jpy,v_preview.exchange_amount_cny,v_preview.source_settlement_id,
      v_preview.source_historical_carryover_cny,v_preview.adjustment_type,
      v_preview.adjustment_amount_cny,v_preview.line_manifest_sha256,
      v_preview.final_billing_amount_cny,'different reason',v_marker);
    raise exception 'P0E_REASON_CONFLICT_ACCEPTED';
  exception when others then
    if sqlerrm not like '%TUITION_P0E_IDEMPOTENCY_CONFLICT%' then raise; end if;
  end;
  begin
    update public.school_student_tuition_generation_revision_adjustments
    set amount_cny=0 where target_revision_id=v_reissue.generation_revision_id;
    raise exception 'P0E_ADJUSTMENT_UPDATE_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_P0E_ADJUSTMENT_IMMUTABLE%' then raise; end if;
  end;
  begin
    delete from public.school_student_tuition_generation_revision_adjustments
    where target_revision_id=v_reissue.generation_revision_id;
    raise exception 'P0E_ADJUSTMENT_DELETE_SUCCEEDED';
  exception when others then
    if sqlerrm not like '%TUITION_P0E_ADJUSTMENT_IMMUTABLE%' then raise; end if;
  end;

  select * into strict v_cash from public.school_get_cash_income_submission_preflight(
    array[v_reissue.income_record_id]);
  if v_cash.payment_currency<>'CNY' or v_cash.payment_amount<>27950 then
    raise exception 'P0E_CASH_FROZEN_AMOUNT_INVALID: eligible %, currency %, amount %',
      v_cash.eligible,v_cash.payment_currency,v_cash.payment_amount;
  end if;
  select * into strict v_state from public.school_get_student_monthly_settlement_effective_states(
    array[v_settlement]);
  if v_state.physical_status<>'unlocked'
     or v_state.effective_status<>'historically_consumed_immutable'
     or v_state.frozen_carryover_cny<>107.50 or v_state.editable or v_state.relockable
     or v_state.immutable_error_code<>'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' then
    raise exception 'P0E_EFFECTIVE_STATE_INVALID';
  end if;
end;
$tests$;

select 'P0E_ROLLBACK_TEST_PASSED' result;
rollback;
