-- Read-only postdeploy acceptance for registered lesson variance Preview fields.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

do $catalog_acceptance$
declare
  v_signature constant regprocedure :=
    'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure;
  v_acl text;
begin
  select coalesce(array_to_string(p.proacl,','),'') into v_acl
  from pg_proc p where p.oid=v_signature::oid;
  if md5(pg_get_functiondef(v_signature::oid))<>'13fe9c288069ae785887559e6b475138'
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid))<>'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or v_acl ~ '(^|,)=X/'
     or not has_function_privilege('anon',v_signature,'EXECUTE')
     or not has_function_privilege('authenticated',v_signature,'EXECUTE')
     or not has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'REGISTERED_VARIANCE_PREVIEW_CATALOG_ACCEPTANCE_FAILED: %',v_acl;
  end if;
end
$catalog_acceptance$;

do $payload_acceptance$
declare
  v_result jsonb;
  v_preview jsonb;
  v_status jsonb;
begin
  v_result:=public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  );
  v_preview:=v_result->'preview';
  if v_preview->>'registered_variance_contract_version'
       <>'registered_lesson_variance_summary_v1'
     or v_preview->>'variance_summary_status'<>'ready'
     or (v_preview->>'registered_pending_hours')::numeric<>7
     or (v_preview->>'registered_pending_amount_jpy')::numeric<>63000
     or (v_preview->>'registered_overage_hours')::numeric<>1
     or (v_preview->>'registered_overage_amount_jpy')::numeric<>9000
     or (v_preview->>'registered_overage_amount_cny')::numeric<>373.50
     or v_preview->>'registered_net_direction'<>'pending'
     or (v_preview->>'registered_net_hours')::numeric<>6
     or (v_preview->>'registered_net_amount_jpy')::numeric<>54000
     or (v_preview->>'registered_source_count')::integer<>5
     or (v_preview->>'unresolved_planned_count')::integer<>6
     or (v_preview->>'registered_overage_included_in_system_difference')::boolean is not true
     or (v_preview->>'variance_summary_manifest_sha256')!~'^[0-9a-f]{64}$' then
    raise exception 'REGISTERED_VARIANCE_PREVIEW_PAYLOAD_ACCEPTANCE_FAILED: %',v_preview;
  end if;
  if (v_preview->>'pending_makeup_hours')::numeric<>0
     or (v_preview->>'unused_planned_credit_jpy')::numeric<>0
     or (v_preview->>'overage_hours')::numeric<>0
     or (v_preview->>'overage_charge_jpy')::numeric<>0
     or (v_preview->>'net_lesson_variance_jpy')::numeric<>0
     or (v_preview->>'net_lesson_variance_cny')::numeric<>0
     or (v_preview->>'system_difference_cny')::numeric<>373.50
     or v_result->>'preview_manifest_sha256'
        <>'53403da32a891321be8d12dadd157548b5680dd8b0e2d74e7ce412847a80f85d' then
    raise exception 'REGISTERED_VARIANCE_PREVIEW_OLD_FIELDS_CHANGED: %',v_result;
  end if;
  begin
    perform * from public.school_preview_student_settlement_source_treatment(
      '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
      '2026-08','net_lesson_variance_to_financial_credit_v1',0.0415,
      'registered_variance_postdeploy','2026-08-16'::date
    );
    raise exception 'REGISTERED_VARIANCE_NET_FAIL_CLOSED_MISSING';
  exception when others then
    if position('SETTLEMENT_LESSON_SOURCE_UNRESOLVED' in sqlerrm)=0 then raise; end if;
  end;
  v_status:=public.school_get_student_monthly_settlement_online_status_core(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,'2026-08'
  );
  if (v_status->>'can_save')::boolean is not false
     or (v_status->>'can_lock')::boolean is not false
     or v_status->>'save_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED' then
    raise exception 'REGISTERED_VARIANCE_CURRENT_MONTH_GATE_CHANGED: %',v_status;
  end if;
end
$payload_acceptance$;

select
  preview->>'registered_pending_hours' as registered_pending_hours,
  preview->>'registered_pending_amount_jpy' as registered_pending_amount_jpy,
  preview->>'registered_overage_hours' as registered_overage_hours,
  preview->>'registered_overage_amount_jpy' as registered_overage_amount_jpy,
  preview->>'registered_overage_amount_cny' as registered_overage_amount_cny,
  preview->>'registered_net_direction' as registered_net_direction,
  preview->>'registered_net_hours' as registered_net_hours,
  preview->>'registered_net_amount_jpy' as registered_net_amount_jpy,
  preview->>'unresolved_planned_count' as unresolved_planned_count,
  preview->>'system_difference_cny' as system_difference_cny,
  preview->>'variance_summary_manifest_sha256' as variance_summary_manifest_sha256
from (
  select public.school_preview_student_settlement_adjustment_dialog(
    '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08','separate_makeup_and_overage_v1',null,null,null,
    'carry_final_balance',null
  )->'preview' as preview
) target;

select object_name,row_count,row_hash
from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'source_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_source_treatment_drafts x
  union all select 4,'adjustment_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_adjustment_drafts x
  union all select 5,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 6,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 7,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 8,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 9,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 10,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 11,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 12,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
  union all select 13,'storage_objects',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
) fingerprints
order by sort_order;

select 'SCHOOL_REGISTERED_VARIANCE_PREVIEW_POSTDEPLOY_READONLY_PASS' as result;
rollback;
