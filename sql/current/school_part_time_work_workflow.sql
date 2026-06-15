-- school_part_time_work_workflow.sql
-- Purpose: Replace the incorrect V1 one-row wage record model with the
-- planned lesson -> actual lesson -> monthly settlement -> School income request workflow.
-- Status: executed on School DB 2026-06-15; verified by read-only schema/RPC/grant inspection.
--
-- Scope:
-- - Drops the obsolete school_part_time_work_records V1 table and RPCs.
-- - Creates School-side external part-time work lessons, monthly settlements,
--   settlement detail snapshots, and School-side income requests.
-- - lesson_count and cumulative_hours are display-only progress fields and do not
--   enter monthly wage calculation.
-- - Locked Excel export reads settlement detail snapshots only.
-- - Does not write Cash DB, call Cash RPCs, or create Cash transactions.
-- - Does not reference students, lesson management, teacher_wage, or payment requests.
-- - All page-facing RPC execute grants are authenticated-only; anon is intentionally not granted.

begin;

drop function if exists public.school_get_part_time_work_settlement_export(uuid);
drop function if exists public.school_create_part_time_work_income_request(uuid);
drop function if exists public.school_unlock_part_time_work_monthly_settlement(uuid);
drop function if exists public.school_lock_part_time_work_monthly_settlement(uuid);
drop function if exists public.school_lock_part_time_work_monthly_settlement(text, text, integer, text);
drop function if exists public.school_save_part_time_work_monthly_settlement(text, text, integer, text);
drop function if exists public.school_save_part_time_work_monthly_settlement(text, text, integer, integer, text);
drop function if exists public.school_save_part_time_work_monthly_settlement(text, text, integer, integer, integer, text);
drop function if exists public.school_list_part_time_work_monthly_settlements(text);
drop function if exists public.school_delete_part_time_work_lesson(uuid, boolean);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, integer, numeric, integer, integer, text);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, text, integer, integer, integer, text);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, integer, integer, integer, text);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, integer, integer, text);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, numeric, integer, integer, text);
drop function if exists public.school_generate_part_time_work_actual_from_planned(uuid, date, numeric, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, integer, numeric, integer, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, text, integer, integer, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, integer, integer, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, integer, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, text, text, text, numeric, integer, integer, text);
drop function if exists public.school_update_part_time_work_lesson(uuid, date, text, text, text, numeric, integer, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, integer, numeric, integer, integer, text, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, text, integer, integer, integer, text, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, integer, integer, integer, text, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, integer, integer, text, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, text, text, text, numeric, integer, integer, text, text);
drop function if exists public.school_create_part_time_work_planned_lesson(date, text, text, text, numeric, integer, text, text);
drop function if exists public.school_list_part_time_work_lessons(text, text, text);
drop function if exists public.school_part_time_work_calculate_hours(time, time);

drop function if exists public.school_get_part_time_work_monthly_stats(text);
drop function if exists public.school_delete_part_time_work_record(uuid);
drop function if exists public.school_update_part_time_work_record(uuid, date, text, text, text, text, numeric, integer, integer, integer, text, date, text);
drop function if exists public.school_create_part_time_work_record(date, text, text, text, text, numeric, integer, integer, integer, text, date, text);
drop function if exists public.school_list_part_time_work_records(text, text, text);
drop function if exists public.school_part_time_work_normalize_status(text);
drop table if exists public.school_part_time_work_records;

