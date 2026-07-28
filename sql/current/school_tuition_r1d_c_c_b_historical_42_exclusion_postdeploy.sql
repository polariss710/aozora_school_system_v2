-- R1D-C-C-B postdeploy read-only verification.
-- Proves the immutable fixed 42 evidence exists while candidate and all prior
-- School/Cash-facing business facts remain unchanged.

\set ON_ERROR_STOP on
\pset pager off

begin isolation level repeatable read read only;

select transaction_timestamp() as r1d_c_c_b_postdeploy_snapshot_at;

do $postdeploy$
declare
  v record;
  v_current_candidates bigint;
  v_new_candidates bigint;
begin
  if to_regclass('public.school_student_tuition_historical_lesson_exclusions') is null
     or to_regprocedure('public.school_r1d_c_c_b_fixed_42_manifest()') is null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_insert()') is null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_immutable()') is null then
    raise exception 'R1D_C_C_B_POSTDEPLOY_OBJECT_MISSING';
  end if;

  select
    count(*) as row_count,
    count(distinct exclusion.planned_lesson_id) as distinct_lessons,
    count(distinct exclusion.evidence_recorded_at) as recording_times,
    md5(string_agg(exclusion.lesson_old31_hash,'' order by exclusion.planned_lesson_id::text))
      as old31_aggregate_hash,
    md5(string_agg(exclusion.evidence_hash,'' order by exclusion.planned_lesson_id::text))
      as evidence_aggregate_hash,
    count(*) filter (where manifest.planned_lesson_id is null) as outside_manifest,
    count(*) filter (
      where exclusion.student_id_snapshot is distinct from manifest.expected_student_id
         or exclusion.business_entity_id_snapshot is distinct from manifest.expected_business_entity_id
         or exclusion.settlement_month_snapshot is distinct from manifest.expected_year_month
         or exclusion.lesson_old31_hash is distinct from manifest.expected_old31_hash
         or exclusion.linked_actual_lesson_id is distinct from manifest.expected_actual_lesson_id
         or exclusion.locked_settlement_id is distinct from manifest.expected_settlement_id
         or exclusion.received_tuition_income_id is distinct from manifest.expected_income_id
         or exclusion.school_account_transaction_id is distinct from manifest.expected_account_transaction_id
         or exclusion.evidence_hash is distinct from manifest.expected_evidence_hash
         or exclusion.exclusion_reason_code is distinct from 'historical_monthly_tuition_paid'
         or exclusion.evidence_class_code is distinct from 'business_approved_reviewable_medium'
         or exclusion.approval_source_code is distinct from 'approved_r1d_c_c_a_manifest'
         or exclusion.approval_report_version is distinct from
              'school-v2-r1d-c-c-a-billing-fact-audit-report-20260728-v1'
         or exclusion.manifest_version is distinct from
              'school-v2-r1d-c-c-a-current-only-42-20260728-v1'
    ) as row_drift
  into v
  from public.school_student_tuition_historical_lesson_exclusions exclusion
  left join public.school_r1d_c_c_b_fixed_42_manifest() manifest
    on manifest.planned_lesson_id=exclusion.planned_lesson_id;

  if v.row_count <> 42
     or v.distinct_lessons <> 42
     or v.recording_times <> 1
     or v.old31_aggregate_hash <> 'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or v.evidence_aggregate_hash <> 'dc2546bff536942650db58e437d37f0e'
     or v.outside_manifest <> 0
     or v.row_drift <> 0 then
    raise exception 'R1D_C_C_B_POSTDEPLOY_EVIDENCE_FAILED: %',to_jsonb(v);
  end if;

  if (select count(*) from public.school_r1d_c_c_b_fixed_42_manifest()) <> 42
     or (select count(distinct planned_lesson_id)
         from public.school_r1d_c_c_b_fixed_42_manifest()) <> 42
     or (select count(*)
         from public.school_r1d_c_c_b_fixed_42_manifest() manifest
         join public.school_lesson_records pending
           on pending.id=manifest.planned_lesson_id
          and pending.status='pending_makeup') <> 0
     or (select count(*) from public.school_lesson_records pending
         where pending.lesson_type='planned'
           and pending.status='pending_makeup'
           and pending.student_id in (
             '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
             'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
           )
           and pending.year_month in ('2026-05','2026-06')) <> 6 then
    raise exception 'R1D_C_C_B_POSTDEPLOY_PENDING_SCOPE_FAILED';
  end if;

  if (select count(*) from information_schema.columns
      where table_schema='public'
        and table_name='school_student_tuition_historical_lesson_exclusions') <> 20
     or (select count(*) from pg_trigger
         where tgrelid='public.school_student_tuition_historical_lesson_exclusions'::regclass
           and not tgisinternal and tgenabled='O') <> 3
     or not has_table_privilege(
          'service_role','public.school_student_tuition_historical_lesson_exclusions','SELECT')
     or has_table_privilege(
          'service_role','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     or has_table_privilege(
          'service_role','public.school_student_tuition_historical_lesson_exclusions','UPDATE')
     or has_table_privilege(
          'service_role','public.school_student_tuition_historical_lesson_exclusions','DELETE')
     or has_table_privilege(
          'anon','public.school_student_tuition_historical_lesson_exclusions','SELECT')
     or has_table_privilege(
          'authenticated','public.school_student_tuition_historical_lesson_exclusions','SELECT')
     or has_table_privilege(
          'anon','public.school_student_tuition_historical_lesson_exclusions','INSERT')
     or has_table_privilege(
          'authenticated','public.school_student_tuition_historical_lesson_exclusions','INSERT') then
    raise exception 'R1D_C_C_B_POSTDEPLOY_SCHEMA_OR_PRIVILEGE_FAILED';
  end if;

  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1d9149f6e3ff02305d0963f81af9f0b9'
     or position(
          'school_student_tuition_historical_lesson_exclusions' in
          pg_get_functiondef(
            'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
          )
        ) <> 0 then
    raise exception 'R1D_C_C_B_POSTDEPLOY_CANDIDATE_FUNCTION_CHANGED';
  end if;

  select count(*) into v_current_candidates
  from (
    select distinct candidate.planned_lesson_id
    from public.school_students student
    join (
      select distinct student_id,year_month
      from public.school_lesson_records
      where app_type='school' and lesson_type='planned'
    ) scope on scope.student_id=student.id
    cross join lateral public.school_list_student_tuition_candidates(
      student.id,student.business_entity_id,scope.year_month,false
    ) candidate
    where candidate.candidate_status='candidate'
  ) current_rows;

  select count(*) into v_new_candidates
  from (
    select distinct candidate.planned_lesson_id
    from public.school_lesson_records lesson
    cross join lateral public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,lesson.billing_month,false
    ) candidate
    where lesson.app_type='school'
      and lesson.lesson_type='planned'
      and lesson.billing_month is not null
      and lesson.billing_week_start_date is not null
      and lesson.student_settlement_month=lesson.billing_month
      and lesson.billing_month_source is not null
      and lesson.billing_month_decided_at is not null
      and public.school_is_valid_tuition_billing_period(
        lesson.billing_month,lesson.billing_week_start_date
      )
      and candidate.planned_lesson_id=lesson.id
      and candidate.candidate_status='candidate'
  ) new_rows;

  if v_current_candidates <> 160 or v_new_candidates <> 118 then
    raise exception 'R1D_C_C_B_POSTDEPLOY_CANDIDATE_SET_CHANGED: current %, new %',
      v_current_candidates,v_new_candidates;
  end if;

  if (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type='planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type='actual') <> 229
     or (select count(*) from public.school_lesson_records where billing_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_week_start_date is not null) <> 118
     or (select count(*) from public.school_lesson_records where student_settlement_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_source is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_decided_at is not null) <> 118
     or (select count(*) from public.school_lesson_records where scheduled_lesson_date is not null) <> 0
     or (select count(*) from public.school_student_tuition_bills) <> 9
     or (select count(*) from public.school_income_records) <> 42
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121
     or (select count(*) from public.school_business_entity_migration_batches) <> 2
     or (select count(*) from public.school_business_entity_migration_items) <> 118
     or (select count(*) from public.school_student_monthly_settlements) <> 15
     or (select count(*) from public.school_student_settlement_adjustments) <> 5
     or (select count(*) from public.school_student_payments) <> 0
     or (select count(*) from public.school_account_transactions) <> 185
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 35
     or (select count(*) from public.school_teacher_wage_locks) <> 95
     or (select count(*) from public.school_teacher_wage_lock_details) <> 556
     or (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_C_C_B_POSTDEPLOY_BUSINESS_COUNT_CHANGED';
  end if;

  if (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t) <> 'c4f892d857fe674e4060f80d6af56b42'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t) <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t) <> '2a4897b752f272b1f192045418b4940c'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t) <> '4d91a5a1074f90389822fc367a7e5467'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t) <> '09dfee7d8833e09384fb41a84f2959e0'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t) <> '7925cf3018bd0e669cd29710f6593238'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_account_transactions t) <> '8f4f6c4365035f6c36bac59ba986b28b'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_teacher_wage_locks t) <> '7bbe108d3ac73d4f21530793bf141bc6'
     or (select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_teacher_wage_lock_details t) <> '6204dc666b3b8e0f64fac901ecf0686a' then
    raise exception 'R1D_C_C_B_POSTDEPLOY_BUSINESS_HASH_CHANGED';
  end if;

  if not exists (select 1 from public.school_feature_gates
                 where feature_key='student_tuition_preview' and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                   where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                   where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D_C_C_B_POSTDEPLOY_R0_CHANGED';
  end if;
end;
$postdeploy$;

select exclusion.student_id_snapshot,
       student.display_name,
       exclusion.settlement_month_snapshot,
       count(*) as exclusion_rows,
       sum(lesson.duration_hours) as duration_hours,
       sum(lesson.lesson_fee) as lesson_fee_jpy,
       min(exclusion.evidence_recorded_at) as evidence_recorded_at,
       max(exclusion.evidence_recorded_at) as evidence_recorded_at_max
from public.school_student_tuition_historical_lesson_exclusions exclusion
join public.school_students student on student.id=exclusion.student_id_snapshot
join public.school_lesson_records lesson on lesson.id=exclusion.planned_lesson_id
group by exclusion.student_id_snapshot,student.display_name,
         exclusion.settlement_month_snapshot
order by exclusion.settlement_month_snapshot,student.display_name;

select trigger_name,event_manipulation,action_timing,action_orientation
from information_schema.triggers
where event_object_schema='public'
  and event_object_table='school_student_tuition_historical_lesson_exclusions'
order by trigger_name,event_manipulation;

select grantee,privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name='school_student_tuition_historical_lesson_exclusions'
  and grantee in ('anon','authenticated','service_role')
order by grantee,privilege_type;

select feature_key,state
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
order by feature_key;

commit;
