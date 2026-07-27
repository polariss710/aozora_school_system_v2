-- School V2 tuition P0 R1A historical-backfill simulation.
-- SELECT-only: this statement expands all 121 bill JSON lesson relationships
-- and returns every simulated row plus validation evidence as JSON sections.

with
bill_base as (
  select
    b.*,
    coalesce(s.display_name, s.name) as student_name,
    i.status as income_status,
    i.source_type as income_source_type,
    i.source_id as income_source_id,
    jsonb_array_length(
      coalesce(b.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
    ) as json_lesson_count,
    link.id as linkage_id,
    link.sync_status,
    link.cash_request_id,
    link.cash_request_status,
    link.cash_transaction_id
  from public.school_student_tuition_bills b
  join public.school_students s on s.id = b.student_id
  left join public.school_income_records i on i.id = b.income_record_id
  left join lateral (
    select e.*
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = b.income_record_id
    order by e.attempt_no desc, e.created_at desc, e.id desc
    limit 1
  ) link on true
),
bill_json_relations as (
  select
    b.id as bill_id,
    b.student_id,
    b.business_entity_id,
    b.billing_month,
    b.created_at as bill_created_at,
    lesson.ordinality::integer as line_no,
    lesson.planned_lesson_id::uuid as planned_lesson_id
  from bill_base b
  cross join lateral jsonb_array_elements_text(
    coalesce(b.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
  ) with ordinality lesson(planned_lesson_id, ordinality)
),
canonical_bills as (
  select b.id as bill_id
  from bill_base b
  where b.status = 'income_created'
    and b.income_status = 'received'
    and b.sync_status = 'synced'
    and b.cash_request_status = 'approved'
    and b.cash_transaction_id is not null
),
full_duplicate_matches as (
  select
    candidate.bill_id,
    canonical.bill_id as canonical_bill_id,
    count(*)::integer as overlap_count
  from bill_json_relations candidate
  join bill_json_relations canonical
    on canonical.planned_lesson_id = candidate.planned_lesson_id
   and canonical.bill_id <> candidate.bill_id
  join canonical_bills cb on cb.bill_id = canonical.bill_id
  join bill_base candidate_bill on candidate_bill.id = candidate.bill_id
  join bill_base canonical_bill on canonical_bill.id = canonical.bill_id
  where candidate_bill.student_id = canonical_bill.student_id
  group by candidate.bill_id, canonical.bill_id,
           candidate_bill.json_lesson_count, canonical_bill.json_lesson_count
  having count(*) = candidate_bill.json_lesson_count
     and count(*) = canonical_bill.json_lesson_count
),
selected_duplicate_match as (
  select distinct on (m.bill_id)
    m.bill_id,
    m.canonical_bill_id,
    m.overlap_count
  from full_duplicate_matches m
  order by m.bill_id, m.canonical_bill_id
),
bill_roles as (
  select
    b.*,
    m.canonical_bill_id as matching_canonical_bill_id,
    case
      when cb.bill_id is not null then 'canonical_charge'
      when b.status = 'income_created'
       and b.income_status = 'pending'
       and m.canonical_bill_id is not null then 'incident_duplicate'
      when b.status = 'cancelled'
       and b.income_status = 'cancelled'
       and m.canonical_bill_id is not null then 'legacy_cancelled'
      else 'unclassified'
    end as simulated_billing_role,
    case
      when cb.bill_id is not null
        then 'received income + synced linkage + approved Cash request + Cash transaction'
      when b.status = 'income_created'
       and b.income_status = 'pending'
       and m.canonical_bill_id is not null
        then 'pending duplicate with an exact same-student planned-lesson set already consumed by canonical bill'
      when b.status = 'cancelled'
       and b.income_status = 'cancelled'
       and m.canonical_bill_id is not null
        then 'cancelled legacy bill with an exact same-student planned-lesson set already consumed by canonical bill'
      else 'no approved R1A classification rule matched'
    end as role_basis
  from bill_base b
  left join canonical_bills cb on cb.bill_id = b.id
  left join selected_duplicate_match m on m.bill_id = b.id
),
identity_simulation as (
  select
    r.student_id,
    r.billing_month,
    r.id as canonical_bill_id,
    'historical_backfill'::text as source,
    concat(
      'historical_backfill:student_tuition:',
      r.student_id::text,
      ':',
      r.billing_month
    ) as creation_idempotency_key,
    jsonb_build_object(
      'bill_status', r.status,
      'income_record_id', r.income_record_id,
      'income_status', r.income_status,
      'cash_linkage_id', r.linkage_id,
      'cash_request_id', r.cash_request_id,
      'cash_transaction_id', r.cash_transaction_id,
      'classification_basis', r.role_basis
    ) as evidence
  from bill_roles r
  where r.simulated_billing_role = 'canonical_charge'
),
relationship_simulation as (
  select
    r.bill_id as tuition_bill_id,
    r.planned_lesson_id,
    role.simulated_billing_role as relation_role,
    r.line_no,
    r.student_id as student_id_snapshot,
    r.business_entity_id as business_entity_id_snapshot,
    r.billing_month as billing_month_snapshot,
    null::date as week_start_date_snapshot,
    null::date as scheduled_lesson_date_snapshot,
    l.teacher_id as teacher_id_snapshot,
    l.subject_id as subject_id_snapshot,
    coalesce(l.lesson_count, 1) as lesson_count_snapshot,
    l.duration_hours as duration_hours_snapshot,
    coalesce(l.unit_price, 0) as unit_price_jpy_snapshot,
    coalesce(l.lesson_fee, 0) as lesson_fee_jpy_snapshot,
    l.updated_at as source_lesson_updated_at,
    jsonb_build_object(
      'bill_json_planned_lesson_id', r.planned_lesson_id,
      'bill_json_line_no', r.line_no,
      'current_planned_lesson', to_jsonb(l),
      'relationship_identity_confidence', 'high',
      'current_source_field_confidence', 'medium',
      'bill_aggregate_verified', true,
      'historical_schedule_dates_available', false,
      'scheduled_date_policy', 'leave_null_do_not_use_actual_date'
    ) as source_snapshot,
    'medium'::text as attribution_confidence,
    'bill_json_exact_id_plus_current_source_fields_aggregate_verified'::text as snapshot_source,
    role.matching_canonical_bill_id
  from bill_json_relations r
  join bill_roles role on role.id = r.bill_id
  left join public.school_lesson_records l on l.id = r.planned_lesson_id
),
relationship_bill_aggregates as (
  select
    rel.tuition_bill_id,
    count(*)::integer as relationship_count,
    count(rel.planned_lesson_id) filter (
      where rel.duration_hours_snapshot is not null
    )::integer as found_source_count,
    coalesce(sum(rel.duration_hours_snapshot), 0)::numeric as relationship_hours,
    coalesce(sum(rel.lesson_fee_jpy_snapshot), 0)::numeric as relationship_fee_jpy
  from relationship_simulation rel
  group by rel.tuition_bill_id
),
bill_income_simulation as (
  select
    b.id as bill_id,
    b.income_record_id,
    i.status as income_status,
    i.source_type,
    i.source_id,
    (i.id = b.income_record_id) as bill_points_to_income,
    (
      i.source_type = 'student_tuition_bill'
      and i.source_id = b.id
    ) as income_points_to_bill,
    (
      select count(*)
      from public.school_income_records other_income
      where other_income.source_type = 'student_tuition_bill'
        and other_income.source_id = b.id
    ) as income_count_for_bill,
    (
      select count(*)
      from public.school_student_tuition_bills other_bill
      where other_bill.income_record_id = i.id
    ) as bill_count_for_income,
    (
      i.id = b.income_record_id
      and i.source_type = 'student_tuition_bill'
      and i.source_id = b.id
      and (
        select count(*)
        from public.school_income_records other_income
        where other_income.source_type = 'student_tuition_bill'
          and other_income.source_id = b.id
      ) = 1
      and (
        select count(*)
        from public.school_student_tuition_bills other_bill
        where other_bill.income_record_id = i.id
      ) = 1
    ) as safe_to_backfill_tuition_bill_id
  from public.school_student_tuition_bills b
  left join public.school_income_records i on i.id = b.income_record_id
),
august_unbilled_candidates as (
  select l.id
  from public.school_lesson_records l
  join public.school_students s on s.id = l.student_id
  where coalesce(s.display_name, s.name) = '陈加恩'
    and l.app_type = 'school'
    and l.lesson_type = 'planned'
    and l.year_month = '2026-08'
    and l.voided_at is null
    and coalesce(l.status, '') not in ('cancelled', 'voided', 'void')
    and not exists (
      select 1
      from relationship_simulation rel
      where rel.planned_lesson_id = l.id
        and rel.relation_role = 'canonical_charge'
    )
),
result_sections as (
  select
    1 as section_order,
    'bill_role_simulation_9_rows'::text as section,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'bill_id', r.id,
        'student', r.student_name,
        'student_id', r.student_id,
        'billing_month', r.billing_month,
        'current_bill_status', r.status,
        'income_id', r.income_record_id,
        'income_status', r.income_status,
        'cash_linkage_id', r.linkage_id,
        'cash_sync_status', r.sync_status,
        'cash_request_id', r.cash_request_id,
        'cash_request_status', r.cash_request_status,
        'cash_transaction_id', r.cash_transaction_id,
        'planned_lesson_count', r.json_lesson_count,
        'simulated_billing_role', r.simulated_billing_role,
        'matching_canonical_bill_id', r.matching_canonical_bill_id,
        'role_basis', r.role_basis
      )
      order by r.student_name, r.billing_month, r.created_at, r.id
    ), '[]'::jsonb) as payload
  from bill_roles r

  union all

  select
    2,
    'bill_role_counts',
    jsonb_build_object(
      'canonical_charge', count(*) filter (where simulated_billing_role = 'canonical_charge'),
      'incident_duplicate', count(*) filter (where simulated_billing_role = 'incident_duplicate'),
      'legacy_cancelled', count(*) filter (where simulated_billing_role = 'legacy_cancelled'),
      'unclassified', count(*) filter (where simulated_billing_role = 'unclassified')
    )
  from bill_roles

  union all

  select
    3,
    'billing_identity_simulation_7_rows',
    coalesce(jsonb_agg(to_jsonb(i) order by i.student_id, i.billing_month), '[]'::jsonb)
  from identity_simulation i

  union all

  select
    4,
    'billing_identity_validation',
    jsonb_build_object(
      'identity_count', count(*),
      'duplicate_student_month_count', (
        select count(*)
        from (
          select student_id, billing_month
          from identity_simulation
          group by student_id, billing_month
          having count(*) > 1
        ) duplicates
      ),
      'duplicate_canonical_bill_count', (
        select count(*)
        from (
          select canonical_bill_id
          from identity_simulation
          group by canonical_bill_id
          having count(*) > 1
        ) duplicates
      ),
      'noncanonical_identity_count', (
        select count(*)
        from identity_simulation identity_row
        join bill_roles role on role.id = identity_row.canonical_bill_id
        where role.simulated_billing_role <> 'canonical_charge'
      )
    )
  from identity_simulation

  union all

  select
    5,
    'bill_lesson_relationship_simulation_121_rows',
    coalesce(jsonb_agg(
      to_jsonb(rel) order by rel.tuition_bill_id, rel.line_no
    ), '[]'::jsonb)
  from relationship_simulation rel

  union all

  select
    6,
    'bill_lesson_relationship_validation',
    jsonb_build_object(
      'canonical_charge', count(*) filter (where relation_role = 'canonical_charge'),
      'incident_duplicate', count(*) filter (where relation_role = 'incident_duplicate'),
      'legacy_cancelled', count(*) filter (where relation_role = 'legacy_cancelled'),
      'total', count(*),
      'canonical_planned_lesson_duplicate_count', (
        select count(*)
        from (
          select planned_lesson_id
          from relationship_simulation
          where relation_role = 'canonical_charge'
          group by planned_lesson_id
          having count(*) > 1
        ) duplicates
      ),
      'incident_without_canonical_count', (
        select count(*)
        from relationship_simulation incident
        where incident.relation_role = 'incident_duplicate'
          and not exists (
            select 1
            from relationship_simulation canonical
            where canonical.relation_role = 'canonical_charge'
              and canonical.planned_lesson_id = incident.planned_lesson_id
          )
      ),
      'legacy_without_canonical_count', (
        select count(*)
        from relationship_simulation legacy
        where legacy.relation_role = 'legacy_cancelled'
          and not exists (
            select 1
            from relationship_simulation canonical
            where canonical.relation_role = 'canonical_charge'
              and canonical.planned_lesson_id = legacy.planned_lesson_id
          )
      ),
      'orphan_planned_lesson_count', count(*) filter (
        where duration_hours_snapshot is null
      ),
      'duplicate_bill_line_count', (
        select count(*)
        from (
          select tuition_bill_id, line_no
          from relationship_simulation
          group by tuition_bill_id, line_no
          having count(*) > 1
        ) duplicates
      ),
      'bill_aggregate_mismatch_count', (
        select count(*)
        from relationship_bill_aggregates aggregate_row
        join bill_base bill on bill.id = aggregate_row.tuition_bill_id
        where aggregate_row.relationship_count <> bill.planned_lesson_count
           or aggregate_row.found_source_count <> bill.planned_lesson_count
           or aggregate_row.relationship_hours <> bill.planned_lesson_hours
           or aggregate_row.relationship_fee_jpy <> bill.planned_lesson_fee_jpy
           or aggregate_row.relationship_fee_jpy <> bill.bill_amount_jpy
      )
    )
  from relationship_simulation

  union all

  select
    7,
    'current_source_vs_frozen_bill_differences',
    coalesce(jsonb_agg(
      jsonb_build_object(
        'bill_id', rel.tuition_bill_id,
        'planned_lesson_id', rel.planned_lesson_id,
        'bill_billing_month', rel.billing_month_snapshot,
        'current_source_year_month', lesson.year_month,
        'bill_business_entity_id', rel.business_entity_id_snapshot,
        'current_source_business_entity_id', lesson.business_entity_id,
        'bill_student_id', rel.student_id_snapshot,
        'current_source_student_id', lesson.student_id,
        'current_source_lesson_date', lesson.lesson_date,
        'source_updated_after_bill', lesson.updated_at > bill.bill_created_at,
        'historical_date_backfill_policy', 'week_start_date_snapshot and scheduled_lesson_date_snapshot remain NULL'
      )
      order by rel.tuition_bill_id, rel.line_no
    ) filter (
      where lesson.year_month is distinct from rel.billing_month_snapshot
         or lesson.business_entity_id is distinct from rel.business_entity_id_snapshot
         or lesson.student_id is distinct from rel.student_id_snapshot
    ), '[]'::jsonb)
  from relationship_simulation rel
  join public.school_lesson_records lesson on lesson.id = rel.planned_lesson_id
  join bill_json_relations bill on bill.bill_id = rel.tuition_bill_id
   and bill.planned_lesson_id = rel.planned_lesson_id

  union all

  select
    8,
    'bill_income_1to1_simulation_9_rows',
    coalesce(jsonb_agg(to_jsonb(pair) order by pair.bill_id), '[]'::jsonb)
  from bill_income_simulation pair

  union all

  select
    9,
    'bill_income_1to1_validation',
    jsonb_build_object(
      'pair_count', count(*),
      'exact_mutual_pair_count', count(*) filter (
        where bill_points_to_income and income_points_to_bill
      ),
      'one_bill_multiple_income_count', count(*) filter (
        where income_count_for_bill <> 1
      ),
      'one_income_multiple_bill_count', count(*) filter (
        where bill_count_for_income <> 1
      ),
      'safe_backfill_count', count(*) filter (
        where safe_to_backfill_tuition_bill_id
      ),
      'unsafe_backfill_count', count(*) filter (
        where not safe_to_backfill_tuition_bill_id
      )
    )
  from bill_income_simulation

  union all

  select
    10,
    'zhang_zhuowen_incident_simulation',
    jsonb_build_object(
      'canonical_bill_id', (max(id::text) filter (
        where simulated_billing_role = 'canonical_charge'
      ))::uuid,
      'canonical_income_id', (max(income_record_id::text) filter (
        where simulated_billing_role = 'canonical_charge'
      ))::uuid,
      'canonical_income_status', max(income_status) filter (
        where simulated_billing_role = 'canonical_charge'
      ),
      'incident_bill_id', (max(id::text) filter (
        where simulated_billing_role = 'incident_duplicate'
      ))::uuid,
      'incident_income_id', (max(income_record_id::text) filter (
        where simulated_billing_role = 'incident_duplicate'
      ))::uuid,
      'incident_income_current_status', max(income_status) filter (
        where simulated_billing_role = 'incident_duplicate'
      ),
      'incident_income_future_status', 'incident_quarantined',
      'incident_relationship_count', (
        select count(*)
        from relationship_simulation rel
        join bill_roles role on role.id = rel.tuition_bill_id
        where role.student_name = '张倬闻'
          and rel.relation_role = 'incident_duplicate'
      ),
      'incident_without_canonical_count', (
        select count(*)
        from relationship_simulation incident
        join bill_roles role on role.id = incident.tuition_bill_id
        where role.student_name = '张倬闻'
          and incident.relation_role = 'incident_duplicate'
          and not exists (
            select 1
            from relationship_simulation canonical
            where canonical.relation_role = 'canonical_charge'
              and canonical.planned_lesson_id = incident.planned_lesson_id
          )
      )
    )
  from bill_roles
  where student_name = '张倬闻'

  union all

  select
    11,
    'chen_jiaen_legacy_simulation',
    jsonb_build_object(
      'legacy_bill_id', (max(id::text) filter (
        where simulated_billing_role = 'legacy_cancelled'
      ))::uuid,
      'legacy_income_id', (max(income_record_id::text) filter (
        where simulated_billing_role = 'legacy_cancelled'
      ))::uuid,
      'legacy_income_status', max(income_status) filter (
        where simulated_billing_role = 'legacy_cancelled'
      ),
      'matching_canonical_bill_id', (max(matching_canonical_bill_id::text) filter (
        where simulated_billing_role = 'legacy_cancelled'
      ))::uuid,
      'legacy_identity_count', (
        select count(*)
        from identity_simulation identity_row
        join bill_roles role on role.id = identity_row.canonical_bill_id
        where role.student_name = '陈加恩'
          and role.simulated_billing_role = 'legacy_cancelled'
      ),
      'legacy_relationship_count', (
        select count(*)
        from relationship_simulation rel
        join bill_roles role on role.id = rel.tuition_bill_id
        where role.student_name = '陈加恩'
          and rel.relation_role = 'legacy_cancelled'
      ),
      'legacy_without_canonical_count', (
        select count(*)
        from relationship_simulation legacy
        join bill_roles role on role.id = legacy.tuition_bill_id
        where role.student_name = '陈加恩'
          and legacy.relation_role = 'legacy_cancelled'
          and not exists (
            select 1
            from relationship_simulation canonical
            where canonical.relation_role = 'canonical_charge'
              and canonical.planned_lesson_id = legacy.planned_lesson_id
          )
      ),
      'correct_august_unbilled_candidate_count', (
        select count(*) from august_unbilled_candidates
      )
    )
  from bill_roles
  where student_name = '陈加恩'
)
select
  section,
  jsonb_pretty(payload) as payload
from result_sections
order by section_order;
