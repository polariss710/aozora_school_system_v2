-- School V2 tuition P0 R1C-C-A future lesson inventory.
-- Strictly read-only: SELECT/DO-only, no temporary objects, no write RPC calls.
-- The historical fixed 68-ID manifest is unavailable. This file reports that
-- fact and separately labels the reproducible current 68-row reconstruction.

\set ON_ERROR_STOP on

do $$
declare
  v_future_raw_count integer;
  v_planned_count integer;
  v_actual_count integer;
  v_reconstructed_68_count integer;
begin
  select
    count(*)::integer,
    count(*) filter (where lesson.lesson_type = 'planned')::integer,
    count(*) filter (where lesson.lesson_type = 'actual')::integer
  into v_future_raw_count, v_planned_count, v_actual_count
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09';

  select count(*)::integer
  into v_reconstructed_68_count
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
    and lesson.lesson_type = 'planned'
    and lesson.status = 'planned'
    and lesson.voided_at is null
    and lesson.is_billable
    and lesson.student_id is not null
    and lesson.business_entity_id is not null
    and lesson.teacher_id is not null
    and lesson.subject_id is not null
    and lesson.lesson_date is not null
    and lesson.lesson_count > 0
    and lesson.duration_hours > 0
    and lesson.unit_price > 0
    and lesson.lesson_fee > 0
    and not exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    );

  if v_future_raw_count <> 77
     or v_planned_count <> 73
     or v_actual_count <> 4
     or v_reconstructed_68_count <> 68 then
    raise exception
      'R1C_C_A_SCOPE_CHANGED: raw=% planned=% actual=% reconstructed_68=%',
      v_future_raw_count,
      v_planned_count,
      v_actual_count,
      v_reconstructed_68_count;
  end if;

  if to_regprocedure(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'
     ) is null then
    raise exception 'R1C_C_A_R1C_B_CANDIDATE_FUNCTION_MISSING';
  end if;

  raise notice
    'R1C_C_A_SCOPE_OK: current raw 77 = 73 planned + 4 actual; reproducible current clean/unfulfilled planned subset = 68; historical fixed 68-ID manifest remains unavailable.';
end;
$$;

-- Direct-evidence status. No original UUIDs or historical row hashes were
-- committed with the lone R1C-A report reference to "68".
select
  '68-ID manifest unavailable'::text as original_68_manifest_status,
  'Direct repository evidence is one aggregate mention in the R1C-A report; Git history, SQL manifests, saved audit outputs, and prior attached prompts contain no fixed original 68 UUID set.'::text as evidence_summary,
  'The 68 rows reconstructed below are a current reproducible query result, not proof of the historical set.'::text as limitation;

-- Cardinality and aggregate math. Values come from the database query.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
reconstructed_68 as (
  select lesson.*
  from future_raw lesson
  where lesson.lesson_type = 'planned'
    and lesson.status = 'planned'
    and lesson.voided_at is null
    and lesson.is_billable
    and lesson.student_id is not null
    and lesson.business_entity_id is not null
    and lesson.teacher_id is not null
    and lesson.subject_id is not null
    and lesson.lesson_date is not null
    and lesson.lesson_count > 0
    and lesson.duration_hours > 0
    and lesson.unit_price > 0
    and lesson.lesson_fee > 0
    and not exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    )
)
select
  count(*)::integer as current_r1c_b_raw_rows,
  count(*) filter (where lesson_type = 'planned')::integer as true_planned_rows,
  count(*) filter (where lesson_type = 'actual')::integer as actual_rows,
  count(*) filter (
    where lesson_type = 'planned' and status = 'planned'
  )::integer as active_status_planned_rows,
  count(*) filter (
    where lesson_type = 'planned' and status = 'pending_makeup'
  )::integer as pending_makeup_planned_rows,
  count(*) filter (
    where lesson_type = 'planned'
      and exists (
        select 1
        from public.school_lesson_records actual
        where actual.planned_lesson_id = future_raw.id
          and actual.lesson_type = 'actual'
          and actual.voided_at is null
      )
  )::integer as planned_rows_with_linked_actual,
  (select count(*) from reconstructed_68)::integer as reconstructed_68_rows,
  sum(duration_hours) as raw_duration_hours,
  sum(lesson_fee) as raw_lesson_fee_jpy,
  (select sum(duration_hours) from reconstructed_68) as reconstructed_68_duration_hours,
  (select sum(lesson_fee) from reconstructed_68) as reconstructed_68_lesson_fee_jpy