create table if not exists public.school_part_time_work_lessons (
  id uuid primary key default gen_random_uuid(),
  record_kind text not null,
  planned_lesson_id uuid references public.school_part_time_work_lessons(id),
  work_date date not null,
  start_time time,
  end_time time,
  year_month text not null,
  workplace_name text not null,
  teacher_name text not null default '吴峰',
  subject_name text not null,
  class_description text,
  planned_hours numeric(8,2) not null default 0,
  actual_hours numeric(8,2) not null default 0,
  lesson_count integer not null default 1,
  cumulative_hours numeric(8,2) not null default 0,
  hourly_rate_jpy integer not null default 0,
  lesson_wage_jpy integer not null default 0,
  transportation_fee_jpy integer not null default 0,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.school_part_time_work_lessons
  add column if not exists start_time time,
  add column if not exists end_time time,
  add column if not exists lesson_count integer not null default 1,
  add column if not exists cumulative_hours numeric(8,2) not null default 0,
  add column if not exists transportation_fee_jpy integer not null default 0,
  drop column if exists course_group_name;

alter table public.school_part_time_work_lessons
  drop constraint if exists school_part_time_work_lessons_record_kind_check,
  drop constraint if exists school_part_time_work_lessons_year_month_check,
  drop constraint if exists school_part_time_work_lessons_workplace_check,
  drop constraint if exists school_part_time_work_lessons_subject_check,
  drop constraint if exists school_part_time_work_lessons_hours_check,
  drop constraint if exists school_part_time_work_lessons_time_check,
  drop constraint if exists school_part_time_work_lessons_count_check,
  drop constraint if exists school_part_time_work_lessons_cumulative_hours_check,
  drop constraint if exists school_part_time_work_lessons_rate_check,
  drop constraint if exists school_part_time_work_lessons_wage_check,
  drop constraint if exists school_part_time_work_lessons_transportation_check,
  drop constraint if exists school_part_time_work_lessons_kind_pair_check,
  add constraint school_part_time_work_lessons_record_kind_check
    check (record_kind in ('planned', 'actual')),
  add constraint school_part_time_work_lessons_year_month_check
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  add constraint school_part_time_work_lessons_workplace_check
    check (workplace_name in ('诺应教育', '致远教育', '新领域')),
  add constraint school_part_time_work_lessons_subject_check
    check (subject_name in ('EJU文数班课', 'EJU理数班课', 'EJU文数一对一', 'EJU理数一对一', '大学院一对一')),
  add constraint school_part_time_work_lessons_hours_check
    check (planned_hours >= 0 and actual_hours >= 0),
  add constraint school_part_time_work_lessons_time_check
    check (
      deleted_at is not null
      or (start_time is not null and end_time is not null and end_time > start_time)
    ),
  add constraint school_part_time_work_lessons_count_check
    check (lesson_count >= 1),
  add constraint school_part_time_work_lessons_cumulative_hours_check
    check (cumulative_hours >= 0),
  add constraint school_part_time_work_lessons_rate_check
    check (hourly_rate_jpy >= 0),
  add constraint school_part_time_work_lessons_wage_check
    check (lesson_wage_jpy >= 0),
  add constraint school_part_time_work_lessons_transportation_check
    check (transportation_fee_jpy >= 0),
  add constraint school_part_time_work_lessons_kind_pair_check
    check (
      (record_kind = 'planned' and planned_lesson_id is null and actual_hours = 0 and lesson_wage_jpy = 0)
      or (record_kind = 'actual' and planned_lesson_id is not null and planned_hours = 0)
    );

create unique index if not exists school_part_time_work_actual_one_active_per_planned_idx
  on public.school_part_time_work_lessons (planned_lesson_id)
  where record_kind = 'actual' and deleted_at is null;

create index if not exists school_part_time_work_lessons_month_kind_idx
  on public.school_part_time_work_lessons (year_month, record_kind, work_date)
  where deleted_at is null;

create index if not exists school_part_time_work_lessons_workplace_idx
  on public.school_part_time_work_lessons (workplace_name, year_month)
  where deleted_at is null;

create table if not exists public.school_part_time_work_monthly_settlements (
  id uuid primary key default gen_random_uuid(),
  year_month text not null,
  workplace_name text not null,
  teacher_name text not null default '吴峰',
  currency text not null default 'JPY',
  actual_lesson_count integer not null default 0,
  actual_hours_total numeric(10,2) not null default 0,
  hourly_rate_jpy integer not null default 0,
  lesson_wage_jpy integer not null default 0,
  transportation_fee_jpy integer not null default 0,
  adjustment_jpy integer not null default 0,
  total_wage_jpy integer not null default 0,
  status text not null default 'draft',
  income_request_id uuid,
  locked_at timestamptz,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.school_part_time_work_monthly_settlements
  drop constraint if exists school_part_time_work_settlements_year_month_check,
  drop constraint if exists school_part_time_work_settlements_workplace_check,
  drop constraint if exists school_part_time_work_settlements_currency_check,
  drop constraint if exists school_part_time_work_settlements_amount_check,
  drop constraint if exists school_part_time_work_settlements_status_check,
  add constraint school_part_time_work_settlements_year_month_check
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  add constraint school_part_time_work_settlements_workplace_check
    check (workplace_name in ('诺应教育', '致远教育', '新领域')),
  add constraint school_part_time_work_settlements_currency_check
    check (currency = 'JPY'),
  add constraint school_part_time_work_settlements_amount_check
    check (
      actual_lesson_count >= 0
      and actual_hours_total >= 0
      and hourly_rate_jpy >= 0
      and lesson_wage_jpy >= 0
      and transportation_fee_jpy >= 0
      and total_wage_jpy >= 0
    ),
  add constraint school_part_time_work_settlements_status_check
    check (status in ('draft', 'locked', 'income_request_created'));

create unique index if not exists school_part_time_work_settlements_month_workplace_active_idx
  on public.school_part_time_work_monthly_settlements (year_month, workplace_name)
  where deleted_at is null;

create table if not exists public.school_part_time_work_monthly_settlement_details (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.school_part_time_work_monthly_settlements(id),
  actual_lesson_id uuid not null references public.school_part_time_work_lessons(id),
  work_date date not null,
  start_time time not null,
  end_time time not null,
  workplace_name text not null,
  subject_name text not null,
  class_description text,
  actual_hours numeric(8,2) not null default 0,
  lesson_count integer not null default 1,
  cumulative_hours numeric(8,2) not null default 0,
  hourly_rate_jpy integer not null default 0,
  lesson_wage_jpy integer not null default 0,
  transportation_fee_jpy integer not null default 0,
  memo text,
  created_at timestamptz not null default now()
);

alter table public.school_part_time_work_monthly_settlement_details
  add column if not exists start_time time,
  add column if not exists end_time time,
  add column if not exists lesson_count integer not null default 1,
  add column if not exists cumulative_hours numeric(8,2) not null default 0,
  add column if not exists transportation_fee_jpy integer not null default 0,
  drop column if exists course_group_name;

alter table public.school_part_time_work_monthly_settlement_details
  alter column start_time set not null,
  alter column end_time set not null,
  drop constraint if exists school_part_time_work_settlement_details_count_check,
  drop constraint if exists school_part_time_work_settlement_details_cumulative_hours_check,
  add constraint school_part_time_work_settlement_details_count_check
    check (lesson_count >= 1),
  add constraint school_part_time_work_settlement_details_cumulative_hours_check
    check (cumulative_hours >= 0);

create unique index if not exists school_part_time_work_settlement_details_lesson_idx
  on public.school_part_time_work_monthly_settlement_details (actual_lesson_id);

create index if not exists school_part_time_work_settlement_details_settlement_idx
  on public.school_part_time_work_monthly_settlement_details (settlement_id, work_date);

create table if not exists public.school_part_time_work_income_requests (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.school_part_time_work_monthly_settlements(id),
  year_month text not null,
  workplace_name text not null,
  teacher_name text not null default '吴峰',
  request_source text not null default 'external_part_time_work',
  currency text not null default 'JPY',
  amount_jpy integer not null,
  status text not null default 'pending_cash_request',
  cash_request_id text,
  cash_transaction_id text,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.school_part_time_work_income_requests
  drop constraint if exists school_part_time_work_income_requests_source_check,
  drop constraint if exists school_part_time_work_income_requests_currency_check,
  drop constraint if exists school_part_time_work_income_requests_amount_check,
  drop constraint if exists school_part_time_work_income_requests_status_check,
  add constraint school_part_time_work_income_requests_source_check
    check (request_source = 'external_part_time_work'),
  add constraint school_part_time_work_income_requests_currency_check
    check (currency = 'JPY'),
  add constraint school_part_time_work_income_requests_amount_check
    check (amount_jpy >= 0),
  add constraint school_part_time_work_income_requests_status_check
    check (status in ('pending_cash_request', 'awaiting_cash_confirmation', 'synced', 'cash_rejected', 'failed', 'blocked'));

create unique index if not exists school_part_time_work_income_requests_settlement_active_idx
  on public.school_part_time_work_income_requests (settlement_id)
  where deleted_at is null;

revoke all on table public.school_part_time_work_lessons from anon, authenticated;
revoke all on table public.school_part_time_work_monthly_settlements from anon, authenticated;
revoke all on table public.school_part_time_work_monthly_settlement_details from anon, authenticated;
revoke all on table public.school_part_time_work_income_requests from anon, authenticated;

create or replace function public.school_part_time_work_validate_workplace(p_workplace_name text)
returns text
language plpgsql
immutable
as $$
declare
  v_value text := nullif(trim(coalesce(p_workplace_name, '')), '');
begin
  if v_value is null or v_value not in ('诺应教育', '致远教育', '新领域') then
    raise exception '打工先无效：%。', coalesce(p_workplace_name, '');
  end if;

  return v_value;
end;
$$;

create or replace function public.school_part_time_work_validate_subject(p_subject_name text)
returns text
language plpgsql
immutable
as $$
declare
  v_value text := nullif(trim(coalesce(p_subject_name, '')), '');
begin
  if v_value is null or v_value not in ('EJU文数班课', 'EJU理数班课', 'EJU文数一对一', 'EJU理数一对一', '大学院一对一') then
    raise exception '科目无效：%。', coalesce(p_subject_name, '');
  end if;

  return v_value;
end;
$$;

create or replace function public.school_part_time_work_validate_year_month(p_year_month text)
returns text
language plpgsql
immutable
as $$
declare
  v_value text := nullif(trim(coalesce(p_year_month, '')), '');
begin
  if v_value is null or v_value !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '年月格式无效：%。', coalesce(p_year_month, '');
  end if;

  return v_value;
end;
$$;

create or replace function public.school_part_time_work_calculate_hours(
  p_start_time time,
  p_end_time time
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_minutes numeric;
begin
  if p_start_time is null then
    raise exception '请选择开始时间。';
  end if;

  if p_end_time is null then
    raise exception '请选择结束时间。';
  end if;

  if p_end_time <= p_start_time then
    raise exception '结束时间必须晚于开始时间。';
  end if;

  v_minutes := extract(epoch from (p_end_time - p_start_time)) / 60;
  return round(v_minutes / 60, 2);
end;
$$;

create or replace function public.school_list_part_time_work_lessons(
  p_year_month text default null,
  p_workplace_name text default null,
  p_record_kind text default null
)
returns table (
  id uuid,
  record_kind text,
  planned_lesson_id uuid,
  generated_actual_id uuid,
  work_date date,
  start_time time,
  end_time time,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  planned_hours numeric,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text,
  settlement_id uuid,
  settlement_status text,
  income_request_id uuid,
  income_request_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    l.id,
    l.record_kind,
    l.planned_lesson_id,
    ga.id as generated_actual_id,
    l.work_date,
    l.start_time,
    l.end_time,
    l.year_month,
    l.workplace_name,
    l.teacher_name,
    l.subject_name,
    l.class_description,
    l.planned_hours,
    l.actual_hours,
    l.lesson_count,
    l.cumulative_hours,
    l.hourly_rate_jpy,
    l.lesson_wage_jpy,
    l.transportation_fee_jpy,
    l.memo,
    s.id as settlement_id,
    s.status as settlement_status,
    s.income_request_id,
    ir.status as income_request_status,
    l.created_at,
    l.updated_at
  from public.school_part_time_work_lessons l
  left join public.school_part_time_work_lessons ga
    on ga.planned_lesson_id = l.id
    and ga.record_kind = 'actual'
    and ga.deleted_at is null
  left join public.school_part_time_work_monthly_settlement_details d
    on d.actual_lesson_id = l.id
    and l.record_kind = 'actual'
  left join public.school_part_time_work_monthly_settlements s
    on s.id = d.settlement_id
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  where l.deleted_at is null
    and (nullif(trim(coalesce(p_year_month, '')), '') is null or l.year_month = trim(p_year_month))
    and (nullif(trim(coalesce(p_workplace_name, '')), '') is null or l.workplace_name = trim(p_workplace_name))
    and (nullif(trim(coalesce(p_record_kind, '')), '') is null or l.record_kind = lower(trim(p_record_kind)))
  order by l.work_date, l.created_at;
$$;

create or replace function public.school_create_part_time_work_planned_lesson(
  p_work_date date,
  p_start_time time,
  p_end_time time,
  p_workplace_name text,
  p_subject_name text,
  p_class_description text default null,
  p_lesson_count integer default 1,
  p_cumulative_hours numeric default 0,
  p_hourly_rate_jpy integer default 0,
  p_transportation_fee_jpy integer default 0,
  p_memo text default null,
  p_teacher_name text default '吴峰'
)
returns table (
  id uuid,
  record_kind text,
  planned_lesson_id uuid,
  generated_actual_id uuid,
  work_date date,
  start_time time,
  end_time time,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  planned_hours numeric,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text,
  settlement_id uuid,
  settlement_status text,
  income_request_id uuid,
  income_request_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_subject_name text := public.school_part_time_work_validate_subject(p_subject_name);
  v_planned_hours numeric(8,2) := public.school_part_time_work_calculate_hours(p_start_time, p_end_time);
  v_lesson_count integer := coalesce(p_lesson_count, 1);
  v_cumulative_hours numeric(8,2) := coalesce(p_cumulative_hours, 0);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
begin
  if p_work_date is null then
    raise exception '请选择预定日期。';
  end if;
  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  insert into public.school_part_time_work_lessons (
    record_kind,
    work_date,
    start_time,
    end_time,
    year_month,
    workplace_name,
    teacher_name,
    subject_name,
    class_description,
    planned_hours,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  values (
    'planned',
    p_work_date,
    p_start_time,
    p_end_time,
    to_char(p_work_date, 'YYYY-MM'),
    v_workplace_name,
    coalesce(nullif(trim(p_teacher_name), ''), '吴峰'),
    v_subject_name,
    nullif(trim(coalesce(p_class_description, '')), ''),
    v_planned_hours,
    0,
    v_lesson_count,
    v_cumulative_hours,
    v_hourly_rate_jpy,
    0,
    v_transportation_fee_jpy,
    nullif(trim(coalesce(p_memo, '')), '')
  )
  returning school_part_time_work_lessons.id into v_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = v_id;
end;
$$;

create or replace function public.school_update_part_time_work_lesson(
  p_id uuid,
  p_work_date date,
  p_start_time time,
  p_end_time time,
  p_workplace_name text,
  p_subject_name text,
  p_class_description text default null,
  p_lesson_count integer default 1,
  p_cumulative_hours numeric default 0,
  p_hourly_rate_jpy integer default 0,
  p_transportation_fee_jpy integer default 0,
  p_memo text default null
)
returns table (
  id uuid,
  record_kind text,
  planned_lesson_id uuid,
  generated_actual_id uuid,
  work_date date,
  start_time time,
  end_time time,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  planned_hours numeric,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text,
  settlement_id uuid,
  settlement_status text,
  income_request_id uuid,
  income_request_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson public.school_part_time_work_lessons%rowtype;
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_subject_name text := public.school_part_time_work_validate_subject(p_subject_name);
  v_hours numeric(8,2) := public.school_part_time_work_calculate_hours(p_start_time, p_end_time);
  v_lesson_count integer := coalesce(p_lesson_count, 1);
  v_cumulative_hours numeric(8,2) := coalesce(p_cumulative_hours, 0);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
begin
  if p_id is null then
    raise exception '记录 ID 不能为空。';
  end if;
  if p_work_date is null then
    raise exception '请选择日期。';
  end if;
  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  select *
  into v_lesson
  from public.school_part_time_work_lessons l
  where l.id = p_id
    and deleted_at is null
  for update;

  if not found then
    raise exception '私塾打工课时不存在或已删除。';
  end if;

  if v_lesson.record_kind = 'actual' and exists (
    select 1
    from public.school_part_time_work_monthly_settlement_details d
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where d.actual_lesson_id = p_id
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该实际课时已进入锁定结算，不能编辑。';
  end if;

  update public.school_part_time_work_lessons l
  set
    work_date = p_work_date,
    start_time = p_start_time,
    end_time = p_end_time,
    year_month = to_char(p_work_date, 'YYYY-MM'),
    workplace_name = v_workplace_name,
    subject_name = v_subject_name,
    class_description = nullif(trim(coalesce(p_class_description, '')), ''),
    planned_hours = case when v_lesson.record_kind = 'planned' then v_hours else 0 end,
    actual_hours = case when v_lesson.record_kind = 'actual' then v_hours else 0 end,
    lesson_count = v_lesson_count,
    cumulative_hours = v_cumulative_hours,
    hourly_rate_jpy = v_hourly_rate_jpy,
    lesson_wage_jpy = case when v_lesson.record_kind = 'actual' then round(v_hours * v_hourly_rate_jpy) else 0 end,
    transportation_fee_jpy = v_transportation_fee_jpy,
    memo = nullif(trim(coalesce(p_memo, '')), ''),
    updated_at = now()
  where l.id = p_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = p_id;
end;
$$;

create or replace function public.school_generate_part_time_work_actual_from_planned(
  p_planned_lesson_id uuid,
  p_actual_work_date date default null,
  p_start_time time default null,
  p_end_time time default null,
  p_lesson_count integer default null,
  p_cumulative_hours numeric default null,
  p_hourly_rate_jpy integer default null,
  p_transportation_fee_jpy integer default null,
  p_memo text default null
)
returns table (
  id uuid,
  record_kind text,
  planned_lesson_id uuid,
  generated_actual_id uuid,
  work_date date,
  start_time time,
  end_time time,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  planned_hours numeric,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text,
  settlement_id uuid,
  settlement_status text,
  income_request_id uuid,
  income_request_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planned public.school_part_time_work_lessons%rowtype;
  v_actual_id uuid;
  v_work_date date;
  v_start_time time;
  v_end_time time;
  v_actual_hours numeric(8,2);
  v_lesson_count integer;
  v_cumulative_hours numeric(8,2);
  v_hourly_rate_jpy integer;
  v_transportation_fee_jpy integer;
begin
  select *
  into v_planned
  from public.school_part_time_work_lessons l
  where l.id = p_planned_lesson_id
    and l.record_kind = 'planned'
    and l.deleted_at is null
  for update;

  if not found then
    raise exception '预定打工课时不存在或已删除。';
  end if;

  if exists (
    select 1
    from public.school_part_time_work_lessons a
    where a.planned_lesson_id = p_planned_lesson_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
  ) then
    raise exception '该预定课时已经生成实际课时。';
  end if;

  v_work_date := coalesce(p_actual_work_date, v_planned.work_date);
  v_start_time := coalesce(p_start_time, v_planned.start_time);
  v_end_time := coalesce(p_end_time, v_planned.end_time);
  v_actual_hours := public.school_part_time_work_calculate_hours(v_start_time, v_end_time);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count, 1);
  v_cumulative_hours := coalesce(p_cumulative_hours, v_planned.cumulative_hours, 0);
  v_hourly_rate_jpy := coalesce(p_hourly_rate_jpy, v_planned.hourly_rate_jpy);
  v_transportation_fee_jpy := coalesce(p_transportation_fee_jpy, v_planned.transportation_fee_jpy);

  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  insert into public.school_part_time_work_lessons (
    record_kind,
    planned_lesson_id,
    work_date,
    start_time,
    end_time,
    year_month,
    workplace_name,
    teacher_name,
    subject_name,
    class_description,
    planned_hours,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  values (
    'actual',
    v_planned.id,
    v_work_date,
    v_start_time,
    v_end_time,
    to_char(v_work_date, 'YYYY-MM'),
    v_planned.workplace_name,
    v_planned.teacher_name,
    v_planned.subject_name,
    v_planned.class_description,
    0,
    v_actual_hours,
    v_lesson_count,
    v_cumulative_hours,
    v_hourly_rate_jpy,
    round(v_actual_hours * v_hourly_rate_jpy),
    v_transportation_fee_jpy,
    coalesce(nullif(trim(coalesce(p_memo, '')), ''), v_planned.memo)
  )
  returning school_part_time_work_lessons.id into v_actual_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = v_actual_id;
end;
$$;

create or replace function public.school_delete_part_time_work_lesson(
  p_id uuid,
  p_confirm_generated_actual boolean default false
)
returns table (
  deleted_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson public.school_part_time_work_lessons%rowtype;
  v_now timestamptz := now();
  v_count integer := 0;
begin
  select *
  into v_lesson
  from public.school_part_time_work_lessons l
  where l.id = p_id
    and l.deleted_at is null
  for update;

  if not found then
    raise exception '私塾打工课时不存在或已删除。';
  end if;

  if v_lesson.record_kind = 'actual' and exists (
    select 1
    from public.school_part_time_work_monthly_settlement_details d
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where d.actual_lesson_id = p_id
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该实际课时已进入锁定结算，不能删除。';
  end if;

  if v_lesson.record_kind = 'planned' and exists (
    select 1
    from public.school_part_time_work_lessons a
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
  ) and not p_confirm_generated_actual then
    raise exception '该预定课时已生成实际课时。请再次确认后删除。';
  end if;

  if v_lesson.record_kind = 'planned' and exists (
    select 1
    from public.school_part_time_work_lessons a
    join public.school_part_time_work_monthly_settlement_details d
      on d.actual_lesson_id = a.id
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该预定课时的实际课时已进入锁定结算，不能删除。';
  end if;

  update public.school_part_time_work_lessons l
  set deleted_at = v_now, updated_at = v_now
  where l.id = p_id
    and l.deleted_at is null;
  get diagnostics v_count = row_count;

  if v_lesson.record_kind = 'planned' and p_confirm_generated_actual then
    update public.school_part_time_work_lessons a
    set deleted_at = v_now, updated_at = v_now
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
      and not exists (
        select 1
        from public.school_part_time_work_monthly_settlement_details d
        join public.school_part_time_work_monthly_settlements s
          on s.id = d.settlement_id
        where d.actual_lesson_id = a.id
          and s.deleted_at is null
          and s.status in ('locked', 'income_request_created')
      );
    get diagnostics v_count = row_count;
    v_count := v_count + 1;
  end if;

  return query select v_count;
end;
$$;

create or replace function public.school_list_part_time_work_monthly_settlements(
  p_year_month text
)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  memo text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with target_workplaces(workplace_name) as (
    values ('诺应教育'), ('致远教育'), ('新领域')
  ),
  actual_totals as (
    select
      l.workplace_name,
      count(*)::integer as actual_lesson_count,
      coalesce(sum(l.actual_hours), 0)::numeric as actual_hours_total,
      coalesce(sum(l.lesson_wage_jpy), 0)::integer as default_lesson_wage_jpy,
      coalesce(sum(l.transportation_fee_jpy), 0)::integer as transportation_fee_jpy
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
      and l.record_kind = 'actual'
      and l.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    group by l.workplace_name
  )
  select
    s.id,
    public.school_part_time_work_validate_year_month(p_year_month) as year_month,
    w.workplace_name,
    coalesce(s.teacher_name, '吴峰') as teacher_name,
    case when s.status in ('locked', 'income_request_created') then s.actual_lesson_count else coalesce(a.actual_lesson_count, 0) end as actual_lesson_count,
    case when s.status in ('locked', 'income_request_created') then s.actual_hours_total else coalesce(a.actual_hours_total, 0) end as actual_hours_total,
    coalesce(s.hourly_rate_jpy, 0) as hourly_rate_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.lesson_wage_jpy
      else coalesce(a.default_lesson_wage_jpy, 0)
    end as lesson_wage_jpy,
    case when s.status in ('locked', 'income_request_created') then s.transportation_fee_jpy else coalesce(a.transportation_fee_jpy, 0) end as transportation_fee_jpy,
    coalesce(s.adjustment_jpy, 0) as adjustment_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.total_wage_jpy
      else (
        coalesce(a.default_lesson_wage_jpy, 0)
        + coalesce(a.transportation_fee_jpy, 0)
        + coalesce(s.adjustment_jpy, 0)
      )
    end as total_wage_jpy,
    coalesce(s.status, 'draft') as status,
    s.locked_at,
    s.income_request_id,
    ir.status as income_request_status,
    s.memo,
    s.updated_at
  from target_workplaces w
  left join actual_totals a
    on a.workplace_name = w.workplace_name
  left join public.school_part_time_work_monthly_settlements s
    on s.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    and s.workplace_name = w.workplace_name
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  order by case w.workplace_name when '诺应教育' then 1 when '致远教育' then 2 else 3 end;
$$;

create or replace function public.school_lock_part_time_work_monthly_settlement(
  p_year_month text,
  p_workplace_name text,
  p_adjustment_jpy integer default 0,
  p_memo text default null
)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  memo text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_month text := public.school_part_time_work_validate_year_month(p_year_month);
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_actual_lesson_count integer;
  v_actual_hours_total numeric(10,2);
  v_lesson_wage_jpy integer;
  v_transportation_fee_jpy integer;
  v_adjustment_jpy integer := coalesce(p_adjustment_jpy, 0);
  v_total_wage_jpy integer;
  v_detail_count integer;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.year_month = v_year_month
    and s.workplace_name = v_workplace_name
    and s.deleted_at is null
  for update;

  if found and v_settlement.status <> 'draft' then
    raise exception '只有草稿状态的月度工资结算可以锁定。';
  end if;

  select
    count(*)::integer,
    coalesce(sum(l.actual_hours), 0)::numeric(10,2),
    coalesce(sum(l.lesson_wage_jpy), 0)::integer,
    coalesce(sum(l.transportation_fee_jpy), 0)::integer
  into v_actual_lesson_count, v_actual_hours_total, v_lesson_wage_jpy, v_transportation_fee_jpy
  from public.school_part_time_work_lessons l
  where l.year_month = v_year_month
    and l.workplace_name = v_workplace_name
    and l.record_kind = 'actual'
    and l.deleted_at is null;

  if v_actual_lesson_count <= 0 then
    raise exception '没有实际打工课时，不能锁定工资结算。';
  end if;

  v_total_wage_jpy := v_lesson_wage_jpy + v_transportation_fee_jpy + v_adjustment_jpy;

  if v_total_wage_jpy < 0 then
    raise exception '工资总额不能小于 0。';
  end if;

  if v_settlement.id is not null then
    update public.school_part_time_work_monthly_settlements s
    set
      actual_lesson_count = v_actual_lesson_count,
      actual_hours_total = v_actual_hours_total,
      hourly_rate_jpy = 0,
      lesson_wage_jpy = v_lesson_wage_jpy,
      transportation_fee_jpy = v_transportation_fee_jpy,
      adjustment_jpy = v_adjustment_jpy,
      total_wage_jpy = v_total_wage_jpy,
      memo = nullif(trim(coalesce(p_memo, '')), ''),
      updated_at = now()
    where s.id = v_settlement.id
    returning * into v_settlement;
  else
    insert into public.school_part_time_work_monthly_settlements (
      year_month,
      workplace_name,
      actual_lesson_count,
      actual_hours_total,
      hourly_rate_jpy,
      lesson_wage_jpy,
      transportation_fee_jpy,
      adjustment_jpy,
      total_wage_jpy,
      status,
      memo,
      updated_at
    )
    values (
      v_year_month,
      v_workplace_name,
      v_actual_lesson_count,
      v_actual_hours_total,
      0,
      v_lesson_wage_jpy,
      v_transportation_fee_jpy,
      v_adjustment_jpy,
      v_total_wage_jpy,
      'draft',
      nullif(trim(coalesce(p_memo, '')), ''),
      now()
    )
    returning * into v_settlement;
  end if;

  delete from public.school_part_time_work_monthly_settlement_details
  where school_part_time_work_monthly_settlement_details.settlement_id = v_settlement.id;

  insert into public.school_part_time_work_monthly_settlement_details (
    settlement_id,
    actual_lesson_id,
    work_date,
    start_time,
    end_time,
    workplace_name,
    subject_name,
    class_description,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  select
    v_settlement.id,
    l.id,
    l.work_date,
    l.start_time,
    l.end_time,
    l.workplace_name,
    l.subject_name,
    l.class_description,
    l.actual_hours,
    l.lesson_count,
    l.cumulative_hours,
    l.hourly_rate_jpy,
    l.lesson_wage_jpy,
    l.transportation_fee_jpy,
    l.memo
  from public.school_part_time_work_lessons l
  where l.year_month = v_settlement.year_month
    and l.workplace_name = v_settlement.workplace_name
    and l.record_kind = 'actual'
    and l.deleted_at is null
  order by l.work_date, l.created_at;

  get diagnostics v_detail_count = row_count;

  if v_detail_count <> v_settlement.actual_lesson_count then
    raise exception '锁定明细数量不一致，请刷新后重新锁定结算。';
  end if;

  update public.school_part_time_work_monthly_settlements
  set status = 'locked',
      locked_at = now(),
      updated_at = now()
  where school_part_time_work_monthly_settlements.id = v_settlement.id;

  return query
  select *
  from public.school_list_part_time_work_monthly_settlements(v_settlement.year_month) r
  where r.id = v_settlement.id;
end;
$$;

create or replace function public.school_unlock_part_time_work_monthly_settlement(p_settlement_id uuid)
returns table (
  id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  actual_lesson_count integer,
  actual_hours_total numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  income_request_id uuid,
  income_request_status text,
  memo text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.id = p_settlement_id
    and s.deleted_at is null
  for update;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;
  if v_settlement.status <> 'locked' then
    raise exception '只有已锁定且未生成收入请求的结算可以撤销锁定。';
  end if;
  if v_settlement.income_request_id is not null or exists (
    select 1
    from public.school_part_time_work_income_requests ir
    where ir.settlement_id = v_settlement.id
      and ir.deleted_at is null
  ) then
    raise exception '已生成收入请求，不能撤销锁定。';
  end if;

  delete from public.school_part_time_work_monthly_settlement_details d
  where d.settlement_id = v_settlement.id;

  update public.school_part_time_work_monthly_settlements
  set status = 'draft',
      locked_at = null,
      updated_at = now()
  where school_part_time_work_monthly_settlements.id = v_settlement.id;

  return query
  select *
  from public.school_list_part_time_work_monthly_settlements(v_settlement.year_month) r
  where r.id = v_settlement.id;
end;
$$;

create or replace function public.school_create_part_time_work_income_request(p_settlement_id uuid)
returns table (
  id uuid,
  settlement_id uuid,
  year_month text,
  workplace_name text,
  amount_jpy integer,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
  v_request_id uuid;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.id = p_settlement_id
    and s.deleted_at is null
  for update;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;
  if v_settlement.status not in ('locked', 'income_request_created') then
    raise exception '请先锁定月度工资结算，再生成收入请求。';
  end if;

  select ir.id
  into v_request_id
  from public.school_part_time_work_income_requests ir
  where ir.settlement_id = v_settlement.id
    and ir.deleted_at is null
  limit 1;

  if v_request_id is null then
    insert into public.school_part_time_work_income_requests (
      settlement_id,
      year_month,
      workplace_name,
      teacher_name,
      amount_jpy,
      status,
      memo
    )
    values (
      v_settlement.id,
      v_settlement.year_month,
      v_settlement.workplace_name,
      v_settlement.teacher_name,
      v_settlement.total_wage_jpy,
      'pending_cash_request',
      v_settlement.memo
    )
    returning school_part_time_work_income_requests.id into v_request_id;
  end if;

  update public.school_part_time_work_monthly_settlements
  set status = 'income_request_created',
      income_request_id = v_request_id,
      updated_at = now()
  where school_part_time_work_monthly_settlements.id = v_settlement.id;

  return query
  select
    ir.id,
    ir.settlement_id,
    ir.year_month,
    ir.workplace_name,
    ir.amount_jpy,
    ir.status,
    ir.created_at
  from public.school_part_time_work_income_requests ir
  where ir.id = v_request_id;
end;
$$;

create or replace function public.school_get_part_time_work_settlement_export(p_settlement_id uuid)
returns table (
  settlement_id uuid,
  year_month text,
  workplace_name text,
  teacher_name text,
  adjustment_jpy integer,
  total_wage_jpy integer,
  status text,
  locked_at timestamptz,
  actual_lesson_id uuid,
  work_date date,
  start_time time,
  end_time time,
  subject_name text,
  class_description text,
  actual_hours numeric,
  lesson_count integer,
  cumulative_hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  memo text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.id = p_settlement_id
    and s.deleted_at is null;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;
  if v_settlement.status not in ('locked', 'income_request_created') then
    raise exception '月度工资结算锁定后才能导出。';
  end if;

  return query
  select
    v_settlement.id as settlement_id,
    v_settlement.year_month,
    v_settlement.workplace_name,
    v_settlement.teacher_name,
    v_settlement.adjustment_jpy,
    v_settlement.total_wage_jpy,
    v_settlement.status,
    v_settlement.locked_at,
    d.actual_lesson_id,
    d.work_date,
    d.start_time,
    d.end_time,
    d.subject_name,
    d.class_description,
    d.actual_hours,
    d.lesson_count,
    d.cumulative_hours,
    d.hourly_rate_jpy,
    d.lesson_wage_jpy,
    d.transportation_fee_jpy,
    d.memo
  from public.school_part_time_work_monthly_settlement_details d
  where d.settlement_id = v_settlement.id
  order by d.work_date, d.created_at;
end;
$$;

revoke all on function public.school_part_time_work_validate_workplace(text) from public, anon, authenticated;
revoke all on function public.school_part_time_work_validate_subject(text) from public, anon, authenticated;
revoke all on function public.school_part_time_work_validate_year_month(text) from public, anon, authenticated;
revoke all on function public.school_part_time_work_calculate_hours(time, time) from public, anon, authenticated;
revoke all on function public.school_list_part_time_work_lessons(text, text, text) from public, anon, authenticated;
revoke all on function public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, integer, numeric, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, integer, numeric, integer, integer, text) from public, anon, authenticated;
revoke all on function public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, integer, numeric, integer, integer, text) from public, anon, authenticated;
revoke all on function public.school_delete_part_time_work_lesson(uuid, boolean) from public, anon, authenticated;
revoke all on function public.school_list_part_time_work_monthly_settlements(text) from public, anon, authenticated;
revoke all on function public.school_lock_part_time_work_monthly_settlement(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.school_unlock_part_time_work_monthly_settlement(uuid) from public, anon, authenticated;
revoke all on function public.school_create_part_time_work_income_request(uuid) from public, anon, authenticated;
revoke all on function public.school_get_part_time_work_settlement_export(uuid) from public, anon, authenticated;

grant execute on function public.school_list_part_time_work_lessons(text, text, text) to authenticated;
grant execute on function public.school_create_part_time_work_planned_lesson(date, time, time, text, text, text, integer, numeric, integer, integer, text, text) to authenticated;
grant execute on function public.school_update_part_time_work_lesson(uuid, date, time, time, text, text, text, integer, numeric, integer, integer, text) to authenticated;
grant execute on function public.school_generate_part_time_work_actual_from_planned(uuid, date, time, time, integer, numeric, integer, integer, text) to authenticated;
grant execute on function public.school_delete_part_time_work_lesson(uuid, boolean) to authenticated;
grant execute on function public.school_list_part_time_work_monthly_settlements(text) to authenticated;
grant execute on function public.school_lock_part_time_work_monthly_settlement(text, text, integer, text) to authenticated;
grant execute on function public.school_unlock_part_time_work_monthly_settlement(uuid) to authenticated;
grant execute on function public.school_create_part_time_work_income_request(uuid) to authenticated;
grant execute on function public.school_get_part_time_work_settlement_export(uuid) to authenticated;

commit;
