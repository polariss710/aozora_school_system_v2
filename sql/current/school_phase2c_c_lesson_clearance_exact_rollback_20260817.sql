-- School V2 Phase 2C-C exact rollback to the deployed Phase 2I-A backend.
-- Safe only while both clearance tables are empty. The P002 package lot is preserved.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  if to_regclass('public.school_lesson_clearances') is null
     or to_regclass('public.school_lesson_clearance_details') is null then
    raise exception 'LESSON_CLEARANCE_ROLLBACK_SCHEMA_MISSING';
  end if;
  if exists(select 1 from public.school_lesson_clearance_details)
     or exists(select 1 from public.school_lesson_clearances) then
    raise exception 'LESSON_CLEARANCE_ROLLBACK_BUSINESS_FACTS_EXIST';
  end if;
  if not exists(select 1 from public.school_student_package_credit_lots
    where id='2a000000-0000-4000-8000-202608170002'
      and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
      and status='active') then
    raise exception 'LESSON_CLEARANCE_ROLLBACK_P002_BASELINE_MISMATCH';
  end if;
end
$preflight$;

drop trigger school_variance_claim_clearance_mutex
  on public.school_student_settlement_lesson_variance_claims;
drop trigger school_lesson_clearance_detail_validate
  on public.school_lesson_clearance_details;
drop trigger school_lesson_clearances_append_only
  on public.school_lesson_clearances;
drop trigger school_lesson_clearance_details_append_only
  on public.school_lesson_clearance_details;
drop trigger school_lesson_clearances_truncate_guard
  on public.school_lesson_clearances;
drop trigger school_lesson_clearance_details_truncate_guard
  on public.school_lesson_clearance_details;

-- Restore the five predeployment Phase 2I-A definitions byte-for-byte at source level.
create or replace function public.school_get_lesson_credit_raw_remaining_hours(
  p_planned_lesson_id uuid
) returns numeric language sql stable security definer
set search_path=pg_catalog,public as $function$
  select case when public.school_is_active_package_credit_origin(p.id) then 0
    else p.duration_hours-coalesce(sum(a.duration_hours) filter(
      where a.lesson_type='actual'
        and a.status in ('completed','makeup_completed')
        and a.voided_at is null
    ),0) end
  from public.school_lesson_records p
  left join public.school_lesson_records a on a.planned_lesson_id=p.id
  where p.id=p_planned_lesson_id and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create or replace function public.school_get_lesson_credit_remaining_hours(
  p_planned_lesson_id uuid
) returns numeric language sql stable security definer
set search_path=pg_catalog,public as $function$
  select case when public.school_is_active_package_credit_origin(p.id) then 0
    else greatest(
      coalesce(p.duration_hours,0)-coalesce(sum(a.duration_hours) filter(
        where a.lesson_type='actual'
          and a.status in ('completed','makeup_completed')
      ),0),0
    )::numeric end
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id=p.id and a.app_type='school'
  where p.id=p_planned_lesson_id and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create or replace function public.school_list_student_lesson_credit_balances(
  p_student_id uuid default null
) returns table(
  student_id uuid,business_entity_id uuid,open_source_count bigint,
  open_credit_hours numeric,oldest_credit_date date
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with credit_sources as(
    select p.id,p.student_id,p.business_entity_id,p.lesson_date,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        remaining_hours
    from public.school_lesson_records p
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and (p_student_id is null or p.student_id=p_student_id)
      and not public.school_is_active_package_credit_origin(p.id)
      and not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='unused_planned_credit_v1'
          and claim.source_planned_lesson_id=p.id
      )
  )
  select source.student_id,source.business_entity_id,
    count(*) filter(where source.remaining_hours>0)::bigint,
    coalesce(sum(source.remaining_hours) filter(where source.remaining_hours>0),0)::numeric,
    min(source.lesson_date) filter(where source.remaining_hours>0)
  from credit_sources source where source.student_id is not null
  group by source.student_id,source.business_entity_id
