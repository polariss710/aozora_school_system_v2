-- Disposable PostgreSQL 17 contract test. Never run against production.
\set ON_ERROR_STOP on
begin;

do $roles$
begin
  if not exists(select 1 from pg_roles where rolname='postgres') then
    create role postgres superuser nologin;
  end if;
  if not exists(select 1 from pg_roles where rolname='anon') then
    create role anon nologin;
  end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then
    create role service_role nologin;
  end if;
end
$roles$;

create table public.school_students(
  id uuid primary key,
  app_type text not null,
  preset_exchange_rate numeric not null
);
create table public.school_lesson_records(
  id uuid primary key,
  app_type text not null,
  student_id uuid not null,
  lesson_type text not null,
  status text not null,
  is_billable boolean,
  business_entity_id uuid not null,
  student_settlement_month text,
  student_duration_overage_minutes integer,
  student_duration_overage_fee_jpy numeric,
  student_duration_overage_policy_version text,
  student_duration_overage_source text,
  voided_at timestamptz
);
create table public.school_student_monthly_settlements(
  id uuid primary key,
  student_id uuid not null,
  year_month text not null,
  settlement_status text not null,
  duration_overage_minutes integer,
  duration_overage_fee_jpy numeric,
  duration_overage_fee_cny numeric,
  duration_overage_actual_count integer,
  duration_overage_policy_version text,
  duration_overage_source text,
  locked_at timestamptz,
  updated_at timestamptz not null default transaction_timestamp(),
  created_at timestamptz not null default transaction_timestamp()
);
create table public.school_lesson_clearances(
  id uuid primary key,
  clearance_type text not null,
  reverses_clearance_id uuid,
  requires_forward_adjustment boolean not null default false
);
create table public.school_lesson_clearance_details(
  id uuid primary key,
  clearance_id uuid not null,
  overtime_source_actual_id uuid,
  allocated_minutes integer not null
);
create table public.school_student_settlement_lesson_variance_claims(
  id uuid primary key,
  claim_status text not null,
  source_type text not null,
  source_actual_lesson_id uuid
);

create function public.school_primary_business_entity_id()
returns uuid language sql immutable as $function$
  select '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
$function$;

create function public.school_get_lesson_clearance_overtime_allocated_minutes(
  p_overtime_source_actual_id uuid
)
returns integer language sql stable security definer
set search_path=pg_catalog,public as $function$
  select coalesce(sum(
    case when header.clearance_type='reversal'
      then -detail.allocated_minutes else detail.allocated_minutes end
  ),0)::integer
  from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  where detail.overtime_source_actual_id=p_overtime_source_actual_id
$function$;

create function public.school_get_lesson_clearance_overtime_remaining_minutes(
  p_overtime_source_actual_id uuid
)
returns integer language sql stable security definer
set search_path=pg_catalog,public as $function$
  select actual_row.student_duration_overage_minutes
    - public.school_get_lesson_clearance_overtime_allocated_minutes(actual_row.id)
  from public.school_lesson_records actual_row
  where actual_row.id=p_overtime_source_actual_id
    and actual_row.app_type='school'
    and actual_row.lesson_type='actual'
    and actual_row.status='completed'
    and actual_row.is_billable is true
    and actual_row.voided_at is null
    and actual_row.student_duration_overage_policy_version='student_duration_overage_v1'
    and actual_row.student_duration_overage_source='ordinary_actual_rpc'
$function$;

