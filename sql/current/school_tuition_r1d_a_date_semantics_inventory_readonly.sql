-- School V2 tuition P0 R1D-A: date, week, billing, settlement, and wage semantics inventory.
-- SELECT/DO-only. No database object or business row is created or changed.

\set ON_ERROR_STOP on

-- 1. Current School business baseline. These hashes are intended for before/after comparison.
select
  baseline.table_name,
  baseline.row_count,
  baseline.business_hash
from (
  select
    'school_student_tuition_bills'::text as table_name,
    count(*) as row_count,
    md5(coalesce(string_agg(md5((to_jsonb(t) - array[
      'billing_role', 'incident_locked_at', 'incident_reason', 'cash_submission_blocked'
    ]::text[])::text), '' order by id::text), '')) as business_hash
  from public.school_student_tuition_bills t

  union all
  select
    'school_income_records', count(*),
    md5(coalesce(string_agg(md5((to_jsonb(t) - array[
      'status_before_quarantine', 'incident_type', 'incident_canonical_income_id',
      'incident_canonical_bill_id', 'incident_duplicate_bill_id',
      'incident_quarantined_at', 'incident_quarantined_by', 'incident_reason',
      'cash_submission_blocked', 'operational_excluded', 'tuition_bill_id'
    ]::text[])::text), '' order by id::text), ''))
  from public.school_income_records t

  union all
  select 'school_student_tuition_billing_identities', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_student_tuition_billing_identities t

  union all
  select 'school_student_tuition_bill_lessons', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_student_tuition_bill_lessons t

  union all
  select 'school_lesson_records', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_lesson_records t

  union all
  select 'school_lesson_records:planned', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_lesson_records t where lesson_type = 'planned'

  union all
  select 'school_lesson_records:actual', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_lesson_records t where lesson_type = 'actual'

  union all
  select 'school_business_entity_migration_batches', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_business_entity_migration_batches t

  union all
  select 'school_business_entity_migration_items', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_business_entity_migration_items t

  union all
  select 'school_personal_cash_income_linkage_events', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_personal_cash_income_linkage_events t

  union all
  select 'school_account_transactions', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_account_transactions t

  union all
  select 'school_student_monthly_settlements', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_student_monthly_settlements t

  union all
  select 'school_teacher_wage_locks', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_teacher_wage_locks t

  union all
  select 'school_teacher_wage_lock_details', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
  from public.school_teacher_wage_lock_details t

  union all
  select 'school_feature_gates', count(*),
    md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by feature_key), ''))
  from public.school_feature_gates t
) baseline
order by baseline.table_name;

-- 1A. Tuition billing month, income business month, and income occurrence date are distinct facts.
select
  bill.id as tuition_bill_id,
  bill.billing_month,
  bill.status as bill_status,
  bill.income_record_id,
  income.income_date,
  income.year_month as income_business_month,
  income.settlement_month as income_settlement_month,
  income.status as income_status,
  (income.tuition_bill_id = bill.id
    and income.source_type = 'student_tuition_bill'
    and income.source_id = bill.id) as exact_reverse_link
from public.school_student_tuition_bills bill
left join public.school_income_records income on income.id = bill.income_record_id
order by bill.billing_month, bill.id;

-- 2. Schema inventory for all persisted date/month/week fields in scope.
select
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in (
    'school_lesson_records',
    'school_student_tuition_bills',
    'school_student_tuition_billing_identities',
    'school_student_tuition_bill_lessons',
    'school_student_monthly_settlements',
    'school_teacher_wage_locks',
    'school_teacher_wage_lock_details',
    'school_income_records',
    'school_account_transactions'
  )
  and (
    c.column_name ~ '(date|month|week|created_at|updated_at|locked_at|voided_at|imported_at)'
    or c.column_name in ('lesson_type', 'status', 'planned_lesson_id')
  )
order by c.table_name, c.ordinal_position;

