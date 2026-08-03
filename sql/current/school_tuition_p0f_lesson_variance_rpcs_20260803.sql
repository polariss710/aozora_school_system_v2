-- School V2 tuition P0-F RPC cutover.
-- Usage: psql -v p0f_rpc_commit=0|1 -f this_file.sql
-- No business rows are changed by installation.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0f_rpc_commit}
\else
  \set p0f_rpc_commit 0
\endif

begin;
set local lock_timeout = '8s';
set local statement_timeout = '240s';

do $preflight$
begin
  if to_regclass('public.school_student_settlement_source_treatment_drafts') is null
     or to_regclass('public.school_student_settlement_lesson_variance_claims') is null then
    raise exception 'P0F_SCHEMA_NOT_INSTALLED';
  end if;
  if to_regprocedure('public.school_preview_student_settlement_source_treatment(uuid,text,text,numeric,text,date)') is not null
     or to_regprocedure('public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)') is not null
     or to_regprocedure('public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)') is not null
     or to_regprocedure('public.school_get_student_monthly_settlement_summary_p0f_legacy(uuid,text)') is not null then
    raise exception 'P0F_RPC_ALREADY_INSTALLED';
  end if;
  if to_regprocedure('public.school_get_student_monthly_settlement_summary(uuid,text)') is null
     or to_regprocedure('public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text)') is null
     or to_regprocedure('public.school_assert_tuition_settlement_month_mutable(uuid,text)') is null
     or to_regprocedure('public.school_get_lesson_credit_remaining_hours(uuid)') is null then
    raise exception 'P0F_REQUIRED_AUTHORITY_MISSING';
  end if;
end
$preflight$;

-- The original summary remains an immutable legacy implementation. The public
-- name below becomes the P0-F-aware wrapper; exact rollback restores the name.
alter function public.school_get_student_monthly_settlement_summary(uuid,text)
  rename to school_get_student_monthly_settlement_summary_p0f_legacy;

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
$function$;

