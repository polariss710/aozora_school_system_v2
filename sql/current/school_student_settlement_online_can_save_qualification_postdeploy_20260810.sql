\set ON_ERROR_STOP on

begin transaction read only;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

select
  p.oid::regprocedure signature,
  r.rolname owner,
  p.prosecdef,
  p.proconfig,
  has_function_privilege('public', p.oid, 'EXECUTE') public_exec,
  has_function_privilege('anon', p.oid, 'EXECUTE') anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') authenticated_exec,
  has_function_privilege('service_role', p.oid, 'EXECUTE') service_role_exec
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_roles r on r.oid = p.proowner
where n.nspname = 'public'
  and p.proname in (
    'school_get_student_settlement_online_save_eligibility_core',
    'school_assert_student_monthly_settlement_online_writable',
    'school_get_student_monthly_settlement_online_status_core',
    'school_get_student_monthly_settlement_online_status',
    'school_save_student_monthly_settlement_draft_online_admin',
    'school_lock_student_monthly_settlement_online_admin'
  )
order by p.proname, pg_get_function_identity_arguments(p.oid);

with targets(student_id, year_month) as (
  values
    ('b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2026-06'),
    ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '2026-06')
)
select
  s.name,
  t.student_id,
  t.year_month,
  status->'effective_state'->>'effective_status' effective_status,
  (status->>'source_facts_available')::boolean source_facts_available,
  (status->>'can_save')::boolean can_save,
  status->>'save_blocker_code' save_blocker_code,
  (status->>'can_lock')::boolean can_lock,
  status->>'lock_blocker_code' lock_blocker_code
from targets t
join public.school_students s on s.id = t.student_id
cross join lateral public.school_get_student_monthly_settlement_online_status_core(
  t.student_id, t.year_month
) status
order by s.name;

select feature_key, state
from public.school_feature_gates
where feature_key like 'student_tuition_%'
order by feature_key;

commit;

select 'SETTLEMENT_ONLINE_CAN_SAVE_R1_POSTDEPLOY_PASS' result;
