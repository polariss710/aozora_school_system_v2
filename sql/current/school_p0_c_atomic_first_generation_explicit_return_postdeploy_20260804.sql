-- P0-C narrow-fix postdeploy verification. Read-only by construction.
\set ON_ERROR_STOP on
\pset pager off

begin transaction read only;
set local statement_timeout='120s';

do $verify$
declare
  v_signature constant regprocedure :=
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure;
  v_definition text;
  v_proc pg_proc%rowtype;
begin
  select p,pg_get_functiondef(p.oid)
  into strict v_proc,v_definition
  from pg_proc p where p.oid=v_signature;

  if md5(v_definition)<>'95a68598215b61f55e5b63c74eeaa3f1' then
    raise exception 'P0_C_EXPLICIT_RETURN_DEFINITION_MD5_INVALID';
  end if;
  if position('return query select v_result.*; return;' in v_definition)<>0
     or position('v_result.tuition_bill_id::uuid' in v_definition)=0
     or position('v_result.message::text;' in v_definition)=0 then
    raise exception 'P0_C_EXPLICIT_RETURN_BODY_INVALID';
  end if;
  if (length(v_definition)-length(replace(
      v_definition,'school_generate_student_tuition_bill_atomic_base_core_v1(',''
    )))/length('school_generate_student_tuition_bill_atomic_base_core_v1(')<>1 then
    raise exception 'P0_C_BASE_CORE_CALL_COUNT_INVALID';
  end if;
  if pg_get_function_identity_arguments(v_signature)<>
       'p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text, p_test_fail_after_step text'
     or pg_get_function_result(v_signature)<>
       'TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)'
     or v_proc.proargmodes::text<>'{i,i,i,i,i,i,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
     or v_proc.proallargtypes::text<>'{2950,25,1700,25,25,25,2950,2950,2950,2950,2950,25,25,23,23,1700,1700,1700,1700,1700,1700,1700,25,25,16,25}' then
    raise exception 'P0_C_FUNCTION_SIGNATURE_OR_RESULT_CONTRACT_INVALID';
  end if;
  if pg_get_userbyid(v_proc.proowner)<>'postgres'
     or not v_proc.prosecdef or v_proc.provolatile<>'v'
     or v_proc.proparallel<>'u' or v_proc.proleakproof
     or v_proc.procost<>100 or v_proc.prorows<>1000
     or v_proc.proconfig::text<>'{"search_path=pg_catalog, public"}'
     or v_proc.proacl::text<>'{postgres=X/postgres}' then
    raise exception 'P0_C_FUNCTION_ATTRIBUTES_OR_ACL_INVALID';
  end if;
  if has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('authenticated',v_signature,'EXECUTE')
     or has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'P0_C_FUNCTION_EXECUTE_ACL_INVALID';
  end if;
  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='enabled')
         or (feature_key in ('student_tuition_generate','student_tuition_cash_submit') and state='blocked'))<>3 then
    raise exception 'P0_C_REQUIRED_GATE_STATE_INVALID';
  end if;
end;
$verify$;

select md5(pg_get_functiondef(
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
)) as p0_c_explicit_return_definition_md5;
select feature_key,state from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;
rollback;
