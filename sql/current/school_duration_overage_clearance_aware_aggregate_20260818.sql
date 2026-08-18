-- School V2: make the unlocked duration-overage aggregate clearance-aware.
-- The locked settlement snapshot branch and the function signature stay unchanged.
\set ON_ERROR_STOP on

\if :{?SCHOOL_CLEARANCE_OVERAGE_AGGREGATE_REHEARSAL}
\else
begin;
\endif

do $preflight$
declare
  v_signature constant regprocedure :=
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;
begin
  perform 'public.school_lesson_records'::regclass;
  perform 'public.school_student_monthly_settlements'::regclass;
  perform 'public.school_lesson_clearances'::regclass;
  perform 'public.school_lesson_clearance_details'::regclass;
  perform 'public.school_get_lesson_clearance_overtime_remaining_minutes(uuid)'::regprocedure;

  if pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid)) <> 'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.provolatile from pg_proc p where p.oid=v_signature::oid) <> 's'
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or not has_function_privilege('service_role',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('authenticated',v_signature,'EXECUTE') then
    raise exception 'CLEARANCE_OVERAGE_AGGREGATE_SECURITY_BASELINE_DRIFT';
  end if;
end
$preflight$;

\if :{?SCHOOL_CLEARANCE_OVERAGE_SKIP_PRODUCTION_MD5}
\else
do $definition_preflight$
declare
  v_signature constant regprocedure :=
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_signature::oid)) <> 'd24b82f51053b3960ce0e4839613ddc7' then
    raise exception 'CLEARANCE_OVERAGE_AGGREGATE_DEFINITION_BASELINE_DRIFT';
  end if;
end
$definition_preflight$;
\endif

