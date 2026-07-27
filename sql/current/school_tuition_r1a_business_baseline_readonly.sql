-- School V2 tuition P0 R1A business-data baseline.
-- SELECT-only. The income/bill hashes deliberately omit R1A additive columns
-- so the same expressions are comparable before and after DDL deployment.

select
  'school_income_records' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(
    md5((
      to_jsonb(t) - array[
        'status_before_quarantine',
        'incident_type',
        'incident_canonical_income_id',
        'incident_canonical_bill_id',
        'incident_duplicate_bill_id',
        'incident_quarantined_at',
        'incident_quarantined_by',
        'incident_reason',
        'cash_submission_blocked',
        'operational_excluded',
        'tuition_bill_id'
      ]::text[]
    )::text),
    '' order by id::text
  ), '')) as business_hash
from public.school_income_records t;

select
  'school_student_tuition_bills' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(
    md5((
      to_jsonb(t) - array[
        'billing_role',
        'incident_locked_at',
        'incident_reason',
        'cash_submission_blocked'
      ]::text[]
    )::text),
    '' order by id::text
  ), '')) as business_hash
from public.school_student_tuition_bills t;

select
  'school_account_transactions' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_account_transactions t;

select
  'school_lesson_records' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_lesson_records t;

select
  'school_personal_cash_income_linkage_events' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_personal_cash_income_linkage_events t;

select
  'school_student_monthly_settlements' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_student_monthly_settlements t;

select
  'school_teacher_wage_locks' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_teacher_wage_locks t;

select
  'school_teacher_wage_lock_details' as table_name,
  count(*) as row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as business_hash
from public.school_teacher_wage_lock_details t;
