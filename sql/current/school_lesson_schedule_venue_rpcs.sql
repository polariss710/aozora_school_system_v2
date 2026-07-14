-- school_lesson_schedule_venue_rpcs.sql
-- Purpose: Add guarded lesson venue-aware write entry points while preserving
--          the existing lesson business guards and historical rows.
-- Status: EXECUTED ON SCHOOL DB. Rollback-tested and whitelist commit-tested.
-- Version: v10.3.76-lesson-schedule-venue-rpcs-20260714
--
-- Scope:
-- - New venue-aware wrappers call the already verified core lesson RPCs.
-- - Existing RPC signatures remain available for compatibility.
-- - Actual rows created from planned rows inherit the planned venue only when
--   both target venue fields are NULL.
-- - No historical backfill, settlement, wage, income, expense, Cash, account,
--   or account-transaction write is performed.
--
-- Verification:
-- - Rollback tests covered single create/update, actual-row inheritance, batch
--   generation, planned-only import, and invalid onsite venue rejection; all
--   four generated rollback IDs left zero residue.
-- - Commit test inserted only whitelisted codex-test planned lesson
--   fdbae3f3-a6e3-42a1-9639-47232e742963.
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
    raise exception '线下课程必须填写上课场地。';
  end if;

  if v_venue is not null and char_length(v_venue) > 100 then
    raise exception '上课场地不能超过 100 个字符。';
  end if;

  return query select v_mode, v_venue;
end;
$$;

comment on function public.school_normalize_lesson_schedule_venue(text, text) is
  'Normalizes and validates explicit lesson delivery mode / venue input. It does not read or write business data.';

revoke all on function public.school_normalize_lesson_schedule_venue(text, text)
from public, anon, authenticated;

grant execute on function public.school_normalize_lesson_schedule_venue(text, text)
to authenticated;

