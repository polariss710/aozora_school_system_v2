-- School V2 Li Tianlun + Wu Feng exact correction audit table schema.
-- Status: reviewed schema-only deployment file, 2026-08-06.
-- Business expansion approval: current task sections 2.1 and 7.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='180s';

do $preflight$
begin
  if to_regclass('public.school_lesson_exact_correction_events') is not null then
    raise exception 'LI_WU_CORRECTION_AUDIT_OBJECT_ALREADY_EXISTS';
  end if;
  if to_regclass('public.school_lesson_records') is null then
    raise exception 'LI_WU_CORRECTION_LESSON_TABLE_MISSING';
  end if;
end;
$preflight$;

create table public.school_lesson_exact_correction_events (
  id uuid primary key default gen_random_uuid(),
  correction_batch_id text not null,
  lesson_id uuid not null
    references public.school_lesson_records(id) on delete restrict,
  action text not null,
  reason text not null,
  before_row jsonb not null,
  after_row jsonb not null,
  before_hash text not null,
  after_hash text not null,
  manifest_hash text not null,
  actor_user_id uuid not null,
  created_at timestamptz not null default transaction_timestamp(),
  constraint school_lesson_exact_correction_batch_lesson_uniq
    unique(correction_batch_id,lesson_id),
  constraint school_lesson_exact_correction_action_chk
    check(action='exact_void_correction'),
  constraint school_lesson_exact_correction_reason_chk
    check(length(trim(reason))>0),
  constraint school_lesson_exact_correction_before_hash_chk
    check(before_hash ~ '^[0-9a-f]{32}$'
      and before_hash=md5(before_row::text)),
  constraint school_lesson_exact_correction_after_hash_chk
    check(after_hash ~ '^[0-9a-f]{32}$'
      and after_hash=md5(after_row::text)),
  constraint school_lesson_exact_correction_manifest_hash_chk
    check(manifest_hash='e2bc9f4380f5bf5a95ff0341ae47183b')
);

alter table public.school_lesson_exact_correction_events owner to postgres;
alter table public.school_lesson_exact_correction_events enable row level security;

revoke all privileges on table public.school_lesson_exact_correction_events
  from public,anon,authenticated,service_role;

comment on table public.school_lesson_exact_correction_events is
  'Immutable active-admin exact lesson correction audit. Operational lesson authority remains school_lesson_records.voided_at/void_reason; legacy settlement evidence is unchanged.';
comment on column public.school_lesson_exact_correction_events.before_row is
  'Deterministic full JSONB snapshot immediately before the approved exact correction.';
comment on column public.school_lesson_exact_correction_events.after_row is
  'Deterministic full JSONB snapshot immediately after the approved exact correction.';

do $verify$
begin
  if pg_get_userbyid((select relowner from pg_class where oid=
       'public.school_lesson_exact_correction_events'::regclass))<>'postgres'
     or not (select relrowsecurity from pg_class where oid=
       'public.school_lesson_exact_correction_events'::regclass)
     or exists(
       select 1 from information_schema.role_table_grants
       where table_schema='public'
         and table_name='school_lesson_exact_correction_events'
         and grantee in ('PUBLIC','anon','authenticated','service_role')
         and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
     ) then
    raise exception 'LI_WU_CORRECTION_AUDIT_SCHEMA_VERIFY_FAILED';
  end if;
end;
$verify$;

commit;
select 'LI_WU_CORRECTION_AUDIT_SCHEMA_DEPLOYED' result;
