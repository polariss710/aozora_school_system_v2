-- school_void_planned_lesson_rpc.sql
-- RPC: public.school_void_planned_lesson
-- Purpose: Soft-void one planned-only lesson record.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, guard-tested, and commit-tested.
-- Version: v2.63.0-lesson-planned-void-schema-rpc-20260609
--
-- Scope:
-- - Update one public.school_lesson_records row only.
-- - Preserve lesson_type, status, planned_lesson_id, import_batch_id,
--   import_source, and imported_at.
-- - Express void state only through voided_at is not null.
--
-- Guards:
-- - lesson_type must be planned.
-- - status must be planned or pending_makeup.
-- - voided_at must be null.
-- - No linked actual may exist.
-- - Matching student monthly settlement month must not be locked.
-- - updated_at optimistic lock must match.
-- - void_reason must be non-empty.

create or replace function public.school_void_planned_lesson(
  p_lesson_id uuid,
  p_expected_updated_at timestamptz,
  p_void_reason text
)
returns table (
  lesson_id uuid,
  lesson_type text,
  status text,
  voided_at timestamptz,
  void_reason text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson public.school_lesson_records%rowtype;
  v_reason text := nullif(trim(coalesce(p_void_reason, '')), '');
begin
  if p_lesson_id is null then
    raise exception '请选择要作废的预定课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本信息，请刷新后重试。';
  end if;

  if v_reason is null then
    raise exception '请填写作废原因。';
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
    raise exception '只能作废 planned 预定课时。';
  end if;

  if v_lesson.status not in ('planned', 'pending_makeup') then
    raise exception '当前 planned 状态不允许作废：%。', coalesce(v_lesson.status, '');
  end if;

  if v_lesson.voided_at is not null then
    raise exception '该预定课时已作废。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_lesson.id
  ) then
    raise exception '该预定课时已有 actual 关联，不能作废。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_lesson.student_id
      and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(
        v_lesson.id
      )
      and s.business_entity_id is not distinct from v_lesson.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能作废预定课时。';
  end if;

  update public.school_lesson_records l
  set
    voided_at = now(),
    void_reason = v_reason
  where l.id = v_lesson.id;

  return query
  select
    l.id,
    l.lesson_type,
    l.status,
    l.voided_at,
    l.void_reason,
    l.updated_at
  from public.school_lesson_records l
  where l.id = v_lesson.id;
end;
$$;

comment on function public.school_void_planned_lesson(uuid, timestamptz, text) is
  'Soft-voids one planned-only school lesson using voided_at/void_reason. Preserves status/import metadata and rejects linked actuals, locked student settlement months, already-voided rows, stale updated_at, and non-planned lessons.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
