-- Production ROLLBACK rehearsal. No synthetic business rows are created.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

create temp table rehearsal_no_clearance_baseline on commit drop as
select to_jsonb(aggregate_row) as result_json
from public.school_get_student_duration_overage_aggregate(
  '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07'
) aggregate_row;

create temp table rehearsal_locked_baseline on commit drop as
select to_jsonb(aggregate_row) as result_json
from public.school_get_student_duration_overage_aggregate(
  'eb705aad-de4d-45e6-a391-42dcdd89aeda','2026-07'
) aggregate_row;

create temp table rehearsal_target_rows_baseline on commit drop as
select
  (select md5(to_jsonb(row_value)::text)
   from public.school_lesson_records row_value
   where id='e58457a1-89c5-441b-9bcb-73ffc6168d8a') as lesson_md5,
  (select md5(to_jsonb(row_value)::text)
   from public.school_lesson_clearances row_value
   where id='cbf5e5f9-8397-4bea-8297-e66a3ebdb32b') as clearance_md5,
  (select md5(to_jsonb(row_value)::text)
   from public.school_lesson_clearance_details row_value
   where id='3fdfd160-8c73-4a7d-8a5c-49d03b3306e3') as detail_md5,
  (select md5(to_jsonb(row_value)::text)
   from public.school_student_package_credit_lots row_value
   where id='2a000000-0000-4000-8000-202608170002') as package_md5;

do $baseline$
declare
  v_preview jsonb;
begin
  if md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
     ))<>'d24b82f51053b3960ce0e4839613ddc7' then
    raise exception 'REHEARSAL_OLD_DEFINITION_DRIFT';
  end if;
  v_preview:=public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',
    'separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  if (v_preview#>>'{preview,system_difference_cny}')::numeric<>373.50
     or (v_preview#>>'{preview,registered_overage_hours}')::numeric<>0 then
    raise exception 'REHEARSAL_TARGET_BASELINE_DRIFT';
  end if;
end
$baseline$;

\set SCHOOL_CLEARANCE_OVERAGE_AGGREGATE_REHEARSAL 1
\ir school_duration_overage_clearance_aware_aggregate_20260818.sql

do $deployed_assertions$
declare
  v_preview jsonb;
  v_status jsonb;
  v_row record;
  v_expected jsonb;
begin
  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd','2026-08'
  );
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count,
      v_row.aggregation_basis)
     is distinct from (0,0::numeric,0::numeric,0,'live_s1_b_actual_aggregate'::text) then
    raise exception 'REHEARSAL_TARGET_AGGREGATE_NOT_ZERO: %',to_jsonb(v_row);
  end if;

  v_preview:=public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-08',
    'separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  if (v_preview#>>'{preview,base_receivable_difference_cny}')::numeric<>0
     or (v_preview#>>'{preview,system_difference_cny}')::numeric<>0
     or (v_preview#>>'{preview,projected_final_carryover_cny}')::numeric<>0
     or (v_preview#>>'{preview,registered_pending_hours}')::numeric<>6
     or (v_preview#>>'{preview,registered_pending_amount_jpy}')::numeric<>54000
     or (v_preview#>>'{preview,registered_overage_hours}')::numeric<>0
     or (v_preview#>>'{preview,registered_overage_amount_jpy}')::numeric<>0
     or v_preview#>>'{preview,registered_net_direction}'<>'pending'
     or (v_preview#>>'{preview,registered_net_hours}')::numeric<>6
     or (v_preview#>>'{preview,registered_net_amount_jpy}')::numeric<>54000
     or (v_preview#>>'{preview,unresolved_planned_count}')::integer<>6 then
    raise exception 'REHEARSAL_TARGET_PREVIEW_WRONG: %',v_preview->'preview';
  end if;

  v_status:=public.school_get_student_monthly_settlement_online_status_core(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd','2026-08'
  );
  if (v_status->>'can_save')::boolean
     or (v_status->>'can_lock')::boolean
     or v_status->>'save_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED'
     or v_status->>'lock_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED'
     or (v_status->>'authoritative_system_difference_cny')::numeric<>0 then
    raise exception 'REHEARSAL_MONTH_GATE_CHANGED: %',v_status;
  end if;

  select result_json into strict v_expected from rehearsal_no_clearance_baseline;
  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07'
  );
  if to_jsonb(v_row) is distinct from v_expected then
    raise exception 'REHEARSAL_NO_CLEARANCE_REGRESSION: old %, new %',
      v_expected,to_jsonb(v_row);
  end if;

  select result_json into strict v_expected from rehearsal_locked_baseline;
  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda','2026-07'
  );
  if to_jsonb(v_row) is distinct from v_expected then
    raise exception 'REHEARSAL_LOCKED_SNAPSHOT_REGRESSION: old %, new %',
      v_expected,to_jsonb(v_row);
  end if;

  if md5(pg_get_functiondef(
       'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure::oid
     ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
       'public.school_guard_variance_claim_clearance_mutex()'::regprocedure::oid
     ))<>'23b080faf3243b2c5dcb86f780b08bc3' then
    raise exception 'REHEARSAL_CLAIM_OR_WRITER_CONTRACT_CHANGED';
  end if;
end
$deployed_assertions$;

-- Exercise the exact rollback inside the same outer transaction.
\ir school_duration_overage_clearance_aware_aggregate_exact_rollback_20260818.sql

do $exact_rollback_assertions$
begin
  if md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
     ))<>'d24b82f51053b3960ce0e4839613ddc7' then
    raise exception 'REHEARSAL_EXACT_ROLLBACK_NOT_EXACT';
  end if;
end
$exact_rollback_assertions$;

-- Reapply once to prove the same-byte deployment remains deterministic, then
-- leave no persistent catalog or business change by rolling back the outer tx.
\ir school_duration_overage_clearance_aware_aggregate_20260818.sql

do $final_transaction_assertions$
declare
  v_baseline rehearsal_target_rows_baseline%rowtype;
begin
  select * into strict v_baseline from rehearsal_target_rows_baseline;
  if v_baseline.lesson_md5<>(select md5(to_jsonb(row_value)::text)
       from public.school_lesson_records row_value
       where id='e58457a1-89c5-441b-9bcb-73ffc6168d8a')
     or v_baseline.clearance_md5<>(select md5(to_jsonb(row_value)::text)
       from public.school_lesson_clearances row_value
       where id='cbf5e5f9-8397-4bea-8297-e66a3ebdb32b')
     or v_baseline.detail_md5<>(select md5(to_jsonb(row_value)::text)
       from public.school_lesson_clearance_details row_value
       where id='3fdfd160-8c73-4a7d-8a5c-49d03b3306e3')
     or v_baseline.package_md5<>(select md5(to_jsonb(row_value)::text)
       from public.school_student_package_credit_lots row_value
       where id='2a000000-0000-4000-8000-202608170002') then
    raise exception 'REHEARSAL_BUSINESS_ROW_CHANGED';
  end if;
  if (select count(*) from public.school_lesson_clearances)<>1
     or (select count(*) from public.school_lesson_clearance_details)<>1
     or (select count(*) from public.school_lesson_clearances
         where clearance_type='reversal')<>0 then
    raise exception 'REHEARSAL_CLEARANCE_LEDGER_CHANGED';
  end if;
  raise notice 'CLEARANCE_AWARE_OVERAGE_PRODUCTION_REHEARSAL_PASS';
end
$final_transaction_assertions$;

rollback;
