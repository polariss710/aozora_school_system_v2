-- School V2 tuition P0 R1C-B post-deployment read-only acceptance.
-- SELECT/DO checks only. No DDL, DML, or business RPC writes.

\set ON_ERROR_STOP on

do $$
declare
  v_preview record;
  v_candidate_ids uuid[];
  v_manifest_ids uuid[];
  v_role_counts integer[];
begin
  if to_regprocedure(
       'public.school_classify_student_tuition_candidate(boolean,boolean,text[],boolean,boolean,text,text,timestamp with time zone,boolean,boolean)'
     ) is null
     or to_regprocedure(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'
     ) is null
     or to_regprocedure(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'
     ) is null then
    raise exception 'R1C_B_FUNCTION_SIGNATURE_MISSING';
  end if;

  if has_function_privilege(
       'anon',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'execute'
     ) then
    raise exception 'R1C_B_AUDIT_FUNCTION_PRIVILEGE_MISMATCH';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.school_preview_student_tuition_bill(uuid,text,numeric)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'public.school_preview_student_tuition_bill(uuid,text,numeric)',
       'execute'
     ) then
    raise exception 'R1C_B_PREVIEW_FUNCTION_PRIVILEGE_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bills bill
    where bill.source_snapshot is null
       or not (bill.source_snapshot ? 'planned_lesson_ids')
       or jsonb_typeof(bill.source_snapshot -> 'planned_lesson_ids') <> 'array'
  ) or exists (
    select 1
    from public.school_student_tuition_bills bill
    cross join lateral jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    where snapshot_lesson.lesson_id_text
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception 'R1C_B_SNAPSHOT_FORMAT_MISMATCH';
  end if;

  if (
    with snapshot_rows as (
      select
        bill.id as bill_id,
        snapshot_lesson.lesson_id_text::uuid as planned_lesson_id,
        snapshot_lesson.line_no::integer as line_no
      from public.school_student_tuition_bills bill
      cross join lateral jsonb_array_elements_text(
        bill.source_snapshot -> 'planned_lesson_ids'
      ) with ordinality snapshot_lesson(lesson_id_text, line_no)
    )
    select count(*)
    from (
      (
        select snapshot.bill_id, snapshot.planned_lesson_id, snapshot.line_no
        from snapshot_rows snapshot
        except
        select relation.tuition_bill_id, relation.planned_lesson_id, relation.line_no
        from public.school_student_tuition_bill_lessons relation
      )

      union all

      (
        select relation.tuition_bill_id, relation.planned_lesson_id, relation.line_no
        from public.school_student_tuition_bill_lessons relation
        except
        select snapshot.bill_id, snapshot.planned_lesson_id, snapshot.line_no
        from snapshot_rows snapshot
      )
    ) mismatch
  ) <> 0 then
    raise exception 'R1C_B_NORMALIZED_SNAPSHOT_COVERAGE_MISMATCH';
  end if;

  select *
    into v_preview
    from public.school_preview_student_tuition_bill(
      '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-08', 0.05
    );
  if v_preview.planned_lesson_count <> 30
     or v_preview.planned_lesson_hours <> 65
     or v_preview.planned_lesson_fee_jpy <> 650000 then
    raise exception 'R1C_B_ZHANG_POSTDEPLOY_PREVIEW_MISMATCH';
  end if;

  select *
    into v_preview
    from public.school_preview_student_tuition_bill(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc', '2026-08', 0.05
    );
  if v_preview.planned_lesson_count <> 22
     or v_preview.planned_lesson_hours <> 44
     or v_preview.planned_lesson_fee_jpy <> 374000 then
    raise exception 'R1C_B_SUN_POSTDEPLOY_PREVIEW_MISMATCH';
  end if;

  with candidates as (
    select candidate.planned_lesson_id
    from public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08', false
    ) candidate
    union all
    select candidate.planned_lesson_id
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08', false
    ) candidate
  )
  select array_agg(planned_lesson_id order by planned_lesson_id)
    into v_candidate_ids
    from candidates;

  select array_agg(item.lesson_record_id order by item.lesson_record_id)
    into v_manifest_ids
    from public.school_business_entity_migration_items item
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999';

  if v_candidate_ids is distinct from v_manifest_ids then
    raise exception 'R1C_B_POSTDEPLOY_FIXED_52_SET_MISMATCH';
  end if;

  if (
    select count(*)
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-08', true
    ) candidate
    where candidate.planned_lesson_id in (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
      and candidate.candidate_status = 'excluded'
      and candidate.exclusion_reason = 'already_canonical_charged'
      and '2a9f1c25-a060-461e-ae10-b02295dec381'::uuid = any(candidate.associated_bill_ids)
  ) <> 2 then
    raise exception 'R1C_B_POSTDEPLOY_CROSS_MONTH_EXCLUSION_MISMATCH';
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
      scope.student_id, scope.business_entity_id, scope.year_month, true
    ) candidate
  )
  select array[
    count(*) filter (
      where relation.relation_role = 'canonical_charge'
        and audit.candidate_status = 'excluded'
    )::integer,
    count(*) filter (
      where relation.relation_role = 'incident_duplicate'
        and audit.candidate_status = 'excluded'
    )::integer,
    count(*) filter (
      where relation.relation_role = 'legacy_cancelled'
        and audit.candidate_status = 'excluded'
    )::integer
  ]
  into v_role_counts
  from public.school_student_tuition_bill_lessons relation
  join audit_rows audit on audit.planned_lesson_id = relation.planned_lesson_id;

  if v_role_counts is distinct from array[85, 24, 12] then
    raise exception 'R1C_B_POSTDEPLOY_ROLE_EXCLUSION_MISMATCH: %', v_role_counts;
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'R1C_B_POSTDEPLOY_R0_GATE_MISMATCH';
  end if;

  raise notice 'R1C_B_POSTDEPLOY_OK: exact 52 candidate IDs; previews 30/65/650000 and 22/44/374000; 85/24/12 historical roles excluded.';
