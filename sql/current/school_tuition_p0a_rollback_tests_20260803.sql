-- P0-A rollback-only business, guard, and permission matrix.
-- Requires deployed P0-A migration. Every fixture row is rolled back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

create temporary table tuition_p0a_test_results(
  test_name text primary key,passed boolean not null,detail text not null
) on commit drop;

do $fixture_and_tests$
declare
  v_marker constant text:='codex-test tuition-p0a-concurrency-20260803';
  v_entity constant uuid:='a0a00000-0000-4000-8000-00000000e001';
  v_student_a constant uuid:='a0a00000-0000-4000-8000-00000000a001';
  v_student_b constant uuid:='a0a00000-0000-4000-8000-00000000a002';
  v_student_c constant uuid:='a0a00000-0000-4000-8000-00000000a003';
  v_student_d constant uuid:='a0a00000-0000-4000-8000-00000000a004';
  v_settlement_a constant uuid:='a0a00000-0000-4000-8000-00000000b001';
  v_settlement_d constant uuid:='a0a00000-0000-4000-8000-00000000b004';
  v_draft_a constant uuid:='a0a00000-0000-4000-8000-00000000c001';
  v_adjustment_a constant uuid:='a0a00000-0000-4000-8000-00000000c002';
  v_carryover_a constant uuid:='a0a00000-0000-4000-8000-00000000c003';
  v_carryover_d constant uuid:='a0a00000-0000-4000-8000-00000000c004';
  v_bill_a constant uuid:='a0a00000-0000-4000-8000-00000000d001';
  v_identity_a constant uuid:='a0a00000-0000-4000-8000-00000000d002';
  v_income_b constant uuid:='a0a00000-0000-4000-8000-00000000f002';
  v_income_c constant uuid:='a0a00000-0000-4000-8000-00000000f003';
  v_locked_b uuid;
  v_locked_c uuid;
  v_failed boolean;
  v_before jsonb;
