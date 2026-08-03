-- P0-D single-session writer matrix. Entire file rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

do $matrix$
declare
  v_student constant uuid:='d0d00000-0000-4000-8000-00000000a001';
  v_entity constant uuid:='d0d00000-0000-4000-8000-00000000e001';
  v_generation constant uuid:='d0d00000-0000-4000-8000-000000003001';
  v_settlement constant uuid:='d0d00000-0000-4000-8000-00000000b001';
  v_bill constant uuid:='d0d00000-0000-4000-8000-000000006001';
  v_income constant uuid:='d0d00000-0000-4000-8000-000000007101';
  v_revision constant uuid:='d0d00000-0000-4000-8000-000000004001';
  v_manifest text; v_preview record; v_void record; v_generate record; v_code text;
begin
  select generation_manifest_sha256 into strict v_manifest
  from public.school_student_tuition_generation_revisions where id=v_revision;
  select * into strict v_preview from public.school_get_atomic_tuition_void_preflight(v_income);
  if not v_preview.eligible or v_preview.generation_revision_id<>v_revision then
    raise exception 'P0D_ELIGIBLE_PREFLIGHT_FAILED';
  end if;
  select blocker_code into strict v_code
  from public.school_get_atomic_tuition_void_preflight('468ab75b-312e-4ba0-8d8d-8ae2f6ace00e');
  if v_code<>'TUITION_VOID_NOT_ATOMIC' then raise exception 'P0D_HISTORICAL_PREFLIGHT_FAILED'; end if;

  begin
    update public.school_student_tuition_generation_revisions set revision_no=2 where id=v_revision;
    raise exception 'EXPECTED_REVISION_DIRECT_UPDATE_FAILURE_MISSING';
  exception when others then
    if position('TUITION_GENERATION_REVISION_MUTATION_FORBIDDEN' in sqlerrm)=0 then raise; end if;
  end;
  begin
    delete from public.school_student_tuition_generation_void_events;
    raise exception 'EXPECTED_VOID_EVENT_DIRECT_DELETE_FAILURE_MISSING';
  exception when others then
    if position('TUITION_P0C_DIRECT_DELETE_FORBIDDEN' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_cancel_pending_income_record(v_income,'codex-test generic reject',null);
    raise exception 'EXPECTED_GENERIC_CANCEL_REJECTION_MISSING';
  exception when others then
    if position('TUITION_ATOMIC_CANCEL_FORBIDDEN' in sqlerrm)=0 then raise; end if;
  end;

  select * into strict v_void from public.school_void_atomic_student_tuition_generation_local(
    v_revision,v_bill,v_income,v_manifest,'codex-test P0-D rollback success');
  if v_void.lifecycle_status<>'voided' or v_void.bill_status<>'cancelled'
     or v_void.income_status<>'cancelled' or v_void.released_lesson_count<>2
     or v_void.next_revision_no<>2 then raise exception 'P0D_VOID_RESULT_INVALID'; end if;
  if (select count(*) from public.school_student_tuition_generation_void_events
      where generation_revision_id=v_revision)<>1
     or (select count(*) from public.school_active_student_tuition_bill_lessons
         where tuition_bill_id=v_bill)<>0
     or public.school_tuition_p0a_consumed_bill_id(v_settlement)<>v_bill then
    raise exception 'P0D_VOID_AUTHORITY_RESULT_INVALID';
  end if;
  if (select operator_authority from public.school_student_tuition_generation_void_events
      where generation_revision_id=v_revision)<>'local_trusted_business_owner_v1' then
    raise exception 'P0D_LOCAL_OPERATOR_AUTHORITY_INVALID';
  end if;
  begin
    perform * from public.school_void_atomic_student_tuition_generation_local(
      v_revision,v_bill,v_income,v_manifest,'codex-test duplicate');
    raise exception 'EXPECTED_DUPLICATE_VOID_REJECTION_MISSING';
  exception when others then
    if position('TUITION_VOID_ALREADY_VOIDED' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_unlock_student_monthly_settlement(v_settlement,'codex-test');
    raise exception 'EXPECTED_CONSUMED_SETTLEMENT_REJECTION_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;

  select * into strict v_preview
  from public.school_get_student_tuition_validation_preview_details(v_student,'2020-08',0.043);
  if v_preview.candidate_count<>2 or v_preview.total_fee_jpy<>650000
     or v_preview.previous_carryover_cny<>0 or v_preview.billing_amount_cny<>27950 then
    raise exception 'P0D_ZHANG_MIRROR_PREVIEW_INVALID';
  end if;
  select * into strict v_generate from public.school_reissue_atomic_student_tuition_generation_local(
    v_generation,v_revision,v_student,v_entity,'2020-08',
    v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,
    0.043,650000,27950,'codex-test tuition-p0d-e2e-readiness-20260803');
  if v_generate.idempotent or (select count(*) from public.school_student_tuition_generation_revisions
      where generation_identity_id=(select generation_identity_id from public.school_student_tuition_generation_revisions where id=v_revision)
        and lifecycle_status='active')<>1
     or (select revision_no from public.school_student_tuition_generation_revisions
         where tuition_bill_id=v_generate.tuition_bill_id)<>2 then
    raise exception 'P0D_REISSUE_RESULT_INVALID';
  end if;
  perform public.school_validate_tuition_identity_for_bill(v_generate.tuition_bill_id);
  perform public.school_validate_tuition_bill_income_for_bill(v_generate.tuition_bill_id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_generate.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_for_bill(v_generate.tuition_bill_id);
  select * into strict v_generate from public.school_reissue_atomic_student_tuition_generation_local(
    v_generation,v_revision,v_student,v_entity,'2020-08',
    v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,
    0.043,650000,27950,'codex-test tuition-p0d-e2e-readiness-20260803');
  if not v_generate.idempotent then raise exception 'P0D_DUPLICATE_REISSUE_NOT_IDEMPOTENT'; end if;
  begin
    perform * from public.school_reissue_atomic_student_tuition_generation_local(
      v_generation,v_revision,v_student,v_entity,'2020-08',
      v_preview.candidate_manifest_sha256,repeat('0',64),
      0.043,650000,27950,'codex-test tuition-p0d-e2e-readiness-20260803');
    raise exception 'EXPECTED_REISSUE_MANIFEST_CONFLICT_MISSING';
  exception when others then
    if position('TUITION_REISSUE_EXPECTED_FACT_MISMATCH' in sqlerrm)=0 then raise; end if;
  end;

  -- Blocker classification matrix uses subtransactions so every mutation is rolled back.
  begin
    insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_void_v1');
    update public.school_income_records set status='received' where id=v_income;
    perform * from public.school_void_atomic_student_tuition_generation_local(v_revision,v_bill,v_income,v_manifest,'received blocker');
  exception when others then
    if position('TUITION_VOID_INCOME_NOT_PENDING' in sqlerrm)=0
       and position('TUITION_VOID_ALREADY_VOIDED' in sqlerrm)=0 then raise; end if;
  end;
end;
$matrix$;

rollback;
\echo 'P0D_SINGLE_SESSION_MATRIX_ROLLED_BACK'