-- 3. Lesson distribution at the required semantic granularity.
with relation_rollup as (
  select
    relation.planned_lesson_id,
    count(*) as relation_count,
    count(*) filter (where relation.relation_role = 'canonical_charge') as canonical_count,
    array_agg(distinct relation.relation_role order by relation.relation_role) as relation_roles
  from public.school_student_tuition_bill_lessons relation
  group by relation.planned_lesson_id
),
actual_rollup as (
  select
    actual.planned_lesson_id,
    count(*) as linked_actual_count,
    array_agg(distinct actual.year_month order by actual.year_month) as linked_actual_year_months,
    min(actual.lesson_date) as first_actual_date,
    max(actual.lesson_date) as last_actual_date
  from public.school_lesson_records actual
  where actual.lesson_type = 'actual'
    and actual.planned_lesson_id is not null
  group by actual.planned_lesson_id
)
select
  lesson.lesson_type,
  lesson.status,
  lesson.student_id,
  student.name as student_name,
  lesson.business_entity_id,
  entity.name as business_name,
  lesson.year_month,
  to_char(lesson.lesson_date, 'YYYY-MM') as lesson_date_month,
  date_trunc('week', lesson.lesson_date)::date as iso_week_monday,
  to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as iso_week_monday_month,
  lesson.import_batch_id,
  coalesce(relation.relation_roles, array[]::text[]) as relation_roles,
  coalesce(relation.relation_count, 0) as relation_count,
  coalesce(relation.canonical_count, 0) as canonical_relation_count,
  coalesce(actual.linked_actual_count, 0) as linked_actual_count,
  actual.linked_actual_year_months,
  actual.first_actual_date,
  actual.last_actual_date,
  count(*) as lesson_rows,
  sum(coalesce(lesson.duration_hours, 0)) as duration_hours,
  sum(coalesce(lesson.lesson_fee, 0)) as lesson_fee_jpy
from public.school_lesson_records lesson
left join public.school_students student on student.id = lesson.student_id
left join public.school_business_entities entity on entity.id = lesson.business_entity_id
left join relation_rollup relation on relation.planned_lesson_id = lesson.id
left join actual_rollup actual on actual.planned_lesson_id = lesson.id
group by
  lesson.lesson_type, lesson.status, lesson.student_id, student.name,
  lesson.business_entity_id, entity.name, lesson.year_month,
  to_char(lesson.lesson_date, 'YYYY-MM'),
  date_trunc('week', lesson.lesson_date)::date,
  to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM'),
  lesson.import_batch_id, relation.relation_roles, relation.relation_count,
  relation.canonical_count, actual.linked_actual_count,
  actual.linked_actual_year_months, actual.first_actual_date, actual.last_actual_date
order by lesson.lesson_type, lesson.year_month, student.name,
  date_trunc('week', lesson.lesson_date)::date, lesson.import_batch_id;

