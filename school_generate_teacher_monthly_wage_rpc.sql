-- school_generate_teacher_monthly_wage_rpc.sql
-- RPC: public.school_generate_teacher_monthly_wage
-- Purpose: Generate teacher monthly wage locks and details from actual lessons.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.83.0-teacher-wage-guard-order-20260610
--
-- Scope:
-- - Generate saved teacher wage snapshots for one settlement month.
-- - Read only actual lessons with status completed / makeup_completed.
-- - Write only public.school_teacher_wage_locks and
--   public.school_teacher_wage_lock_details.
-- - Generate one wage lock per teacher/month in this MVP. A teacher/month with
--   actual lessons under multiple business entities is rejected for a later
--   explicit design because the wage lock header has one business entity field.
--
-- Business rules:
-- - planned lessons do not participate.
-- - cancelled actual lessons do not participate.
-- - is_billable is ignored for teacher wage; non-billable makeup_completed
--   actual lessons still participate.
-- - Cross-month makeup actual lessons participate by teacher_settlement_month.
-- - CNY, exchange-rate, transport fee, and classroom fee calculation are not
--   handled in this MVP. Generated fee_jpy / CNY / exchange fields are 0.
-- - lesson_count equals generated wage detail row count.
--
-- Not supported:
-- - Draft wage generation.
-- - Regeneration, overwrite, delete, historical backfill, or cleanup.
-- - Payment request, expense, account, account transaction, income, student
--   settlement, or lesson mutation.
--
-- Verification:
-- - Read-only DB verification confirmed existing wage detail formula:
--   lesson_wage_jpy = round(pay_hours * hourly_rate_jpy), and main totals are
--   detail aggregates.
-- - Rollback test used codex-test actual lesson ids
--   80000000-0000-4000-8000-000000008001 /
--   80000000-0000-4000-8000-000000008002 /
--   80000000-0000-4000-8000-000000008003 and left zero residue.
-- - Commit test used codex-test actual lesson ids
--   81000000-0000-4000-8000-000000010001 /
--   81000000-0000-4000-8000-000000010002 /
--   81000000-0000-4000-8000-000000010003, created wage lock
--   f5fe1fe3-f9e1-45d4-ac50-270c9b609d58 and detail ids
--   aad48406-c0cc-499b-b2a5-0fd7e1709688 /
--   1ad4f156-e869-4a36-aa47-c12edaa18da6.
-- - 2026-06-10 follow-up changed guard order so existing same-teacher/month
--   wage snapshots are rejected before missing-field actual validation.
-- - Protected payment, expense, account, account transaction, income, and
--   student settlement table counts stayed unchanged.