begin
  if exists (
    select 1 from public.school_business_entities where id=v_entity
    union all select 1 from public.school_students where id in (v_student_a,v_student_b,v_student_c,v_student_d)
    union all select 1 from public.school_student_monthly_settlements where id in (v_settlement_a,v_settlement_d)
    union all select 1 from public.school_student_tuition_bills where id=v_bill_a
    union all select 1 from public.school_student_tuition_billing_identities where id=v_identity_a
  ) then raise exception 'TUITION_P0A_ROLLBACK_FIXTURE_ID_COLLISION'; end if;

  insert into public.school_business_entities(
    id,code,name,entity_type,default_currency,is_active,note
  ) values (
    v_entity,'codex-test-p0a-entity','codex-test P0-A entity','company','JPY',true,v_marker
  );

  insert into public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) values
    (v_student_a,'codex-test-p0a-a','codex-test P0-A consumed','codex-test P0-A consumed',v_entity,'active','school',0.05,0,v_marker),
    (v_student_b,'codex-test-p0a-b','codex-test P0-A draft-lock','codex-test P0-A draft-lock',v_entity,'active','school',0.05,0,v_marker),
    (v_student_c,'codex-test-p0a-c','codex-test P0-A unlock-relock','codex-test P0-A unlock-relock',v_entity,'active','school',0.05,0,v_marker),
    (v_student_d,'codex-test-p0a-d','codex-test P0-A carryover','codex-test P0-A carryover',v_entity,'active','school',0.05,0,v_marker);

  insert into public.school_income_records(
    id,business_entity_id,student_id,income_date,year_month,settlement_month,
    income_category,description,currency,amount,amount_cny,payment_currency,
    status,is_taxable_income,receipt_status,include_in_student_settlement,
    note,app_type,operational_excluded
  ) values
    (v_income_b,v_entity,v_student_b,date '2020-01-15','2020-01','2020-01',
      'tuition',v_marker,'CNY',1000,1000,'CNY','received',false,'codex-test',true,v_marker,'school',false),
    (v_income_c,v_entity,v_student_c,date '2020-02-15','2020-02','2020-02',
      'tuition',v_marker,'CNY',1000,1000,'CNY','received',false,'codex-test',true,v_marker,'school',false);

  insert into public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,preset_exchange_rate,
    system_difference_cny,adjustment_amount_cny,carryover_amount_cny,
    settlement_status,locked_at,note
  ) values
    (v_settlement_a,v_student_a,'2020-01',v_entity,0.05,10,0,10,'locked',now(),v_marker),
    (v_settlement_d,v_student_d,'2020-04',v_entity,0.05,5,0,5,'locked',now(),v_marker);

  insert into public.school_student_settlement_adjustment_drafts(
    id,student_id,year_month,business_entity_id,adjustment_amount_cny,
    adjustment_source,adjustment_reason,note,status,settlement_id,app_type
  ) values (v_draft_a,v_student_a,'2020-01',v_entity,1,'manual',v_marker,v_marker,'active',v_settlement_a,'school');
  insert into public.school_student_settlement_adjustments(
    id,settlement_id,student_id,year_month,business_entity_id,
    adjustment_amount_cny,adjustment_source,adjustment_reason,note,status,app_type
  ) values (v_adjustment_a,v_settlement_a,v_student_a,'2020-01',v_entity,1,'manual',v_marker,v_marker,'posted','school');
  insert into public.school_student_settlement_carryovers(
    id,student_id,from_year_month,to_year_month,amount_cny,
    source_settlement_id,source_settlement_month,status,note
  ) values (v_carryover_a,v_student_a,'2020-01','2020-02',10,v_settlement_a,'2020-01','inactive',v_marker);

  insert into public.school_tuition_atomic_writer_context(
    backend_pid,transaction_id,writer_source
  ) values (pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  insert into public.school_student_tuition_bills(
    id,student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,billing_role,cash_submission_blocked
  ) values (
    v_bill_a,v_student_a,v_entity,'2020-02','2020-01',v_settlement_a,10,
    1,1,100,100,'JPY','draft','{}'::jsonb,v_marker,'school','canonical_charge',false
  );
  insert into public.school_student_tuition_billing_identities(
    id,student_id,billing_month,canonical_bill_id,creation_idempotency_key,
    source,created_by,evidence
  ) values (
    v_identity_a,v_student_a,'2020-02',v_bill_a,
    'codex-test:tuition-p0a-concurrency-20260803','atomic_charge',v_marker,'{}'::jsonb
  );

  if public.school_tuition_p0a_consumed_bill_id(v_settlement_a)<>v_bill_a then
    raise exception 'TUITION_P0A_CONSUMED_RESOLVER_FAILED';
  end if;
  insert into tuition_p0a_test_results values
    ('consumed_resolver',true,'active canonical identity/bill/previous_settlement_id resolved');

  begin
    perform * from public.school_unlock_student_monthly_settlement(v_settlement_a,v_marker);
    raise exception 'EXPECTED_CONSUMED_UNLOCK_FAILURE_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_relock_student_monthly_settlement(v_settlement_a,v_marker);
    raise exception 'EXPECTED_CONSUMED_RELOCK_FAILURE_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student_a,'2020-01',1,'manual',v_marker,v_marker);
    raise exception 'EXPECTED_CONSUMED_DRAFT_RPC_FAILURE_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  insert into tuition_p0a_test_results values
    ('consumed_rpc_guards',true,'unlock/revoke, relock and draft RPC return stable consumed error');

  select to_jsonb(row_value) into v_before
  from public.school_student_monthly_settlements row_value where id=v_settlement_a;
  begin
    update public.school_student_monthly_settlements set note='must fail' where id=v_settlement_a;
    raise exception 'EXPECTED_CONSUMED_SETTLEMENT_UPDATE_FAILURE_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  if (select to_jsonb(row_value) from public.school_student_monthly_settlements row_value where id=v_settlement_a)<>v_before then
    raise exception 'TUITION_P0A_FAILED_UPDATE_CHANGED_SETTLEMENT';
  end if;
  insert into tuition_p0a_test_results values
    ('consumed_settlement_direct_update',true,'stable error and row unchanged');

  begin insert into public.school_student_settlement_adjustment_drafts(
    id,student_id,year_month,business_entity_id,adjustment_amount_cny,
    adjustment_source,adjustment_reason,status,app_type
  ) values ('a0a00000-0000-4000-8000-00000000c011',v_student_a,'2020-01',v_entity,1,'manual',v_marker,'active','school');
    raise exception 'EXPECTED_CONSUMED_DRAFT_INSERT_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin update public.school_student_settlement_adjustment_drafts set note='must fail' where id=v_draft_a;
    raise exception 'EXPECTED_CONSUMED_DRAFT_UPDATE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin delete from public.school_student_settlement_adjustment_drafts where id=v_draft_a;
    raise exception 'EXPECTED_CONSUMED_DRAFT_DELETE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  insert into tuition_p0a_test_results values ('consumed_draft_direct_dml',true,'insert/update/delete rejected');

  begin insert into public.school_student_settlement_adjustments(
    id,settlement_id,student_id,year_month,business_entity_id,
    adjustment_amount_cny,adjustment_source,adjustment_reason,status,app_type
  ) values ('a0a00000-0000-4000-8000-00000000c012',v_settlement_a,v_student_a,'2020-01',v_entity,1,'manual',v_marker,'posted','school');
    raise exception 'EXPECTED_CONSUMED_ADJUSTMENT_INSERT_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin update public.school_student_settlement_adjustments set note='must fail' where id=v_adjustment_a;
    raise exception 'EXPECTED_CONSUMED_ADJUSTMENT_UPDATE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin delete from public.school_student_settlement_adjustments where id=v_adjustment_a;
    raise exception 'EXPECTED_CONSUMED_ADJUSTMENT_DELETE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  insert into tuition_p0a_test_results values ('consumed_adjustment_direct_dml',true,'insert/update/delete rejected');

  begin insert into public.school_student_settlement_carryovers(
    id,student_id,from_year_month,to_year_month,amount_cny,source_settlement_id,
    source_settlement_month,status,note
  ) values ('a0a00000-0000-4000-8000-00000000c013',v_student_a,'2020-01','2020-02',1,v_settlement_a,'2020-01','inactive',v_marker);
    raise exception 'EXPECTED_CONSUMED_CARRYOVER_INSERT_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin update public.school_student_settlement_carryovers set note='must fail' where id=v_carryover_a;
    raise exception 'EXPECTED_CONSUMED_CARRYOVER_UPDATE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  begin delete from public.school_student_settlement_carryovers where id=v_carryover_a;
    raise exception 'EXPECTED_CONSUMED_CARRYOVER_DELETE_FAILURE_MISSING';
  exception when others then if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if; end;
  insert into tuition_p0a_test_results values ('consumed_carryover_direct_dml',true,'insert/update/delete rejected');

  perform * from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student_b,'2020-01',2,'manual',v_marker,v_marker);
  select settlement_id into strict v_locked_b
  from public.school_lock_student_monthly_settlement(v_student_b,'2020-01',v_marker);
  if (select settlement_status from public.school_student_monthly_settlements where id=v_locked_b)<>'locked' then
    raise exception 'TUITION_P0A_UNCONSUMED_LOCK_FAILED';
  end if;
  insert into tuition_p0a_test_results values ('unconsumed_draft_and_lock',true,'legal draft and first lock remain available');

  select settlement_id into strict v_locked_c
  from public.school_lock_student_monthly_settlement(v_student_c,'2020-02',v_marker);
  perform * from public.school_unlock_student_monthly_settlement(v_locked_c,v_marker);
  perform * from public.school_relock_student_monthly_settlement(v_locked_c,v_marker);
  if (select settlement_status from public.school_student_monthly_settlements where id=v_locked_c)<>'locked' then
    raise exception 'TUITION_P0A_UNCONSUMED_UNLOCK_RELOCK_FAILED';
  end if;
  insert into tuition_p0a_test_results values ('unconsumed_unlock_relock',true,'legal unlock and relock remain available');

  insert into public.school_student_settlement_carryovers(
    id,student_id,from_year_month,to_year_month,amount_cny,
    source_settlement_id,source_settlement_month,status,note
  ) values (v_carryover_d,v_student_d,'2020-04','2020-05',5,v_settlement_d,'2020-04','active',v_marker);
  if (select amount_cny from public.school_student_settlement_carryovers where id=v_carryover_d)<>5 then
    raise exception 'TUITION_P0A_UNCONSUMED_CARRYOVER_FAILED';
  end if;
  insert into tuition_p0a_test_results values ('unconsumed_carryover',true,'owner path create/read remains available for unconsumed source');

  if has_table_privilege('anon','public.school_student_monthly_settlements','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated','public.school_student_settlement_carryovers','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role','public.school_student_settlement_adjustments','INSERT,UPDATE,DELETE,TRUNCATE')
     or not has_table_privilege('anon','public.school_student_monthly_settlements','SELECT')
     or not has_function_privilege('anon','public.school_unlock_student_monthly_settlement(uuid,text)','EXECUTE')
     or has_function_privilege('anon','public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text)','EXECUTE') then
    raise exception 'TUITION_P0A_PERMISSION_MATRIX_FAILED';
  end if;
  insert into tuition_p0a_test_results values ('permission_catalog',true,'direct DML false, SELECT and formal RPC true, owner helper false');
