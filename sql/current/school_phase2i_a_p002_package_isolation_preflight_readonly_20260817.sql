-- School V2 Phase 2I-A P002 package isolation production preflight. SELECT only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select current_setting('transaction_read_only') transaction_read_only,
  current_setting('transaction_isolation') transaction_isolation;

select to_jsonb(lesson) p002_lesson,
  md5(to_jsonb(lesson)::text) p002_row_md5
from public.school_lesson_records lesson
where lesson.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';

select to_jsonb(student_row) student_fact
from public.school_students student_row
where student_row.id='a7b163a0-201e-4867-9b94-372343356a80';
select to_jsonb(entity_row) business_entity_fact
from public.school_business_entities entity_row
where entity_row.id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
select to_jsonb(relation_row) bill_lesson_fact
from public.school_student_tuition_bill_lessons relation_row
where relation_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';
select to_jsonb(bill_row) bill_fact
from public.school_student_tuition_bills bill_row
where bill_row.id in (
  select relation_row.tuition_bill_id
  from public.school_student_tuition_bill_lessons relation_row
  where relation_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
);
select to_jsonb(revision_row) revision_fact
from public.school_student_tuition_generation_revisions revision_row
where revision_row.tuition_bill_id in (
  select relation_row.tuition_bill_id
  from public.school_student_tuition_bill_lessons relation_row
  where relation_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
);
select to_jsonb(income_row) income_fact
from public.school_income_records income_row
where income_row.tuition_bill_id in (
  select relation_row.tuition_bill_id
  from public.school_student_tuition_bill_lessons relation_row
  where relation_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
);
select to_jsonb(linkage_row) cash_linkage_fact
from public.school_personal_cash_income_linkage_events linkage_row
where linkage_row.income_record_id in (
  select income_row.id from public.school_income_records income_row
  where income_row.tuition_bill_id in (
    select relation_row.tuition_bill_id
    from public.school_student_tuition_bill_lessons relation_row
    where relation_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
  )
);

select public.school_get_lesson_credit_raw_remaining_hours(
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
) raw_remaining_hours,
public.school_get_lesson_credit_remaining_hours(
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
) public_remaining_hours;

select count(*) open_reader_count
from public.school_list_open_lesson_credit_sources('2026-07','2026-07','2026-07') source
where source.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';

select * from public.school_tuition_p0f_source_lines(
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',0.045,false
)
where source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';

select jsonb_pretty(public.school_preview_student_settlement_adjustment_dialog(
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  '2026-07','separate_makeup_and_overage_v1',null,null,null,
  'carry_final_balance',null
)) p002_settlement_preview;

select count(*) active_claim_count
from public.school_student_settlement_lesson_variance_claims claim
where claim.claim_status='active'
  and (claim.source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
    or claim.source_actual_lesson_id in (
      select actual_row.id from public.school_lesson_records actual_row
      where actual_row.planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
    ));

select procedure.oid::regprocedure::text signature,
  pg_get_userbyid(procedure.proowner) owner,
  procedure.prosecdef security_definer,
  coalesce(array_to_string(procedure.proconfig,','),'') settings,
  coalesce(array_to_string(procedure.proacl,','),'') acl,
  md5(pg_get_functiondef(procedure.oid)) definition_md5
from pg_proc procedure
join pg_namespace namespace on namespace.oid=procedure.pronamespace
where namespace.nspname='public' and procedure.proname in (
  'school_get_lesson_credit_raw_remaining_hours',
  'school_get_lesson_credit_remaining_hours',
  'school_list_student_lesson_credit_balances',
  'school_get_lesson_credit_summary',
  'school_list_open_lesson_credit_sources',
  'school_create_lesson_credit_makeup_actual',
  'school_tuition_p0f_source_lines',
  'school_tuition_p0f_assert_sources_resolved',
  'school_preview_student_settlement_adjustment_dialog'
)
order by procedure.oid::regprocedure::text;

select to_regclass('public.school_student_package_credit_lots') package_table,
  to_regprocedure('public.school_list_student_package_credit_lots(uuid)') package_reader,
  to_regprocedure('public.school_is_active_package_credit_origin(uuid)') package_helper,
  to_regclass('public.school_lesson_clearances') clearance_table,
  to_regprocedure(
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'
  ) clearance_writer;

select object_name,row_count,row_hash from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 7,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 8,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 9,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 10,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 11,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
  union all select 12,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
) fingerprints order by sort_order;

select max(updated_at) latest_lesson_update from public.school_lesson_records;
select count(*) open_related_transactions
from pg_stat_activity activity
where activity.datname=current_database() and activity.pid<>pg_backend_pid()
  and activity.xact_start is not null and activity.state<>'idle'
  and (activity.query ilike '%school_lesson_records%'
    or activity.query ilike '%school_student_monthly_settlements%'
    or activity.query ilike '%school_student_settlement_lesson_variance_claims%');

rollback;
