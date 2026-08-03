-- School V2 P0-G1-A membership schema.
-- Approved business model: one current membership row per canonical School Auth user.
\set ON_ERROR_STOP on
\pset pager off

begin;

create table public.school_app_memberships (
  user_id uuid primary key
    references auth.users(id) on delete restrict,
  role text not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_id uuid not null
    references auth.users(id) on delete restrict,
  updated_by_user_id uuid not null
    references auth.users(id) on delete restrict,
  note text null,
  constraint school_app_memberships_role_chk
    check (role in ('admin','operator','read_only')),
  constraint school_app_memberships_updated_not_before_created_chk
    check (updated_at >= created_at)
);

create index school_app_memberships_active_role_idx
  on public.school_app_memberships (role,user_id)
  where is_active;

alter table public.school_app_memberships enable row level security;

revoke all on table public.school_app_memberships
  from public,anon,authenticated,service_role;

comment on table public.school_app_memberships is
  'P0-G1-A sole authorization authority keyed only by canonical School auth.users.id; email is never authorization input.';
comment on column public.school_app_memberships.user_id is
  'Canonical School Auth user UUID and sole membership identity.';
comment on column public.school_app_memberships.role is
  'Current role: admin, operator, or read_only. P0-G1 critical finance writers require admin.';
comment on column public.school_app_memberships.is_active is
  'Fail-closed current membership state; new rows default inactive.';
comment on column public.school_app_memberships.created_by_user_id is
  'Confirmed School Auth actor UUID that created the membership.';
comment on column public.school_app_memberships.updated_by_user_id is
  'Confirmed School Auth actor UUID that last changed the membership.';
comment on column public.school_app_memberships.note is
  'Controlled maintenance note; never an authorization input.';

commit;
