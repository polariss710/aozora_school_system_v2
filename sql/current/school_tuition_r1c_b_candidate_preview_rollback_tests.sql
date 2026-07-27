-- School V2 tuition P0 R1C-B candidate/preview deployment rollback test.
-- DDL is installed and exercised in one transaction, then fully rolled back.
-- The test contains no business DML.

\set ON_ERROR_STOP on

begin;

\ir school_student_tuition_bill_preview_rpc.sql

do $$
declare
  v_preview record;
  v_candidate_ids uuid[];
  v_manifest_ids uuid[];
  v_candidate_count integer;
  v_candidate_hours numeric;
  v_candidate_fee numeric;
  v_historical_candidate_count integer;
  v_canonical_excluded integer;
  v_incident_excluded integer;
  v_legacy_excluded integer;
begin
  select *
    into v_preview
    from public.school_preview_student_tuition_bill(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2026-08',
      0.05
    );

  if v_preview.planned_lesson_count <> 30
     or v_preview.planned_lesson_hours <> 65
     or v_preview.planned_lesson_fee_jpy <> 650000 then
    raise exception 'R1C_B_ZHANG_PREVIEW_MISMATCH: %', to_jsonb(v_preview);
  end if;

  select *
    into v_preview
    from public.school_preview_student_tuition_bill(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2026-08',
      0.05
    );

  if v_preview.planned_lesson_count <> 22
     or v_preview.planned_lesson_hours <> 44
     or v_preview.planned_lesson_fee_jpy <> 374000 then
    raise exception 'R1C_B_SUN_PREVIEW_MISMATCH: %', to_jsonb(v_preview);
  end if;

  with candidate_rows as (
    select candidate.planned_lesson_id, candidate.duration_hours, candidate.lesson_fee
    from public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08',
      false
    ) candidate
    union all
    select candidate.planned_lesson_id, candidate.duration_hours, candidate.lesson_fee
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08',
      false
    ) candidate
  )
  select
    count(*)::integer,
    sum(duration_hours),
    sum(lesson_fee),
    array_agg(planned_lesson_id order by planned_lesson_id)
  into
    v_candidate_count,
    v_candidate_hours,
    v_candidate_fee,
    v_candidate_ids
  from candidate_rows;

  select array_agg(item.lesson_record_id order by item.lesson_record_id)
    into v_manifest_ids
    from public.school_business_entity_migration_items item
   where item.batch_id = 'c1000000-0000-4000-8000-202607279999';

  if v_candidate_count <> 52
     or v_candidate_hours <> 109
     or v_candidate_fee <> 1024000
     or v_candidate_ids is distinct from v_manifest_ids then
    raise exception 'R1C_B_FIXED_52_CANDIDATE_SET_MISMATCH';
  end if;

  if (
    select count(*)
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08',
      true
    ) candidate
    where candidate.planned_lesson_id in (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
      and candidate.candidate_status = 'excluded'
      and candidate.exclusion_reason = 'already_canonical_charged'
      and candidate.has_normalized_bill_relation
      and candidate.has_bill_snapshot_evidence
      and not candidate.bill_evidence_conflict
      and 'canonical_charge' = any(candidate.relation_roles)
      and '2a9f1c25-a060-461e-ae10-b02295dec381'::uuid = any(candidate.associated_bill_ids)
  ) <> 2 then
    raise exception 'R1C_B_CROSS_MONTH_EXCLUSION_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08',
      true
    ) candidate
    join public.school_lesson_records lesson
      on lesson.id = candidate.planned_lesson_id
    where candidate.planned_lesson_id in (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
      and candidate.complete_row_hash <> md5(to_jsonb(lesson)::text)
  ) then
    raise exception 'R1C_B_CROSS_MONTH_ROW_HASH_MISMATCH';
  end if;

  with historical_scopes as (
    select distinct lesson.student_id, lesson.business_entity_id, lesson.year_month
    from public.school_student_tuition_bill_lessons relation
    join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
  ),
  candidate_rows as (
    select candidate.planned_lesson_id
    from historical_scopes scope
    cross join lateral public.school_list_student_tuition_candidates(
      scope.student_id,
      scope.business_entity_id,
      scope.year_month,
      false
    ) candidate
  )
  select count(*)::integer
    into v_historical_candidate_count
    from candidate_rows candidate
    join public.school_student_tuition_bill_lessons relation
      on relation.planned_lesson_id = candidate.planned_lesson_id;

  if v_historical_candidate_count <> 0 then
    raise exception 'R1C_B_HISTORICAL_RELATION_REOPENED: %', v_historical_candidate_count;
  end if;

  with historical_scopes as (
    select distinct lesson.student_id, lesson.business_entity_id, lesson.year_month
    from public.school_student_tuition_bill_lessons relation
    join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
  ),
  audit_rows as (
    select candidate.*
    from historical_scopes scope
    cross join lateral public.school_list_student_tuition_candidates(
      scope.student_id,
      scope.business_entity_id,
      scope.year_month,
      true
    ) candidate
  )
  select
    count(*) filter (
      where relation.relation_role = 'canonical_charge'
        and audit.candidate_status = 'excluded'
        and 'canonical_charge' = any(audit.relation_roles)
    )::integer,
    count(*) filter (
      where relation.relation_role = 'incident_duplicate'
        and audit.candidate_status = 'excluded'
        and 'incident_duplicate' = any(audit.relation_roles)
    )::integer,
    count(*) filter (
      where relation.relation_role = 'legacy_cancelled'
        and audit.candidate_status = 'excluded'
        and 'legacy_cancelled' = any(audit.relation_roles)
    )::integer
  into v_canonical_excluded, v_incident_excluded, v_legacy_excluded
  from public.school_student_tuition_bill_lessons relation
  join audit_rows audit on audit.planned_lesson_id = relation.planned_lesson_id;

  if v_canonical_excluded <> 85
     or v_incident_excluded <> 24
     or v_legacy_excluded <> 12 then
    raise exception 'R1C_B_RELATION_ROLE_EXCLUSION_MISMATCH: %/%/%',
      v_canonical_excluded, v_incident_excluded, v_legacy_excluded;
  end if;

  -- Synthetic conflict and mutable-state cases exercise the deterministic
  -- classifier without writing temporary or real business rows.
  if public.school_classify_student_tuition_candidate(
       true, true, array['canonical_charge'], false, true,
       'planned', 'planned', null, true, true
     ) <> 'bill_snapshot_conflict'
     or public.school_classify_student_tuition_candidate(
       true, false, '{}'::text[], true, false,
       'planned', 'planned', null, true, true
     ) <> 'bill_snapshot_conflict'
     or public.school_classify_student_tuition_candidate(
       true, false, '{}'::text[], false, false,
       'actual', 'completed', null, true, true
     ) <> 'voided_or_inactive'
     or public.school_classify_student_tuition_candidate(
       true, false, '{}'::text[], false, false,
       'planned', 'planned', now(), true, true
     ) <> 'voided_or_inactive'
     or public.school_classify_student_tuition_candidate(
       true, false, '{}'::text[], false, false,
       'planned', 'planned', null, false, true
     ) <> 'non_billable'
     or public.school_classify_student_tuition_candidate(
       true, false, '{}'::text[], false, false,
       'planned', 'planned', null, true, false
     ) <> 'invalid_or_incomplete_data'
     or public.school_classify_student_tuition_candidate(
       false, false, '{}'::text[], false, false,
       'planned', 'planned', null, true, true
     ) <> 'scope_mismatch' then
    raise exception 'R1C_B_CLASSIFIER_NEGATIVE_CASE_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '886a8f7c-0fea-45ac-97d2-15c976ede996',
      '2026-08',
      false
    )
  ) or exists (
    select 1
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-09',
      false
    )
  ) then
    raise exception 'R1C_B_SCOPE_ISOLATION_MISMATCH';
  end if;

  -- The current incident-quarantined and legacy-cancelled incomes remain
  -- excluded because classification depends on bill evidence, not income state.
  if (
    select count(distinct relation.tuition_bill_id)
    from public.school_student_tuition_bill_lessons relation
    join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
    join public.school_income_records income on income.id = bill.income_record_id
    where income.status in ('incident_quarantined', 'cancelled', 'rejected')
  ) <> 2 then
    raise exception 'R1C_B_NON_ACTIVE_INCOME_EVIDENCE_BASELINE_MISMATCH';
  end if;

  raise notice 'R1C_B_ROLLBACK_TESTS_OK: previews 30/65/650000 and 22/44/374000; exact 52 manifest; 85/24/12 historical roles excluded; negative classifier and scope tests passed.';
end;
$$;

rollback;