from future_raw;

-- Current raw 77 grouped by student/month/type/status.
select
  lesson.year_month,
  lesson.student_id,
  coalesce(student.display_name, student.name) as student_name,
  lesson.lesson_type,
  lesson.status,
  lesson.is_billable,
  lesson.voided_at is not null as is_voided,
  lesson.business_entity_id as lesson_business_entity_id,
  entity.name as lesson_business_entity_name,
  count(*)::integer as row_count,
  sum(lesson.duration_hours) as duration_hours,
  sum(lesson.lesson_fee) as lesson_fee_jpy,
  array_agg(lesson.id order by lesson.lesson_date, lesson.id) as fixed_ids
from public.school_lesson_records lesson
left join public.school_students student on student.id = lesson.student_id
left join public.school_business_entities entity on entity.id = lesson.business_entity_id
where lesson.app_type = 'school'
  and lesson.year_month >= '2026-09'
group by
  lesson.year_month,
  lesson.student_id,
  student.display_name,
  student.name,
  lesson.lesson_type,
  lesson.status,
  lesson.is_billable,
  is_voided,
  lesson.business_entity_id,
  entity.name
order by lesson.year_month, student_name, lesson.lesson_type, lesson.status;

-- Full current raw 77 fingerprint and downstream evidence inventory.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
candidate_scopes as (
  select distinct
    lesson.student_id,
    lesson.year_month,
    student.business_entity_id as requested_business_entity_id
  from future_raw lesson
  join public.school_students student on student.id = lesson.student_id
),
candidate_audit as (
  select candidate.*
  from candidate_scopes scope
  cross join lateral public.school_list_student_tuition_candidates(
    scope.student_id,
    scope.requested_business_entity_id,
    scope.year_month,
    true
  ) candidate
),
evidence as (
  select
    lesson.*,
    coalesce(student.display_name, student.name) as student_name,
    student.business_entity_id as student_default_business_entity_id,
    student_entity.name as student_default_business_entity_name,
    lesson_entity.name as lesson_business_entity_name,
    teacher.name as teacher_name,
    subject.name as subject_name,
    candidate.candidate_status as r1c_b_candidate_status,
    candidate.exclusion_reason as r1c_b_exclusion_reason,
    candidate.bill_evidence_conflict as r1c_b_bill_evidence_conflict,
    (lesson.lesson_date - (extract(isodow from lesson.lesson_date)::integer - 1))::date
      as audit_week_monday,
    (select count(*)::integer
       from public.school_student_tuition_bill_lessons relation
      where relation.planned_lesson_id = lesson.id) as normalized_relation_count,
    array(select distinct relation.relation_role
            from public.school_student_tuition_bill_lessons relation
           where relation.planned_lesson_id = lesson.id
           order by relation.relation_role) as normalized_relation_roles,
    array(select distinct relation.tuition_bill_id
            from public.school_student_tuition_bill_lessons relation
           where relation.planned_lesson_id = lesson.id
           order by relation.tuition_bill_id) as normalized_bill_ids,
    array(select distinct bill.id
            from public.school_student_tuition_bills bill
           where (bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
           order by bill.id) as snapshot_bill_ids,
    array(select distinct identity.id
            from public.school_student_tuition_billing_identities identity
            join public.school_student_tuition_bills bill
              on bill.id = identity.canonical_bill_id
           where bill.id in (
             select relation.tuition_bill_id
             from public.school_student_tuition_bill_lessons relation
             where relation.planned_lesson_id = lesson.id
             union
             select snapshot_bill.id
             from public.school_student_tuition_bills snapshot_bill
             where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
           )
           order by identity.id) as billing_identity_ids,
    (select count(*)::integer
       from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null) as linked_actual_count,
    array(select actual.id
            from public.school_lesson_records actual
           where actual.planned_lesson_id = lesson.id
             and actual.lesson_type = 'actual'
             and actual.voided_at is null
           order by actual.created_at, actual.id) as linked_actual_ids,
    array(select actual.status
            from public.school_lesson_records actual
           where actual.planned_lesson_id = lesson.id
             and actual.lesson_type = 'actual'
             and actual.voided_at is null
           order by actual.created_at, actual.id) as linked_actual_statuses,
    (select count(distinct detail.id)::integer
       from public.school_teacher_wage_lock_details detail
       join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
      where wage.status <> 'void'
        and detail.lesson_record_id in (
          select lesson.id where lesson.lesson_type = 'actual'
          union
          select actual.id
          from public.school_lesson_records actual
          where actual.planned_lesson_id = lesson.id
            and actual.lesson_type = 'actual'
            and actual.voided_at is null
        )) as effective_wage_detail_count,
    array(select distinct detail.id
            from public.school_teacher_wage_lock_details detail
            join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
           where wage.status <> 'void'
             and detail.lesson_record_id in (
               select lesson.id where lesson.lesson_type = 'actual'
               union
               select actual.id
               from public.school_lesson_records actual
               where actual.planned_lesson_id = lesson.id
                 and actual.lesson_type = 'actual'
                 and actual.voided_at is null
             )
           order by detail.id) as effective_wage_detail_ids,
    (select count(*)::integer
       from public.school_student_monthly_settlements settlement
      where settlement.student_id = lesson.student_id
        and settlement.business_entity_id = lesson.business_entity_id
        and settlement.year_month = lesson.year_month
        and settlement.settlement_status = 'locked') as locked_settlement_count,
    array(select settlement.id
            from public.school_student_monthly_settlements settlement
           where settlement.student_id = lesson.student_id
             and settlement.business_entity_id = lesson.business_entity_id
             and settlement.year_month = lesson.year_month
             and settlement.settlement_status = 'locked'
           order by settlement.id) as locked_settlement_ids,
    array(select distinct bill.id
            from public.school_student_tuition_bills bill
           where bill.id in (
             select relation.tuition_bill_id
             from public.school_student_tuition_bill_lessons relation
             where relation.planned_lesson_id = lesson.id
             union
             select snapshot_bill.id
             from public.school_student_tuition_bills snapshot_bill
             where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
           )
           order by bill.id) as downstream_bill_ids,
    array(select distinct income.id
            from public.school_income_records income
           where income.tuition_bill_id in (
             select relation.tuition_bill_id
             from public.school_student_tuition_bill_lessons relation
             where relation.planned_lesson_id = lesson.id
             union
             select snapshot_bill.id
             from public.school_student_tuition_bills snapshot_bill
             where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
           )
           order by income.id) as downstream_income_ids,
    array(select distinct linkage.id
            from public.school_personal_cash_income_linkage_events linkage
           where linkage.income_record_id in (
             select income.id
             from public.school_income_records income
             where income.tuition_bill_id in (
               select relation.tuition_bill_id
               from public.school_student_tuition_bill_lessons relation
               where relation.planned_lesson_id = lesson.id
               union
               select snapshot_bill.id
               from public.school_student_tuition_bills snapshot_bill
               where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
             )
           )
           order by linkage.id) as downstream_cash_linkage_ids,
    array(select distinct transaction_row.id
            from public.school_account_transactions transaction_row
           where transaction_row.related_table = 'school_income_records'
             and transaction_row.related_id in (
               select income.id
               from public.school_income_records income
               where income.tuition_bill_id in (
                 select relation.tuition_bill_id
                 from public.school_student_tuition_bill_lessons relation
                 where relation.planned_lesson_id = lesson.id
                 union
                 select snapshot_bill.id
                 from public.school_student_tuition_bills snapshot_bill
                 where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
               )
             )
           order by transaction_row.id) as downstream_account_transaction_ids,
    exists (
      select 1
      from public.school_business_entity_migration_items item
      where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
        and item.lesson_record_id = lesson.id
    ) as belongs_to_r1c_a_52,
    (
      lesson.lesson_type = 'planned'
      and lesson.status = 'planned'
      and lesson.voided_at is null
      and lesson.is_billable
      and lesson.student_id is not null
      and lesson.business_entity_id is not null
      and lesson.teacher_id is not null
      and lesson.subject_id is not null
      and lesson.lesson_date is not null
      and lesson.lesson_count > 0
      and lesson.duration_hours > 0
      and lesson.unit_price > 0
      and lesson.lesson_fee > 0
      and not exists (
        select 1
        from public.school_lesson_records actual
        where actual.planned_lesson_id = lesson.id
          and actual.lesson_type = 'actual'
          and actual.voided_at is null
      )
    ) as belongs_to_current_reconstructed_68,
    md5(to_jsonb(lesson)::text) as complete_row_md5,
    to_jsonb(lesson) as complete_row_json
  from future_raw lesson
  left join public.school_students student on student.id = lesson.student_id
  left join public.school_business_entities student_entity
    on student_entity.id = student.business_entity_id
  left join public.school_business_entities lesson_entity
    on lesson_entity.id = lesson.business_entity_id
  left join public.school_teachers teacher on teacher.id = lesson.teacher_id
  left join public.school_subjects subject on subject.id = lesson.subject_id
  left join candidate_audit candidate on candidate.planned_lesson_id = lesson.id
)
select
  evidence.id as lesson_record_id,
  evidence.student_id,
  evidence.student_name,
  evidence.student_default_business_entity_id,
  evidence.student_default_business_entity_name,
  evidence.business_entity_id as lesson_business_entity_id,
  evidence.lesson_business_entity_name,
  evidence.app_type,
  evidence.lesson_type,
  evidence.status,
  evidence.voided_at,
  evidence.is_billable,
  evidence.year_month,
  evidence.lesson_date,
  evidence.audit_week_monday,
  evidence.import_batch_id,
  evidence.import_source,
  evidence.teacher_id,
  evidence.teacher_name,
  evidence.subject_id,
  evidence.subject_name,
  evidence.lesson_count,
  evidence.duration_hours,
  evidence.unit_price,
  evidence.lesson_fee,
  evidence.planned_lesson_id,
  evidence.created_at,
  evidence.updated_at,
  evidence.lesson_content,
  evidence.note,
  evidence.complete_row_json,
  evidence.complete_row_md5,
  evidence.r1c_b_candidate_status,
  evidence.r1c_b_exclusion_reason,
  evidence.normalized_relation_count,
  evidence.normalized_relation_roles,
  evidence.normalized_bill_ids,
  evidence.snapshot_bill_ids,
  evidence.billing_identity_ids,
  evidence.r1c_b_bill_evidence_conflict,
  evidence.linked_actual_count,
  evidence.linked_actual_ids,
  evidence.linked_actual_statuses,
  evidence.effective_wage_detail_count,
  evidence.effective_wage_detail_ids,
  evidence.locked_settlement_count,
  evidence.locked_settlement_ids,
  evidence.downstream_bill_ids,
  evidence.downstream_income_ids,
  evidence.downstream_cash_linkage_ids,
  evidence.downstream_account_transaction_ids,
  evidence.belongs_to_r1c_a_52,
  null::boolean as belongs_to_original_68_unavailable,
  evidence.belongs_to_current_reconstructed_68,
  case
    when evidence.lesson_type <> 'planned'
      then 'exclude_from_future_migration'
    when evidence.normalized_relation_count > 0
      or cardinality(evidence.snapshot_bill_ids) > 0
      or cardinality(evidence.downstream_bill_ids) > 0
      then 'exclude_from_future_migration'
    when evidence.linked_actual_count > 0
      or evidence.effective_wage_detail_count > 0
      or evidence.locked_settlement_count > 0
      then 'exclude_from_future_migration'
    when evidence.status <> 'planned'
      or evidence.voided_at is not null
      or evidence.is_billable is distinct from true
      then 'requires_manual_review'
    when evidence.student_id is null
      or evidence.business_entity_id is null
      or evidence.teacher_id is null
      or evidence.subject_id is null
      or evidence.lesson_date is null
      or evidence.lesson_count <= 0
      or evidence.duration_hours <= 0
      or evidence.unit_price <= 0
      or evidence.lesson_fee <= 0
      or evidence.lesson_fee <> evidence.duration_hours * evidence.unit_price
      then 'requires_manual_review'
    when coalesce(evidence.import_source, '') like '%测试%'
      then 'requires_manual_review'
    else 'recommended_for_business_confirmation'
  end as suggested_r1c_c_b_classification,
  case
    when evidence.lesson_type <> 'planned'
      then 'Current 77 contains an actual row, not a future planned lesson.'
    when evidence.normalized_relation_count > 0
      or cardinality(evidence.snapshot_bill_ids) > 0
      or cardinality(evidence.downstream_bill_ids) > 0
      then 'Existing tuition billing evidence.'
    when evidence.linked_actual_count > 0
      then 'Planned lesson already has linked actual evidence.'
    when evidence.effective_wage_detail_count > 0
      then 'Effective teacher wage detail exists.'
    when evidence.locked_settlement_count > 0
      then 'Locked student settlement exists.'
    when evidence.status <> 'planned'
      then 'Planned lesson is not in active planned status.'
    when evidence.voided_at is not null
      or evidence.is_billable is distinct from true
      then 'Voided or non-billable record.'
    when evidence.student_id is null
      or evidence.business_entity_id is null
      or evidence.teacher_id is null
      or evidence.subject_id is null
      or evidence.lesson_date is null
      or evidence.lesson_count <= 0
      or evidence.duration_hours <= 0
      or evidence.unit_price <= 0
      or evidence.lesson_fee <= 0
      or evidence.lesson_fee <> evidence.duration_hours * evidence.unit_price
      then 'Required business fingerprint is incomplete or internally inconsistent.'
    when coalesce(evidence.import_source, '') like '%测试%'
      then 'Source file is explicitly test-labelled; business ownership is unconfirmed.'
    else 'Current clean active unfulfilled planned lesson; recommendation only, not migration approval.'
  end as suggested_reason
from evidence
order by evidence.year_month, evidence.student_name, evidence.lesson_date,
  evidence.lesson_type, evidence.id;

-- Freeze current raw 77 and the current reconstructed 68 as ordered ID/hash
-- arrays. The second array is explicitly inference, not the original manifest.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
reconstructed_68 as (
  select lesson.*
  from future_raw lesson
  where lesson.lesson_type = 'planned'
    and lesson.status = 'planned'
    and lesson.voided_at is null
    and lesson.is_billable
    and lesson.student_id is not null
    and lesson.business_entity_id is not null
    and lesson.teacher_id is not null
    and lesson.subject_id is not null
    and lesson.lesson_date is not null
    and lesson.lesson_count > 0
    and lesson.duration_hours > 0
    and lesson.unit_price > 0
    and lesson.lesson_fee > 0
    and not exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    )
)
select
  (select count(*) from future_raw)::integer as current_raw_count,
  (select array_agg(id order by id) from future_raw) as current_raw_77_ids,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by id::text))
     from future_raw row_value) as current_raw_77_full_row_hash,
  (select count(*) from reconstructed_68)::integer as reconstructed_count,
  (select array_agg(id order by id) from reconstructed_68) as reconstructed_68_ids,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by id::text))
     from reconstructed_68 row_value) as reconstructed_68_full_row_hash;

