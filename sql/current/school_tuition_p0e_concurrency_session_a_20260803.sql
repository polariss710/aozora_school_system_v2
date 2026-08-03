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
select clock_timestamp() session_a_started,:'p0e_scenario' scenario;
do $a$
declare v record;
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
  perform * from public.school_reissue_atomic_student_tuition_generation_p0e_local(
    v.generation_id,v.previous_revision_id,v.student_id,v.business_entity_id,v.billing_month,
    v.source_snapshot->>'candidate_manifest_sha256',v.generation_manifest_sha256,
    v.billing_exchange_rate,v.bill_amount_jpy,
    (v.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric,
    v.source_settlement_id,v.source_historical_carryover_cny,v.adjustment_type,
    v.adjustment_amount,v.line_manifest_sha256,v.billing_amount_cny,v.reason,'codex-test P0-E concurrency A');
  perform pg_sleep(4);
end;
$a$;
select clock_timestamp() session_a_finished,:'p0e_scenario' scenario;
rollback;
