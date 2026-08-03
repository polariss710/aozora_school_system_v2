\set ON_ERROR_STOP on
\pset pager off
\if :{?p0e_scenario}
\else
  \echo 'P0E_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='8s';
set local statement_timeout='30s';
select set_config('tuition.p0e_scenario',:'p0e_scenario',true);
select clock_timestamp() session_b_started,:'p0e_scenario' scenario;
do $b$
declare v_scenario text:=current_setting('tuition.p0e_scenario'); v record; v_result record; v_error text;
begin
  select g.id generation_id,r.id revision_id,r.previous_revision_id,
    r.generation_manifest_sha256,b.*,i.id active_income_id,
    a.adjustment_type,a.amount_cny adjustment_amount,a.source_settlement_id,
    a.source_historical_carryover_cny,a.line_manifest_sha256,a.reason
  into strict v
  from public.school_student_tuition_generation_identities g
  join public.school_student_tuition_generation_revisions r on r.generation_identity_id=g.id and r.lifecycle_status='active'
  join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
  join public.school_income_records i on i.id=b.income_record_id
  join public.school_student_tuition_generation_revision_adjustments a on a.target_revision_id=r.id
  where g.id='d0d00000-0000-4000-8000-000000003001';
  if v_scenario='reissue_vs_settlement_mutation' then
    begin
      perform * from public.school_relock_student_monthly_settlement(v.source_settlement_id,'codex-test P0-E concurrency');
      raise exception 'P0E_CONCURRENCY_SETTLEMENT_MUTATION_SUCCEEDED';
    exception when others then
      if sqlerrm not like '%TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE%' then raise; end if;
    end;
  elsif v_scenario='reissue_vs_void' then
    perform * from public.school_void_atomic_student_tuition_generation_local(
      v.revision_id,v.id,v.active_income_id,v.generation_manifest_sha256,'codex-test P0-E concurrency Void');
  elsif v_scenario in ('duplicate_reissue','adjustment_duplicate_race') then
    select * into strict v_result from public.school_reissue_atomic_student_tuition_generation_p0e_local(
      v.generation_id,v.previous_revision_id,v.student_id,v.business_entity_id,v.billing_month,
      v.source_snapshot->>'candidate_manifest_sha256',v.generation_manifest_sha256,
      v.billing_exchange_rate,v.bill_amount_jpy,
      (v.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric,
      v.source_settlement_id,v.source_historical_carryover_cny,v.adjustment_type,
      v.adjustment_amount,v.line_manifest_sha256,v.billing_amount_cny,v.reason,'codex-test P0-E concurrency B');
    if not v_result.idempotent then raise exception 'P0E_CONCURRENCY_DUPLICATE_NOT_IDEMPOTENT'; end if;
  elsif v_scenario='reissue_vs_lesson_edit' then
    begin
      perform public.school_tuition_p0b1_lock_existing_lesson_scope(
        'd0d00000-0000-4000-8000-000000001101',null,null,null);
    exception when others then
      if sqlstate in ('55P03','57014','40P01') then raise; end if;
    end;
  elsif v_scenario='reissue_vs_cash_reservation' then
    begin
      update public.school_feature_gates set state='enabled' where feature_key='student_tuition_cash_submit';
      perform * from public.school_request_cash_income_confirmation_for_record(
        v.active_income_id,'d0d00000-0000-4000-8000-000000009001',
        'd0d00000-0000-4000-8000-000000009002','codex-test Cash','test',
        null,null,null,'codex-test P0-E concurrency',null);
    exception when others then
      if sqlstate in ('55P03','57014','40P01') then raise; end if;
    end;
  elsif v_scenario='ordinary_vs_p0e_reissue' then
    begin
      perform * from public.school_reissue_atomic_student_tuition_generation_local(
        v.generation_id,v.previous_revision_id,v.student_id,v.business_entity_id,v.billing_month,
        v.source_snapshot->>'candidate_manifest_sha256',v.generation_manifest_sha256,
        v.billing_exchange_rate,v.bill_amount_jpy,v.billing_amount_cny,'codex-test P0-E ordinary race');
    exception when others then
      if sqlstate in ('55P03','57014','40P01') then raise; end if;
    end;
  elsif v_scenario='manifest_mismatch_race' then
    begin
      perform * from public.school_reissue_atomic_student_tuition_generation_p0e_local(
        v.generation_id,v.previous_revision_id,v.student_id,v.business_entity_id,v.billing_month,
        v.source_snapshot->>'candidate_manifest_sha256',repeat('0',64),
        v.billing_exchange_rate,v.bill_amount_jpy,
        (v.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric,
        v.source_settlement_id,v.source_historical_carryover_cny,v.adjustment_type,
        v.adjustment_amount,v.line_manifest_sha256,v.billing_amount_cny,v.reason,'codex-test P0-E mismatch');
      raise exception 'P0E_CONCURRENCY_MANIFEST_MISMATCH_SUCCEEDED';
    exception when others then
      if sqlerrm not like '%TUITION_P0E_IDEMPOTENCY_CONFLICT%' then raise; end if;
    end;
  else
    raise exception 'P0E_SCENARIO_INVALID: %',v_scenario;
  end if;
end;
$b$;
select clock_timestamp() session_b_finished,:'p0e_scenario' scenario;
rollback;
select count(*) active_revision_count
from public.school_student_tuition_generation_revisions
where generation_identity_id='d0d00000-0000-4000-8000-000000003001' and lifecycle_status='active';
select count(*) adjustment_count
from public.school_student_tuition_generation_revision_adjustments
where generation_identity_id='d0d00000-0000-4000-8000-000000003001';