-- Required original-68 difference groups cannot be stated without inventing
-- the missing manifest or historical fingerprints.
select *
from (values
  ('current_77_intersect_original_68', 'unavailable', 'Original fixed 68 UUID set is unavailable.'),
  ('current_77_only', 'unavailable', 'Cannot compare current rows with an unknown original set.'),
  ('original_68_only', 'unavailable', 'Cannot identify absent original UUIDs.'),
  ('same_id_business_fingerprint_changed', 'unavailable', 'Original per-row hashes were not preserved.')
) difference_group(group_name, result_status, reason);

-- Current raw 77 versus the reproducible current 68 reconstruction. This is a
-- mathematical diagnostic only and must not be renamed as the original set.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
reconstructed_68 as (
  select lesson.*
  from future_raw lesson
  where lesson.lesson_type = 'planned'
    and lesson.status = 'planned'
    and lesson.voided_at is null
    and lesson.is_billable
    and lesson.student_id is not null
    and lesson.business_entity_id is not null
    and lesson.teacher_id is not null
    and lesson.subject_id is not null
    and lesson.lesson_date is not null
    and lesson.lesson_count > 0
    and lesson.duration_hours > 0
    and lesson.unit_price > 0
    and lesson.lesson_fee > 0
    and not exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    )
)
select
  lesson.id,
  lesson.student_id,
  coalesce(student.display_name, student.name) as student_name,
  lesson.year_month,
  lesson.lesson_date,
  lesson.lesson_type,
  lesson.status,
  lesson.is_billable,
  lesson.planned_lesson_id,
  lesson.import_batch_id,
  lesson.import_source,
  lesson.created_at,
  lesson.updated_at,
  md5(to_jsonb(lesson)::text) as complete_row_md5,
  case
    when lesson.lesson_type = 'actual' then 'actual_row_in_r1c_b_raw_inventory'
    when lesson.status <> 'planned' then 'non_active_planned_status'
    when exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = lesson.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    ) then 'planned_has_linked_actual'
    else 'other'
  end as current_77_minus_reconstructed_68_reason
