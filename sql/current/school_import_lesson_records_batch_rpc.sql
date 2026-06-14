-- school_import_lesson_records_batch_rpc.sql
-- RPC: public.school_import_lesson_records_batch
-- Purpose: Batch import planned lesson records from validated preview rows.
-- Status: EXECUTED ON SUPABASE. Rollback-tested, guard-tested, and commit-tested.
-- Version: v2.60.0-lesson-planned-only-batch-import-20260608
--
-- Scope:
-- - Insert validated planned rows into public.school_lesson_records only.
-- - Accepts only lesson_type = planned.
-- - Accepts only planned status values planned / pending_makeup.
-- - Uses all-or-nothing validation: any row error returns row errors and writes
--   no lesson records.
-- - Keeps the general RPC name so a future history-migration phase can extend
--   actual branches only if needed.
--
-- Direction note:
-- - The earlier full lesson batch import design is retained only as future /
--   history-migration backlog. This implementation intentionally does not write
--   completed, cancelled, or makeup_completed actual rows.
--
-- Not supported:
-- - Importing actual rows.
-- - Creating planned_lesson_id links.
-- - Auto-matching planned rows.
-- - Editing, deleting, or rewriting existing lesson records.
-- - Creating or updating student settlements, teacher wage locks/details,
--   payment requests, income, expense, accounts, or account transactions.
-- - Partial success imports.
--
-- Verification:
-- - Function exists with expected signature and return columns.
-- - Rollback test covered planned status planned and pending_makeup; rollback
--   left no residue and confirmed planned_lesson_id, actual_minutes, and
--   teacher_settlement_month remain null.
-- - Guard tests covered actual-row rejection, locked student settlement month,
--   and import_batch_id re-entry.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox
--   planned lessons for 2027-01:
--   planned 62288630-2005-4ace-be9d-34343d715bc2,
--   pending_makeup b04ca01d-ed3d-4a06-8e63-17a29d3e2a0d.
-- - No student settlement, teacher wage, payment request, income, expense,
--   account, or account transaction rows were generated or modified by the RPC.

