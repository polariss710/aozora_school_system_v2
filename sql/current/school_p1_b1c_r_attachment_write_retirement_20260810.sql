-- V1 decommission P1-B1C-R: retire all expense-attachment write entry points.
-- Permission/object-definition changes only. This migration never writes Storage
-- objects, attachment metadata, or any School/Cash business row.
\set ON_ERROR_STOP on
\pset pager off

begin;

do $preflight$
declare
  v_policy_fingerprint text;
  v_metadata_acl name[];
begin
  if current_setting('transaction_read_only')::boolean then
    raise exception 'P1_B1C_R_WRITABLE_MIGRATION_TRANSACTION_REQUIRED';
  end if;

  if to_regclass('storage.buckets') is null
     or to_regclass('storage.objects') is null
     or to_regclass('public.school_expense_attachments') is null then
    raise exception 'P1_B1C_R_REQUIRED_RELATION_MISSING';
  end if;

  if (select count(*) from storage.buckets) <> 1
     or not exists (
       select 1 from storage.buckets
       where id='school-expense-files'
         and name='school-expense-files'
         and public=false
         and file_size_limit is null
         and allowed_mime_types is null
     ) then
    raise exception 'P1_B1C_R_BUCKET_DRIFT';
  end if;

  if not exists (
    select 1
    from (
      select count(*) object_count,
             count(distinct name) distinct_path_count,
             coalesce(sum((metadata->>'size')::bigint),0) total_bytes,
             md5(coalesce(string_agg(md5(concat_ws('|',id::text,bucket_id,name,
               coalesce(owner::text,''),coalesce(owner_id::text,''),coalesce(metadata::text,''),
               coalesce(created_at::text,''),coalesce(updated_at::text,''),coalesce(last_accessed_at::text,''))),
               '' order by id::text),'')) object_fingerprint,
             md5(coalesce(string_agg(md5(name),'' order by name),'')) path_fingerprint
      from storage.objects where bucket_id='school-expense-files'
    ) s
    where object_count=57 and distinct_path_count=57 and total_bytes=6936405
      and object_fingerprint='ec6522f59532814af6bbfbb1a90e1822'
      and path_fingerprint='554366526bc0a983efa58d8001b7f536'
  ) then
    raise exception 'P1_B1C_R_STORAGE_OBJECT_SNAPSHOT_DRIFT';
  end if;

  if not exists (
    with target as (
      select o.*,split_part(o.name,'/',3) expense_segment
      from storage.objects o where o.bucket_id='school-expense-files'
    ), classified as (
      select t.*,
        exists(select 1 from public.school_expense_attachments a
          where a.storage_bucket=t.bucket_id and a.storage_path=t.name) has_attachment,
        case when expense_segment ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then exists(select 1 from public.school_expense_records e where e.id=expense_segment::uuid)
          else false end has_expense
      from target t
    )
    select 1 from classified
    having count(*) filter(where has_attachment)=23
       and count(*) filter(where not has_attachment and has_expense)=4
       and count(*) filter(where not has_attachment and not has_expense)=30
       and md5(coalesce(string_agg(md5(concat_ws('|',id::text,name,coalesce(metadata::text,''))),'' order by id::text)
           filter(where not has_attachment and not has_expense),''))='3b17d8c87494da6404c213009132437e'
  ) then
    raise exception 'P1_B1C_R_ORPHAN_CLASSIFICATION_DRIFT';
  end if;

  select md5(coalesce(string_agg(md5(concat_ws('|',policyname,cmd,roles::text,
      permissive,coalesce(qual,''),coalesce(with_check,''))),'' order by policyname,cmd),''))
    into v_policy_fingerprint
  from pg_policies where schemaname='storage' and tablename='objects';

  if (select count(*) from pg_policies where schemaname='storage' and tablename='objects') <> 4
     or v_policy_fingerprint <> '52aa55fc0e750ea51058187417a302e1'
     or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
       and policyname='school_allow_all_storage_expense_files_select' and cmd='SELECT')
     or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
       and policyname='school_allow_all_storage_expense_files_insert' and cmd='INSERT')
     or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
       and policyname='school_allow_all_storage_expense_files_update' and cmd='UPDATE')
     or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
       and policyname='school_allow_all_storage_expense_files_delete' and cmd='DELETE') then
    raise exception 'P1_B1C_R_STORAGE_POLICY_DRIFT: %',v_policy_fingerprint;
  end if;

  if exists (
    select 1 from pg_trigger t
    where t.tgrelid='storage.objects'::regclass
      and not t.tgisinternal
      and t.tgname='school_expense_files_write_retired_guard'
  ) or to_regprocedure('public.school_guard_retired_expense_file_writes()') is not null then
    raise exception 'P1_B1C_R_GUARD_ALREADY_PRESENT';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_create_expense_attachment_metadata') <> 1
     or to_regprocedure('public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)') is null then
    raise exception 'P1_B1C_R_METADATA_RPC_OVERLOAD_DRIFT';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid='public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)'::regprocedure
      and pg_get_userbyid(p.proowner)='postgres'
      and p.prosecdef
      and p.proconfig='{"search_path=pg_catalog, public"}'::text[]
      and md5(pg_get_functiondef(p.oid))='a7459d0479d9208b5ea01804cf5ad086'
      and not exists (
        select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
        where x.grantee=0 and x.privilege_type='EXECUTE'
      )
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')
  ) then
    raise exception 'P1_B1C_R_METADATA_RPC_CONTRACT_DRIFT';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='school_expense_attachments'
      and c.relkind='r' and pg_get_userbyid(c.relowner)='postgres'
      and c.relrowsecurity and not c.relforcerowsecurity
  ) then
    raise exception 'P1_B1C_R_METADATA_RELATION_DRIFT';
  end if;

  if (select count(*) from pg_policies where schemaname='public' and tablename='school_expense_attachments') <> 2
     or not exists (select 1 from pg_policies where schemaname='public' and tablename='school_expense_attachments'
       and policyname='school_allow_all_expense_attachments' and cmd='ALL'
       and roles='{authenticated}'::name[] and qual='false' and with_check='false')
     or not exists (select 1 from pg_policies where schemaname='public' and tablename='school_expense_attachments'
       and policyname='school_expense_attachments_p0_phase2_authenticated_select' and cmd='SELECT'
       and roles='{authenticated}'::name[] and qual='true') then
    raise exception 'P1_B1C_R_METADATA_POLICY_DRIFT';
  end if;

  select array_agg(distinct privilege_type::name order by privilege_type::name)
    into v_metadata_acl
  from information_schema.role_table_grants
  where table_schema='public' and table_name='school_expense_attachments'
    and grantee in ('anon','authenticated','service_role');

  if v_metadata_acl is distinct from array['SELECT'::name]
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r,
         unnest(array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
       where has_table_privilege(r,'public.school_expense_attachments',p)
     )
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r
       where not has_table_privilege(r,'public.school_expense_attachments','MAINTAIN')
     )
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r
       where not has_table_privilege(r,'public.school_expense_attachments','SELECT')
     ) then
    raise exception 'P1_B1C_R_METADATA_ACL_DRIFT: %',v_metadata_acl;
  end if;

  if not exists (
    select 1 from (
      select count(*) metadata_count,
        count(*) filter(where storage_bucket='school-expense-files') target_count,
        md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' order by id::text),'')) fingerprint
      from public.school_expense_attachments a
    ) s where metadata_count=23 and target_count=23
      and fingerprint='a1b50c81c634121e83b65d31309eb062'
  ) then
    raise exception 'P1_B1C_R_METADATA_SNAPSHOT_DRIFT';
  end if;

  if not exists(select 1 from pg_roles where rolname='service_role' and rolbypassrls)
     or not exists(select 1 from pg_roles where rolname='anon' and not rolbypassrls)
     or not exists(select 1 from pg_roles where rolname='authenticated' and not rolbypassrls) then
    raise exception 'P1_B1C_R_ROLE_ATTRIBUTE_DRIFT';
  end if;