create or replace function public.school_create_planned_lesson_record_with_venue(
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
  p_status text default 'planned',
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
begin
  select n.lesson_delivery_mode, n.lesson_venue
  into v_mode, v_venue
  from public.school_normalize_lesson_schedule_venue(
    p_lesson_delivery_mode,
    p_lesson_venue
  ) n;

  select c.lesson_id
  into v_lesson_id
  from public.school_create_planned_lesson_record(
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
    p_lesson_count,
    p_lesson_content,
    p_note
  ) c;

  update public.school_lesson_records l
  set
    lesson_delivery_mode = v_mode,
    lesson_venue = v_venue,
    updated_at = now()
  where l.id = v_lesson_id;

  return query
  select l.*
  from public.school_lesson_records l
  where l.id = v_lesson_id;
end;
$$;

comment on function public.school_create_planned_lesson_record_with_venue(
  date, uuid, uuid, uuid, uuid, text, text, numeric, numeric, numeric,
  text, integer, text, text, text, text
) is
  'Creates one planned lesson through the verified core RPC, then stores normalized explicit delivery mode / venue in the same transaction.';

revoke all on function public.school_create_planned_lesson_record_with_venue(
  date, uuid, uuid, uuid, uuid, text, text, numeric, numeric, numeric,
  text, integer, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.school_create_planned_lesson_record_with_venue(
  date, uuid, uuid, uuid, uuid, text, text, numeric, numeric, numeric,
  text, integer, text, text, text, text
) to authenticated;

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
begin
  select n.lesson_delivery_mode, n.lesson_venue
  into v_mode, v_venue
  from public.school_normalize_lesson_schedule_venue(
    p_lesson_delivery_mode,
    p_lesson_venue
  ) n;

  select u.lesson_id
  into v_lesson_id
  from public.school_update_lesson_record_guarded(
    p_lesson_id,
    p_expected_updated_at,
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

  update public.school_lesson_records l
  set
    lesson_delivery_mode = v_mode,
    lesson_venue = v_venue,
    updated_at = now()
  where l.id = v_lesson_id;

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
  'Updates one lesson through the verified guarded core RPC, then stores normalized explicit delivery mode / venue in the same transaction.';

revoke all on function public.school_update_lesson_record_guarded_with_venue(
  uuid, timestamptz, date, uuid, uuid, uuid, uuid, text, text, numeric,
  numeric, numeric, text, boolean, integer, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.school_update_lesson_record_guarded_with_venue(
  uuid, timestamptz, date, uuid, uuid, uuid, uuid, text, text, numeric,
  numeric, numeric, text, boolean, integer, text, text, text, text
) to authenticated;

create or replace function public.school_generate_planned_lessons_batch_with_venue(
  p_generation_id uuid,
  p_student_id uuid,
  p_business_entity_id uuid,
  p_start_date date,
  p_end_date date,
  p_patterns jsonb,
  p_excluded_occurrences jsonb default '[]'::jsonb,
  p_note text default null
)
returns table (
  row_index integer,
  pattern_index integer,
  lesson_date date,
  row_valid boolean,
  batch_committed boolean,
  created_lesson_id uuid,
  status text,
  warnings text[],
  errors text[],
  generation_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_pattern jsonb;
  v_mode text;
  v_venue text;
begin
  if p_patterns is null or jsonb_typeof(p_patterns) <> 'array' then
    raise exception '课程规则必须是 JSON array。';
  end if;

  for v_pattern in
    select value
    from jsonb_array_elements(p_patterns)
  loop
    perform 1
    from public.school_normalize_lesson_schedule_venue(
      v_pattern ->> 'lesson_delivery_mode',
      v_pattern ->> 'lesson_venue'
    );
  end loop;

  for v_result in
    select *
    from public.school_generate_planned_lessons_batch(
      p_generation_id,
      p_student_id,
      p_business_entity_id,
      p_start_date,
      p_end_date,
      p_patterns,
      p_excluded_occurrences,
      p_note
    )
  loop
    if v_result.batch_committed and v_result.created_lesson_id is not null then
      select value
      into v_pattern
      from jsonb_array_elements(p_patterns)
      where (value ->> 'pattern_index')::integer = v_result.pattern_index
      limit 1;

      if not found then
        raise exception '无法匹配批量生成结果的课程规则：pattern_index=%。',
          v_result.pattern_index;
      end if;

      select n.lesson_delivery_mode, n.lesson_venue
      into v_mode, v_venue
      from public.school_normalize_lesson_schedule_venue(
        v_pattern ->> 'lesson_delivery_mode',
        v_pattern ->> 'lesson_venue'
      ) n;

      update public.school_lesson_records l
      set
        lesson_delivery_mode = v_mode,
        lesson_venue = v_venue,
        updated_at = now()
      where l.id = v_result.created_lesson_id;
    end if;

    row_index := v_result.row_index;
    pattern_index := v_result.pattern_index;
    lesson_date := v_result.lesson_date;
    row_valid := v_result.row_valid;
    batch_committed := v_result.batch_committed;
    created_lesson_id := v_result.created_lesson_id;
    status := v_result.status;
    warnings := v_result.warnings;
    errors := v_result.errors;
    generation_id := v_result.generation_id;
    return next;
  end loop;
end;
$$;

comment on function public.school_generate_planned_lessons_batch_with_venue(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text
) is
  'Runs verified planned-lesson batch generation, then stores each pattern explicit delivery mode / venue on its created rows in the same transaction.';

revoke all on function public.school_generate_planned_lessons_batch_with_venue(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text
) from public, anon, authenticated;

grant execute on function public.school_generate_planned_lessons_batch_with_venue(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text
) to authenticated;

create or replace function public.school_import_lesson_records_batch_with_venue(
  p_import_batch_id uuid,
  p_source_file_name text,
  p_source_file_hash text,
  p_rows jsonb,
  p_note text default null
)
returns table (
  row_index integer,
  source_row_no integer,
  row_valid boolean,
  batch_committed boolean,
  created_lesson_id uuid,
  lesson_type text,
  status text,
  planned_lesson_id uuid,
  warnings text[],
  errors text[],
  import_batch_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_row jsonb;
  v_mode text;
  v_venue text;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows 必须是 JSON array。';
  end if;

  for v_row in
    select value
    from jsonb_array_elements(p_rows)
  loop
    perform 1
    from public.school_normalize_lesson_schedule_venue(
      v_row ->> 'lesson_delivery_mode',
      v_row ->> 'lesson_venue'
    );
  end loop;

  for v_result in
    select *
    from public.school_import_lesson_records_batch(
      p_import_batch_id,
      p_source_file_name,
      p_source_file_hash,
      p_rows,
      p_note
    )
  loop
    if v_result.batch_committed and v_result.created_lesson_id is not null then
      select value
      into v_row
      from jsonb_array_elements(p_rows)
      where (value ->> 'row_index')::integer = v_result.row_index
      limit 1;

      if not found then
        raise exception '无法匹配批量导入结果行：row_index=%。',
          v_result.row_index;
      end if;

      select n.lesson_delivery_mode, n.lesson_venue
      into v_mode, v_venue
      from public.school_normalize_lesson_schedule_venue(
        v_row ->> 'lesson_delivery_mode',
        v_row ->> 'lesson_venue'
      ) n;

      update public.school_lesson_records l
      set
        lesson_delivery_mode = v_mode,
        lesson_venue = v_venue,
        updated_at = now()
      where l.id = v_result.created_lesson_id;
    end if;

    row_index := v_result.row_index;
    source_row_no := v_result.source_row_no;
    row_valid := v_result.row_valid;
    batch_committed := v_result.batch_committed;
    created_lesson_id := v_result.created_lesson_id;
    lesson_type := v_result.lesson_type;
    status := v_result.status;
    planned_lesson_id := v_result.planned_lesson_id;
    warnings := v_result.warnings;
    errors := v_result.errors;
    import_batch_id := v_result.import_batch_id;
    return next;
  end loop;
end;
$$;

comment on function public.school_import_lesson_records_batch_with_venue(
  uuid, text, text, jsonb, text
) is
  'Runs verified planned-only lesson import, then stores each row explicit delivery mode / venue on its created row in the same transaction.';

revoke all on function public.school_import_lesson_records_batch_with_venue(
  uuid, text, text, jsonb, text
) from public, anon, authenticated;

grant execute on function public.school_import_lesson_records_batch_with_venue(
  uuid, text, text, jsonb, text
) to authenticated;

create or replace function public.school_lesson_inherit_schedule_venue()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.lesson_type = 'actual'
     and new.planned_lesson_id is not null
     and new.lesson_delivery_mode is null
     and new.lesson_venue is null then
    select
      p.lesson_delivery_mode,
      p.lesson_venue
    into
      new.lesson_delivery_mode,
      new.lesson_venue
    from public.school_lesson_records p
    where p.id = new.planned_lesson_id
      and p.lesson_type = 'planned';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'trg_school_lesson_inherit_schedule_venue'
      and tgrelid = 'public.school_lesson_records'::regclass
      and not tgisinternal
  ) then
    create trigger trg_school_lesson_inherit_schedule_venue
      before insert on public.school_lesson_records
      for each row
      execute function public.school_lesson_inherit_schedule_venue();
  end if;
end
$$;

comment on function public.school_lesson_inherit_schedule_venue() is
  'Before insert, inherits planned delivery mode / venue into a linked actual only when both target venue fields are NULL.';

revoke all on function public.school_lesson_inherit_schedule_venue()
from public, anon, authenticated;