create or replace function public.school_tuition_p0f_assert_sources_resolved(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare v_lesson_id uuid;
begin
  select p.id into v_lesson_id
  from public.school_lesson_records p
  where p.app_type='school' and p.lesson_type='planned'
    and p.student_id=p_student_id
    and p.business_entity_id=p_business_entity_id
    and public.school_resolve_r1d_e_c_lesson_student_month(p.id)=p_year_month
    and p.voided_at is null
    and coalesce(p.is_billable,true) is true
    and p.status not in ('pending_makeup','makeup_completed','completed','cancelled')
    and not exists (
      select 1 from public.school_lesson_records a
      where a.app_type='school' and a.lesson_type='actual'
        and a.planned_lesson_id=p.id
        and (a.status in ('completed','makeup_completed','cancelled')
             or a.is_billable is false)
    )
  order by p.id limit 1;
  if v_lesson_id is not null then
    raise exception 'SETTLEMENT_LESSON_SOURCE_UNRESOLVED: %',v_lesson_id;
  end if;

  select p.id into v_lesson_id
  from public.school_lesson_records p
  where p.app_type='school' and p.lesson_type='planned'
    and p.student_id=p_student_id and p.business_entity_id=p_business_entity_id
    and public.school_resolve_r1d_e_c_lesson_student_month(p.id)=p_year_month
    and p.status='pending_makeup' and p.voided_at is null
    and (p.duration_hours<=0
      or coalesce(p.base_lesson_fee_jpy,p.lesson_fee,p.unit_price*p.duration_hours) is null
      or public.school_get_lesson_credit_remaining_hours(p.id)>p.duration_hours)
  order by p.id limit 1;
  if v_lesson_id is not null then
    raise exception 'SETTLEMENT_LESSON_SOURCE_VALUE_INVALID: %',v_lesson_id;
  end if;
end
$function$;

create or replace function public.school_preview_student_settlement_source_treatment(
  p_student_id uuid,
  p_year_month text,
  p_source_treatment_mode text default null,
  p_settlement_exchange_rate numeric default null,
  p_settlement_exchange_rate_source text default null,
  p_settlement_exchange_rate_effective_date date default null
)
returns table (
  student_id uuid,year_month text,business_entity_id uuid,
  source_treatment_mode text,settlement_exchange_rate numeric,
  settlement_exchange_rate_source text,
  settlement_exchange_rate_effective_date date,
  lesson_variance_calculation_version text,
  planned_hours numeric,actual_hours numeric,
  planned_fee_jpy numeric,planned_fee_cny numeric,
  actual_fee_jpy numeric,actual_fee_cny numeric,
  unused_planned_credit_jpy numeric,unused_planned_credit_cny numeric,
  pending_makeup_hours numeric,overage_hours numeric,
  overage_charge_jpy numeric,overage_charge_cny numeric,
  lesson_variance_display_hours numeric,
  net_lesson_variance_jpy numeric,net_lesson_variance_cny numeric,
  previous_carryover_cny numeric,received_jpy numeric,received_cny numeric,
  received_equivalent_cny numeric,system_difference_cny numeric,
  lesson_variance_source_count integer,
  lesson_variance_manifest_sha256 text,draft_id uuid,draft_status text
)
language plpgsql
volatile
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_entity uuid; v_mode text; v_rate numeric; v_rate_source text;
  v_effective_date date; v_draft record; v_legacy record;
  v_unused_jpy numeric:=0; v_unused_cny numeric:=0; v_unused_hours numeric:=0;
  v_overage_jpy numeric:=0; v_overage_cny numeric:=0; v_overage_hours numeric:=0;
  v_count integer:=0; v_manifest text; v_net_jpy numeric; v_net_cny numeric;
  v_planned_cny numeric; v_actual_cny numeric; v_received_equiv numeric;
  v_system numeric;
begin
  if p_student_id is null or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID';
  end if;
  select s.business_entity_id into v_entity
  from public.school_students s where s.id=p_student_id and s.app_type='school';
  if v_entity is null then raise exception 'SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID'; end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id,v_entity,p_year_month
  );
  select * into v_draft
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id=p_student_id and d.business_entity_id=v_entity
    and d.year_month=p_year_month and d.status='active'
  order by d.created_at desc limit 1;
  v_mode:=coalesce(p_source_treatment_mode,v_draft.source_treatment_mode,
    'separate_makeup_and_overage_v1');
  if v_mode not in ('separate_makeup_and_overage_v1',
                    'net_lesson_variance_to_financial_credit_v1') then
    raise exception 'SETTLEMENT_SOURCE_TREATMENT_MODE_INVALID';
  end if;
  if v_mode='net_lesson_variance_to_financial_credit_v1' then
    v_rate:=coalesce(p_settlement_exchange_rate,v_draft.settlement_exchange_rate);
    v_rate_source:=coalesce(nullif(btrim(p_settlement_exchange_rate_source),''),
      v_draft.settlement_exchange_rate_source);
    v_effective_date:=coalesce(p_settlement_exchange_rate_effective_date,
      v_draft.settlement_exchange_rate_effective_date);
    if v_rate is null or v_rate<=0 or v_rate_source is null or v_effective_date is null then
      raise exception 'SETTLEMENT_EXPLICIT_EXCHANGE_RATE_REQUIRED';
    end if;
    if to_char(v_effective_date,'YYYY-MM')<>p_year_month then
      raise exception 'SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH';
    end if;
    perform public.school_tuition_p0f_assert_sources_resolved(
      p_student_id,v_entity,p_year_month
    );
    select
      coalesce(sum(l.source_amount_jpy) filter(where l.source_type='unused_planned_credit_v1'),0),
      coalesce(sum(l.source_amount_cny) filter(where l.source_type='unused_planned_credit_v1'),0),
      -coalesce(sum(l.source_hours) filter(where l.source_type='unused_planned_credit_v1'),0),
      coalesce(sum(l.source_amount_jpy) filter(where l.source_type='actual_duration_overage_charge_v1'),0),
      coalesce(sum(l.source_amount_cny) filter(where l.source_type='actual_duration_overage_charge_v1'),0),
      coalesce(sum(l.source_hours) filter(where l.source_type='actual_duration_overage_charge_v1'),0),
      count(*)::integer,
      encode(extensions.digest(coalesce(string_agg(l.line_manifest_sha256,'' order by
        l.source_type,l.source_planned_lesson_id,l.source_actual_lesson_id),''),'sha256'),'hex')
    into v_unused_jpy,v_unused_cny,v_unused_hours,
      v_overage_jpy,v_overage_cny,v_overage_hours,v_count,v_manifest
    from public.school_tuition_p0f_source_lines(
      p_student_id,v_entity,p_year_month,v_rate,false
    ) l;
  else
    v_rate:=null; v_rate_source:=null; v_effective_date:=null;
    v_manifest:=encode(extensions.digest('separate_makeup_and_overage_v1','sha256'),'hex');
  end if;
  select * into strict v_legacy
  from public.school_get_student_monthly_settlement_summary_p0f_legacy(
    p_student_id,p_year_month
  );
  v_net_jpy:=round(v_unused_jpy+v_overage_jpy,2);
  v_net_cny:=case when v_mode='net_lesson_variance_to_financial_credit_v1'
    then round(v_net_jpy*v_rate,2) else 0 end;
  v_planned_cny:=case when v_mode='net_lesson_variance_to_financial_credit_v1'
    then round(v_legacy.planned_fee_jpy*v_rate,2) else v_legacy.planned_fee_cny end;
  v_actual_cny:=case when v_mode='net_lesson_variance_to_financial_credit_v1'
    then round(v_legacy.actual_fee_jpy*v_rate,2) else v_legacy.actual_fee_cny end;
  v_received_equiv:=case when v_mode='net_lesson_variance_to_financial_credit_v1'
    then round(v_legacy.received_cny+v_legacy.received_jpy*v_rate,2)
    else v_legacy.received_equivalent_cny end;
  v_system:=case when v_mode='net_lesson_variance_to_financial_credit_v1'
    then round(v_planned_cny+v_legacy.carryover_cny+v_net_cny-v_received_equiv,2)
    else v_legacy.final_due_cny end;
  return query select p_student_id,p_year_month,v_entity,v_mode,v_rate,v_rate_source,
    v_effective_date,'lesson_variance_financial_netting_v1'::text,
    v_legacy.planned_hours,v_legacy.actual_hours,v_legacy.planned_fee_jpy,
    v_planned_cny,v_legacy.actual_fee_jpy,v_actual_cny,
    round(v_unused_jpy,2),round(v_unused_cny,2),round(v_unused_hours,6),
    round(v_overage_hours,6),round(v_overage_jpy,2),round(v_overage_cny,2),
    round(v_overage_hours-v_unused_hours,6),v_net_jpy,v_net_cny,
    v_legacy.carryover_cny,v_legacy.received_jpy,v_legacy.received_cny,
    v_received_equiv,v_system,v_count,v_manifest,v_draft.id,v_draft.status;
