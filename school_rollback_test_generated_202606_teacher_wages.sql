-- school_rollback_test_generated_202606_teacher_wages.sql
-- Purpose:
--   Guarded one-time rollback for real 2026-06 teacher wage snapshots that
--   were generated early during testing and now block actual lesson editing.
--
-- Scope:
--   - Exact nine 2026-06 wage locks listed in this file.
--   - Deletes only their wage detail rows and wage lock rows.
--   - Does not update lesson records, actual_minutes, payment requests,
--     expenses, account transactions, accounts, income, or settlements.
--
-- Safety:
--   - This is not a general wage void/reissue lifecycle.
--   - It must be run in rollback test first, then run once only after guards pass.
--   - It fails if payment requests, expenses/account transactions through payment
--     requests, or wage detail adjustments exist for the target locks.

select
  'pre_rollback_target_summary' as check_name,
  count(*) as lock_count,
  coalesce(sum(total_jpy), 0) as total_jpy,
  coalesce(sum(total_cny), 0) as total_cny,
  count(*) filter (where status = 'locked') as locked_count
from public.school_teacher_wage_locks
where id = any (array[
  'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
  'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
  '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
  '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
  'b60a925c-74de-4030-8405-e310bb915600'::uuid,
  '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
  'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
  'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
  'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
]);

select
  'pre_rollback_dependency_summary' as check_name,
  (
    select count(*)
    from public.school_teacher_wage_lock_details d
    where d.lock_id = any (array[
      'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
      'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
      '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
      '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
      'b60a925c-74de-4030-8405-e310bb915600'::uuid,
      '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
      'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
      'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
      'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
    ])
  ) as detail_count,
  (
    select count(*)
    from public.school_payment_requests p
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
        'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
        '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
        '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
        'b60a925c-74de-4030-8405-e310bb915600'::uuid,
        '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
        'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
        'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
        'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
      ])
  ) as payment_request_count,
  (
    select count(*)
    from public.school_expense_records e
    join public.school_payment_requests p
      on p.paid_expense_id = e.id
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
        'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
        '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
        '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
        'b60a925c-74de-4030-8405-e310bb915600'::uuid,
        '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
        'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
        'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
        'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
      ])
  ) as paid_expense_count,
  (
    select count(*)
    from public.school_account_transactions t
    join public.school_payment_requests p
      on p.reversal_transaction_id = t.id
        or p.paid_account_transaction_id = t.id
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
        'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
        '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
        '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
        'b60a925c-74de-4030-8405-e310bb915600'::uuid,
        '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
        'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
        'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
        'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
      ])
  ) as linked_account_transaction_count,
  (
    select count(*)
    from public.school_teacher_wage_detail_adjustments a
    where a.wage_lock_id = any (array[
      'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
      'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
      '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
      '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
      'b60a925c-74de-4030-8405-e310bb915600'::uuid,
      '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
      'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
      'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
      'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
    ])
  ) as adjustment_count;

select
  'pre_rollback_actual_source_summary' as check_name,
  count(distinct lr.id) as source_actual_count,
  coalesce(sum(lr.actual_minutes), 0) as source_actual_minutes,
  count(*) filter (where lr.actual_minutes is null) as missing_actual_minutes,
  count(*) filter (where lr.lesson_type <> 'actual') as non_actual_count,
  count(*) filter (where lr.status not in ('completed', 'makeup_completed')) as unsupported_actual_status_count
from public.school_teacher_wage_lock_details d
join public.school_lesson_records lr
  on lr.id = d.lesson_record_id
where d.lock_id = any (array[
  'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
  'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
  '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
  '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
  'b60a925c-74de-4030-8405-e310bb915600'::uuid,
  '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
  'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
  'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
  'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
]);

do $$
declare
  v_target_lock_ids uuid[] := array[
    'ed2e7b00-30f5-4e06-82fd-2819b2ce941b'::uuid,
    'f152afba-0db9-4bc9-820b-e0150b755cee'::uuid,
    '5431f1b9-b33d-4510-8995-3cb3d22ceb63'::uuid,
    '3f103378-6e4b-4125-8efa-3ac2c202c36f'::uuid,
    'b60a925c-74de-4030-8405-e310bb915600'::uuid,
    '7e739665-b28b-4755-a3f1-d3ee3a2edee9'::uuid,
    'b73d1222-d46b-4cd0-9a44-bcf48180b9e2'::uuid,
    'e745b5fe-a087-48a6-9f04-6321dcd5b5f2'::uuid,
    'd82111fc-f0df-46f8-b64c-aae25c726528'::uuid
  ];
  v_lock_count integer;
  v_month_lock_count integer;
  v_locked_count integer;
  v_total_jpy numeric;
  v_total_cny numeric;
  v_detail_count integer;
  v_detail_total_jpy numeric;
  v_source_actual_count integer;
  v_source_actual_minutes integer;
  v_missing_actual_minutes integer;
  v_bad_source_count integer;
  v_payment_request_count integer;
  v_paid_expense_count integer;
  v_linked_account_transaction_count integer;
  v_adjustment_count integer;
  v_deleted_details integer;
  v_deleted_locks integer;