$function$;

create or replace function public.school_list_open_lesson_credit_sources(
  p_from_month text,p_to_month text,p_target_month text
) returns table(
  id uuid,lesson_date date,year_month text,student_id uuid,teacher_id uuid,
  subject_id uuid,business_entity_id uuid,start_time text,end_time text,
  duration_hours numeric,lesson_content text,note text,lesson_count integer,
  unit_price numeric,lesson_delivery_mode text,lesson_venue text,
  remaining_hours numeric
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with args as(
    select nullif(trim(coalesce(p_from_month,'')),'') from_month,
      nullif(trim(coalesce(p_to_month,'')),'') to_month,
      nullif(trim(coalesce(p_target_month,'')),'') target_month
  ),sources as(
    select p.id,p.lesson_date,
      public.school_resolve_r1d_e_c_lesson_student_month(p.id) source_month,
      p.student_id,p.teacher_id,p.subject_id,p.business_entity_id,p.start_time,
      p.end_time,p.duration_hours,p.lesson_content,p.note,p.lesson_count,
      p.unit_price,p.lesson_delivery_mode,p.lesson_venue,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        remaining_hours
    from public.school_lesson_records p cross join args input
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and input.from_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.to_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.target_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.from_month<=input.to_month and input.to_month<=input.target_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        between input.from_month and input.to_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)<=input.target_month
      and not public.school_is_active_package_credit_origin(p.id)
  )
  select source.id,source.lesson_date,source.source_month,source.student_id,
    source.teacher_id,source.subject_id,source.business_entity_id,
    source.start_time,source.end_time,source.duration_hours,source.lesson_content,
    source.note,source.lesson_count,source.unit_price,source.lesson_delivery_mode,
    source.lesson_venue,source.remaining_hours
  from sources source
  where source.remaining_hours>0 and not exists(
    select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=source.id
  )
  order by source.source_month,source.lesson_date,
    source.lesson_count nulls last,source.start_time nulls last,source.id
$function$;

create or replace function public.school_tuition_p0f_source_lines(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text,
  p_settlement_exchange_rate numeric,p_include_active_claimed boolean default false
) returns table(
  source_type text,source_planned_lesson_id uuid,source_actual_lesson_id uuid,
  source_hours numeric,source_amount_jpy numeric,source_amount_cny numeric,
  line_manifest_sha256 text
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with unused_sources as(
    select 'unused_planned_credit_v1'::text source_type,
      p.id source_planned_lesson_id,null::uuid source_actual_lesson_id,
      -public.school_get_lesson_credit_remaining_hours(p.id)::numeric source_hours,
      -round(coalesce(p.base_lesson_fee_jpy,p.lesson_fee,
        p.unit_price*p.duration_hours,0)
        * public.school_get_lesson_credit_remaining_hours(p.id)
        /nullif(p.duration_hours,0),2)::numeric source_amount_jpy
    from public.school_lesson_records p
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and p.student_id=p_student_id and p.business_entity_id=p_business_entity_id
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)=p_year_month
      and p.duration_hours>0
      and coalesce(p.base_lesson_fee_jpy,p.lesson_fee,
        p.unit_price*p.duration_hours,0)>=0
      and not public.school_is_active_package_credit_origin(p.id)
      and public.school_get_lesson_credit_remaining_hours(p.id)>0
      and (p_include_active_claimed or not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims c
        where c.claim_status='active'
          and c.source_type='unused_planned_credit_v1'
          and c.source_planned_lesson_id=p.id
      ))
  ),overage_sources as(
    select 'actual_duration_overage_charge_v1'::text source_type,
      a.planned_lesson_id source_planned_lesson_id,a.id source_actual_lesson_id,
      round(a.student_duration_overage_minutes::numeric/60,6)::numeric source_hours,
      round(a.student_duration_overage_fee_jpy,2)::numeric source_amount_jpy
    from public.school_lesson_records a
    where a.app_type='school' and a.lesson_type='actual'
      and a.status='completed' and a.is_billable is true and a.voided_at is null
      and a.student_id=p_student_id and a.business_entity_id=p_business_entity_id
      and a.student_settlement_month=p_year_month
      and a.student_duration_overage_policy_version='student_duration_overage_v1'
      and a.student_duration_overage_source='ordinary_actual_rpc'
      and a.student_duration_overage_minutes>0
      and a.student_duration_overage_fee_jpy>0
      and (p_include_active_claimed or not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims c
        where c.claim_status='active'
          and c.source_type='actual_duration_overage_charge_v1'
          and c.source_actual_lesson_id=a.id
      ))
  ),lines as(
    select * from unused_sources union all select * from overage_sources
  ),converted as(
    select line.*,
      round(line.source_amount_jpy*p_settlement_exchange_rate,2)::numeric
        source_amount_cny from lines line
  )
  select converted.source_type,converted.source_planned_lesson_id,
    converted.source_actual_lesson_id,converted.source_hours,
    converted.source_amount_jpy,converted.source_amount_cny,
    encode(extensions.digest(concat_ws('|','lesson_variance_financial_netting_v1',
      converted.source_type,coalesce(converted.source_planned_lesson_id::text,''),
      coalesce(converted.source_actual_lesson_id::text,''),
      converted.source_hours::text,converted.source_amount_jpy::text,
      converted.source_amount_cny::text,
      to_char(p_settlement_exchange_rate,'FM999999990.000000')),
      'sha256'),'hex')::text
  from converted order by converted.source_type,
    converted.source_planned_lesson_id,converted.source_actual_lesson_id