-- Exact predeployment definition.
CREATE OR REPLACE FUNCTION public.school_get_student_duration_overage_aggregate(
  p_student_id uuid,
  p_year_month text
)
RETURNS TABLE (
  duration_overage_minutes integer,
  duration_overage_fee_jpy numeric,
  duration_overage_fee_cny numeric,
  duration_overage_actual_count integer,
  aggregation_basis text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  WITH input_month AS (
    SELECT p_year_month AS year_month
    WHERE p_student_id IS NOT NULL
      AND p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  locked_snapshot AS (
    SELECT
      m.duration_overage_minutes,
      m.duration_overage_fee_jpy,
      m.duration_overage_fee_cny,
      m.duration_overage_actual_count,
      m.duration_overage_policy_version,
      m.duration_overage_source
    FROM public.school_student_monthly_settlements m
    JOIN input_month im ON im.year_month = m.year_month
    WHERE m.student_id = p_student_id
      AND m.settlement_status = 'locked'
    ORDER BY m.locked_at DESC NULLS LAST,
      m.updated_at DESC NULLS LAST,
      m.created_at DESC NULLS LAST
    LIMIT 1
  ),
  live_aggregate AS (
    SELECT
      coalesce(sum(l.student_duration_overage_minutes), 0)::integer
        AS duration_overage_minutes,
      coalesce(sum(l.student_duration_overage_fee_jpy), 0)::numeric
        AS duration_overage_fee_jpy,
      count(*)::integer AS duration_overage_actual_count
    FROM public.school_lesson_records l
    JOIN input_month im ON im.year_month = l.student_settlement_month
    WHERE l.app_type = 'school'
      AND l.student_id = p_student_id
      AND l.lesson_type = 'actual'
      AND l.status = 'completed'
      AND l.is_billable IS TRUE
      AND l.business_entity_id = public.school_primary_business_entity_id()
      AND l.student_duration_overage_policy_version =
        'student_duration_overage_v1'
      AND l.student_duration_overage_source = 'ordinary_actual_rpc'
      AND l.student_duration_overage_minutes > 0
      AND l.student_duration_overage_fee_jpy > 0
  ),
  exchange_rate AS (
    SELECT coalesce(s.preset_exchange_rate, 0)::numeric AS rate
    FROM public.school_students s
    WHERE s.id = p_student_id
      AND s.app_type = 'school'
  )
  SELECT
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_minutes
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_minutes
                     FROM live_aggregate a), 0)
    END::integer,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_fee_jpy
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_fee_jpy
                     FROM live_aggregate a), 0)
    END::numeric,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_fee_cny
                     FROM locked_snapshot s), 0)
      ELSE round(
        coalesce((SELECT a.duration_overage_fee_jpy
                  FROM live_aggregate a), 0)
        * coalesce((SELECT e.rate FROM exchange_rate e), 0),
        2
      )
    END::numeric,
    CASE WHEN EXISTS (SELECT 1 FROM locked_snapshot)
      THEN coalesce((SELECT s.duration_overage_actual_count
                     FROM locked_snapshot s), 0)
      ELSE coalesce((SELECT a.duration_overage_actual_count
                     FROM live_aggregate a), 0)
    END::integer,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM locked_snapshot s
        WHERE s.duration_overage_policy_version =
              'student_duration_overage_v1'
          AND s.duration_overage_source = 'monthly_settlement_lock'
      ) THEN 'locked_snapshot'
      WHEN EXISTS (SELECT 1 FROM locked_snapshot)
        THEN 'legacy_locked_null_snapshot'
      ELSE 'live_s1_b_actual_aggregate'
    END::text;
$function$;

alter function public.school_get_student_duration_overage_aggregate(uuid,text)
  owner to postgres;
