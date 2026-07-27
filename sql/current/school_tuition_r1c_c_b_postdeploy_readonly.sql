-- School V2 tuition P0 R1C-C-B: post-deployment read-only acceptance.
-- SELECT/DO checks only. No DDL, DML, or write RPC calls.

\set ON_ERROR_STOP on

do $$
declare
  v_candidate_ids uuid[];
  v_manifest_ids uuid[];
  v_august_candidate_ids uuid[];
  v_r1c_a_manifest_ids uuid[];
begin
  if (select count(*) from public.school_business_entity_migration_batches
      where id = 'c1000000-0000-4000-8000-202607289999'
        and migration_key = 'r1c-c-b:2026-09-11:zhang-planned-business-entity:personal-to-aosora'
        and execution_status = 'executed'
        and expected_lesson_count = 66
        and expected_duration_hours = 145
        and expected_lesson_fee_jpy = 1450000
        and manifest_hash = 'ee7c476c9c56c926eda083008197450a') <> 1 then
    raise exception 'R1C_C_B_POSTDEPLOY_BATCH_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id = 'c1000000-0000-4000-8000-202607289999'
        and execution_status = 'executed') <> 66 then
    raise exception 'R1C_C_B_POSTDEPLOY_ITEM_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    left join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
      and (
        lesson.id is null
        or lesson.business_entity_id <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        or md5(item.original_row_snapshot::text) <> item.before_hash
        or md5(item.after_row_snapshot::text) <> item.after_hash
        or to_jsonb(lesson) is distinct from item.after_row_snapshot
        or (item.original_row_snapshot - 'business_entity_id')
           is distinct from (item.after_row_snapshot - 'business_entity_id')
        or item.original_row_snapshot ->> 'business_entity_id'
           <> '886a8f7c-0fea-45ac-97d2-15c976ede996'
        or item.after_row_snapshot ->> 'business_entity_id'
           <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        or item.original_updated_at is distinct from lesson.updated_at
      )
  ) then
    raise exception 'R1C_C_B_POSTDEPLOY_ROW_OR_AUDIT_HASH_MISMATCH';
  end if;

  if (select md5(string_agg(item.before_hash, '' order by item.lesson_record_id::text))
      from public.school_business_entity_migration_items item
      where item.batch_id = 'c1000000-0000-4000-8000-202607289999')
     <> 'ee7c476c9c56c926eda083008197450a' then
    raise exception 'R1C_C_B_POSTDEPLOY_MANIFEST_HASH_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_student_tuition_bill_lessons relation
    join public.school_business_entity_migration_items item
      on item.lesson_record_id = relation.planned_lesson_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
  ) or exists (
    select 1 from public.school_student_tuition_bills bill
    join public.school_business_entity_migration_items item
      on (bill.source_snapshot -> 'planned_lesson_ids') ? item.lesson_record_id::text
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
  ) or exists (
    select 1 from public.school_lesson_records actual
    join public.school_business_entity_migration_items item
      on item.lesson_record_id = actual.planned_lesson_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
      and actual.lesson_type = 'actual' and actual.voided_at is null
  ) then
    raise exception 'R1C_C_B_POSTDEPLOY_TARGET_HAS_BILL_OR_ACTUAL';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details detail
    join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
    where wage.status <> 'void' and (
      exists (
        select 1 from public.school_business_entity_migration_items item
        where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
          and item.lesson_record_id = detail.lesson_record_id
      ) or exists (
        select 1 from public.school_lesson_records actual
        join public.school_business_entity_migration_items item
          on item.lesson_record_id = actual.planned_lesson_id
        where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
          and actual.id = detail.lesson_record_id
      )
    )
  ) or exists (
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
      and settlement.business_entity_id in (
        '886a8f7c-0fea-45ac-97d2-15c976ede996',
        '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      )
      and settlement.year_month in ('2026-09', '2026-10', '2026-11')
      and settlement.settlement_status = 'locked'
  ) then
    raise exception 'R1C_C_B_POSTDEPLOY_TARGET_HAS_WAGE_OR_SETTLEMENT';
  end if;

  if exists (
    select 1 from public.school_income_records income
    join public.school_business_entity_migration_items item
      on to_jsonb(income)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
  ) or exists (
    select 1 from public.school_personal_cash_income_linkage_events linkage
    join public.school_business_entity_migration_items item
      on to_jsonb(linkage)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
  ) or exists (
    select 1 from public.school_account_transactions transaction_row
    join public.school_business_entity_migration_items item
      on to_jsonb(transaction_row)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
  ) then
    raise exception 'R1C_C_B_POSTDEPLOY_TARGET_HAS_FINANCIAL_REFERENCE';
  end if;

  with candidates as (
    select candidate.planned_lesson_id
    from (values ('2026-09'), ('2026-10'), ('2026-11')) month_scope(year_month)
    cross join lateral public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      month_scope.year_month, false
    ) candidate
  )
  select array_agg(planned_lesson_id order by planned_lesson_id)
  into v_candidate_ids
  from candidates;

  select array_agg(item.lesson_record_id order by item.lesson_record_id)
  into v_manifest_ids
  from public.school_business_entity_migration_items item
  where item.batch_id = 'c1000000-0000-4000-8000-202607289999';

  if v_candidate_ids is distinct from v_manifest_ids then
    raise exception 'R1C_C_B_POSTDEPLOY_CANDIDATE_SET_MISMATCH';
  end if;

  with august_candidates as (
    select candidate.planned_lesson_id
    from public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466', '2026-08', false
    ) candidate
    union all
    select candidate.planned_lesson_id
    from public.school_list_student_tuition_candidates(
      'b17abc58-2f64-4bad-bf20-c9643ead60bc',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466', '2026-08', false
    ) candidate
  )
  select array_agg(planned_lesson_id order by planned_lesson_id)
  into v_august_candidate_ids
  from august_candidates;

  select array_agg(item.lesson_record_id order by item.lesson_record_id)
  into v_r1c_a_manifest_ids
  from public.school_business_entity_migration_items item
  where item.batch_id = 'c1000000-0000-4000-8000-202607279999';

  if v_august_candidate_ids is distinct from v_r1c_a_manifest_ids then
    raise exception 'R1C_C_B_POSTDEPLOY_AUGUST_REGRESSION';
  end if;

  if exists (
    with li_fixed(lesson_record_id, expected_row_hash) as (
      values
        ('f256bca9-fac5-4909-b113-8077efd27d65'::uuid, '39a3d5ccc1755499b54595b303c49cc5'),
        ('a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid, 'f7b3636134ebd23191c5b6ea37c0d204'),
        ('265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid, '6620ad1a8085077dbb8e4d4317f0af8f'),
        ('e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid, 'b707e69e1ece74e9b6edf2e44483f512'),
        ('552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid, '82a2d4d62f96c07a3bb65a2c2e8b92a1'),
        ('b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid, '3ac247e72ba1e8e55484d5bb96052a9c'),
        ('ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid, '0c32bffa1f171517a1c034b0cb6d1195'),
        ('39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid, 'c46cc189dac5ac53ba455838af5859e0'),
        ('f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid, '4fff65ea2500ba5613d3927f2cd8042c'),
        ('c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid, '91679ca8877c299bf02faaf56fdfee8c'),
        ('dc06b98c-360f-4661-a294-52ecb82830a7'::uuid, '04099067c0430d749487c2170b1ec5d8')
    )
    select 1 from li_fixed li
    left join public.school_lesson_records lesson on lesson.id = li.lesson_record_id
    where lesson.id is null
       or md5(to_jsonb(lesson)::text) <> li.expected_row_hash
       or exists (
         select 1 from public.school_business_entity_migration_items item
         where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
           and item.lesson_record_id = li.lesson_record_id
       )
  ) then
    raise exception 'R1C_C_B_POSTDEPLOY_LI_FIXED_ROW_CHANGED';
  end if;

  if (select count(*)
      from (values ('2026-10'), ('2026-11')) month_scope(year_month)
      cross join lateral public.school_list_student_tuition_candidates(
        'a7b163a0-201e-4867-9b94-372343356a80',
        '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
        month_scope.year_month, true
      ) candidate
      where candidate.candidate_status = 'excluded'
        and candidate.exclusion_reason = 'scope_mismatch') <> 11 then
    raise exception 'R1C_C_B_POSTDEPLOY_LI_CANDIDATE_EXCLUSION_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3
     or (select count(*) from pg_trigger
         where tgrelid = 'public.school_lesson_records'::regclass
           and tgname = 'trg_school_lesson_records_updated_at'
           and tgenabled = 'O' and not tgisinternal) <> 1 then
    raise exception 'R1C_C_B_POSTDEPLOY_TRIGGER_OR_GATE_CHANGED';
  end if;

  raise notice 'R1C_C_B_POSTDEPLOY_OK: fixed 66 migrated; exact candidate set 66; August fixed 52 unchanged; Li fixed 11 unchanged/excluded.';
end;
$$;

select
  item.target_year_month as year_month,
  count(*) as migrated_lesson_count,
  sum((item.original_row_snapshot ->> 'duration_hours')::numeric) as duration_hours,
  sum((item.original_row_snapshot ->> 'lesson_fee')::numeric) as lesson_fee_jpy,
  count(*) filter (where item.original_updated_at = lesson.updated_at) as updated_at_unchanged,
  md5(string_agg(md5((item.original_row_snapshot - 'business_entity_id')::text), '' order by item.lesson_record_id::text)) as immutable_before_hash,
  md5(string_agg(md5((item.after_row_snapshot - 'business_entity_id')::text), '' order by item.lesson_record_id::text)) as immutable_after_hash
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
group by item.target_year_month
order by item.target_year_month;

select
  item.item_order,
  item.lesson_record_id,
  item.target_year_month,
  item.before_hash,
  item.after_hash,
  item.original_updated_at,
  item.executed_at as migration_audit_executed_at
from public.school_business_entity_migration_items item
where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
order by item.item_order;

select
  (select count(*) from public.school_student_tuition_bills) as tuition_bill_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_student_tuition_bills row_value) as tuition_bill_hash,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_income_records row_value) as income_hash,
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_student_tuition_billing_identities row_value) as identity_hash,
  (select count(*) from public.school_student_tuition_bill_lessons) as bill_lesson_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_student_tuition_bill_lessons row_value) as bill_lesson_hash;

select
  (select count(*) from public.school_personal_cash_income_linkage_events) as cash_linkage_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_personal_cash_income_linkage_events row_value) as cash_linkage_hash,
  (select count(*) from public.school_account_transactions) as account_transaction_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_account_transactions row_value) as account_transaction_hash,
  (select count(*) from public.school_lesson_records where lesson_type = 'actual') as actual_lesson_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_lesson_records row_value where row_value.lesson_type = 'actual') as actual_lesson_hash;

select
  (select count(*) from public.school_student_monthly_settlements) as settlement_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_student_monthly_settlements row_value) as settlement_hash,
  (select count(*) from public.school_teacher_wage_locks) as wage_lock_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_teacher_wage_locks row_value) as wage_lock_hash,
  (select count(*) from public.school_teacher_wage_lock_details) as wage_detail_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), '')) from public.school_teacher_wage_lock_details row_value) as wage_detail_hash;

select
  count(*) as li_fixed_count,
  md5(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text)) as li_fixed_full_row_hash
from public.school_lesson_records lesson
where lesson.id in (
  'f256bca9-fac5-4909-b113-8077efd27d65', 'a722a49e-dbe5-447d-8068-fd5fb743f6ab',
  '265f4d3d-2372-42e3-aec3-b963bbdddf95', 'e890424d-407d-4fc2-b8ad-84745b242cdd',
  '552c54e3-2d0c-4607-962d-aad39dfff7f7', 'b186fa1c-a56b-4ed7-b566-178a5708ae96',
  'ac16b068-a58b-4ca5-be95-7c57c3f1b82b', '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7',
  'f759623b-ce28-4c5f-8556-95c4381b6b1b', 'c582a187-32f6-4a24-bb7b-d590b25c1854',
  'dc06b98c-360f-4661-a294-52ecb82830a7'
);

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;
