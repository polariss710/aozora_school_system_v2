-- School V2 tuition P0 R1D-C-C-B: fixed 42 historical-paid exclusion evidence.
-- Required psql variable: r1d_c_c_b_commit=0 for rollback rehearsal or 1 for deployment.
-- This phase creates immutable evidence only. It does not change candidate functions,
-- lessons, actuals, bills, income, settlements, wages, account rows, Cash, or R0 gates.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_c_c_b_commit}
\else
  \echo 'R1D_C_C_B_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

-- Reuse the committed, read-only fixed-42 audit as the immediate preflight.
\ir school_tuition_r1d_c_c_a_current_only_42_billing_fact_readonly.sql

begin;

create function pg_temp.r1d_c_c_b_school_business_fingerprint()
returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $fingerprint$
  select jsonb_build_object(
    'lesson',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_lesson_records t),
    'bill',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_bills t),
    'income',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_income_records t),
    'identity',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_billing_identities t),
    'relation',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_bill_lessons t),
    'migration_batch',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_business_entity_migration_batches t),
    'migration_item',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_business_entity_migration_items t),
    'settlement',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_monthly_settlements t),
    'settlement_adjustment',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_settlement_adjustments t),
    'student_payment',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_payments t),
    'account_transaction',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_account_transactions t),
    'cash_linkage',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_personal_cash_income_linkage_events t),
    'wage_lock',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_teacher_wage_locks t),
    'wage_detail',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_teacher_wage_lock_details t),
    'gate',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.feature_key),''))) from public.school_feature_gates t),
    'override',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_tuition_billing_attribution_override_audit t)
  );
$fingerprint$;

create temporary table r1d_c_c_b_school_business_before
on commit drop
as select pg_temp.r1d_c_c_b_school_business_fingerprint() as fingerprint;

do $preflight$
begin
  if to_regclass('public.school_student_tuition_historical_lesson_exclusions') is not null
     or to_regprocedure('public.school_r1d_c_c_b_fixed_42_manifest()') is not null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_insert()') is not null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_immutable()') is not null then
    raise exception 'R1D_C_C_B_OBJECT_ALREADY_EXISTS';
  end if;

  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1d9149f6e3ff02305d0963f81af9f0b9' then
    raise exception 'R1D_C_C_B_CANDIDATE_FUNCTION_DRIFT';
  end if;
end;
$preflight$;

