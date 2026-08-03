-- P0-C narrow fix: replace only the anonymous first-generation record return
-- with the existing 20-column TABLE contract in explicit order and types.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0_c_fix_commit}
\else
  \echo 'P0_C_FIX_COMMIT_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $cutover$
declare
  v_signature constant regprocedure :=
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure;
  v_old constant text := 'return query select v_result.*; return;';
  v_new constant text := $return$
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

  if md5(v_before)<>'03854d804871fbea5f9c9ddec6d33aa6' then
    raise exception 'P0_C_FIRST_RETURN_BASELINE_MD5_DRIFT';
  end if;
  if (length(v_before)-length(replace(v_before,v_old,'')))/length(v_old)<>1 then
    raise exception 'P0_C_FIRST_RETURN_TARGET_NOT_EXACTLY_ONCE';
  end if;
  if (length(v_before)-length(replace(
      v_before,'school_generate_student_tuition_bill_atomic_base_core_v1(',''
    )))/length('school_generate_student_tuition_bill_atomic_base_core_v1(')<>1 then
    raise exception 'P0_C_BASE_CORE_CALL_COUNT_BASELINE_INVALID';
  end if;

  v_expected:=replace(v_before,v_old,v_new);
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

  if v_after<>v_expected then
    raise exception 'P0_C_FIRST_RETURN_UNEXPECTED_DEFINITION_DIFF';
  end if;
  if v_after_contract is distinct from v_before_contract then
    raise exception 'P0_C_FIRST_RETURN_FUNCTION_CONTRACT_DRIFT';
  end if;
  if position(v_old in v_after)<>0
     or position(v_new in v_after)=0 then
    raise exception 'P0_C_FIRST_RETURN_REPLACEMENT_INVALID';
  end if;
  if (length(v_after)-length(replace(
      v_after,'school_generate_student_tuition_bill_atomic_base_core_v1(',''
    )))/length('school_generate_student_tuition_bill_atomic_base_core_v1(')<>1 then
    raise exception 'P0_C_BASE_CORE_CALL_COUNT_CHANGED';
  end if;
end;
$cutover$;

select md5(pg_get_functiondef(
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
)) as p0_c_explicit_return_definition_md5;

\if :p0_c_fix_commit
  commit;
  \echo 'P0_C_FIRST_RETURN_FIX_COMMITTED'
\else
  rollback;
  \echo 'P0_C_FIRST_RETURN_FIX_REHEARSAL_ROLLED_BACK'
\endif
