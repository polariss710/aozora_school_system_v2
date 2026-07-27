-- School V2 tuition P0 R1B post-deployment acceptance. SELECT-only.

select billing_role, count(*) as bill_count
from public.school_student_tuition_bills
group by billing_role
order by billing_role;

select relation_role, count(*) as relationship_count
from public.school_student_tuition_bill_lessons
group by relation_role
order by relation_role;

select
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select count(*) from public.school_student_tuition_bill_lessons) as relationship_count,
  (select count(*) from public.school_income_records where tuition_bill_id is not null) as paired_income_count,
  (select count(*) from public.school_income_records where status = 'incident_quarantined') as incident_count,
  (select count(*) from public.school_operational_income_records) as operational_income_count,
  (select count(*) from public.school_incident_income_records) as incident_audit_count;

select
  count(*) filter (
    where b.income_record_id = i.id
      and i.source_type = 'student_tuition_bill'
      and i.source_id = b.id
      and i.tuition_bill_id = b.id
  ) as exact_pairs,
  count(*) as pair_count
from public.school_student_tuition_bills b
join public.school_income_records i on i.id = b.income_record_id;

select
  count(*) filter (where b.billing_role = 'canonical_charge') as canonical_bills,
  count(*) filter (where b.billing_role = 'incident_duplicate') as incident_bills,
  count(*) filter (where b.billing_role = 'legacy_cancelled') as legacy_bills,
  count(*) filter (where b.billing_role is null) as unclassified_bills,
  count(*) filter (
    where b.billing_role = 'canonical_charge' and identity_row.id is null
  ) as canonical_without_identity,
  count(*) filter (
    where b.billing_role <> 'canonical_charge' and identity_row.id is not null
  ) as noncanonical_with_identity
from public.school_student_tuition_bills b
left join public.school_student_tuition_billing_identities identity_row
  on identity_row.canonical_bill_id = b.id;

select
  count(*) filter (where relation_role = 'canonical_charge') as canonical_relations,
  count(*) filter (where relation_role = 'incident_duplicate') as incident_relations,
  count(*) filter (where relation_role = 'legacy_cancelled') as legacy_relations,
  count(*) filter (where week_start_date_snapshot is not null) as week_snapshot_nonnull,
  count(*) filter (where scheduled_lesson_date_snapshot is not null) as scheduled_snapshot_nonnull,
  count(*) filter (
    where attribution_confidence <> 'medium'
       or snapshot_source <> 'bill_json_exact_id_plus_current_source_fields_aggregate_verified'
       or source_snapshot ->> 'relationship_identity_confidence' <> 'high'
       or source_snapshot ->> 'current_source_field_confidence' <> 'medium'
       or source_snapshot ->> 'bill_aggregate_verified' <> 'true'
       or source_snapshot ->> 'historical_schedule_dates_available' <> 'false'
  ) as evidence_mismatch_count
from public.school_student_tuition_bill_lessons;

select
  count(*) filter (
    where relation_role = 'canonical_charge'
  ) - count(distinct planned_lesson_id) filter (
    where relation_role = 'canonical_charge'
  ) as canonical_duplicate_count,
  count(*) filter (
    where relation_role = 'incident_duplicate'
      and not exists (
        select 1 from public.school_student_tuition_bill_lessons canonical
        where canonical.planned_lesson_id = school_student_tuition_bill_lessons.planned_lesson_id
          and canonical.relation_role = 'canonical_charge'
      )
  ) as incident_without_canonical,
  count(*) filter (
    where relation_role = 'legacy_cancelled'
      and not exists (
        select 1 from public.school_student_tuition_bill_lessons canonical
        where canonical.planned_lesson_id = school_student_tuition_bill_lessons.planned_lesson_id
          and canonical.relation_role = 'canonical_charge'
      )
  ) as legacy_without_canonical
from public.school_student_tuition_bill_lessons;

select
  i.id,
  i.status_before_quarantine,
  i.status,
  i.incident_type,
  i.incident_canonical_income_id,
  i.incident_canonical_bill_id,
  i.incident_duplicate_bill_id,
  i.cash_submission_blocked,
  i.operational_excluded,
  i.tuition_bill_id,
  exists (select 1 from public.school_operational_income_records op where op.id = i.id) as in_operational_view,
  exists (select 1 from public.school_incident_income_records audit where audit.id = i.id) as in_incident_view,
  (select count(*) from public.school_personal_cash_income_linkage_events e where e.income_record_id = i.id) as linkage_count,
  (select count(*) from public.school_account_transactions t where t.related_table = 'school_income_records' and t.related_id = i.id) as account_transaction_count