create or replace function public.school_get_student_duration_overage_aggregate(
  p_student_id uuid,
  p_year_month text
)
returns table (
  duration_overage_minutes integer,
  duration_overage_fee_jpy numeric,
  duration_overage_fee_cny numeric,
  duration_overage_actual_count integer,
  aggregation_basis text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with input_month as (
    select p_year_month as year_month
    where p_student_id is not null
      and p_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  locked_snapshot as (
    select
      m.duration_overage_minutes,
      m.duration_overage_fee_jpy,
      m.duration_overage_fee_cny,
      m.duration_overage_actual_count,
      m.duration_overage_policy_version,
      m.duration_overage_source
    from public.school_student_monthly_settlements m
    join input_month im on im.year_month = m.year_month
    where m.student_id = p_student_id
      and m.settlement_status = 'locked'
    order by m.locked_at desc nulls last,
      m.updated_at desc nulls last,
      m.created_at desc nulls last
    limit 1
  ),
  eligible_live_sources as (
    select
      l.id,
      l.student_duration_overage_minutes as raw_overage_minutes,
      l.student_duration_overage_fee_jpy as raw_overage_fee_jpy
    from public.school_lesson_records l
    join input_month im on im.year_month = l.student_settlement_month
    where l.app_type = 'school'
      and l.student_id = p_student_id
      and l.lesson_type = 'actual'
      and l.status = 'completed'
      and l.is_billable is true
      and l.business_entity_id = public.school_primary_business_entity_id()
      and l.student_duration_overage_policy_version =
        'student_duration_overage_v1'
      and l.student_duration_overage_source = 'ordinary_actual_rpc'
      and l.student_duration_overage_minutes > 0
      and l.student_duration_overage_fee_jpy > 0
  ),
  clearance_aware_sources as (
    select
      source.id,
      source.raw_overage_minutes,
      source.raw_overage_fee_jpy,
      remaining.remaining_minutes
    from eligible_live_sources source
    cross join lateral (
      select public.school_get_lesson_clearance_overtime_remaining_minutes(
        source.id
      ) as remaining_minutes
    ) remaining
    where remaining.remaining_minutes > 0
  ),
  live_aggregate as (
    select
      coalesce(sum(source.remaining_minutes), 0)::integer
        as duration_overage_minutes,
      coalesce(sum(
        case
          when source.remaining_minutes = source.raw_overage_minutes
            then source.raw_overage_fee_jpy
          else round(
            source.raw_overage_fee_jpy * source.remaining_minutes
            / nullif(source.raw_overage_minutes, 0),
            2
          )
        end
      ), 0)::numeric as duration_overage_fee_jpy,
      count(*)::integer as duration_overage_actual_count
    from clearance_aware_sources source
  ),
  exchange_rate as (
    select coalesce(s.preset_exchange_rate, 0)::numeric as rate
    from public.school_students s
    where s.id = p_student_id
      and s.app_type = 'school'
  )
  select
    case when exists (select 1 from locked_snapshot)
      then coalesce((select s.duration_overage_minutes
                     from locked_snapshot s), 0)
      else coalesce((select a.duration_overage_minutes
                     from live_aggregate a), 0)
    end::integer,
    case when exists (select 1 from locked_snapshot)
      then coalesce((select s.duration_overage_fee_jpy
                     from locked_snapshot s), 0)
      else coalesce((select a.duration_overage_fee_jpy
                     from live_aggregate a), 0)
    end::numeric,
    case when exists (select 1 from locked_snapshot)
      then coalesce((select s.duration_overage_fee_cny
                     from locked_snapshot s), 0)
      else round(
        coalesce((select a.duration_overage_fee_jpy
                  from live_aggregate a), 0)
        * coalesce((select e.rate from exchange_rate e), 0),
        2
      )
    end::numeric,
    case when exists (select 1 from locked_snapshot)
      then coalesce((select s.duration_overage_actual_count
                     from locked_snapshot s), 0)
      else coalesce((select a.duration_overage_actual_count
                     from live_aggregate a), 0)
    end::integer,
    case
      when exists (
        select 1 from locked_snapshot s
        where s.duration_overage_policy_version =
              'student_duration_overage_v1'
          and s.duration_overage_source = 'monthly_settlement_lock'
      ) then 'locked_snapshot'
      when exists (select 1 from locked_snapshot)
        then 'legacy_locked_null_snapshot'
      else 'live_s1_b_actual_aggregate'
    end::text;
$function$;

alter function public.school_get_student_duration_overage_aggregate(uuid,text)
  owner to postgres;
revoke all on function public.school_get_student_duration_overage_aggregate(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_student_duration_overage_aggregate(uuid,text)
  to service_role;

comment on function public.school_get_student_duration_overage_aggregate(uuid,text)
is 'S1-C internal aggregate. For an unlocked source month it sums the DB-authoritative remaining frozen S1-B ordinary actual overage after append-only clearance/reversal allocations, prorating partial JPY with the existing source-line two-decimal rule and preserving raw JPY when no allocation remains active. For a locked month it returns the unchanged six-field settlement snapshot; legacy locked NULL snapshots return zero.';

do $postflight$
declare
  v_signature constant regprocedure :=
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;
  v_definition text := pg_get_functiondef(v_signature::oid);
begin
  if md5(v_definition) <> '6ca9679d62304830e0161ae6da22a69a'
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid)) <> 'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.provolatile from pg_proc p where p.oid=v_signature::oid) <> 's'
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or not has_function_privilege('service_role',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('authenticated',v_signature,'EXECUTE')
     or position('school_get_lesson_clearance_overtime_remaining_minutes' in v_definition)=0
     or position('when source.remaining_minutes = source.raw_overage_minutes' in v_definition)=0
     or position('from locked_snapshot s' in v_definition)=0 then
    raise exception 'CLEARANCE_OVERAGE_AGGREGATE_POSTFLIGHT_FAILED';
  end if;
end
$postflight$;

\if :{?SCHOOL_CLEARANCE_OVERAGE_AGGREGATE_REHEARSAL}
\else
commit;
\endif
