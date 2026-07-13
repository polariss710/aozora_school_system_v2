-- school_student_profile_status_rpc.sql
-- RPC: public.school_create_student_profile / public.school_update_student_profile
-- Purpose: Allow v2 student management to maintain explicit student status.
-- Version: v10.3.57-student-status-profile-20260704
--
-- Scope:
-- - Adds new overloads with p_status for create/update profile RPCs.
-- - Valid statuses are active / paused / graduated / withdrawn.
-- - Does not alter table schema, historical rows, balances, settlements,
--   lessons, income, expense, wage, payment, Cash linkage, or account data.

create or replace function public.school_create_student_profile(
  p_name text,
  p_default_business_entity_id uuid default null,
  p_course_track text default null,
  p_preset_exchange_rate numeric default 0,
  p_wechat text default null,
  p_phone text default null,
  p_entrance_date date default null,
  p_target_schools text default null,
  p_note text default null,
  p_status text default 'active'
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  status text,
  course_track text,
  target_schools text,
  business_entity_id uuid,
  default_currency text,
  preset_exchange_rate numeric,
  wechat text,
  phone text,
  entrance_date date,
  note text,
  previous_balance_cny numeric,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_status text := coalesce(nullif(trim(coalesce(p_status, '')), ''), 'active');
  v_course_track text := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_schools text := nullif(trim(coalesce(p_target_schools, '')), '');
  v_wechat text := nullif(trim(coalesce(p_wechat, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_preset_exchange_rate numeric := coalesce(p_preset_exchange_rate, 0);
  v_business_entity_id uuid;
  v_target_school_count integer := 0;
  v_student_id uuid;
begin
  if v_name is null then
    raise exception '学生姓名不能为空。';
  end if;

  if v_status not in ('active', 'paused', 'graduated', 'withdrawn') then
    raise exception '学生状态无效：%。', v_status;
  end if;

  if v_course_track is not null
    and v_course_track not in ('science', 'humanities') then
    raise exception '文理区分无效：%。', v_course_track;
  end if;

  if v_preset_exchange_rate < 0 then
    raise exception '预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*)
    into v_target_school_count
    from regexp_split_to_table(v_target_schools, E'\\r?\\n') as item
    where nullif(trim(item), '') is not null;

    if v_target_school_count > 3 then
      raise exception '目标学校最多填写 3 个。';
    end if;
  end if;

  v_business_entity_id := public.school_assert_new_business_entity_allowed(
    coalesce(p_default_business_entity_id, public.school_primary_business_entity_id()),
    '新增学生'
  );

  insert into public.school_students (
    name,
    display_name,
    status,
    course_track,
    target_schools,
    business_entity_id,
    default_currency,
    preset_exchange_rate,
    wechat,
    phone,
    entrance_date,
    note,
    app_type
  )
  values (
    v_name,
    v_name,
    v_status,
    v_course_track,
    v_target_schools,
    v_business_entity_id,
    'CNY',
    v_preset_exchange_rate,
    v_wechat,
    v_phone,
    p_entrance_date,
    v_note,
    'school'
  )
  returning id into v_student_id;

  return query
  select
    s.id,
    s.student_code,
    s.name,
    s.display_name,
    s.status,
    s.course_track,
    s.target_schools,
    s.business_entity_id,
    s.default_currency,
    s.preset_exchange_rate,
    s.wechat,
    s.phone,
    s.entrance_date,
    s.note,
    s.previous_balance_cny,
    s.created_at,
    s.updated_at
  from public.school_students s
  where s.id = v_student_id;
end;
$$;

comment on function public.school_create_student_profile(
  text,
  uuid,
  text,
  numeric,
  text,
  text,
  date,
  text,
  text,
  text
) is
  'Creates one narrowed v2 student profile row with explicit status. Only writes safe student master/contact fields and does not modify settlement, income, lesson, wage, payment, expense, Cash, or account data.';

grant execute on function public.school_create_student_profile(
  text,
  uuid,
  text,
  numeric,
  text,
  text,
  date,
  text,
  text,
  text
) to anon, authenticated, service_role;

create or replace function public.school_update_student_profile(
  p_student_id uuid,
  p_name text,
  p_default_business_entity_id uuid default null,
  p_course_track text default null,
  p_preset_exchange_rate numeric default 0,
  p_wechat text default null,
  p_phone text default null,
  p_entrance_date date default null,
  p_target_schools text default null,
  p_note text default null,
  p_status text default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  status text,
  course_track text,
  target_schools text,
  business_entity_id uuid,
  default_currency text,
  preset_exchange_rate numeric,
  wechat text,
  phone text,
  entrance_date date,
  note text,
  previous_balance_cny numeric,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_student public.school_students%rowtype;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_status text;
  v_course_track text := nullif(trim(coalesce(p_course_track, '')), '');
  v_target_schools text := nullif(trim(coalesce(p_target_schools, '')), '');
  v_wechat text := nullif(trim(coalesce(p_wechat, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_preset_exchange_rate numeric := coalesce(p_preset_exchange_rate, 0);
  v_business_entity_id uuid;
  v_target_school_count integer := 0;
begin
  if p_student_id is null then
    raise exception '请选择要编辑的学生。';
  end if;

  if v_name is null then
    raise exception '学生姓名不能为空。';
  end if;

  if v_course_track is not null
    and v_course_track not in ('science', 'humanities') then
    raise exception '文理区分无效：%。', v_course_track;
  end if;

  if v_preset_exchange_rate < 0 then
    raise exception '预设汇率不能为负数。';
  end if;

  if v_target_schools is not null then
    select count(*)
    into v_target_school_count
    from regexp_split_to_table(v_target_schools, E'\\r?\\n') as item
    where nullif(trim(item), '') is not null;

    if v_target_school_count > 3 then
      raise exception '目标学校最多填写 3 个。';
    end if;
  end if;

  if p_default_business_entity_id is not null
    and not exists (
      select 1
      from public.school_business_entities b
      where b.id = p_default_business_entity_id
        and coalesce(b.is_active, true) = true
    ) then
    raise exception '默认业务归属不存在或已停用。';
  end if;

  select *
  into v_student
  from public.school_students s
  where s.id = p_student_id
    and coalesce(s.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '学生不存在。';
  end if;

  v_status := coalesce(nullif(trim(coalesce(p_status, '')), ''), v_student.status, 'active');
  if v_status not in ('active', 'paused', 'graduated', 'withdrawn') then
    raise exception '学生状态无效：%。', v_status;
  end if;

  if p_default_business_entity_id is distinct from v_student.business_entity_id then
    v_business_entity_id := public.school_assert_new_business_entity_allowed(
      p_default_business_entity_id,
      '更新学生默认业务归属'
    );
  else
    v_business_entity_id := p_default_business_entity_id;
  end if;

  update public.school_students s
  set
    name = v_name,
    display_name = v_name,
    status = v_status,
    course_track = v_course_track,
    target_schools = v_target_schools,
    business_entity_id = v_business_entity_id,
    preset_exchange_rate = v_preset_exchange_rate,
    wechat = v_wechat,
    phone = v_phone,
    entrance_date = p_entrance_date,
    note = v_note,
    updated_at = v_now
  where s.id = v_student.id;

  return query
  select
    s.id,
    s.student_code,
    s.name,
    s.display_name,
    s.status,
    s.course_track,
    s.target_schools,
    s.business_entity_id,
    s.default_currency,
    s.preset_exchange_rate,
    s.wechat,
    s.phone,
    s.entrance_date,
    s.note,
    s.previous_balance_cny,
    s.updated_at
  from public.school_students s
  where s.id = v_student.id;
end;
$$;

comment on function public.school_update_student_profile(
  uuid,
  text,
  uuid,
  text,
  numeric,
  text,
  text,
  date,
  text,
  text,
  text
) is
  'Updates narrowed v2 student profile/contact/default fields including explicit status; does not modify balances, settlements, income, lessons, wage, payment, expense, Cash, or account data.';

grant execute on function public.school_update_student_profile(
  uuid,
  text,
  uuid,
  text,
  numeric,
  text,
  text,
  date,
  text,
  text,
  text
) to anon, authenticated, service_role;
