\set ON_ERROR_STOP on
\pset pager off

do $test$
declare
  v_result jsonb;
  v_definition text;
begin
  if to_regprocedure('public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)') is null then
    raise exception 'P0F_DIALOG_PREVIEW_FUNCTION_MISSING';
  end if;
  if not has_function_privilege('anon',
      'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)','EXECUTE')
     or not has_function_privilege('authenticated',
      'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)','EXECUTE')
     or not has_function_privilege('service_role',
      'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)','EXECUTE') then
    raise exception 'P0F_DIALOG_PREVIEW_READER_ACL_INVALID';
  end if;
  if has_function_privilege('anon',
      'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)','EXECUTE')
     or has_function_privilege('anon',
      'public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric)','EXECUTE') then
    raise exception 'P0F_DIALOG_PREVIEW_OWNER_HELPER_EXPOSED';
  end if;

  select pg_get_functiondef(
    'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure
  ) into v_definition;
  if v_definition ~* E'\\m(insert|update|delete|merge|truncate)\\M' then
    raise exception 'P0F_DIALOG_PREVIEW_CONTAINS_BUSINESS_DML';
  end if;
  if position('SET search_path TO ''pg_catalog'', ''public''' in v_definition)=0 then
    raise exception 'P0F_DIALOG_PREVIEW_SEARCH_PATH_INVALID';
  end if;

  select public.school_preview_student_settlement_adjustment_dialog(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-07','net_lesson_variance_to_financial_credit_v1',0.042,
    'business_owner_confirmed_monthly_settlement_rate_v1','2026-07-01'::date,
    'carry_final_balance',null
  ) into v_result;

  if v_result->>'contract_version' is distinct from 'settlement_adjustment_dialog_preview_v1'
     or (v_result->'current_state'->>'is_saved')::boolean
     or (v_result->'preview'->>'pending_makeup_hours')::numeric<>2
     or (v_result->'preview'->>'overage_hours')::numeric<>0.25
     or (v_result->'preview'->>'lesson_variance_display_hours')::numeric<>-1.75
     or (v_result->'preview'->>'unused_planned_credit_jpy')::numeric<>-17000
     or (v_result->'preview'->>'overage_charge_jpy')::numeric<>2125
     or (v_result->'preview'->>'net_lesson_variance_jpy')::numeric<>-14875
     or (v_result->'preview'->>'net_lesson_variance_cny')::numeric<>-624.75
     or (v_result->'preview'->>'system_difference_cny')::numeric<>-624.75
     or (v_result->'preview'->>'projected_adjustment_amount_cny')::numeric<>0
     or (v_result->'preview'->>'projected_final_carryover_cny')::numeric<>-624.75
     or jsonb_array_length(v_result->'preview'->'source_lines')<>2
     or length(v_result->>'preview_manifest_sha256')<>64 then
    raise exception 'P0F_DIALOG_PREVIEW_PENG_RESULT_INVALID: %',v_result;
  end if;
end
$test$;

select
  p.provolatile,
  p.prosecdef,
  p.proconfig,
  p.proacl,
  extensions.digest(pg_get_functiondef(p.oid),'sha256') as function_sha256
from pg_proc p
where p.oid='public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure;
