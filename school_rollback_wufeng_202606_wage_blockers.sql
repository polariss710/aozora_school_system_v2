-- school_rollback_wufeng_202606_wage_blockers.sql
-- Purpose:
--   Guarded one-time rollback for two mistaken real 2026-06 Wu Feng teacher
--   wage snapshots that still block the formal June wage generation flow.
--
-- Scope:
--   - Exact wage lock ids:
--     * 2af31792-6d52-49fc-85a4-a915bd5d12ba / void / 个人名义
--     * aa301221-5fab-424a-830c-f5dcf7681783 / locked / 青空进学塾
--   - Deletes only their school_teacher_wage_lock_details rows and the two
--     school_teacher_wage_locks rows.
--   - Does not update school_lesson_records, actual_minutes, payment requests,
--     expenses, account transactions, accounts, income, or settlements.
--
-- Safety:
--   - This is not a general wage void/reissue lifecycle.
--   - Run inside a transaction and ROLLBACK first, then execute once only after
--     all guard checks pass.
--   - Fails if any payment request, expense/account transaction side effect, or
--     wage detail adjustment exists for the target locks.

select
  'pre_target_summary' as check_name,
  count(*) as lock_count,
  count(*) filter (where id = '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid and status = 'void') as void_personal_count,
  count(*) filter (where id = 'aa301221-5fab-424a-830c-f5dcf7681783'::uuid and status = 'locked') as locked_aozora_count,
  coalesce(sum(total_jpy), 0) as total_jpy,
  coalesce(sum(total_cny), 0) as total_cny
from public.school_teacher_wage_locks
where id = any (array[
  '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
  'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
]);

select
  'pre_detail_summary' as check_name,
  count(*) as detail_count,
  count(distinct lesson_record_id) as distinct_lesson_count,
  coalesce(sum(total_jpy), 0) as detail_total_jpy,
  coalesce(sum(total_cny), 0) as detail_total_cny
from public.school_teacher_wage_lock_details
where lock_id = any (array[
  '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
  'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
]);

select
  'pre_dependency_summary' as check_name,
  (
    select count(*)
    from public.school_payment_requests p
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
        'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
      ])
  ) as payment_request_count,
  (
    select count(*)
    from public.school_teacher_wage_detail_adjustments a
    where a.wage_lock_id = any (array[
      '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
      'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
    ])
  ) as adjustment_count,
  (
    select count(*)
    from public.school_expense_records e
    join public.school_payment_requests p
      on p.paid_expense_id = e.id
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
        'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
      ])
  ) as paid_expense_via_payment_count,
  (
    select count(*)
    from public.school_expense_records e
    where e.salary_payment_id = any (array[
      '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
      'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
    ])
  ) as expense_salary_payment_id_count,
  (
    select count(*)
    from public.school_account_transactions t
    join public.school_payment_requests p
      on p.paid_account_transaction_id = t.id
        or p.reversal_transaction_id = t.id
    where p.source_type = 'teacher_wage'
      and p.source_id = any (array[
        '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
        'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
      ])
  ) as account_tx_via_payment_count,
  (
    select count(*)
    from public.school_account_transactions t
    where t.related_table in ('school_teacher_wage_locks', 'teacher_wage')
      and t.related_id = any (array[
        '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
        'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
      ])
  ) as direct_wage_related_account_tx_count;

select
  'pre_source_lesson_summary' as check_name,
  count(distinct lr.id) as source_actual_count,
  coalesce(sum(lr.actual_minutes), 0) as source_actual_minutes,
  count(*) filter (where lr.actual_minutes is null) as missing_actual_minutes,
  count(*) filter (where lr.lesson_type <> 'actual') as non_actual_count,
  count(*) filter (where lr.status not in ('completed', 'makeup_completed')) as unsupported_actual_status_count,
  count(*) filter (where coalesce(lr.teacher_settlement_month, lr.year_month) <> '2026-06') as wrong_month_count,
  count(*) filter (where lr.voided_at is not null) as voided_lesson_count
from public.school_teacher_wage_lock_details d
join public.school_lesson_records lr
  on lr.id = d.lesson_record_id