from future_raw lesson
left join reconstructed_68 inferred on inferred.id = lesson.id
left join public.school_students student on student.id = lesson.student_id
where inferred.id is null
order by lesson.year_month, student_name, lesson.lesson_date,
  lesson.lesson_type, lesson.id;

-- Student/month/batch timeline. import_source is kept as a distinct evidence
-- array because batch generation encodes pattern/occurrence in that field.
select
  lesson.student_id,
  coalesce(student.display_name, student.name) as student_name,
  lesson.year_month,
  lesson.import_batch_id,
  array_agg(distinct lesson.import_source order by lesson.import_source)
    filter (where lesson.import_source is not null) as import_sources,
  count(*)::integer as row_count,
  count(*) filter (where lesson.lesson_type = 'planned')::integer as planned_count,
  count(*) filter (where lesson.lesson_type = 'actual')::integer as actual_count,
  sum(lesson.duration_hours) as duration_hours,
  sum(lesson.lesson_fee) as lesson_fee_jpy,
  min(lesson.created_at) as created_at_min,
  max(lesson.created_at) as created_at_max,
  min(lesson.updated_at) as updated_at_min,
  max(lesson.updated_at) as updated_at_max,
  array_agg(lesson.id order by lesson.lesson_date, lesson.lesson_type, lesson.id) as fixed_ids
