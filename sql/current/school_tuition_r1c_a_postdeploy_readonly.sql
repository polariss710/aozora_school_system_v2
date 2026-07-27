-- School V2 tuition P0 R1C-A: post-deployment read-only acceptance.
-- No DDL/DML and no RPC calls.

\set ON_ERROR_STOP on

do $$
begin
  if (select count(*) from public.school_business_entity_migration_batches
      where id = 'c1000000-0000-4000-8000-202607279999'
        and migration_key = 'r1c-a:2026-08:planned-business-entity:personal-to-aosora'
        and execution_status = 'executed'
        and expected_lesson_count = 52
        and expected_duration_hours = 109
        and expected_lesson_fee_jpy = 1024000
        and manifest_hash = '698f2bcb8f1fbc947b1f9785b5041b9a') <> 1 then
    raise exception 'R1C_A_POSTDEPLOY_BATCH_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id = 'c1000000-0000-4000-8000-202607279999'
        and execution_status = 'executed') <> 52 then
    raise exception 'R1C_A_POSTDEPLOY_ITEM_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    left join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
      and (
        lesson.id is null
        or lesson.business_entity_id <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        or md5(item.original_row_snapshot::text) <> item.before_hash
        or md5(item.after_row_snapshot::text) <> item.after_hash
        or to_jsonb(lesson) is distinct from item.after_row_snapshot
        or (item.original_row_snapshot - 'business_entity_id')
           is distinct from (item.after_row_snapshot - 'business_entity_id')
        or item.original_updated_at is distinct from lesson.updated_at
      )
  ) then
    raise exception 'R1C_A_POSTDEPLOY_ROW_OR_AUDIT_HASH_MISMATCH';
  end if;

  if (select md5(string_agg(item.before_hash, '' order by item.lesson_record_id::text))
      from public.school_business_entity_migration_items item
      where item.batch_id = 'c1000000-0000-4000-8000-202607279999')
     <> '698f2bcb8f1fbc947b1f9785b5041b9a' then
    raise exception 'R1C_A_POSTDEPLOY_MANIFEST_HASH_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
      and item.lesson_record_id in (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
  ) then
    raise exception 'R1C_A_POSTDEPLOY_CROSS_MONTH_IN_MANIFEST';
  end if;

  if (select count(*) from public.school_lesson_records lesson
      where lesson.id in (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
        and lesson.business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        and lesson.duration_hours = 2
        and lesson.unit_price = 8500
        and lesson.lesson_fee = 17000) <> 2
     or exists (
       select 1 from public.school_lesson_records lesson
       where (lesson.id = '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
              and md5(to_jsonb(lesson)::text) <> '2d52e778bfb59a27bb3b28506232217d')
          or (lesson.id = '8b737b58-cd14-42c5-afd2-34730dcef963'
              and md5(to_jsonb(lesson)::text) <> '21f83674162b1b1ca485912a048bac3c')
     )
     or (select count(*) from public.school_student_tuition_bill_lessons relation
         where relation.planned_lesson_id in (
           '8b737b58-cd14-42c5-afd2-34730dcef963',
           '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
         )
           and relation.tuition_bill_id = '2a9f1c25-a060-461e-ae10-b02295dec381'
           and relation.relation_role = 'canonical_charge') <> 2 then
    raise exception 'R1C_A_POSTDEPLOY_CROSS_MONTH_EVIDENCE_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_student_tuition_bill_lessons relation
    join public.school_business_entity_migration_items item
      on item.lesson_record_id = relation.planned_lesson_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
  ) or exists (
    select 1 from public.school_student_tuition_bills bill
    join public.school_business_entity_migration_items item
      on (bill.source_snapshot -> 'planned_lesson_ids') ? item.lesson_record_id::text
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
  ) or exists (
    select 1 from public.school_lesson_records actual
    join public.school_business_entity_migration_items item
      on item.lesson_record_id = actual.planned_lesson_id
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
      and actual.lesson_type = 'actual'
      and actual.voided_at is null
  ) then
    raise exception 'R1C_A_POSTDEPLOY_TARGET_HAS_BILL_OR_ACTUAL';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details detail
    join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
    where wage.status <> 'void'
      and (
        exists (
          select 1 from public.school_business_entity_migration_items item
          where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
            and item.lesson_record_id = detail.lesson_record_id
        )
        or exists (
          select 1
          from public.school_lesson_records actual
          join public.school_business_entity_migration_items item
            on item.lesson_record_id = actual.planned_lesson_id
          where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
            and actual.id = detail.lesson_record_id
        )
      )
  ) or exists (
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id in (
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      'b17abc58-2f64-4bad-bf20-c9643ead60bc'
    ) and settlement.year_month = '2026-08'
  ) then
    raise exception 'R1C_A_POSTDEPLOY_TARGET_HAS_WAGE_OR_SETTLEMENT';
  end if;

  if exists (
    select 1 from public.school_income_records income
    join public.school_business_entity_migration_items item
      on to_jsonb(income)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
  ) or exists (
    select 1 from public.school_personal_cash_income_linkage_events linkage
    join public.school_business_entity_migration_items item
      on to_jsonb(linkage)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
  ) or exists (
    select 1 from public.school_account_transactions transaction_row
    join public.school_business_entity_migration_items item
      on to_jsonb(transaction_row)::text like '%' || item.lesson_record_id::text || '%'
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
  ) then
    raise exception 'R1C_A_POSTDEPLOY_TARGET_HAS_FINANCIAL_REFERENCE';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'R1C_A_POSTDEPLOY_R0_GATE_MISMATCH';
  end if;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.school_lesson_records'::regclass
        and tgname = 'trg_school_lesson_records_updated_at'
        and tgenabled = 'O'
        and not tgisinternal) <> 1 then
    raise exception 'R1C_A_POSTDEPLOY_UPDATED_AT_TRIGGER_MISMATCH';
  end if;