create function public.school_r1d_c_c_b_fixed_42_manifest()
returns table (
  planned_lesson_id uuid,
  expected_old31_hash text,
  expected_student_id uuid,
  expected_student_name text,
  expected_business_entity_id uuid,
  expected_year_month text,
  expected_actual_lesson_id uuid,
  expected_settlement_id uuid,
  expected_income_id uuid,
  expected_account_transaction_id uuid,
  expected_evidence_hash text
)
language sql
immutable
parallel safe
set search_path = pg_catalog
as $function$
  values
    ('495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid,'5d3ad276618bc01bae27b6b43a83e978','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2c2f34a3-f553-4d11-b1e4-d92c553fbb0c'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab027f173099b22536eb6c4edb73268a'),
    ('747398ab-db47-493a-8047-4da69174e32b'::uuid,'f9fe1a977a030e519db136cf153bfb9b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','002875ac-4b12-4f83-b752-d5972d8bb7fa'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'77f932de5a1f4948ece4dee63344b74d'),
    ('8dce41c6-9df0-45e0-bd19-46aeb5fffedc'::uuid,'8645bf1604c52df8438e31a6c1d5fb78','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','511d1cfd-b570-4ee0-a827-9fbec8768743'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'fc69b063c6adcff5daa1241c4fbbbb3a'),
    ('8e778948-194f-40a0-9c6f-cfa3d8637c22'::uuid,'ebddcfc08659025b0011e1a7939bc58b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','7209bf5d-1916-4f61-bb4c-41dd0b667028'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'d2ec92c9952ad1468ea76a7833892933'),
    ('94e720de-0715-442f-a32a-848a31af3440'::uuid,'ace9d0e97b6dff47bc066f9c8ece3bec','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','daa403bd-4c8b-4752-a1a6-717c9270f661'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'03d32132cd4c5ffeee63c9c18d110d6c'),
    ('a25f02e1-1855-40e6-823d-93789a9ddea7'::uuid,'c26b1fb170e7c027da17368b509e9414','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4459aef2-735a-42bb-882d-e473571398cf'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'462a681344ec346e3d46dfa6ed71e871'),
    ('dd5a4236-f236-4c41-bbb8-84e1907531db'::uuid,'b9b96d7152e7d5b4a5a8d532f4639001','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d14ea4da-743a-41f6-8203-cea07f59cfb7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab4973e72027cd86c8e9e04e5fa5e771'),
    ('ed2b7a74-6f6e-4448-8d84-c610754dfb8f'::uuid,'bbda62e926307d064dab6716c37b9c26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b2967413-882f-416f-b038-be8520e934a7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'bfde93b7cbf347135bb05411e2bdd2e4'),
    ('ef7e9696-f655-4b0f-b627-cc51975e6515'::uuid,'dfe00f02fdf6128365ac163438061ba6','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d53292ea-74c0-43ec-9b94-a4d22a0acaf4'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'a2c6783aae17babbab3a9185a27254fd'),
    ('fddeae0d-47b6-4e4b-9f6b-ade92d3de922'::uuid,'5e2a2aa03a1ea38ea64360865a3f6668','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2fc6bac6-7324-4bef-ad5d-a25ffcefb168'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'50fe1695e7fee1def843bed90b90a929'),
    ('200cfd39-f61f-4ac4-9f0e-5cc3d885f670'::uuid,'3ac1a3f26dacdcce8cfc764674ddf013','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','62735cb7-bddc-4b96-bd16-ba74842c7c47'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'b057a252bf3ede3077ed3c64bc051428'),
    ('2852a46d-9d9d-4db6-8247-df3cc50725d8'::uuid,'af036483cc8ed66939bf37d2ee3af1ea','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c60bdbe6-9bcf-4f6a-8bc4-333ac027ede9'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'40c87fe0f28b4f6d4e8904265b53163e'),
    ('4724f45b-c66c-4ae2-b4ab-a1f06e0d545f'::uuid,'1ca747eb81bab16875f524c75798210c','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','a6bc3f1e-717e-4933-89b9-efb8e956726d'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'0e21f1a0796608eed919fe209f0d2a67'),
    ('606d7dfe-3eb6-4884-a0c6-75a1ccc8e335'::uuid,'094ad9e4c6b583beeb36a2bc856296e0','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','8cd37bd7-cfeb-482c-90f9-4a74144d658b'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'865910b9f721492c7fb10f273540b5e1'),
    ('ada45346-50cd-41ce-9568-71d8bb1038a1'::uuid,'1f136ac621568d18a5c5174969f578b1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b675f59e-edbd-4cdd-a001-b081375439a3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'224928ef89ad740376016185db7a8bd8'),
    ('cc24c61f-91d7-49d8-bbfc-73e13e4e7841'::uuid,'4637b1df60bd0b36f9fded098cb20a19','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e34a3a1f-83b4-4776-81b4-ef8f8165436e'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'28ca3351359d79139838b83b789b352d'),
    ('cdebfb82-e551-4598-bfc5-70e540f438e8'::uuid,'dc459956de00a1d6a40255cd91e581a1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c79b2cce-4372-4720-a565-995e18e7c318'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'787dff73f5917bacaa58e3939dfc1eb2'),
    ('e4ac1818-4d2f-4f3f-8979-65ab934f64fc'::uuid,'2932d2a64f095f6c7485f549a51a3541','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','ff6f9dd7-5b6c-4f47-90e9-9531f72e4ca3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'f32adf79910bbb0503c785994aa94779'),
    ('f99c2359-d9de-4603-a6ed-5b173b94d150'::uuid,'9c6462008676151f4325d3f150527422','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e0ce2693-0d38-4018-90a2-e8a78de2774f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'2ca2030d9b531e19bc9c7446f0ba267f'),
    ('ff1f1f7e-671f-48db-885e-14d0a808caed'::uuid,'4a68f6108d276eb01a1e735d6a8e203a','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4818624b-9302-446d-8982-c5ed09a9f50f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'21a95d17b396c48ef81137201116e662'),
    ('05246e13-b353-428b-a5cc-2da1cf4e903a'::uuid,'00634dd5baea89050eb7aaf82b7f2dfc','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bf9d3520-1a31-4605-bb17-e1eda5ef89a3'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'58e7c84bd7d4756e89c9b62c093daae4'),
    ('0aa5af82-783c-4164-b0a1-1ee1289e7d71'::uuid,'9490438221f5184ec7500f53e3d8d12f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','a2eb187e-d3ec-464b-9710-b0a63db6ab10'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'217d9b2d112de6532d1f59cde0d137f1'),
    ('1309c4cc-8abc-43ae-bde9-c7a9634a5aca'::uuid,'b0a8da4de95646f50771edcb1435a3c4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','7bb82294-33ba-4f28-b19d-d63623c5e659'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'6ad46d5bead5416e333001007b8e5341'),
    ('2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a'::uuid,'f640eacc94ff817604d944b3fade8ef2','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','6f0d528b-f414-4632-814e-d965b1f2960e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'2bc73f067629eda052bec091dd9666e5'),
    ('50d2aeee-538d-4582-8a3c-5fb692cd9f07'::uuid,'f78e435fe7970e3c68468fcbb0d426f1','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','4c974e87-3d7b-44ee-8a73-53149e3d9a8e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'773dc32b89f50888c4255165b333b221'),
    ('b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b'::uuid,'529eb5bd838376040b4b2d0af1544315','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f29301e0-4e8a-46c8-8cd6-21edd16409e2'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'f9f9620735a9f7c21a323e49bdc27e16'),
    ('b53d5c38-edcf-4e5c-ac38-286030abef81'::uuid,'ef6e38d4bffacc60af9f484ac4f92528','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','34e930c9-63cd-4b91-a027-0d5a7ea16517'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'fa8a16544c46815aa0399a9febd950b8'),
    ('cf3236a0-21f5-4fd3-8622-42a20aa19ebd'::uuid,'b6f95f21e49bb3baa3665902a1484b26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1c93d2be-c0c6-4e0b-a220-b7df04ab18ed'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'555c02f1552a7684df9fe7eb739d6ae7'),
    ('e131726d-b55d-4795-aeff-6fdf966b5017'::uuid,'b19ac2cafe2121c7342917190cf724d4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','ccac353f-d4b6-4698-ad4f-288e6cf7c613'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'3fada3574592978db2f6368a729fc5d7'),
    ('e3d729b4-4aab-480a-b574-cb02dae0ec71'::uuid,'f055310406a7b05f983598e0f2d3a97f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','8112c37e-fc63-4b2b-b4a2-25ee241a143c'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'4a4e9b5dcb916830697eab83f99282ae'),
    ('e85b6f77-87ae-42bd-bef4-60ebf4d307d0'::uuid,'412b0d286b8fd53ed0902a9ec73d748a','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1a951d5f-030b-4656-929e-36426646b1d5'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'90f6344d0145dd8cb9709bc022d918d7'),
    ('faed40b8-a819-4224-8da1-6e463dde4de7'::uuid,'947e35d6efb510baf06c184e081f3e05','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c6533183-1553-46f1-bbf6-7e2508383d81'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'e6f91fe9a90a631e0adab74f3aeb07a0'),
    ('1f767cd5-a265-4c4a-8b99-58f0e0ad4c09'::uuid,'218ee1cca4735749e499f5a1207798a9','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bc924326-5913-4902-9169-690f34b11df8'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'64f5099af2f7439c648d0e871d69fe98'),
    ('2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037'::uuid,'fee3f05ad997a6cd944be6683207c319','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','e7b2eb2c-a974-425b-8e0e-175e797e8601'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a893d73c57144e7c0e2f5f6f6cd989d7'),
    ('458017c5-ab50-44c8-a304-8851a73b3ce3'::uuid,'16f6fad84f976476e8ed75a7d730431e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','aefaa674-9fe4-4874-bf35-e97c8e2c89dc'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'012474619190fc41b663012abdc6f09f'),
    ('632a3bb3-1ebb-4941-9e22-98c07d829695'::uuid,'a95c00ea2914f1180bdcdd6a298e491e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c5298639-038d-4b89-9df4-974367ab7c0c'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0ec1875296531416c0d32b9cceac4fae'),
    ('79356de1-f6cb-4d80-811c-9e78c5b3672d'::uuid,'0cfe12d96227e538431d2ea07b6757e7','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','fbbd5dc8-294a-4cfb-967a-6f27ad97391f'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'520926b164318cb92cf064c3c2e57946'),
    ('7e5730ec-ad51-4f8b-87a6-c4cc225b6ede'::uuid,'c581ebfc9cbefd0ec01304ff9ae0532f','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','05451028-ecdb-41d2-8077-baf8e1ad3e97'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'879293d0353a04b43916eb48ac620aa1'),
    ('a4316220-13aa-486d-8262-f20d4de6a436'::uuid,'0c251281cf06743de80f4ada86be1f03','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','90cd07c4-4b18-43ec-a6c2-c7ed46988cd6'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'184da0d3e1382c71b376c5a343fe34e1'),
    ('d722a147-6ada-44e6-8caf-85bf09e8af3c'::uuid,'7e885c1d2cde3a5cb5fb3b60d5e0a2ad','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f9b85a6f-36ae-4f57-b1a6-8d630bece00b'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'692b50a0042c7702b6aa0a7a8606d870'),
    ('dbadbee8-b460-4671-ac16-44021cbe599b'::uuid,'8864b522f4c3fdc326212f3513506e0e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1cbeb207-ca6d-48bf-b6a5-f89b6ecc8687'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a7fa64a41493445208822092e3cf4bd7'),
    ('ee682a14-dbea-4480-966a-34fafb9b5902'::uuid,'46172777e57e72d4d3b6e5d40447d588','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','840d3f42-dbd2-408c-8ecd-b9a89fa74411'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0f9d4cb4541b850d8784be2c2d09fb5c');
$function$;

comment on function public.school_r1d_c_c_b_fixed_42_manifest() is
  'R1D-C-C-B immutable constant manifest for the 42 business-approved historical-paid planned lesson exclusions.';

revoke all on function public.school_r1d_c_c_b_fixed_42_manifest()
  from public, anon, authenticated, service_role;

create table public.school_student_tuition_historical_lesson_exclusions (
  id uuid primary key default gen_random_uuid(),
  planned_lesson_id uuid not null unique,
  student_id_snapshot uuid not null,
  business_entity_id_snapshot uuid not null,
  settlement_month_snapshot text not null,
  lesson_old31_hash text not null,
  linked_actual_lesson_id uuid not null unique,
  locked_settlement_id uuid not null,
  received_tuition_income_id uuid not null,
  school_account_transaction_id uuid not null,
  evidence_hash text not null,
  exclusion_reason_code text not null,
  evidence_class_code text not null,
  approval_source_code text not null,
  approval_report_version text not null,
  manifest_version text not null,
  approval_summary text not null,
  evidence_recorded_at timestamptz not null,
  recorded_by text not null default current_user,
  created_at timestamptz not null default now(),
  constraint school_tuition_historical_exclusion_planned_fkey
    foreign key (planned_lesson_id) references public.school_lesson_records(id) on delete restrict,
  constraint school_tuition_historical_exclusion_student_fkey
    foreign key (student_id_snapshot) references public.school_students(id) on delete restrict,
  constraint school_tuition_historical_exclusion_entity_fkey
    foreign key (business_entity_id_snapshot) references public.school_business_entities(id) on delete restrict,
  constraint school_tuition_historical_exclusion_actual_fkey
    foreign key (linked_actual_lesson_id) references public.school_lesson_records(id) on delete restrict,
  constraint school_tuition_historical_exclusion_settlement_fkey
    foreign key (locked_settlement_id) references public.school_student_monthly_settlements(id) on delete restrict,
  constraint school_tuition_historical_exclusion_income_fkey
    foreign key (received_tuition_income_id) references public.school_income_records(id) on delete restrict,
  constraint school_tuition_historical_exclusion_account_tx_fkey
    foreign key (school_account_transaction_id) references public.school_account_transactions(id) on delete restrict,
  constraint school_tuition_historical_exclusion_month_chk check (
    settlement_month_snapshot ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  constraint school_tuition_historical_exclusion_hash_chk check (
    lesson_old31_hash ~ '^[0-9a-f]{32}$'
    and evidence_hash ~ '^[0-9a-f]{32}$'
  ),
  constraint school_tuition_historical_exclusion_reason_chk check (
    exclusion_reason_code = 'historical_monthly_tuition_paid'
  ),
  constraint school_tuition_historical_exclusion_class_chk check (
    evidence_class_code = 'business_approved_reviewable_medium'
  ),
  constraint school_tuition_historical_exclusion_source_chk check (
    approval_source_code = 'approved_r1d_c_c_a_manifest'
  ),
  constraint school_tuition_historical_exclusion_report_chk check (
    approval_report_version = 'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1'
  ),
  constraint school_tuition_historical_exclusion_manifest_chk check (
    manifest_version = 'school-v2-r1d-c-c-a-current-only-42-20260728-v1'
  ),
  constraint school_tuition_historical_exclusion_text_chk check (
    nullif(btrim(approval_summary), '') is not null
    and nullif(btrim(recorded_by), '') is not null
  )
);

create index school_tuition_historical_exclusion_student_month_idx
  on public.school_student_tuition_historical_lesson_exclusions
    (student_id_snapshot, business_entity_id_snapshot, settlement_month_snapshot);

create index school_tuition_historical_exclusion_income_idx
  on public.school_student_tuition_historical_lesson_exclusions
    (received_tuition_income_id, planned_lesson_id);

comment on table public.school_student_tuition_historical_lesson_exclusions is
  'Append-only immutable evidence for the fixed R1D-C-C-A 42 business-approved historical-paid lesson exclusions. R1D-C-C-B does not wire this table into candidate readers.';
comment on column public.school_student_tuition_historical_lesson_exclusions.evidence_recorded_at is
  'Controlled database evidence recording time after business approval; not the original 2026-05/06 tuition charge, receipt, or per-lesson approval time.';
comment on column public.school_student_tuition_historical_lesson_exclusions.evidence_hash is
  'R1D-C-C-A evidence hash over fixed lesson, old31, actual, settlement, income, account transaction, and reviewable-medium classification.';
comment on column public.school_student_tuition_historical_lesson_exclusions.approval_summary is
  'Human-readable approval context only; machine decisions use controlled code/version columns.';

create function public.school_guard_tuition_historical_lesson_exclusion_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not exists (
    select 1
    from public.school_r1d_c_c_b_fixed_42_manifest() manifest
    where manifest.planned_lesson_id = new.planned_lesson_id
      and manifest.expected_old31_hash = new.lesson_old31_hash
      and manifest.expected_student_id = new.student_id_snapshot
      and manifest.expected_business_entity_id = new.business_entity_id_snapshot
      and manifest.expected_year_month = new.settlement_month_snapshot
      and manifest.expected_actual_lesson_id = new.linked_actual_lesson_id
      and manifest.expected_settlement_id = new.locked_settlement_id
      and manifest.expected_income_id = new.received_tuition_income_id
      and manifest.expected_account_transaction_id = new.school_account_transaction_id
      and manifest.expected_evidence_hash = new.evidence_hash
  ) then
    raise exception 'R1D_C_C_B_FIXED_MANIFEST_ROW_REJECTED: lesson %', new.planned_lesson_id;
  end if;

  return new;
end;
$function$;

create function public.school_guard_tuition_historical_lesson_exclusion_immutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
begin
  raise exception 'TUITION_HISTORICAL_LESSON_EXCLUSION_IMMUTABLE';
end;
$function$;

comment on function public.school_guard_tuition_historical_lesson_exclusion_insert() is
  'R1D-C-C-B insert guard: accepts only exact rows from the fixed approved 42 manifest.';
comment on function public.school_guard_tuition_historical_lesson_exclusion_immutable() is
  'R1D-C-C-B immutable guard: exclusion evidence cannot be updated, deleted, moved, or truncated.';

revoke all on function public.school_guard_tuition_historical_lesson_exclusion_insert()
  from public, anon, authenticated, service_role;
revoke all on function public.school_guard_tuition_historical_lesson_exclusion_immutable()
  from public, anon, authenticated, service_role;

create trigger school_tuition_historical_exclusion_insert_guard
before insert on public.school_student_tuition_historical_lesson_exclusions
for each row execute function public.school_guard_tuition_historical_lesson_exclusion_insert();

create trigger school_tuition_historical_exclusion_row_immutable
before update or delete on public.school_student_tuition_historical_lesson_exclusions
for each row execute function public.school_guard_tuition_historical_lesson_exclusion_immutable();

create trigger school_tuition_historical_exclusion_truncate_immutable
before truncate on public.school_student_tuition_historical_lesson_exclusions
for each statement execute function public.school_guard_tuition_historical_lesson_exclusion_immutable();

revoke all on table public.school_student_tuition_historical_lesson_exclusions
  from public, anon, authenticated, service_role;
grant select on table public.school_student_tuition_historical_lesson_exclusions
  to service_role;

do $fixed_evidence_preinsert$
declare
  v record;
begin
  with manifest as (
    select * from public.school_r1d_c_c_b_fixed_42_manifest()
  ), checked as (
    select
      manifest.*,
      lesson.id as current_planned_id,
      md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'
        -'scheduled_lesson_date'-'student_settlement_month'
        -'billing_month_source'-'billing_month_decided_at')::text) as current_old31_hash,
      actual.id as current_actual_id,
      (select count(*) from public.school_lesson_records sibling
       where sibling.lesson_type = 'actual'
         and sibling.planned_lesson_id = lesson.id) as actual_count,
      settlement.id as current_settlement_id,
      income.id as current_income_id,
      account_tx.id as current_account_transaction_id,
      md5(jsonb_build_object(
        'planned_lesson_id',lesson.id,
        'old31_hash',md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'
          -'scheduled_lesson_date'-'student_settlement_month'
          -'billing_month_source'-'billing_month_decided_at')::text),
        'actual_lesson_id',actual.id,
        'settlement_id',settlement.id,
        'income_id',income.id,
        'account_transaction_id',account_tx.id,
        'classification','exclude_reviewable_medium'
      )::text) as current_evidence_hash,
      exists (
        select 1
        from public.school_list_student_tuition_candidates(
          lesson.student_id,lesson.business_entity_id,lesson.year_month,false
        ) candidate
        where candidate.planned_lesson_id = lesson.id
          and candidate.candidate_status = 'candidate'
      ) as remains_current_candidate,
      exists (
        select 1 from public.school_student_tuition_bill_lessons relation
        where relation.planned_lesson_id = lesson.id
      ) as has_relation,
      exists (
        select 1
        from public.school_student_tuition_bills bill
        cross join lateral jsonb_array_elements_text(
          bill.source_snapshot -> 'planned_lesson_ids'
        ) snapshot_lesson(lesson_id_text)
        where snapshot_lesson.lesson_id_text::uuid = lesson.id
      ) as has_snapshot
    from manifest
    left join public.school_lesson_records lesson
      on lesson.id = manifest.planned_lesson_id
    left join public.school_lesson_records actual
      on actual.id = manifest.expected_actual_lesson_id
     and actual.lesson_type = 'actual'
     and actual.planned_lesson_id = lesson.id
    left join public.school_student_monthly_settlements settlement
      on settlement.id = manifest.expected_settlement_id
     and settlement.student_id = lesson.student_id
     and settlement.business_entity_id is not distinct from lesson.business_entity_id
     and settlement.year_month = lesson.year_month
     and settlement.settlement_status = 'locked'
    left join public.school_income_records income
      on income.id = manifest.expected_income_id
     and income.student_id = lesson.student_id
     and income.business_entity_id is not distinct from lesson.business_entity_id
     and coalesce(income.settlement_month,income.year_month) = lesson.year_month
     and income.income_category = 'tuition'
     and income.status = 'received'
     and income.currency = 'JPY'
     and income.amount = 204000
    left join public.school_account_transactions account_tx
      on account_tx.id = manifest.expected_account_transaction_id
     and account_tx.related_table = 'school_income_records'
     and account_tx.related_id = income.id
     and account_tx.amount = 204000
    where lesson.id is not null
  )
  select
    (select count(*) from manifest) as manifest_rows,
    (select count(distinct planned_lesson_id) from manifest) as distinct_lessons,
    (select md5(string_agg(expected_old31_hash,'' order by planned_lesson_id::text)) from manifest)
      as old31_aggregate_hash,
    (select md5(string_agg(expected_evidence_hash,'' order by planned_lesson_id::text)) from manifest)
      as evidence_aggregate_hash,
    (select count(*) from checked) as checked_rows,
    (select count(*) from checked
      where current_old31_hash is distinct from expected_old31_hash
         or current_actual_id is distinct from expected_actual_lesson_id
         or current_settlement_id is distinct from expected_settlement_id
         or current_income_id is distinct from expected_income_id
         or current_account_transaction_id is distinct from expected_account_transaction_id
         or current_evidence_hash is distinct from expected_evidence_hash
         or actual_count <> 1
         or not remains_current_candidate
         or has_relation
         or has_snapshot) as evidence_drift,
    (select count(*) from checked
      join public.school_lesson_records lesson on lesson.id = checked.planned_lesson_id
      join public.school_lesson_records actual on actual.id = checked.expected_actual_lesson_id
      where lesson.app_type is distinct from 'school'
         or lesson.lesson_type is distinct from 'planned'
         or lesson.student_id is distinct from checked.expected_student_id
         or lesson.business_entity_id is distinct from checked.expected_business_entity_id
         or lesson.year_month is distinct from checked.expected_year_month
         or lesson.billing_month is not null
         or lesson.billing_week_start_date is not null
         or lesson.scheduled_lesson_date is not null
         or lesson.student_settlement_month is not null
         or lesson.billing_month_source is not null
         or lesson.billing_month_decided_at is not null
         or actual.status not in ('completed','makeup_completed')
         or actual.student_id is distinct from lesson.student_id
         or actual.business_entity_id is distinct from lesson.business_entity_id
         or actual.subject_id is distinct from lesson.subject_id
         or actual.teacher_id is distinct from lesson.teacher_id
         or actual.duration_hours is distinct from lesson.duration_hours
         or actual.lesson_fee is distinct from lesson.lesson_fee) as business_drift,
    (select sum(lesson.duration_hours)
     from manifest join public.school_lesson_records lesson on lesson.id=manifest.planned_lesson_id)
      as total_hours,
    (select sum(lesson.lesson_fee)
     from manifest join public.school_lesson_records lesson on lesson.id=manifest.planned_lesson_id)
      as total_jpy,
    (select count(*) from public.school_lesson_records pending
      where pending.lesson_type='planned'
        and pending.status='pending_makeup'
        and pending.student_id in (
          '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
          'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
        )
        and pending.year_month in ('2026-05','2026-06')) as pending_makeup_rows,
    (select count(*)
     from manifest join public.school_lesson_records pending
       on pending.id=manifest.planned_lesson_id
      and pending.status='pending_makeup') as pending_manifest_overlap
  into v;

  if v.manifest_rows <> 42
     or v.distinct_lessons <> 42
     or v.old31_aggregate_hash <> 'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or v.evidence_aggregate_hash <> 'dc2546bff536942650db58e437d37f0e'
     or v.checked_rows <> 42
     or v.evidence_drift <> 0
     or v.business_drift <> 0
     or v.total_hours <> 84
     or v.total_jpy <> 714000
     or v.pending_makeup_rows <> 6
     or v.pending_manifest_overlap <> 0
     or (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 0 then
    raise exception 'R1D_C_C_B_FIXED_EVIDENCE_PREFLIGHT_FAILED: %', to_jsonb(v);
  end if;
end;
$fixed_evidence_preinsert$;

\if :r1d_c_c_b_commit
\else
do $preinsert_negative_tests$
declare
  v_manifest record;
  v_rejected boolean;
begin
  select * into v_manifest
  from public.school_r1d_c_c_b_fixed_42_manifest()
  order by planned_lesson_id::text
  limit 1;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      v_manifest.planned_lesson_id,v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'wrong_reason','business_approved_reviewable_medium','approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_REASON_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      v_manifest.planned_lesson_id,v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'historical_monthly_tuition_paid','wrong_class','approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_CLASS_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      v_manifest.planned_lesson_id,v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'historical_monthly_tuition_paid','business_approved_reviewable_medium','wrong_source',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_SOURCE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      v_manifest.planned_lesson_id,v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      null,v_manifest.expected_income_id,v_manifest.expected_account_transaction_id,
      v_manifest.expected_evidence_hash,'historical_monthly_tuition_paid',
      'business_approved_reviewable_medium','approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_NULL_REFERENCE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      '00003ee2-4358-457c-8727-7a4c8299b952',v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'historical_monthly_tuition_paid','business_approved_reviewable_medium',
      'approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_43RD_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      '9085ab09-a719-42b7-a517-2700b8d9ddb0',v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'historical_monthly_tuition_paid','business_approved_reviewable_medium',
      'approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback negative',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_PENDING_MAKEUP_NOT_REJECTED'; end if;

  if (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 0 then
    raise exception 'R1D_C_C_B_PREINSERT_NEGATIVE_RESIDUE';
  end if;
end;
$preinsert_negative_tests$;
\endif

insert into public.school_student_tuition_historical_lesson_exclusions (
  planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
  settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
  locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
  evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
  approval_report_version,manifest_version,approval_summary,evidence_recorded_at,
  recorded_by,created_at
)
select
  manifest.planned_lesson_id,
  manifest.expected_student_id,
  manifest.expected_business_entity_id,
  manifest.expected_year_month,
  manifest.expected_old31_hash,
  manifest.expected_actual_lesson_id,
  manifest.expected_settlement_id,
  manifest.expected_income_id,
  manifest.expected_account_transaction_id,
  manifest.expected_evidence_hash,
  'historical_monthly_tuition_paid',
  'business_approved_reviewable_medium',
  'approved_r1d_c_c_a_manifest',
  'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
  'school-v2-r1d-c-c-a-current-only-42-20260728-v1',
  'Business owner confirmed four JPY 204,000 receipts cover all planned lessons for the four student-months, including six pending_makeup lessons; only fixed Manifest B 42 is approved for future candidate exclusion.',
  transaction_timestamp(),
  current_user,
  transaction_timestamp()
from public.school_r1d_c_c_b_fixed_42_manifest() manifest
order by manifest.planned_lesson_id::text;

do $postinsert$
declare
  v record;
begin
  select
    count(*) as row_count,
    count(distinct exclusion.planned_lesson_id) as distinct_lessons,
    count(distinct exclusion.evidence_recorded_at) as recording_times,
    md5(string_agg(exclusion.lesson_old31_hash,'' order by exclusion.planned_lesson_id::text))
      as old31_aggregate_hash,
    md5(string_agg(exclusion.evidence_hash,'' order by exclusion.planned_lesson_id::text))
      as evidence_aggregate_hash,
    count(*) filter (where manifest.planned_lesson_id is null) as rows_outside_manifest,
    count(*) filter (
      where exclusion.student_id_snapshot is distinct from manifest.expected_student_id
         or exclusion.business_entity_id_snapshot is distinct from manifest.expected_business_entity_id
         or exclusion.settlement_month_snapshot is distinct from manifest.expected_year_month
         or exclusion.lesson_old31_hash is distinct from manifest.expected_old31_hash
         or exclusion.linked_actual_lesson_id is distinct from manifest.expected_actual_lesson_id
         or exclusion.locked_settlement_id is distinct from manifest.expected_settlement_id
         or exclusion.received_tuition_income_id is distinct from manifest.expected_income_id
         or exclusion.school_account_transaction_id is distinct from manifest.expected_account_transaction_id
         or exclusion.evidence_hash is distinct from manifest.expected_evidence_hash
    ) as row_drift
  into v
  from public.school_student_tuition_historical_lesson_exclusions exclusion
  left join public.school_r1d_c_c_b_fixed_42_manifest() manifest
    on manifest.planned_lesson_id = exclusion.planned_lesson_id;

  if v.row_count <> 42
     or v.distinct_lessons <> 42
     or v.recording_times <> 1
     or v.old31_aggregate_hash <> 'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or v.evidence_aggregate_hash <> 'dc2546bff536942650db58e437d37f0e'
     or v.rows_outside_manifest <> 0
     or v.row_drift <> 0
     or md5(pg_get_functiondef(
          'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
        )) <> '1d9149f6e3ff02305d0963f81af9f0b9'
     or (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_C_C_B_POSTINSERT_ASSERTION_FAILED: %', to_jsonb(v);
  end if;

  if has_table_privilege('anon','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     or has_table_privilege('authenticated','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     or has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     or has_table_privilege('anon','public.school_student_tuition_historical_lesson_exclusions','UPDATE')
     or has_table_privilege('authenticated','public.school_student_tuition_historical_lesson_exclusions','UPDATE')
     or has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','UPDATE')
     or has_table_privilege('anon','public.school_student_tuition_historical_lesson_exclusions','DELETE')
     or has_table_privilege('authenticated','public.school_student_tuition_historical_lesson_exclusions','DELETE')
     or has_table_privilege('service_role','public.school_student_tuition_historical_lesson_exclusions','DELETE') then
    raise exception 'R1D_C_C_B_WRITE_PRIVILEGE_LEAK';
  end if;
end;
$postinsert$;

\if :r1d_c_c_b_commit
\else
do $postinsert_negative_tests$
declare
  v_id uuid;
  v_rejected boolean;
  v_manifest record;
begin
  select id into v_id
  from public.school_student_tuition_historical_lesson_exclusions
  order by planned_lesson_id::text limit 1;
  select * into v_manifest
  from public.school_r1d_c_c_b_fixed_42_manifest()
  order by planned_lesson_id::text limit 1;

  v_rejected := false;
  begin
    update public.school_student_tuition_historical_lesson_exclusions
    set approval_summary = approval_summary || ' changed'
    where id = v_id;
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_UPDATE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    update public.school_student_tuition_historical_lesson_exclusions
    set planned_lesson_id = '00003ee2-4358-457c-8727-7a4c8299b952'
    where id = v_id;
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_MOVE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    delete from public.school_student_tuition_historical_lesson_exclusions where id = v_id;
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_DELETE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    execute 'truncate table public.school_student_tuition_historical_lesson_exclusions';
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_TRUNCATE_NOT_REJECTED'; end if;

  v_rejected := false;
  begin
    insert into public.school_student_tuition_historical_lesson_exclusions (
      planned_lesson_id,student_id_snapshot,business_entity_id_snapshot,
      settlement_month_snapshot,lesson_old31_hash,linked_actual_lesson_id,
      locked_settlement_id,received_tuition_income_id,school_account_transaction_id,
      evidence_hash,exclusion_reason_code,evidence_class_code,approval_source_code,
      approval_report_version,manifest_version,approval_summary,evidence_recorded_at
    ) values (
      v_manifest.planned_lesson_id,v_manifest.expected_student_id,
      v_manifest.expected_business_entity_id,v_manifest.expected_year_month,
      v_manifest.expected_old31_hash,v_manifest.expected_actual_lesson_id,
      v_manifest.expected_settlement_id,v_manifest.expected_income_id,
      v_manifest.expected_account_transaction_id,v_manifest.expected_evidence_hash,
      'historical_monthly_tuition_paid','business_approved_reviewable_medium',
      'approved_r1d_c_c_a_manifest',
      'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1',
      'school-v2-r1d-c-c-a-current-only-42-20260728-v1','rollback duplicate',now()
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_B_NEGATIVE_DUPLICATE_NOT_REJECTED'; end if;

  if (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 42 then
    raise exception 'R1D_C_C_B_NEGATIVE_TEST_CHANGED_ROWS';
  end if;
end;
$postinsert_negative_tests$;
\endif

do $final_business_guard$
declare
  v_current_candidates bigint;
  v_new_candidates bigint;
  v_before_fingerprint jsonb;
begin
  select count(*) into v_current_candidates
  from (
    select distinct candidate.planned_lesson_id
    from public.school_students student
    join (
      select distinct student_id,year_month
      from public.school_lesson_records
      where app_type='school' and lesson_type='planned'
    ) scope on scope.student_id=student.id
    cross join lateral public.school_list_student_tuition_candidates(
      student.id,student.business_entity_id,scope.year_month,false
    ) candidate
    where candidate.candidate_status='candidate'
  ) current_rows;

  select count(*) into v_new_candidates
  from (
    select distinct candidate.planned_lesson_id
    from public.school_lesson_records lesson
    cross join lateral public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,lesson.billing_month,false
    ) candidate
    where lesson.app_type='school'
      and lesson.lesson_type='planned'
      and lesson.billing_month is not null
      and lesson.billing_week_start_date is not null
      and lesson.student_settlement_month=lesson.billing_month
      and lesson.billing_month_source is not null
      and lesson.billing_month_decided_at is not null
      and public.school_is_valid_tuition_billing_period(
        lesson.billing_month,lesson.billing_week_start_date
      )
      and candidate.planned_lesson_id=lesson.id
      and candidate.candidate_status='candidate'
  ) new_rows;

  select fingerprint into v_before_fingerprint
  from r1d_c_c_b_school_business_before;

  if v_current_candidates <> 160
     or v_new_candidates <> 118
     or v_before_fingerprint is distinct from pg_temp.r1d_c_c_b_school_business_fingerprint()
     or (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type='planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type='actual') <> 229
     or (select count(*) from public.school_lesson_records where billing_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_week_start_date is not null) <> 118
     or (select count(*) from public.school_lesson_records where student_settlement_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_source is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_decided_at is not null) <> 118
     or (select count(*) from public.school_lesson_records where scheduled_lesson_date is not null) <> 0
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_preview' and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D_C_C_B_FINAL_BUSINESS_GUARD_FAILED: current %, new %',
      v_current_candidates,v_new_candidates;
  end if;
end;
$final_business_guard$;

select count(*) as exclusion_rows,
       min(evidence_recorded_at) as evidence_recorded_at,
       md5(string_agg(lesson_old31_hash,'' order by planned_lesson_id::text)) as old31_aggregate_hash,
       md5(string_agg(evidence_hash,'' order by planned_lesson_id::text)) as evidence_aggregate_hash
from public.school_student_tuition_historical_lesson_exclusions;

\if :r1d_c_c_b_commit
  commit;
\else
  rollback;
\endif
