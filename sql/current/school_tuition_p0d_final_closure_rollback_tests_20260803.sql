\set ON_ERROR_STOP on
\pset pager off
-- Rule A / Rule B matrix. Entire file rolls back.
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

do $tests$
declare
  v_student constant uuid:='d0d00000-0000-4000-8000-00000000a001';
  v_entity constant uuid:='d0d00000-0000-4000-8000-00000000e001';
  v_original_settlement constant uuid:='d0d00000-0000-4000-8000-00000000b001';
  v_zero_settlement constant uuid:='d0d00000-0000-4000-8000-00000000b201';
  v_bill constant uuid:='d0d00000-0000-4000-8000-000000006201';
  v_legacy constant uuid:='d0d00000-0000-4000-8000-000000002201';
  v_generation constant uuid:='d0d00000-0000-4000-8000-000000003201';
  v_revision constant uuid:='d0d00000-0000-4000-8000-000000004201';
  v_teacher constant uuid:='d0d00000-0000-4000-8000-000000007001';
  v_subject constant uuid:='d0d00000-0000-4000-8000-00000000d001';
  v_sep_lesson constant uuid:='d0d00000-0000-4000-8000-000000001201';
  v_oct_lesson constant uuid:='d0d00000-0000-4000-8000-000000001202';
  v_manifest text;
  v_locked record;
  v_preview record;
  v_reissue record;
