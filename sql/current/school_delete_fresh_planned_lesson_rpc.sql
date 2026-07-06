-- school_delete_fresh_planned_lesson_rpc.sql
-- RPC: public.school_delete_fresh_planned_lesson
-- Purpose:
--   Physically delete exactly one fresh planned school lesson.
--
-- Scope:
-- - Deletes one row from public.school_lesson_records by id only.
-- - Does not delete actual lessons, settlements, wage snapshots, tuition bills,
--   income records, expense records, account transactions, or Cash records.
--
-- Guards:
-- - Operator must explicitly pass p_confirm_delete = true.
-- - Target row must be app_type = school, lesson_type = planned, status = planned.
-- - Target row must not be voided and must have no planned_lesson_id.
-- - expected updated_at must match.
-- - No actual lesson may reference it through planned_lesson_id.
-- - No student monthly settlement, adjustment draft, or adjustment may exist for
--   the same student/month/business entity.
-- - No teacher wage lock detail may reference it through lesson_record_id.
-- - No student tuition bill or income record source_snapshot may contain the
--   planned lesson id.

create or replace function public.school_delete_fresh_planned_lesson(
  p_lesson_id uuid,
  p_expected_updated_at timestamptz,
  p_confirm_delete boolean default false
)
returns table (
  lesson_id uuid,
  lesson_date date,
  year_month text,
  student_id uuid,
  teacher_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson public.school_lesson_records%rowtype;
  v_deleted_at timestamptz := now();
begin
  if p_lesson_id is null then
    raise exception '请选择要删除的预定课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本信息，请刷新后重试。';
  end if;

  if p_confirm_delete is distinct from true then
    raise exception '请确认删除预定课时。';
  end if;

  select l.*
  into v_lesson
  from public.school_lesson_records l
  where l.id = p_lesson_id
    and l.app_type = 'school'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;

  if v_lesson.updated_at is distinct from p_expected_updated_at then
    raise exception '课时已被其他操作更新，请刷新后重试。';
  end if;

  if v_lesson.lesson_type <> 'planned' then
    raise exception '只能删除 planned 预定课时。';
  end if;

  if v_lesson.status <> 'planned' then
    raise exception '只有全新的待上课预定课时可以删除；当前状态为：%。', coalesce(v_lesson.status, '');
  end if;

  if v_lesson.voided_at is not null then
    raise exception '该预定课时已作废，不能删除。';
  end if;

  if v_lesson.planned_lesson_id is not null then
    raise exception '该预定课时存在来源关联，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_lesson.id
  ) then
    raise exception '该预定课时已有实际课时、取消课或补课完成记录，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_lesson.student_id
      and s.year_month = coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'))
      and s.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算记录，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_adjustment_drafts d
    where d.app_type = 'school'
      and d.student_id = v_lesson.student_id
      and d.year_month = coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'))
      and d.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算调整草稿，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_adjustments a
    where a.app_type = 'school'
      and a.student_id = v_lesson.student_id
      and a.year_month = coalesce(v_lesson.year_month, to_char(v_lesson.lesson_date, 'YYYY-MM'))
      and a.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算调整记录，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details d
    where d.lesson_record_id = v_lesson.id
  ) then
    raise exception '该课时已进入老师工资快照明细，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bills b
    where exists (
      select 1
      from jsonb_array_elements_text(coalesce(b.source_snapshot->'planned_lesson_ids', '[]'::jsonb)) ids(lesson_id)
      where ids.lesson_id = v_lesson.id::text
    )
  ) then
    raise exception '该预定课时已进入学生学费应收快照，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_income_records i
    where i.app_type = 'school'
      and exists (
        select 1
        from jsonb_array_elements_text(coalesce(i.source_snapshot->'planned_lesson_ids', '[]'::jsonb)) ids(lesson_id)
        where ids.lesson_id = v_lesson.id::text
      )
  ) then
    raise exception '该预定课时已进入收入记录快照，不能删除。';
  end if;

  delete from public.school_lesson_records l
  where l.id = v_lesson.id;

  return query
  select
    v_lesson.id,
    v_lesson.lesson_date,
    v_lesson.year_month,
    v_lesson.student_id,
    v_lesson.teacher_id,
    v_lesson.subject_id,
    v_lesson.business_entity_id,
    v_deleted_at;
end;
$$;

comment on function public.school_delete_fresh_planned_lesson(uuid, timestamptz, boolean) is
  'Deletes exactly one fresh planned school lesson. Requires explicit confirmation and rejects non-planned status, voided rows, linked actuals, student settlement/adjustment records, teacher wage detail snapshots, tuition bill snapshots, and income snapshots.';

revoke all on function public.school_delete_fresh_planned_lesson(uuid, timestamptz, boolean)
from public, anon, authenticated;

grant execute on function public.school_delete_fresh_planned_lesson(uuid, timestamptz, boolean)
to authenticated;
