-- Exact rollback for School V2 Phase 2I-A P002 package isolation.
-- Default leaves transaction open. Use only for verified rollback, not normal flow.
\set ON_ERROR_STOP on
\if :{?phase2i_a_rollback_commit}
\else
  \set phase2i_a_rollback_commit 0
\endif
\if :{?phase2i_a_expected_p002_md5}
\else
  \set phase2i_a_expected_p002_md5 686cbf3a566160bf0de0e30abbdaafa5
\endif
\if :{?phase2i_a_expected_raw_md5}
\else
  \set phase2i_a_expected_raw_md5 f5da14743858f89d37f17ba2646ab092
\endif
\if :{?phase2i_a_expected_remaining_md5}
\else
  \set phase2i_a_expected_remaining_md5 2111a62f998abeeb6933b47fc5c512aa
\endif
\if :{?phase2i_a_expected_balance_md5}
\else
  \set phase2i_a_expected_balance_md5 81823a464f235e72a439867a2c4d395a
\endif
\if :{?phase2i_a_expected_open_md5}
\else
  \set phase2i_a_expected_open_md5 3b45f8f09d4d63a952ca5ec42f7214d7
\endif
\if :{?phase2i_a_expected_p0f_md5}
\else
  \set phase2i_a_expected_p0f_md5 4859d04189893b1dfdecc6a3d66df192
\endif
\if :{?phase2i_a_expected_writer_md5}
\else
  \set phase2i_a_expected_writer_md5 3434e8ece09ec210511aec8b8eb1960f
\endif

begin;
select set_config('phase2i.expected_p002_md5', :'phase2i_a_expected_p002_md5', true),
  set_config('phase2i.expected_raw_md5', :'phase2i_a_expected_raw_md5', true),
  set_config('phase2i.expected_remaining_md5', :'phase2i_a_expected_remaining_md5', true),
  set_config('phase2i.expected_balance_md5', :'phase2i_a_expected_balance_md5', true),
  set_config('phase2i.expected_open_md5', :'phase2i_a_expected_open_md5', true),
  set_config('phase2i.expected_p0f_md5', :'phase2i_a_expected_p0f_md5', true),
  set_config('phase2i.expected_writer_md5', :'phase2i_a_expected_writer_md5', true);
select pg_advisory_xact_lock(hashtextextended(
  'school_phase2i_a_p002_package_isolation_20260817',0
));

do $preflight$
begin
  if to_regclass('public.school_student_package_credit_lots') is null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is null
     or to_regprocedure('public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)') is null then
    raise exception 'PHASE2I_A_ROLLBACK_OBJECTS_MISSING';
  end if;
  if (select count(*) from public.school_student_package_credit_lots)<>1
     or not exists(
       select 1 from public.school_student_package_credit_lots lot
       where lot.id='2a000000-0000-4000-8000-202608170002'
         and lot.origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
         and lot.initial_minutes=1200 and lot.consumed_minutes=0
         and lot.remaining_minutes=1200 and lot.status='active'
         and lot.origin_lesson_row_md5=current_setting('phase2i.expected_p002_md5')
     ) then
    raise exception 'PHASE2I_A_ROLLBACK_PACKAGE_FACT_DRIFT';
  end if;
end
$preflight$;

drop trigger school_package_credit_actual_insert_guard
  on public.school_lesson_records;
drop trigger school_package_credit_lots_append_only
  on public.school_student_package_credit_lots;
drop trigger school_package_credit_lots_truncate_guard
  on public.school_student_package_credit_lots;

delete from public.school_student_package_credit_lots
where id='2a000000-0000-4000-8000-202608170002'
  and origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';

drop function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
);
alter function public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) rename to school_create_lesson_credit_makeup_actual;
revoke all on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;

