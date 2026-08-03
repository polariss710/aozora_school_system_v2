-- Exact reverse of the P0-C anonymous-record return fix.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0_c_rollback_commit}
\else
  \echo 'P0_C_ROLLBACK_COMMIT_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $rollback_fix$
declare
  v_signature constant regprocedure :=
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure;
  v_fixed constant text := $return$
return query select
      v_result.tuition_bill_id::uuid,
      v_result.billing_identity_id::uuid,
      v_result.income_record_id::uuid,
      v_result.student_id::uuid,
      v_result.business_entity_id::uuid,
      v_result.billing_month::text,
      v_result.generation_manifest_sha256::text,
      v_result.candidate_count::integer,
      v_result.total_lesson_count::integer,
      v_result.total_duration_hours::numeric,
      v_result.total_base_lesson_fee_jpy::numeric,
      v_result.total_aircon_fee_jpy::numeric,
      v_result.total_fee_jpy::numeric,
      v_result.billing_exchange_rate::numeric,
      v_result.previous_carryover_cny::numeric,
      v_result.billing_amount_cny::numeric,
      v_result.bill_status::text,
      v_result.income_status::text,
      v_result.idempotent::boolean,
      v_result.message::text;
    return;$return$;
  v_original constant text := 'return query select v_result.*; return;';
  v_before text;
  v_expected text;
  v_after text;
  v_before_contract jsonb;
  v_after_contract jsonb;
begin
  select pg_get_functiondef(v_signature),jsonb_build_object(
    'identity_arguments',pg_get_function_identity_arguments(p.oid),
    'result_type',pg_get_function_result(p.oid),
    'proargnames',p.proargnames,'proallargtypes',p.proallargtypes,
    'proargmodes',p.proargmodes,'proowner',p.proowner,'prosecdef',p.prosecdef,
    'provolatile',p.provolatile,'proparallel',p.proparallel,
    'proleakproof',p.proleakproof,'procost',p.procost,'prorows',p.prorows,
    'proconfig',p.proconfig,'proacl',p.proacl
  ) into strict v_before,v_before_contract
  from pg_proc p where p.oid=v_signature;

  if md5(v_before)<>'95a68598215b61f55e5b63c74eeaa3f1' then
    raise exception 'P0_C_ROLLBACK_FIXED_MD5_DRIFT';
  end if;
  if (length(v_before)-length(replace(v_before,v_fixed,'')))/length(v_fixed)<>1 then
    raise exception 'P0_C_ROLLBACK_TARGET_NOT_EXACTLY_ONCE';
  end if;

  v_expected:=replace(v_before,v_fixed,v_original);
  execute v_expected;

  select pg_get_functiondef(v_signature),jsonb_build_object(
    'identity_arguments',pg_get_function_identity_arguments(p.oid),
    'result_type',pg_get_function_result(p.oid),
    'proargnames',p.proargnames,'proallargtypes',p.proallargtypes,
    'proargmodes',p.proargmodes,'proowner',p.proowner,'prosecdef',p.prosecdef,
    'provolatile',p.provolatile,'proparallel',p.proparallel,
    'proleakproof',p.proleakproof,'procost',p.procost,'prorows',p.prorows,
    'proconfig',p.proconfig,'proacl',p.proacl
  ) into strict v_after,v_after_contract
  from pg_proc p where p.oid=v_signature;

  if v_after<>v_expected or md5(v_after)<>'03854d804871fbea5f9c9ddec6d33aa6' then
    raise exception 'P0_C_ROLLBACK_ORIGINAL_DEFINITION_NOT_RESTORED';
  end if;
  if v_after_contract is distinct from v_before_contract then
    raise exception 'P0_C_ROLLBACK_FUNCTION_CONTRACT_DRIFT';
  end if;
end;
$rollback_fix$;

\if :p0_c_rollback_commit
  commit;
  \echo 'P0_C_EXPLICIT_RETURN_FIX_ROLLED_BACK'
\else
  rollback;
  \echo 'P0_C_EXPLICIT_RETURN_ROLLBACK_REHEARSAL_ROLLED_BACK'
\endif
