-- school_generate_planned_lessons_batch_rpc.sql
-- Purpose: Generate planned school lesson records from DB/RPC-owned schedule rules.
--
-- Scope:
-- - Inserts planned rows into public.school_lesson_records only.
-- - The page submits schedule rules; DB/RPC generates dates, duration, and
--   lesson_fee, then performs all-or-nothing validation before insert.
-- - Does not create actual lessons, settlements, wages, payment requests,
--   income, expenses, accounts, Cash requests, or account transactions.

create or replace function public.school_generate_planned_lessons_batch(
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
  v_generation_id_text text := p_generation_id::text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_row_count integer;
  v_has_errors boolean;
  v_student_business_entity_id uuid;
begin
  if p_generation_id is null then
    raise exception 'generation_id 不能为空。';
  end if;

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '批量生成预定课时'
  );

  if p_start_date is null or p_end_date is null then
    raise exception '请选择生成开始日期和结束日期。';
  end if;

  if p_end_date < p_start_date then
    raise exception '结束日期不能早于开始日期。';
  end if;

  if p_end_date - p_start_date > 370 then
    raise exception '单次生成最多支持 370 天范围。';
  end if;

  if p_patterns is null or jsonb_typeof(p_patterns) <> 'array' then
    raise exception '课程规则必须是 JSON array。';
  end if;

  if p_excluded_occurrences is null or jsonb_typeof(p_excluded_occurrences) <> 'array' then
    raise exception '排除课时必须是 JSON array。';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('school_generate_planned_lessons_batch'),
    hashtext(v_generation_id_text)
  );

  if exists (
    select 1
    from public.school_lesson_records l
    where l.import_batch_id = v_generation_id_text
  ) then
    raise exception '该批量生成 ID 已经写入过课时，不能重复提交。';
  end if;

  select s.business_entity_id
  into v_student_business_entity_id
  from public.school_students s
  where s.id = p_student_id
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null
    and v_student_business_entity_id is distinct from p_business_entity_id then
    raise exception '学生默认业务归属与课时业务归属不一致。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = p_business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;

  create temp table planned_lesson_generation_patterns (
    pattern_index integer,
    weekday integer,
    status text,
    teacher_id uuid,
    subject_id uuid,
    start_time text,
    end_time text,
    duration_hours numeric,
    unit_price numeric,
    occurrence_count integer,
    lesson_count integer,
    lesson_content text,
    note text,
    warnings text[] not null default array[]::text[],
    errors text[] not null default array[]::text[]
  ) on commit drop;

  insert into planned_lesson_generation_patterns (
    pattern_index,
    weekday,
    status,
    teacher_id,
    subject_id,
    start_time,
    end_time,
    duration_hours,
    unit_price,
    occurrence_count,
    lesson_count,
    lesson_content,
    note
  )
  select
    r.pattern_index,
    r.weekday,
    lower(nullif(trim(coalesce(r.status, 'planned')), '')),
    r.teacher_id,
    r.subject_id,
    nullif(trim(coalesce(r.start_time, '')), ''),
    nullif(trim(coalesce(r.end_time, '')), ''),
    r.duration_hours,
    r.unit_price,
    coalesce(r.occurrence_count, 1),
    r.lesson_count,
    nullif(trim(coalesce(r.lesson_content, '')), ''),
    nullif(trim(coalesce(r.note, '')), '')
  from jsonb_to_recordset(p_patterns) as r(
    pattern_index integer,
    weekday integer,
    status text,
    teacher_id uuid,
    subject_id uuid,
    start_time text,
    end_time text,
    duration_hours numeric,
    unit_price numeric,
    occurrence_count integer,
    lesson_count integer,
    lesson_content text,
    note text
  );

  select count(*)
  into v_row_count
  from planned_lesson_generation_patterns;

  if v_row_count <= 0 then
    raise exception '至少需要一条课程规则。';
  end if;

  if v_row_count > 50 then
    raise exception '单次最多支持 50 条课程规则。';
  end if;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['课程规则序号不能为空。']
  where p.pattern_index is null;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['课程规则序号重复。']
  where p.pattern_index in (
    select d.pattern_index
    from planned_lesson_generation_patterns d
    where d.pattern_index is not null
    group by d.pattern_index
    having count(*) > 1
  );

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['星期必须是 0-6。']
  where p.weekday is null
     or p.weekday < 0
     or p.weekday > 6;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['预定课时状态必须是 planned 或 pending_makeup。']
  where p.status is null
     or p.status not in ('planned', 'pending_makeup');

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['老师不能为空。']
  where p.teacher_id is null;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['科目不能为空。']
  where p.subject_id is null;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['老师无效或不可用。']
  where p.teacher_id is not null
    and not exists (
      select 1
      from public.school_teachers t
      where t.id = p.teacher_id
        and t.app_type = 'school'
        and coalesce(t.status, 'employed') not in ('inactive', 'retired')
    );

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['科目无效或已停用。']
  where p.subject_id is not null
    and not exists (
      select 1
      from public.school_subjects s
      where s.id = p.subject_id
        and coalesce(s.is_active, true) = true
    );

  update planned_lesson_generation_patterns p
  set
    start_time = null,
    end_time = null,
    warnings = p.warnings || array['开始/结束时间未完整填写或格式无效，已按课时生成并不写入时间。']
  where coalesce(p.duration_hours, 0) > 0
    and (
      p.start_time is null
      or p.end_time is null
      or p.start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or p.end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    );

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['开始时间格式无效，请使用 HH:MM。']
  where p.start_time is not null
    and p.start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['结束时间格式无效，请使用 HH:MM。']
  where p.end_time is not null
    and p.end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';

  update planned_lesson_generation_patterns p
  set
    duration_hours = round(
      (
        case
          when (
            split_part(p.end_time, ':', 1)::integer * 60
            + split_part(p.end_time, ':', 2)::integer
          ) > (
            split_part(p.start_time, ':', 1)::integer * 60
            + split_part(p.start_time, ':', 2)::integer
          )
            then (
              split_part(p.end_time, ':', 1)::integer * 60
              + split_part(p.end_time, ':', 2)::integer
            ) - (
              split_part(p.start_time, ':', 1)::integer * 60
              + split_part(p.start_time, ':', 2)::integer
            )
          when (
            split_part(p.end_time, ':', 1)::integer * 60
            + split_part(p.end_time, ':', 2)::integer
          ) < (
            split_part(p.start_time, ':', 1)::integer * 60
            + split_part(p.start_time, ':', 2)::integer
          )
            then (
              split_part(p.end_time, ':', 1)::integer * 60
              + split_part(p.end_time, ':', 2)::integer
              + 1440
            ) - (
              split_part(p.start_time, ':', 1)::integer * 60
              + split_part(p.start_time, ':', 2)::integer
            )
          else 0
        end
      )::numeric / 60,
      2
    ),
    warnings = p.warnings || array['课时为空，已由 DB/RPC 按开始/结束时间计算。']
  where coalesce(p.duration_hours, 0) <= 0
    and p.start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    and p.end_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['课时时长必须大于 0；如未填写课时，必须提供有效开始/结束时间供 DB/RPC 计算。']
  where coalesce(p.duration_hours, 0) <= 0;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['课程单价不能小于 0。']
  where coalesce(p.unit_price, 0) < 0;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['次数必须是 1-10 的正整数。']
  where p.occurrence_count is null
     or p.occurrence_count <= 0
     or p.occurrence_count > 10;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['回数必须大于 0。']
  where p.lesson_count is not null
    and p.lesson_count <= 0;

  update planned_lesson_generation_patterns p
  set errors = p.errors || array['课程规则重复，请删除或调整重复规则。']
  where exists (
    select 1
    from planned_lesson_generation_patterns d
    where d.pattern_index is distinct from p.pattern_index
      and d.pattern_index < p.pattern_index
      and d.weekday is not distinct from p.weekday
      and d.status is not distinct from p.status
      and d.teacher_id is not distinct from p.teacher_id
      and d.subject_id is not distinct from p.subject_id
      and d.start_time is not distinct from p.start_time
      and d.end_time is not distinct from p.end_time
      and d.duration_hours is not distinct from p.duration_hours
      and d.unit_price is not distinct from p.unit_price
      and d.occurrence_count is not distinct from p.occurrence_count
      and d.lesson_count is not distinct from p.lesson_count
      and d.lesson_content is not distinct from p.lesson_content
      and d.note is not distinct from p.note
  );

  select exists (
    select 1
    from planned_lesson_generation_patterns p
    where cardinality(p.errors) > 0
  )
  into v_has_errors;

  if v_has_errors then
    return query
    select
      p.pattern_index,
      p.pattern_index,
      null::date,
      false,
      false,
      null::uuid,
      p.status,
      p.warnings,
      p.errors,
      p_generation_id
    from planned_lesson_generation_patterns p
    order by p.pattern_index nulls last;
    return;
  end if;

  create temp table planned_lesson_generation_exclusions (
    pattern_index integer,
    lesson_date date,
    occurrence_index integer
  ) on commit drop;

  insert into planned_lesson_generation_exclusions (
    pattern_index,
    lesson_date,
    occurrence_index
  )
  select
    e.pattern_index,
    e.lesson_date,
    e.occurrence_index
  from jsonb_to_recordset(p_excluded_occurrences) as e(
    pattern_index integer,
    lesson_date date,
    occurrence_index integer
  )
  where e.pattern_index is not null
    and e.lesson_date is not null;

  create temp table planned_lesson_generation_rows (
    row_index integer,
    pattern_index integer,
    occurrence_index integer,
    lesson_date date,
    year_month text,
    status text,
    teacher_id uuid,
    subject_id uuid,
    start_time text,
    end_time text,
    duration_hours numeric,
    unit_price numeric,
    lesson_fee numeric,
    lesson_count integer,
    lesson_content text,
    note text,
    created_lesson_id uuid,
    warnings text[] not null default array[]::text[],
    errors text[] not null default array[]::text[]
  ) on commit drop;

  insert into planned_lesson_generation_rows (
    row_index,
    pattern_index,
    occurrence_index,
    lesson_date,
    year_month,
    status,
    teacher_id,
    subject_id,
    start_time,
    end_time,
    duration_hours,
    unit_price,
    lesson_fee,
    lesson_count,
    lesson_content,
    note,
    warnings
  )
  select
    row_number() over (order by w.lesson_date, p.pattern_index, o.occurrence_index)::integer,
    p.pattern_index,
    o.occurrence_index,
    w.lesson_date,
    to_char(w.lesson_date, 'YYYY-MM'),
    p.status,
    p.teacher_id,
    p.subject_id,
    p.start_time,
    p.end_time,
    p.duration_hours,
    coalesce(p.unit_price, 0),
    round(p.duration_hours * coalesce(p.unit_price, 0)),
    case
      when p.lesson_count is null and p.occurrence_count > 1 then o.occurrence_index
      when p.lesson_count is null then null
      else p.lesson_count + o.occurrence_index - 1
    end,
    p.lesson_content,
    p.note,
    p.warnings
  from planned_lesson_generation_patterns p
  cross join lateral generate_series(p_start_date, p_end_date, interval '1 day') as gs(lesson_date)
  cross join lateral (select gs.lesson_date::date as lesson_date) d
  cross join lateral (
    select (d.lesson_date - ((extract(dow from d.lesson_date)::integer + 6) % 7))::date as lesson_date
  ) w
  cross join lateral generate_series(1, p.occurrence_count) as o(occurrence_index)
  where extract(dow from d.lesson_date)::integer = p.weekday
    and not exists (
      select 1
      from planned_lesson_generation_exclusions x
      where x.pattern_index = p.pattern_index
        and x.lesson_date = w.lesson_date
        and (
          x.occurrence_index is null
          or x.occurrence_index = o.occurrence_index
        )
    );

  select count(*)
  into v_row_count
  from planned_lesson_generation_rows;

  if v_row_count <= 0 then
    raise exception '当前规则和排除项没有生成任何课时。';
  end if;

  if v_row_count > 500 then
    raise exception '单次最多生成 500 条预定课时。';
  end if;

  update planned_lesson_generation_rows r
  set errors = r.errors || array['目标学生月度结算已锁定，不能生成预定课时。']
  where exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.year_month = (
        select attribution.billing_month
        from public.school_resolve_planned_billing_attribution(
          null,
          r.lesson_date
        ) attribution
      )
      and s.business_entity_id is not distinct from p_business_entity_id
      and s.settlement_status = 'locked'
  );

  update planned_lesson_generation_rows r
  set errors = r.errors || array['展开后生成了重复课时，请删除或调整重复规则。']
  where exists (
    select 1
    from planned_lesson_generation_rows d
    where d.row_index < r.row_index
      and d.lesson_date is not distinct from r.lesson_date
      and d.status is not distinct from r.status
      and d.teacher_id is not distinct from r.teacher_id
      and d.subject_id is not distinct from r.subject_id
      and d.start_time is not distinct from r.start_time
      and d.end_time is not distinct from r.end_time
      and d.duration_hours is not distinct from r.duration_hours
      and d.unit_price is not distinct from r.unit_price
      and d.lesson_count is not distinct from r.lesson_count
      and d.lesson_content is not distinct from r.lesson_content
      and d.note is not distinct from r.note
  );

  update planned_lesson_generation_rows r
  set errors = r.errors || array['目标课时已存在，不能重复生成同一条预定课时。']
  where exists (
    select 1
    from public.school_lesson_records l
    where l.app_type = 'school'
      and l.lesson_type = 'planned'
      and coalesce(l.status, '') <> 'voided'
      and l.student_id = p_student_id
      and l.business_entity_id is not distinct from p_business_entity_id
      and l.lesson_date is not distinct from r.lesson_date
      and l.status is not distinct from r.status
      and l.teacher_id is not distinct from r.teacher_id
      and l.subject_id is not distinct from r.subject_id
      and l.start_time::text is not distinct from r.start_time
      and l.end_time::text is not distinct from r.end_time
      and l.duration_hours is not distinct from r.duration_hours
      and l.unit_price is not distinct from r.unit_price
      and l.lesson_count is not distinct from r.lesson_count
      and nullif(trim(coalesce(l.lesson_content, '')), '') is not distinct from r.lesson_content
  );

  select exists (
    select 1
    from planned_lesson_generation_rows r
    where cardinality(r.errors) > 0
  )
  into v_has_errors;

  if v_has_errors then
    return query
    select
      r.row_index,
      r.pattern_index,
      r.lesson_date,
      cardinality(r.errors) = 0,
      false,
      null::uuid,
      r.status,
      r.warnings,
      r.errors,
      p_generation_id
    from planned_lesson_generation_rows r
    order by r.row_index;
    return;
  end if;

  update planned_lesson_generation_rows r
  set created_lesson_id = gen_random_uuid()
  where true;

  insert into public.school_lesson_records (
    id,
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
  select
    r.created_lesson_id,
    'planned',
    r.lesson_date,
    r.year_month,
    p_student_id,
    r.teacher_id,
    r.subject_id,
    p_business_entity_id,
    r.start_time,
    r.end_time,
    r.duration_hours,
    r.lesson_content,
    r.status,
    true,
    nullif(concat_ws(E'\n', r.note, v_note), ''),
    'school',
    null,
    r.unit_price,
    r.lesson_fee,
    v_generation_id_text,
    concat_ws(
      ' | ',
      'lesson_planned_batch_generator',
      'generation=' || v_generation_id_text,
      'pattern=' || r.pattern_index::text,
      'occurrence=' || r.occurrence_index::text
    ),
    v_now,
    r.lesson_count,
    null,
    null
  from planned_lesson_generation_rows r
  order by r.row_index;

  return query
  select
    r.row_index,
    r.pattern_index,
    r.lesson_date,
    true,
    true,
    r.created_lesson_id,
    r.status,
    r.warnings,
    r.errors,
    p_generation_id
  from planned_lesson_generation_rows r
  order by r.row_index;
end;
$$;

comment on function public.school_generate_planned_lessons_batch(
  uuid,
  uuid,
  uuid,
  date,
  date,
  jsonb,
  jsonb,
  text
) is
  'Generates planned school lesson records from schedule rules. DB/RPC owns date expansion, duration calculation, fee calculation, locked-settlement guards, and all-or-nothing insert. Does not create actual, settlement, wage, payment, income, expense, account, Cash, or account transaction rows.';

revoke all on function public.school_generate_planned_lessons_batch(
  uuid,
  uuid,
  uuid,
  date,
  date,
  jsonb,
  jsonb,
  text
) from public, anon, authenticated;

grant execute on function public.school_generate_planned_lessons_batch(
  uuid,
  uuid,
  uuid,
  date,
  date,
  jsonb,
  jsonb,
  text
) to authenticated;
