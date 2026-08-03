-- P0-G1-A exact initial admin bootstrap authorized by the business owner.
-- Target School Auth UUID was separately matched to the confirmed masked email.
\set ON_ERROR_STOP on
\pset pager off

begin;

do $preflight$
begin
  if not exists (
    select 1 from auth.users u
    where u.id='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
      and u.deleted_at is null
      and not u.is_anonymous
  ) then
    raise exception 'P0G1_CONFIRMED_ADMIN_AUTH_USER_NOT_FOUND';
  end if;
  if exists (select 1 from public.school_app_memberships) then
    raise exception 'P0G1_INITIAL_BOOTSTRAP_REQUIRES_EMPTY_MEMBERSHIP_TABLE';
  end if;
end;
$preflight$;

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
)
values (
  '25331ae9-3412-48b9-bdc3-e516caeaeba4',
  'admin',
  true,
  '25331ae9-3412-48b9-bdc3-e516caeaeba4',
  '25331ae9-3412-48b9-bdc3-e516caeaeba4',
  'Business-owner-authorized P0-G1-A initial admin bootstrap on 2026-08-04.'
);

commit;
