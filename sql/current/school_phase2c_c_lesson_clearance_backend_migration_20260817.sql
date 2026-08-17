-- School V2 Phase 2C-C production clearance backend migration.
-- Requires the matching Phase 2C-C schema migration and the deployed Phase 2I-A package lot.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  perform 'public.school_lesson_clearances'::regclass;
  perform 'public.school_lesson_clearance_details'::regclass;
  perform 'public.school_student_package_credit_lots'::regclass;
  perform 'public.school_app_memberships'::regclass;
  perform 'public.school_is_active_package_credit_origin(uuid)'::regprocedure;
  perform 'public.school_list_student_package_credit_lots(uuid)'::regprocedure;
  if to_regprocedure('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)') is not null then
    raise exception 'LESSON_CLEARANCE_RPCS_ALREADY_EXIST';
  end if;
end
$preflight$;

create function public.school_get_lesson_clearance_allocated_minutes(
  p_pending_source_planned_id uuid
)
returns integer
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select coalesce(sum(
    case when header.clearance_type='reversal'
      then -detail.allocated_minutes else detail.allocated_minutes end
  ),0)::integer
  from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  where detail.pending_source_planned_id=p_pending_source_planned_id
$function$;

create function public.school_get_lesson_clearance_overtime_allocated_minutes(
  p_overtime_source_actual_id uuid
)
returns integer
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select coalesce(sum(
    case when header.clearance_type='reversal'
      then -detail.allocated_minutes else detail.allocated_minutes end
  ),0)::integer
  from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  where detail.overtime_source_actual_id=p_overtime_source_actual_id
$function$;

create function public.school_get_lesson_clearance_pending_remaining_minutes(
  p_pending_source_planned_id uuid
)
returns integer
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select case
    when public.school_is_active_package_credit_origin(p.id) then 0
    else (
      round(coalesce(p.duration_hours,0)*60)::integer
      - coalesce(sum(round(coalesce(a.duration_hours,0)*60)::integer) filter (
          where a.lesson_type='actual'
            and a.status in ('completed','makeup_completed')
            and a.voided_at is null
        ),0)::integer
      - public.school_get_lesson_clearance_allocated_minutes(p.id)
    )
  end
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id=p.id and a.app_type='school'
  where p.id=p_pending_source_planned_id
    and p.app_type='school' and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create function public.school_get_lesson_clearance_overtime_remaining_minutes(
  p_overtime_source_actual_id uuid
)
returns integer
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
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

-- Preserve the existing raw function's non-void actual rule while subtracting
-- only the new non-makeup clearance facts. Package origins have no makeup balance.
create or replace function public.school_get_lesson_credit_raw_remaining_hours(
  p_planned_lesson_id uuid
)
returns numeric
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select public.school_get_lesson_clearance_pending_remaining_minutes(
    p_planned_lesson_id
  )::numeric/60
$function$;

