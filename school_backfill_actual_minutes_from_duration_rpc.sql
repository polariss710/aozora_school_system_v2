-- school_backfill_actual_minutes_from_duration_rpc.sql
-- RPC: public.school_backfill_actual_minutes_from_duration
-- Purpose: Safely sync actual_minutes from duration_hours for one
-- teacher-wage month.
-- Guardrails:
-- - Updates only school actual completed / makeup_completed rows in one month.
-- - Requires positive duration_hours and derives minutes as round(hours * 60)
--   when actual_minutes is missing, negative, or inconsistent with duration.
-- - Rejects rows tied to locked student settlements, locked teacher wage
--   snapshots, existing wage details, or teacher_wage payment requests.
-- - Does not change wage generation rules, wage snapshots, payment requests,
--   expenses, accounts, account transactions, income, or student settlements.

create or replace function public.school_backfill_actual_minutes_from_duration(
  p_year_month text
)
returns table (
  lesson_id uuid,
  lesson_date date,
  teacher_id uuid,
  student_id uuid,
  duration_hours numeric,
  old_actual_minutes integer,
  new_actual_minutes integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_candidate_count integer;
  v_not_fixable_count integer;
  v_locked_student_count integer;
  v_locked_wage_count integer;
  v_wage_detail_count integer;
  v_payment_request_count integer;
begin
  if v_year_month is null then
    raise exception '请选择补齐月份。';
  end if;

  if v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '补齐月份格式无效，应为 YYYY-MM。';
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_candidate_count
  from candidates;

  if v_candidate_count = 0 then
    return;
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_not_fixable_count
  from candidates c
  where coalesce(c.duration_hours, 0) <= 0
     or c.duration_hours > 24;

  if v_not_fixable_count > 0 then
    raise exception '存在无法按 duration_hours 安全补齐 actual_minutes 的 actual 课时。';
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_locked_student_count
  from candidates c
  where exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = c.student_id
      and s.year_month = c.year_month
      and s.settlement_status = 'locked'
  );

  if v_locked_student_count > 0 then
    raise exception '存在学生月度结算已锁定的 actual 课时，不能补齐 actual_minutes。';
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_locked_wage_count
  from candidates c
  where exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = c.teacher_id
      and w.business_entity_id is not distinct from c.business_entity_id
      and w.settlement_month = coalesce(c.teacher_settlement_month, c.year_month)
      and w.status = 'locked'
  );

  if v_locked_wage_count > 0 then
    raise exception '存在老师工资快照已生成的 actual 课时，不能补齐 actual_minutes。';
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_wage_detail_count
  from candidates c
  where exists (
    select 1
    from public.school_teacher_wage_lock_details d
    where d.lesson_record_id = c.id
  );

  if v_wage_detail_count > 0 then
    raise exception '存在已进入老师工资明细的 actual 课时，不能补齐 actual_minutes。';
  end if;

  with candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  )
  select count(*)
  into v_payment_request_count
  from candidates c
  where exists (
    select 1
    from public.school_teacher_wage_locks w
    join public.school_payment_requests pr
      on pr.source_type = 'teacher_wage'
     and pr.source_id = w.id
    where w.teacher_id = c.teacher_id
      and w.business_entity_id is not distinct from c.business_entity_id
      and w.settlement_month = coalesce(c.teacher_settlement_month, c.year_month)
  );

  if v_payment_request_count > 0 then
    raise exception '存在已生成老师工资支付请求的 actual 课时，不能补齐 actual_minutes。';
  end if;

  return query
  with candidates as (
    select lr.id, lr.lesson_date, lr.teacher_id, lr.student_id,
           lr.duration_hours, lr.actual_minutes
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (lr.actual_minutes is null or lr.actual_minutes < 0 or (coalesce(lr.duration_hours, 0) > 0 and lr.actual_minutes <> round(lr.duration_hours * 60)::integer))
  ),
  updated as (
    update public.school_lesson_records lr
    set actual_minutes = round(c.duration_hours * 60)::integer
    from candidates c
    where lr.id = c.id
    returning lr.id, lr.lesson_date, lr.teacher_id, lr.student_id,
              lr.duration_hours, c.actual_minutes as old_actual_minutes,
              lr.actual_minutes as new_actual_minutes
  )
  select updated.id, updated.lesson_date, updated.teacher_id, updated.student_id,
         updated.duration_hours, updated.old_actual_minutes,
         updated.new_actual_minutes
  from updated
  order by updated.lesson_date, updated.id;
end;
$$;

revoke all on function public.school_backfill_actual_minutes_from_duration(text)
from public, anon, authenticated;

grant execute on function public.school_backfill_actual_minutes_from_duration(text)
to service_role;

comment on function public.school_backfill_actual_minutes_from_duration(text)
is 'Safely syncs school_lesson_records.actual_minutes from duration_hours for one teacher-wage month, rejecting locked/wage-detailed/payment-linked rows.';