CREATE OR REPLACE FUNCTION public.school_get_lesson_credit_raw_remaining_hours(p_planned_lesson_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select p.duration_hours-coalesce(sum(a.duration_hours) filter (
    where a.lesson_type='actual'
      and a.status in ('completed','makeup_completed')
      and a.voided_at is null
  ),0)
  from public.school_lesson_records p
  left join public.school_lesson_records a on a.planned_lesson_id=p.id
  where p.id=p_planned_lesson_id
    and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$
;

CREATE OR REPLACE FUNCTION public.school_get_lesson_credit_remaining_hours(p_planned_lesson_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select greatest(
    coalesce(p.duration_hours, 0)
    - coalesce(sum(a.duration_hours) filter (
      where a.lesson_type = 'actual'
        and a.status in ('completed', 'makeup_completed')
    ), 0),
    0
  )::numeric
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id = p.id
   and a.app_type = 'school'
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
    and p.lesson_type = 'planned'
  group by p.id, p.duration_hours;
$function$
;

CREATE OR REPLACE FUNCTION public.school_list_open_lesson_credit_sources(p_from_month text, p_to_month text, p_target_month text)
 RETURNS TABLE(id uuid, lesson_date date, year_month text, student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid, start_time text, end_time text, duration_hours numeric, lesson_content text, note text, lesson_count integer, unit_price numeric, lesson_delivery_mode text, lesson_venue text, remaining_hours numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH args AS (
    SELECT nullif(trim(coalesce(p_from_month,'')),'') AS from_month,
      nullif(trim(coalesce(p_to_month,'')),'') AS to_month,
      nullif(trim(coalesce(p_target_month,'')),'') AS target_month
  ), sources AS (
    SELECT p.id,p.lesson_date,
      public.school_resolve_r1d_e_c_lesson_student_month(p.id) AS source_month,
      p.student_id,p.teacher_id,p.subject_id,p.business_entity_id,
      p.start_time,p.end_time,p.duration_hours,p.lesson_content,p.note,
      p.lesson_count,p.unit_price,p.lesson_delivery_mode,p.lesson_venue,
      greatest(coalesce(p.duration_hours,0)-coalesce(sum(a.duration_hours)
        FILTER(WHERE a.lesson_type='actual'
          AND a.status IN ('completed','makeup_completed')
          AND a.voided_at IS NULL),0),0)::numeric
        AS remaining_hours
    FROM public.school_lesson_records p
    CROSS JOIN args x
    LEFT JOIN public.school_lesson_records a
      ON a.planned_lesson_id=p.id AND a.app_type='school'
    WHERE p.app_type='school' AND p.lesson_type='planned'
      AND p.status='pending_makeup' AND p.voided_at IS NULL
      AND x.from_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.to_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      AND x.from_month<=x.to_month AND x.to_month<=x.target_month
      AND public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          BETWEEN x.from_month AND x.to_month
      AND public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          <=x.target_month
    GROUP BY p.id
  )
  SELECT s.id,s.lesson_date,s.source_month AS year_month,s.student_id,
    s.teacher_id,s.subject_id,s.business_entity_id,s.start_time,s.end_time,
    s.duration_hours,s.lesson_content,s.note,s.lesson_count,s.unit_price,
    s.lesson_delivery_mode,s.lesson_venue,s.remaining_hours
  FROM sources s
  WHERE s.remaining_hours>0
    and not exists (
      select 1
      from public.school_student_settlement_lesson_variance_claims c
      where c.claim_status='active'
        and c.source_type='unused_planned_credit_v1'
        and c.source_planned_lesson_id=s.id
    )
  ORDER BY s.source_month,s.lesson_date,s.lesson_count NULLS LAST,
    s.start_time NULLS LAST,s.id;
$function$
;

CREATE OR REPLACE FUNCTION public.school_list_student_lesson_credit_balances(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(student_id uuid, business_entity_id uuid, open_source_count bigint, open_credit_hours numeric, oldest_credit_date date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with credit_sources as (
    select
      p.id,
      p.student_id,
      p.business_entity_id,
      p.lesson_date,
      greatest(
        coalesce(p.duration_hours, 0) - coalesce(sum(a.duration_hours) filter (
          where a.lesson_type = 'actual'
            and a.status in ('completed', 'makeup_completed')
            and a.voided_at is null
        ), 0),
        0
      )::numeric as remaining_hours
    from public.school_lesson_records p
    left join public.school_lesson_records a
      on a.planned_lesson_id = p.id
     and a.app_type = 'school'
    where p.app_type = 'school'
      and p.lesson_type = 'planned'
      and p.status = 'pending_makeup'
      and p.voided_at is null
      and (p_student_id is null or p.student_id = p_student_id)
    group by p.id, p.student_id, p.business_entity_id, p.lesson_date, p.duration_hours
  )
  select
    c.student_id,
    c.business_entity_id,
    count(*) filter (where c.remaining_hours > 0)::bigint as open_source_count,
    coalesce(sum(c.remaining_hours) filter (where c.remaining_hours > 0), 0)::numeric as open_credit_hours,
    min(c.lesson_date) filter (where c.remaining_hours > 0) as oldest_credit_date
  from credit_sources c
  where c.student_id is not null
  group by c.student_id, c.business_entity_id;
$function$
;

CREATE OR REPLACE FUNCTION public.school_tuition_p0f_source_lines(p_student_id uuid, p_business_entity_id uuid, p_year_month text, p_settlement_exchange_rate numeric, p_include_active_claimed boolean DEFAULT false)
 RETURNS TABLE(source_type text, source_planned_lesson_id uuid, source_actual_lesson_id uuid, source_hours numeric, source_amount_jpy numeric, source_amount_cny numeric, line_manifest_sha256 text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  with unused_sources as (
    select
      'unused_planned_credit_v1'::text as source_type,
      p.id as source_planned_lesson_id,
      null::uuid as source_actual_lesson_id,
      -public.school_get_lesson_credit_remaining_hours(p.id)::numeric as source_hours,
      -round(
        coalesce(p.base_lesson_fee_jpy,p.lesson_fee,p.unit_price*p.duration_hours,0)
        * public.school_get_lesson_credit_remaining_hours(p.id)
        / nullif(p.duration_hours,0), 2
      )::numeric as source_amount_jpy
    from public.school_lesson_records p
    where p.app_type='school'
      and p.lesson_type='planned'
      and p.status='pending_makeup'
      and p.voided_at is null
      and p.student_id=p_student_id
      and p.business_entity_id=p_business_entity_id
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)=p_year_month
      and p.duration_hours>0
      and coalesce(p.base_lesson_fee_jpy,p.lesson_fee,p.unit_price*p.duration_hours,0)>=0
      and public.school_get_lesson_credit_remaining_hours(p.id)>0
      and (
        p_include_active_claimed
        or not exists (
          select 1
          from public.school_student_settlement_lesson_variance_claims c
          where c.claim_status='active'
            and c.source_type='unused_planned_credit_v1'
            and c.source_planned_lesson_id=p.id
        )
      )
  ),
  overage_sources as (
    select
      'actual_duration_overage_charge_v1'::text as source_type,
      a.planned_lesson_id as source_planned_lesson_id,
      a.id as source_actual_lesson_id,
      round(a.student_duration_overage_minutes::numeric/60,6)::numeric as source_hours,
      round(a.student_duration_overage_fee_jpy,2)::numeric as source_amount_jpy
    from public.school_lesson_records a
    where a.app_type='school'
      and a.lesson_type='actual'
      and a.status='completed'
      and a.is_billable is true
      and a.voided_at is null
      and a.student_id=p_student_id
      and a.business_entity_id=p_business_entity_id
      and a.student_settlement_month=p_year_month
      and a.student_duration_overage_policy_version='student_duration_overage_v1'
      and a.student_duration_overage_source='ordinary_actual_rpc'
      and a.student_duration_overage_minutes>0
      and a.student_duration_overage_fee_jpy>0
      and (
        p_include_active_claimed
        or not exists (
          select 1
          from public.school_student_settlement_lesson_variance_claims c
          where c.claim_status='active'
            and c.source_type='actual_duration_overage_charge_v1'
            and c.source_actual_lesson_id=a.id
        )
      )
  ),
  lines as (
    select * from unused_sources
    union all
    select * from overage_sources
  ),
  converted as (
    select l.*,
      round(l.source_amount_jpy*p_settlement_exchange_rate,2)::numeric
        as source_amount_cny
    from lines l
  )
  select c.source_type,c.source_planned_lesson_id,c.source_actual_lesson_id,
    c.source_hours,c.source_amount_jpy,c.source_amount_cny,
    encode(extensions.digest(concat_ws('|','lesson_variance_financial_netting_v1',
      c.source_type,coalesce(c.source_planned_lesson_id::text,''),
      coalesce(c.source_actual_lesson_id::text,''),c.source_hours::text,
      c.source_amount_jpy::text,c.source_amount_cny::text,
      to_char(p_settlement_exchange_rate,'FM999999990.000000')),'sha256'),'hex')::text
  from converted c
  order by c.source_type,c.source_planned_lesson_id,c.source_actual_lesson_id;
$function$
;

revoke all on function public.school_get_lesson_credit_raw_remaining_hours(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_credit_remaining_hours(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_lesson_credit_remaining_hours(uuid)
  to anon,authenticated,service_role;
revoke all on function public.school_list_student_lesson_credit_balances(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_student_lesson_credit_balances(uuid)
  to anon,authenticated,service_role;
revoke all on function public.school_list_open_lesson_credit_sources(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_open_lesson_credit_sources(text,text,text)
  to anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_source_lines(
  uuid,uuid,text,numeric,boolean
) from public,anon,authenticated,service_role;

drop function public.school_list_student_package_credit_lots(uuid);
drop function public.school_guard_package_credit_actual_insert();
drop function public.school_prevent_package_credit_lot_mutation();
drop table public.school_student_package_credit_lots;
drop function public.school_is_active_package_credit_origin(uuid);

select check_row.object_name,check_row.actual_md5,check_row.expected_md5,
  check_row.actual_md5=check_row.expected_md5 as matches
from (values
  ('raw',md5(pg_get_functiondef(
    'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure)),
    current_setting('phase2i.expected_raw_md5')),
  ('remaining',md5(pg_get_functiondef(
    'public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure)),
    current_setting('phase2i.expected_remaining_md5')),
  ('balance',md5(pg_get_functiondef(
    'public.school_list_student_lesson_credit_balances(uuid)'::regprocedure)),
    current_setting('phase2i.expected_balance_md5')),
  ('open',md5(pg_get_functiondef(
    'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure)),
    current_setting('phase2i.expected_open_md5')),
  ('p0f',md5(pg_get_functiondef(
    'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure)),
    current_setting('phase2i.expected_p0f_md5')),
  ('writer',md5(pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure)),
    current_setting('phase2i.expected_writer_md5'))
) check_row(object_name,actual_md5,expected_md5)
order by check_row.object_name;

do $verify$
begin
  if md5(pg_get_functiondef(
       'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_raw_md5')
     or md5(pg_get_functiondef(
       'public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_remaining_md5')
     or md5(pg_get_functiondef(
       'public.school_list_student_lesson_credit_balances(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_balance_md5')
     or md5(pg_get_functiondef(
       'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
     ))<>current_setting('phase2i.expected_open_md5')
     or md5(pg_get_functiondef(
       'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
     ))<>current_setting('phase2i.expected_p0f_md5')
     or md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     ))<>current_setting('phase2i.expected_writer_md5') then
    raise exception 'PHASE2I_A_EXACT_ROLLBACK_DEFINITION_MISMATCH';
  end if;
  if md5((select to_jsonb(lesson)::text from public.school_lesson_records lesson
      where lesson.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'))
       <>current_setting('phase2i.expected_p002_md5') then
    raise exception 'PHASE2I_A_EXACT_ROLLBACK_P002_MUTATED';
  end if;
end
$verify$;

\if :phase2i_a_rollback_commit
  commit;
\endif
