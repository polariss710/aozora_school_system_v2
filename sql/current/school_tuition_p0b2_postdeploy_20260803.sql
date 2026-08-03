\set ON_ERROR_STOP on
\pset pager off
begin read only;
do $verify$
declare
  v_signature text;
  v_expected_md5 text;
  v_role text;
  v_table text;
begin
  for v_signature,v_expected_md5 in select * from (values
    ('public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric)','9e056a42b0de50476233ed78de58b528'),
    ('public.school_tuition_p0b2_guard_draft_row()','6249f945e0d359a8f5aa7820bd21f5da'),
    ('public.school_tuition_p0b2_guard_posted_adjustment()','aef4c30b2c3953b975b72d4e27feafc1'),
    ('public.school_tuition_p0b2_guard_settlement_resolution()','c67bc3735b253eb2bb57c843fafdfa4a'),
    ('public.school_get_student_monthly_settlement_preview(uuid,text)','646e278c3144cab782141d3d01f69db5'),
    ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','9b68480b55736c0602b28f637dcdc7a1'),
    ('public.school_lock_student_monthly_settlement(uuid,text,text)','19033b559cacb99677fc1d3583f78ad3'),
    ('public.school_relock_student_monthly_settlement(uuid,text)','6357848be1eb6c1cf11016d01cad14cb')
  ) x(signature,definition_md5) loop
    if md5(pg_get_functiondef(v_signature::regprocedure))<>v_expected_md5 then
      raise exception 'P0B2_POSTDEPLOY_FUNCTION_DRIFT: %',v_signature;
    end if;
  end loop;
  if (select count(*) from pg_trigger
      where not tgisinternal and tgname like 'school_tuition_p0b2_%')<>3
     or not exists(select 1 from pg_constraint where
       conname='school_student_settlement_adjustment_drafts_mode_chk' and convalidated)
     or not exists(select 1 from pg_constraint where
       conname='school_student_settlement_adjustments_mode_chk' and convalidated)
     or to_regclass('public.school_student_settlement_adjustments_settlement_uidx') is null then
    raise exception 'P0B2_POSTDEPLOY_OBJECT_DRIFT';
  end if;
  foreach v_role in array array['anon','authenticated','service_role'] loop
    foreach v_table in array array[
      'school_student_monthly_settlements',
      'school_student_settlement_adjustment_drafts',
      'school_student_settlement_adjustments',
      'school_student_settlement_carryovers'
    ] loop
      if has_table_privilege(v_role,'public.'||v_table,'INSERT')
         or has_table_privilege(v_role,'public.'||v_table,'UPDATE')
         or has_table_privilege(v_role,'public.'||v_table,'DELETE') then
        raise exception 'P0B2_POSTDEPLOY_TABLE_WRITE_ACL: %.%',v_role,v_table;
      end if;
    end loop;
    if not has_function_privilege(v_role,
       'public.school_get_student_monthly_settlement_preview(uuid,text)','EXECUTE')
       or not has_function_privilege(v_role,
       'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','EXECUTE')
       or has_function_privilege(v_role,
       'public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)','EXECUTE')
       or has_function_privilege(v_role,
       'public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric)','EXECUTE') then
      raise exception 'P0B2_POSTDEPLOY_FUNCTION_ACL: %',v_role;
    end if;
  end loop;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'P0B2_GATE_DRIFT';
  end if;
  if exists(
    select 1 from public.school_business_entities where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_subjects where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_teachers where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_students where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_lesson_records where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_student_monthly_settlements where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_student_settlement_adjustment_drafts where note like 'codex-test tuition-p0b%20260803%'
    union all select 1 from public.school_student_settlement_adjustments where note like 'codex-test tuition-p0b%20260803%'
  ) then raise exception 'P0B2_FIXTURE_RESIDUE'; end if;
end
$verify$;

select object_name,row_count,full_hash from (
  select 'settlement' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash from public.school_student_monthly_settlements t
  union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
  union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
  union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
  union all select 'lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t
  union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
  union all select 'identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t
  union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
  union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
  union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t
) hashes order by object_name;

do $hashes$
begin
  if (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t)<>'85c829ebc3bb0a4100393d9c8d6421d7'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t)<>'059c5187ad6513f9501076193aa55696'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t)<>'4bce2b158d4de769d592a2d367881868'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t)<>'54133d433579c772ba76017b757c49fd'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t)<>'fdddb50d53ff8be527186aa01dc4f710'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t)<>'b18f15673637280bf1455667ccd3cc00'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t)<>'d8d72d5f886e363b80bca4aecfe22522'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t)<>'dfa2bdb71f812f4b2aa0a23613edf289'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t)<>'dccaf8446c3907b48cec9bf028b4373c'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t)<>'8e467489878b5bbe15f9eadbcbaabb10' then
    raise exception 'P0B2_PRODUCTION_BUSINESS_HASH_DRIFT';
  end if;
end
$hashes$;
rollback;