create or replace function public.school_generate_teacher_monthly_wage(
  p_year_month text,
  p_teacher_id uuid default null
)
returns table (
  wage_lock_id uuid,
  teacher_id uuid,
  teacher_name text,
  settlement_month text,
  business_entity_id uuid,
  business_name text,
  lesson_count integer,
  total_minutes numeric,
  pay_hours numeric,
  lesson_wage_jpy numeric,
  total_jpy numeric,
  status text,
  locked_at timestamptz,
  detail_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_candidate_count integer;
  v_bad_actual_count integer;
  v_missing_rule_count integer;
  v_duplicate_rule_count integer;
  v_existing_detail_count integer;
  v_existing_lock_count integer;
  v_multi_business_teacher_count integer;
begin
  if v_year_month is null then
    raise exception '请选择工资月份。';
  end if;

  if v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '工资月份格式无效，应为 YYYY-MM。';
  end if;

  if p_teacher_id is not null and not exists (
    select 1
    from public.school_teachers t
    where t.id = p_teacher_id
      and coalesce(t.app_type, '') = 'school'
  ) then
    raise exception '老师不存在。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  )
  select count(*)
  into v_candidate_count
  from raw_candidates;

  if v_candidate_count = 0 then
    raise exception '该月份没有可生成老师工资的 completed / makeup_completed actual 课时。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  )
  select count(*)
  into v_existing_lock_count
  from (
    select distinct c.teacher_id
    from raw_candidates c
    where c.teacher_id is not null
  ) target_teachers
  where exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = target_teachers.teacher_id
      and w.settlement_month = v_year_month
  );

  if v_existing_lock_count > 0 then
    raise exception '目标老师月份已有工资记录，不能重复生成。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  )
  select count(*)
  into v_existing_detail_count
  from raw_candidates c
  where exists (
    select 1
    from public.school_teacher_wage_lock_details d
    where d.lesson_record_id = c.id
  );

  if v_existing_detail_count > 0 then
    raise exception '存在已经进入老师工资明细的 actual 课时，不能重复生成工资。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  )
  select count(*)
  into v_bad_actual_count
  from raw_candidates c
  where c.teacher_id is null
     or c.student_id is null
     or c.subject_id is null
     or c.business_entity_id is null
     or c.actual_minutes is null
     or c.actual_minutes < 0;

  if v_bad_actual_count > 0 then
    raise exception '存在缺少老师/学生/科目/业务归属/实际分钟的 actual 课时，不能生成工资。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  )
  select count(*)
  into v_multi_business_teacher_count
  from (
    select c.teacher_id
    from raw_candidates c
    group by c.teacher_id
    having count(distinct c.business_entity_id) > 1
  ) multi_business;

  if v_multi_business_teacher_count > 0 then
    raise exception '同一老师同月存在多个业务归属的 actual 课时，MVP 不能生成单一工资锁。';
  end if;

  with raw_candidates as (
    select lr.*
    from public.school_lesson_records lr
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  ),
  rule_counts as (
    select c.id as lesson_record_id, count(r.id) as active_rule_count
    from raw_candidates c
    left join public.school_teacher_wage_rules r
      on r.teacher_id = c.teacher_id
     and r.student_id = c.student_id
     and r.subject_id = c.subject_id
     and r.business_entity_id = c.business_entity_id
     and coalesce(r.is_active, true) = true
    group by c.id
  )
  select
    count(*) filter (where active_rule_count = 0),
    count(*) filter (where active_rule_count > 1)
  into v_missing_rule_count, v_duplicate_rule_count
  from rule_counts;

  if v_missing_rule_count > 0 then
    raise exception '存在没有启用工资规则的 actual 课时，不能生成工资。';
  end if;

  if v_duplicate_rule_count > 0 then
    raise exception '存在命中多条启用工资规则的 actual 课时，不能生成工资。';
  end if;

  return query
  with raw_candidates as (
    select
      lr.id as lesson_record_id,
      lr.lesson_date,
      lr.start_time,
      lr.end_time,
      lr.student_id,
      lr.teacher_id,
      lr.subject_id,
      lr.business_entity_id,
      lr.status as lesson_status,
      lr.lesson_content,
      lr.actual_minutes,
      coalesce(t.display_name, t.name) as teacher_name,
      coalesce(s.display_name, s.name) as student_name,
      sub.name as subject_name,
      be.name as business_name
    from public.school_lesson_records lr
    left join public.school_teachers t on t.id = lr.teacher_id
    left join public.school_students s on s.id = lr.student_id
    left join public.school_subjects sub on sub.id = lr.subject_id
    left join public.school_business_entities be on be.id = lr.business_entity_id
    where coalesce(lr.app_type, '') = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed', 'makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
  ),
  candidate_rules as (
    select
      c.*,
      r.settlement_type,
      case
        when r.settlement_type = 'no_wage' then 0::numeric
        else (c.actual_minutes::numeric / 60)
      end as pay_hours,
      case
        when r.settlement_type = 'no_wage' then 0::numeric
        else round((c.actual_minutes::numeric / 60) * r.hourly_rate_jpy)
      end as lesson_wage_jpy,
      case
        when r.settlement_type = 'no_wage' then true
        else false
      end as is_no_wage
    from raw_candidates c
    join public.school_teacher_wage_rules r
      on r.teacher_id = c.teacher_id
     and r.student_id = c.student_id
     and r.subject_id = c.subject_id
     and r.business_entity_id = c.business_entity_id
     and coalesce(r.is_active, true) = true
  ),
  lock_groups as (
    select
      c.teacher_id,
      max(c.teacher_name) as teacher_name,
      min(c.business_entity_id::text)::uuid as business_entity_id,
      max(c.business_name) as business_name,
      case
        when bool_and(c.settlement_type = 'no_wage') then 'no_wage'
        else 'jpy_hourly'
      end as settlement_type,
      count(*)::integer as lesson_count,
      sum(c.actual_minutes)::numeric as total_minutes,
      sum(c.pay_hours)::numeric as pay_hours,
      sum(c.lesson_wage_jpy)::numeric as lesson_wage_jpy,
      sum(c.lesson_wage_jpy)::numeric as total_jpy
    from candidate_rules c
    group by c.teacher_id
  ),
  inserted_locks as (
    insert into public.school_teacher_wage_locks as w (
      settlement_month,
      teacher_id,
      teacher_name,
      business_entity_id,
      business_name,
      settlement_type,
      exchange_rate,
      total_minutes,
      pay_hours,
      lesson_wage_jpy,
      lesson_wage_cny,
      fee_jpy,
      total_jpy,
      total_cny,
      lesson_count,
      status,
      locked_at,
      updated_at
    )
    select
      v_year_month,
      g.teacher_id,
      g.teacher_name,
      g.business_entity_id,
      g.business_name,
      g.settlement_type,
      0,
      g.total_minutes,
      g.pay_hours,
      g.lesson_wage_jpy,
      0,
      0,
      g.total_jpy,
      0,
      g.lesson_count,
      'locked',
      now(),
      now()
    from lock_groups g
    returning
      w.id,
      w.teacher_id,
      w.teacher_name,
      w.settlement_month,
      w.business_entity_id,
      w.business_name,
      w.lesson_count,
      w.total_minutes,
      w.pay_hours,
      w.lesson_wage_jpy,
      w.total_jpy,
      w.status,
      w.locked_at
  ),
  inserted_details as (
    insert into public.school_teacher_wage_lock_details as d (
      lock_id,
      lesson_record_id,
      lesson_date,
      start_time,
      end_time,
      student_id,
      student_name,
      subject_id,
      subject_name,
      business_entity_id,
      business_name,
      pay_hours,
      lesson_wage_jpy,
      lesson_wage_cny,
      transport_fee_jpy,
      classroom_fee_jpy,
      total_jpy,
      total_cny,
      settlement_type,
      exchange_rate,
      is_no_wage,
      status,
      lesson_content
    )
    select
      il.id,
      c.lesson_record_id,
      c.lesson_date,
      c.start_time,
      c.end_time,
      c.student_id,
      c.student_name,
      c.subject_id,
      c.subject_name,
      c.business_entity_id,
      c.business_name,
      c.pay_hours,
      c.lesson_wage_jpy,
      0,
      0,
      0,
      c.lesson_wage_jpy,
      0,
      c.settlement_type,
      0,
      c.is_no_wage,
      c.lesson_status,
      c.lesson_content
    from candidate_rules c
    join inserted_locks il on il.teacher_id = c.teacher_id
    returning d.lock_id
  ),
  detail_counts as (
    select lock_id, count(*)::integer as detail_count
    from inserted_details
    group by lock_id
  )
  select
    il.id,
    il.teacher_id,
    il.teacher_name,
    il.settlement_month,
    il.business_entity_id,
    il.business_name,
    il.lesson_count,
    il.total_minutes,
    il.pay_hours,
    il.lesson_wage_jpy,
    il.total_jpy,
    il.status,
    il.locked_at,
    dc.detail_count
  from inserted_locks il
  join detail_counts dc on dc.lock_id = il.id
  order by il.teacher_name nulls last, il.teacher_id;
end;
$$;

comment on function public.school_generate_teacher_monthly_wage(text, uuid) is
  'Generates teacher monthly wage locks/details from actual completed and makeup_completed lessons. Writes only wage locks and wage details; no payment, expense, account, income, student settlement, or lesson mutation.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
