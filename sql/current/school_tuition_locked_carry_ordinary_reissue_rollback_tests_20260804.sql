-- Rollback test against the fixed P0-E whitelist fixture inserted with a locked source.
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
  v_revision constant uuid:='d0d00000-0000-4000-8000-000000004001';
  v_bill constant uuid:='d0d00000-0000-4000-8000-000000006001';
  v_income constant uuid:='d0d00000-0000-4000-8000-000000007101';
  v_marker constant text:='codex-test tuition-p0e-forward-adjustment-20260803';
  v_manifest text; v_void record; v_snapshot record; v_reissue record; v_duplicate record;
begin
  if not exists(select 1 from public.school_student_monthly_settlements
                where id=v_settlement and settlement_status='locked'
                  and carryover_amount_cny=107.50)
     or not exists(select 1 from public.school_student_tuition_generation_revisions
                   where id=v_revision and lifecycle_status='active') then
    raise exception 'LOCKED_CARRY_FIXTURE_INVALID';
  end if;
  select generation_manifest_sha256 into strict v_manifest
  from public.school_student_tuition_generation_revisions where id=v_revision;
  select * into strict v_void
  from public.school_void_atomic_student_tuition_generation_local(
    v_revision,v_bill,v_income,v_manifest,v_marker||' locked carry rollback Void');
  select * into strict v_snapshot
  from public.school_build_student_tuition_generation_snapshot(v_student,'2020-08',0.043);
  if v_snapshot.previous_settlement_id<>v_settlement
     or v_snapshot.previous_carryover_cny<>107.50
     or v_snapshot.total_fee_jpy<>650000
     or v_snapshot.billing_amount_cny<>28057.50 then
    raise exception 'LOCKED_CARRY_PREVIEW_INVALID';
  end if;
  select * into strict v_reissue
  from public.school_reissue_atomic_student_tuition_generation_local(
    v_generation,v_revision,v_student,v_entity,'2020-08',
    v_snapshot.candidate_manifest_sha256,v_snapshot.generation_manifest_sha256,
    0.043,v_snapshot.total_fee_jpy,v_snapshot.billing_amount_cny,
    v_marker||' locked carry rollback Reissue');
  if v_reissue.idempotent
     or v_reissue.previous_carryover_cny<>107.50
     or v_reissue.billing_amount_cny<>28057.50
     or (select count(*) from public.school_student_tuition_generation_revision_adjustments
         where generation_identity_id=v_generation)<>0 then
    raise exception 'LOCKED_CARRY_REISSUE_INVALID';
  end if;
  perform public.school_validate_tuition_identity_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_bill_income_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_for_bill(v_reissue.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_adjustment_for_bill(v_reissue.tuition_bill_id);
  select * into strict v_duplicate
  from public.school_reissue_atomic_student_tuition_generation_local(
    v_generation,v_revision,v_student,v_entity,'2020-08',
    v_snapshot.candidate_manifest_sha256,v_snapshot.generation_manifest_sha256,
    0.043,v_snapshot.total_fee_jpy,v_snapshot.billing_amount_cny,
    v_marker||' locked carry duplicate');
  if not v_duplicate.idempotent
     or v_duplicate.tuition_bill_id<>v_reissue.tuition_bill_id then
    raise exception 'LOCKED_CARRY_DUPLICATE_INVALID';
  end if;
end;
$tests$;

select 'LOCKED_CARRY_ORDINARY_REISSUE_ROLLBACK_PASS' result;
rollback;
