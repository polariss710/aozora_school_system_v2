-- School V2 tuition P0 R1A post-deployment verification.
-- SELECT-only.

select
  count(*) as income_count,
  count(*) filter (where status = 'incident_quarantined') as quarantined_count,
  count(*) filter (where status_before_quarantine is not null) as status_before_nonnull,
  count(*) filter (where incident_type is not null) as incident_type_nonnull,
  count(*) filter (where incident_canonical_income_id is not null) as canonical_income_nonnull,
  count(*) filter (where incident_canonical_bill_id is not null) as canonical_bill_nonnull,
  count(*) filter (where incident_duplicate_bill_id is not null) as duplicate_bill_nonnull,
  count(*) filter (where incident_quarantined_at is not null) as quarantined_at_nonnull,
  count(*) filter (where incident_quarantined_by is not null) as quarantined_by_nonnull,
  count(*) filter (where incident_reason is not null) as incident_reason_nonnull,
  count(*) filter (where cash_submission_blocked) as cash_blocked_true,
  count(*) filter (where operational_excluded) as operational_excluded_true,
  count(*) filter (where tuition_bill_id is not null) as tuition_bill_id_nonnull,
  count(*) filter (
    where status <> 'incident_quarantined'
      and (
        status_before_quarantine is not null
        or incident_type is not null
        or incident_canonical_income_id is not null
        or incident_canonical_bill_id is not null
        or incident_duplicate_bill_id is not null
        or incident_quarantined_at is not null
        or incident_quarantined_by is not null
        or incident_reason is not null
        or cash_submission_blocked
        or operational_excluded
      )
  ) as non_quarantine_incident_field_mismatch
from public.school_income_records;

select
  count(*) as bill_count,
  count(*) filter (where billing_role is not null) as billing_role_nonnull,
  count(*) filter (where incident_locked_at is not null) as incident_locked_at_nonnull,
  count(*) filter (where incident_reason is not null) as incident_reason_nonnull,
  count(*) filter (where cash_submission_blocked) as cash_blocked_true
from public.school_student_tuition_bills;

select
  (select count(*) from public.school_student_tuition_billing_identities) as identity_rows,
  (select count(*) from public.school_student_tuition_bill_lessons) as bill_lesson_rows;

select
  g.feature_key,
  g.state,
  g.release_version
from public.school_feature_gates g
where g.feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by g.feature_key;

select
  c.conrelid::regclass as table_name,
  c.conname,
  c.contype,
  c.convalidated,
  pg_get_constraintdef(c.oid) as definition
from pg_constraint c
where c.conrelid in (
    'public.school_income_records'::regclass,
    'public.school_student_tuition_bills'::regclass,
    'public.school_student_tuition_billing_identities'::regclass,
    'public.school_student_tuition_bill_lessons'::regclass
  )
  and (
    c.conname like '%incident%'
    or c.conname like '%billing_role%'
    or c.conname like '%tuition_bill_id%'
    or c.conname like 'school_tuition_billing_identities_%'
    or c.conname like 'school_tuition_bill_lessons_%'
    or c.conname = 'school_income_records_status_check'
  )
order by c.conrelid::regclass::text, c.conname;

select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'school_income_records_incident_status_idx',
    'school_income_records_incident_canonical_income_idx',
    'school_student_tuition_bills_billing_role_idx',
    'school_tuition_billing_identities_student_month_key',
    'school_tuition_billing_identities_canonical_bill_key',
    'school_tuition_billing_identities_idempotency_key',
    'school_tuition_bill_lessons_bill_planned_key',
    'school_tuition_bill_lessons_bill_line_key',
    'school_tuition_bill_lessons_canonical_planned_key',
    'school_tuition_bill_lessons_bill_role_idx',
    'school_income_records_tuition_bill_id_key'
  )
order by tablename, indexname;

select
  t.tgrelid::regclass as table_name,
  t.tgname,
  t.tgenabled,
  p.proname as trigger_function
from pg_trigger t
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and t.tgname in (
    'school_tuition_billing_identities_immutable',
    'school_tuition_bill_lessons_immutable',
    'school_incident_quarantined_income_immutable',
    'school_r0_tuition_bill_mutation_guard',
    'school_r0_tuition_income_mutation_guard',
    'school_r0_tuition_cash_linkage_mutation_guard'
  )
order by t.tgrelid::regclass::text, t.tgname;

select
  role_name,
  table_name,
  has_table_privilege(
    role_name,
    'public.' || table_name,
    'INSERT'
  ) as can_insert,
  has_table_privilege(
    role_name,
    'public.' || table_name,
    'UPDATE'
  ) as can_update,
  has_table_privilege(
    role_name,
    'public.' || table_name,
    'DELETE'
  ) as can_delete,
  has_table_privilege(
    role_name,
    'public.' || table_name,
    'SELECT'
  ) as can_select
from (
  values
    ('public'::text, 'school_student_tuition_billing_identities'::text),
    ('anon'::text, 'school_student_tuition_billing_identities'::text),
    ('authenticated', 'school_student_tuition_billing_identities'),
    ('service_role', 'school_student_tuition_billing_identities'),
    ('public', 'school_student_tuition_bill_lessons'),
    ('anon', 'school_student_tuition_bill_lessons'),
    ('authenticated', 'school_student_tuition_bill_lessons'),
    ('service_role', 'school_student_tuition_bill_lessons')
) permissions(role_name, table_name)
order by table_name, role_name;

select
  p.oid::regprocedure as function_signature,
  md5(pg_get_functiondef(p.oid)) as definition_hash,
  pg_get_functiondef(p.oid) like '%TUITION_GENERATION_BLOCKED%' as generation_block_present,
  pg_get_functiondef(p.oid) like '%TUITION_CASH_SUBMISSION_BLOCKED%' as cash_block_present
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'school_generate_student_tuition_bill',
    'school_create_student_tuition_bill_income_record',
    'school_create_personal_cash_tuition_income_record',
    'school_request_cash_income_confirmation_for_record'
  )
order by p.oid::regprocedure::text;

select
  p.oid::regprocedure as function_signature,
  pg_get_functiondef(p.oid) ~
    'insert[[:space:]]+into[[:space:]]+public[.]school_income_records[[:space:]]*[(]'
    as uses_explicit_income_insert_column_list
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and pg_get_functiondef(p.oid) ~
    'insert[[:space:]]+into[[:space:]]+public[.]school_income_records'
order by p.oid::regprocedure::text;
