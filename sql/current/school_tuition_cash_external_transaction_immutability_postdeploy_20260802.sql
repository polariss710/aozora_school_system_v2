-- School tuition Cash external transaction immutability closure postdeploy.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select feature_key, state, release_version, evidence_hash
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;

do $assert$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit'
             and state = 'enabled'
             and release_version = 'tuition-cash-external-immutable-20260802'
             and evidence_hash = '8e5f62d1e256228b956ca7155bed65db')) <> 3 then
    raise exception 'TUITION_CASH_EXTERNAL_IMMUTABILITY_GATE_FAILED';
  end if;

  if (select count(*) from public.school_student_tuition_bills) <> 17
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by t.id::text), ''))
         from public.school_student_tuition_bills t) <> 'b18f15673637280bf1455667ccd3cc00'
     or (select count(*) from public.school_income_records) <> 50
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by t.id::text), ''))
         from public.school_income_records t) <> '6d2b5b7a3b021007b857a261e4bdf94d'
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 36
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by t.id::text), ''))
         from public.school_personal_cash_income_linkage_events t) <> 'd8f8e4b8556c38fba9873d343aec16d3'
     or (select count(*) from public.school_student_tuition_billing_identities) <> 15
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by t.id::text), ''))
         from public.school_student_tuition_billing_identities t) <> 'd8d72d5f886e363b80bca4aecfe22522'
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 256
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by t.id::text), ''))
         from public.school_student_tuition_bill_lessons t) <> 'dfa2bdb71f812f4b2aa0a23613edf289' then
    raise exception 'TUITION_CASH_EXTERNAL_IMMUTABILITY_SCHOOL_FINGERPRINT_FAILED';
  end if;

  if not exists (
    select 1
    from public.school_income_records income
    where income.id = '4a6efa01-82c4-4e61-b4ff-d558e52c1f16'
      and income.status = 'received'
      and income.receipt_status = 'Cash已确认'
      and income.tuition_bill_id = '00c956f1-19fb-4e79-9c4b-0570c8d7c3b1'
  ) or not exists (
    select 1
    from public.school_personal_cash_income_linkage_events linkage
    where linkage.id = 'c6e0c77f-e5f3-461f-a9a9-8863ebc0e239'
      and linkage.income_record_id = '4a6efa01-82c4-4e61-b4ff-d558e52c1f16'
      and linkage.sync_status = 'synced'
      and linkage.cash_request_status = 'approved'
      and linkage.cash_request_id = 'dd141707-9b9f-47c7-91fe-aaa243db13a6'
      and linkage.cash_transaction_id = '2feb333c-6228-4f57-a1fa-c8aa3d40616c'
      and linkage.payment_currency = 'CNY'
      and linkage.payment_amount = 1120.50
  ) then
    raise exception 'TUITION_CASH_EXTERNAL_IMMUTABILITY_PROTECTED_CHAIN_FAILED';
  end if;

  if (select count(*)
      from public.school_get_cash_income_submission_preflight(
        array(select income_record_id from public.school_student_tuition_bills order by id)
      ) p where p.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 7
     or (select count(*)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) p where p.classification = 'ALREADY_SYNCED') <> 8
     or (select count(*)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) p where p.classification = 'BLOCKED_CONFLICT') <> 2
     or (select sum(p.payment_amount)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) p where p.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 108806.22
     or (select sum(p.previous_carryover_cny)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) p where p.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 107.50 then
    raise exception 'TUITION_CASH_EXTERNAL_IMMUTABILITY_CLASSIFICATION_FAILED';
  end if;

  if exists (select 1 from public.school_tuition_atomic_writer_context)
     or exists (select 1 from public.school_students where id::text like 'f3f10000-%') then
    raise exception 'TUITION_CASH_EXTERNAL_IMMUTABILITY_FIXTURE_RESIDUE_FAILED';
  end if;
end
$assert$;

select 'POSTDEPLOY_PASS' as result,
       7 as eligible,
       8 as already_synced,
       2 as blocked_conflict,
       108806.22::numeric as eligible_cny,
       107.50::numeric as eligible_carryover_cny;

rollback;