end
$function$;

create or replace function public.school_get_student_monthly_settlement_summary(
  p_student_id uuid,p_year_month text
)
returns table (
  student_id uuid,year_month text,exchange_rate numeric,carryover_cny numeric,
  planned_hours numeric,actual_hours numeric,planned_fee_jpy numeric,
  planned_fee_cny numeric,planned_total_cny numeric,actual_fee_jpy numeric,
  actual_fee_cny numeric,received_jpy numeric,received_cny numeric,
  received_equivalent_cny numeric,final_due_cny numeric,
  locked_carryover_cny numeric
)
language plpgsql
volatile
security definer
set search_path=pg_catalog,public
as $function$
declare v_legacy record; v_p0f record; v_locked public.school_student_monthly_settlements%rowtype;
begin
  select * into strict v_legacy
  from public.school_get_student_monthly_settlement_summary_p0f_legacy(p_student_id,p_year_month);
  select * into v_locked from public.school_student_monthly_settlements m
  where m.student_id=p_student_id and m.year_month=p_year_month
    and m.settlement_status='locked' order by m.locked_at desc limit 1;
  if found and v_locked.source_treatment_mode='net_lesson_variance_to_financial_credit_v1' then
    return query select v_locked.student_id,v_locked.year_month,
      v_locked.preset_exchange_rate,v_locked.previous_balance_cny,
      v_legacy.planned_hours,v_legacy.actual_hours,
      v_locked.planned_lesson_fee_jpy,v_locked.planned_lesson_fee_cny,
      round(v_locked.planned_lesson_fee_cny+v_locked.previous_balance_cny,2),
      v_locked.actual_lesson_fee_jpy,v_locked.actual_lesson_fee_cny,
      v_locked.received_jpy,v_locked.received_cny,v_locked.received_equivalent_cny,
      v_locked.system_difference_cny,v_locked.carryover_amount_cny;
    return;
  end if;
  select * into strict v_p0f
  from public.school_preview_student_settlement_source_treatment(
    p_student_id,p_year_month,null,null,null,null
  );
  return query select v_legacy.student_id,v_legacy.year_month,
    v_legacy.exchange_rate,v_p0f.previous_carryover_cny,
    v_p0f.planned_hours,v_p0f.actual_hours,v_p0f.planned_fee_jpy,
    v_p0f.planned_fee_cny,round(v_p0f.planned_fee_cny+v_p0f.previous_carryover_cny,2),
    v_p0f.actual_fee_jpy,v_p0f.actual_fee_cny,v_p0f.received_jpy,
    v_p0f.received_cny,v_p0f.received_equivalent_cny,
    v_p0f.system_difference_cny,
    coalesce(v_locked.carryover_amount_cny,v_p0f.system_difference_cny);
