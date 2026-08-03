-- P0-G1-B1 three-income and Gate invariant verification. Read-only.
\set ON_ERROR_STOP on
\pset pager off

\if :{?expected_cash_gate_state}
\else
  \echo 'EXPECTED_CASH_GATE_STATE_REQUIRED'
  \quit
\endif

begin transaction read only;
select set_config('p0g1b1.expected_cash_gate_state',:'expected_cash_gate_state',true);

do $verify$
declare
  v_case record;
  v_bill uuid;
begin
  if current_setting('p0g1b1.expected_cash_gate_state') not in ('blocked','enabled')
     or (select state from public.school_feature_gates where feature_key='student_tuition_preview')<>'enabled'
     or (select state from public.school_feature_gates where feature_key='student_tuition_generate')<>'blocked'
     or (select state from public.school_feature_gates where feature_key='student_tuition_cash_submit')<>current_setting('p0g1b1.expected_cash_gate_state') then
    raise exception 'P0G1B1_PRODUCTION_GATE_STATE_INVALID';
  end if;

  for v_case in select * from (values
    ('7d319b0d-8f62-41e9-95bf-c1a0c6ed7090'::uuid,'013a7766-101b-4b5b-bcae-c008825b14fa'::uuid,'d980cedd-ebba-4be1-afcb-b25dfa26798a'::uuid,27950.00::numeric),
    ('f7bbd000-9753-4f00-9d3a-d8705ee8d5e9'::uuid,'a5cac133-36ee-4324-9c67-f95eadf62200'::uuid,'648e264d-3435-43f1-a797-cf1394011f65'::uuid,8147.25::numeric),
    ('f7150ce5-fb77-4b7f-99f8-207bfbbced91'::uuid,'66a1f276-2756-466f-b709-b8ca29063fd9'::uuid,'efd670bc-8dba-4926-82c4-2d194281a609'::uuid,9240.00::numeric)
  ) expected(revision_id,bill_id,income_id,amount_cny)
  loop
    select bill.id into strict v_bill
    from public.school_student_tuition_generation_revisions revision
    join public.school_student_tuition_bills bill on bill.id=revision.tuition_bill_id
    join public.school_income_records income on income.id=bill.income_record_id
    where revision.id=v_case.revision_id and revision.lifecycle_status='active'
      and bill.id=v_case.bill_id and bill.status='income_created'
      and bill.billing_amount_cny=v_case.amount_cny
      and income.id=v_case.income_id and income.status='pending'
      and (income.source_snapshot->>'billing_amount_cny')::numeric=v_case.amount_cny;
    if (select count(*) from public.school_student_tuition_generation_revisions
        where generation_identity_id=(select generation_identity_id from public.school_student_tuition_generation_revisions where id=v_case.revision_id)
          and lifecycle_status='active')<>1
       or exists(select 1 from public.school_personal_cash_income_linkage_events where income_record_id=v_case.income_id) then
      raise exception 'P0G1B1_PRODUCTION_CHAIN_OR_CASH_FACT_INVALID: %',v_case.income_id;
    end if;
    perform public.school_validate_tuition_identity_for_bill(v_bill);
    perform public.school_validate_tuition_bill_income_for_bill(v_bill);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    perform public.school_validate_tuition_generation_revision_for_bill(v_bill);
  end loop;
end;
$verify$;

select revision.id revision_id,bill.id bill_id,income.id income_id,
       bill.billing_amount_cny,income.status,
       (select count(*) from public.school_personal_cash_income_linkage_events linkage
        where linkage.income_record_id=income.id) cash_linkage_count
from public.school_student_tuition_generation_revisions revision
join public.school_student_tuition_bills bill on bill.id=revision.tuition_bill_id
join public.school_income_records income on income.id=bill.income_record_id
where revision.id in (
  '7d319b0d-8f62-41e9-95bf-c1a0c6ed7090',
  'f7bbd000-9753-4f00-9d3a-d8705ee8d5e9',
  'f7150ce5-fb77-4b7f-99f8-207bfbbced91'
)
order by bill.billing_amount_cny desc;
select feature_key,state from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;
select 'P0G1B1_PRODUCTION_FACTS_READONLY_PASS' result;
rollback;
