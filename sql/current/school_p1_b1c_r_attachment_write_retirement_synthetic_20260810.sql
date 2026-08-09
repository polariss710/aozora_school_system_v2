-- Synthetic-only contract for P1-B1C-R. Never run against production.
\set ON_ERROR_STOP on
\pset pager off

drop schema if exists storage cascade;
drop schema if exists auth cascade;
drop table if exists public.school_expense_attachments cascade;
drop function if exists public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text);
drop function if exists public.school_guard_retired_expense_file_writes();
drop role if exists anon;
drop role if exists authenticated;
drop role if exists service_role;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;

create table storage.buckets(id text primary key,public boolean not null default false);
create table storage.objects(
  id uuid primary key,
  bucket_id text not null references storage.buckets(id),
  name text not null,
  metadata jsonb not null default '{}'::jsonb
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert,update,delete on storage.objects to anon,authenticated,service_role;

insert into storage.buckets(id,public) values ('school-expense-files',false),('unrelated-bucket',false);
insert into storage.objects(id,bucket_id,name,metadata) values
  ('00000000-0000-4000-8000-000000000001','school-expense-files','expenses/2026-01/00000000-0000-4000-8000-000000000010/a.pdf','{"size":1}'),
  ('00000000-0000-4000-8000-000000000002','unrelated-bucket','unrelated.txt','{"size":2}');

create policy school_allow_all_storage_expense_files_select on storage.objects
  for select to authenticated using (bucket_id='school-expense-files');
create policy school_allow_all_storage_expense_files_insert on storage.objects
  for insert to authenticated with check (bucket_id='school-expense-files');
create policy school_allow_all_storage_expense_files_update on storage.objects
  for update to authenticated using(false) with check(false);
create policy school_allow_all_storage_expense_files_delete on storage.objects
  for delete to authenticated using(false);
create policy synthetic_unrelated_bucket_all on storage.objects
  for all to authenticated using(bucket_id='unrelated-bucket') with check(bucket_id='unrelated-bucket');

create table public.school_expense_attachments(
  id uuid primary key,
  expense_id uuid not null,
  storage_bucket text not null,
  storage_path text not null,
  file_name text not null
);
alter table public.school_expense_attachments enable row level security;
grant select,maintain on public.school_expense_attachments to anon,authenticated,service_role;
create policy school_allow_all_expense_attachments on public.school_expense_attachments
  for all to authenticated using(false) with check(false);
create policy school_expense_attachments_p0_phase2_authenticated_select
  on public.school_expense_attachments for select to authenticated using(true);
insert into public.school_expense_attachments values
  ('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000010',
   'school-expense-files','expenses/2026-01/00000000-0000-4000-8000-000000000010/a.pdf','a.pdf');

create function public.school_create_expense_attachment_metadata(
  p_expense_id uuid,p_file_name text,p_file_type text,p_file_size bigint,p_source_type text,p_note text
) returns uuid language sql security definer set search_path=pg_catalog,public
as $$select '00000000-0000-4000-8000-000000000099'::uuid$$;
revoke all on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)
  to authenticated;

-- Apply the exact production enforcement core.
create function public.school_guard_retired_expense_file_writes()
returns trigger language plpgsql security invoker set search_path=pg_catalog
as $function$
declare
  v_request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',
    current_user
  );
  v_targeted boolean := case tg_op
    when 'INSERT' then new.bucket_id='school-expense-files'
    when 'DELETE' then old.bucket_id='school-expense-files'
    when 'UPDATE' then old.bucket_id='school-expense-files' or new.bucket_id='school-expense-files'
    else false end;
begin
  if v_targeted and (current_user in ('anon','authenticated','service_role')
      or v_request_role in ('anon','authenticated','service_role')) then
    raise exception using errcode='42501',message='SCHOOL_EXPENSE_ATTACHMENT_WRITES_RETIRED';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.school_guard_retired_expense_file_writes()
  from public,anon,authenticated,service_role;
create trigger school_expense_files_write_retired_guard
before insert or update or delete on storage.objects
for each row execute function public.school_guard_retired_expense_file_writes();
drop policy school_allow_all_storage_expense_files_insert on storage.objects;
drop policy school_allow_all_storage_expense_files_update on storage.objects;
drop policy school_allow_all_storage_expense_files_delete on storage.objects;
drop policy school_allow_all_expense_attachments on public.school_expense_attachments;
revoke all on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)
  from public,anon,authenticated,service_role;
revoke insert,update,delete,truncate,references,trigger,maintain
  on public.school_expense_attachments from public,anon,authenticated,service_role;

-- Owner-side assertions: history retained, reader retained, overload exactly covered.
do $assert$
begin
  if (select count(*) from storage.objects where bucket_id='school-expense-files')<>1
     or (select count(*) from public.school_expense_attachments)<>1 then
    raise exception 'SYNTHETIC_HISTORY_CHANGED';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_create_expense_attachment_metadata')<>1 then
    raise exception 'SYNTHETIC_OVERLOAD_COVERAGE_FAILED';
  end if;
  if has_function_privilege('authenticated',
       'public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)'::regprocedure,'EXECUTE')
     or has_table_privilege('authenticated','public.school_expense_attachments','INSERT')
     or not has_table_privilege('authenticated','public.school_expense_attachments','SELECT') then
    raise exception 'SYNTHETIC_METADATA_PRIVILEGE_FAILED';
  end if;
end;
$assert$;