end
$function$;

create or replace function public.school_set_student_settlement_source_treatment_draft(
  p_student_id uuid,p_year_month text,p_source_treatment_mode text,
  p_settlement_exchange_rate numeric,
  p_settlement_exchange_rate_source text,
  p_settlement_exchange_rate_effective_date date,
  p_reason text
)
returns setof public.school_student_settlement_source_treatment_drafts
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare v_entity uuid; v_preview record; v_now timestamptz:=now(); v_id uuid;
begin
  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'SETTLEMENT_SOURCE_TREATMENT_REASON_REQUIRED';
  end if;
  select s.business_entity_id into v_entity from public.school_students s
  where s.id=p_student_id and s.app_type='school';
  if v_entity is null then raise exception 'SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID'; end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(p_student_id,v_entity,p_year_month);
  perform public.school_assert_tuition_settlement_month_mutable(p_student_id,p_year_month);
  if exists(select 1 from public.school_student_monthly_settlements m
            where m.student_id=p_student_id and m.year_month=p_year_month
              and coalesce(m.settlement_status,'')<>'unlocked') then
    raise exception 'SETTLEMENT_SOURCE_TREATMENT_LOCKED_READ_ONLY';
  end if;
  select * into strict v_preview
  from public.school_preview_student_settlement_source_treatment(
    p_student_id,p_year_month,p_source_treatment_mode,
    p_settlement_exchange_rate,p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date
  );
  perform set_config('school.p0f_draft_writer','on',true);
  update public.school_student_settlement_source_treatment_drafts d
  set status='superseded',superseded_at=v_now,updated_at=v_now,updated_by=current_user
  where d.student_id=p_student_id and d.business_entity_id=v_entity
    and d.year_month=p_year_month and d.status='active';
  insert into public.school_student_settlement_source_treatment_drafts(
    student_id,business_entity_id,year_month,source_treatment_mode,
    settlement_exchange_rate,settlement_exchange_rate_source,
    settlement_exchange_rate_effective_date,lesson_variance_calculation_version,
    source_manifest_sha256,source_count,status,reason,created_by,updated_by
  ) values (
    p_student_id,v_entity,p_year_month,v_preview.source_treatment_mode,
    v_preview.settlement_exchange_rate,v_preview.settlement_exchange_rate_source,
    v_preview.settlement_exchange_rate_effective_date,
    'lesson_variance_financial_netting_v1',v_preview.lesson_variance_manifest_sha256,
    v_preview.lesson_variance_source_count,'active',btrim(p_reason),current_user,current_user
  ) returning id into v_id;
  perform set_config('school.p0f_draft_writer','off',true);
  return query select * from public.school_student_settlement_source_treatment_drafts d
  where d.id=v_id;
end
$function$;

create or replace function public.school_tuition_p0f_guard_draft_dml()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if coalesce(current_setting('school.p0f_draft_writer',true),'off')<>'on' then
    raise exception 'SETTLEMENT_SOURCE_TREATMENT_DRAFT_RPC_ONLY';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

