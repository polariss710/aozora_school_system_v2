-- school_fix_202605_teacher_wage_duplicate_cong_qirun_rpc.sql
-- RPC: public.school_fix_202605_teacher_wage_duplicate_cong_qirun
-- Purpose:
-- - One-time guarded correction for the duplicated 2026-05 teacher wage snapshot.
-- - Cancel only the duplicate pending teacher-wage payment request through the existing
--   payment status RPC.
-- - Mark only the duplicate teacher wage snapshot as void.
-- - Preserve wage details, lesson records, the older wage snapshot, and the older payment request.

create or replace function public.school_fix_202605_teacher_wage_duplicate_cong_qirun()
returns table (
  duplicate_wage_lock_id uuid,
  duplicate_payment_request_id uuid,
  old_wage_status text,
  new_wage_status text,
  old_payment_status text,
  new_payment_status text,
  locked_count_after integer,
  void_count_after integer,
  fixed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_older_wage_lock_id constant uuid := 'dacc2887-f039-4dcb-861b-6ec36e51bace'::uuid;
  v_duplicate_wage_lock_id constant uuid := '4af1b55e-ece1-47a1-a350-5bb0f2e111ca'::uuid;
  v_older_payment_request_id constant uuid := 'a2794694-9bb0-411f-9f66-ae1fc174a646'::uuid;
  v_duplicate_payment_request_id constant uuid := 'c8280c86-15f9-410b-b9ac-3588b780b3b0'::uuid;
  v_expected_lesson_ids constant uuid[] := array[
    '002875ac-4b12-4f83-b752-d5972d8bb7fa'::uuid,
    'daa403bd-4c8b-4752-a1a6-717c9270f661'::uuid,
    '7209bf5d-1916-4f61-bb4c-41dd0b667028'::uuid
  ];
  v_older_wage public.school_teacher_wage_locks%rowtype;
  v_duplicate_wage public.school_teacher_wage_locks%rowtype;
  v_older_payment public.school_payment_requests%rowtype;
  v_duplicate_payment public.school_payment_requests%rowtype;
  v_older_detail_count integer;
  v_duplicate_detail_count integer;
  v_older_expected_detail_count integer;
  v_duplicate_expected_detail_count integer;
  v_older_payment_count integer;
  v_duplicate_payment_count integer;
  v_locked_count_before integer;
  v_void_count_before integer;
  v_locked_count_after integer;
  v_void_count_after integer;
  v_payment_cancel record;
  v_fixed_at timestamptz := now();
begin
  select count(*) filter (where status = 'locked')::integer,
         count(*) filter (where status = 'void')::integer
    into v_locked_count_before,
         v_void_count_before
    from public.school_teacher_wage_locks
   where settlement_month = '2026-05';

  if v_locked_count_before <> 10 or v_void_count_before <> 12 then
    raise exception
      'unexpected 2026-05 teacher wage count before fix. locked %, void %',
      v_locked_count_before,
      v_void_count_before;
  end if;

  select *
    into v_older_wage
    from public.school_teacher_wage_locks
   where id = v_older_wage_lock_id
   for update;

  if not found then
    raise exception 'older wage lock not found: %', v_older_wage_lock_id;
  end if;

  select *
    into v_duplicate_wage
    from public.school_teacher_wage_locks
   where id = v_duplicate_wage_lock_id
   for update;

  if not found then
    raise exception 'duplicate wage lock not found: %', v_duplicate_wage_lock_id;
  end if;

  if v_older_wage.status <> 'locked' or v_older_wage.voided_at is not null then
    raise exception
      'older wage lock must remain active locked. status %, voided_at %',
      v_older_wage.status,
      v_older_wage.voided_at;
  end if;

  if v_duplicate_wage.status <> 'locked' or v_duplicate_wage.voided_at is not null then
    raise exception
      'duplicate wage lock must be locked and non-void before fix. status %, voided_at %',
      v_duplicate_wage.status,
      v_duplicate_wage.voided_at;
  end if;

  if v_older_wage.settlement_month <> '2026-05'
     or v_duplicate_wage.settlement_month <> '2026-05' then
    raise exception
      'target wage locks must both belong to 2026-05. older %, duplicate %',
      v_older_wage.settlement_month,
      v_duplicate_wage.settlement_month;
  end if;

  if v_duplicate_wage.created_at <= v_older_wage.created_at then
    raise exception
      'duplicate wage lock is not newer than older wage lock. older %, duplicate %',
      v_older_wage.created_at,
      v_duplicate_wage.created_at;
  end if;

  if v_older_wage.teacher_id is distinct from v_duplicate_wage.teacher_id
     or v_older_wage.business_entity_id is distinct from v_duplicate_wage.business_entity_id
     or v_older_wage.teacher_name is distinct from v_duplicate_wage.teacher_name
     or v_older_wage.business_name is distinct from v_duplicate_wage.business_name
     or v_older_wage.lesson_count is distinct from v_duplicate_wage.lesson_count
     or v_older_wage.total_minutes is distinct from v_duplicate_wage.total_minutes
     or v_older_wage.pay_hours is distinct from v_duplicate_wage.pay_hours
     or v_older_wage.lesson_wage_jpy is distinct from v_duplicate_wage.lesson_wage_jpy
     or v_older_wage.total_jpy is distinct from v_duplicate_wage.total_jpy then
    raise exception 'target wage locks no longer match the confirmed duplicate fingerprint';
  end if;

  select count(*)::integer,
         count(*) filter (where lesson_record_id = any(v_expected_lesson_ids))::integer
    into v_older_detail_count,
         v_older_expected_detail_count
    from public.school_teacher_wage_lock_details
   where lock_id = v_older_wage_lock_id;

  select count(*)::integer,
         count(*) filter (where lesson_record_id = any(v_expected_lesson_ids))::integer
    into v_duplicate_detail_count,
         v_duplicate_expected_detail_count
    from public.school_teacher_wage_lock_details
   where lock_id = v_duplicate_wage_lock_id;

  if v_older_detail_count <> 3
     or v_duplicate_detail_count <> 3
     or v_older_expected_detail_count <> 3
     or v_duplicate_expected_detail_count <> 3 then
    raise exception
      'target wage details do not match expected lesson ids. older %/%, duplicate %/%',
      v_older_expected_detail_count,
      v_older_detail_count,
      v_duplicate_expected_detail_count,
      v_duplicate_detail_count;
  end if;

  if exists (
    select 1
      from (
        (
          select lesson_record_id
            from public.school_teacher_wage_lock_details
           where lock_id = v_older_wage_lock_id
          except
          select lesson_record_id
            from public.school_teacher_wage_lock_details
           where lock_id = v_duplicate_wage_lock_id
        )
        union all
        (
          select lesson_record_id
            from public.school_teacher_wage_lock_details
           where lock_id = v_duplicate_wage_lock_id
          except
          select lesson_record_id
            from public.school_teacher_wage_lock_details
           where lock_id = v_older_wage_lock_id
        )
      ) detail_diff
  ) then
    raise exception 'target wage detail lesson ids are not identical';
  end if;

  select count(*)::integer
    into v_older_payment_count
    from public.school_payment_requests
   where source_type = 'teacher_wage'
     and source_id = v_older_wage_lock_id;

  select count(*)::integer
    into v_duplicate_payment_count
    from public.school_payment_requests
   where source_type = 'teacher_wage'
     and source_id = v_duplicate_wage_lock_id;

  if v_older_payment_count <> 1 or v_duplicate_payment_count <> 1 then
    raise exception
      'expected one teacher_wage payment request per target wage lock. older %, duplicate %',
      v_older_payment_count,
      v_duplicate_payment_count;
  end if;

  select *
    into v_older_payment
    from public.school_payment_requests
   where id = v_older_payment_request_id
   for update;

  if not found then
    raise exception 'older payment request not found: %', v_older_payment_request_id;
  end if;

  select *
    into v_duplicate_payment
    from public.school_payment_requests
   where id = v_duplicate_payment_request_id
   for update;

  if not found then
    raise exception 'duplicate payment request not found: %', v_duplicate_payment_request_id;
  end if;

  if v_older_payment.source_type <> 'teacher_wage'
     or v_older_payment.source_id <> v_older_wage_lock_id
     or v_older_payment.status <> 'pending' then
    raise exception
      'older payment request no longer matches expected pending teacher_wage source. source %/%, status %',
      v_older_payment.source_type,
      v_older_payment.source_id,
      v_older_payment.status;
  end if;

  if v_duplicate_payment.source_type <> 'teacher_wage'
     or v_duplicate_payment.source_id <> v_duplicate_wage_lock_id
     or v_duplicate_payment.status <> 'pending' then
    raise exception
      'duplicate payment request must be pending teacher_wage source before fix. source %/%, status %',
      v_duplicate_payment.source_type,
      v_duplicate_payment.source_id,
      v_duplicate_payment.status;
  end if;

  if v_duplicate_payment.paid_at is not null
     or v_duplicate_payment.paid_expense_id is not null
     or v_duplicate_payment.paid_account_transaction_id is not null
     or v_duplicate_payment.account_id is not null then
    raise exception 'duplicate payment request already has payment-side effects';
  end if;

  if v_older_payment.paid_at is not null
     or v_older_payment.paid_expense_id is not null
     or v_older_payment.paid_account_transaction_id is not null
     or v_older_payment.account_id is not null then
    raise exception 'older payment request unexpectedly has payment-side effects';
  end if;

  if v_duplicate_payment.amount_jpy is distinct from v_duplicate_wage.total_jpy
     or v_duplicate_payment.amount is distinct from v_duplicate_wage.total_jpy then
    raise exception
      'duplicate payment amount no longer matches duplicate wage lock. payment %, wage %',
      v_duplicate_payment.amount_jpy,
      v_duplicate_wage.total_jpy;
  end if;

  select *
    into v_payment_cancel
    from public.school_cancel_payment_request(
      v_duplicate_payment_request_id,
      '2026-05 duplicate teacher wage reconciliation'
    );

  if v_payment_cancel.new_status <> 'cancelled' then
    raise exception 'duplicate payment request was not cancelled';
  end if;

  update public.school_teacher_wage_locks
     set status = 'void',
         voided_at = v_fixed_at,
         updated_at = v_fixed_at
   where id = v_duplicate_wage_lock_id
     and status = 'locked'
     and voided_at is null;

  if not found then
    raise exception 'duplicate wage lock was not voided';
  end if;

  select count(*) filter (where status = 'locked')::integer,
         count(*) filter (where status = 'void')::integer
    into v_locked_count_after,
         v_void_count_after
    from public.school_teacher_wage_locks
   where settlement_month = '2026-05';

  if v_locked_count_after <> 9 or v_void_count_after <> 13 then
    raise exception
      'unexpected 2026-05 teacher wage count after fix. locked %, void %',
      v_locked_count_after,
      v_void_count_after;
  end if;

  perform 1
    from public.school_teacher_wage_locks
   where id = v_older_wage_lock_id
     and status = 'locked'
     and voided_at is null;

  if not found then
    raise exception 'older wage lock was unexpectedly changed';
  end if;

  perform 1
    from public.school_payment_requests
   where id = v_older_payment_request_id
     and status = 'pending'
     and paid_at is null
     and paid_expense_id is null
     and paid_account_transaction_id is null
     and account_id is null;

  if not found then
    raise exception 'older payment request was unexpectedly changed';
  end if;

  duplicate_wage_lock_id := v_duplicate_wage_lock_id;
  duplicate_payment_request_id := v_duplicate_payment_request_id;
  old_wage_status := v_duplicate_wage.status;
  new_wage_status := 'void';
  old_payment_status := v_duplicate_payment.status;
  new_payment_status := 'cancelled';
  locked_count_after := v_locked_count_after;
  void_count_after := v_void_count_after;
  fixed_at := v_fixed_at;
  return next;
end;
$$;

comment on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun() is
  'One-time guarded correction for the duplicated 2026-05 Cong Qirun teacher wage snapshot and pending payment request.';

revoke all on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun() from public;
revoke all on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun() from anon;
revoke all on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun() from authenticated;
grant execute on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun() to service_role;
