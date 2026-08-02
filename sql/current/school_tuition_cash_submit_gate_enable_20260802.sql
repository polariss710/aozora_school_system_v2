-- School V2 tuition Cash submit controlled Gate enable, 2026-08-02.
-- Prepared for a later business-owner cutover. This phase only runs with
-- tuition_cash_gate_commit=0, which verifies every precondition then ROLLBACKs.
-- The only persistent write possible with tuition_cash_gate_commit=1 is the
-- student_tuition_cash_submit Gate row.
\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_cash_gate_commit}
\else
  \echo 'TUITION_CASH_GATE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?edge_version}
\else
  \echo 'EDGE_VERSION_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?edge_bundle_sha256}
\else
  \echo 'EDGE_BUNDLE_SHA256_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?edge_source_sha256}
\else
  \echo 'EDGE_SOURCE_SHA256_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?baseline_16_sha256}
\else
  \echo 'BASELINE_16_SHA256_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?baseline_17_sha256}
\else
  \echo 'BASELINE_17_SHA256_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?eligible_set_sha256}
\else
  \echo 'ELIGIBLE_SET_SHA256_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?school_rollback_pass}
\else
  \echo 'SCHOOL_ROLLBACK_PASS_VARIABLE_REQUIRED'
  \quit
\endif
\if :{?cash_rollback_pass}
\else
  \echo 'CASH_ROLLBACK_PASS_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

create temporary table tuition_cash_gate_evidence (
  edge_version text not null,
  edge_bundle_sha256 text not null,
  edge_source_sha256 text not null,
  baseline_16_sha256 text not null,
  baseline_17_sha256 text not null,
  eligible_set_sha256 text not null,
  school_rollback_pass text not null,
  cash_rollback_pass text not null
) on commit drop;
insert into tuition_cash_gate_evidence values (
  :'edge_version', :'edge_bundle_sha256', :'edge_source_sha256',
  :'baseline_16_sha256', :'baseline_17_sha256', :'eligible_set_sha256',
  :'school_rollback_pass', :'cash_rollback_pass'
);