create or replace function public.school_tuition_p0f_guard_claim_dml()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if coalesce(current_setting('school.p0f_claim_writer',true),'off')<>'on' then
    raise exception 'SETTLEMENT_LESSON_VARIANCE_CLAIM_RPC_ONLY';
  end if;
  if tg_op='DELETE' then raise exception 'SETTLEMENT_LESSON_VARIANCE_CLAIM_DELETE_FORBIDDEN'; end if;
  if tg_op='UPDATE' and (
    new.id is distinct from old.id or new.claim_batch_id is distinct from old.claim_batch_id
    or new.claim_batch_version is distinct from old.claim_batch_version
    or new.settlement_id is distinct from old.settlement_id
    or new.student_id is distinct from old.student_id
    or new.business_entity_id is distinct from old.business_entity_id
    or new.year_month is distinct from old.year_month
    or new.source_type is distinct from old.source_type
    or new.source_planned_lesson_id is distinct from old.source_planned_lesson_id
    or new.source_actual_lesson_id is distinct from old.source_actual_lesson_id
    or new.source_hours is distinct from old.source_hours
    or new.source_amount_jpy is distinct from old.source_amount_jpy
    or new.source_amount_cny is distinct from old.source_amount_cny
    or new.settlement_exchange_rate is distinct from old.settlement_exchange_rate
    or new.calculation_version is distinct from old.calculation_version
    or new.line_manifest_sha256 is distinct from old.line_manifest_sha256
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by
  ) then raise exception 'SETTLEMENT_LESSON_VARIANCE_CLAIM_IMMUTABLE'; end if;
  return new;
end
$function$;

create trigger school_tuition_p0f_draft_rpc_only
before insert or update or delete on public.school_student_settlement_source_treatment_drafts
for each row execute function public.school_tuition_p0f_guard_draft_dml();
create trigger school_tuition_p0f_claim_rpc_only
before insert or update or delete on public.school_student_settlement_lesson_variance_claims
for each row execute function public.school_tuition_p0f_guard_claim_dml();

create or replace function public.school_tuition_p0f_settlement_before()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_draft record; v_preview record; v_preset numeric;
begin
  if new.settlement_status='locked'
     and (tg_op='INSERT' or old.settlement_status is distinct from 'locked') then
    select * into v_draft
    from public.school_student_settlement_source_treatment_drafts d
    where d.student_id=new.student_id and d.business_entity_id=new.business_entity_id
      and d.year_month=new.year_month and d.status='active'
    order by d.created_at desc limit 1;
    if tg_op='UPDATE'
       and old.source_treatment_mode='net_lesson_variance_to_financial_credit_v1'
       and v_draft.id is null then
      raise exception 'SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK';
    end if;
    select * into strict v_preview
    from public.school_preview_student_settlement_source_treatment(
      new.student_id,new.year_month,
      coalesce(v_draft.source_treatment_mode,'separate_makeup_and_overage_v1'),
      v_draft.settlement_exchange_rate,v_draft.settlement_exchange_rate_source,
      v_draft.settlement_exchange_rate_effective_date
    );
    if v_draft.id is not null
       and v_draft.source_manifest_sha256 is distinct from v_preview.lesson_variance_manifest_sha256 then
      raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT: draft=% current=%',
        v_draft.source_manifest_sha256,v_preview.lesson_variance_manifest_sha256;
    end if;
    new.source_treatment_mode:=v_preview.source_treatment_mode;
    if v_preview.source_treatment_mode='net_lesson_variance_to_financial_credit_v1' then
      select s.preset_exchange_rate into v_preset from public.school_students s where s.id=new.student_id;
      new.preset_exchange_rate:=v_preset;
      new.settlement_exchange_rate:=v_preview.settlement_exchange_rate;
      new.settlement_exchange_rate_source:=v_preview.settlement_exchange_rate_source;
      new.settlement_exchange_rate_effective_date:=v_preview.settlement_exchange_rate_effective_date;
      new.lesson_variance_calculation_version:='lesson_variance_financial_netting_v1';
      new.unused_planned_credit_jpy:=v_preview.unused_planned_credit_jpy;
      new.unused_planned_credit_cny:=v_preview.unused_planned_credit_cny;
      new.pending_makeup_hours:=v_preview.pending_makeup_hours;
      new.lesson_variance_display_hours:=v_preview.lesson_variance_display_hours;
      new.net_lesson_variance_jpy:=v_preview.net_lesson_variance_jpy;
      new.net_lesson_variance_cny:=v_preview.net_lesson_variance_cny;
      new.lesson_variance_source_count:=v_preview.lesson_variance_source_count;
      new.lesson_variance_manifest_sha256:=v_preview.lesson_variance_manifest_sha256;
    else
      new.settlement_exchange_rate:=null;
      new.settlement_exchange_rate_source:=null;
      new.settlement_exchange_rate_effective_date:=null;
      new.lesson_variance_calculation_version:=null;
      new.unused_planned_credit_jpy:=null; new.unused_planned_credit_cny:=null;
      new.pending_makeup_hours:=null; new.lesson_variance_display_hours:=null;
      new.net_lesson_variance_jpy:=null; new.net_lesson_variance_cny:=null;
      new.lesson_variance_source_count:=null; new.lesson_variance_manifest_sha256:=null;
    end if;
  end if;
  return new;
