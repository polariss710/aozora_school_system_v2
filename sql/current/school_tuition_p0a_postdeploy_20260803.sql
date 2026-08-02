-- Read-only production postdeploy assertions for School V2 tuition P0-A.
\set ON_ERROR_STOP on
\pset pager off
begin isolation level repeatable read read only;

do $assertions$
declare
  v_bill_id uuid;
  v_signature text;
  v_expected_md5 text;
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='enabled')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'TUITION_P0A_POSTDEPLOY_GATE_FAILED';
  end if;
  for v_signature,v_expected_md5 in
    select * from (values
      ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','3e3414b996faf773c5dbc073bc6973b7'),
      ('public.school_lock_student_monthly_settlement(uuid,text,text)','efaa26100bc5cbd2e61be63e7eaa46ef'),
      ('public.school_unlock_student_monthly_settlement(uuid,text)','653356cc5c9c75b584d0d5cc5104397f'),
      ('public.school_relock_student_monthly_settlement(uuid,text)','38efb4f3170f39359ca67ba23ac1ccae'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','f8b33842d6dbaa3cbdeca20236146c82'),
      ('public.school_tuition_p0a_consumed_bill_id(uuid)','f881595b9acc06f0c863a5a4fab657c8'),
      ('public.school_assert_tuition_settlement_mutable(uuid)','21607d2038d636697a21df5c2f55ad6d'),
      ('public.school_tuition_p0a_lock_generate_scope(uuid,uuid,text[])','27bd26ae464b46894f69209a6e63ff5f'),
      ('public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text)','c3b7cacb4803be0edfc059a462ef3183')
    ) expected(signature,definition_md5)
  loop
    if md5(pg_get_functiondef(v_signature::regprocedure))<>v_expected_md5 then
      raise exception 'TUITION_P0A_POSTDEPLOY_FUNCTION_DRIFT: %',v_signature;
    end if;
  end loop;

  if (select count(*) from public.school_student_monthly_settlements)<>17
     or (select count(*) from public.school_student_settlement_adjustment_drafts)<>6
     or (select count(*) from public.school_student_settlement_adjustments)<>5
     or (select count(*) from public.school_student_settlement_carryovers)<>8
     or (select count(*) from public.school_student_tuition_billing_identities)<>15
     or (select count(*) from public.school_student_tuition_bills)<>17
     or (select count(*) from public.school_student_tuition_bill_lessons)<>256
     or (select count(*) from public.school_income_records)<>50
     or (select count(*) from public.school_personal_cash_income_linkage_events)<>40 then
    raise exception 'TUITION_P0A_POSTDEPLOY_REAL_COUNT_DRIFT';
  end if;
  if (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t)<>'85c829ebc3bb0a4100393d9c8d6421d7'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t)<>'059c5187ad6513f9501076193aa55696'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t)<>'4bce2b158d4de769d592a2d367881868'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t)<>'54133d433579c772ba76017b757c49fd'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t)<>'b18f15673637280bf1455667ccd3cc00'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t)<>'d8d72d5f886e363b80bca4aecfe22522'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t)<>'dfa2bdb71f812f4b2aa0a23613edf289'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t)<>'dccaf8446c3907b48cec9bf028b4373c'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t)<>'8e467489878b5bbe15f9eadbcbaabb10' then
    raise exception 'TUITION_P0A_POSTDEPLOY_REAL_HASH_DRIFT';
  end if;

  for v_bill_id in
    select identity_row.canonical_bill_id
    from public.school_student_tuition_billing_identities identity_row
    order by identity_row.canonical_bill_id
  loop
    perform public.school_validate_tuition_identity_for_bill(v_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(v_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill_id);
  end loop;

  if public.school_tuition_p0a_consumed_bill_id(
       'b699209d-2f61-4cfa-959b-45686e2fe19b')<>
       '553a24ba-81cf-4af0-b723-169a09914c79' then
    raise exception 'TUITION_P0A_ZHANG_CONSUMED_RESOLUTION_FAILED';
  end if;
  begin
    perform public.school_assert_tuition_settlement_mutable(
      'b699209d-2f61-4cfa-959b-45686e2fe19b');
    raise exception 'TUITION_P0A_ZHANG_GUARD_MISSING';
  exception when others then
    if position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  if (select settlement_status from public.school_student_monthly_settlements
      where id='b699209d-2f61-4cfa-959b-45686e2fe19b')<>'unlocked'
     or (select status from public.school_income_records
         where id='be64a9e2-f15e-44b0-a9de-2ee91bdf9567')<>'pending'
     or exists (select 1 from public.school_personal_cash_income_linkage_events
                where income_record_id='be64a9e2-f15e-44b0-a9de-2ee91bdf9567') then
    raise exception 'TUITION_P0A_ZHANG_REAL_CHAIN_CHANGED';
  end if;
  if (select count(*) from public.school_student_tuition_billing_identities identity_row
      join public.school_student_tuition_bills bill on bill.id=identity_row.canonical_bill_id
      join public.school_income_records income_row on income_row.id=bill.income_record_id
      where identity_row.student_id in (
        'eb705aad-de4d-45e6-a391-42dcdd89aeda',
        'a7b163a0-201e-4867-9b94-372343356a80'
      ) and identity_row.billing_month='2026-08'
        and bill.status='income_created' and income_row.status='pending')<>2 then
    raise exception 'TUITION_P0A_PENG_LI_CHAIN_CHANGED';
  end if;
  if exists (
    select 1 from public.school_students where note like '%codex-test tuition-p0a-concurrency-20260803%'
    union all select 1 from public.school_lesson_records where note like '%codex-test tuition-p0a-concurrency-20260803%'
    union all select 1 from public.school_student_monthly_settlements where note like '%codex-test tuition-p0a-concurrency-20260803%'
    union all select 1 from public.school_student_settlement_adjustment_drafts where note like '%codex-test tuition-p0a-concurrency-20260803%'
    union all select 1 from public.school_student_settlement_carryovers where note like '%codex-test tuition-p0a-concurrency-20260803%'
  ) then raise exception 'TUITION_P0A_FIXTURE_RESIDUE'; end if;
end
$assertions$;

select feature_key,state,release_version from public.school_feature_gates
where feature_key like 'student_tuition_%' order by feature_key;
select count(*) as canonical_validated_count
from public.school_student_tuition_billing_identities;
select public.school_tuition_p0a_consumed_bill_id(
  'b699209d-2f61-4cfa-959b-45686e2fe19b') as zhang_consuming_bill_id;

rollback;