create or replace function public.school_import_lesson_records_batch(
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
  v_batch_id_text text := p_import_batch_id::text;
  v_source_file_name text := nullif(trim(coalesce(p_source_file_name, '')), '');
  v_source_file_hash text := nullif(trim(coalesce(p_source_file_hash, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_row_count integer;
  v_has_errors boolean;
begin
  if p_import_batch_id is null then
    raise exception 'import_batch_id 不能为空。';
  end if;

  if v_source_file_name is null then
    raise exception 'source_file_name 不能为空。';
  end if;

  if v_source_file_hash is null then
    raise exception 'source_file_hash 不能为空。';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows 必须是 JSON array。';
  end if;

  select count(*)
  into v_row_count
  from jsonb_array_elements(p_rows);

  if v_row_count <= 0 then
    raise exception '导入行不能为空。';
  end if;

  if v_row_count > 500 then
    raise exception '单次导入最多支持 500 行。';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('school_import_lesson_records_batch'),
    hashtext(v_batch_id_text)
  );

  create temp table lesson_import_rows (
    row_index integer,
    source_row_no integer,
    row_key text,
    lesson_type text,
    status text,
    lesson_date date,
    year_month text,
    start_time text,
    end_time text,
    duration_hours numeric,
    lesson_count integer,
    unit_price numeric,
    lesson_fee numeric,
    is_billable_input boolean,
    student_id uuid,
    teacher_id uuid,
    subject_id uuid,
    business_entity_id uuid,
    planned_lesson_id uuid,
    lesson_content text,
    note text,
    import_source text,
    created_lesson_id uuid,
    warnings text[] not null default array[]::text[],
    errors text[] not null default array[]::text[]
  ) on commit drop;

  insert into lesson_import_rows (
    row_index,
    source_row_no,
    row_key,
    lesson_type,
    status,
    lesson_date,
    start_time,
    end_time,
    duration_hours,
    lesson_count,
    unit_price,
    lesson_fee,
    is_billable_input,
    student_id,
    teacher_id,
    subject_id,
    business_entity_id,
    planned_lesson_id,
    lesson_content,
    note
  )
  select
    r.row_index,
    r.source_row_no,
    nullif(trim(coalesce(r.row_key, '')), ''),
    lower(nullif(trim(coalesce(r.lesson_type, '')), '')),
    lower(nullif(trim(coalesce(r.status, '')), '')),
    r.lesson_date,
    nullif(trim(coalesce(r.start_time, '')), ''),
    nullif(trim(coalesce(r.end_time, '')), ''),
    r.duration_hours,
    r.lesson_count,
    r.unit_price,
    r.lesson_fee,
    r.is_billable,
    r.student_id,
    r.teacher_id,
    r.subject_id,
    r.business_entity_id,
    r.planned_lesson_id,
    nullif(trim(coalesce(r.lesson_content, '')), ''),
    nullif(trim(coalesce(r.note, '')), '')
  from jsonb_to_recordset(p_rows) as r(
    row_index integer,
    source_row_no integer,
    row_key text,
    lesson_type text,
    status text,
    lesson_date date,
    start_time text,
    end_time text,
    duration_hours numeric,
    lesson_count integer,
    unit_price numeric,
    lesson_fee numeric,
    is_billable boolean,
    student_id uuid,
    teacher_id uuid,
    subject_id uuid,
    business_entity_id uuid,
    planned_lesson_id uuid,
    lesson_content text,
    note text
  );

  update lesson_import_rows r
  set errors = r.errors || array['import_batch_id 已存在，不能重复导入同一批次。']
  where exists (
    select 1
    from public.school_lesson_records l
    where l.import_batch_id = v_batch_id_text
  );

  update lesson_import_rows r
  set errors = r.errors || array['row_index 不能为空。']
  where r.row_index is null;

  update lesson_import_rows r
  set errors = r.errors || array['row_index 在本批内重复。']
  where r.row_index in (
    select d.row_index
    from lesson_import_rows d
    where d.row_index is not null
    group by d.row_index
    having count(*) > 1
  );

  update lesson_import_rows r
  set errors = r.errors || array['lesson_type 不能为空。']
  where r.lesson_type is null;

  update lesson_import_rows r
  set errors = r.errors || array['当前批量导入第一版仅支持预定课时。']
  where r.lesson_type is not null
    and r.lesson_type <> 'planned';

  update lesson_import_rows r
  set errors = r.errors || array['status 不能为空。']
  where r.status is null;

  update lesson_import_rows r
  set errors = r.errors || array['预定课时 status 必须是 planned 或 pending_makeup。']
  where r.lesson_type = 'planned'
    and r.status is not null
    and r.status not in ('planned', 'pending_makeup');

  update lesson_import_rows r
  set errors = r.errors || array['lesson_date 不能为空。']
  where r.lesson_date is null;

  update lesson_import_rows r
  set errors = r.errors || array['学生不能为空。']
  where r.student_id is null;

  update lesson_import_rows r
  set errors = r.errors || array['老师不能为空。']
  where r.teacher_id is null;

  update lesson_import_rows r
  set errors = r.errors || array['科目不能为空。']
  where r.subject_id is null;

  update lesson_import_rows r
  set errors = r.errors || array['业务归属不能为空。']
  where r.business_entity_id is null;

  update lesson_import_rows r
  set errors = r.errors || array['课时时长必须大于 0。']
  where coalesce(r.duration_hours, 0) <= 0;

  update lesson_import_rows r
  set errors = r.errors || array['课程单价不能小于 0。']
  where coalesce(r.unit_price, 0) < 0;

  update lesson_import_rows r
  set errors = r.errors || array['课时金额不能小于 0。']
  where r.lesson_fee is not null
    and r.lesson_fee < 0;

  update lesson_import_rows r
  set errors = r.errors || array['课次数必须大于 0。']
  where r.lesson_count is not null
    and r.lesson_count <= 0;

  update lesson_import_rows r
  set errors = r.errors || array['开始时间格式无效，请使用 HH:MM。']
  where r.start_time is not null
    and r.start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';

  update lesson_import_rows r
  set errors = r.errors || array['结束时间格式无效，请使用 HH:MM。']
  where r.end_time is not null
    and r.end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';

  update lesson_import_rows r
  set errors = r.errors || array['预定课时导入不允许填写 planned_lesson_id。']
  where r.planned_lesson_id is not null;

  update lesson_import_rows r
  set
    year_month = to_char(r.lesson_date, 'YYYY-MM'),
    unit_price = coalesce(r.unit_price, 0),
    lesson_fee = case
      when r.lesson_fee is not null then r.lesson_fee
      else round(coalesce(r.duration_hours, 0) * coalesce(r.unit_price, 0))
    end,
    import_source = concat_ws(
      ' | ',
      'lesson_planned_batch_import',
      v_source_file_name,
      v_source_file_hash,
      'row=' || coalesce(r.row_index::text, ''),
      'source_row=' || coalesce(r.source_row_no::text, ''),
      case when r.row_key is not null then 'key=' || r.row_key else null end
    )
  where true;

  update lesson_import_rows r
  set errors = r.errors || array['学生无效或不可用。']
  where r.student_id is not null
    and not exists (
      select 1
      from public.school_students s
      where s.id = r.student_id
        and s.app_type = 'school'
        and coalesce(s.status, 'active') not in ('inactive', 'graduated')
    );

  update lesson_import_rows r
  set errors = r.errors || array['学生默认业务归属与课时业务归属不一致。']
  where exists (
    select 1
    from public.school_students s
    where s.id = r.student_id
      and s.app_type = 'school'
      and coalesce(s.status, 'active') not in ('inactive', 'graduated')
      and s.business_entity_id is not null
      and s.business_entity_id is distinct from r.business_entity_id
  );

  update lesson_import_rows r
  set errors = r.errors || array['老师无效或不可用。']
  where r.teacher_id is not null
    and not exists (
      select 1
      from public.school_teachers t
      where t.id = r.teacher_id
        and t.app_type = 'school'
        and coalesce(t.status, 'employed') not in ('inactive', 'retired')
    );

  update lesson_import_rows r
  set errors = r.errors || array['科目无效或已停用。']
  where r.subject_id is not null
    and not exists (
      select 1
      from public.school_subjects s
      where s.id = r.subject_id
        and coalesce(s.is_active, true) = true
    );

  update lesson_import_rows r
  set errors = r.errors || array['业务归属无效或已停用。']
  where r.business_entity_id is not null
    and not exists (
      select 1
      from public.school_business_entities b
      where b.id = r.business_entity_id
        and coalesce(b.is_active, true) = true
    );

  update lesson_import_rows r
  set errors = r.errors || array['目标学生月度结算已锁定，不能导入预定课时。']
  where exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = r.student_id
      and s.year_month = r.year_month
      and s.business_entity_id is not distinct from r.business_entity_id
      and s.settlement_status = 'locked'
  );

  select exists (
    select 1
    from lesson_import_rows r
    where cardinality(r.errors) > 0
  )
  into v_has_errors;

  if v_has_errors then
    return query
    select
      r.row_index,
      r.source_row_no,
      cardinality(r.errors) = 0,
      false,
      null::uuid,
      r.lesson_type,
      r.status,
      r.planned_lesson_id,
      r.warnings,
      r.errors,
      p_import_batch_id
    from lesson_import_rows r
    order by r.row_index nulls last, r.source_row_no nulls last;
    return;
  end if;

  update lesson_import_rows r
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
    r.student_id,
    r.teacher_id,
    r.subject_id,
    r.business_entity_id,
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
    v_batch_id_text,
    r.import_source,
    v_now,
    r.lesson_count,
    null,
    null
  from lesson_import_rows r
  order by r.row_index;

  return query
  select
    r.row_index,
    r.source_row_no,
    true,
    true,
    r.created_lesson_id,
    'planned'::text,
    r.status,
    null::uuid,
    r.warnings,
    r.errors,
    p_import_batch_id
  from lesson_import_rows r
  order by r.row_index;
end;
$$;