end;
$$;

-- Candidate-only summaries and fixed UUID manifests used by the validation UI.
with target_students(student_id, student_name, business_entity_id) as (
  values
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '张倬闻'::text,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid),
    ('b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '孙陈锋'::text,
     '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid)
)
select
  target.student_name,
  count(*)::integer as candidate_count,
  sum(candidate.duration_hours) as candidate_hours,
  sum(candidate.lesson_fee) as candidate_fee_jpy,
  array_agg(candidate.planned_lesson_id order by candidate.lesson_date, candidate.planned_lesson_id) as candidate_ids
from target_students target
cross join lateral public.school_list_student_tuition_candidates(
  target.student_id, target.business_entity_id, '2026-08', false
) candidate
group by target.student_name
order by target.student_name;

-- Structured disclosure for the two cross-month canonical exclusions.
select
  candidate.planned_lesson_id,
  candidate.lesson_date,
  candidate.complete_row_hash,
  candidate.candidate_status,
  candidate.exclusion_reason,
  candidate.relation_roles,
  candidate.associated_bill_ids,
  candidate.associated_billing_identity_ids,
  candidate.has_bill_snapshot_evidence,
  candidate.snapshot_bill_ids,
  candidate.bill_evidence_conflict
from public.school_list_student_tuition_candidates(
  'b17abc58-2f64-4bad-bf20-c9643ead60bc',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  '2026-08', true
) candidate
where candidate.planned_lesson_id in (
  '8b737b58-cd14-42c5-afd2-34730dcef963',
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
)
order by candidate.lesson_date;

-- September and later are inventory only; no migration or generation occurs.
with future_scopes as (
  select distinct lesson.student_id, student.business_entity_id, lesson.year_month
  from public.school_lesson_records lesson
  join public.school_students student on student.id = lesson.student_id
  where lesson.app_type = 'school'
    and lesson.year_month >= '2026-09'
),
future_audit as (
  select scope.year_month as audit_month, candidate.*
  from future_scopes scope
  cross join lateral public.school_list_student_tuition_candidates(
    scope.student_id, scope.business_entity_id, scope.year_month, true
  ) candidate
)
select
  audit.audit_month as year_month,
  coalesce(student.display_name, student.name) as student_name,
  count(*) filter (where audit.candidate_status = 'candidate')::integer as candidate_count,
  coalesce(sum(audit.duration_hours) filter (where audit.candidate_status = 'candidate'), 0) as candidate_hours,
  coalesce(sum(audit.lesson_fee) filter (where audit.candidate_status = 'candidate'), 0) as candidate_fee_jpy,
  count(*) filter (where audit.candidate_status = 'excluded')::integer as excluded_count,
  array_agg(distinct audit.exclusion_reason order by audit.exclusion_reason)
    filter (where audit.exclusion_reason is not null) as exclusion_reasons
from future_audit audit
join public.school_students student on student.id = audit.student_id
group by audit.audit_month, student.display_name, student.name
order by audit.audit_month, student_name;

-- School business baselines. Compare with the captured pre-deployment output.
select
  (select count(*) from public.school_student_tuition_bills) as bill_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bills t) as bill_hash,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_income_records t) as income_hash,
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_billing_identities t) as identity_hash,
  (select count(*) from public.school_student_tuition_bill_lessons) as relation_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bill_lessons t) as relation_hash;

select
  (select count(*) from public.school_personal_cash_income_linkage_events) as linkage_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_personal_cash_income_linkage_events t) as linkage_hash,
  (select count(*) from public.school_account_transactions) as account_transaction_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_account_transactions t) as account_transaction_hash,
  (select count(*) from public.school_lesson_records where lesson_type = 'actual') as actual_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t where lesson_type = 'actual') as actual_hash;

select
  (select count(*) from public.school_student_monthly_settlements) as settlement_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_monthly_settlements t) as settlement_hash,
  (select count(*) from public.school_teacher_wage_locks) as wage_lock_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_locks t) as wage_lock_hash,
  (select count(*) from public.school_teacher_wage_lock_details) as wage_detail_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_lock_details t) as wage_detail_hash;

select
  (select count(*) from public.school_business_entity_migration_batches) as migration_batch_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_batches t) as migration_batch_hash,
  (select count(*) from public.school_business_entity_migration_items) as migration_item_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_items t) as migration_item_hash,
  (select md5(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text))
     from public.school_lesson_records lesson
     join public.school_business_entity_migration_items item on item.lesson_record_id = lesson.id
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999') as r1c_a_52_current_hash;

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;