revoke all on function public.school_get_student_duration_overage_aggregate(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_student_duration_overage_aggregate(uuid,text)
  to service_role;

insert into public.school_students(id,app_type,preset_exchange_rate)
select id,'school',0.0415 from (values
  ('ca180000-0000-4000-8000-000000000001'::uuid),
  ('ca180000-0000-4000-8000-000000000002'::uuid),
  ('ca180000-0000-4000-8000-000000000003'::uuid),
  ('ca180000-0000-4000-8000-000000000004'::uuid),
  ('ca180000-0000-4000-8000-000000000005'::uuid),
  ('ca180000-0000-4000-8000-000000000006'::uuid),
  ('ca180000-0000-4000-8000-000000000007'::uuid),
  ('ca180000-0000-4000-8000-000000000008'::uuid),
  ('ca180000-0000-4000-8000-000000000009'::uuid)
) student(id);

insert into public.school_lesson_records(
  id,app_type,student_id,lesson_type,status,is_billable,business_entity_id,
  student_settlement_month,student_duration_overage_minutes,
  student_duration_overage_fee_jpy,student_duration_overage_policy_version,
  student_duration_overage_source,voided_at
) values
  ('ca180000-0000-4000-8100-000000000001','school','ca180000-0000-4000-8000-000000000001','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000002','school','ca180000-0000-4000-8000-000000000002','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000003','school','ca180000-0000-4000-8000-000000000003','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',120,18000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000004','school','ca180000-0000-4000-8000-000000000004','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',120,18000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000005','school','ca180000-0000-4000-8000-000000000005','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000006','school','ca180000-0000-4000-8000-000000000006','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000016','school','ca180000-0000-4000-8000-000000000006','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',30,4500,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000007','school','ca180000-0000-4000-8000-000000000007','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000008','school','ca180000-0000-4000-8000-000000000008','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null),
  ('ca180000-0000-4000-8100-000000000009','school','ca180000-0000-4000-8000-000000000009','actual','completed',true,'2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2020-01',60,9000,'student_duration_overage_v1','ordinary_actual_rpc',null);

insert into public.school_lesson_clearances(
  id,clearance_type,reverses_clearance_id,requires_forward_adjustment
) values
  ('ca180000-0000-4000-8200-000000000002','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000003','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000041','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000042','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000005','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000015','reversal','ca180000-0000-4000-8200-000000000005',false),
  ('ca180000-0000-4000-8200-000000000006','overtime_offset',null,false),
  ('ca180000-0000-4000-8200-000000000008','overtime_offset',null,true);

insert into public.school_lesson_clearance_details(
  id,clearance_id,overtime_source_actual_id,allocated_minutes
) values
  ('ca180000-0000-4000-8300-000000000002','ca180000-0000-4000-8200-000000000002','ca180000-0000-4000-8100-000000000002',60),
  ('ca180000-0000-4000-8300-000000000003','ca180000-0000-4000-8200-000000000003','ca180000-0000-4000-8100-000000000003',30),
  ('ca180000-0000-4000-8300-000000000041','ca180000-0000-4000-8200-000000000041','ca180000-0000-4000-8100-000000000004',30),
  ('ca180000-0000-4000-8300-000000000042','ca180000-0000-4000-8200-000000000042','ca180000-0000-4000-8100-000000000004',45),
  ('ca180000-0000-4000-8300-000000000005','ca180000-0000-4000-8200-000000000005','ca180000-0000-4000-8100-000000000005',60),
  ('ca180000-0000-4000-8300-000000000015','ca180000-0000-4000-8200-000000000015','ca180000-0000-4000-8100-000000000005',60),
  ('ca180000-0000-4000-8300-000000000006','ca180000-0000-4000-8200-000000000006','ca180000-0000-4000-8100-000000000006',60),
  ('ca180000-0000-4000-8300-000000000008','ca180000-0000-4000-8200-000000000008','ca180000-0000-4000-8100-000000000008',60);

insert into public.school_student_monthly_settlements(
  id,student_id,year_month,settlement_status,duration_overage_minutes,
  duration_overage_fee_jpy,duration_overage_fee_cny,
  duration_overage_actual_count,duration_overage_policy_version,
  duration_overage_source,locked_at
) values
  ('ca180000-0000-4000-8400-000000000007','ca180000-0000-4000-8000-000000000007','2020-01','locked',15,2125,92.44,1,'student_duration_overage_v1','monthly_settlement_lock',now()),
  ('ca180000-0000-4000-8400-000000000008','ca180000-0000-4000-8000-000000000008','2020-01','locked',15,2125,92.44,1,'student_duration_overage_v1','monthly_settlement_lock',now());

insert into public.school_student_settlement_lesson_variance_claims
  (id,claim_status,source_type,source_actual_lesson_id)
values
  ('ca180000-0000-4000-8500-000000000009','active','actual_duration_overage_charge_v1','ca180000-0000-4000-8100-000000000009');

create temp table old_contract as
select
  md5(pg_get_functiondef(
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
  )) as definition_md5,
  pg_get_function_result(
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
  ) as result_contract;

create temp table baseline_results as
select scope_key,to_jsonb(result_row) as result_json
from (values
  ('no_clearance','ca180000-0000-4000-8000-000000000001'::uuid),
  ('locked_snapshot','ca180000-0000-4000-8000-000000000007'::uuid),
  ('locked_forward','ca180000-0000-4000-8000-000000000008'::uuid),
  ('active_claim','ca180000-0000-4000-8000-000000000009'::uuid)
) scope(scope_key,student_id)
cross join lateral public.school_get_student_duration_overage_aggregate(
  scope.student_id,'2020-01'
) result_row;

\set SCHOOL_CLEARANCE_OVERAGE_AGGREGATE_REHEARSAL 1
\set SCHOOL_CLEARANCE_OVERAGE_SKIP_PRODUCTION_MD5 1
\ir ../current/school_duration_overage_clearance_aware_aggregate_20260818.sql

do $assertions$
declare
  v_row record;
  v_json jsonb;
  v_original_md5 text;
  v_original_contract text;
begin
  select * into strict v_row
  from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000001','2020-01'
  );
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (60,9000::numeric,373.50::numeric,1) then
    raise exception 'NO_CLEARANCE_RESULT_CHANGED: %',to_jsonb(v_row);
  end if;
  select result_json into strict v_json from baseline_results where scope_key='no_clearance';
  if to_jsonb(v_row) is distinct from v_json then
    raise exception 'NO_CLEARANCE_BYTE_CONTRACT_CHANGED';
  end if;

  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000002','2020-01');
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (0,0::numeric,0::numeric,0) then
    raise exception 'FULL_CLEARANCE_NOT_ZERO: %',to_jsonb(v_row);
  end if;

  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000003','2020-01');
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (90,13500::numeric,560.25::numeric,1) then
    raise exception 'PARTIAL_CLEARANCE_WRONG: %',to_jsonb(v_row);
  end if;

  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000004','2020-01');
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (45,6750::numeric,280.13::numeric,1)
     or v_row.duration_overage_fee_jpy>18000 then
    raise exception 'MULTI_PARTIAL_WRONG: %',to_jsonb(v_row);
  end if;

  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000005','2020-01');
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (60,9000::numeric,373.50::numeric,1) then
    raise exception 'REVERSAL_NOT_RESTORED: %',to_jsonb(v_row);
  end if;

  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000006','2020-01');
  if (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
      v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count)
     is distinct from (30,4500::numeric,186.75::numeric,1) then
    raise exception 'MIXED_SOURCE_RESULT_WRONG: %',to_jsonb(v_row);
  end if;

  select result_json into strict v_json from baseline_results where scope_key='locked_snapshot';
  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000007','2020-01');
  if to_jsonb(v_row) is distinct from v_json
     or (v_row.duration_overage_minutes,v_row.duration_overage_fee_jpy,
         v_row.duration_overage_fee_cny,v_row.duration_overage_actual_count,
         v_row.aggregation_basis)
        is distinct from (15,2125::numeric,92.44::numeric,1,'locked_snapshot'::text) then
    raise exception 'LOCKED_SNAPSHOT_CHANGED: %',to_jsonb(v_row);
  end if;

  select result_json into strict v_json from baseline_results where scope_key='locked_forward';
  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000008','2020-01');
  if to_jsonb(v_row) is distinct from v_json then
    raise exception 'LOCKED_FORWARD_REWROTE_SNAPSHOT: %',to_jsonb(v_row);
  end if;

  select result_json into strict v_json from baseline_results where scope_key='active_claim';
  select * into strict v_row from public.school_get_student_duration_overage_aggregate(
    'ca180000-0000-4000-8000-000000000009','2020-01');
  if to_jsonb(v_row) is distinct from v_json then
    raise exception 'ACTIVE_CLAIM_WAS_TREATED_AS_CLEARANCE: %',to_jsonb(v_row);
  end if;

  select definition_md5,result_contract into strict v_original_md5,v_original_contract
  from old_contract;
  if v_original_md5<>'d24b82f51053b3960ce0e4839613ddc7'
     or pg_get_function_result(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
     )<>v_original_contract
     or (select count(*) from public.school_get_student_duration_overage_aggregate(
       'ca180000-0000-4000-8000-000000000001','2020-01'))<>1 then
    raise exception 'FUNCTION_RETURN_CONTRACT_CHANGED';
  end if;

  raise notice 'CLEARANCE_AWARE_OVERAGE_LOCAL_PASS passed_assertions=10 new_md5=%',
    md5(pg_get_functiondef(
      'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
    ));
end
$assertions$;

\ir ../current/school_duration_overage_clearance_aware_aggregate_exact_rollback_20260818.sql

do $rollback_assertions$
declare
  v_old_md5 text;
begin
  select definition_md5 into strict v_old_md5 from old_contract;
  if md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure::oid
     ))<>v_old_md5 then
    raise exception 'LOCAL_EXACT_ROLLBACK_DEFINITION_MISMATCH';
  end if;
  raise notice 'CLEARANCE_AWARE_OVERAGE_LOCAL_EXACT_ROLLBACK_PASS';
end
$rollback_assertions$;

rollback;