$function$;

alter function public.school_get_lesson_credit_raw_remaining_hours(uuid) owner to postgres;
alter function public.school_get_lesson_credit_remaining_hours(uuid) owner to postgres;
alter function public.school_list_student_lesson_credit_balances(uuid) owner to postgres;
alter function public.school_list_open_lesson_credit_sources(text,text,text) owner to postgres;
alter function public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean) owner to postgres;

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

drop function public.school_reverse_lesson_clearance(uuid,date,text,text);
drop function public.school_reverse_lesson_clearance_core(uuid,date,text,text,uuid,text);
drop function public.school_create_lesson_clearance(
  text,uuid,uuid,integer,date,text,text,text,text,text
);
drop function public.school_create_lesson_clearance_core(
  text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text
);
drop function public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text);
drop function public.school_list_lesson_clearance_forward_manifest(uuid,uuid,text);
drop function public.school_list_lesson_clearance_history(uuid);
drop function public.school_list_cross_month_makeup_projection(uuid,text);
drop function public.school_list_lesson_clearance_available_overages(uuid,boolean);
drop function public.school_list_lesson_clearance_pending_balances(uuid,boolean);
drop function public.school_suggest_lesson_clearance_targets(uuid);
drop function public.school_suggest_lesson_clearance_targets_core(uuid);
drop function public.school_assert_lesson_clearance_actor();
drop function public.school_assert_lesson_clearance_reader();
drop function public.school_get_lesson_clearance_source_manifest(uuid,uuid);
drop function public.school_guard_variance_claim_clearance_mutex();
drop function public.school_validate_lesson_clearance_detail();
drop function public.school_prevent_lesson_clearance_mutation();
drop function public.school_get_lesson_clearance_overtime_remaining_minutes(uuid);
drop function public.school_get_lesson_clearance_pending_remaining_minutes(uuid);
drop function public.school_get_lesson_clearance_overtime_allocated_minutes(uuid);
drop function public.school_get_lesson_clearance_allocated_minutes(uuid);

drop table public.school_lesson_clearance_details;
drop table public.school_lesson_clearances;

\if :{?PHASE2C_C_REHEARSAL}
\else
commit;
\endif