end;
$$;

select
  coalesce(student.display_name, student.name) as student_name,
  count(*) as migrated_lesson_count,
  sum((item.original_row_snapshot ->> 'duration_hours')::numeric) as duration_hours,
  sum((item.original_row_snapshot ->> 'lesson_fee')::numeric) as lesson_fee_jpy,
  count(*) filter (where item.original_updated_at = lesson.updated_at) as updated_at_unchanged,
  md5(string_agg(md5((item.original_row_snapshot - 'business_entity_id')::text), '' order by item.lesson_record_id::text)) as immutable_before_hash,
  md5(string_agg(md5((item.after_row_snapshot - 'business_entity_id')::text), '' order by item.lesson_record_id::text)) as immutable_after_hash
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
join public.school_students student on student.id = item.student_id
where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
group by student.display_name, student.name
order by student_name;

select
  item.item_order,
  item.lesson_record_id,
  item.student_id,
  item.source_generation_batch_id,
  item.before_hash,
  item.after_hash
from public.school_business_entity_migration_items item
where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
order by item.item_order;

select
  (select count(*) from public.school_student_tuition_bills) as tuition_bill_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_student_tuition_bills row_value) as tuition_bill_hash,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_income_records row_value) as income_hash,
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_student_tuition_billing_identities row_value) as identity_hash,
  (select count(*) from public.school_student_tuition_bill_lessons) as bill_lesson_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_student_tuition_bill_lessons row_value) as bill_lesson_hash;

select
  (select count(*) from public.school_personal_cash_income_linkage_events) as cash_linkage_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_personal_cash_income_linkage_events row_value) as cash_linkage_hash,
  (select count(*) from public.school_account_transactions) as account_transaction_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_account_transactions row_value) as account_transaction_hash,
  (select count(*) from public.school_lesson_records where lesson_type = 'actual') as actual_lesson_current_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_lesson_records row_value where row_value.lesson_type = 'actual') as actual_lesson_current_hash;

select
  (select count(*) from public.school_student_monthly_settlements) as settlement_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_student_monthly_settlements row_value) as settlement_hash,
  (select count(*) from public.school_teacher_wage_locks) as wage_lock_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_teacher_wage_locks row_value) as wage_lock_hash,
  (select count(*) from public.school_teacher_wage_lock_details) as wage_detail_count,
  (select md5(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text)) from public.school_teacher_wage_lock_details row_value) as wage_detail_hash;

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;

select
  lesson.id,
  lesson.lesson_date,
  lesson.business_entity_id,
  lesson.duration_hours,
  lesson.unit_price,
  lesson.lesson_fee,
  md5(to_jsonb(lesson)::text) as complete_row_hash,
  relation.tuition_bill_id,
  relation.relation_role
from public.school_lesson_records lesson
join public.school_student_tuition_bill_lessons relation
  on relation.planned_lesson_id = lesson.id
where lesson.id in (
  '8b737b58-cd14-42c5-afd2-34730dcef963',
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
)
order by lesson.lesson_date;

-- Compare actual creation times with the recorded migration audit execution evidence.
select
  batch.executed_at as migration_executed_at,
  count(actual.*) filter (where actual.created_at <= batch.executed_at) as actual_at_or_before_migration_execution_evidence,
  md5(string_agg(md5(to_jsonb(actual)::text), '' order by actual.id::text)
      filter (where actual.created_at <= batch.executed_at)) as actual_hash_at_or_before_migration_execution_evidence,
  count(actual.*) filter (where actual.created_at > batch.executed_at) as actual_created_after_migration_execution_evidence,
  count(actual.*) as actual_current
from public.school_business_entity_migration_batches batch
join public.school_lesson_records actual on actual.lesson_type = 'actual'
where batch.id = 'c1000000-0000-4000-8000-202607279999'
group by batch.executed_at;

select
  actual.id as later_actual_id,
  actual.planned_lesson_id,
  actual.created_at,
  actual.created_at - batch.executed_at as created_after_migration_execution_evidence,
  exists (
    select 1
    from public.school_business_entity_migration_items item
    where item.batch_id = batch.id
      and item.lesson_record_id = actual.planned_lesson_id
  ) as source_in_r1c_a_manifest
from public.school_business_entity_migration_batches batch
join public.school_lesson_records actual
  on actual.lesson_type = 'actual'
 and actual.created_at > batch.executed_at
where batch.id = 'c1000000-0000-4000-8000-202607279999'
order by actual.created_at, actual.id;
