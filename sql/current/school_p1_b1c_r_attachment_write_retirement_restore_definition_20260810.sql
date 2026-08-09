-- P1-B1C-R exact pre-change restoration definition.
-- DO NOT EXECUTE without a separate incident/business authorization.
-- Restores only the P1-B1C-R permission surface; never touches object or metadata rows.
\set ON_ERROR_STOP on
\pset pager off

begin;

drop trigger school_expense_files_write_retired_guard on storage.objects;
drop function public.school_guard_retired_expense_file_writes();

create policy school_allow_all_storage_expense_files_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='school-expense-files'
  and name ~ '^expenses/[0-9]{4}-(0[1-9]|1[0-2])/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[^/]+$'
  and exists (
    select 1 from public.school_get_current_app_membership() m
    where m.role='admin' and m.is_active
  )
  and exists (
    select 1 from public.school_expense_records e
    where e.id::text=split_part(name,'/',3)
      and e.app_type='school'
      and e.year_month=split_part(name,'/',2)
      and e.expense_category is distinct from 'teacher_wage'
  )
);
create policy school_allow_all_storage_expense_files_update
on storage.objects for update to authenticated using(false) with check(false);
create policy school_allow_all_storage_expense_files_delete
on storage.objects for delete to authenticated using(false);

create policy school_allow_all_expense_attachments
on public.school_expense_attachments for all to authenticated
using(false) with check(false);

grant maintain on table public.school_expense_attachments
  to anon,authenticated,service_role;
grant execute on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)
  to authenticated;
comment on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text) is
  'Create metadata-only attachment summaries for ordinary school expenses. Does not upload, download, preview, delete, OCR, or mutate expense/account/reimbursement/account transaction state.';

commit;