from public.school_lesson_records lesson
join public.school_students student on student.id = lesson.student_id
where lesson.app_type = 'school'
  and lesson.year_month >= '2026-09'
group by lesson.student_id, student.display_name, student.name,
  lesson.year_month, lesson.import_batch_id
order by lesson.year_month, student_name, lesson.import_batch_id nulls last;

-- Downstream summary over current raw 77.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
)
select
  count(*)::integer as raw_rows,
  count(*) filter (where exists (
    select 1 from public.school_student_tuition_bill_lessons relation
    where relation.planned_lesson_id = future_raw.id
  ))::integer as rows_with_normalized_bill_relation,
  count(*) filter (where exists (
    select 1 from public.school_student_tuition_bills bill
    where (bill.source_snapshot -> 'planned_lesson_ids') ? future_raw.id::text
  ))::integer as rows_with_bill_snapshot_evidence,
  count(*) filter (where exists (
    select 1
    from public.school_student_tuition_billing_identities identity
    join public.school_student_tuition_bills bill on bill.id = identity.canonical_bill_id
    where bill.id in (
      select relation.tuition_bill_id
      from public.school_student_tuition_bill_lessons relation
      where relation.planned_lesson_id = future_raw.id
      union
      select snapshot_bill.id
      from public.school_student_tuition_bills snapshot_bill
      where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? future_raw.id::text
    )
  ))::integer as rows_with_billing_identity,
  count(*) filter (where exists (
    select 1
    from public.school_income_records income
    where income.tuition_bill_id in (
      select relation.tuition_bill_id
      from public.school_student_tuition_bill_lessons relation
      where relation.planned_lesson_id = future_raw.id
      union
      select snapshot_bill.id
      from public.school_student_tuition_bills snapshot_bill
      where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? future_raw.id::text
    )
  ))::integer as rows_with_downstream_income,
  count(*) filter (where exists (
    select 1
    from public.school_personal_cash_income_linkage_events linkage
    where linkage.income_record_id in (
      select income.id
      from public.school_income_records income
      where income.tuition_bill_id in (
        select relation.tuition_bill_id
        from public.school_student_tuition_bill_lessons relation
        where relation.planned_lesson_id = future_raw.id
        union
        select snapshot_bill.id
        from public.school_student_tuition_bills snapshot_bill
        where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? future_raw.id::text
      )
    )
  ))::integer as rows_with_downstream_cash_linkage,
  count(*) filter (where exists (
    select 1
    from public.school_account_transactions transaction_row
    where transaction_row.related_table = 'school_income_records'
      and transaction_row.related_id in (
        select income.id
        from public.school_income_records income
        where income.tuition_bill_id in (
          select relation.tuition_bill_id
          from public.school_student_tuition_bill_lessons relation
          where relation.planned_lesson_id = future_raw.id
          union
          select snapshot_bill.id
          from public.school_student_tuition_bills snapshot_bill
          where (snapshot_bill.source_snapshot -> 'planned_lesson_ids') ? future_raw.id::text
        )
      )
  ))::integer as rows_with_downstream_account_transaction,
  count(*) filter (where exists (
    select 1 from public.school_lesson_records actual
    where actual.planned_lesson_id = future_raw.id
      and actual.lesson_type = 'actual'
      and actual.voided_at is null
  ))::integer as planned_rows_with_linked_actual,
  count(*) filter (where exists (
    select 1
    from public.school_teacher_wage_lock_details detail
    join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
    where wage.status <> 'void'
      and detail.lesson_record_id in (
        select future_raw.id where future_raw.lesson_type = 'actual'
        union
        select actual.id from public.school_lesson_records actual
        where actual.planned_lesson_id = future_raw.id
          and actual.lesson_type = 'actual'
          and actual.voided_at is null
      )
  ))::integer as rows_with_effective_wage_detail,
  count(*) filter (where exists (
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id = future_raw.student_id
      and settlement.business_entity_id = future_raw.business_entity_id
      and settlement.year_month = future_raw.year_month
      and settlement.settlement_status = 'locked'
  ))::integer as rows_with_locked_student_settlement,
  count(*) filter (where exists (
    select 1 from public.school_business_entity_migration_items item
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
      and item.lesson_record_id = future_raw.id
  ))::integer as rows_in_r1c_a_52