-- Preserve the legacy public reader's clamped contract and existing actual set.
create or replace function public.school_get_lesson_credit_remaining_hours(
  p_planned_lesson_id uuid
)
returns numeric
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select case
    when public.school_is_active_package_credit_origin(p.id) then 0
    else greatest(
      round(coalesce(p.duration_hours,0)*60)::integer
      - coalesce(sum(round(coalesce(a.duration_hours,0)*60)::integer) filter (
          where a.lesson_type='actual'
            and a.status in ('completed','makeup_completed')
        ),0)::integer
      - public.school_get_lesson_clearance_allocated_minutes(p.id),
      0
    )::numeric/60
  end
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id=p.id and a.app_type='school'
  where p.id=p_planned_lesson_id
    and p.app_type='school' and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create or replace function public.school_list_student_lesson_credit_balances(
  p_student_id uuid default null
)
returns table(
  student_id uuid,business_entity_id uuid,open_source_count bigint,
  open_credit_hours numeric,oldest_credit_date date
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with credit_sources as (
    select p.id,p.student_id,p.business_entity_id,p.lesson_date,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        as remaining_hours
    from public.school_lesson_records p
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and (p_student_id is null or p.student_id=p_student_id)
      and not public.school_is_active_package_credit_origin(p.id)
      and not exists(
        select 1
        from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='unused_planned_credit_v1'
          and claim.source_planned_lesson_id=p.id
      )
  )
  select source.student_id,source.business_entity_id,
    count(*) filter(where source.remaining_hours>0)::bigint,
    coalesce(sum(source.remaining_hours) filter(where source.remaining_hours>0),0)::numeric,
    min(source.lesson_date) filter(where source.remaining_hours>0)
  from credit_sources source
  where source.student_id is not null
  group by source.student_id,source.business_entity_id
$function$;

create or replace function public.school_list_open_lesson_credit_sources(
  p_from_month text,p_to_month text,p_target_month text
)
returns table(
  id uuid,lesson_date date,year_month text,student_id uuid,teacher_id uuid,
  subject_id uuid,business_entity_id uuid,start_time text,end_time text,
  duration_hours numeric,lesson_content text,note text,lesson_count integer,
  unit_price numeric,lesson_delivery_mode text,lesson_venue text,
  remaining_hours numeric
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with args as (
    select nullif(trim(coalesce(p_from_month,'')),'') from_month,
      nullif(trim(coalesce(p_to_month,'')),'') to_month,
      nullif(trim(coalesce(p_target_month,'')),'') target_month
  ), sources as (
    select p.id,p.lesson_date,
      public.school_resolve_r1d_e_c_lesson_student_month(p.id) source_month,
      p.student_id,p.teacher_id,p.subject_id,p.business_entity_id,
      p.start_time,p.end_time,p.duration_hours,p.lesson_content,p.note,
      p.lesson_count,p.unit_price,p.lesson_delivery_mode,p.lesson_venue,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        remaining_hours
    from public.school_lesson_records p cross join args input
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and input.from_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and input.to_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and input.target_month ~ '^\d{4}-(0[1-9]|1[0-2])$'
      and input.from_month<=input.to_month and input.to_month<=input.target_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        between input.from_month and input.to_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        <=input.target_month
  )
  select source.id,source.lesson_date,source.source_month,
    source.student_id,source.teacher_id,source.subject_id,source.business_entity_id,
    source.start_time,source.end_time,source.duration_hours,source.lesson_content,
    source.note,source.lesson_count,source.unit_price,
    source.lesson_delivery_mode,source.lesson_venue,source.remaining_hours
  from sources source
  where source.remaining_hours>0
    and not public.school_is_active_package_credit_origin(source.id)
    and not exists(
      select 1
      from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active'
        and claim.source_type='unused_planned_credit_v1'
        and claim.source_planned_lesson_id=source.id
    )
  order by source.source_month,source.lesson_date,
    source.lesson_count nulls last,source.start_time nulls last,source.id
$function$;

create function public.school_get_lesson_clearance_source_manifest(
  p_pending_source_planned_id uuid,
  p_overtime_source_actual_id uuid
)
returns text
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select encode(extensions.digest(coalesce(string_agg(concat_ws('|',
    header.id::text,header.clearance_type,header.operation_date::text,
    coalesce(header.financial_year_month,''),header.requires_forward_adjustment::text,
    detail.id::text,detail.balance_effect,detail.allocated_minutes::text,
    detail.pending_unit_price_jpy::text,
    coalesce(detail.overtime_unit_price_jpy::text,''),
    detail.forward_adjustment_direction,detail.forward_adjustment_amount_jpy::text,
    header.input_manifest_sha256
  ),'|' order by header.created_at,header.id,detail.line_no),''),'sha256'),'hex')::text
  from public.school_lesson_clearance_details detail
  join public.school_lesson_clearances header on header.id=detail.clearance_id
  where (p_pending_source_planned_id is not null
      and detail.pending_source_planned_id=p_pending_source_planned_id)
     or (p_overtime_source_actual_id is not null
      and detail.overtime_source_actual_id=p_overtime_source_actual_id)
$function$;

-- Keep the existing source-line shape. Pending lines use the clearance-aware
-- credit reader; overage lines expose only the still-unallocated minutes and
-- preserve the original authoritative per-minute charge.
create or replace function public.school_tuition_p0f_source_lines(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_year_month text,
  p_settlement_exchange_rate numeric,
  p_include_active_claimed boolean default false
)
returns table (
  source_type text,
  source_planned_lesson_id uuid,
  source_actual_lesson_id uuid,
  source_hours numeric,
  source_amount_jpy numeric,
  source_amount_cny numeric,
  line_manifest_sha256 text
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with unused_sources as (
    select
      'unused_planned_credit_v1'::text as source_type,
      planned.id as source_planned_lesson_id,
      null::uuid as source_actual_lesson_id,
      -public.school_get_lesson_credit_remaining_hours(planned.id)::numeric
        as source_hours,
      -round(
        coalesce(planned.base_lesson_fee_jpy,planned.lesson_fee,
          planned.unit_price*planned.duration_hours,0)
        * public.school_get_lesson_credit_remaining_hours(planned.id)
        / nullif(planned.duration_hours,0),2
      )::numeric as source_amount_jpy
    from public.school_lesson_records planned
    where planned.app_type='school'
      and planned.lesson_type='planned'
      and planned.status='pending_makeup'
      and planned.voided_at is null
      and planned.student_id=p_student_id
      and planned.business_entity_id=p_business_entity_id
      and public.school_resolve_r1d_e_c_lesson_student_month(planned.id)=p_year_month
      and planned.duration_hours>0
      and coalesce(planned.base_lesson_fee_jpy,planned.lesson_fee,
        planned.unit_price*planned.duration_hours,0)>=0
      and not public.school_is_active_package_credit_origin(planned.id)
      and public.school_get_lesson_credit_remaining_hours(planned.id)>0
      and (
        p_include_active_claimed
        or not exists (
          select 1
          from public.school_student_settlement_lesson_variance_claims claim
          where claim.claim_status='active'
            and claim.source_type='unused_planned_credit_v1'
            and claim.source_planned_lesson_id=planned.id
        )
      )
  ),
  overage_sources as (
    select
      'actual_duration_overage_charge_v1'::text as source_type,
      actual_row.planned_lesson_id as source_planned_lesson_id,
      actual_row.id as source_actual_lesson_id,
      round(remaining.remaining_minutes::numeric/60,6)::numeric as source_hours,
      round(
        actual_row.student_duration_overage_fee_jpy
        * remaining.remaining_minutes
        / nullif(actual_row.student_duration_overage_minutes,0),2
      )::numeric as source_amount_jpy
    from public.school_lesson_records actual_row
    cross join lateral (
      select public.school_get_lesson_clearance_overtime_remaining_minutes(
        actual_row.id
      ) remaining_minutes
    ) remaining
    where actual_row.app_type='school'
      and actual_row.lesson_type='actual'
      and actual_row.status='completed'
      and actual_row.is_billable is true
      and actual_row.voided_at is null
      and actual_row.student_id=p_student_id
      and actual_row.business_entity_id=p_business_entity_id
      and actual_row.student_settlement_month=p_year_month
      and actual_row.student_duration_overage_policy_version='student_duration_overage_v1'
      and actual_row.student_duration_overage_source='ordinary_actual_rpc'
      and actual_row.student_duration_overage_minutes>0
      and actual_row.student_duration_overage_fee_jpy>0
      and remaining.remaining_minutes>0
      and (
        p_include_active_claimed
        or not exists (
          select 1
          from public.school_student_settlement_lesson_variance_claims claim
          where claim.claim_status='active'
            and claim.source_type='actual_duration_overage_charge_v1'
            and claim.source_actual_lesson_id=actual_row.id
        )
      )
  ),
  lines as (
    select * from unused_sources
    union all
    select * from overage_sources
  ),
  converted as (
    select line.*,
      round(line.source_amount_jpy*p_settlement_exchange_rate,2)::numeric
        as source_amount_cny
    from lines line
  )
  select converted.source_type,converted.source_planned_lesson_id,
    converted.source_actual_lesson_id,converted.source_hours,
    converted.source_amount_jpy,converted.source_amount_cny,
    encode(extensions.digest(concat_ws('|','lesson_variance_financial_netting_v1',
      converted.source_type,coalesce(converted.source_planned_lesson_id::text,''),
      coalesce(converted.source_actual_lesson_id::text,''),
      converted.source_hours::text,converted.source_amount_jpy::text,
      converted.source_amount_cny::text,
      public.school_get_lesson_clearance_source_manifest(
        converted.source_planned_lesson_id,converted.source_actual_lesson_id),
      to_char(p_settlement_exchange_rate,'FM999999990.000000')),
      'sha256'),'hex')::text
  from converted
  order by converted.source_type,converted.source_planned_lesson_id,
    converted.source_actual_lesson_id
$function$;

create function public.school_assert_lesson_clearance_reader()
returns table(actor_user_id uuid,actor_role text)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_AUTH_REQUIRED';
  end if;
  select membership.role,membership.is_active into v_role,v_active
  from public.school_app_memberships membership
  where membership.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator','read_only') then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_READER_ROLE_REQUIRED';
  end if;
  return query select v_actor,v_role;
end
$function$;

create function public.school_suggest_lesson_clearance_targets_core(
  p_overtime_actual_id uuid
)
returns table(
  recommendation_rank bigint,pending_source_planned_id uuid,
  pending_created_at timestamptz,pending_created_at_source text,
  pending_lesson_date date,pending_teacher_id uuid,pending_subject_id uuid,
  pending_remaining_minutes integer,pending_unit_price_jpy numeric,
  overtime_remaining_minutes integer,overtime_unit_price_jpy numeric,
  same_teacher boolean,same_subject boolean,same_unit_price boolean,
  pending_source_locked boolean,requires_forward_adjustment boolean
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with overtime as (
    select actual_row.*,
      public.school_get_lesson_clearance_overtime_remaining_minutes(actual_row.id)
        overtime_remaining,
      round(actual_row.student_duration_overage_fee_jpy*60
        /nullif(actual_row.student_duration_overage_minutes,0),6) overtime_rate
    from public.school_lesson_records actual_row
    where actual_row.id=p_overtime_actual_id
      and actual_row.app_type='school' and actual_row.lesson_type='actual'
      and actual_row.status='completed' and actual_row.is_billable is true
      and actual_row.voided_at is null
  ), candidates as (
    select pending_row.*,
      public.school_get_lesson_clearance_pending_remaining_minutes(pending_row.id)
        pending_remaining,
      coalesce(pending_row.unit_price,
        round(pending_row.lesson_fee/nullif(pending_row.duration_hours,0),6),0)
        pending_rate,
      causal.created_at causal_created_at
    from overtime source
    join public.school_lesson_records pending_row
      on pending_row.student_id=source.student_id
     and pending_row.business_entity_id=source.business_entity_id
    left join lateral (
      select min(actual_row.created_at) created_at
      from public.school_lesson_records actual_row
      where actual_row.planned_lesson_id=pending_row.id
        and actual_row.app_type='school' and actual_row.voided_at is null
        and actual_row.status in ('cancelled','completed')
    ) causal on true
    where pending_row.app_type='school' and pending_row.lesson_type='planned'
      and pending_row.status='pending_makeup' and pending_row.voided_at is null
      and not public.school_is_active_package_credit_origin(pending_row.id)
      and not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='unused_planned_credit_v1'
          and claim.source_planned_lesson_id=pending_row.id
      )
  )
  select row_number() over(order by
      coalesce(candidate.causal_created_at,candidate.updated_at,candidate.created_at),
      candidate.id),
    candidate.id,
    coalesce(candidate.causal_created_at,candidate.updated_at,candidate.created_at),
    case when candidate.causal_created_at is not null then 'causal_actual_created_at'
      when candidate.updated_at is not null then 'planned_updated_at_fallback'
      else 'planned_created_at_fallback' end,
    candidate.lesson_date,candidate.teacher_id,candidate.subject_id,
    candidate.pending_remaining,candidate.pending_rate,
    source.overtime_remaining,source.overtime_rate,
    candidate.teacher_id is not distinct from source.teacher_id,
    candidate.subject_id is not distinct from source.subject_id,
    round(candidate.pending_rate,6)=round(source.overtime_rate,6),
    exists(
      select 1 from public.school_student_monthly_settlements settlement
      where settlement.student_id=candidate.student_id
        and settlement.business_entity_id=candidate.business_entity_id
        and settlement.year_month=public.school_resolve_r1d_e_c_lesson_student_month(candidate.id)
        and settlement.settlement_status='locked'
    ),
    exists(
      select 1 from public.school_student_monthly_settlements settlement
      where settlement.student_id=candidate.student_id
        and settlement.business_entity_id=candidate.business_entity_id
        and settlement.year_month=public.school_resolve_r1d_e_c_lesson_student_month(candidate.id)
        and settlement.settlement_status='locked'
    )
  from candidates candidate cross join overtime source
  where candidate.pending_remaining>0 and source.overtime_remaining>0
  order by 1
$function$;

create function public.school_suggest_lesson_clearance_targets(
  p_overtime_actual_id uuid
)
returns table(
  recommendation_rank bigint,pending_source_planned_id uuid,
  pending_created_at timestamptz,pending_created_at_source text,
  pending_lesson_date date,pending_teacher_id uuid,pending_subject_id uuid,
  pending_remaining_minutes integer,pending_unit_price_jpy numeric,
  overtime_remaining_minutes integer,overtime_unit_price_jpy numeric,
  same_teacher boolean,same_subject boolean,same_unit_price boolean,
  pending_source_locked boolean,requires_forward_adjustment boolean
)
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
begin
  perform * from public.school_assert_lesson_clearance_reader();
  return query select *
  from public.school_suggest_lesson_clearance_targets_core(p_overtime_actual_id);
end
$function$;

create function public.school_assert_lesson_clearance_actor()
returns table(actor_user_id uuid,actor_role text)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_AUTH_REQUIRED';
  end if;
  select membership.role,membership.is_active into v_role,v_active
  from public.school_app_memberships membership
  where membership.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator') then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_ROLE_REQUIRED';
  end if;
  return query select v_actor,v_role;
end
$function$;

create function public.school_list_lesson_clearance_pending_balances(
  p_student_id uuid default null,
  p_include_active_claimed boolean default false
)
returns table(
  pending_source_planned_id uuid,student_id uuid,business_entity_id uuid,
  source_lesson_date date,source_year_month text,teacher_id uuid,subject_id uuid,
  remaining_minutes integer,unit_price_jpy numeric,source_locked boolean,
  active_claimed boolean,recommendation_timestamp timestamptz,
  recommendation_timestamp_source text
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with actor as (
    select * from public.school_assert_lesson_clearance_reader()
  ), candidates as (
    select planned.*,
      public.school_resolve_r1d_e_c_lesson_student_month(planned.id) source_month,
      public.school_get_lesson_clearance_pending_remaining_minutes(planned.id)
        remaining,
      coalesce(planned.unit_price,
        round(planned.lesson_fee/nullif(planned.duration_hours,0),6),0) unit_rate,
      causal.created_at causal_created_at,
      exists(
        select 1 from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='unused_planned_credit_v1'
          and claim.source_planned_lesson_id=planned.id
      ) claimed
    from public.school_lesson_records planned
    left join lateral (
      select min(actual_row.created_at) created_at
      from public.school_lesson_records actual_row
      where actual_row.planned_lesson_id=planned.id
        and actual_row.app_type='school' and actual_row.voided_at is null
        and actual_row.status in ('cancelled','completed')
    ) causal on true
    where planned.app_type='school' and planned.lesson_type='planned'
      and planned.status='pending_makeup' and planned.voided_at is null
      and (p_student_id is null or planned.student_id=p_student_id)
      and not public.school_is_active_package_credit_origin(planned.id)
  )
  select candidate.id,candidate.student_id,candidate.business_entity_id,
    candidate.lesson_date,candidate.source_month,candidate.teacher_id,
    candidate.subject_id,candidate.remaining,candidate.unit_rate,
    exists(
      select 1 from public.school_student_monthly_settlements settlement
      where settlement.student_id=candidate.student_id
        and settlement.business_entity_id=candidate.business_entity_id
        and settlement.year_month=candidate.source_month
        and settlement.settlement_status='locked'
    ),candidate.claimed,
    coalesce(candidate.causal_created_at,candidate.updated_at,candidate.created_at),
    case when candidate.causal_created_at is not null then 'causal_actual_created_at'
      when candidate.updated_at is not null then 'planned_updated_at_fallback'
      else 'planned_created_at_fallback' end
  from candidates candidate cross join actor
  where candidate.remaining>0 and (p_include_active_claimed or not candidate.claimed)
  order by coalesce(candidate.causal_created_at,candidate.updated_at,candidate.created_at),
    candidate.id
$function$;

create function public.school_list_lesson_clearance_available_overages(
  p_student_id uuid default null,
  p_include_active_claimed boolean default false
)
returns table(
  overtime_source_actual_id uuid,student_id uuid,business_entity_id uuid,
  actual_lesson_date date,student_settlement_month text,teacher_wage_month text,
  teacher_id uuid,subject_id uuid,remaining_minutes integer,
  unit_price_jpy numeric,source_locked boolean,active_claimed boolean
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with actor as (
    select * from public.school_assert_lesson_clearance_reader()
  ), candidates as (
    select actual_row.*,
      public.school_get_lesson_clearance_overtime_remaining_minutes(actual_row.id)
        remaining,
      round(actual_row.student_duration_overage_fee_jpy*60
        /nullif(actual_row.student_duration_overage_minutes,0),6) unit_rate,
      exists(
        select 1 from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='actual_duration_overage_charge_v1'
          and claim.source_actual_lesson_id=actual_row.id
      ) claimed
    from public.school_lesson_records actual_row
    where actual_row.app_type='school' and actual_row.lesson_type='actual'
      and actual_row.status='completed' and actual_row.is_billable is true
      and actual_row.voided_at is null
      and actual_row.student_duration_overage_policy_version='student_duration_overage_v1'
      and actual_row.student_duration_overage_source='ordinary_actual_rpc'
      and actual_row.student_duration_overage_minutes>0
      and actual_row.student_duration_overage_fee_jpy>0
      and (p_student_id is null or actual_row.student_id=p_student_id)
  )
  select candidate.id,candidate.student_id,candidate.business_entity_id,
    candidate.lesson_date,candidate.student_settlement_month,
    candidate.teacher_settlement_month,candidate.teacher_id,candidate.subject_id,
    candidate.remaining,candidate.unit_rate,
    exists(
      select 1 from public.school_student_monthly_settlements settlement
      where settlement.student_id=candidate.student_id
        and settlement.business_entity_id=candidate.business_entity_id
        and settlement.year_month=candidate.student_settlement_month
        and settlement.settlement_status='locked'
    ),candidate.claimed
  from candidates candidate cross join actor
  where candidate.remaining>0 and (p_include_active_claimed or not candidate.claimed)
  order by candidate.lesson_date,candidate.id
$function$;

create function public.school_preview_lesson_clearance(
  p_clearance_type text,
  p_pending_source_planned_id uuid,
  p_overtime_source_actual_id uuid,
  p_allocated_minutes integer,
  p_operation_date date,
  p_administrative_financial_treatment text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_reader record;
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
  v_pending_before integer;
  v_overtime_before integer;
  v_pending_rate numeric;
  v_overtime_rate numeric;
  v_pending_month text;
  v_overtime_month text;
  v_forward boolean;
  v_pending_amount numeric;
  v_overtime_amount numeric:=0;
  v_forward_direction text:='none';
  v_forward_amount numeric:=0;
begin
  select * into strict v_reader from public.school_assert_lesson_clearance_reader();
  if p_clearance_type not in (
      'overtime_offset','administrative_writeoff','legacy_consolidated_fulfillment'
    ) then raise exception 'LESSON_CLEARANCE_TYPE_INVALID'; end if;
  if p_allocated_minutes is null or p_allocated_minutes<=0
     or p_allocated_minutes%15<>0 or p_operation_date is null then
    raise exception 'LESSON_CLEARANCE_MINUTES_INVALID';
  end if;
  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=p_pending_source_planned_id
    and lesson.app_type='school' and lesson.lesson_type='planned';
  if v_pending.status<>'pending_makeup' or v_pending.voided_at is not null
     or public.school_is_active_package_credit_origin(v_pending.id) then
    raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_INVALID';
  end if;
  if exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=v_pending.id) then
    raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED';
  end if;
  v_pending_before:=public.school_get_lesson_clearance_pending_remaining_minutes(v_pending.id);
  if v_pending_before<p_allocated_minutes then
    raise exception 'LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT';
  end if;
  v_pending_rate:=coalesce(v_pending.unit_price,
    round(v_pending.lesson_fee/nullif(v_pending.duration_hours,0),6),0);
  v_pending_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_pending.id);
  v_pending_amount:=round(v_pending_rate*p_allocated_minutes/60.0,2);
  if p_clearance_type='overtime_offset' then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=p_overtime_source_actual_id
      and lesson.app_type='school' and lesson.lesson_type='actual';
    if v_overtime.status<>'completed'
       or v_overtime.is_billable is distinct from true
       or v_overtime.voided_at is not null
       or v_overtime.student_duration_overage_policy_version<>'student_duration_overage_v1'
       or v_overtime.student_duration_overage_source<>'ordinary_actual_rpc'
       or v_overtime.student_duration_overage_minutes<=0
       or v_overtime.student_duration_overage_fee_jpy<=0 then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_INVALID';
    end if;
    if v_overtime.student_id<>v_pending.student_id
       or v_overtime.business_entity_id<>v_pending.business_entity_id then
      raise exception 'LESSON_CLEARANCE_SOURCE_SCOPE_MISMATCH';
    end if;
    if exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active'
        and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=v_overtime.id) then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_CLAIMED';
    end if;
    v_overtime_before:=public.school_get_lesson_clearance_overtime_remaining_minutes(v_overtime.id);
    if v_overtime_before<p_allocated_minutes then
      raise exception 'LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT';
    end if;
    v_overtime_rate:=round(v_overtime.student_duration_overage_fee_jpy*60
      /nullif(v_overtime.student_duration_overage_minutes,0),6);
    if round(v_pending_rate,6)<>round(v_overtime_rate,6) then
      raise exception 'LESSON_CLEARANCE_PRICE_POLICY_REQUIRED';
    end if;
    v_overtime_amount:=round(v_overtime_rate*p_allocated_minutes/60.0,2);
    v_overtime_month:=v_overtime.student_settlement_month;
  elsif p_overtime_source_actual_id is not null then
    raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_FORBIDDEN';
  end if;
  if p_clearance_type='administrative_writeoff'
     and p_administrative_financial_treatment not in (
       'no_refund_no_credit','financial_adjustment_required') then
    raise exception 'LESSON_CLEARANCE_ADMIN_FINANCIAL_TREATMENT_REQUIRED';
  end if;
  v_forward:=exists(
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_pending.student_id
      and settlement.business_entity_id=v_pending.business_entity_id
      and settlement.year_month in (v_pending_month,v_overtime_month)
      and settlement.settlement_status='locked'
  ) or coalesce(p_administrative_financial_treatment='financial_adjustment_required',false);
  if v_forward and p_clearance_type in (
      'administrative_writeoff','legacy_consolidated_fulfillment')
     and coalesce(p_administrative_financial_treatment,'financial_adjustment_required')
       ='financial_adjustment_required' then
    v_forward_direction:='increase_student_due';
    v_forward_amount:=v_pending_amount;
  end if;
  return jsonb_build_object(
    'contract_version','lesson_clearance_v2_same_price_v1',
    'clearance_type',p_clearance_type,
    'pending_source_planned_id',v_pending.id,
    'overtime_source_actual_id',case when p_clearance_type='overtime_offset'
      then v_overtime.id else null end,
    'allocated_minutes',p_allocated_minutes,
    'pending_before_minutes',v_pending_before,
    'pending_after_minutes',v_pending_before-p_allocated_minutes,
    'overtime_before_minutes',case when p_clearance_type='overtime_offset'
      then v_overtime_before else null end,
    'overtime_after_minutes',case when p_clearance_type='overtime_offset'
      then v_overtime_before-p_allocated_minutes else null end,
    'pending_unit_price_jpy',v_pending_rate,
    'overtime_unit_price_jpy',case when p_clearance_type='overtime_offset'
      then v_overtime_rate else null end,
    'pending_amount_jpy',-v_pending_amount,
    'overtime_amount_jpy',case when p_clearance_type='overtime_offset'
      then v_overtime_amount else 0 end,
    'financial_net_amount_jpy',case when p_clearance_type='overtime_offset'
      then v_overtime_amount-v_pending_amount else 0 end,
    'requires_forward_adjustment',v_forward,
    'financial_year_month',case when v_forward
      then to_char(p_operation_date,'YYYY-MM') else null end,
    'forward_adjustment_direction',v_forward_direction,
    'forward_adjustment_amount_jpy',v_forward_amount,
    'reader_actor_role',v_reader.actor_role,
    'manifest',jsonb_build_object(
      'pending_source_year_month',v_pending_month,
      'overtime_source_year_month',v_overtime_month,
      'ordinary_makeup_duplicated',false,
      'package_source',false,
      'selection_mode','manual'
    )
  );
end
$function$;

create function public.school_list_lesson_clearance_history(
  p_student_id uuid default null
)
returns table(
  clearance_id uuid,clearance_type text,student_id uuid,business_entity_id uuid,
  operation_date date,operational_year_month text,financial_year_month text,
  requires_forward_adjustment boolean,pending_source_planned_id uuid,
  overtime_source_actual_id uuid,allocated_minutes integer,balance_effect text,
  pending_unit_price_jpy numeric,overtime_unit_price_jpy numeric,
  forward_adjustment_direction text,forward_adjustment_amount_jpy numeric,
  actor_user_id uuid,actor_role text,business_note text,
  reverses_clearance_id uuid,input_manifest_sha256 text,created_at timestamptz
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with actor as (select * from public.school_assert_lesson_clearance_reader())
  select header.id,header.clearance_type,header.student_id,
    header.business_entity_id,header.operation_date,header.operational_year_month,
    header.financial_year_month,header.requires_forward_adjustment,
    detail.pending_source_planned_id,detail.overtime_source_actual_id,
    detail.allocated_minutes,detail.balance_effect,detail.pending_unit_price_jpy,
    detail.overtime_unit_price_jpy,detail.forward_adjustment_direction,
    detail.forward_adjustment_amount_jpy,header.actor_user_id,header.actor_role,
    header.business_note,header.reverses_clearance_id,
    header.input_manifest_sha256,header.created_at
  from public.school_lesson_clearances header
  join public.school_lesson_clearance_details detail
    on detail.clearance_id=header.id and detail.line_no=1
  cross join actor
  where p_student_id is null or header.student_id=p_student_id
  order by header.created_at desc,header.id
$function$;

create function public.school_list_lesson_clearance_forward_manifest(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text
)
returns table(
  clearance_id uuid,clearance_type text,financial_year_month text,
  pending_source_planned_id uuid,overtime_source_actual_id uuid,
  allocated_minutes integer,pending_amount_jpy numeric,
  overtime_amount_jpy numeric,net_amount_jpy numeric,
  forward_adjustment_direction text,forward_adjustment_amount_jpy numeric,
  source_manifest_sha256 text
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with actor as (select * from public.school_assert_lesson_clearance_reader())
  select header.id,header.clearance_type,header.financial_year_month,
    detail.pending_source_planned_id,detail.overtime_source_actual_id,
    detail.allocated_minutes,
    -round(detail.pending_unit_price_jpy*detail.allocated_minutes/60.0,2),
    case when detail.overtime_unit_price_jpy is null then 0::numeric
      else round(detail.overtime_unit_price_jpy*detail.allocated_minutes/60.0,2) end,
    case when detail.overtime_unit_price_jpy is null then 0::numeric
      else round((detail.overtime_unit_price_jpy-detail.pending_unit_price_jpy)
        *detail.allocated_minutes/60.0,2) end,
    detail.forward_adjustment_direction,detail.forward_adjustment_amount_jpy,
    encode(extensions.digest(concat_ws('|','lesson_clearance_forward_manifest_v1',
      header.id::text,header.clearance_type,header.financial_year_month,
      detail.pending_source_planned_id::text,
      coalesce(detail.overtime_source_actual_id::text,''),
      detail.allocated_minutes::text,detail.pending_unit_price_jpy::text,
      coalesce(detail.overtime_unit_price_jpy::text,''),
      detail.forward_adjustment_direction,detail.forward_adjustment_amount_jpy::text,
      header.input_manifest_sha256),'sha256'),'hex')::text
  from public.school_lesson_clearances header
  join public.school_lesson_clearance_details detail
    on detail.clearance_id=header.id and detail.line_no=1
  cross join actor
  where header.student_id=p_student_id
    and header.business_entity_id=p_business_entity_id
    and header.requires_forward_adjustment is true
    and header.financial_year_month=p_year_month
  order by header.created_at,header.id
$function$;

create function public.school_list_cross_month_makeup_projection(
  p_student_id uuid default null,p_year_month text default null
)
returns table(
  projection_month text,projection_role text,actual_lesson_id uuid,
  source_planned_lesson_id uuid,student_id uuid,business_entity_id uuid,
  student_settlement_month text,teacher_wage_month text,actual_lesson_date date,
  teacher_id uuid,subject_id uuid,actual_minutes integer
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  with actor as (select * from public.school_assert_lesson_clearance_reader()),
  facts as (
    select actual_row.*,
      public.school_resolve_r1d_e_c_lesson_student_month(planned.id) source_month,
      to_char(actual_row.lesson_date,'YYYY-MM') actual_month
    from public.school_lesson_records actual_row
    join public.school_lesson_records planned
      on planned.id=actual_row.planned_lesson_id
    where actual_row.app_type='school' and actual_row.lesson_type='actual'
      and actual_row.status='makeup_completed' and actual_row.voided_at is null
      and planned.app_type='school' and planned.lesson_type='planned'
      and (p_student_id is null or actual_row.student_id=p_student_id)
  ), projection as (
    select fact.source_month projection_month,'source_month_reference'::text role,
      fact.* from facts fact
    union all
    select fact.actual_month,'actual_month_fact'::text,fact.* from facts fact
    where fact.actual_month<>fact.source_month
  )
  select projection.projection_month,projection.role,projection.id,
    projection.planned_lesson_id,projection.student_id,
    projection.business_entity_id,projection.student_settlement_month,
    projection.teacher_settlement_month,projection.lesson_date,projection.teacher_id,
    projection.subject_id,projection.actual_minutes
  from projection cross join actor
  where p_year_month is null or projection.projection_month=p_year_month
  order by projection.projection_month,projection.lesson_date,projection.id,
    projection.role
$function$;

create function public.school_create_lesson_clearance_core(
  p_clearance_type text,
  p_pending_source_planned_id uuid,
  p_overtime_source_actual_id uuid,
  p_allocated_minutes integer,
  p_operation_date date,
  p_deviation_reason_code text,
  p_deviation_note text,
  p_business_note text,
  p_administrative_financial_treatment text,
  p_idempotency_key text,
  p_actor_user_id uuid,
  p_actor_role text
)
returns table(
  clearance_id uuid,pending_remaining_minutes integer,
  overtime_remaining_minutes integer,requires_forward_adjustment boolean,
  recommended_pending_source_id uuid,deviated_from_recommendation boolean,
  idempotent_replay boolean
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
  v_student public.school_students%rowtype;
  v_pending_before integer;
  v_overtime_before integer;
  v_pending_rate numeric;
  v_overtime_rate numeric;
  v_pending_month text;
  v_overtime_month text;
  v_operation_month text;
  v_recommended uuid;
  v_deviated boolean;
  v_forward boolean:=false;
  v_forward_direction text:='none';
  v_forward_amount numeric:=0;
  v_forward_amount_source text:='same_unit_price_zero_residual_v1';
  v_manifest text;
  v_existing public.school_lesson_clearances%rowtype;
  v_clearance public.school_lesson_clearances%rowtype;
  v_lock_month text;
  v_lock_id uuid;
begin
  if p_clearance_type not in (
      'overtime_offset','administrative_writeoff','legacy_consolidated_fulfillment'
    ) then
    raise exception 'LESSON_CLEARANCE_TYPE_INVALID';
  end if;
  if p_actor_role not in ('admin','operator','owner') then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_ROLE_REQUIRED';
  end if;
  if p_clearance_type='legacy_consolidated_fulfillment'
     and p_actor_role not in ('admin','owner') then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_LEGACY_ADMIN_REQUIRED';
  end if;
  if p_clearance_type='administrative_writeoff' and p_actor_role<>'admin' then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_ADMIN_REQUIRED';
  end if;
  if p_allocated_minutes is null or p_allocated_minutes<=0
     or p_allocated_minutes%15<>0 then
    raise exception 'LESSON_CLEARANCE_MINUTES_INVALID';
  end if;
  if p_operation_date is null or nullif(btrim(coalesce(p_business_note,'')),'') is null
     or nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then
    raise exception 'LESSON_CLEARANCE_REQUIRED_INPUT_MISSING';
  end if;
  if p_clearance_type='overtime_offset' and p_overtime_source_actual_id is null then
    raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_REQUIRED';
  elsif p_clearance_type<>'overtime_offset' and p_overtime_source_actual_id is not null then
    raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_FORBIDDEN';
  end if;
  if p_clearance_type='administrative_writeoff'
     and p_administrative_financial_treatment not in (
       'no_refund_no_credit','financial_adjustment_required'
     ) then
    raise exception 'LESSON_CLEARANCE_ADMIN_FINANCIAL_TREATMENT_REQUIRED';
  elsif p_clearance_type<>'administrative_writeoff'
        and p_administrative_financial_treatment is not null then
    raise exception 'LESSON_CLEARANCE_ADMIN_FINANCIAL_TREATMENT_FORBIDDEN';
  end if;

  select * into v_pending
  from public.school_lesson_records lesson
  where lesson.id=p_pending_source_planned_id
    and lesson.app_type='school' and lesson.lesson_type='planned';
  if not found or v_pending.status<>'pending_makeup' or v_pending.voided_at is not null then
    raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_INVALID';
  end if;
  if public.school_is_active_package_credit_origin(v_pending.id) then
    raise exception 'LESSON_CLEARANCE_PACKAGE_SOURCE_FORBIDDEN';
  end if;
  select * into v_student from public.school_students student
  where student.id=v_pending.student_id;
  if not found or v_student.status<>'active' then
    if p_clearance_type<>'administrative_writeoff' then
      raise exception 'LESSON_CLEARANCE_STUDENT_NOT_ACTIVE';
    end if;
  end if;

  v_pending_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_pending.id);

  if p_clearance_type='overtime_offset' then
    select * into v_overtime
    from public.school_lesson_records lesson
    where lesson.id=p_overtime_source_actual_id
      and lesson.app_type='school' and lesson.lesson_type='actual';
    if not found or v_overtime.status<>'completed'
       or v_overtime.is_billable is distinct from true or v_overtime.voided_at is not null
       or v_overtime.student_duration_overage_policy_version<>'student_duration_overage_v1'
       or v_overtime.student_duration_overage_source<>'ordinary_actual_rpc'
       or v_overtime.student_duration_overage_minutes<=0
       or v_overtime.student_duration_overage_fee_jpy<=0 then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_INVALID';
    end if;
    if v_overtime.student_id<>v_pending.student_id then
      raise exception 'LESSON_CLEARANCE_STUDENT_MISMATCH';
    end if;
    if v_overtime.business_entity_id<>v_pending.business_entity_id then
      raise exception 'LESSON_CLEARANCE_BUSINESS_ENTITY_MISMATCH';
    end if;
    v_overtime_month:=v_overtime.student_settlement_month;
  end if;

  -- Every competing writer takes settlement scopes first, then source rows, in
  -- deterministic order. This prevents opposite-source allocation deadlocks.
  for v_lock_month in
    select distinct lock_target.year_month
    from (values (v_pending_month),(v_overtime_month)) lock_target(year_month)
    where lock_target.year_month is not null
    order by lock_target.year_month
  loop
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_pending.student_id,v_pending.business_entity_id,v_lock_month
    );
  end loop;
  for v_lock_id in
    select distinct lock_target.lesson_id
    from (values (v_pending.id),(v_overtime.id)) lock_target(lesson_id)
    where lock_target.lesson_id is not null
    order by lock_target.lesson_id
  loop
    perform lesson.id from public.school_lesson_records lesson
    where lesson.id=v_lock_id for update;
  end loop;

  -- Re-read every authoritative source after acquiring all locks.
  select * into v_pending from public.school_lesson_records lesson
  where lesson.id=p_pending_source_planned_id
    and lesson.app_type='school' and lesson.lesson_type='planned';
  if not found or v_pending.status<>'pending_makeup' or v_pending.voided_at is not null
     or public.school_is_active_package_credit_origin(v_pending.id) then
    raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_INVALID';
  end if;
  if exists(
    select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=v_pending.id
  ) then
    raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED';
  end if;

  if p_clearance_type='overtime_offset' then
    select * into v_overtime from public.school_lesson_records lesson
    where lesson.id=p_overtime_source_actual_id
      and lesson.app_type='school' and lesson.lesson_type='actual';
    if not found or v_overtime.status<>'completed'
       or v_overtime.is_billable is distinct from true or v_overtime.voided_at is not null
       or v_overtime.student_duration_overage_policy_version<>'student_duration_overage_v1'
       or v_overtime.student_duration_overage_source<>'ordinary_actual_rpc'
       or v_overtime.student_duration_overage_minutes<=0
       or v_overtime.student_duration_overage_fee_jpy<=0
       or v_overtime.student_id<>v_pending.student_id
       or v_overtime.business_entity_id<>v_pending.business_entity_id then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_INVALID';
    end if;
    if exists(
      select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active'
        and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=v_overtime.id
    ) then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_CLAIMED';
    end if;
  end if;

  v_manifest:=encode(extensions.digest(concat_ws('|',
    'lesson_clearance_v2_same_price_v1',p_clearance_type,
    p_pending_source_planned_id::text,coalesce(p_overtime_source_actual_id::text,''),
    p_allocated_minutes::text,p_operation_date::text,
    coalesce(p_deviation_reason_code,''),coalesce(p_deviation_note,''),
    p_business_note,coalesce(p_administrative_financial_treatment,''),
    p_idempotency_key,p_actor_user_id::text,p_actor_role
  ),'sha256'),'hex');
  select * into v_existing
  from public.school_lesson_clearances header
  where header.student_id=v_pending.student_id
    and header.business_entity_id=v_pending.business_entity_id
    and header.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.input_manifest_sha256<>v_manifest then
      raise exception 'LESSON_CLEARANCE_IDEMPOTENCY_CONFLICT';
    end if;
    return query select v_existing.id,
      public.school_get_lesson_clearance_pending_remaining_minutes(v_pending.id),
      case when p_overtime_source_actual_id is null then null::integer
        else public.school_get_lesson_clearance_overtime_remaining_minutes(
          p_overtime_source_actual_id) end,
      v_existing.requires_forward_adjustment,
      v_existing.recommended_pending_source_id,
      v_existing.deviated_from_recommendation,true;
    return;
  end if;

  v_pending_before:=public.school_get_lesson_clearance_pending_remaining_minutes(v_pending.id);
  if v_pending_before<p_allocated_minutes then
    raise exception 'LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT';
  end if;
  v_pending_rate:=coalesce(v_pending.unit_price,
    round(v_pending.lesson_fee/nullif(v_pending.duration_hours,0),6),0);

  if p_clearance_type='overtime_offset' then
    v_overtime_before:=public.school_get_lesson_clearance_overtime_remaining_minutes(v_overtime.id);
    if v_overtime_before<p_allocated_minutes then
      raise exception 'LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT';
    end if;
    v_overtime_rate:=round(v_overtime.student_duration_overage_fee_jpy*60
      /nullif(v_overtime.student_duration_overage_minutes,0),6);
    if round(v_pending_rate,6)<>round(v_overtime_rate,6) then
      raise exception 'LESSON_CLEARANCE_PRICE_POLICY_REQUIRED';
    end if;
    select suggestion.pending_source_planned_id into v_recommended
    from public.school_suggest_lesson_clearance_targets_core(v_overtime.id) suggestion
    order by suggestion.recommendation_rank limit 1;
  end if;
  v_deviated:=v_recommended is not null and v_recommended<>v_pending.id;
  if v_deviated and nullif(btrim(coalesce(p_deviation_reason_code,'')),'') is null then
    raise exception 'LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED';
  end if;
  if not v_deviated and (p_deviation_reason_code is not null or p_deviation_note is not null) then
    raise exception 'LESSON_CLEARANCE_FIFO_DEVIATION_REASON_FORBIDDEN';
  end if;

  v_forward:=exists(
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_pending.student_id
      and settlement.business_entity_id=v_pending.business_entity_id
      and settlement.year_month in (v_pending_month,v_overtime_month)
      and settlement.settlement_status='locked'
  ) or coalesce(
    p_administrative_financial_treatment='financial_adjustment_required',false
  );
  if v_forward and p_actor_role='operator' then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED';
  end if;
  if v_forward
     and p_clearance_type in ('administrative_writeoff','legacy_consolidated_fulfillment')
     and coalesce(p_administrative_financial_treatment,'financial_adjustment_required')
         ='financial_adjustment_required' then
    v_forward_direction:='increase_student_due';
    v_forward_amount:=round(v_pending_rate*p_allocated_minutes/60.0,2);
    v_forward_amount_source:='pending_unit_price_minutes_v1';
  end if;
  v_operation_month:=to_char(p_operation_date,'YYYY-MM');

  insert into public.school_lesson_clearances(
    student_id,business_entity_id,clearance_type,operation_date,
    operational_year_month,financial_year_month,requires_forward_adjustment,
    selection_mode,recommended_pending_source_id,deviated_from_recommendation,
    deviation_reason_code,deviation_note,business_note,
    administrative_financial_treatment,actor_user_id,actor_role,idempotency_key,
    rule_version,input_manifest_sha256
  ) values (
    v_pending.student_id,v_pending.business_entity_id,p_clearance_type,p_operation_date,
    v_operation_month,case when v_forward then v_operation_month else null end,v_forward,
    'manual',v_recommended,v_deviated,
    case when v_deviated then btrim(p_deviation_reason_code) else null end,
    case when v_deviated then nullif(btrim(coalesce(p_deviation_note,'')),'') else null end,
    btrim(p_business_note),p_administrative_financial_treatment,
    p_actor_user_id,p_actor_role,btrim(p_idempotency_key),
    'lesson_clearance_v2_same_price_v1',v_manifest
  ) returning * into v_clearance;

  insert into public.school_lesson_clearance_details(
    clearance_id,line_no,pending_source_planned_id,overtime_source_actual_id,
    allocated_minutes,balance_effect,pending_unit_price_jpy,overtime_unit_price_jpy,
    pending_source_year_month,overtime_source_year_month,
    pending_before_minutes,pending_after_minutes,
    overtime_before_minutes,overtime_after_minutes,
    forward_adjustment_direction,forward_adjustment_amount_jpy,
    forward_adjustment_amount_source,pending_source_updated_at,pending_source_row_md5,
    overtime_source_updated_at,overtime_source_row_md5
  ) values (
    v_clearance.id,1,v_pending.id,
    case when p_clearance_type='overtime_offset' then v_overtime.id else null end,
    p_allocated_minutes,'consume',v_pending_rate,
    case when p_clearance_type='overtime_offset' then v_overtime_rate else null end,
    v_pending_month,case when p_clearance_type='overtime_offset' then v_overtime_month else null end,
    v_pending_before,v_pending_before-p_allocated_minutes,
    case when p_clearance_type='overtime_offset' then v_overtime_before else null end,
    case when p_clearance_type='overtime_offset' then v_overtime_before-p_allocated_minutes else null end,
    v_forward_direction,v_forward_amount,v_forward_amount_source,
    v_pending.updated_at,md5(to_jsonb(v_pending)::text),
    case when p_clearance_type='overtime_offset' then v_overtime.updated_at else null end,
    case when p_clearance_type='overtime_offset' then md5(to_jsonb(v_overtime)::text) else null end
  );

  return query select v_clearance.id,
    v_pending_before-p_allocated_minutes,
    case when p_clearance_type='overtime_offset'
      then v_overtime_before-p_allocated_minutes else null::integer end,
    v_forward,v_recommended,v_deviated,false;
end
$function$;

create function public.school_create_lesson_clearance(
  p_clearance_type text,
  p_pending_source_planned_id uuid,
  p_overtime_source_actual_id uuid,
  p_allocated_minutes integer,
  p_operation_date date,
  p_deviation_reason_code text,
  p_deviation_note text,
  p_business_note text,
  p_administrative_financial_treatment text,
  p_idempotency_key text
)
returns table(
  clearance_id uuid,pending_remaining_minutes integer,
  overtime_remaining_minutes integer,requires_forward_adjustment boolean,
  recommended_pending_source_id uuid,deviated_from_recommendation boolean,
  idempotent_replay boolean
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare v_actor record;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_actor();
  return query select * from public.school_create_lesson_clearance_core(
    p_clearance_type,p_pending_source_planned_id,p_overtime_source_actual_id,
    p_allocated_minutes,p_operation_date,p_deviation_reason_code,p_deviation_note,
    p_business_note,p_administrative_financial_treatment,p_idempotency_key,
    v_actor.actor_user_id,v_actor.actor_role
  );
end
$function$;

create function public.school_reverse_lesson_clearance_core(
  p_original_clearance_id uuid,p_operation_date date,p_reason text,
  p_idempotency_key text,p_actor_user_id uuid,p_actor_role text
)
returns table(
  reversal_clearance_id uuid,pending_remaining_minutes integer,
  overtime_remaining_minutes integer,idempotent_replay boolean
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_original public.school_lesson_clearances%rowtype;
  v_original_detail public.school_lesson_clearance_details%rowtype;
  v_reversal public.school_lesson_clearances%rowtype;
  v_existing public.school_lesson_clearances%rowtype;
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
  v_pending_before integer;
  v_overtime_before integer;
  v_pending_month text;
  v_overtime_month text;
  v_manifest text;
  v_operation_month text;
  v_forward boolean;
  v_forward_direction text:='none';
  v_forward_amount numeric:=0;
  v_forward_amount_source text:='same_unit_price_zero_residual_v1';
  v_lock_month text;
  v_lock_id uuid;
begin
  if p_actor_role not in ('admin','owner') then
    raise exception using errcode='42501',message='LESSON_CLEARANCE_REVERSAL_ADMIN_REQUIRED';
  end if;
  if p_operation_date is null or nullif(btrim(coalesce(p_reason,'')),'') is null
     or nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then
    raise exception 'LESSON_CLEARANCE_REVERSAL_REQUIRED_INPUT_MISSING';
  end if;
  select * into v_original from public.school_lesson_clearances header
  where header.id=p_original_clearance_id for update;
  if not found or v_original.clearance_type='reversal' then
    raise exception 'LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID';
  end if;
  select * into strict v_original_detail
  from public.school_lesson_clearance_details detail
  where detail.clearance_id=v_original.id and detail.line_no=1;
  select * into v_existing from public.school_lesson_clearances header
  where header.student_id=v_original.student_id
    and header.business_entity_id=v_original.business_entity_id
    and header.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.reverses_clearance_id<>v_original.id then
      raise exception 'LESSON_CLEARANCE_IDEMPOTENCY_CONFLICT';
    end if;
    return query select v_existing.id,
      public.school_get_lesson_clearance_pending_remaining_minutes(
        v_original_detail.pending_source_planned_id),
      case when v_original_detail.overtime_source_actual_id is null then null::integer
        else public.school_get_lesson_clearance_overtime_remaining_minutes(
          v_original_detail.overtime_source_actual_id) end,true;
    return;
  end if;
  if exists(select 1 from public.school_lesson_clearances header
    where header.reverses_clearance_id=v_original.id) then
    raise exception 'LESSON_CLEARANCE_ALREADY_REVERSED';
  end if;
  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=v_original_detail.pending_source_planned_id;
  v_pending_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_pending.id);
  if v_original_detail.overtime_source_actual_id is not null then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=v_original_detail.overtime_source_actual_id;
    v_overtime_month:=v_overtime.student_settlement_month;
  end if;
  v_operation_month:=to_char(p_operation_date,'YYYY-MM');
  for v_lock_month in
    select distinct lock_target.year_month
    from (values
      (v_pending_month),(v_overtime_month),(v_original.financial_year_month),
      (v_operation_month)
    ) lock_target(year_month)
    where lock_target.year_month is not null
    order by lock_target.year_month
  loop
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_original.student_id,v_original.business_entity_id,v_lock_month
    );
  end loop;
  for v_lock_id in
    select distinct lock_target.lesson_id
    from (values
      (v_original_detail.pending_source_planned_id),
      (v_original_detail.overtime_source_actual_id)
    ) lock_target(lesson_id)
    where lock_target.lesson_id is not null
    order by lock_target.lesson_id
  loop
    perform lesson.id from public.school_lesson_records lesson
    where lesson.id=v_lock_id for update;
  end loop;
  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=v_original_detail.pending_source_planned_id;
  if v_original_detail.overtime_source_actual_id is not null then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=v_original_detail.overtime_source_actual_id;
  end if;
  v_pending_before:=public.school_get_lesson_clearance_pending_remaining_minutes(v_pending.id);
  if v_original_detail.overtime_source_actual_id is not null then
    v_overtime_before:=public.school_get_lesson_clearance_overtime_remaining_minutes(v_overtime.id);
  end if;
  v_forward:=v_original.requires_forward_adjustment or exists(
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_original.student_id
      and settlement.business_entity_id=v_original.business_entity_id
      and settlement.year_month=coalesce(
        v_original.financial_year_month,v_original.operational_year_month)
      and settlement.settlement_status='locked'
  );
  if v_forward and v_original_detail.forward_adjustment_direction='increase_student_due' then
    v_forward_direction:='decrease_student_due';
    v_forward_amount:=v_original_detail.forward_adjustment_amount_jpy;
    v_forward_amount_source:='pending_unit_price_minutes_v1';
  elsif v_forward and v_original_detail.forward_adjustment_direction='decrease_student_due' then
    v_forward_direction:='increase_student_due';
    v_forward_amount:=v_original_detail.forward_adjustment_amount_jpy;
    v_forward_amount_source:='pending_unit_price_minutes_v1';
  end if;
  v_manifest:=encode(extensions.digest(concat_ws('|',
    'lesson_clearance_v2_same_price_v1','reversal',v_original.id::text,
    p_operation_date::text,p_reason,p_idempotency_key,
    p_actor_user_id::text,p_actor_role
  ),'sha256'),'hex');
  insert into public.school_lesson_clearances(
    student_id,business_entity_id,clearance_type,operation_date,
    operational_year_month,financial_year_month,requires_forward_adjustment,
    selection_mode,deviated_from_recommendation,business_note,
    actor_user_id,actor_role,idempotency_key,reverses_clearance_id,
    rule_version,input_manifest_sha256
  ) values (
    v_original.student_id,v_original.business_entity_id,'reversal',p_operation_date,
    v_operation_month,case when v_forward then v_operation_month end,
    v_forward,'manual',false,btrim(p_reason),
    p_actor_user_id,p_actor_role,btrim(p_idempotency_key),v_original.id,
    'lesson_clearance_v2_same_price_v1',v_manifest
  ) returning * into v_reversal;
  insert into public.school_lesson_clearance_details(
    clearance_id,line_no,pending_source_planned_id,overtime_source_actual_id,
    allocated_minutes,balance_effect,pending_unit_price_jpy,overtime_unit_price_jpy,
    pending_source_year_month,overtime_source_year_month,
    pending_before_minutes,pending_after_minutes,
    overtime_before_minutes,overtime_after_minutes,
    forward_adjustment_direction,forward_adjustment_amount_jpy,
    forward_adjustment_amount_source,pending_source_updated_at,pending_source_row_md5,
    overtime_source_updated_at,overtime_source_row_md5
  ) values (
    v_reversal.id,1,v_pending.id,v_original_detail.overtime_source_actual_id,
    v_original_detail.allocated_minutes,'restore',
    v_original_detail.pending_unit_price_jpy,v_original_detail.overtime_unit_price_jpy,
    v_original_detail.pending_source_year_month,v_original_detail.overtime_source_year_month,
    v_pending_before,v_pending_before+v_original_detail.allocated_minutes,
    v_overtime_before,
    case when v_original_detail.overtime_source_actual_id is null then null
      else v_overtime_before+v_original_detail.allocated_minutes end,
    v_forward_direction,v_forward_amount,v_forward_amount_source,
    v_pending.updated_at,md5(to_jsonb(v_pending)::text),
    case when v_original_detail.overtime_source_actual_id is null then null else v_overtime.updated_at end,
    case when v_original_detail.overtime_source_actual_id is null then null else md5(to_jsonb(v_overtime)::text) end
  );
  return query select v_reversal.id,
    v_pending_before+v_original_detail.allocated_minutes,
    case when v_original_detail.overtime_source_actual_id is null then null::integer
      else v_overtime_before+v_original_detail.allocated_minutes end,false;
end
$function$;

create function public.school_reverse_lesson_clearance(
  p_original_clearance_id uuid,p_operation_date date,p_reason text,
  p_idempotency_key text
)
returns table(
  reversal_clearance_id uuid,pending_remaining_minutes integer,
  overtime_remaining_minutes integer,idempotent_replay boolean
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare v_actor record;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_actor();
  return query select * from public.school_reverse_lesson_clearance_core(
    p_original_clearance_id,p_operation_date,p_reason,p_idempotency_key,
    v_actor.actor_user_id,v_actor.actor_role
  );
end
$function$;

create function public.school_guard_variance_claim_clearance_mutex()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_source public.school_lesson_records%rowtype;
  v_source_month text;
begin
  if new.claim_status='active' and new.source_type='unused_planned_credit_v1' then
    select * into strict v_source from public.school_lesson_records lesson
    where lesson.id=new.source_planned_lesson_id;
    v_source_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_source.id);
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_source.student_id,v_source.business_entity_id,v_source_month
    );
    perform lesson.id from public.school_lesson_records lesson
    where lesson.id=v_source.id for update;
    if public.school_get_lesson_clearance_allocated_minutes(v_source.id)>0 then
      raise exception 'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_ALLOCATED';
    end if;
  end if;
  if new.claim_status='active' and new.source_type='actual_duration_overage_charge_v1' then
    select * into strict v_source from public.school_lesson_records lesson
    where lesson.id=new.source_actual_lesson_id;
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_source.student_id,v_source.business_entity_id,v_source.student_settlement_month
    );
    perform lesson.id from public.school_lesson_records lesson
    where lesson.id=v_source.id for update;
    if public.school_get_lesson_clearance_overtime_allocated_minutes(v_source.id)>0 then
      raise exception 'LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_ALLOCATED';
    end if;
  end if;
  return new;
end
$function$;

create trigger school_variance_claim_clearance_mutex
before insert or update of claim_status
on public.school_student_settlement_lesson_variance_claims
for each row execute function public.school_guard_variance_claim_clearance_mutex();

create function public.school_validate_lesson_clearance_detail()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_header public.school_lesson_clearances%rowtype;
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
begin
  select * into strict v_header from public.school_lesson_clearances header
  where header.id=new.clearance_id;
  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=new.pending_source_planned_id;
  if v_pending.lesson_type<>'planned'
     or v_pending.student_id<>v_header.student_id
     or v_pending.business_entity_id<>v_header.business_entity_id then
    raise exception 'LESSON_CLEARANCE_DETAIL_PENDING_SCOPE_INVALID';
  end if;
  if v_header.clearance_type='reversal' then
    if new.balance_effect<>'restore' then
      raise exception 'LESSON_CLEARANCE_DETAIL_REVERSAL_EFFECT_INVALID';
    end if;
  elsif new.balance_effect<>'consume' then
    raise exception 'LESSON_CLEARANCE_DETAIL_CONSUME_EFFECT_INVALID';
  end if;
  if v_header.clearance_type='overtime_offset'
     and new.overtime_source_actual_id is null then
    raise exception 'LESSON_CLEARANCE_DETAIL_OVERTIME_SOURCE_REQUIRED';
  elsif v_header.clearance_type in (
      'administrative_writeoff','legacy_consolidated_fulfillment'
    ) and new.overtime_source_actual_id is not null then
    raise exception 'LESSON_CLEARANCE_DETAIL_OVERTIME_SOURCE_FORBIDDEN';
  end if;
  if new.overtime_source_actual_id is not null then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=new.overtime_source_actual_id;
    if v_overtime.lesson_type<>'actual'
       or v_overtime.student_id<>v_header.student_id
       or v_overtime.business_entity_id<>v_header.business_entity_id then
      raise exception 'LESSON_CLEARANCE_DETAIL_OVERTIME_SCOPE_INVALID';
    end if;
  end if;
  return new;
end
$function$;

create trigger school_lesson_clearance_detail_validate
before insert on public.school_lesson_clearance_details
for each row execute function public.school_validate_lesson_clearance_detail();

create function public.school_prevent_lesson_clearance_mutation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
begin
  raise exception 'LESSON_CLEARANCE_APPEND_ONLY';
end
$function$;

create trigger school_lesson_clearances_append_only
before update or delete on public.school_lesson_clearances
for each row execute function public.school_prevent_lesson_clearance_mutation();
create trigger school_lesson_clearance_details_append_only
before update or delete on public.school_lesson_clearance_details
for each row execute function public.school_prevent_lesson_clearance_mutation();
create trigger school_lesson_clearances_truncate_guard
before truncate on public.school_lesson_clearances
for each statement execute function public.school_prevent_lesson_clearance_mutation();
create trigger school_lesson_clearance_details_truncate_guard
before truncate on public.school_lesson_clearance_details
for each statement execute function public.school_prevent_lesson_clearance_mutation();

alter function public.school_get_lesson_clearance_allocated_minutes(uuid) owner to postgres;
alter function public.school_get_lesson_clearance_overtime_allocated_minutes(uuid) owner to postgres;
alter function public.school_get_lesson_clearance_pending_remaining_minutes(uuid) owner to postgres;
alter function public.school_get_lesson_clearance_overtime_remaining_minutes(uuid) owner to postgres;
alter function public.school_get_lesson_clearance_source_manifest(uuid,uuid) owner to postgres;
alter function public.school_assert_lesson_clearance_reader() owner to postgres;
alter function public.school_suggest_lesson_clearance_targets_core(uuid) owner to postgres;
alter function public.school_suggest_lesson_clearance_targets(uuid) owner to postgres;
alter function public.school_assert_lesson_clearance_actor() owner to postgres;
alter function public.school_list_lesson_clearance_pending_balances(uuid,boolean) owner to postgres;
alter function public.school_list_lesson_clearance_available_overages(uuid,boolean) owner to postgres;
alter function public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text) owner to postgres;
alter function public.school_list_lesson_clearance_history(uuid) owner to postgres;
alter function public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text) owner to postgres;
alter function public.school_list_cross_month_makeup_projection(uuid,text) owner to postgres;
alter function public.school_create_lesson_clearance_core(
  text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text
) owner to postgres;
alter function public.school_create_lesson_clearance(
  text,uuid,uuid,integer,date,text,text,text,text,text
) owner to postgres;
alter function public.school_reverse_lesson_clearance_core(
  uuid,date,text,text,uuid,text
) owner to postgres;
alter function public.school_reverse_lesson_clearance(uuid,date,text,text) owner to postgres;
alter function public.school_guard_variance_claim_clearance_mutex() owner to postgres;
alter function public.school_validate_lesson_clearance_detail() owner to postgres;
alter function public.school_prevent_lesson_clearance_mutation() owner to postgres;

revoke all on function public.school_get_lesson_clearance_allocated_minutes(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_clearance_overtime_allocated_minutes(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_clearance_pending_remaining_minutes(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_clearance_overtime_remaining_minutes(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_clearance_source_manifest(uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_assert_lesson_clearance_actor()
  from public,anon,authenticated,service_role;
revoke all on function public.school_assert_lesson_clearance_reader()
  from public,anon,authenticated,service_role;
revoke all on function public.school_suggest_lesson_clearance_targets_core(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_lesson_clearance_core(
  text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_reverse_lesson_clearance_core(
  uuid,date,text,text,uuid,text
) from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_source_lines(
  uuid,uuid,text,numeric,boolean
) from public,anon,authenticated,service_role;
revoke all on function public.school_guard_variance_claim_clearance_mutex()
  from public,anon,authenticated,service_role;
revoke all on function public.school_validate_lesson_clearance_detail()
  from public,anon,authenticated,service_role;
revoke all on function public.school_prevent_lesson_clearance_mutation()
  from public,anon,authenticated,service_role;

revoke all on function public.school_create_lesson_clearance(
  text,uuid,uuid,integer,date,text,text,text,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_clearance(
  text,uuid,uuid,integer,date,text,text,text,text,text
) to authenticated;
revoke all on function public.school_reverse_lesson_clearance(uuid,date,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_reverse_lesson_clearance(uuid,date,text,text)
  to authenticated;

revoke all on function public.school_suggest_lesson_clearance_targets(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_suggest_lesson_clearance_targets(uuid)
  to authenticated;
revoke all on function public.school_list_lesson_clearance_pending_balances(uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_pending_balances(uuid,boolean)
  to authenticated;
revoke all on function public.school_list_lesson_clearance_available_overages(uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_available_overages(uuid,boolean)
  to authenticated;
revoke all on function public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)
  to authenticated;
revoke all on function public.school_list_lesson_clearance_history(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_history(uuid)
  to authenticated;
revoke all on function public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text)
  to authenticated;
revoke all on function public.school_list_cross_month_makeup_projection(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_cross_month_makeup_projection(uuid,text)
  to authenticated;
revoke all on public.school_lesson_clearances from public,anon,authenticated,service_role;
revoke all on public.school_lesson_clearance_details from public,anon,authenticated,service_role;

comment on function public.school_create_lesson_clearance(
  text,uuid,uuid,integer,date,text,text,text,text,text
) is 'Phase 2C-C manual-target writer. V2 supports same-price overtime offset and admin writeoff; no automatic FIFO selection.';
comment on function public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text) is
  'Phase 2C-C DB-authoritative forward evidence for future settlement Preview manifests; it never rewrites locked history.';
comment on function public.school_list_cross_month_makeup_projection(uuid,text) is
  'Phase 2C-C read-only dual-month projection. Both rows preserve one authoritative makeup actual UUID.';

\if :{?PHASE2C_C_REHEARSAL}
\else
commit;
\endif
