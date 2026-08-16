-- PTW-independent School V2 monthly settlement registered variance Preview preflight.
-- Read-only production investigation; safe to repeat.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select current_setting('transaction_read_only') as transaction_read_only;

select
  p.oid::regprocedure::text as signature,
  pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as settings,
  coalesce(array_to_string(p.proacl, ','), '') as acl,
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  obj_description(p.oid, 'pg_proc') as comment
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'school_preview_student_settlement_adjustment_dialog',
    'school_preview_student_settlement_source_treatment',
    'school_tuition_p0f_source_lines',
    'school_tuition_p0f_assert_sources_resolved',
    'school_get_student_monthly_settlement_summary_p0f_legacy'
  )
order by p.oid::regprocedure::text;

select jsonb_pretty(public.school_preview_student_settlement_adjustment_dialog(
  '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
  '2026-08',
  'separate_makeup_and_overage_v1',
  null,
  null,
  null,
  'carry_final_balance',
  null
)) as yuan_zhenxuan_separate_preview;

select *
from public.school_tuition_p0f_source_lines(
  '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid,
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
  '2026-08',
  0.0415,
  false
)
order by source_type, source_planned_lesson_id, source_actual_lesson_id;

with scopes as (
  select distinct
    lesson_row.student_id,
    lesson_row.business_entity_id,
    public.school_resolve_r1d_e_c_lesson_student_month(lesson_row.id) as year_month
  from public.school_lesson_records lesson_row
  where lesson_row.app_type='school'
    and lesson_row.lesson_type='planned'
    and lesson_row.voided_at is null
  union
  select distinct
    lesson_row.student_id,
    lesson_row.business_entity_id,
    lesson_row.student_settlement_month as year_month
  from public.school_lesson_records lesson_row
  where lesson_row.app_type='school'
    and lesson_row.lesson_type='actual'
    and lesson_row.voided_at is null
    and lesson_row.student_settlement_month is not null
), source_summary as (
  select
    scope_row.student_id,
    scope_row.business_entity_id,
    scope_row.year_month,
    count(*) filter (where source_row.source_type='unused_planned_credit_v1') as pending_source_count,
    count(*) filter (where source_row.source_type='actual_duration_overage_charge_v1') as overage_source_count,
    coalesce(-sum(source_row.source_hours)
      filter (where source_row.source_type='unused_planned_credit_v1'),0) as pending_hours,
    coalesce(sum(source_row.source_hours)
      filter (where source_row.source_type='actual_duration_overage_charge_v1'),0) as overage_hours
  from scopes scope_row
  join public.school_students student_row on student_row.id=scope_row.student_id
  cross join lateral public.school_tuition_p0f_source_lines(
    scope_row.student_id,
    scope_row.business_entity_id,
    scope_row.year_month,
    student_row.preset_exchange_rate,
    false
  ) source_row
  where scope_row.year_month is not null
  group by scope_row.student_id,scope_row.business_entity_id,scope_row.year_month
)
select *
from source_summary
order by
  (pending_source_count>0 and overage_source_count>0) desc,
  (pending_source_count>0 and overage_source_count=0) desc,
  (pending_source_count=0 and overage_source_count>0) desc,
  year_month,
  student_id;

select object_name, row_count, row_hash
from (
  select 1 as sort_order, 'lessons' as object_name, count(*) as row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), '')) as row_hash
  from public.school_lesson_records x
  union all select 2, 'settlements', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_monthly_settlements x
  union all select 3, 'source_drafts', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_settlement_source_treatment_drafts x
  union all select 4, 'adjustment_drafts', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_settlement_adjustment_drafts x
  union all select 5, 'bills', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_tuition_bills x
  union all select 6, 'bill_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_tuition_bill_lessons x
  union all select 7, 'revisions', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_student_tuition_generation_revisions x
  union all select 8, 'income', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_income_records x
  union all select 9, 'cash_linkages', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_personal_cash_income_linkage_events x
  union all select 10, 'wage_locks', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_teacher_wage_locks x
  union all select 11, 'wage_details', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from public.school_teacher_wage_lock_details x
  union all select 12, 'feature_gates', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.feature_key), ''))
  from public.school_feature_gates x
  union all select 13, 'storage_objects', count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' order by x.id::text), ''))
  from storage.objects x
) fingerprints
order by sort_order;

select feature_key, state
from public.school_feature_gates
order by feature_key;

select count(*) as open_related_transactions
from pg_stat_activity a
where a.datname = current_database()
  and a.pid <> pg_backend_pid()
  and a.xact_start is not null
  and a.state <> 'idle'
  and (
    a.query ilike '%school_lesson_records%'
    or a.query ilike '%school_student_monthly_settlements%'
    or a.query ilike '%school_student_settlement_adjustment_drafts%'
  );

select 'SCHOOL_REGISTERED_VARIANCE_PREVIEW_PREFLIGHT_READONLY_PASS' as result;

rollback;
