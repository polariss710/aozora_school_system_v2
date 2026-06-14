-- school_create_subject_profile_rpc.sql
-- RPC: public.school_create_subject_profile
-- Purpose: Create future-use subject master data only.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.44.0-subject-create-full-autopilot-20260606
--
-- Scope:
-- - Insert one row into public.school_subjects.
-- - Allowed fields: name, category, color, sort_order, is_active via status,
--   note, primary_category, tertiary_category.
-- - The current schema has no display_name/status columns; display name maps
--   to school_subjects.name and status maps to is_active.
--
-- Not supported:
-- - Deleting, merging, or replacing subjects.
-- - Editing historical lesson, settlement, wage, payment, income, expense, or
--   account transaction records.
-- - Recalculating historical data.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - public.school_subjects.name has unique constraint school_subjects_name_key.
-- - Rollback test inserted one codex-test subject and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox subject
--   a4147872-7b2c-4ec2-a26e-24af44311fce.
-- - Duplicate subject name is rejected.
-- - Historical lesson, settlement, wage, payment, income, expense, and account
--   transaction counts stayed unchanged.

create or replace function public.school_create_subject_profile(
  p_name text,
  p_status text default 'active',
  p_category text default null,
  p_primary_category text default null,
  p_tertiary_category text default null,
  p_color text default null,
  p_sort_order integer default null,
  p_note text default null
)
returns table (
  subject_id uuid,
  name text,
  status text,
  is_active boolean,
  category text,
  primary_category text,
  tertiary_category text,
  color text,
  sort_order integer,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_status text := nullif(trim(coalesce(p_status, 'active')), '');
  v_is_active boolean;
  v_category text := nullif(trim(coalesce(p_category, '')), '');
  v_primary_category text := nullif(trim(coalesce(p_primary_category, '')), '');
  v_tertiary_category text := nullif(trim(coalesce(p_tertiary_category, '')), '');
  v_color text := nullif(trim(coalesce(p_color, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_sort_order integer := coalesce(p_sort_order, 0);
  v_subject_id uuid;
begin
  if v_name is null then
    raise exception '科目名称不能为空。';
  end if;

  if v_status is null then
    raise exception '科目状态不能为空。';
  end if;

  if v_status not in ('active', 'inactive') then
    raise exception '科目状态无效：%。', v_status;
  end if;

  if v_color is not null and v_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception '科目颜色格式无效，请使用 #RRGGBB。';
  end if;

  if v_sort_order < 0 then
    raise exception '科目排序不能小于 0。';
  end if;

  if exists (
    select 1
    from public.school_subjects s
    where s.name = v_name
  ) then
    raise exception '科目名称已存在：%。', v_name;
  end if;

  v_is_active := v_status = 'active';
  v_primary_category := coalesce(v_primary_category, '班课');

  insert into public.school_subjects (
    name,
    category,
    color,
    sort_order,
    is_active,
    note,
    primary_category,
    tertiary_category
  )
  values (
    v_name,
    v_category,
    v_color,
    v_sort_order,
    v_is_active,
    v_note,
    v_primary_category,
    v_tertiary_category
  )
  returning id into v_subject_id;

  return query
  select
    s.id,
    s.name,
    case when s.is_active then 'active' else 'inactive' end,
    s.is_active,
    s.category,
    s.primary_category,
    s.tertiary_category,
    s.color,
    s.sort_order,
    s.note,
    s.created_at,
    s.updated_at
  from public.school_subjects s
  where s.id = v_subject_id;
exception
  when unique_violation then
    raise exception '科目名称已存在：%。', v_name;
end;
$$;

comment on function public.school_create_subject_profile(
  text,
  text,
  text,
  text,
  text,
  text,
  integer,
  text
) is
  'Creates one future-use school subject master row. Does not modify historical lessons, settlements, wages, payments, income, expenses, or account transactions.';

-- Permission note:
-- Keep execute permission management explicit. Review permissions separately
-- before enabling this function for authenticated users.
