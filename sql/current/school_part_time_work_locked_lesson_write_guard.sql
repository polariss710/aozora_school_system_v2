-- school_part_time_work_locked_lesson_write_guard.sql
-- Version: v10.3.46 protect locked external part-time lesson writes
-- Purpose:
-- - Block planned/actual external part-time lesson writes after the
--   corresponding month/workplace settlement is locked or income-recorded.

create or replace function public.school_part_time_work_assert_lesson_month_unlocked(
  p_year_month text,
  p_workplace_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  select s.status
    into v_status
    from public.school_part_time_work_monthly_settlements s
   where s.year_month = p_year_month
     and s.workplace_name = p_workplace_name
     and s.deleted_at is null
     and s.status in ('locked', 'income_request_created')
   limit 1;

  if found then
    raise exception '该月份 / 机构的外部授课结算已锁定，不能新增、编辑或删除课时。'
      using errcode = 'P0001',
            detail = format('year_month=%s, workplace_name=%s, status=%s', p_year_month, p_workplace_name, v_status);
  end if;
end;
$$;

create or replace function public.school_part_time_work_lessons_locked_write_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.school_part_time_work_assert_lesson_month_unlocked(
      new.year_month,
      new.workplace_name
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    perform public.school_part_time_work_assert_lesson_month_unlocked(
      old.year_month,
      old.workplace_name
    );

    if new.year_month is distinct from old.year_month
       or new.workplace_name is distinct from old.workplace_name then
      perform public.school_part_time_work_assert_lesson_month_unlocked(
        new.year_month,
        new.workplace_name
      );
    end if;

    return new;
  end if;

  if tg_op = 'DELETE' then
    perform public.school_part_time_work_assert_lesson_month_unlocked(
      old.year_month,
      old.workplace_name
    );
    return old;
  end if;

  return null;
end;
$$;

create or replace trigger school_part_time_work_lessons_locked_write_guard_trg
before insert or update or delete on public.school_part_time_work_lessons
for each row
execute function public.school_part_time_work_lessons_locked_write_guard();

revoke all on function public.school_part_time_work_assert_lesson_month_unlocked(text, text) from public, anon, authenticated;
revoke all on function public.school_part_time_work_lessons_locked_write_guard() from public, anon, authenticated;