do $preflight$
declare v_evidence tuition_cash_gate_evidence%rowtype;
begin
  select * into strict v_evidence from tuition_cash_gate_evidence;
  if v_evidence.edge_version <> '10'
     or v_evidence.edge_bundle_sha256 <> 'bd5a0924ae6fb2ab9114f6103a90f825968520784069d9f704a4ac74374cb6a3'
     or v_evidence.edge_source_sha256 <> 'e3e42e2f7b03654c03612def0c1f9d9515dc702432bdf2ec44e55c7cddd4ad54'
     or v_evidence.baseline_16_sha256 <> '33d0cb9a8d0cb62c4de5f6ea26ed658b6898293def3cc2ee205d58721295ec35'
     or v_evidence.baseline_17_sha256 <> 'b91cb9dacef0c0c68013c5a2435a32a27cbef5089a159f30c49247a1145ccf46'
     or v_evidence.eligible_set_sha256 <> 'e1ad372ffea00b113088d7a39d7ab3ee2841f9b18ae3e18fd22952711b3cfd09'
     or v_evidence.school_rollback_pass <> 'passed'
     or v_evidence.cash_rollback_pass <> 'passed' then
    raise exception 'TUITION_CASH_GATE_EXTERNAL_EVIDENCE_DRIFT';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'TUITION_CASH_GATE_BASELINE_STATE_DRIFT';
  end if;

  if md5(pg_get_functiondef(
       'public.school_get_cash_income_submission_preflight(uuid[])'::regprocedure
     )) <> '23aa4f04fa20053e4b38af49067c6a2f'
     or md5(pg_get_functiondef(
       'public.school_guard_r0_tuition_business_mutation()'::regprocedure
     )) <> '98f6ff8612a1b68b0a15cbb4e936852f'
     or md5(pg_get_functiondef(
       'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)'::regprocedure
     )) <> '52bf4699b4cdcf3c6199b51f6ec968a4'
     or md5(pg_get_functiondef(
       'public.school_mark_cash_income_rejected(uuid,uuid,text,timestamptz)'::regprocedure
     )) <> '9624b50b23f24ddff02d8c972e360d35'
     or md5(pg_get_functiondef(
       'public.school_mark_cash_income_request_submitted(uuid,uuid,text)'::regprocedure
     )) <> '157024c648f055457447d81cd3cb4d54'
     or md5(pg_get_functiondef(
       'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)'::regprocedure
     )) <> '02fc85dc099adf6cd6465f53df672d15' then
    raise exception 'TUITION_CASH_GATE_SCHOOL_FUNCTION_DRIFT';
  end if;

  if has_function_privilege('anon',
       'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.school_mark_cash_income_confirmed(uuid,uuid,uuid,timestamptz)', 'EXECUTE') then
    raise exception 'TUITION_CASH_GATE_SCHOOL_ACL_DRIFT';
  end if;

  if (select count(*) from public.school_student_tuition_bills) <> 17
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_student_tuition_bills row_value) <> 'b18f15673637280bf1455667ccd3cc00'
     or (select count(*) from public.school_income_records) <> 50
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_income_records row_value) <> 'd393822a95c6121a2e754919b1464a5b'
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 35
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_personal_cash_income_linkage_events row_value) <> '6e76a4dc2fc2954b28b7ad0a8d203ba0' then
    raise exception 'TUITION_CASH_GATE_SCHOOL_BUSINESS_FINGERPRINT_DRIFT';
  end if;

  if not exists (
    select 1
    from public.school_student_tuition_bills bill
    join public.school_income_records income on income.id = bill.income_record_id
    where bill.id = '3435cbac-adc5-4bec-a54c-cefaab593359'
      and income.id = '004c7eeb-94c8-4312-aa2c-1ab44baa70dd'
      and bill.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
      and bill.billing_month = '2026-09'
      and bill.bill_amount_jpy = 350560.00
      and bill.billing_exchange_rate = 0.0415
      and bill.billing_amount_cny = 14548.24
      and income.status = 'pending'
  ) then
    raise exception 'TUITION_CASH_GATE_SUN_2026_09_DRIFT';
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
         where preflight.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 109926.72
     or (select sum(preflight.previous_carryover_cny)
         from public.school_get_cash_income_submission_preflight(
           array(select income_record_id from public.school_student_tuition_bills order by id)
         ) preflight
         where preflight.classification = 'ELIGIBLE_FOR_CASH_SUBMIT') <> 107.50 then
    raise exception 'TUITION_CASH_GATE_ELIGIBLE_BASELINE_DRIFT';
  end if;

  if exists (select 1 from public.school_tuition_atomic_writer_context)
     or exists (select 1 from public.school_students where id in (
       'f2fc0000-0000-4000-8000-00000000a001',
       'f2fc0000-0000-4000-8000-00000000a002'
     )) then
    raise exception 'TUITION_CASH_GATE_FIXTURE_RESIDUE';
  end if;
end
$preflight$;

update public.school_feature_gates
set state = 'enabled',
    reason = '学费Cash技术硬化、双库回滚矩阵、ACL、Edge和冻结金额权威验收完成。',
    release_version = 'tuition-cash-hardening-20260802',
    evidence_hash = 'b91cb9dacef0c0c68013c5a2435a32a27cbef5089a159f30c49247a1145ccf46',
    updated_at = statement_timestamp(),
    updated_by = current_user
where feature_key = 'student_tuition_cash_submit'
  and state = 'blocked';

do $verify$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit' and state = 'enabled')) <> 3 then
    raise exception 'TUITION_CASH_GATE_ENABLE_FAILED';
  end if;
end
$verify$;

\if :tuition_cash_gate_commit
  commit;
\else
  rollback;
\endif