begin
  -- Rule B is permanent and takes precedence over active-claim release.
  begin
    perform public.school_assert_tuition_settlement_mutable(v_original_settlement);
    raise exception 'EXPECTED_RULE_B_REJECTION_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;

  -- Prepare an unlocked zero settlement before creating an active revision whose
  -- bill intentionally has previous_settlement_id NULL and carryover 0.
  insert into public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,preset_exchange_rate,
    planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
    actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
    received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
    adjustment_reason,carryover_amount_cny,settlement_status,locked_at,note,
    created_at,updated_at,unlocked_at,unlock_reason,duration_overage_minutes,
    duration_overage_fee_jpy,duration_overage_fee_cny,duration_overage_actual_count,
    duration_overage_policy_version,duration_overage_source
  ) select v_zero_settlement,student_id,'2020-09',business_entity_id,preset_exchange_rate,
    planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,actual_lesson_fee_cny,
    previous_balance_cny,received_jpy,received_cny,received_equivalent_cny,
    system_difference_cny,adjustment_amount_cny,adjustment_reason,0,'unlocked',null,
    'codex-test P0-D zero carry claim',created_at,updated_at,unlocked_at,unlock_reason,
    duration_overage_minutes,duration_overage_fee_jpy,
    duration_overage_fee_cny,duration_overage_actual_count,duration_overage_policy_version,
    duration_overage_source
  from public.school_student_monthly_settlements where id=v_original_settlement;

  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
  ) select lesson_id,'planned',lesson_date,year_month,v_student,v_teacher,v_subject,
    v_entity,'15:00','17:00',2,'codex-test P0-D zero carry lifecycle','planned',true,
    'codex-test P0-D zero carry lifecycle','school',1000,2000,1,'online',
    'codex-test P0-D zero carry lifecycle',year_month,
    date_trunc('week',lesson_date::timestamp)::date,lesson_date,year_month,
    'explicit_billing_week_at_create',statement_timestamp()
  from (values
    (v_sep_lesson,date '2020-09-10','2020-09'::text),
    (v_oct_lesson,date '2020-10-10','2020-10'::text)
  ) x(lesson_id,lesson_date,year_month);

  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  select generation_manifest_sha256 into strict v_manifest
  from public.school_student_tuition_generation_revisions
  where id='d0d00000-0000-4000-8000-000000004001';

  insert into public.school_student_tuition_bills(
    id,student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    income_record_id,source_snapshot,note,app_type,created_by,updated_by,created_at,
    updated_at,income_created_at,cancelled_at,cancelled_reason,billing_exchange_rate,
    billing_amount_cny,billing_amount_calculated_at,billing_role,incident_locked_at,
    incident_reason,cash_submission_blocked
  )
  select v_bill,student_id,business_entity_id,'2020-10','2020-09',null,0,
    planned_lesson_count,planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,
    currency,'draft',null,source_snapshot||jsonb_build_object('previous_settlement_id',null,
      'previous_carryover_cny',0,'billing_month','2020-10'),
    'codex-test P0-D zero carry claim',app_type,created_by,updated_by,created_at,updated_at,
    null,null,null,billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,null,null,cash_submission_blocked
  from public.school_student_tuition_bills
  where id='d0d00000-0000-4000-8000-000000006001';
  insert into public.school_student_tuition_billing_identities(
    id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,source,created_by,evidence
  ) values(v_legacy,v_student,'2020-10',v_bill,'codex-test-p0d-zero-claim',
    'atomic_charge','codex-test P0-D zero carry claim','{}'::jsonb);
  insert into public.school_student_tuition_generation_identities(
    id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
  ) values(v_generation,v_student,v_entity,date '2020-10-01',v_legacy,now(),'codex-test P0-D zero carry claim');
  insert into public.school_student_tuition_generation_revisions(
    id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
    generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority,activated_at
  ) values(v_revision,v_generation,v_bill,1,null,v_manifest,'atomic_generation_v1','active',now(),
    'codex-test P0-D zero carry claim',now());

  -- 1 create/save/lock scope, 2 draft, 3 adjustment, 4 carryover, 5 row mutation all reject Rule A.
  begin
    insert into public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id,preset_exchange_rate,
      planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
      actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
      received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
      adjustment_reason,carryover_amount_cny,settlement_status,locked_at,note,
      created_at,updated_at,unlocked_at,unlock_reason,duration_overage_minutes,
      duration_overage_fee_jpy,duration_overage_fee_cny,duration_overage_actual_count,
      duration_overage_policy_version,duration_overage_source
    ) select gen_random_uuid(),student_id,'2020-09',business_entity_id,preset_exchange_rate,
      planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,actual_lesson_fee_cny,
      previous_balance_cny,received_jpy,received_cny,received_equivalent_cny,
      system_difference_cny,adjustment_amount_cny,adjustment_reason,0,'unlocked',null,'blocked',created_at,updated_at,
      unlocked_at,unlock_reason,duration_overage_minutes,duration_overage_fee_jpy,
      duration_overage_fee_cny,duration_overage_actual_count,duration_overage_policy_version,duration_overage_source
    from public.school_student_monthly_settlements where id=v_zero_settlement;
    raise exception 'EXPECTED_ZERO_CREATE_REJECTION_MISSING';
  exception when others then if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin
    insert into public.school_student_settlement_adjustment_drafts(
      student_id,year_month,business_entity_id,adjustment_amount_cny,adjustment_source,
      adjustment_reason,note,status,app_type
    ) values(v_student,'2020-09',v_entity,0,'manual_adjustment','codex-test','blocked','active','school');
    raise exception 'EXPECTED_ZERO_DRAFT_REJECTION_MISSING';
  exception when others then if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin
    insert into public.school_student_settlement_adjustments(
      settlement_id,student_id,year_month,business_entity_id,adjustment_amount_cny,
      adjustment_source,adjustment_reason,note,status,app_type
    ) values(v_zero_settlement,v_student,'2020-09',v_entity,0,'manual_adjustment','codex-test','blocked','posted','school');
    raise exception 'EXPECTED_ZERO_ADJUSTMENT_REJECTION_MISSING';
  exception when others then if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin
    insert into public.school_student_settlement_carryovers(
      student_id,from_year_month,to_year_month,amount_cny,source_settlement_id,
      source_settlement_month,status,note
    ) values(v_student,'2020-09','2020-10',0,v_zero_settlement,'2020-09','active','blocked');
    raise exception 'EXPECTED_ZERO_CARRYOVER_REJECTION_MISSING';
  exception when others then if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin
    update public.school_student_monthly_settlements set note=note where id=v_zero_settlement;
    raise exception 'EXPECTED_ZERO_MUTATION_REJECTION_MISSING';
  exception when others then if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;

  -- 6 Void releases a never-consumed zero claim and permits the formal relock path.
  delete from public.school_tuition_atomic_writer_context
  where backend_pid=pg_backend_pid() and transaction_id=txid_current();
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_void_v1');
  update public.school_student_tuition_generation_revisions
  set lifecycle_status='voided',voided_at=now(),voided_by_authority='codex-test P0-D zero carry claim'
  where id=v_revision;
  update public.school_student_tuition_bills
  set status='cancelled',cancelled_at=now(),cancelled_reason='codex-test P0-D zero carry claim'
  where id=v_bill;
  delete from public.school_tuition_atomic_writer_context
  where backend_pid=pg_backend_pid() and transaction_id=txid_current();
  perform public.school_assert_active_tuition_previous_period_claim(v_student,v_entity,'2020-09');
  update public.school_student_monthly_settlements set note=note where id=v_zero_settlement;

  select * into strict v_locked
  from public.school_relock_student_monthly_settlement(
    v_zero_settlement,'codex-test P0-D zero carry relock after Void'
  );
  if v_locked.settlement_status<>'locked' or v_locked.carryover_amount_cny<=0 then
    raise exception 'RULE_A_RELEASE_FORMAL_RELOCK_FAILED';
  end if;

  -- 7 after the released July-equivalent period is locked, Reissue consumes its exact carry.
  select * into strict v_preview
  from public.school_get_student_tuition_validation_preview_details(v_student,'2020-10',0.043);
  if v_preview.previous_settlement_id is distinct from v_zero_settlement
     or v_preview.previous_carryover_cny is distinct from v_locked.carryover_amount_cny
     or v_preview.candidate_count<>1 then
    raise exception 'RULE_A_RELOCKED_CARRY_PREVIEW_FAILED';
  end if;
  select * into strict v_reissue
  from public.school_reissue_atomic_student_tuition_generation_local(
    v_generation,v_revision,v_student,v_entity,'2020-10',
    v_preview.candidate_manifest_sha256,v_preview.generation_manifest_sha256,
    0.043,v_preview.total_fee_jpy,v_preview.billing_amount_cny,
    'codex-test P0-D zero carry reissue after relock'
  );
  if v_reissue.previous_carryover_cny is distinct from v_locked.carryover_amount_cny
     or (select previous_settlement_id from public.school_student_tuition_bills
         where id=v_reissue.tuition_bill_id) is distinct from v_zero_settlement
     or (select count(*) from public.school_student_tuition_generation_revisions
         where generation_identity_id=v_generation and lifecycle_status='active')<>1 then
    raise exception 'RULE_A_RELOCKED_CARRY_REISSUE_FAILED';
  end if;

  -- 8 Rule B remains after the original revision is hypothetically voided; resolver is historical.
  if public.school_tuition_p0a_consumed_bill_id(v_original_settlement)
       is distinct from 'd0d00000-0000-4000-8000-000000006001'::uuid then
    raise exception 'RULE_B_HISTORICAL_RESOLVER_DRIFT';
  end if;
end
$tests$;

rollback;
\echo 'P0D_FINAL_RULE_A_B_MATRIX_ROLLED_BACK_8_OF_8'