end
$function$;

create or replace function public.school_tuition_p0f_settlement_after()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_batch uuid; v_version integer; v_draft uuid;
begin
  if new.settlement_status='locked'
     and (tg_op='INSERT' or old.settlement_status is distinct from 'locked')
     and new.source_treatment_mode='net_lesson_variance_to_financial_credit_v1' then
    select coalesce(max(c.claim_batch_version),0)+1 into v_version
    from public.school_student_settlement_lesson_variance_claims c
    where c.settlement_id=new.id;
    v_batch:=gen_random_uuid();
    perform set_config('school.p0f_claim_writer','on',true);
    insert into public.school_student_settlement_lesson_variance_claims(
      claim_batch_id,claim_batch_version,settlement_id,student_id,business_entity_id,
      year_month,source_type,source_planned_lesson_id,source_actual_lesson_id,
      source_hours,source_amount_jpy,source_amount_cny,settlement_exchange_rate,
      calculation_version,line_manifest_sha256,claim_status,created_by
    ) select v_batch,v_version,new.id,new.student_id,new.business_entity_id,new.year_month,
      l.source_type,l.source_planned_lesson_id,l.source_actual_lesson_id,l.source_hours,
      l.source_amount_jpy,l.source_amount_cny,new.settlement_exchange_rate,
      'lesson_variance_financial_netting_v1',l.line_manifest_sha256,'active',current_user
    from public.school_tuition_p0f_source_lines(
      new.student_id,new.business_entity_id,new.year_month,new.settlement_exchange_rate,false
    ) l;
    if (select count(*) from public.school_student_settlement_lesson_variance_claims c
        where c.claim_batch_id=v_batch) is distinct from new.lesson_variance_source_count then
      raise exception 'SETTLEMENT_LESSON_VARIANCE_CLAIM_COUNT_MISMATCH';
    end if;
    perform set_config('school.p0f_draft_writer','on',true);
    update public.school_student_settlement_source_treatment_drafts d
    set status='consumed',settlement_id=new.id,consumed_at=now(),updated_at=now(),updated_by=current_user
    where d.student_id=new.student_id and d.business_entity_id=new.business_entity_id
      and d.year_month=new.year_month and d.status='active'
    returning d.id into v_draft;
    if v_draft is null then raise exception 'SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED'; end if;
    perform set_config('school.p0f_draft_writer','off',true);
    perform set_config('school.p0f_claim_writer','off',true);
  elsif new.settlement_status='locked'
        and (tg_op='INSERT' or old.settlement_status is distinct from 'locked') then
    perform set_config('school.p0f_draft_writer','on',true);
    update public.school_student_settlement_source_treatment_drafts d
    set status='consumed',settlement_id=new.id,consumed_at=now(),updated_at=now(),updated_by=current_user
    where d.student_id=new.student_id and d.business_entity_id=new.business_entity_id
      and d.year_month=new.year_month and d.status='active';
    perform set_config('school.p0f_draft_writer','off',true);
  elsif tg_op='UPDATE' and old.settlement_status='locked'
        and new.settlement_status='unlocked' then
    perform set_config('school.p0f_claim_writer','on',true);
    update public.school_student_settlement_lesson_variance_claims c
    set claim_status='released',released_at=now(),
      release_reason=coalesce(nullif(btrim(new.unlock_reason),''),'settlement unlocked'),
      released_by=current_user
    where c.settlement_id=new.id and c.claim_status='active';
    perform set_config('school.p0f_claim_writer','off',true);
  end if;
  return null;
end
$function$;

