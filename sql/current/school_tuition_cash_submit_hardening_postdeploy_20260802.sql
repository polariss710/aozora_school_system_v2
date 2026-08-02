-- School V2 tuition Cash hardening read-only postdeploy, 2026-08-02.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select feature_key, state, release_version, evidence_hash
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview', 'student_tuition_generate', 'student_tuition_cash_submit'
)
order by feature_key;

select p.oid::regprocedure as signature,
       md5(pg_get_functiondef(p.oid)) as md5,
       p.prosecdef,
       array_to_string(p.proacl, ',') as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'school_get_cash_income_submission_preflight',
    'school_guard_r0_tuition_business_mutation',
    'school_request_cash_income_confirmation_for_record',
    'school_mark_cash_income_request_submitted',
    'school_mark_cash_income_confirmed',
    'school_mark_cash_income_rejected'
  )
order by p.oid::regprocedure::text;

select
  (select count(*) from public.school_student_tuition_bills) as bill_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.school_student_tuition_bills row_value) as bill_md5,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.school_income_records row_value) as income_md5,
  (select count(*) from public.school_personal_cash_income_linkage_events) as linkage_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
   from public.school_personal_cash_income_linkage_events row_value) as linkage_md5,
  (select count(*) from public.school_tuition_atomic_writer_context) as writer_context_count;

select bill.id as bill_id, income.id as income_id, bill.student_id,
       bill.billing_month, bill.bill_amount_jpy, bill.billing_exchange_rate,
       bill.billing_amount_cny, bill.previous_carryover_cny, income.status
from public.school_student_tuition_bills bill
join public.school_income_records income on income.id = bill.income_record_id
where bill.id = '3435cbac-adc5-4bec-a54c-cefaab593359';

do $assert$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'TUITION_CASH_POSTDEPLOY_GATE_FAILED';
  end if;
  if md5(pg_get_functiondef('public.school_get_cash_income_submission_preflight(uuid[])'::regprocedure))
       <> '23aa4f04fa20053e4b38af49067c6a2f'
     or md5(pg_get_functiondef('public.school_guard_r0_tuition_business_mutation()'::regprocedure))
       <> '98f6ff8612a1b68b0a15cbb4e936852f'
     or md5(pg_get_functiondef('public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)'::regprocedure))
       <> '52bf4699b4cdcf3c6199b51f6ec968a4'
     or md5(pg_get_functiondef('public.school_mark_cash_income_rejected(uuid,uuid,text,timestamptz)'::regprocedure))
       <> '9624b50b23f24ddff02d8c972e360d35'
     or md5(pg_get_functiondef('public.school_mark_cash_income_request_submitted(uuid,uuid,text)'::regprocedure))
       <> '157024c648f055457447d81cd3cb4d54'
     or md5(pg_get_functiondef('public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)'::regprocedure))
       <> '02fc85dc099adf6cd6465f53df672d15' then
    raise exception 'TUITION_CASH_POSTDEPLOY_FUNCTION_FAILED';
  end if;
  if has_function_privilege('anon', 'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE') then
    raise exception 'TUITION_CASH_POSTDEPLOY_ACL_FAILED';
  end if;
  if (select count(*) from public.school_student_tuition_bills) <> 17
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_student_tuition_bills row_value) <> 'b18f15673637280bf1455667ccd3cc00'
     or (select count(*) from public.school_income_records) <> 50
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_income_records row_value) <> 'd393822a95c6121a2e754919b1464a5b'
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 35
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_personal_cash_income_linkage_events row_value) <> '6e76a4dc2fc2954b28b7ad0a8d203ba0'
     or exists (select 1 from public.school_tuition_atomic_writer_context)
     or exists (select 1 from public.school_students where id in ('f2fc0000-0000-4000-8000-00000000a001','f2fc0000-0000-4000-8000-00000000a002')) then
    raise exception 'TUITION_CASH_POSTDEPLOY_BUSINESS_OR_RESIDUE_FAILED';
  end if;
  if (select count(*)
      from public.school_get_cash_income_submission_preflight(
        array(select income_record_id from public.school_student_tuition_bills order by id)
      ) preflight
      where preflight.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 8
     or (select count(*)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) preflight
         where preflight.eligible) <> 0
     or (select sum(preflight.payment_amount)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) preflight
         where preflight.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 109926.72 then
    raise exception 'TUITION_CASH_POSTDEPLOY_ELIGIBLE_BASELINE_FAILED';
  end if;
end
$assert$;
rollback;
