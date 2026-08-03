-- P0-G1-A exact initial admin and unchanged business boundary verification.
\set ON_ERROR_STOP on
\pset pager off

select user_id,role,is_active,
  created_by_user_id,updated_by_user_id,
  created_at=updated_at as timestamps_initialized_together,
  note
from public.school_app_memberships
where user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid;

do $verify$
begin
  if (select count(*) from public.school_app_memberships)<>1
     or not exists (
       select 1 from public.school_app_memberships m
       where m.user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
         and m.role='admin' and m.is_active
         and m.created_by_user_id=m.user_id
         and m.updated_by_user_id=m.user_id
         and m.note='Business-owner-authorized P0-G1-A initial admin bootstrap on 2026-08-04.'
     ) then
    raise exception 'P0G1_INITIAL_ADMIN_BOOTSTRAP_INVALID';
  end if;
  if exists (
    select 1 from auth.users
    where id=any(array[
      'a0100000-0000-4000-8000-000000000001','a0100000-0000-4000-8000-000000000002',
      'a0100000-0000-4000-8000-000000000003','a0100000-0000-4000-8000-000000000004',
      'a0100000-0000-4000-8000-000000000005'
    ]::uuid[])
  ) then
    raise exception 'P0G1_ROLLBACK_AUTH_FIXTURE_RESIDUE';
  end if;
  if (select jsonb_object_agg(feature_key,state) from public.school_feature_gates
      where feature_key like 'student_tuition_%')
       is distinct from '{"student_tuition_preview":"enabled","student_tuition_generate":"blocked","student_tuition_cash_submit":"blocked"}'::jsonb then
    raise exception 'P0G1_TUITION_GATE_DRIFT';
  end if;
end;
$verify$;

begin read only;
set local request.jwt.claims='{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}';
select * from public.school_get_current_app_membership();
select public.school_require_current_app_admin() as confirmed_admin_actor;
rollback;

select feature_key,state
from public.school_feature_gates
where feature_key like 'student_tuition_%'
order by feature_key;

select 'P0G1_INITIAL_ADMIN_POSTDEPLOY_PASS' result;
