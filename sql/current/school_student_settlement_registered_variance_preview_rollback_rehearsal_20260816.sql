-- Production rollback rehearsal for the registered variance Preview extension.
-- Both phases end in ROLLBACK; no business DML or persistent catalog changes.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

\ir school_student_settlement_registered_variance_preview_20260816.sql
\ir school_student_settlement_registered_variance_preview_exact_rollback_20260816.sql

select 'EXACT_ROLLBACK_REHEARSAL_PASS' as result;
rollback;

begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

\ir school_student_settlement_registered_variance_preview_20260816.sql

do $target_acceptance$
declare
  v_result jsonb;
  v_preview jsonb;
  v_status jsonb;
begin
  v_result := public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08',
    'separate_makeup_and_overage_v1',
    null,
    null,
    null,
    'carry_final_balance',
    null
  );
  v_preview := v_result->'preview';

  if v_preview->>'variance_summary_status' <> 'ready'
     or (v_preview->>'registered_pending_hours')::numeric <> 7
     or (v_preview->>'registered_pending_amount_jpy')::numeric <> 63000
     or (v_preview->>'registered_overage_hours')::numeric <> 1
     or (v_preview->>'registered_overage_amount_jpy')::numeric <> 9000
     or (v_preview->>'registered_overage_amount_cny')::numeric <> 373.50
     or v_preview->>'registered_net_direction' <> 'pending'
     or (v_preview->>'registered_net_hours')::numeric <> 6
     or (v_preview->>'registered_net_amount_jpy')::numeric <> 54000
     or (v_preview->>'registered_source_count')::integer <> 5
     or (v_preview->>'unresolved_planned_count')::integer <> 6
     or (v_preview->>'registered_overage_included_in_system_difference')::boolean is not true
     or (v_preview->>'variance_summary_manifest_sha256') !~ '^[0-9a-f]{64}$' then
    raise exception 'REGISTERED_VARIANCE_TARGET_SUMMARY_MISMATCH: %', v_preview;
  end if;

  if (v_preview->>'pending_makeup_hours')::numeric <> 0
     or (v_preview->>'unused_planned_credit_jpy')::numeric <> 0
     or (v_preview->>'overage_hours')::numeric <> 0
     or (v_preview->>'overage_charge_jpy')::numeric <> 0
     or (v_preview->>'net_lesson_variance_jpy')::numeric <> 0
     or (v_preview->>'net_lesson_variance_cny')::numeric <> 0
     or (v_preview->>'system_difference_cny')::numeric <> 373.50
     or v_result->>'preview_manifest_sha256'
        <> '53403da32a891321be8d12dadd157548b5680dd8b0e2d74e7ce412847a80f85d' then
    raise exception 'REGISTERED_VARIANCE_OLD_CONTRACT_CHANGED: %', v_result;
  end if;

  begin
    perform *
    from public.school_preview_student_settlement_source_treatment(
      '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
      '2026-08',
      'net_lesson_variance_to_financial_credit_v1',
      0.0415,
      'registered_variance_rehearsal',
      '2026-08-16'::date
    );
    raise exception 'REGISTERED_VARIANCE_NET_UNRESOLVED_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_LESSON_SOURCE_UNRESOLVED' in sqlerrm)=0 then
      raise;
    end if;
  end;

  v_status := public.school_get_student_monthly_settlement_online_status_core(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
    '2026-08'
  );
  if (v_status->>'can_save')::boolean is not false
     or (v_status->>'can_lock')::boolean is not false
     or v_status->>'save_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED' then
    raise exception 'REGISTERED_VARIANCE_CURRENT_MONTH_GATE_CHANGED: %', v_status;
  end if;

  -- Existing production scopes exercise the added projection without fixture DML.
  v_result := public.school_preview_student_settlement_adjustment_dialog(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  v_preview := v_result->'preview';
  if v_preview->>'variance_summary_status'<>'ready'
     or (v_preview->>'registered_pending_hours')::numeric<=0
     or (v_preview->>'registered_overage_hours')::numeric<>0
     or v_preview->>'registered_net_direction'<>'pending' then
    raise exception 'REGISTERED_VARIANCE_PENDING_ONLY_FAILED: %',v_preview;
  end if;

  v_result := public.school_preview_student_settlement_adjustment_dialog(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  v_preview := v_result->'preview';
  if v_preview->>'variance_summary_status'<>'ready'
     or (v_preview->>'registered_pending_hours')::numeric<>0
     or (v_preview->>'registered_overage_hours')::numeric<=0
     or v_preview->>'registered_net_direction'<>'overage' then
    raise exception 'REGISTERED_VARIANCE_OVERAGE_ONLY_FAILED: %',v_preview;
  end if;

  v_result := public.school_preview_student_settlement_adjustment_dialog(
    '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-07','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  v_preview := v_result->'preview';
  if v_preview->>'variance_summary_status'<>'ready'
     or (v_preview->>'registered_pending_hours')::numeric<=0
     or (v_preview->>'registered_overage_hours')::numeric<>0 then
    raise exception 'REGISTERED_VARIANCE_HISTORICAL_MONTH_FAILED: %',v_preview;
  end if;

  v_result := public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-09','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  v_preview := v_result->'preview';
  if v_preview->>'variance_summary_status'<>'empty'
     or (v_preview->>'registered_source_count')::integer<>0
     or (v_preview->>'registered_pending_hours')::numeric<>0
     or (v_preview->>'registered_overage_hours')::numeric<>0 then
    raise exception 'REGISTERED_VARIANCE_EMPTY_FAILED: %',v_preview;
  end if;

  v_result := public.school_preview_student_settlement_adjustment_dialog(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-07','net_lesson_variance_to_financial_credit_v1',0.0415,
    'registered_variance_rehearsal','2026-07-01'::date,
    'carry_final_balance',null
  );
  v_preview := v_result->'preview';
  if (v_preview->>'lesson_variance_source_count')::integer<=0
     or jsonb_array_length(v_preview->'source_lines')<=0
     or (v_preview->>'net_lesson_variance_jpy')::numeric=0 then
    raise exception 'REGISTERED_VARIANCE_NET_MODE_SOURCE_LINES_FAILED: %',v_preview;
  end if;

  if public.school_get_lesson_credit_remaining_hours(
       '8870f57f-bca5-4114-90db-ee592cca2f45'::uuid
     )<>1
     or (
       select count(*)
       from public.school_tuition_p0f_source_lines(
         '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
         '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
         '2026-08',0.0415,false
       ) source_row
       where source_row.source_planned_lesson_id in (
         '44dcd8ac-7303-40cb-92aa-32e91933bd87'::uuid,
         '7154187f-d32b-48f8-9efa-5a60c5a4d6dc'::uuid
       )
     )<>2 then
    raise exception 'REGISTERED_VARIANCE_PARTIAL_OR_FUTURE_CANCELLED_SOURCE_FAILED';
  end if;
end
$target_acceptance$;

select
  md5(pg_get_functiondef(
    'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure
  )) as rehearsal_definition_md5,
  'FORWARD_REHEARSAL_PASS' as result;

rollback;