create trigger school_tuition_p0f_settlement_before
before insert or update on public.school_student_monthly_settlements
for each row execute function public.school_tuition_p0f_settlement_before();
create trigger school_tuition_p0f_settlement_after
after insert or update on public.school_student_monthly_settlements
for each row execute function public.school_tuition_p0f_settlement_after();

create or replace function public.school_tuition_p0f_guard_claimed_lesson_source()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_source public.school_lesson_records%rowtype;
begin
  if tg_op in ('INSERT','UPDATE') and new.lesson_type='actual'
     and new.planned_lesson_id is not null then
    select * into strict v_source from public.school_lesson_records
    where id=new.planned_lesson_id;
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_source.student_id,v_source.business_entity_id,
      public.school_resolve_r1d_e_c_lesson_student_month(v_source.id)
    );
  elsif tg_op in ('UPDATE','DELETE') and old.lesson_type='planned' then
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      old.student_id,old.business_entity_id,
      public.school_resolve_r1d_e_c_lesson_student_month(old.id)
    );
  end if;
  if tg_op='DELETE' and exists(
    select 1 from public.school_student_settlement_lesson_variance_claims c
    where c.claim_status='active'
      and (c.source_planned_lesson_id=old.id or c.source_actual_lesson_id=old.id)
  ) then raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE'; end if;
  if tg_op in ('INSERT','UPDATE') and new.lesson_type='actual'
     and new.planned_lesson_id is not null and exists(
       select 1 from public.school_student_settlement_lesson_variance_claims c
       where c.claim_status='active' and c.source_type='unused_planned_credit_v1'
         and c.source_planned_lesson_id=new.planned_lesson_id
     ) then raise exception 'SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED'; end if;
  if tg_op='UPDATE' and exists(
    select 1 from public.school_student_settlement_lesson_variance_claims c
    where c.claim_status='active'
      and (c.source_planned_lesson_id=old.id or c.source_actual_lesson_id=old.id)
  ) and to_jsonb(new)-array['updated_at'] is distinct from to_jsonb(old)-array['updated_at'] then
    raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

create trigger school_tuition_p0f_claimed_lesson_source_guard
before insert or update or delete on public.school_lesson_records
for each row execute function public.school_tuition_p0f_guard_claimed_lesson_source();

create or replace function public.school_void_planned_lesson_after_tuition_void(
  p_lesson_id uuid,p_expected_updated_at timestamptz,p_void_reason text,p_confirmation text
)
returns table(lesson_id uuid,lesson_type text,status text,voided_at timestamptz,
  void_reason text,updated_at timestamptz)
