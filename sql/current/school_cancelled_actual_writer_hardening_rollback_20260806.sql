-- Exact DB metadata rollback for the pre-2026-08-06 cancellation writer.
-- Restores original pg_get_functiondef MD5 fcbb8a4c48cf62c285de45238b219e43
-- and original anon/authenticated/service_role ACL. No business-data DML.
\set ON_ERROR_STOP on
\pset pager off
\if :{?cancellation_writer_rollback_commit}
\else
  \set cancellation_writer_rollback_commit 0
\endif

begin;

create or replace function public.school_create_cancelled_actual_lesson_from_planned(
  p_planned_lesson_id uuid,
  p_lesson_date date default null,
  p_start_time text default null,
  p_end_time text default null,
  p_duration_hours numeric default null,
  p_unit_price numeric default null,
  p_lesson_count integer default null,
  p_lesson_content text default null,
  p_note text default null
)
returns table (
  lesson_id uuid,
  lesson_type text,
  lesson_date date,
  year_month text,
  student_id uuid,
  teacher_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  start_time text,
  end_time text,
  duration_hours numeric,
  unit_price numeric,
  lesson_fee numeric,
  status text,
  is_billable boolean,
  lesson_count integer,
  actual_minutes integer,
  planned_lesson_id uuid,
  teacher_settlement_month text,
  lesson_content text,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_planned public.school_lesson_records%rowtype;
  v_lesson_date date;
  v_start_time text;
  v_end_time text;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_teacher_settlement_month text;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  if p_planned_lesson_id is null then
    raise exception '请选择预定课时。';
  end if;

  select p.*
  into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;

  if v_planned.lesson_type <> 'planned' then
    raise exception '只能从 planned 课时生成取消 actual。';
  end if;

  if v_planned.voided_at is not null then
    raise exception '该预定课时已作废，不能生成 cancelled actual。';
  end if;

  if v_planned.status not in ('planned', 'pending_makeup') then
    raise exception '当前 planned 状态不能生成 cancelled actual：%。', coalesce(v_planned.status, '');
  end if;

  if v_planned.student_id is null then
    raise exception '预定课时缺少学生，不能生成取消 actual。';
  end if;

  if v_planned.teacher_id is null then
    raise exception '预定课时缺少老师，不能生成取消 actual。';
  end if;

  if v_planned.subject_id is null then
    raise exception '预定课时缺少科目，不能生成取消 actual。';
  end if;

  if v_planned.business_entity_id is null then
    raise exception '预定课时缺少业务归属，不能生成取消 actual。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该预定课时已有关联 actual，不能重复生成。';
  end if;

  v_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  if v_lesson_date is null then
    raise exception '请选择取消课日期。';
  end if;

  v_start_time := coalesce(nullif(trim(coalesce(p_start_time, '')), ''), nullif(trim(coalesce(v_planned.start_time, '')), ''));
  v_end_time := coalesce(nullif(trim(coalesce(p_end_time, '')), ''), nullif(trim(coalesce(v_planned.end_time, '')), ''));
  v_duration_hours := coalesce(p_duration_hours, v_planned.duration_hours, 0);
  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(nullif(trim(coalesce(p_lesson_content, '')), ''), v_planned.lesson_content);
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_duration_hours <= 0 then
    raise exception '取消课时长必须大于 0。';
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
  end if;

  if v_lesson_count is not null and v_lesson_count <= 0 then
    raise exception '课次数必须大于 0。';
  end if;

  if v_start_time is not null and v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间格式无效，请使用 HH:MM。';
  end if;

  if v_end_time is not null and v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间格式无效，请使用 HH:MM。';
  end if;

  select s.business_entity_id
  into v_student_business_entity_id
  from public.school_students s
  where s.id = v_planned.student_id
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null
    and v_student_business_entity_id is distinct from v_planned.business_entity_id then
    raise exception '学生默认业务归属与课时业务归属不一致。';
  end if;

  if not exists (
    select 1
    from public.school_teachers t
    where t.id = v_planned.teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if not exists (
    select 1
    from public.school_subjects s
    where s.id = v_planned.subject_id
      and coalesce(s.is_active, true) = true
  ) then
    raise exception '科目无效或已停用。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = v_planned.business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(
        v_planned.id
      )
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成取消 actual。';
  end if;

  v_teacher_settlement_month := to_char(v_lesson_date, 'YYYY-MM');

  if exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_teacher_settlement_month
      and w.status = 'locked'
  ) then
    raise exception '目标老师工资月份已锁定，不能生成取消 actual。';
  end if;

  insert into public.school_lesson_records (
    lesson_type,
    lesson_date,
    year_month,
    student_id,
    teacher_id,
    subject_id,
    business_entity_id,
    start_time,
    end_time,
    duration_hours,
    lesson_content,
    status,
    is_billable,
    note,
    app_type,
    planned_lesson_id,
    unit_price,
    lesson_fee,
    import_batch_id,
    import_source,
    imported_at,
    lesson_count,
    actual_minutes,
    teacher_settlement_month
  )
  values (
    'actual',
    v_lesson_date,
    v_planned.year_month,
    v_planned.student_id,
    v_planned.teacher_id,
    v_planned.subject_id,
    v_planned.business_entity_id,
    v_start_time,
    v_end_time,
    v_duration_hours,
    v_lesson_content,
    'cancelled',
    false,
    v_note,
    'school',
    v_planned.id,
    v_unit_price,
    0,
    null,
    null,
    null,
    v_lesson_count,
    0,
    v_teacher_settlement_month
  )
  returning id into v_actual_id;

  update public.school_lesson_records
     set status = 'pending_makeup'
   where id = v_planned.id;

  return query
  select
    a.id,
    a.lesson_type,
    a.lesson_date,
    a.year_month,
    a.student_id,
    a.teacher_id,
    a.subject_id,
    a.business_entity_id,
    a.start_time,
    a.end_time,
    a.duration_hours,
    a.unit_price,
    a.lesson_fee,
    a.status,
    a.is_billable,
    a.lesson_count,
    a.actual_minutes,
    a.planned_lesson_id,
    a.teacher_settlement_month,
    a.lesson_content,
    a.note,
    a.created_at,
    a.updated_at
  from public.school_lesson_records a
  where a.id = v_actual_id;
end;
$function$;


revoke all on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) to anon,authenticated,service_role;

do $verify$
declare v_writer regprocedure :=
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_writer))<>'fcbb8a4c48cf62c285de45238b219e43'
     or not has_function_privilege('anon',v_writer,'EXECUTE')
     or not has_function_privilege('authenticated',v_writer,'EXECUTE')
     or not has_function_privilege('service_role',v_writer,'EXECUTE')
     or has_function_privilege('public',v_writer,'EXECUTE') then
    raise exception 'CANCELLATION_WRITER_ROLLBACK_NOT_EXACT';
  end if;
end;
$verify$;

\if :cancellation_writer_rollback_commit
  commit;
  \echo 'CANCELLATION_WRITER_HARDENING_ROLLBACK_COMMIT'
\else
  rollback;
  \echo 'CANCELLATION_WRITER_HARDENING_ROLLBACK_REHEARSAL'
\endif
