-- Phase 2C-C postdeploy business zero-change fingerprint. SELECT only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

select object_name,row_count,row_hash from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 7,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 8,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 9,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 10,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 11,'package_lots',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_package_credit_lots x
  union all select 12,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
  union all select 13,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
) fingerprint order by sort_order;

with pending as (
  select lesson.id,public.school_get_lesson_clearance_pending_remaining_minutes(lesson.id) remaining_minutes
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='planned'
    and lesson.status='pending_makeup' and lesson.voided_at is null
    and not public.school_is_active_package_credit_origin(lesson.id)
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
        and claim.source_planned_lesson_id=lesson.id)
), overage as (
  select lesson.id,public.school_get_lesson_clearance_overtime_remaining_minutes(lesson.id) remaining_minutes
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='actual'
    and lesson.status='completed' and lesson.is_billable is true and lesson.voided_at is null
    and lesson.student_duration_overage_policy_version='student_duration_overage_v1'
    and lesson.student_duration_overage_source='ordinary_actual_rpc'
    and lesson.student_duration_overage_minutes>0 and lesson.student_duration_overage_fee_jpy>0
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=lesson.id)
)
select 'pending_available' object_name,count(*) filter(where remaining_minutes>0) row_count,
  coalesce(sum(remaining_minutes) filter(where remaining_minutes>0),0) balance_minutes,
  md5(coalesce(string_agg(id::text||':'||remaining_minutes::text,'|' order by id),'')) manifest
from pending
union all
select 'overage_available',count(*) filter(where remaining_minutes>0),
  coalesce(sum(remaining_minutes) filter(where remaining_minutes>0),0),
  md5(coalesce(string_agg(id::text||':'||remaining_minutes::text,'|' order by id),''))
from overage;

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
select id,origin_planned_lesson_id,initial_minutes,consumed_minutes,remaining_minutes,
  unit_price_jpy,total_price_jpy,student_billing_month,status,md5(to_jsonb(row_value)::text) row_md5
from public.school_student_package_credit_lots row_value
where id='2a000000-0000-4000-8000-202608170002';

rollback;