begin
  select count(*), coalesce(sum(total_jpy), 0), coalesce(sum(total_cny), 0),
         count(*) filter (where status = 'locked')
  into v_lock_count, v_total_jpy, v_total_cny, v_locked_count
  from public.school_teacher_wage_locks
  where id = any (v_target_lock_ids)
    and settlement_month = '2026-06';

  select count(*)
  into v_month_lock_count
  from public.school_teacher_wage_locks
  where settlement_month = '2026-06';

  select count(*), coalesce(sum(total_jpy), 0)
  into v_detail_count, v_detail_total_jpy
  from public.school_teacher_wage_lock_details
  where lock_id = any (v_target_lock_ids);

  select count(distinct lr.id), coalesce(sum(lr.actual_minutes), 0),
         count(*) filter (where lr.actual_minutes is null),
         count(*) filter (
           where lr.lesson_type <> 'actual'
              or lr.status not in ('completed', 'makeup_completed')
              or coalesce(lr.teacher_settlement_month, lr.year_month) <> '2026-06'
         )
  into v_source_actual_count, v_source_actual_minutes, v_missing_actual_minutes, v_bad_source_count
  from public.school_teacher_wage_lock_details d
  join public.school_lesson_records lr
    on lr.id = d.lesson_record_id
  where d.lock_id = any (v_target_lock_ids);

  select count(*)
  into v_payment_request_count
  from public.school_payment_requests
  where source_type = 'teacher_wage'
    and source_id = any (v_target_lock_ids);

  select count(*)
  into v_paid_expense_count
  from public.school_expense_records e
  join public.school_payment_requests p
    on p.paid_expense_id = e.id
  where p.source_type = 'teacher_wage'
    and p.source_id = any (v_target_lock_ids);

  select count(*)
  into v_linked_account_transaction_count
  from public.school_account_transactions t
  join public.school_payment_requests p
    on p.paid_account_transaction_id = t.id
      or p.reversal_transaction_id = t.id
  where p.source_type = 'teacher_wage'
    and p.source_id = any (v_target_lock_ids);

  select count(*)
  into v_adjustment_count
  from public.school_teacher_wage_detail_adjustments
  where wage_lock_id = any (v_target_lock_ids);

  if v_lock_count <> 9
    or v_month_lock_count <> 9
    or v_locked_count <> 9
    or v_total_jpy <> 193975
    or v_total_cny <> 0
  then
    raise exception
      'unexpected 2026-06 wage lock target state: target %, month %, locked %, total_jpy %, total_cny %',
      v_lock_count, v_month_lock_count, v_locked_count, v_total_jpy, v_total_cny;
  end if;

  if v_detail_count <> 21 or v_detail_total_jpy <> 193975 then
    raise exception
      'unexpected 2026-06 wage detail target state: detail %, detail_total_jpy %',
      v_detail_count, v_detail_total_jpy;
  end if;

  if v_source_actual_count <> 21
    or v_source_actual_minutes <> 2475
    or v_missing_actual_minutes <> 0
    or v_bad_source_count <> 0
  then
    raise exception
      'unexpected 2026-06 source actual state: actual %, minutes %, missing_minutes %, bad_sources %',
      v_source_actual_count, v_source_actual_minutes, v_missing_actual_minutes, v_bad_source_count;
  end if;

  if v_payment_request_count <> 0
    or v_paid_expense_count <> 0
    or v_linked_account_transaction_count <> 0
    or v_adjustment_count <> 0
  then
    raise exception
      'target 2026-06 wage locks have downstream dependencies: payment_requests %, expenses %, account_transactions %, adjustments %',
      v_payment_request_count, v_paid_expense_count, v_linked_account_transaction_count, v_adjustment_count;
  end if;

  delete from public.school_teacher_wage_lock_details d
  where d.lock_id = any (v_target_lock_ids);
  get diagnostics v_deleted_details = row_count;

  if v_deleted_details <> 21 then
    raise exception 'unexpected deleted wage detail count: %', v_deleted_details;
  end if;

  delete from public.school_teacher_wage_locks w
  where w.id = any (v_target_lock_ids)
    and w.settlement_month = '2026-06'
    and w.status = 'locked';
  get diagnostics v_deleted_locks = row_count;

  if v_deleted_locks <> 9 then
    raise exception 'unexpected deleted wage lock count: %', v_deleted_locks;
  end if;

  raise notice 'rolled back mistaken 2026-06 teacher wage snapshots: deleted_details %, deleted_locks %',
    v_deleted_details, v_deleted_locks;
end $$;

select
  'post_rollback_target_summary' as check_name,
  (
    select count(*)
    from public.school_teacher_wage_locks
    where settlement_month = '2026-06'
  ) as remaining_june_wage_locks,
  (
    select count(*)
    from public.school_teacher_wage_lock_details d
    join public.school_teacher_wage_locks w
      on w.id = d.lock_id
    where w.settlement_month = '2026-06'
  ) as remaining_june_wage_details,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
      and lr.actual_minutes is null
  ) as remaining_missing_actual_minutes,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
      and exists (
        select 1
        from public.school_teacher_wage_lock_details d
        where d.lesson_record_id = lr.id
      )
  ) as remaining_detail_ref_blockers,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
      and exists (
        select 1
        from public.school_teacher_wage_locks w
        where w.teacher_id = lr.teacher_id
          and w.business_entity_id is not distinct from lr.business_entity_id
          and w.settlement_month = '2026-06'
          and w.status = 'locked'
      )
  ) as remaining_locked_month_blockers;