where d.lock_id = any (array[
  '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
  'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
]);

do $$
declare
  v_target_lock_ids uuid[] := array[
    '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
    'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
  ];
  v_teacher_id uuid := 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid;
  v_lock_count integer;
  v_void_personal_count integer;
  v_locked_aozora_count integer;
  v_total_jpy numeric;
  v_total_cny numeric;
  v_detail_count integer;
  v_distinct_lesson_count integer;
  v_detail_total_jpy numeric;
  v_detail_total_cny numeric;
  v_source_actual_count integer;
  v_source_actual_minutes integer;
  v_missing_actual_minutes integer;
  v_bad_source_count integer;
  v_payment_request_count integer;
  v_adjustment_count integer;
  v_paid_expense_count integer;
  v_salary_payment_expense_count integer;
  v_account_tx_via_payment_count integer;
  v_direct_wage_account_tx_count integer;
  v_deleted_details integer;
  v_deleted_locks integer;
begin
  select
    count(*),
    count(*) filter (
      where id = '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid
        and status = 'void'
        and business_entity_id = '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid
        and total_jpy = 0
    ),
    count(*) filter (
      where id = 'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
        and status = 'locked'
        and business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
        and total_jpy = 9000
    ),
    coalesce(sum(total_jpy), 0),
    coalesce(sum(total_cny), 0)
  into v_lock_count, v_void_personal_count, v_locked_aozora_count, v_total_jpy, v_total_cny
  from public.school_teacher_wage_locks
  where id = any (v_target_lock_ids)
    and settlement_month = '2026-06'
    and teacher_id = v_teacher_id
    and teacher_name = '吴峰';

  if v_lock_count <> 2
    or v_void_personal_count <> 1
    or v_locked_aozora_count <> 1
    or v_total_jpy <> 9000
    or v_total_cny <> 0
  then
    raise exception
      'unexpected Wu Feng 2026-06 wage lock target state: locks %, void_personal %, locked_aozora %, total_jpy %, total_cny %',
      v_lock_count, v_void_personal_count, v_locked_aozora_count, v_total_jpy, v_total_cny;
  end if;

  select count(*), count(distinct lesson_record_id),
         coalesce(sum(total_jpy), 0), coalesce(sum(total_cny), 0)
  into v_detail_count, v_distinct_lesson_count, v_detail_total_jpy, v_detail_total_cny
  from public.school_teacher_wage_lock_details
  where lock_id = any (v_target_lock_ids);

  if v_detail_count <> 4
    or v_distinct_lesson_count <> 4
    or v_detail_total_jpy <> 9000
    or v_detail_total_cny <> 0
  then
    raise exception
      'unexpected Wu Feng 2026-06 wage detail target state: detail %, distinct_lessons %, detail_total_jpy %, detail_total_cny %',
      v_detail_count, v_distinct_lesson_count, v_detail_total_jpy, v_detail_total_cny;
  end if;

  select count(distinct lr.id), coalesce(sum(lr.actual_minutes), 0),
         count(*) filter (where lr.actual_minutes is null),
         count(*) filter (
           where lr.lesson_type <> 'actual'
              or lr.status not in ('completed', 'makeup_completed')
              or coalesce(lr.teacher_settlement_month, lr.year_month) <> '2026-06'
              or lr.teacher_id <> v_teacher_id
              or lr.voided_at is not null
         )
  into v_source_actual_count, v_source_actual_minutes, v_missing_actual_minutes, v_bad_source_count
  from public.school_teacher_wage_lock_details d
  join public.school_lesson_records lr
    on lr.id = d.lesson_record_id
  where d.lock_id = any (v_target_lock_ids);

  if v_source_actual_count <> 4
    or v_source_actual_minutes <> 480
    or v_missing_actual_minutes <> 0
    or v_bad_source_count <> 0
  then
    raise exception
      'unexpected Wu Feng 2026-06 source actual state: actual %, minutes %, missing_minutes %, bad_sources %',
      v_source_actual_count, v_source_actual_minutes, v_missing_actual_minutes, v_bad_source_count;
  end if;

  select count(*)
  into v_payment_request_count
  from public.school_payment_requests
  where source_type = 'teacher_wage'
    and source_id = any (v_target_lock_ids);

  select count(*)
  into v_adjustment_count
  from public.school_teacher_wage_detail_adjustments
  where wage_lock_id = any (v_target_lock_ids);

  select count(*)
  into v_paid_expense_count
  from public.school_expense_records e
  join public.school_payment_requests p
    on p.paid_expense_id = e.id
  where p.source_type = 'teacher_wage'
    and p.source_id = any (v_target_lock_ids);

  select count(*)
  into v_salary_payment_expense_count
  from public.school_expense_records
  where salary_payment_id = any (v_target_lock_ids);

  select count(*)
  into v_account_tx_via_payment_count
  from public.school_account_transactions t
  join public.school_payment_requests p
    on p.paid_account_transaction_id = t.id
      or p.reversal_transaction_id = t.id
  where p.source_type = 'teacher_wage'
    and p.source_id = any (v_target_lock_ids);

  select count(*)
  into v_direct_wage_account_tx_count
  from public.school_account_transactions
  where related_table in ('school_teacher_wage_locks', 'teacher_wage')
    and related_id = any (v_target_lock_ids);

  if v_payment_request_count <> 0
    or v_adjustment_count <> 0
    or v_paid_expense_count <> 0
    or v_salary_payment_expense_count <> 0
    or v_account_tx_via_payment_count <> 0
    or v_direct_wage_account_tx_count <> 0
  then
    raise exception
      'target Wu Feng 2026-06 wage locks have downstream dependencies: payment_requests %, adjustments %, paid_expenses %, salary_expenses %, account_tx_via_payment %, direct_wage_account_tx %',
      v_payment_request_count, v_adjustment_count, v_paid_expense_count, v_salary_payment_expense_count,
      v_account_tx_via_payment_count, v_direct_wage_account_tx_count;
  end if;

  delete from public.school_teacher_wage_lock_details
  where lock_id = any (v_target_lock_ids);
  get diagnostics v_deleted_details = row_count;

  if v_deleted_details <> 4 then
    raise exception 'unexpected deleted wage detail count: %', v_deleted_details;
  end if;

  delete from public.school_teacher_wage_locks
  where id = any (v_target_lock_ids)
    and settlement_month = '2026-06'
    and teacher_id = v_teacher_id
    and status in ('locked', 'void');
  get diagnostics v_deleted_locks = row_count;

  if v_deleted_locks <> 2 then
    raise exception 'unexpected deleted wage lock count: %', v_deleted_locks;
  end if;

  raise notice 'rolled back Wu Feng 2026-06 wage blockers: deleted_details %, deleted_locks %',
    v_deleted_details, v_deleted_locks;
