-- P0-C blocker classification matrix. Requires the fixed synthetic fixture.
-- Every mutation is inside a subtransaction and the outer transaction rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

do $blockers$
declare
  v_student constant uuid:='c0c00000-0000-4000-8000-00000000a001';
  v_entity constant uuid:='c0c00000-0000-4000-8000-00000000e001';
  v_bill constant uuid:='c0c00000-0000-4000-8000-000000006001';
  v_income constant uuid:='c0c00000-0000-4000-8000-000000007101';
  v_revision constant uuid:='c0c00000-0000-4000-8000-000000004001';
  v_manifest text; v_code text; v_status text; v_i integer;
  v_statuses constant text[]:=array[
    'pending','awaiting_cash_confirmation','cash_rejected','synced'
  ];
  v_ids constant uuid[]:=array[
    'c0c00000-0000-4000-8000-000000008101'::uuid,
    'c0c00000-0000-4000-8000-000000008102'::uuid,
    'c0c00000-0000-4000-8000-000000008103'::uuid,
    'c0c00000-0000-4000-8000-000000008104'::uuid
  ];
begin
  select generation_manifest_sha256 into strict v_manifest
  from public.school_student_tuition_generation_revisions where id=v_revision;

  -- received / settled income classification.
  begin
    insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_void_v1');
    update public.school_income_records set status='received' where id=v_income;
    select blocker_code into strict v_code
    from public.school_get_atomic_tuition_void_preflight(v_income);
    if v_code<>'TUITION_VOID_INCOME_NOT_PENDING' then
      raise exception 'P0C_RECEIVED_BLOCKER_INVALID: %',v_code;
    end if;
    raise exception 'P0C_EXPECTED_SUBTX_ROLLBACK';
  exception when others then
    if sqlerrm<>'P0C_EXPECTED_SUBTX_ROLLBACK' then raise; end if;
  end;

  -- School reservation/linkage states. Awaiting/rejected rows carry request IDs;
  -- synced carries both request and transaction IDs.
  update public.school_feature_gates set state='enabled'
  where feature_key='student_tuition_cash_submit';
  for v_i in 1..cardinality(v_statuses) loop
    v_status:=v_statuses[v_i];
    begin
      insert into public.school_personal_cash_income_linkage_events(
        id,source_id,income_record_id,business_entity_id,cash_user_id,cash_account_id,
        cash_account_name_snapshot,cash_account_type_snapshot,cash_transaction_table,
        cash_transaction_id,currency,amount,idempotency_key,sync_status,note,
        payment_currency,payment_amount,cash_request_id,cash_request_status,
        requested_at,confirmed_at,rejected_at,rejected_reason,synced_at
      ) values(
        v_ids[v_i],v_income,v_income,v_entity,
        'c0c00000-0000-4000-8000-000000009001','c0c00000-0000-4000-8000-000000009002',
        'codex-test P0-C cash account','codex-test','home_jpy_transactions',
        case when v_status='synced' then 'c0c00000-0000-4000-8000-000000009104'::uuid end,
        'JPY',(select amount from public.school_income_records where id=v_income),
        'codex-test-p0c-'||v_status,v_status,'codex-test P0-C blocker',
        'JPY',(select amount from public.school_income_records where id=v_income),
        case when v_status in ('awaiting_cash_confirmation','cash_rejected','synced')
          then ('c0c00000-0000-4000-8000-0000000091'||lpad(v_i::text,2,'0'))::uuid end,
        case v_status when 'awaiting_cash_confirmation' then 'awaiting'
          when 'cash_rejected' then 'rejected' when 'synced' then 'confirmed' end,
        case when v_status<>'pending' then clock_timestamp() end,
        case when v_status='synced' then clock_timestamp() end,
        case when v_status='cash_rejected' then clock_timestamp() end,
        case when v_status='cash_rejected' then 'codex-test rejected' end,
        case when v_status='synced' then clock_timestamp() end
      );
      select blocker_code into strict v_code
      from public.school_get_atomic_tuition_void_preflight(v_income);
      if v_code<>'TUITION_VOID_CASH_FACT_EXISTS' then
        raise exception 'P0C_CASH_BLOCKER_INVALID[%]: %',v_status,v_code;
      end if;
      raise exception 'P0C_EXPECTED_SUBTX_ROLLBACK';
    exception when others then
      if sqlerrm<>'P0C_EXPECTED_SUBTX_ROLLBACK' then raise; end if;
    end;
  end loop;

  -- Locked billing-month settlement is the same downstream blocker used by core.
  begin
    perform * from public.school_lock_student_monthly_settlement(
      v_student,'2020-08','codex-test P0-C settlement blocker');
    select blocker_code into strict v_code
    from public.school_get_atomic_tuition_void_preflight(v_income);
    if v_code<>'TUITION_VOID_DOWNSTREAM_FACT_EXISTS' then
      raise exception 'P0C_SETTLEMENT_BLOCKER_INVALID: %',v_code;
    end if;
    raise exception 'P0C_EXPECTED_SUBTX_ROLLBACK';
  exception when others then
    if sqlerrm<>'P0C_EXPECTED_SUBTX_ROLLBACK' then raise; end if;
  end;

  -- Expected active revision, manifest and historical classification.
  begin
    perform * from public.school_void_atomic_student_tuition_generation(
      v_revision,v_bill,v_income,repeat('0',64),'codex-test manifest mismatch');
    raise exception 'P0C_MANIFEST_MISMATCH_NOT_REJECTED';
  exception when others then
    if position('TUITION_VOID_MANIFEST_MISMATCH' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_void_atomic_student_tuition_generation(
      'c0c00000-0000-4000-8000-000000004099',v_bill,v_income,v_manifest,
      'codex-test non-active revision');
    raise exception 'P0C_NON_ACTIVE_NOT_REJECTED';
  exception when others then
    if position('TUITION_VOID_NOT_ACTIVE_REVISION' in sqlerrm)=0 then raise; end if;
  end;
  select blocker_code into strict v_code
  from public.school_get_atomic_tuition_void_preflight(
    '468ab75b-312e-4ba0-8d8d-8ae2f6ace00e');
  if v_code<>'TUITION_VOID_NOT_ATOMIC' then
    raise exception 'P0C_HISTORICAL_BLOCKER_INVALID: %',v_code;
  end if;

  -- A broken manifest/validator chain is reported with the stable manifest code.
  begin
    insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_void_v1');
    update public.school_income_records
    set source_snapshot=jsonb_set(source_snapshot,'{generation_manifest_sha256}',
      to_jsonb(repeat('f',64)),false)
    where id=v_income;
    select blocker_code into strict v_code
    from public.school_get_atomic_tuition_void_preflight(v_income);
    if v_code<>'TUITION_VOID_MANIFEST_MISMATCH' then
      raise exception 'P0C_INCOMPLETE_CHAIN_BLOCKER_INVALID: %',v_code;
    end if;
    raise exception 'P0C_EXPECTED_SUBTX_ROLLBACK';
  exception when others then
    if sqlerrm<>'P0C_EXPECTED_SUBTX_ROLLBACK' then raise; end if;
  end;
end;
$blockers$;

rollback;
\echo 'P0C_BLOCKER_MATRIX_ROLLED_BACK'
