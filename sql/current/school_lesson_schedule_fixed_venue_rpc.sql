-- school_lesson_schedule_fixed_venue_rpc.sql
-- Purpose: Make the DB/RPC venue validator authoritative for fixed onsite venues.
-- Status: EXECUTED ON SCHOOL DB. Rollback-tested and whitelist commit-tested.
-- Version: v10.3.79-fixed-onsite-venue-rpc-20260714
--
-- Scope:
-- - Onsite accepts only Regus公共区 / Regus办公室.
-- - Online may keep an optional free-text platform.
-- - Existing venue-aware write wrappers automatically use this validator.
-- - No business row is written by this file.
--
-- Verification:
-- - Rollback tests confirmed invalid onsite venues are rejected by both RPC and
--   table constraint, online free-text platforms remain valid, legacy venue
--   rows can migrate to a fixed venue, and a downstream core guard rejection
--   atomically rolls back the prepared venue and updated_at change.
-- - Commit test updated only whitelisted codex-test lesson
--   fdbae3f3-a6e3-42a1-9639-47232e742963 to Regus办公室.
-- - Settlement, wage, payment request, income, expense, account, and account
--   transaction counts remained unchanged.

create or replace function public.school_normalize_lesson_schedule_venue(
  p_lesson_delivery_mode text,
  p_lesson_venue text
)
returns table (
  lesson_delivery_mode text,
  lesson_venue text
)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_mode text := nullif(lower(trim(coalesce(p_lesson_delivery_mode, ''))), '');
  v_venue text := nullif(trim(coalesce(p_lesson_venue, '')), '');
begin
  if v_mode is null and v_venue is not null then
    raise exception '填写上课场地前，请先选择授课方式。';
  end if;

  if v_mode is not null and v_mode not in ('onsite', 'online') then
    raise exception '授课方式无效，只能选择线下或线上。';
  end if;

  if v_mode = 'onsite' and v_venue is null then
    raise exception '线下课程必须选择上课场地。';
  end if;

  if v_mode = 'onsite' and v_venue not in ('Regus公共区', 'Regus办公室') then
    raise exception '线下上课场地只能选择 Regus公共区 或 Regus办公室。';
  end if;

  if v_venue is not null and char_length(v_venue) > 100 then
    raise exception '上课场地不能超过 100 个字符。';
  end if;

  return query select v_mode, v_venue;
end;
$$;

comment on function public.school_normalize_lesson_schedule_venue(text, text) is
  'Normalizes explicit lesson delivery mode / venue input. Onsite accepts only Regus公共区 or Regus办公室; online keeps an optional free-text platform.';

revoke all on function public.school_normalize_lesson_schedule_venue(text, text)
from public, anon, authenticated;

grant execute on function public.school_normalize_lesson_schedule_venue(text, text)
to authenticated;

create or replace function public.school_update_lesson_record_guarded_with_venue(
  p_lesson_id uuid,
  p_expected_updated_at timestamptz,
  p_lesson_date date,
  p_student_id uuid,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_business_entity_id uuid,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default 0,
  p_unit_price numeric default 0,
  p_lesson_fee numeric default null,
  p_status text default null,
  p_is_billable boolean default true,
  p_lesson_count integer default null,
  p_lesson_content text default null,
  p_note text default null,
  p_lesson_delivery_mode text default null,
  p_lesson_venue text default null
)
returns setof public.school_lesson_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
  v_mode text;
  v_venue text;
  v_current_updated_at timestamptz;
  v_prepared_updated_at timestamptz;
begin
  if p_lesson_id is null then
    raise exception '请选择要编辑的课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本，请刷新页面后重试。';
  end if;

  select n.lesson_delivery_mode, n.lesson_venue
  into v_mode, v_venue
  from public.school_normalize_lesson_schedule_venue(
    p_lesson_delivery_mode,
    p_lesson_venue
  ) n;

  select l.updated_at
  into v_current_updated_at
  from public.school_lesson_records l
  where l.id = p_lesson_id
    and l.app_type = 'school'
  for update;

  if not found then
    raise exception '课时记录不存在。';
  end if;

  if v_current_updated_at is distinct from p_expected_updated_at then
    raise exception '课时记录已被其他操作更新，请刷新页面后重试。';
  end if;

  -- Prepare the normalized venue before calling the verified core updater.
  -- The table updated_at trigger advances the version, so capture that new
  -- value and pass it to the core optimistic-lock check. If the core rejects
  -- any business guard, this entire function call (including this update)
  -- rolls back atomically.
  update public.school_lesson_records l
  set
    lesson_delivery_mode = v_mode,
    lesson_venue = v_venue
  where l.id = p_lesson_id
  returning l.updated_at into v_prepared_updated_at;

  select u.lesson_id
  into v_lesson_id
  from public.school_update_lesson_record_guarded(
    p_lesson_id,
    v_prepared_updated_at,
    p_lesson_date,
    p_student_id,
    p_teacher_id,
    p_subject_id,
    p_business_entity_id,
    p_start_time,
    p_end_time,
    p_duration_hours,
    p_unit_price,
    p_lesson_fee,
    p_status,
    p_is_billable,
    p_lesson_count,
    p_lesson_content,
    p_note
  ) u;

  return query
  select l.*
  from public.school_lesson_records l
  where l.id = v_lesson_id;
end;
$$;

comment on function public.school_update_lesson_record_guarded_with_venue(
  uuid, timestamptz, date, uuid, uuid, uuid, uuid, text, text, numeric,
  numeric, numeric, text, boolean, integer, text, text, text, text
) is
  'Atomically prepares a normalized venue, then runs the verified guarded lesson updater with the trigger-advanced optimistic-lock version. Any guard rejection rolls back the venue preparation.';

revoke all on function public.school_update_lesson_record_guarded_with_venue(
  uuid, timestamptz, date, uuid, uuid, uuid, uuid, text, text, numeric,
  numeric, numeric, text, boolean, integer, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.school_update_lesson_record_guarded_with_venue(
  uuid, timestamptz, date, uuid, uuid, uuid, uuid, text, text, numeric,
  numeric, numeric, text, boolean, integer, text, text, text, text
) to authenticated;
