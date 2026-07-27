-- school_tuition_r0_august_2026_baseline_readonly.sql
-- R0 read-only audit for all seven School students and 2026-08 planned lessons.
-- This file contains SELECT statements only and must never modify data.

with students as (
  select
    s.id as student_id,
    coalesce(s.display_name, s.name) as student_name,
    s.status as student_status,
    s.business_entity_id as current_business_entity_id,
    be.name as current_business_entity
  from public.school_students s
  left join public.school_business_entities be on be.id = s.business_entity_id
  where s.app_type = 'school'
),
august_planned as (
  select
    l.*,
    s.current_business_entity_id,
    exists (
      select 1
      from public.school_student_tuition_bills bill
      cross join lateral jsonb_array_elements_text(
        coalesce(bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
      ) snapshot_lesson(id)
      where snapshot_lesson.id = l.id::text
    ) as in_historical_bill,
    exists (
      select 1
      from public.school_student_tuition_bills bill
      join public.school_income_records income on income.id = bill.income_record_id
      cross join lateral jsonb_array_elements_text(
        coalesce(bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
      ) snapshot_lesson(id)
      where snapshot_lesson.id = l.id::text
        and income.status = 'received'
        and exists (
          select 1
          from public.school_personal_cash_income_linkage_events event
          where event.income_record_id = income.id
            and event.sync_status = 'synced'
        )
    ) as in_received_cash_bill,
    exists (
      select 1
      from public.school_lesson_records actual
      where actual.planned_lesson_id = l.id
        and actual.lesson_type = 'actual'
        and actual.voided_at is null
    ) as has_actual,
    exists (
      select 1
      from public.school_lesson_records actual
      join public.school_teacher_wage_lock_details detail
        on detail.lesson_record_id = actual.id
      join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
      where actual.planned_lesson_id = l.id
        and wage.status <> 'void'
    ) as in_active_wage
  from public.school_lesson_records l
  join students s on s.student_id = l.student_id
  where l.app_type = 'school'
    and l.year_month = '2026-08'
    and l.lesson_type = 'planned'
    and l.voided_at is null
    and coalesce(l.status, '') not in ('cancelled', 'voided', 'void')
),
summary as (
  select
    s.student_id,
    s.student_name,
    s.student_status,
    s.current_business_entity,
    count(p.id)::integer as august_planned_total,
    count(p.id) filter (
      where p.business_entity_id = s.current_business_entity_id
    )::integer as current_preview_candidate_count,
    coalesce(sum(p.duration_hours), 0)::numeric as total_hours,
    coalesce(sum(p.lesson_fee), 0)::numeric as total_jpy,
    count(p.id) filter (
      where p.business_entity_id = (
        select id from public.school_business_entities where name = '个人名义' limit 1
      )
    )::integer as personal_lesson_count,
    count(p.id) filter (
      where p.business_entity_id = (
        select id from public.school_business_entities where name = '青空进学塾' limit 1
      )
    )::integer as aosora_lesson_count,
    count(p.id) filter (where p.in_historical_bill)::integer as historical_bill_lesson_count,
    count(p.id) filter (where p.in_received_cash_bill)::integer as received_cash_bill_lesson_count,
    count(p.id) filter (where p.has_actual)::integer as actual_lesson_count,
    count(p.id) filter (where p.in_active_wage)::integer as active_wage_lesson_count,
    count(p.id) filter (
      where p.business_entity_id is distinct from s.current_business_entity_id
    )::integer as business_entity_mismatch_count,
    count(p.id) filter (
      where p.in_received_cash_bill
        and exists (
          select 1
          from public.school_student_tuition_bills bill
          cross join lateral jsonb_array_elements_text(
            coalesce(bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
          ) snapshot_lesson(id)
          where snapshot_lesson.id = p.id::text
            and bill.billing_month <> '2026-08'
        )
    )::integer as month_drift_duplicate_count
  from students s
  left join august_planned p on p.student_id = s.student_id
  group by
    s.student_id,
    s.student_name,
    s.student_status,
    s.current_business_entity,
    s.current_business_entity_id
)
select
  student_name as "学生",
  student_id,
  current_business_entity as "当前业务归属",
  august_planned_total as "8月planned总数",
  current_preview_candidate_count as "当前候选数",
  total_hours as "小时",
  total_jpy as "JPY金额",
  personal_lesson_count as "personal课时",
  aosora_lesson_count as "青空课时",
  historical_bill_lesson_count as "已进入历史账单",
  actual_lesson_count as "有actual",
  case
    when august_planned_total = 0 then '无8月planned'
    when month_drift_duplicate_count > 0 then format('字段尚不存在；%s条存在跨月账单冲突', month_drift_duplicate_count)
    else '字段尚不存在；批量生成记录可按原始周一分类审计'
  end as "week anchor状态",
  case
    when august_planned_total - received_cash_bill_lesson_count > 0
      then format('是：%s条未进入received/Cash synced账单', august_planned_total - received_cash_bill_lesson_count)
    else '否：无未收费候选'
  end as "预期是否可收费",
  concat_ws(
    '；',
    case when business_entity_mismatch_count > 0 then format('业务归属不一致%s条', business_entity_mismatch_count) end,
    case when received_cash_bill_lesson_count > 0 then format('旧候选未排除已Cash收费%s条', received_cash_bill_lesson_count) end,
    case when month_drift_duplicate_count > 0 then format('月份漂移重复风险%s条', month_drift_duplicate_count) end,
    case when actual_lesson_count > 0 then format('已有actual%s条', actual_lesson_count) end,
    case when active_wage_lesson_count > 0 then format('已有工资关系%s条', active_wage_lesson_count) end
  ) as "异常"
from summary
order by "学生", student_id;

-- Future date-field backfill classification. The new columns intentionally do
-- not exist in R0; these counts are evidence only.
with august_planned as (
  select l.*,
    exists (
      select 1
      from public.school_student_tuition_bills bill
      cross join lateral jsonb_array_elements_text(
        coalesce(bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
      ) snapshot_lesson(id)
      where snapshot_lesson.id = l.id::text
    ) as in_formal_bill,
    exists (
      select 1
      from public.school_student_tuition_bills bill
      cross join lateral jsonb_array_elements_text(
        coalesce(bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
      ) snapshot_lesson(id)
      where snapshot_lesson.id = l.id::text
        and bill.billing_month <> '2026-08'
    ) as billing_month_conflict
  from public.school_lesson_records l
  where l.app_type = 'school'
    and l.year_month = '2026-08'
    and l.lesson_type = 'planned'
    and l.voided_at is null
    and coalesce(l.status, '') not in ('cancelled', 'voided', 'void')
)
select classification, count(*)::integer as lesson_count
from (
  select case
    when billing_month_conflict then '证据冲突，需要人工确认；不属于8月收费范围'
    when in_formal_bill then '已进入正式账单，可由账单和生成批次确定'
    when import_source like 'lesson_planned_batch_generator%'
      and updated_at = created_at then '可根据批量生成原始周一高置信度回填'
    when updated_at <> created_at then '经过用户编辑，不能只靠当前lesson_date回填'
    else '证据不足，需要人工确认'
  end as classification
  from august_planned
) classified
group by classification
order by classification;