end $$;

select
  'post_target_summary' as check_name,
  (
    select count(*)
    from public.school_teacher_wage_locks
    where id = any (array[
      '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
      'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
    ])
  ) as remaining_target_locks,
  (
    select count(*)
    from public.school_teacher_wage_lock_details
    where lock_id = any (array[
      '2af31792-6d52-49fc-85a4-a915bd5d12ba'::uuid,
      'aa301221-5fab-424a-830c-f5dcf7681783'::uuid
    ])
  ) as remaining_target_details,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.teacher_id = 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
  ) as remaining_candidate_actuals,
  (
    select coalesce(sum(lr.actual_minutes), 0)
    from public.school_lesson_records lr
    where lr.teacher_id = 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
  ) as remaining_candidate_actual_minutes,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.teacher_id = 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
      and exists (
        select 1
        from public.school_teacher_wage_locks w
        where w.teacher_id = lr.teacher_id
          and w.business_entity_id is not distinct from lr.business_entity_id
          and w.settlement_month = '2026-06'
      )
  ) as remaining_wage_lock_group_blockers,
  (
    select count(*)
    from public.school_lesson_records lr
    where lr.teacher_id = 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = '2026-06'
      and exists (
        select 1
        from public.school_teacher_wage_lock_details d
        where d.lesson_record_id = lr.id
      )
  ) as remaining_wage_detail_blockers;