end
$fixture_and_tests$;

set local role anon;
select count(*)>=0 as anon_select_available
from public.school_student_monthly_settlements;
do $anon_dml$
begin
  begin
    insert into public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id,settlement_status
    ) values (
      'a0a00000-0000-4000-8000-00000000b099',
      'a0a00000-0000-4000-8000-00000000a004','2020-09',
      'a0a00000-0000-4000-8000-00000000e001','draft'
    );
    raise exception 'EXPECTED_ANON_INSERT_DENIAL_MISSING';
  exception when insufficient_privilege then null; end;
  begin
    update public.school_student_monthly_settlements set note='must fail'
    where id='a0a00000-0000-4000-8000-00000000b004';
    raise exception 'EXPECTED_ANON_UPDATE_DENIAL_MISSING';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.school_student_monthly_settlements
    where id='a0a00000-0000-4000-8000-00000000b004';
    raise exception 'EXPECTED_ANON_DELETE_DENIAL_MISSING';
  exception when insufficient_privilege then null; end;
end
$anon_dml$;
reset role;

insert into tuition_p0a_test_results values
  ('anon_runtime_permissions',true,'SELECT succeeded; direct INSERT/UPDATE/DELETE raised insufficient_privilege');

select * from tuition_p0a_test_results order by test_name;

do $verify$
begin
  if (select count(*) from tuition_p0a_test_results)<>11
     or exists (select 1 from tuition_p0a_test_results where not passed) then
    raise exception 'TUITION_P0A_ROLLBACK_TEST_MATRIX_FAILED';
  end if;
end
$verify$;

rollback;
\echo 'TUITION_P0A_ROLLBACK_TESTS_PASSED_AND_ROLLED_BACK'