-- 4. Lesson semantic summary, including invalid, edited, voided, non-billable, and makeup rows.
select
  lesson.lesson_type,
  count(*) as lesson_rows,
  count(*) filter (where lesson.year_month = to_char(lesson.lesson_date, 'YYYY-MM')) as date_month_match,
  count(*) filter (where lesson.year_month <> to_char(lesson.lesson_date, 'YYYY-MM')) as date_month_mismatch,
  count(*) filter (where lesson.year_month = to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')) as week_month_match,
  count(*) filter (where lesson.year_month <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')) as week_month_mismatch,
  count(*) filter (where lesson.lesson_date is null) as null_lesson_date,
  count(*) filter (where lesson.year_month is null or lesson.year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$') as null_or_invalid_year_month,
  count(*) filter (where lesson.student_id is null) as null_student,
  count(*) filter (where lesson.business_entity_id is null) as null_business_entity,
  count(*) filter (where lesson.updated_at is distinct from lesson.created_at) as edited_rows,
  count(*) filter (where lesson.voided_at is not null) as voided_rows,
  count(*) filter (where not lesson.is_billable) as non_billable_rows,
  count(*) filter (where lesson.status in ('pending_makeup', 'makeup_completed')) as makeup_status_rows,
  count(*) filter (where lesson.planned_lesson_id is not null) as linked_to_planned_rows
from public.school_lesson_records lesson
group by lesson.lesson_type
order by lesson.lesson_type;

-- 5. Planned-to-actual date and month relationship.
select
  planned.id as planned_lesson_id,
  planned.lesson_date as scheduled_lesson_date,
  planned.year_month as planned_year_month,
  date_trunc('week', planned.lesson_date)::date as planned_iso_week_monday,
  actual.id as actual_lesson_id,
  actual.status as actual_status,
  actual.lesson_date as occurred_lesson_date,
  actual.year_month as actual_year_month,
  actual.teacher_settlement_month,
  to_char(actual.lesson_date, 'YYYY-MM') as occurred_date_month,
  (planned.year_month = actual.year_month) as same_student_month,
  (to_char(actual.lesson_date, 'YYYY-MM') = actual.year_month) as actual_month_matches_occurred_date,
  (actual.teacher_settlement_month = to_char(actual.lesson_date, 'YYYY-MM')) as wage_month_matches_occurred_date
from public.school_lesson_records planned
join public.school_lesson_records actual
  on actual.planned_lesson_id = planned.id
 and actual.lesson_type = 'actual'
where planned.lesson_type = 'planned'
order by planned.id, actual.lesson_date, actual.id;

-- 6. All 121 historical bill-lesson rows: frozen evidence, current row, and model classifications.
with evidence as (
  select
    relation.id as relation_id,
    relation.tuition_bill_id,
    relation.planned_lesson_id,
    relation.relation_role,
    relation.line_no,
    relation.billing_month_snapshot,
    relation.week_start_date_snapshot,
    relation.scheduled_lesson_date_snapshot,
    relation.attribution_confidence,
    relation.snapshot_source,
    relation.source_lesson_updated_at,
    bill.billing_month as bill_billing_month,
    identity.billing_month as identity_billing_month,
    lesson.year_month as current_lesson_year_month,
    lesson.lesson_date as current_lesson_date,
    to_char(lesson.lesson_date, 'YYYY-MM') as current_lesson_date_month,
    date_trunc('week', lesson.lesson_date)::date as current_iso_week_monday,
    to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as current_iso_week_monday_month,
    relation.source_snapshot -> 'current_planned_lesson' ->> 'year_month' as r1b_evidence_year_month,
    (relation.source_snapshot -> 'current_planned_lesson' ->> 'lesson_date')::date as r1b_evidence_lesson_date,
    relation.source_snapshot ->> 'scheduled_date_policy' as scheduled_date_policy,
    (relation.source_snapshot ->> 'historical_schedule_dates_available')::boolean as historical_schedule_dates_available,
    (bill.source_snapshot ->> 'billing_month') as bill_json_billing_month,
    ((bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text) as bill_json_contains_lesson,
    ((relation.source_snapshot ->> 'bill_json_planned_lesson_id')::uuid = lesson.id) as relation_json_id_matches,
    (relation.source_snapshot -> 'current_planned_lesson' = to_jsonb(lesson)) as current_row_matches_r1b_evidence
  from public.school_student_tuition_bill_lessons relation
  join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
  join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
  left join public.school_student_tuition_billing_identities identity
    on identity.canonical_bill_id = bill.id
)
select
  evidence.*,
  case
    when evidence.billing_month_snapshot <> evidence.bill_billing_month
      or evidence.bill_json_billing_month <> evidence.bill_billing_month
      or not evidence.bill_json_contains_lesson
      or not evidence.relation_json_id_matches
      or (evidence.relation_role = 'canonical_charge'
          and evidence.identity_billing_month is distinct from evidence.bill_billing_month)
      then 'conflict'
    when not evidence.current_row_matches_r1b_evidence then 'current_lesson_drift'
    when evidence.scheduled_lesson_date_snapshot is null
      or evidence.week_start_date_snapshot is null
      or not coalesce(evidence.historical_schedule_dates_available, false)
      then 'insufficient_evidence'
    else 'historical_snapshot_only'
  end as evidence_classification,
  case
    when evidence.bill_billing_month = evidence.current_lesson_date_month
      and evidence.bill_billing_month = evidence.current_iso_week_monday_month
      then 'calendar_month_match+week_start_month_match'
    when evidence.bill_billing_month = evidence.current_iso_week_monday_month
      and evidence.bill_billing_month <> evidence.current_lesson_date_month
      then 'cross_month_week_charge'
    when evidence.bill_billing_month = evidence.current_lesson_date_month
      then 'calendar_month_match_only'
    when evidence.bill_billing_month = evidence.current_iso_week_monday_month
      then 'week_start_month_match_only'
    else 'neither_current_calendar_nor_week_month'
  end as current_model_classification
from evidence
order by evidence.bill_billing_month, evidence.tuition_bill_id,
  evidence.line_no, evidence.relation_id;

-- 7. Historical relation classification counts and evidence sufficiency.
with relation_audit as (
  select
    relation.relation_role,
    bill.billing_month,
    identity.billing_month as identity_month,
    lesson.year_month,
    to_char(lesson.lesson_date, 'YYYY-MM') as date_month,
    to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as week_month,
    relation.billing_month_snapshot,
    relation.week_start_date_snapshot,
    relation.scheduled_lesson_date_snapshot,
    ((bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text) as json_has_id,
    (relation.source_snapshot -> 'current_planned_lesson' = to_jsonb(lesson)) as current_matches_r1b
  from public.school_student_tuition_bill_lessons relation
  join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
  join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
  left join public.school_student_tuition_billing_identities identity
    on identity.canonical_bill_id = bill.id
)
select
  relation_role,
  count(*) as relation_rows,
  count(*) filter (where billing_month = date_month) as calendar_month_match,
  count(*) filter (where billing_month = week_month) as week_start_month_match,
  count(*) filter (where billing_month = week_month and billing_month <> date_month) as cross_month_week_charge,
  count(*) filter (where week_start_date_snapshot is null or scheduled_lesson_date_snapshot is null) as insufficient_evidence,
  count(*) filter (where not current_matches_r1b) as current_lesson_drift,
  count(*) filter (where billing_month_snapshot <> billing_month or not json_has_id) as normalized_json_conflict,
  count(*) filter (where relation_role = 'canonical_charge' and identity_month is distinct from billing_month) as identity_conflict
from relation_audit
group by relation_role
order by relation_role;

-- 8. Fixed evidence for Sun Chenfeng's two cross-month lessons. These rows are never changed here.
select
  lesson.id as planned_lesson_id,
  student.name as student_name,
  lesson.lesson_date,
  lesson.year_month as current_year_month,
  date_trunc('week', lesson.lesson_date)::date as iso_week_monday,
  to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as iso_week_monday_month,
  relation.tuition_bill_id as canonical_bill_id,
  bill.billing_month as canonical_bill_month,
  identity.billing_month as billing_identity_month,
  relation.relation_role,
  relation.billing_month_snapshot,
  relation.scheduled_lesson_date_snapshot,
  relation.week_start_date_snapshot,
  ((bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text) as bill_json_contains_lesson,
  ((relation.source_snapshot ->> 'bill_json_planned_lesson_id')::uuid = lesson.id) as normalized_json_id_match,
  md5(to_jsonb(lesson)::text) as current_row_hash
from public.school_lesson_records lesson
join public.school_students student on student.id = lesson.student_id
join public.school_student_tuition_bill_lessons relation
  on relation.planned_lesson_id = lesson.id
 and relation.relation_role = 'canonical_charge'
join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
join public.school_student_tuition_billing_identities identity
  on identity.canonical_bill_id = bill.id
where lesson.id in (
  '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid,
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'::uuid
)
order by lesson.lesson_date, lesson.id;

-- 9. R1C-A fixed 52 and R1C-C-B fixed 66: row-level simulation of calendar and week rules.
select
  batch.migration_key,
  item.item_order,
  item.lesson_record_id,
  item.student_id,
  lesson.lesson_date,
  to_char(lesson.lesson_date, 'YYYY-MM') as calendar_candidate_month,
  date_trunc('week', lesson.lesson_date)::date as iso_week_monday,
  to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as week_candidate_month,
  lesson.year_month as current_candidate_month,
  case
    when to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') = lesson.year_month
      then lesson.year_month
    else to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')
  end as recommended_default_billing_month_simulation,
  (lesson.year_month = to_char(lesson.lesson_date, 'YYYY-MM')) as current_equals_calendar,
  (lesson.year_month = to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')) as current_equals_week,
  (to_char(lesson.lesson_date, 'YYYY-MM') = to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')) as calendar_equals_week,
  md5(to_jsonb(lesson)::text) as current_row_hash
from public.school_business_entity_migration_items item
join public.school_business_entity_migration_batches batch on batch.id = item.batch_id
join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
where item.batch_id in (
  'c1000000-0000-4000-8000-202607279999'::uuid,
  'c1000000-0000-4000-8000-202607289999'::uuid
)
order by item.batch_id, item.item_order;

-- 10. Fixed-manifest model simulation summary. A changed_set count above zero would require a new review.
select
  batch.migration_key,
  count(*) as manifest_rows,
  sum((item.original_row_snapshot ->> 'duration_hours')::numeric) as duration_hours,
  sum((item.original_row_snapshot ->> 'lesson_fee')::numeric) as lesson_fee_jpy,
  count(*) filter (where lesson.year_month = to_char(lesson.lesson_date, 'YYYY-MM')) as current_equals_calendar,
  count(*) filter (where lesson.year_month = to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')) as current_equals_week,
  count(*) filter (
    where to_char(lesson.lesson_date, 'YYYY-MM')
      <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')
  ) as calendar_week_disagreement,
  count(*) filter (
    where lesson.year_month
      <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')
  ) as changed_set_under_week_rule
from public.school_business_entity_migration_items item
join public.school_business_entity_migration_batches batch on batch.id = item.batch_id
join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
where item.batch_id in (
  'c1000000-0000-4000-8000-202607279999'::uuid,
  'c1000000-0000-4000-8000-202607289999'::uuid
)
group by batch.migration_key
order by batch.migration_key;

-- 10A. Current R1C-B DB-authoritative candidate sets for the two approved manifests.
with requested_scopes(student_id, business_entity_id, billing_month, expected_batch_id) as (
  values
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
     '2026-08'::text, 'c1000000-0000-4000-8000-202607279999'::uuid),
    ('b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
     '2026-08'::text, 'c1000000-0000-4000-8000-202607279999'::uuid),
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
     '2026-09'::text, 'c1000000-0000-4000-8000-202607289999'::uuid),
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
     '2026-10'::text, 'c1000000-0000-4000-8000-202607289999'::uuid),
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
     '2026-11'::text, 'c1000000-0000-4000-8000-202607289999'::uuid)
),
candidate_rows as (
  select scope.*, candidate.planned_lesson_id
  from requested_scopes scope
  cross join lateral public.school_list_student_tuition_candidates(
    scope.student_id, scope.business_entity_id, scope.billing_month, false
  ) candidate
),
manifest_rows as (
  select
    item.batch_id,
    item.student_id,
    item.target_year_month as billing_month,
    item.lesson_record_id
  from public.school_business_entity_migration_items item
  where item.batch_id in (
    'c1000000-0000-4000-8000-202607279999'::uuid,
    'c1000000-0000-4000-8000-202607289999'::uuid
  )
)
select
  scope.student_id,
  student.name as student_name,
  scope.billing_month,
  scope.expected_batch_id,
  count(distinct candidate.planned_lesson_id) as candidate_count,
  (select count(*)
   from manifest_rows manifest
   where manifest.batch_id = scope.expected_batch_id
     and manifest.student_id = scope.student_id
     and manifest.billing_month = scope.billing_month) as manifest_count,
  count(distinct candidate.planned_lesson_id) filter (where exists (
    select 1
    from manifest_rows manifest
    where manifest.batch_id = scope.expected_batch_id
      and manifest.student_id = scope.student_id
      and manifest.billing_month = scope.billing_month
      and manifest.lesson_record_id = candidate.planned_lesson_id
  )) as candidate_manifest_intersection
from requested_scopes scope
left join candidate_rows candidate
  on candidate.student_id = scope.student_id
 and candidate.business_entity_id = scope.business_entity_id
 and candidate.billing_month = scope.billing_month
 and candidate.expected_batch_id = scope.expected_batch_id
join public.school_students student on student.id = scope.student_id
group by scope.student_id, student.name, scope.billing_month, scope.expected_batch_id
order by scope.expected_batch_id, scope.billing_month, student.name;

-- 10B. Every historical bill-evidence row must remain excluded by the current candidate rule.
with historical_scopes as (
  select distinct lesson.student_id, lesson.business_entity_id, lesson.year_month
  from public.school_student_tuition_bill_lessons relation
  join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
),
candidate_audit as (
  select candidate.*
  from historical_scopes scope
  cross join lateral public.school_list_student_tuition_candidates(
    scope.student_id, scope.business_entity_id, scope.year_month, true
  ) candidate
)
select
  relation.relation_role,
  candidate.candidate_status,
  candidate.exclusion_reason,
  count(*) as relation_rows
from public.school_student_tuition_bill_lessons relation
join candidate_audit candidate on candidate.planned_lesson_id = relation.planned_lesson_id
group by relation.relation_role, candidate.candidate_status, candidate.exclusion_reason
order by relation.relation_role, candidate.candidate_status, candidate.exclusion_reason;

-- 11. Student settlement and teacher wage month relationships for actual lessons.
select
  actual.year_month as actual_student_month,
  to_char(actual.lesson_date, 'YYYY-MM') as occurred_date_month,
  actual.teacher_settlement_month,
  planned.year_month as source_planned_month,
  actual.status,
  count(*) as actual_rows,
  count(*) filter (where student_settlement.id is not null) as matching_actual_month_student_settlement,
  count(*) filter (where source_settlement.id is not null) as matching_source_planned_month_student_settlement,
  count(*) filter (where wage_evidence.has_current_wage_detail) as current_wage_detail_rows,
  count(*) filter (where wage_evidence.has_matching_wage_month) as matching_wage_month_rows,
  count(*) filter (where actual.year_month <> to_char(actual.lesson_date, 'YYYY-MM')) as actual_date_month_mismatch,
  count(*) filter (where actual.teacher_settlement_month is distinct from to_char(actual.lesson_date, 'YYYY-MM')) as wage_date_month_mismatch
from public.school_lesson_records actual
left join public.school_lesson_records planned on planned.id = actual.planned_lesson_id
left join public.school_student_monthly_settlements student_settlement
  on student_settlement.student_id = actual.student_id
 and student_settlement.year_month = actual.year_month
left join public.school_student_monthly_settlements source_settlement
  on source_settlement.student_id = planned.student_id
 and source_settlement.year_month = planned.year_month
left join lateral (
  select
    coalesce(bool_or(wage.status <> 'void'), false) as has_current_wage_detail,
    coalesce(bool_or(
      wage.status <> 'void'
      and wage.settlement_month = coalesce(actual.teacher_settlement_month, actual.year_month)
    ), false) as has_matching_wage_month
  from public.school_teacher_wage_lock_details detail
  join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
  where detail.lesson_record_id = actual.id
) wage_evidence on true
where actual.lesson_type = 'actual'
group by actual.year_month, to_char(actual.lesson_date, 'YYYY-MM'),
  actual.teacher_settlement_month, planned.year_month, actual.status
order by actual.year_month, occurred_date_month, actual.teacher_settlement_month,
  source_planned_month, actual.status;

-- 12. Locked wage detail date drift. Frozen details remain historical facts even when current rows differ.
select
  wage.status as wage_lock_status,
  wage.settlement_month,
  count(*) as detail_rows,
  count(*) filter (where lesson.id is null) as missing_current_lesson,
  count(*) filter (where detail.lesson_date is distinct from lesson.lesson_date) as frozen_date_drift,
  count(*) filter (where detail.student_id is distinct from lesson.student_id) as frozen_student_drift,
  count(*) filter (where detail.subject_id is distinct from lesson.subject_id) as frozen_subject_drift,
  count(*) filter (where detail.business_entity_id is distinct from lesson.business_entity_id) as frozen_business_entity_drift,
  count(*) filter (
    where lesson.id is not null
      and wage.settlement_month is distinct from coalesce(lesson.teacher_settlement_month, lesson.year_month)
  ) as wage_month_current_lesson_drift
from public.school_teacher_wage_lock_details detail
join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
left join public.school_lesson_records lesson on lesson.id = detail.lesson_record_id
group by wage.status, wage.settlement_month
order by wage.settlement_month, wage.status;

-- 13. Makeup source/completion semantics.
select
  planned.id as source_planned_lesson_id,
  planned.status as source_status,
  planned.lesson_date as source_scheduled_date,
  planned.year_month as source_month,
  actual.id as completion_actual_lesson_id,
  actual.status as completion_status,
  actual.lesson_date as completion_date,
  actual.year_month as completion_student_month,
  actual.teacher_settlement_month as completion_wage_month,
  to_char(actual.lesson_date, 'YYYY-MM') as completion_date_month,
  (planned.year_month <> to_char(actual.lesson_date, 'YYYY-MM')) as cross_month_completion
from public.school_lesson_records planned
join public.school_lesson_records actual
  on actual.planned_lesson_id = planned.id
 and actual.lesson_type = 'actual'
where planned.status in ('pending_makeup', 'makeup_completed')
   or actual.status = 'makeup_completed'
order by planned.id, actual.lesson_date, actual.id;

-- 14. Boundary and anomaly inventory.
select
  lesson.id,
  lesson.lesson_type,
  lesson.status,
  lesson.lesson_date,
  lesson.year_month,
  date_trunc('week', lesson.lesson_date)::date as iso_week_monday,
  to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') as iso_week_monday_month,
  case
    when extract(month from lesson.lesson_date) = 2 and extract(day from lesson.lesson_date) = 29 then 'leap_day'
    when extract(month from lesson.lesson_date) = 1
      and extract(month from date_trunc('week', lesson.lesson_date)) = 12 then 'cross_year_week'
    when to_char(lesson.lesson_date, 'YYYY-MM')
      <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') then 'cross_month_week'
    when lesson.year_month <> to_char(lesson.lesson_date, 'YYYY-MM') then 'year_month_vs_date'
    else 'other'
  end as boundary_classification
from public.school_lesson_records lesson
where lesson.year_month <> to_char(lesson.lesson_date, 'YYYY-MM')
   or to_char(lesson.lesson_date, 'YYYY-MM')
      <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')
   or (extract(month from lesson.lesson_date) = 2 and extract(day from lesson.lesson_date) = 29)
order by lesson.lesson_date, lesson.id;

select
  actual.planned_lesson_id,
  count(*) as linked_actual_count,
  array_agg(actual.id order by actual.lesson_date, actual.id) as actual_lesson_ids,
  array_agg(actual.lesson_date order by actual.lesson_date, actual.id) as actual_dates,
  array_agg(actual.year_month order by actual.lesson_date, actual.id) as actual_year_months
from public.school_lesson_records actual
where actual.lesson_type = 'actual'
  and actual.planned_lesson_id is not null
group by actual.planned_lesson_id
having count(*) > 1
order by actual.planned_lesson_id;

select
  relation.planned_lesson_id,
  count(distinct bill.billing_month) as distinct_bill_months,
  array_agg(distinct bill.billing_month order by bill.billing_month) as bill_months,
  array_agg(distinct relation.relation_role order by relation.relation_role) as relation_roles
from public.school_student_tuition_bill_lessons relation
join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
group by relation.planned_lesson_id
having count(distinct bill.billing_month) > 1
order by relation.planned_lesson_id;

-- 15. Fail-closed assertions: evidence coverage, fixed examples, model simulation, and R0 gates.
do $$
begin
  if (select count(*) from public.school_student_tuition_bill_lessons) <> 121 then
    raise exception 'R1D_A_RELATION_COUNT_CHANGED';
  end if;

  if exists (
    with snapshot_rows as (
      select
        bill.id as bill_id,
        snapshot.lesson_id_text::uuid as planned_lesson_id,
        snapshot.line_no::integer as line_no
      from public.school_student_tuition_bills bill
      cross join lateral jsonb_array_elements_text(
        bill.source_snapshot -> 'planned_lesson_ids'
      ) with ordinality snapshot(lesson_id_text, line_no)
    )
    select 1
    from (
      (select bill_id, planned_lesson_id, line_no from snapshot_rows
       except
       select tuition_bill_id, planned_lesson_id, line_no
       from public.school_student_tuition_bill_lessons)
      union all
      (select tuition_bill_id, planned_lesson_id, line_no
       from public.school_student_tuition_bill_lessons
       except
       select bill_id, planned_lesson_id, line_no from snapshot_rows)
    ) mismatch
  ) then
    raise exception 'R1D_A_NORMALIZED_JSON_RELATION_CONFLICT';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bill_lessons relation
    join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
    left join public.school_student_tuition_billing_identities identity
      on identity.canonical_bill_id = bill.id
    where relation.billing_month_snapshot <> bill.billing_month
       or (bill.source_snapshot ->> 'billing_month') <> bill.billing_month
       or not ((bill.source_snapshot -> 'planned_lesson_ids') ? relation.planned_lesson_id::text)
       or (relation.relation_role = 'canonical_charge'
           and identity.billing_month is distinct from bill.billing_month)
  ) then
    raise exception 'R1D_A_HISTORICAL_BILLING_EVIDENCE_CONFLICT';
  end if;

  if (select count(*)
      from public.school_lesson_records lesson
      join public.school_student_tuition_bill_lessons relation
        on relation.planned_lesson_id = lesson.id
       and relation.relation_role = 'canonical_charge'
      join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
      where lesson.id in (
        '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid,
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'::uuid
      )
        and lesson.year_month = '2026-08'
        and to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM') = '2026-07'
        and bill.id = '2a9f1c25-a060-461e-ae10-b02295dec381'::uuid
        and bill.billing_month = '2026-07') <> 2 then
    raise exception 'R1D_A_SUN_CROSS_MONTH_EVIDENCE_CHANGED';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id = 'c1000000-0000-4000-8000-202607279999') <> 52
     or (select count(*) from public.school_business_entity_migration_items
         where batch_id = 'c1000000-0000-4000-8000-202607289999') <> 66
     or exists (
       select 1
       from public.school_business_entity_migration_items item
       join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
       where item.batch_id in (
         'c1000000-0000-4000-8000-202607279999'::uuid,
         'c1000000-0000-4000-8000-202607289999'::uuid
       )
         and lesson.year_month
           <> to_char(date_trunc('week', lesson.lesson_date), 'YYYY-MM')
     ) then
    raise exception 'R1D_A_FIXED_MANIFEST_WEEK_SIMULATION_CHANGED';
  end if;

  if exists (
    with historical_scopes as (
      select distinct lesson.student_id, lesson.business_entity_id, lesson.year_month
      from public.school_student_tuition_bill_lessons relation
      join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
    ),
    candidate_audit as (
      select candidate.*
      from historical_scopes scope
      cross join lateral public.school_list_student_tuition_candidates(
        scope.student_id, scope.business_entity_id, scope.year_month, true
      ) candidate
    )
    select 1
    from public.school_student_tuition_bill_lessons relation
    join candidate_audit candidate on candidate.planned_lesson_id = relation.planned_lesson_id
    where candidate.candidate_status <> 'excluded'
  ) then
    raise exception 'R1D_A_HISTORICAL_BILL_EVIDENCE_REOPENED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'R1D_A_R0_GATE_CHANGED';
  end if;

  raise notice 'R1D_A_DATE_SEMANTICS_AUDIT_OK: read-only evidence stable; 121 JSON relations match; fixed 52+66 unchanged under week simulation; R0 gates unchanged.';
end;
$$;

select feature_key, state, reason, updated_at
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;
