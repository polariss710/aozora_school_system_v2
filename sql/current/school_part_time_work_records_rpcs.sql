-- school_part_time_work_records_rpcs.sql
-- Purpose: RPC API for the standalone external cram-school part-time work module.
-- Status: executed on School DB 2026-06-15; verified by read-only RPC/grant inspection.
--
-- Scope:
-- - List, create, update, soft-delete, and aggregate external part-time work records.
-- - RPCs calculate lesson_wage_jpy and total_wage_jpy on save.
-- - No Cash integration, no teacher_wage/payment request writes, no lesson/student writes.
-- - All execute grants are authenticated only; anon is intentionally not granted.
-- - No real business data or test data is inserted by this file.

begin;

create or replace function public.school_part_time_work_normalize_status(p_status text)
returns text
language plpgsql
immutable
as $$
declare
  v_status text := lower(trim(coalesce(p_status, 'unpaid')));
begin
  if v_status = '' then
    v_status := 'unpaid';
  end if;

  if v_status not in ('unpaid', 'paid', 'cancelled') then
    raise exception '支付状态无效：%。', v_status;
  end if;

  return v_status;
end;
$$;

create or replace function public.school_list_part_time_work_records(
  p_year_month text default null,
  p_workplace_name text default null,
  p_payment_status text default null
)
returns table (
  id uuid,
  work_date date,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  payment_status text,
  paid_date date,
  memo text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    r.id,
    r.work_date,
    r.year_month,
    r.workplace_name,
    r.teacher_name,
    r.subject_name,
    r.class_description,
    r.hours,
    r.hourly_rate_jpy,
    r.lesson_wage_jpy,
    r.transportation_fee_jpy,
    r.adjustment_jpy,
    r.total_wage_jpy,
    r.payment_status,
    r.paid_date,
    r.memo,
    r.created_at,
    r.updated_at
  from public.school_part_time_work_records r
  where r.deleted_at is null
    and (
      nullif(trim(coalesce(p_year_month, '')), '') is null
      or r.year_month = trim(p_year_month)
    )
    and (
      nullif(trim(coalesce(p_workplace_name, '')), '') is null
      or r.workplace_name ilike '%' || trim(p_workplace_name) || '%'
    )
    and (
      nullif(trim(coalesce(p_payment_status, '')), '') is null
      or r.payment_status = lower(trim(p_payment_status))
    )
  order by r.work_date desc, r.created_at desc;
$$;

create or replace function public.school_create_part_time_work_record(
  p_work_date date,
  p_workplace_name text,
  p_teacher_name text default null,
  p_subject_name text default null,
  p_class_description text default null,
  p_hours numeric default 0,
  p_hourly_rate_jpy integer default 0,
  p_transportation_fee_jpy integer default 0,
  p_adjustment_jpy integer default 0,
  p_payment_status text default 'unpaid',
  p_paid_date date default null,
  p_memo text default null
)
returns table (
  id uuid,
  work_date date,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  payment_status text,
  paid_date date,
  memo text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_id uuid;
  v_workplace_name text := nullif(trim(coalesce(p_workplace_name, '')), '');
  v_teacher_name text := nullif(trim(coalesce(p_teacher_name, '')), '');
  v_subject_name text := nullif(trim(coalesce(p_subject_name, '')), '');
  v_class_description text := nullif(trim(coalesce(p_class_description, '')), '');
  v_hours numeric(8,2) := round(coalesce(p_hours, 0)::numeric, 2);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
  v_adjustment_jpy integer := coalesce(p_adjustment_jpy, 0);
  v_lesson_wage_jpy integer;
  v_total_wage_jpy integer;
  v_payment_status text := public.school_part_time_work_normalize_status(p_payment_status);
begin
  if p_work_date is null then
    raise exception '请选择工作日期。';
  end if;

  if v_workplace_name is null then
    raise exception '请填写打工先。';
  end if;

  if v_hours < 0 then
    raise exception '课时不能小于 0。';
  end if;

  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;

  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  v_lesson_wage_jpy := round(v_hours * v_hourly_rate_jpy);
  v_total_wage_jpy := v_lesson_wage_jpy + v_transportation_fee_jpy + v_adjustment_jpy;

  if v_total_wage_jpy < 0 then
    raise exception '总工资不能小于 0。';
  end if;

  insert into public.school_part_time_work_records (
    work_date,
    year_month,
    workplace_name,
    teacher_name,
    subject_name,
    class_description,
    hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    adjustment_jpy,
    total_wage_jpy,
    payment_status,
    paid_date,
    memo,
    created_at,
    updated_at
  )
  values (
    p_work_date,
    to_char(p_work_date, 'YYYY-MM'),
    v_workplace_name,
    v_teacher_name,
    v_subject_name,
    v_class_description,
    v_hours,
    v_hourly_rate_jpy,
    v_lesson_wage_jpy,
    v_transportation_fee_jpy,
    v_adjustment_jpy,
    v_total_wage_jpy,
    v_payment_status,
    p_paid_date,
    nullif(trim(coalesce(p_memo, '')), ''),
    v_now,
    v_now
  )
  returning school_part_time_work_records.id into v_id;

  return query
  select *
  from public.school_list_part_time_work_records(null, null, null) r
  where r.id = v_id;
end;
$$;

create or replace function public.school_update_part_time_work_record(
  p_id uuid,
  p_work_date date,
  p_workplace_name text,
  p_teacher_name text default null,
  p_subject_name text default null,
  p_class_description text default null,
  p_hours numeric default 0,
  p_hourly_rate_jpy integer default 0,
  p_transportation_fee_jpy integer default 0,
  p_adjustment_jpy integer default 0,
  p_payment_status text default 'unpaid',
  p_paid_date date default null,
  p_memo text default null
)
returns table (
  id uuid,
  work_date date,
  year_month text,
  workplace_name text,
  teacher_name text,
  subject_name text,
  class_description text,
  hours numeric,
  hourly_rate_jpy integer,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  payment_status text,
  paid_date date,
  memo text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_workplace_name text := nullif(trim(coalesce(p_workplace_name, '')), '');
  v_teacher_name text := nullif(trim(coalesce(p_teacher_name, '')), '');
  v_subject_name text := nullif(trim(coalesce(p_subject_name, '')), '');
  v_class_description text := nullif(trim(coalesce(p_class_description, '')), '');
  v_hours numeric(8,2) := round(coalesce(p_hours, 0)::numeric, 2);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
  v_adjustment_jpy integer := coalesce(p_adjustment_jpy, 0);
  v_lesson_wage_jpy integer;
  v_total_wage_jpy integer;
  v_payment_status text := public.school_part_time_work_normalize_status(p_payment_status);
begin
  if p_id is null then
    raise exception '记录 ID 不能为空。';
  end if;

  if p_work_date is null then
    raise exception '请选择工作日期。';
  end if;

  if v_workplace_name is null then
    raise exception '请填写打工先。';
  end if;

  if v_hours < 0 then
    raise exception '课时不能小于 0。';
  end if;

  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;

  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  v_lesson_wage_jpy := round(v_hours * v_hourly_rate_jpy);
  v_total_wage_jpy := v_lesson_wage_jpy + v_transportation_fee_jpy + v_adjustment_jpy;

  if v_total_wage_jpy < 0 then
    raise exception '总工资不能小于 0。';
  end if;

  update public.school_part_time_work_records r
  set
    work_date = p_work_date,
    year_month = to_char(p_work_date, 'YYYY-MM'),
    workplace_name = v_workplace_name,
    teacher_name = v_teacher_name,
    subject_name = v_subject_name,
    class_description = v_class_description,
    hours = v_hours,
    hourly_rate_jpy = v_hourly_rate_jpy,
    lesson_wage_jpy = v_lesson_wage_jpy,
    transportation_fee_jpy = v_transportation_fee_jpy,
    adjustment_jpy = v_adjustment_jpy,
    total_wage_jpy = v_total_wage_jpy,
    payment_status = v_payment_status,
    paid_date = p_paid_date,
    memo = nullif(trim(coalesce(p_memo, '')), ''),
    updated_at = v_now
  where r.id = p_id
    and r.deleted_at is null;

  if not found then
    raise exception '私塾打工记录不存在或已删除。';
  end if;

  return query
  select *
  from public.school_list_part_time_work_records(null, null, null) r
  where r.id = p_id;
end;
$$;

create or replace function public.school_delete_part_time_work_record(p_id uuid)
returns table (
  id uuid,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_at timestamptz := now();
begin
  if p_id is null then
    raise exception '记录 ID 不能为空。';
  end if;

  update public.school_part_time_work_records r
  set
    deleted_at = v_deleted_at,
    updated_at = v_deleted_at
  where r.id = p_id
    and r.deleted_at is null;

  if not found then
    raise exception '私塾打工记录不存在或已删除。';
  end if;

  return query select p_id, v_deleted_at;
end;
$$;

create or replace function public.school_get_part_time_work_monthly_stats(
  p_year_month text default null
)
returns table (
  record_count integer,
  total_hours numeric,
  lesson_wage_jpy integer,
  transportation_fee_jpy integer,
  adjustment_jpy integer,
  total_wage_jpy integer,
  unpaid_wage_jpy integer,
  paid_wage_jpy integer
)
language sql
security definer
set search_path = public
as $$
  select
    count(*) filter (where r.payment_status <> 'cancelled')::integer as record_count,
    coalesce(sum(r.hours) filter (where r.payment_status <> 'cancelled'), 0)::numeric as total_hours,
    coalesce(sum(r.lesson_wage_jpy) filter (where r.payment_status <> 'cancelled'), 0)::integer as lesson_wage_jpy,
    coalesce(sum(r.transportation_fee_jpy) filter (where r.payment_status <> 'cancelled'), 0)::integer as transportation_fee_jpy,
    coalesce(sum(r.adjustment_jpy) filter (where r.payment_status <> 'cancelled'), 0)::integer as adjustment_jpy,
    coalesce(sum(r.total_wage_jpy) filter (where r.payment_status <> 'cancelled'), 0)::integer as total_wage_jpy,
    coalesce(sum(r.total_wage_jpy) filter (where r.payment_status = 'unpaid'), 0)::integer as unpaid_wage_jpy,
    coalesce(sum(r.total_wage_jpy) filter (where r.payment_status = 'paid'), 0)::integer as paid_wage_jpy
  from public.school_part_time_work_records r
  where r.deleted_at is null
    and (
      nullif(trim(coalesce(p_year_month, '')), '') is null
      or r.year_month = trim(p_year_month)
    );
$$;

revoke all on function public.school_part_time_work_normalize_status(text) from public, anon, authenticated;
revoke all on function public.school_list_part_time_work_records(text, text, text) from public, anon, authenticated;
revoke all on function public.school_create_part_time_work_record(date, text, text, text, text, numeric, integer, integer, integer, text, date, text) from public, anon, authenticated;
revoke all on function public.school_update_part_time_work_record(uuid, date, text, text, text, text, numeric, integer, integer, integer, text, date, text) from public, anon, authenticated;
revoke all on function public.school_delete_part_time_work_record(uuid) from public, anon, authenticated;
revoke all on function public.school_get_part_time_work_monthly_stats(text) from public, anon, authenticated;

grant execute on function public.school_list_part_time_work_records(text, text, text) to authenticated;
grant execute on function public.school_create_part_time_work_record(date, text, text, text, text, numeric, integer, integer, integer, text, date, text) to authenticated;
grant execute on function public.school_update_part_time_work_record(uuid, date, text, text, text, text, numeric, integer, integer, integer, text, date, text) to authenticated;
grant execute on function public.school_delete_part_time_work_record(uuid) to authenticated;
grant execute on function public.school_get_part_time_work_monthly_stats(text) to authenticated;

commit;
