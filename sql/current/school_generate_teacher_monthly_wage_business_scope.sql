-- school_generate_teacher_monthly_wage_rpc.sql
-- RPC: public.school_generate_teacher_monthly_wage
-- Purpose: Generate teacher monthly wage locks and details from actual lessons.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v10.3.67 teacher wage business scoped generation
--
-- Scope:
-- - Generate saved teacher wage snapshots for one settlement month.
-- - Read only actual lessons with status completed / makeup_completed.
-- - Write only public.school_teacher_wage_locks and
--   public.school_teacher_wage_lock_details.
-- - Generate one wage lock per teacher + business entity + month.
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
-- - Regeneration over effective locked snapshots, overwrite, delete,
--   historical backfill, or cleanup.
-- - Payment request, expense, account, account transaction, income, student
--   settlement, or lesson mutation.
--
-- Verification:
-- - 3-argument function plus backward-compatible 2-argument wrapper verified
--   in DB.
-- - Rollback test used fixed whitelist UUID prefix
--   97000000-0000-4000-8000-0000001067xx and proved that one teacher's
--   business B locked snapshot does not block scoped business A generation;
--   duplicate scoped B and old unscoped calls are still guarded. Residue 0.
-- - Commit test used fixed whitelist UUID prefix
--   97000000-0000-4000-8000-0000001068xx, created one scoped wage snapshot,
--   removed all generated/test rows in the same transaction, and committed
--   with residue 0.
-- - Real business data, Cash DB, payment, expense, account transaction,
--   income, student settlement repair, and historical data were not modified.

create or replace function public.school_generate_teacher_monthly_wage(
  p_year_month text,
  p_teacher_id uuid,
  p_business_entity_id uuid
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
set search_path = pg_catalog, public
as $$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_business_entity_id uuid := p_business_entity_id;
  v_candidate_count integer;
  v_bad_actual_count integer;
  v_missing_rule_count integer;
  v_duplicate_rule_count integer;
  v_existing_detail_count integer;
  v_existing_lock_count integer;
  v_unsettled_student_group_count integer;
  v_unsettled_student_examples text;
begin
  perform public.school_require_current_app_admin();

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

  if v_business_entity_id is not null and not exists (
    select 1
    from public.school_business_entities be
    where be.id = v_business_entity_id
  ) then
    raise exception '业务归属不存在。';
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
  )
  select count(*)
  into v_existing_lock_count
  from (
    select distinct c.teacher_id, c.business_entity_id
    from raw_candidates c
    where c.teacher_id is not null
      and c.business_entity_id is not null
  ) target_groups
  where exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = target_groups.teacher_id
      and w.business_entity_id is not distinct from target_groups.business_entity_id
      and w.settlement_month = v_year_month
      and w.status = 'locked'
      and w.voided_at is null
  );

  if v_existing_lock_count > 0 then
    raise exception '目标老师业务归属月份已有工资记录，不能重复生成。';
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
  )
  select count(*)
  into v_existing_detail_count
  from raw_candidates c
  where exists (
    select 1
    from public.school_teacher_wage_lock_details d
    join public.school_teacher_wage_locks w
      on w.id = d.lock_id
    where d.lesson_record_id = c.id
      and w.status = 'locked'
      and w.voided_at is null
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
  ),
  unsettled_groups as (
    select distinct
      public.school_resolve_r1d_e_c_lesson_student_month(c.id)
        as student_settlement_month,
      c.student_id,
      coalesce(s.display_name, s.name, c.student_id::text) as student_name,
      c.business_entity_id,
      coalesce(be.name, c.business_entity_id::text) as business_name
    from raw_candidates c
    left join public.school_student_monthly_settlements m
      on m.student_id = c.student_id
     and m.year_month =
       public.school_resolve_r1d_e_c_lesson_student_month(c.id)
     and m.business_entity_id is not distinct from c.business_entity_id
     and m.settlement_status = 'locked'
    left join public.school_students s on s.id = c.student_id
    left join public.school_business_entities be on be.id = c.business_entity_id
    where m.id is null
  )
  select count(*)
  into v_unsettled_student_group_count
  from unsettled_groups;

  if v_unsettled_student_group_count > 0 then
    with raw_candidates as (
      select lr.*
      from public.school_lesson_records lr
      where coalesce(lr.app_type, '') = 'school'
        and lr.lesson_type = 'actual'
        and lr.status in ('completed', 'makeup_completed')
        and lr.voided_at is null
        and coalesce(lr.teacher_settlement_month, lr.year_month) = v_year_month
        and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
        and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
    ),
    unsettled_groups as (
      select distinct
        public.school_resolve_r1d_e_c_lesson_student_month(c.id)
          as student_settlement_month,
        coalesce(s.display_name, s.name, c.student_id::text) as student_name,
        coalesce(be.name, c.business_entity_id::text) as business_name
      from raw_candidates c
      left join public.school_student_monthly_settlements m
        on m.student_id = c.student_id
       and m.year_month =
         public.school_resolve_r1d_e_c_lesson_student_month(c.id)
       and m.business_entity_id is not distinct from c.business_entity_id
       and m.settlement_status = 'locked'
      left join public.school_students s on s.id = c.student_id
      left join public.school_business_entities be on be.id = c.business_entity_id
      where m.id is null
      order by 1, 2, 3
      limit 8
    )
    select string_agg(format('%s / %s / %s', ug.student_settlement_month, ug.student_name, ug.business_name), '；')
    into v_unsettled_student_examples
    from unsettled_groups ug;

    raise exception '%',
      format(
        '存在学生月度结算未完成的 actual 课时，不能生成老师工资。请先完成学生月度结算：%s%s',
        coalesce(v_unsettled_student_examples, '未完成学生结算'),
        case
          when v_unsettled_student_group_count > 8 then format(' 等 %s 组', v_unsettled_student_group_count)
          else ''
        end
      );
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
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
      and (v_business_entity_id is null or lr.business_entity_id = v_business_entity_id)
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
      c.business_entity_id,
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
    group by c.teacher_id, c.business_entity_id
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
    join inserted_locks il
      on il.teacher_id = c.teacher_id
     and il.business_entity_id is not distinct from c.business_entity_id
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

comment on function public.school_generate_teacher_monthly_wage(text, uuid, uuid) is
  'Generates teacher monthly wage locks/details from actual completed and makeup_completed lessons after requiring locked student monthly settlements for candidate student/month/business groups. Optional p_business_entity_id limits generation and all blockers to one business entity. Writes only wage locks and wage details; no payment, expense, account, income, student settlement, or lesson mutation. Ignores voided wage snapshots/details when checking regeneration blockers.';

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
set search_path = pg_catalog, public
as $$
begin
  perform public.school_require_current_app_admin();

  return query
  select *
  from public.school_generate_teacher_monthly_wage(p_year_month, p_teacher_id, null::uuid);
end;
$$;

comment on function public.school_generate_teacher_monthly_wage(text, uuid) is
  'Backward-compatible wrapper for school_generate_teacher_monthly_wage(text, uuid, uuid) with no business-entity scope.';

revoke all on function public.school_generate_teacher_monthly_wage(text,uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_generate_teacher_monthly_wage(text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_generate_teacher_monthly_wage(text, uuid, uuid) to authenticated;
grant execute on function public.school_generate_teacher_monthly_wage(text, uuid) to authenticated;