from future_raw;

-- Duplicate and anomaly reports. These are evidence, not repair instructions.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
)
select
  'same_business_fingerprint_different_id'::text as anomaly_type,
  student_id,
  lesson_date,
  teacher_id,
  subject_id,
  lesson_count,
  duration_hours,
  unit_price,
  lesson_fee,
  count(*)::integer as row_count,
  array_agg(id order by id) as ids,
  array_agg(lesson_type order by id) as lesson_types,
  array_agg(status order by id) as statuses
from future_raw
group by student_id, lesson_date, teacher_id, subject_id, lesson_count,
  duration_hours, unit_price, lesson_fee
having count(*) > 1
order by lesson_date, student_id;

with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
)
select
  planned.id as planned_lesson_id,
  planned.status as planned_status,
  count(actual.id)::integer as linked_actual_count,
  array_agg(actual.id order by actual.created_at, actual.id) as linked_actual_ids,
  array_agg(actual.status order by actual.created_at, actual.id) as linked_actual_statuses,
  array_agg(actual.is_billable order by actual.created_at, actual.id) as linked_actual_billable_flags
from future_raw planned
join public.school_lesson_records actual
  on actual.planned_lesson_id = planned.id
 and actual.lesson_type = 'actual'
 and actual.voided_at is null
where planned.lesson_type = 'planned'
group by planned.id, planned.status
having count(actual.id) > 1
order by planned.id;

