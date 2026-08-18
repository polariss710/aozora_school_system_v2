-- Exact code rollback for the School V2 clearance-aware overage aggregate.
-- Restores the predeployment definition, owner, SECURITY DEFINER/search_path,
-- comment, and EXECUTE ACL. It never updates business rows.
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
  if md5(pg_get_functiondef(v_signature::oid)) <> '6ca9679d62304830e0161ae6da22a69a'
     or position(
       'school_get_lesson_clearance_overtime_remaining_minutes'
       in pg_get_functiondef(v_signature::oid)
     )=0 then
    raise exception 'CLEARANCE_OVERAGE_AGGREGATE_ROLLBACK_TARGET_MISMATCH';
  end if;
end
$preflight$;

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

comment on function public.school_get_student_duration_overage_aggregate(uuid,text)
is 'S1-C internal aggregate. For an unlocked source month it sums only frozen S1-B ordinary actual overage minutes/JPY and converts once with the source-month student rate. For a locked month it returns the six-field settlement snapshot; legacy locked NULL snapshots return zero and are never inferred from duration, price, fee, date, legacy month, aircon, or add-ons.';

do $postflight$
declare
  v_signature constant regprocedure :=
    'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_signature::oid)) <> 'd24b82f51053b3960ce0e4839613ddc7'
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid)) <> 'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or not has_function_privilege('service_role',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('authenticated',v_signature,'EXECUTE') then
    raise exception 'CLEARANCE_OVERAGE_AGGREGATE_EXACT_ROLLBACK_FAILED';
  end if;
end
$postflight$;

\if :{?SCHOOL_CLEARANCE_OVERAGE_AGGREGATE_REHEARSAL}
\else
commit;
\endif