language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_lesson public.school_lesson_records%rowtype; v_reason text;
begin
  v_reason:=nullif(btrim(coalesce(p_void_reason,'')),'');
  if p_lesson_id is null or p_expected_updated_at is null then
    raise exception 'LESSON_AFTER_TUITION_VOID_EXPECTED_FACTS_REQUIRED';
  end if;
  if v_reason is null then raise exception 'LESSON_AFTER_TUITION_VOID_REASON_REQUIRED'; end if;
  if p_confirmation is distinct from 'CONFIRM VOID PLANNED LESSON AFTER TUITION VOID' then
    raise exception 'LESSON_AFTER_TUITION_VOID_CONFIRMATION_REQUIRED';
  end if;
  select * into v_lesson from public.school_lesson_records l
  where l.id=p_lesson_id and l.app_type='school' for update;
  if not found then raise exception 'LESSON_AFTER_TUITION_VOID_NOT_FOUND'; end if;
  if v_lesson.updated_at is distinct from p_expected_updated_at then
    raise exception 'LESSON_AFTER_TUITION_VOID_STALE';
  end if;
  if v_lesson.lesson_type<>'planned' or v_lesson.status not in ('planned','pending_makeup') then
    raise exception 'LESSON_AFTER_TUITION_VOID_STATE_INVALID';
  end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    v_lesson.student_id,v_lesson.business_entity_id,
    public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)
  );
  if not exists(
    select 1 from public.school_student_tuition_bill_lessons bl
    join public.school_student_tuition_generation_revisions r
      on r.tuition_bill_id=bl.tuition_bill_id
    where bl.planned_lesson_id=v_lesson.id and r.lifecycle_status='voided'
  ) then raise exception 'LESSON_AFTER_TUITION_VOID_HISTORY_REQUIRED'; end if;
  if exists(
    select 1 from public.school_student_tuition_bill_lessons bl
    join public.school_student_tuition_generation_revisions r
      on r.tuition_bill_id=bl.tuition_bill_id
    where bl.planned_lesson_id=v_lesson.id and r.lifecycle_status='active'
  ) then raise exception 'LESSON_ACTIVE_TUITION_REVISION_CLAIM'; end if;
  if v_lesson.voided_at is not null then
    return query select l.id,l.lesson_type,l.status,l.voided_at,l.void_reason,l.updated_at
    from public.school_lesson_records l where l.id=v_lesson.id; return;
  end if;
  if exists(select 1 from public.school_lesson_records a
    where a.app_type='school' and a.lesson_type='actual' and a.planned_lesson_id=v_lesson.id)
    then raise exception 'LESSON_AFTER_TUITION_VOID_ACTUAL_DOWNSTREAM'; end if;
  if exists(select 1 from public.school_teacher_wage_lock_details w
    where w.lesson_record_id=v_lesson.id)
    then raise exception 'LESSON_AFTER_TUITION_VOID_WAGE_DOWNSTREAM'; end if;
  if exists(select 1 from public.school_student_monthly_settlements s
    where s.student_id=v_lesson.student_id
      and s.business_entity_id=v_lesson.business_entity_id
      and s.year_month=public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)
      and s.settlement_status='locked')
    then raise exception 'LESSON_AFTER_TUITION_VOID_SETTLEMENT_DOWNSTREAM'; end if;
  if exists(select 1 from public.school_student_settlement_lesson_variance_claims c
    where c.claim_status='active'
      and (c.source_planned_lesson_id=v_lesson.id or c.source_actual_lesson_id=v_lesson.id))
    then raise exception 'LESSON_AFTER_TUITION_VOID_VARIANCE_CLAIM'; end if;
  if exists(
    select 1 from public.school_student_tuition_bill_lessons bl
    join public.school_student_tuition_bills b on b.id=bl.tuition_bill_id
    left join public.school_income_records i on i.id=b.income_record_id
    where bl.planned_lesson_id=v_lesson.id
      and (b.status<>'cancelled' or coalesce(i.status,'cancelled')<>'cancelled'
        or exists(select 1 from public.school_personal_cash_income_linkage_events e
                  where e.income_record_id=i.id)
        or exists(select 1 from public.school_account_transactions t
                  where (t.related_table='school_income_records' and t.related_id=i.id)
                     or (t.related_table='school_student_tuition_bills' and t.related_id=b.id)))
  ) then raise exception 'LESSON_AFTER_TUITION_VOID_FINANCIAL_DOWNSTREAM'; end if;
  update public.school_lesson_records set voided_at=now(),void_reason=v_reason
  where id=v_lesson.id;
  return query select l.id,l.lesson_type,l.status,l.voided_at,l.void_reason,l.updated_at
  from public.school_lesson_records l where l.id=v_lesson.id;
end
$function$;

revoke all on function public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_assert_sources_resolved(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_guard_draft_dml()
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_guard_claim_dml()
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_settlement_before()
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_settlement_after()
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_guard_claimed_lesson_source()
  from public,anon,authenticated,service_role;

revoke all on function public.school_preview_student_settlement_source_treatment(uuid,text,text,numeric,text,date)
  from public,anon,authenticated,service_role;
grant execute on function public.school_preview_student_settlement_source_treatment(uuid,text,text,numeric,text,date)
  to anon,authenticated,service_role;
revoke all on function public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)
  to authenticated,service_role;
revoke all on function public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)
  to authenticated,service_role;
revoke all on function public.school_get_student_monthly_settlement_summary_p0f_legacy(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_student_monthly_settlement_summary(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_student_monthly_settlement_summary(uuid,text)
  to anon,authenticated,service_role;

comment on function public.school_preview_student_settlement_source_treatment(uuid,text,text,numeric,text,date) is
  'P0-F DB-authoritative source preview. New mode requires an explicit rate and computes every claimable source before aggregating; preview writes no claims.';
comment on function public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text) is
  'P0-F all-student controlled soft-void after a tuition revision was voided. Preserves all revision/bill snapshots and rejects every active or financial downstream.';

\if :p0f_rpc_commit
  commit;
\else
  rollback;
\endif