from public.school_income_records i
where i.id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8';

select
  currency,
  count(*) as operational_count,
  sum(amount) as operational_amount
from public.school_operational_income_records
where app_type = 'school'
group by currency
order by currency;

select
  count(*) filter (where status = 'pending') as operational_pending_count,
  count(*) filter (where status = 'received') as operational_received_count,
  count(*) filter (where status = 'cancelled') as operational_cancelled_count,
  count(*) filter (where status = 'reversed') as operational_reversed_count,
  count(*) filter (where status = 'incident_quarantined') as operational_incident_count
from public.school_operational_income_records;

select feature_key, state, release_version
from public.school_feature_gates
order by feature_key;

select tgname, tgenabled
from pg_trigger
where not tgisinternal
  and tgname in (
    'school_r0_tuition_bill_mutation_guard',
    'school_r0_tuition_income_mutation_guard',
    'school_r0_tuition_cash_linkage_mutation_guard',
    'school_incident_quarantined_income_immutable',
    'school_incident_tuition_bill_immutable',
    'school_incident_income_cash_linkage_guard',
    'school_incident_income_account_transaction_guard',
    'school_tuition_identity_consistency',
    'school_tuition_bill_identity_consistency',
    'school_tuition_bill_income_consistency',
    'school_tuition_income_bill_consistency',
    'school_tuition_bill_lesson_consistency',
    'school_tuition_bill_lesson_row_consistency'
  )
order by tgname;

select
  md5(coalesce(string_agg(md5((to_jsonb(t) - array[
    'billing_role','incident_locked_at','incident_reason','cash_submission_blocked'
  ]::text[])::text), '' order by id::text), '')) as bill_original_business_hash
from public.school_student_tuition_bills t;

select
  md5(coalesce(string_agg(md5((to_jsonb(t) - array[
    'status_before_quarantine','incident_type','incident_canonical_income_id',
    'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
    'incident_quarantined_by','incident_reason','cash_submission_blocked',
    'operational_excluded','tuition_bill_id'
  ]::text[])::text), '' order by id::text), '')) as income_original_business_hash_after_authorized_status_change
from public.school_income_records t;

with expected(income_id, expected_status, expected_original_hash) as (
  values
    ('468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid, 'received',  '76e751b4c6f8855b502591b78286f66f'),
    ('f86ac9db-effd-402e-a320-1e4b6846a9c7'::uuid, 'received',  '99d438fc9f4bcf2d2080584d6e3a0e28'),
    ('bbd7e7fd-fa04-404b-91fc-ab894cca28c8'::uuid, 'pending',   '883dccc58fd713a644ad7b5d9d200a91'),
    ('09fa4398-9d20-494b-8ab5-8f7c3cafa414'::uuid, 'received',  'e208d10927f40820ffd6bc08c57a3396'),
    ('91756564-c48d-4a1d-b6bc-88a041660e46'::uuid, 'received',  '1b17ab68571e0377f841670698cf8f06'),
    ('474f0fd2-71ca-4cce-9ba5-e615bd390151'::uuid, 'cancelled', '501e1612d4332ef60ec4ffeb14efa471'),
    ('4a63f0ca-450f-4306-9e39-6d43172b3cf8'::uuid, 'received',  '02559bbf6d7958f4a43c6f4b778b304b'),
    ('cdf3da68-e578-4f1b-b759-2fff394e1906'::uuid, 'received',  '18570150dc49316287523ea34d34b2a8'),
    ('3a5542c5-5397-4688-999e-a08bb678f40d'::uuid, 'received',  'a7222d442cdac4563e165b6848fc1e7b')
)
select
  count(*) filter (
    where md5(((to_jsonb(i) || jsonb_build_object('status', expected.expected_status)) - array[
      'status_before_quarantine','incident_type','incident_canonical_income_id',
      'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
      'incident_quarantined_by','incident_reason','cash_submission_blocked',
      'operational_excluded','tuition_bill_id'
    ]::text[])::text) = expected.expected_original_hash
  ) as original_income_rows_unchanged,
  count(*) as expected_income_rows
from expected
join public.school_income_records i on i.id = expected.income_id;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as account_transaction_hash
from public.school_account_transactions t;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as lesson_record_hash
from public.school_lesson_records t;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as cash_linkage_hash
from public.school_personal_cash_income_linkage_events t;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as settlement_hash
from public.school_student_monthly_settlements t;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as wage_lock_hash
from public.school_teacher_wage_locks t;

select
  md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) as wage_detail_hash
from public.school_teacher_wage_lock_details t;