end;
$preflight$;

create function public.school_guard_retired_expense_file_writes()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
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
    else false
  end;
begin
  if v_targeted and (
    current_user in ('anon','authenticated','service_role')
    or v_request_role in ('anon','authenticated','service_role')
  ) then
    raise exception using
      errcode='42501',
      message='SCHOOL_EXPENSE_ATTACHMENT_WRITES_RETIRED';
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
comment on function public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text) is
  'Retired P1-B1C-R expense-attachment metadata writer. Owner-only historical definition retained; no client or service-role caller may execute it.';

revoke insert,update,delete,truncate,references,trigger,maintain
  on table public.school_expense_attachments
  from public,anon,authenticated,service_role;

do $postdeploy$
begin
  if (select count(*) from pg_policies where schemaname='storage' and tablename='objects') <> 1
     or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
       and policyname='school_allow_all_storage_expense_files_select' and cmd='SELECT')
     or exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd in ('ALL','INSERT','UPDATE','DELETE')) then
    raise exception 'P1_B1C_R_STORAGE_POLICY_POSTCONDITION_FAILED';
  end if;

  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid='storage.objects'::regclass and not t.tgisinternal
      and t.tgname='school_expense_files_write_retired_guard' and t.tgenabled='O'
  ) then
    raise exception 'P1_B1C_R_STORAGE_GUARD_POSTCONDITION_FAILED';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='school_create_expense_attachment_metadata') <> 1
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r
       where has_function_privilege(r,
         'public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)'::regprocedure,'EXECUTE')
     )
     or exists (
       select 1
       from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
       where p.oid='public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)'::regprocedure
         and x.grantee=0 and x.privilege_type='EXECUTE'
     ) then
    raise exception 'P1_B1C_R_METADATA_RPC_POSTCONDITION_FAILED';
  end if;

  if (select count(*) from pg_policies where schemaname='public' and tablename='school_expense_attachments') <> 1
     or not exists (select 1 from pg_policies where schemaname='public' and tablename='school_expense_attachments'
       and policyname='school_expense_attachments_p0_phase2_authenticated_select' and cmd='SELECT')
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r,
         unnest(array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
       where has_table_privilege(r,'public.school_expense_attachments',p)
     )
     or exists (
       select 1
       from pg_class c
       cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
       where c.oid='public.school_expense_attachments'::regclass and x.grantee=0
         and x.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
     )
     or exists (
       select 1 from unnest(array['anon','authenticated','service_role']) r
       where not has_table_privilege(r,'public.school_expense_attachments','SELECT')
     ) then
    raise exception 'P1_B1C_R_METADATA_TABLE_POSTCONDITION_FAILED';
  end if;

  if not exists (
    select 1 from (
      select count(*) object_count,count(distinct name) distinct_path_count,
        coalesce(sum((metadata->>'size')::bigint),0) total_bytes,
        md5(coalesce(string_agg(md5(concat_ws('|',id::text,bucket_id,name,
          coalesce(owner::text,''),coalesce(owner_id::text,''),coalesce(metadata::text,''),
          coalesce(created_at::text,''),coalesce(updated_at::text,''),coalesce(last_accessed_at::text,''))),
          '' order by id::text),'')) fingerprint
      from storage.objects where bucket_id='school-expense-files'
    ) s where object_count=57 and distinct_path_count=57 and total_bytes=6936405
      and fingerprint='ec6522f59532814af6bbfbb1a90e1822'
  ) or not exists (
    select 1 from (
      select count(*) metadata_count,
        md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' order by id::text),'')) fingerprint
      from public.school_expense_attachments a
    ) s where metadata_count=23 and fingerprint='a1b50c81c634121e83b65d31309eb062'
  ) then
    raise exception 'P1_B1C_R_HISTORICAL_DATA_CHANGED';
  end if;
end;
$postdeploy$;

commit;
