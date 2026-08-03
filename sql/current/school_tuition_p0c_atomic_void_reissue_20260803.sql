-- School V2 tuition P0-C: Atomic Tuition dedicated Void/Reissue.
-- Required psql variable: p0c_migration_commit=0 (rollback rehearsal) or 1 (deploy).
-- Business-model expansion approval: P0-C task sections I-XIII, 2026-08-03.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0c_migration_commit}
\else
  \echo 'P0C_MIGRATION_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

do $preflight$
declare v_signature text; v_expected_md5 text;
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='enabled')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'TUITION_P0C_GATE_BASELINE_INVALID';
  end if;
  if (select count(*) from public.school_student_tuition_billing_identities)<>15 then
    raise exception 'TUITION_P0C_FIXED_15_BASELINE_INVALID';
  end if;
  if exists(select 1 from information_schema.tables where table_schema='public'
    and table_name in ('school_student_tuition_generation_identities',
      'school_student_tuition_generation_revisions',
      'school_student_tuition_generation_void_events')) then
    raise exception 'TUITION_P0C_TARGET_TABLE_ALREADY_EXISTS';
  end if;
  for v_signature,v_expected_md5 in select * from (values
    ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','3e3414b996faf773c5dbc073bc6973b7'),
    ('public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)','6c5f083d2151f43d48bcb3b7d0cc9dfe'),
    ('public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)','65e718ba8d2e4cb46ebb0dc84b11bc2e'),
    ('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)','788ffc50c559116653e4fdb07d6db851'),
    ('public.school_validate_tuition_identity_for_bill(uuid)','8570dbda35c0e0a470888124010d1394'),
    ('public.school_validate_tuition_bill_income_for_bill(uuid)','18b5f07d1ec1c2b6047baa6fce4c4e1d'),
    ('public.school_validate_tuition_bill_lessons_for_bill(uuid)','a19303aa66034a8900fe1077f1a1adc9'),
    ('public.school_enforce_r2_e_planned_aircon()','33d0a36904ef02f595c69caafefe4f92'),
    ('public.school_tuition_p0b1_lesson_financial_authority()','79f76ce47bf05f50ce73f475e5903233'),
    ('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)','0bb6eea4f8439f12d9760e6d0cafd11d'),
    ('public.school_guard_r0_tuition_business_mutation()','98f6ff8612a1b68b0a15cbb4e936852f'),
    ('public.school_guard_tuition_identity_or_lesson_immutable()','c7c6b1e02b0c2a0a7f07827ffbc0dc24'),
    ('public.school_tuition_p0a_consumed_bill_id(uuid)','f881595b9acc06f0c863a5a4fab657c8'),
    ('public.school_get_cash_income_submission_preflight(uuid[])','23aa4f04fa20053e4b38af49067c6a2f'),
    ('public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','02fc85dc099adf6cd6465f53df672d15'),
    ('public.school_cancel_pending_income_record(uuid,text,text)','816cdadf85b9604aca56c8767326f22a')
  ) x(signature,expected_md5) loop
    if md5(pg_get_functiondef(v_signature::regprocedure))<>v_expected_md5 then
      raise exception 'TUITION_P0C_FUNCTION_BASELINE_DRIFT: %',v_signature;
    end if;
  end loop;
end;
$preflight$;

create temporary table tuition_p0c_existing_business_baseline(
  object_name text primary key,row_count bigint not null,full_hash text not null
) on commit drop;
insert into tuition_p0c_existing_business_baseline
select 'legacy_identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
union all select 'relation',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
union all select 'lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t
union all select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t
union all select 'account_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_account_transactions t;

\ir school_tuition_p0c_schema_20260803.sql
\ir school_tuition_p0c_registration_20260803.sql
\ir school_tuition_p0c_authority_cutover_20260803.sql
\ir school_tuition_p0c_writers_20260803.sql

set constraints all immediate;

do $post_assert$
declare r record; v_current record;
begin
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where lifecycle_status='active')<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='atomic_generation_v1')<>8
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='historical_registration_v1')<>7
     or exists(select 1 from public.school_student_tuition_generation_revisions where generation_manifest_sha256 is null) then
    raise exception 'TUITION_P0C_REGISTRATION_POST_ASSERT_FAILED';
  end if;
  for r in select tuition_bill_id from public.school_student_tuition_generation_revisions order by tuition_bill_id loop
    perform public.school_validate_tuition_identity_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_generation_revision_for_bill(r.tuition_bill_id);
  end loop;
  for r in select * from tuition_p0c_existing_business_baseline loop
    execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by t.id::text),'''')) from public.%I t',
      case r.object_name
        when 'legacy_identity' then 'school_student_tuition_billing_identities'
        when 'bill' then 'school_student_tuition_bills'
        when 'income' then 'school_income_records'
        when 'relation' then 'school_student_tuition_bill_lessons'
        when 'lesson' then 'school_lesson_records'
        when 'settlement' then 'school_student_monthly_settlements'
        when 'draft' then 'school_student_settlement_adjustment_drafts'
        when 'adjustment' then 'school_student_settlement_adjustments'
        when 'carryover' then 'school_student_settlement_carryovers'
        when 'cash_linkage' then 'school_personal_cash_income_linkage_events'
        when 'account_transaction' then 'school_account_transactions'
      end) into v_current;
    if v_current.count<>r.row_count or v_current.md5 is distinct from r.full_hash then
      raise exception 'TUITION_P0C_EXISTING_BUSINESS_ROW_DRIFT: %',r.object_name;
    end if;
  end loop;
  if exists(select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'TUITION_P0C_WRITER_CONTEXT_RESIDUE';
  end if;
end;
$post_assert$;

\if :p0c_migration_commit
  commit;
  \echo 'P0C_MIGRATION_COMMITTED'
\else
  rollback;
  \echo 'P0C_MIGRATION_ROLLED_BACK'
\endif
