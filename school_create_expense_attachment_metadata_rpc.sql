-- school_create_expense_attachment_metadata_rpc.sql
-- RPC: public.school_create_expense_attachment_metadata
-- Purpose: Create metadata-only attachment summaries for ordinary school expenses.
-- Status: EXECUTED ON SUPABASE. Rollback-tested and commit-tested.
-- Version: v2.51.0-expense-attachment-metadata-full-autopilot-20260607
--
-- Scope:
-- - Insert one row into public.school_expense_attachments.
-- - Allowed user-facing fields: expense_id, file_name, file_type, file_size,
--   source_type, note.
-- - Generate a metadata-only storage_path placeholder because the existing
--   table requires storage_path NOT NULL. This path is not a Supabase Storage
--   upload/download/preview integration.
--
-- Not supported:
-- - Uploading, downloading, previewing, replacing, or deleting files.
-- - OCR or extracted_text handling.
-- - public_url handling.
-- - Teacher wage expense attachments.
-- - Editing expense amount, status, account, account transactions,
--   reimbursement status, or historical records.
--
-- Verification:
-- - Function exists in public schema with expected signature and return columns.
-- - Rollback test inserted one codex-test attachment metadata row and left no residue.
-- - Commit test inserted only whitelisted codex-test / v2-test / sandbox
--   attachment metadata on ordinary test expense
--   536b9c01-b728-4e7a-a5bb-96173a83656d.
-- - Commit attachment id: ab22a5eb-96f8-4505-a873-1893bafecdbd.
-- - Expense amount/status/account/reimbursement status stayed unchanged.
-- - Account current_balance and account transaction count stayed unchanged.

create or replace function public.school_create_expense_attachment_metadata(
  p_expense_id uuid,
  p_file_name text,
  p_file_type text default null,
  p_file_size bigint default null,
  p_source_type text default 'manual_metadata',
  p_note text default null
)
returns table (
  attachment_id uuid,
  expense_id uuid,
  file_name text,
  file_type text,
  file_size bigint,
  source_type text,
  note text,
  app_type text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_expense public.school_expense_records%rowtype;
  v_attachment_id uuid := gen_random_uuid();
  v_file_name text := nullif(trim(coalesce(p_file_name, '')), '');
  v_file_type text := nullif(trim(coalesce(p_file_type, '')), '');
  v_source_type text := lower(nullif(trim(coalesce(p_source_type, 'manual_metadata')), ''));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_safe_file_name text;
  v_storage_path text;
begin
  if p_expense_id is null then
    raise exception '请选择支出记录。';
  end if;

  if v_file_name is null then
    raise exception '附件文件名不能为空。';
  end if;

  if length(v_file_name) > 255 then
    raise exception '附件文件名过长。';
  end if;

  if p_file_size is not null and p_file_size < 0 then
    raise exception '附件大小不能为负数。';
  end if;

  if v_source_type is null then
    v_source_type := 'manual_metadata';
  end if;

  if v_source_type not in ('manual', 'manual_metadata', 'receipt', 'invoice', 'statement', 'other') then
    raise exception '附件来源类型无效：%。', v_source_type;
  end if;

  select e.*
  into v_expense
  from public.school_expense_records e
  where e.id = p_expense_id
    and e.app_type = 'school';

  if not found then
    raise exception '支出记录不存在。';
  end if;

  if v_expense.expense_category = 'teacher_wage' then
    raise exception '老师工资支出不支持普通支出附件元数据。';
  end if;

  v_safe_file_name := regexp_replace(v_file_name, '[^A-Za-z0-9._-]+', '_', 'g');
  if nullif(v_safe_file_name, '') is null then
    v_safe_file_name := 'attachment-metadata';
  end if;

  v_storage_path := concat(
    'metadata-only/',
    p_expense_id::text,
    '/',
    v_attachment_id::text,
    '/',
    v_safe_file_name
  );

  insert into public.school_expense_attachments (
    id,
    expense_id,
    file_name,
    file_type,
    file_size,
    storage_path,
    source_type,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_attachment_id,
    p_expense_id,
    v_file_name,
    v_file_type,
    p_file_size,
    v_storage_path,
    v_source_type,
    v_note,
    'school',
    v_now,
    v_now
  );

  return query
  select
    a.id,
    a.expense_id,
    a.file_name,
    a.file_type,
    a.file_size,
    a.source_type,
    a.note,
    a.app_type,
    a.created_at,
    a.updated_at
  from public.school_expense_attachments a
  where a.id = v_attachment_id;
end;
$$;

comment on function public.school_create_expense_attachment_metadata(
  uuid,
  text,
  text,
  bigint,
  text,
  text
) is
'Create metadata-only attachment summaries for ordinary school expenses. Does not upload, download, preview, delete, OCR, or mutate expense/account/reimbursement/account transaction state.';