with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
)
select
  count(*) filter (where id is null)::integer as null_id_count,
  count(*) filter (
    where student_id is null
       or business_entity_id is null
       or teacher_id is null
       or subject_id is null
       or lesson_date is null
       or duration_hours <= 0
       or unit_price is null
       or unit_price <= 0
       or lesson_fee is null
       or lesson_fee <= 0
  )::integer as incomplete_business_fingerprint_count,
  count(*) filter (
    where lesson_fee is distinct from duration_hours * unit_price
  )::integer as fee_formula_mismatch_count,
  count(*) filter (where voided_at is not null)::integer as voided_count,
  count(*) filter (where business_entity_id <> '886a8f7c-0fea-45ac-97d2-15c976ede996')::integer
    as non_personal_entity_count,
  count(*) filter (where updated_at is distinct from created_at)::integer
    as edited_after_creation_count
from future_raw;

-- Suggested business-confirmation classes. No row is approved here.
with future_raw as (
  select lesson.*
  from public.school_lesson_records lesson
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
classified as (
  select
    lesson.*,
    case
      when lesson.lesson_type <> 'planned'
        then 'exclude_from_future_migration'
      when exists (
        select 1
        from public.school_student_tuition_bill_lessons relation
        where relation.planned_lesson_id = lesson.id
      ) or exists (
        select 1
        from public.school_student_tuition_bills bill
        where (bill.source_snapshot -> 'planned_lesson_ids') ? lesson.id::text
      ) then 'exclude_from_future_migration'
      when exists (
        select 1
        from public.school_lesson_records actual
        where actual.planned_lesson_id = lesson.id
          and actual.lesson_type = 'actual'
          and actual.voided_at is null
      ) then 'exclude_from_future_migration'
      when lesson.status <> 'planned'
        or lesson.voided_at is not null
        or lesson.is_billable is distinct from true
        then 'requires_manual_review'
      when lesson.student_id is null
        or lesson.business_entity_id is null
        or lesson.teacher_id is null
        or lesson.subject_id is null
        or lesson.lesson_date is null
        or lesson.lesson_count <= 0
        or lesson.duration_hours <= 0
        or lesson.unit_price <= 0
        or lesson.lesson_fee <= 0
        or lesson.lesson_fee <> lesson.duration_hours * lesson.unit_price
        then 'requires_manual_review'
      when coalesce(lesson.import_source, '') like '%测试%'
        then 'requires_manual_review'
      else 'recommended_for_business_confirmation'
    end as suggested_classification
  from future_raw lesson
)
select
  suggested_classification,
  count(*)::integer as row_count,
  sum(duration_hours) as duration_hours,
  sum(lesson_fee) as lesson_fee_jpy,
  array_agg(id order by id) as fixed_ids
from classified
group by suggested_classification
order by suggested_classification;

-- School end-state baseline. Compare exactly with the pre-audit capture.
select
  (select count(*) from public.school_student_tuition_bills) as bill_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bills t) as bill_hash,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_income_records t) as income_hash,
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_billing_identities t) as identity_hash,
  (select count(*) from public.school_student_tuition_bill_lessons) as bill_lesson_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bill_lessons t) as bill_lesson_hash;

select
  (select count(*) from public.school_lesson_records) as lesson_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t) as lesson_hash,
  (select count(*) from public.school_lesson_records where lesson_type = 'planned') as planned_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t where lesson_type = 'planned') as planned_hash,
  (select count(*) from public.school_lesson_records where lesson_type = 'actual') as actual_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t where lesson_type = 'actual') as actual_hash;

select
  (select count(*) from public.school_business_entity_migration_batches) as migration_batch_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_batches t) as migration_batch_hash,
  (select count(*) from public.school_business_entity_migration_items) as migration_item_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_items t) as migration_item_hash,
  (select count(*) from public.school_personal_cash_income_linkage_events) as linkage_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_personal_cash_income_linkage_events t) as linkage_hash,
  (select count(*) from public.school_account_transactions) as account_transaction_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_account_transactions t) as account_transaction_hash;

select
  (select count(*) from public.school_student_monthly_settlements) as settlement_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_monthly_settlements t) as settlement_hash,
  (select count(*) from public.school_teacher_wage_locks) as wage_lock_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_locks t) as wage_lock_hash,
  (select count(*) from public.school_teacher_wage_lock_details) as wage_detail_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_lock_details t) as wage_detail_hash;

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;
