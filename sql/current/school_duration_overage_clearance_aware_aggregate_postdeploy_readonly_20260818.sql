-- Read-only production acceptance for the deployed aggregate definition.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

do $catalog_assertions$
declare
  v_signature constant regprocedure :=
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_signature::oid))<>'6ca9679d62304830e0161ae6da22a69a'
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid))<>'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.provolatile from pg_proc p where p.oid=v_signature::oid)<>'s'
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or not has_function_privilege('service_role',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('authenticated',v_signature,'EXECUTE') then
    raise exception 'POSTDEPLOY_CATALOG_CONTRACT_FAILED';
  end if;
  if md5(pg_get_functiondef(
       'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure::oid
     ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
       'public.school_guard_variance_claim_clearance_mutex()'::regprocedure::oid
     ))<>'23b080faf3243b2c5dcb86f780b08bc3' then
    raise exception 'POSTDEPLOY_WRITER_OR_CLAIM_MUTEX_CHANGED';
  end if;
end
$catalog_assertions$;

do $business_assertions$
declare
  v_preview jsonb;
  v_status jsonb;
  v_row record;
begin
  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd','2026-08'
  );
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (0,0::numeric,0::numeric,0) then
    raise exception 'POSTDEPLOY_TARGET_AGGREGATE_NOT_ZERO: %',to_jsonb(v_row);
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
    raise exception 'POSTDEPLOY_TARGET_PREVIEW_FAILED: %',v_preview->'preview';
  end if;

  v_status:=public.school_get_student_monthly_settlement_online_status_core(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd','2026-08'
  );
  if (v_status->>'can_save')::boolean
     or (v_status->>'can_lock')::boolean
     or v_status->>'save_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED'
     or v_status->>'lock_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED'
     or (v_status->>'authoritative_system_difference_cny')::numeric<>0 then
    raise exception 'POSTDEPLOY_MONTH_GATE_FAILED: %',v_status;
  end if;

  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-07'
  );
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count,
      v_row.aggregation_basis)
     is distinct from (15,2500::numeric,107.50::numeric,1,
       'live_s1_b_actual_aggregate'::text) then
    raise exception 'POSTDEPLOY_NO_CLEARANCE_REGRESSION: %',to_jsonb(v_row);
  end if;

  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda','2026-07'
  );
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count,
      v_row.aggregation_basis)
     is distinct from (15,2125::numeric,92.44::numeric,1,'locked_snapshot'::text) then
    raise exception 'POSTDEPLOY_LOCKED_SNAPSHOT_REGRESSION: %',to_jsonb(v_row);
  end if;

  if (select count(*) from public.school_lesson_clearances)<>1
     or (select count(*) from public.school_lesson_clearance_details)<>1
     or (select count(*) from public.school_lesson_clearances
         where clearance_type='reversal')<>0
     or public.school_get_lesson_clearance_pending_remaining_minutes(
       '8870f57f-bca5-4114-90db-ee592cca2f45')<>0
     or public.school_get_lesson_clearance_overtime_remaining_minutes(
       'e58457a1-89c5-441b-9bcb-73ffc6168d8a')<>0
     or not exists(select 1 from public.school_student_package_credit_lots
       where id='2a000000-0000-4000-8000-202608170002'
         and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200) then
    raise exception 'POSTDEPLOY_CLEARANCE_OR_PACKAGE_REGRESSION';
  end if;
  raise notice 'CLEARANCE_AWARE_OVERAGE_POSTDEPLOY_READONLY_PASS';
end
$business_assertions$;

select
  md5(pg_get_functiondef(
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
  )) as final_definition_md5,
  pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer,
  p.proconfig as function_config,
  p.proacl as acl
from pg_proc p
where p.oid=
  'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;

rollback;
