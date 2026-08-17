-- School V2 Phase 2C-C-R2 versioned clearance candidate/projection readers.
-- Read-only RPC deployment. No business table, writer, balance or lock semantics change.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_R2_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  perform 'public.school_lesson_clearances'::regclass;
  perform 'public.school_lesson_clearance_details'::regclass;
  perform 'public.school_student_package_credit_lots'::regclass;
  perform 'public.school_assert_lesson_clearance_reader()'::regprocedure;
  perform 'public.school_get_lesson_clearance_pending_remaining_minutes(uuid)'::regprocedure;
  perform 'public.school_get_lesson_clearance_overtime_remaining_minutes(uuid)'::regprocedure;
  perform 'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure;
  perform 'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure;
  if to_regprocedure('public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)') is not null
     or to_regprocedure('public.school_list_student_package_credit_lots_v2(uuid)') is not null
     or to_regprocedure('public.school_list_cross_month_makeup_projection_v2(uuid,text)') is not null
     or to_regprocedure('public.school_get_lesson_clearance_dashboard_summary_v1(uuid)') is not null then
    raise exception 'PHASE2C_C_R2_READER_ALREADY_EXISTS';
  end if;
end
$preflight$;

\if :{?PHASE2C_C_R2_SKIP_PRODUCTION_MD5}
\else
do $dependency_md5$
begin
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances(uuid,boolean)'::regprocedure
    ))<>'59dcc6bdbc72488c5f0f25dfcdd7b7bc'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_available_overages(uuid,boolean)'::regprocedure
    ))<>'c7c1c5c2c9e2e36a2587476b063a192e'
     or md5(pg_get_functiondef(
      'public.school_list_student_package_credit_lots(uuid)'::regprocedure
    ))<>'ed3645856732070335827b4329dfecf0'
     or md5(pg_get_functiondef(
      'public.school_list_cross_month_makeup_projection(uuid,text)'::regprocedure
    ))<>'9008b9e1bf2c42953ce05cb2ae343517'
     or md5(pg_get_functiondef(
      'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure
    ))<>'ffeab2952a86c3c40d39cd3a5c806e19'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure
    ))<>'0f0068b523ca6c1c142b6ae55b41bc4d'
     or md5(pg_get_functiondef(
      'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure
    ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
      'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
    ))<>'07aefc153a1b2f9f2faacbf28f29447f' then
    raise exception 'PHASE2C_C_R2_DEPENDENCY_DEFINITION_DRIFT';
  end if;
end
$dependency_md5$;
\endif

create function public.school_list_lesson_clearance_pending_balances_v2(
  p_student_id uuid default null,
  p_include_active_claimed boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_result jsonb;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  with makeup as (
    select actual_row.planned_lesson_id,
      coalesce(sum(round(coalesce(actual_row.duration_hours,0)*60)::integer)
        filter(where actual_row.lesson_type='actual'
          and actual_row.status in ('completed','makeup_completed')
          and actual_row.voided_at is null),0)::integer makeup_consumed_minutes
    from public.school_lesson_records actual_row
    where actual_row.app_type='school' and actual_row.planned_lesson_id is not null
    group by actual_row.planned_lesson_id
  ), clearance as (
    select detail.pending_source_planned_id,
      coalesce(sum(detail.allocated_minutes)
        filter(where detail.balance_effect='consume'),0)::integer
        clearance_allocated_minutes,
      coalesce(sum(detail.allocated_minutes)
        filter(where detail.balance_effect='restore'),0)::integer
        clearance_reversed_minutes
    from public.school_lesson_clearance_details detail
    group by detail.pending_source_planned_id
  ), claims as (
    select claim.source_planned_lesson_id,
      coalesce(sum(round(abs(claim.source_hours)*60)::integer),0)::integer
        active_claimed_minutes
    from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id is not null
    group by claim.source_planned_lesson_id
  ), causal as (
    select actual_row.planned_lesson_id,min(actual_row.created_at) causal_created_at
    from public.school_lesson_records actual_row
    where actual_row.app_type='school' and actual_row.voided_at is null
      and actual_row.status in ('cancelled','completed')
      and actual_row.planned_lesson_id is not null
    group by actual_row.planned_lesson_id
  ), base as (
    select planned.*,public.school_resolve_r1d_e_c_lesson_student_month(planned.id)
        source_year_month,
      round(coalesce(planned.duration_hours,0)*60)::integer initial_credit_minutes,
      coalesce(makeup.makeup_consumed_minutes,0)::integer makeup_consumed_minutes,
      coalesce(clearance.clearance_allocated_minutes,0)::integer
        clearance_allocated_minutes,
      coalesce(clearance.clearance_reversed_minutes,0)::integer
        clearance_reversed_minutes,
      coalesce(claims.active_claimed_minutes,0)::integer active_claimed_minutes,
      claims.source_planned_lesson_id is not null active_claimed,
      public.school_get_lesson_clearance_pending_remaining_minutes(planned.id)
        helper_remaining_minutes,
      coalesce(planned.unit_price,
        round(planned.lesson_fee/nullif(planned.duration_hours,0),6),0) unit_price_jpy,
      coalesce(causal.causal_created_at,planned.updated_at,planned.created_at)
        credit_origin_sort_at,
      case when causal.causal_created_at is not null then 'causal_actual_created_at'
        when planned.updated_at is not null then 'planned_updated_at_fallback'
        else 'planned_created_at_fallback' end credit_origin_sort_source,
      exists(select 1 from public.school_student_monthly_settlements settlement
        where settlement.student_id=planned.student_id
          and settlement.business_entity_id=planned.business_entity_id
          and settlement.year_month=
            public.school_resolve_r1d_e_c_lesson_student_month(planned.id)
          and settlement.settlement_status='locked') is_locked,
      coalesce(nullif(btrim(student.display_name),''),nullif(btrim(student.name),''))
        student_display_name,
      student.status student_status,
      nullif(btrim(entity.name),'') business_entity_display_name,
      coalesce(nullif(btrim(teacher.display_name),''),nullif(btrim(teacher.name),''))
        teacher_display_name,
      nullif(btrim(subject.name),'') subject_display_name,
      student.id is not null student_master_exists,
      entity.id is not null entity_master_exists,
      teacher.id is not null teacher_master_exists,
      subject.id is not null subject_master_exists,
      md5(to_jsonb(planned)::text) source_row_md5
    from public.school_lesson_records planned
    left join makeup on makeup.planned_lesson_id=planned.id
    left join clearance on clearance.pending_source_planned_id=planned.id
    left join claims on claims.source_planned_lesson_id=planned.id
    left join causal on causal.planned_lesson_id=planned.id
    left join public.school_students student on student.id=planned.student_id
    left join public.school_business_entities entity
      on entity.id=planned.business_entity_id
    left join public.school_teachers teacher on teacher.id=planned.teacher_id
    left join public.school_subjects subject on subject.id=planned.subject_id
    where planned.app_type='school' and planned.lesson_type='planned'
      and planned.status='pending_makeup' and planned.voided_at is null
      and (p_student_id is null or planned.student_id=p_student_id)
      and not public.school_is_active_package_credit_origin(planned.id)
  ), fifo as (
    select base.id,
      row_number() over(partition by base.student_id,base.business_entity_id
        order by base.credit_origin_sort_at,base.id) fifo_rank
    from base
    where not base.active_claimed and coalesce(base.helper_remaining_minutes,0)>0
  ), ranked as (
    select base.*,fifo.fifo_rank,
      base.initial_credit_minutes-base.makeup_consumed_minutes
        -base.clearance_allocated_minutes+base.clearance_reversed_minutes
        decomposition_remaining_minutes
    from base
    left join fifo on fifo.id=base.id
  ), candidates as (
    select ranked.*,
      greatest(coalesce(ranked.helper_remaining_minutes,0),0)::integer remaining_minutes,
      case when ranked.active_claimed then 0
        else greatest(coalesce(ranked.helper_remaining_minutes,0),0)::integer end
        currently_allocatable_minutes,
      coalesce(ranked.helper_remaining_minutes,0)
        =ranked.decomposition_remaining_minutes balance_matches_writer_helper
    from ranked
    where coalesce(ranked.helper_remaining_minutes,0)>0
      and (p_include_active_claimed or not ranked.active_claimed)
  ), item_payloads as (
    select candidate.student_id,candidate.business_entity_id,
      candidate.credit_origin_sort_at,candidate.id,
      jsonb_build_object(
        'pending_source_planned_id',candidate.id,
        'student_id',candidate.student_id,
        'student_display_name',candidate.student_display_name,
        'student_name_evidence_status',case when candidate.student_master_exists
          and candidate.student_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'student_status',candidate.student_status,
        'business_entity_id',candidate.business_entity_id,
        'business_entity_display_name',candidate.business_entity_display_name,
        'business_entity_name_evidence_status',case when candidate.entity_master_exists
          and candidate.business_entity_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'teacher_id',candidate.teacher_id,
        'teacher_display_name',candidate.teacher_display_name,
        'teacher_name_evidence_status',case when candidate.teacher_master_exists
          and candidate.teacher_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'subject_id',candidate.subject_id,
        'subject_display_name',candidate.subject_display_name,
        'subject_name_evidence_status',case when candidate.subject_master_exists
          and candidate.subject_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'source_lesson_date',candidate.lesson_date,
        'source_start_time',candidate.start_time,'source_end_time',candidate.end_time,
        'source_year_month',candidate.source_year_month,
        'source_status',candidate.status,
        'source_origin_type','planned_pending_makeup',
        'initial_credit_minutes',candidate.initial_credit_minutes,
        'makeup_consumed_minutes',candidate.makeup_consumed_minutes,
        'clearance_allocated_minutes',candidate.clearance_allocated_minutes,
        'clearance_reversed_minutes',candidate.clearance_reversed_minutes,
        'active_claimed_minutes',candidate.active_claimed_minutes,
        'remaining_minutes',candidate.remaining_minutes,
        'currently_allocatable_minutes',candidate.currently_allocatable_minutes,
        'unit_price_jpy',candidate.unit_price_jpy,
        'initial_amount_jpy',round(candidate.unit_price_jpy
          *candidate.initial_credit_minutes/60.0,2),
        'remaining_amount_jpy',round(candidate.unit_price_jpy
          *candidate.remaining_minutes/60.0,2),
        'active_claimed',candidate.active_claimed,
        'is_locked',candidate.is_locked,
        'lock_reason_code',case when candidate.is_locked
          then 'PHYSICAL_STUDENT_SETTLEMENT_LOCKED' else null end,
        'requires_admin',candidate.is_locked,
        'requires_preview_for_forward',candidate.is_locked,
        'package_classification','ordinary_makeup_credit',
        'can_be_candidate',candidate.balance_matches_writer_helper
          and candidate.student_status='active' and not candidate.active_claimed
          and candidate.remaining_minutes>0 and v_actor.actor_role<>'read_only'
          and (not candidate.is_locked or v_actor.actor_role='admin'),
        'candidate_blocker_code',case
          when not candidate.balance_matches_writer_helper
            then 'LESSON_CLEARANCE_BALANCE_DECOMPOSITION_MISMATCH'
          when candidate.student_status is distinct from 'active'
            then 'LESSON_CLEARANCE_STUDENT_NOT_ACTIVE'
          when candidate.active_claimed
            then 'LESSON_CLEARANCE_PENDING_SOURCE_ALREADY_CLAIMED'
          when candidate.remaining_minutes<=0
            then 'LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT'
          when v_actor.actor_role='read_only' then 'LESSON_CLEARANCE_ROLE_REQUIRED'
          when candidate.is_locked and v_actor.actor_role<>'admin'
            then 'LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED'
          else null end,
        'evidence_status','current_derived',
        'source_updated_at',candidate.updated_at,
        'source_row_md5',candidate.source_row_md5,
        'credit_origin_sort_at',candidate.credit_origin_sort_at,
        'credit_origin_sort_source',candidate.credit_origin_sort_source,
        'fifo_rank',candidate.fifo_rank,
        'balance_matches_writer_helper',candidate.balance_matches_writer_helper
      ) payload
    from candidates candidate
  )
  select jsonb_build_object(
    'contract_version','lesson_clearance_pending_balances_v2',
    'actor_role',v_actor.actor_role,
    'sort_contract','student_business_scope_then_credit_origin_sort_at_then_uuid_v1',
    'items',coalesce((select jsonb_agg(item.payload order by item.student_id,
      item.business_entity_id,item.credit_origin_sort_at,item.id)
      from item_payloads item),'[]'::jsonb),
    'summary',(select jsonb_build_object(
      'source_count',count(*),
      'initial_credit_minutes',coalesce(sum(candidate.initial_credit_minutes),0),
      'makeup_consumed_minutes',coalesce(sum(candidate.makeup_consumed_minutes),0),
      'clearance_allocated_minutes',coalesce(sum(candidate.clearance_allocated_minutes),0),
      'clearance_reversed_minutes',coalesce(sum(candidate.clearance_reversed_minutes),0),
      'active_claimed_minutes',coalesce(sum(candidate.active_claimed_minutes),0),
      'remaining_minutes',coalesce(sum(candidate.remaining_minutes),0),
      'currently_allocatable_minutes',coalesce(sum(candidate.currently_allocatable_minutes),0)
    ) from candidates candidate)
  ) into v_result;
  return v_result;
end
$function$;

create function public.school_list_lesson_clearance_available_overages_v2(
  p_student_id uuid default null,
  p_include_active_claimed boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_result jsonb;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  with clearance as (
    select detail.overtime_source_actual_id,
      coalesce(sum(detail.allocated_minutes)
        filter(where detail.balance_effect='consume'),0)::integer
        clearance_allocated_minutes,
      coalesce(sum(detail.allocated_minutes)
        filter(where detail.balance_effect='restore'),0)::integer
        clearance_reversed_minutes
    from public.school_lesson_clearance_details detail
    where detail.overtime_source_actual_id is not null
    group by detail.overtime_source_actual_id
  ), claims as (
    select claim.source_actual_lesson_id,
      coalesce(sum(round(abs(claim.source_hours)*60)::integer),0)::integer
        active_claimed_minutes
    from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='actual_duration_overage_charge_v1'
      and claim.source_actual_lesson_id is not null
    group by claim.source_actual_lesson_id
  ), base as (
    select actual_row.*,
      coalesce(clearance.clearance_allocated_minutes,0)::integer
        clearance_allocated_minutes,
      coalesce(clearance.clearance_reversed_minutes,0)::integer
        clearance_reversed_minutes,
      coalesce(claims.active_claimed_minutes,0)::integer active_claimed_minutes,
      claims.source_actual_lesson_id is not null active_claimed,
      public.school_get_lesson_clearance_overtime_remaining_minutes(actual_row.id)
        helper_available_minutes,
      round(actual_row.student_duration_overage_fee_jpy*60
        /nullif(actual_row.student_duration_overage_minutes,0),6) unit_price_jpy,
      exists(select 1 from public.school_student_monthly_settlements settlement
        where settlement.student_id=actual_row.student_id
          and settlement.business_entity_id=actual_row.business_entity_id
          and settlement.year_month=actual_row.student_settlement_month
          and settlement.settlement_status='locked') is_locked,
      coalesce(nullif(btrim(student.display_name),''),nullif(btrim(student.name),''))
        student_display_name,
      student.status student_status,
      nullif(btrim(entity.name),'') business_entity_display_name,
      coalesce(nullif(btrim(teacher.display_name),''),nullif(btrim(teacher.name),''))
        teacher_display_name,
      nullif(btrim(subject.name),'') subject_display_name,
      student.id is not null student_master_exists,
      entity.id is not null entity_master_exists,
      teacher.id is not null teacher_master_exists,
      subject.id is not null subject_master_exists,
      coalesce(actual_row.created_at,actual_row.updated_at) overtime_sort_at,
      md5(to_jsonb(actual_row)::text) source_row_md5
    from public.school_lesson_records actual_row
    left join clearance on clearance.overtime_source_actual_id=actual_row.id
    left join claims on claims.source_actual_lesson_id=actual_row.id
    left join public.school_students student on student.id=actual_row.student_id
    left join public.school_business_entities entity
      on entity.id=actual_row.business_entity_id
    left join public.school_teachers teacher on teacher.id=actual_row.teacher_id
    left join public.school_subjects subject on subject.id=actual_row.subject_id
    where actual_row.app_type='school' and actual_row.lesson_type='actual'
      and actual_row.status='completed' and actual_row.is_billable is true
      and actual_row.voided_at is null
      and actual_row.student_duration_overage_policy_version='student_duration_overage_v1'
      and actual_row.student_duration_overage_source='ordinary_actual_rpc'
      and actual_row.student_duration_overage_minutes>0
      and actual_row.student_duration_overage_fee_jpy>0
      and (p_student_id is null or actual_row.student_id=p_student_id)
  ), ranked as (
    select base.*,
      row_number() over(order by base.student_settlement_month,base.lesson_date,
        base.overtime_sort_at,base.id) display_rank,
      base.student_duration_overage_minutes-base.clearance_allocated_minutes
        +base.clearance_reversed_minutes decomposition_available_minutes
    from base
  ), candidates as (
    select ranked.*,
      greatest(coalesce(ranked.helper_available_minutes,0),0)::integer available_minutes,
      case when ranked.active_claimed then 0
        else greatest(coalesce(ranked.helper_available_minutes,0),0)::integer end
        currently_allocatable_minutes,
      coalesce(ranked.helper_available_minutes,0)
        =ranked.decomposition_available_minutes balance_matches_writer_helper
    from ranked
    where coalesce(ranked.helper_available_minutes,0)>0
      and (p_include_active_claimed or not ranked.active_claimed)
  ), item_payloads as (
    select candidate.student_settlement_month,candidate.lesson_date,
      candidate.overtime_sort_at,candidate.id,
      jsonb_build_object(
        'overtime_source_actual_id',candidate.id,
        'linked_planned_lesson_id',candidate.planned_lesson_id,
        'student_id',candidate.student_id,
        'student_display_name',candidate.student_display_name,
        'student_name_evidence_status',case when candidate.student_master_exists
          and candidate.student_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'student_status',candidate.student_status,
        'business_entity_id',candidate.business_entity_id,
        'business_entity_display_name',candidate.business_entity_display_name,
        'business_entity_name_evidence_status',case when candidate.entity_master_exists
          and candidate.business_entity_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'teacher_id',candidate.teacher_id,
        'teacher_display_name',candidate.teacher_display_name,
        'teacher_name_evidence_status',case when candidate.teacher_master_exists
          and candidate.teacher_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'subject_id',candidate.subject_id,
        'subject_display_name',candidate.subject_display_name,
        'subject_name_evidence_status',case when candidate.subject_master_exists
          and candidate.subject_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'actual_lesson_date',candidate.lesson_date,
        'actual_start_time',candidate.start_time,'actual_end_time',candidate.end_time,
        'student_settlement_month',candidate.student_settlement_month,
        'teacher_wage_month',candidate.teacher_settlement_month,
        'overage_policy_version',candidate.student_duration_overage_policy_version,
        'overage_source',candidate.student_duration_overage_source,
        'frozen_overtime_minutes',candidate.student_duration_overage_minutes,
        'active_claimed_minutes',candidate.active_claimed_minutes,
        'clearance_allocated_minutes',candidate.clearance_allocated_minutes,
        'clearance_reversed_minutes',candidate.clearance_reversed_minutes,
        'available_minutes',candidate.available_minutes,
        'currently_allocatable_minutes',candidate.currently_allocatable_minutes,
        'unit_price_jpy',candidate.unit_price_jpy,
        'frozen_amount_jpy',candidate.student_duration_overage_fee_jpy,
        'available_amount_jpy',round(candidate.unit_price_jpy
          *candidate.available_minutes/60.0,2),
        'active_claimed',candidate.active_claimed,
        'is_locked',candidate.is_locked,
        'lock_reason_code',case when candidate.is_locked
          then 'PHYSICAL_STUDENT_SETTLEMENT_LOCKED' else null end,
        'requires_admin',candidate.is_locked,
        'requires_preview_for_forward',candidate.is_locked,
        'can_be_candidate',candidate.balance_matches_writer_helper
          and candidate.student_status='active' and not candidate.active_claimed
          and candidate.available_minutes>0 and v_actor.actor_role<>'read_only'
          and (not candidate.is_locked or v_actor.actor_role='admin'),
        'candidate_blocker_code',case
          when not candidate.balance_matches_writer_helper
            then 'LESSON_CLEARANCE_BALANCE_DECOMPOSITION_MISMATCH'
          when candidate.student_status is distinct from 'active'
            then 'LESSON_CLEARANCE_STUDENT_NOT_ACTIVE'
          when candidate.active_claimed
            then 'LESSON_CLEARANCE_OVERTIME_SOURCE_ALREADY_CLAIMED'
          when candidate.available_minutes<=0
            then 'LESSON_CLEARANCE_OVERTIME_BALANCE_INSUFFICIENT'
          when v_actor.actor_role='read_only' then 'LESSON_CLEARANCE_ROLE_REQUIRED'
          when candidate.is_locked and v_actor.actor_role<>'admin'
            then 'LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED'
          else null end,
        'evidence_status','current_derived',
        'source_updated_at',candidate.updated_at,
        'source_row_md5',candidate.source_row_md5,
        'overtime_sort_at',candidate.overtime_sort_at,
        'overtime_sort_source','actual_created_at',
        'display_rank',candidate.display_rank,
        'balance_matches_writer_helper',candidate.balance_matches_writer_helper
      ) payload
    from candidates candidate
  )
  select jsonb_build_object(
    'contract_version','lesson_clearance_available_overages_v2',
    'actor_role',v_actor.actor_role,
    'sort_contract','student_settlement_month_then_actual_date_then_created_at_then_uuid_v1',
    'items',coalesce((select jsonb_agg(item.payload order by
      item.student_settlement_month,item.lesson_date,item.overtime_sort_at,item.id)
      from item_payloads item),'[]'::jsonb),
    'summary',(select jsonb_build_object(
      'source_count',count(*),
      'frozen_overtime_minutes',coalesce(sum(candidate.student_duration_overage_minutes),0),
      'clearance_allocated_minutes',coalesce(sum(candidate.clearance_allocated_minutes),0),
      'clearance_reversed_minutes',coalesce(sum(candidate.clearance_reversed_minutes),0),
      'active_claimed_minutes',coalesce(sum(candidate.active_claimed_minutes),0),
      'available_minutes',coalesce(sum(candidate.available_minutes),0),
      'currently_allocatable_minutes',coalesce(sum(candidate.currently_allocatable_minutes),0)
    ) from candidates candidate)
  ) into v_result;
  return v_result;
end
$function$;

create function public.school_list_student_package_credit_lots_v2(
  p_student_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_result jsonb;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  with lots as (
    select lot.*,
      coalesce(nullif(btrim(student.display_name),''),nullif(btrim(student.name),''))
        student_display_name,
      nullif(btrim(entity.name),'') business_entity_display_name,
      student.id is not null student_master_exists,
      entity.id is not null entity_master_exists,
      origin.updated_at origin_updated_at
    from public.school_student_package_credit_lots lot
    left join public.school_students student on student.id=lot.student_id
    left join public.school_business_entities entity on entity.id=lot.business_entity_id
    left join public.school_lesson_records origin on origin.id=lot.origin_planned_lesson_id
    where lot.status='active' and (p_student_id is null or lot.student_id=p_student_id)
  ), item_payloads as (
    select lot.created_at,lot.id,jsonb_build_object(
      'package_lot_id',lot.id,
      'origin_planned_lesson_id',lot.origin_planned_lesson_id,
      'student_id',lot.student_id,
      'student_display_name',lot.student_display_name,
      'student_name_evidence_status',case when lot.student_master_exists
        and lot.student_display_name is not null then 'current_reference'
        else 'unavailable' end,
      'business_entity_id',lot.business_entity_id,
      'business_entity_display_name',lot.business_entity_display_name,
      'business_entity_name_evidence_status',case when lot.entity_master_exists
        and lot.business_entity_display_name is not null then 'current_reference'
        else 'unavailable' end,
      'package_business_type','package_credit',
      'package_display_label','套餐余额',
      'classification_reason',lot.classification_reason,
      'initial_minutes',lot.initial_minutes,'consumed_minutes',lot.consumed_minutes,
      'remaining_minutes',lot.remaining_minutes,'unit_price_jpy',lot.unit_price_jpy,
      'total_amount_jpy',lot.total_price_jpy,
      'student_settlement_month',lot.student_billing_month,
      'status',lot.status,'can_consume',false,'can_reserve',false,'read_only',true,
      'evidence_status','immutable_reference',
      'origin_updated_at',lot.origin_updated_at,
      'origin_row_md5',lot.origin_lesson_row_md5,
      'lot_created_at',lot.created_at
    ) payload from lots lot
  )
  select jsonb_build_object(
    'contract_version','student_package_credit_lots_v2',
    'actor_role',v_actor.actor_role,
    'items',coalesce((select jsonb_agg(item.payload order by item.created_at,item.id)
      from item_payloads item),'[]'::jsonb),
    'summary',(select jsonb_build_object(
      'lot_count',count(*),'initial_minutes',coalesce(sum(lot.initial_minutes),0),
      'consumed_minutes',coalesce(sum(lot.consumed_minutes),0),
      'remaining_minutes',coalesce(sum(lot.remaining_minutes),0)
    ) from lots lot)
  ) into v_result;
  return v_result;
end
$function$;

create function public.school_list_cross_month_makeup_projection_v2(
  p_student_id uuid default null,
  p_year_month text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_result jsonb;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  if p_year_month is not null
     and p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'LESSON_CLEARANCE_YEAR_MONTH_INVALID';
  end if;
  with facts as (
    select actual_row.id actual_lesson_id,planned.id source_planned_lesson_id,
      actual_row.student_id,actual_row.business_entity_id,
      public.school_resolve_r1d_e_c_lesson_student_month(planned.id) source_month,
      to_char(actual_row.lesson_date,'YYYY-MM') actual_month,
      planned.lesson_date source_lesson_date,actual_row.lesson_date actual_lesson_date,
      actual_row.start_time actual_start_time,actual_row.end_time actual_end_time,
      actual_row.actual_minutes,
      planned.teacher_id source_teacher_id,actual_row.teacher_id actual_teacher_id,
      planned.subject_id source_subject_id,actual_row.subject_id actual_subject_id,
      actual_row.student_settlement_month,
      actual_row.teacher_settlement_month teacher_wage_month,
      actual_row.status,planned.updated_at source_updated_at,
      actual_row.updated_at actual_updated_at,
      md5(to_jsonb(planned)::text) source_row_md5,
      md5(to_jsonb(actual_row)::text) actual_row_md5,
      coalesce(nullif(btrim(student.display_name),''),nullif(btrim(student.name),''))
        student_display_name,
      nullif(btrim(entity.name),'') business_entity_display_name,
      coalesce(nullif(btrim(source_teacher.display_name),''),
        nullif(btrim(source_teacher.name),'')) source_teacher_display_name,
      coalesce(nullif(btrim(actual_teacher.display_name),''),
        nullif(btrim(actual_teacher.name),'')) actual_teacher_display_name,
      nullif(btrim(source_subject.name),'') source_subject_display_name,
      nullif(btrim(actual_subject.name),'') actual_subject_display_name,
      student.id is not null student_master_exists,
      entity.id is not null entity_master_exists,
      source_teacher.id is not null source_teacher_master_exists,
      actual_teacher.id is not null actual_teacher_master_exists,
      source_subject.id is not null source_subject_master_exists,
      actual_subject.id is not null actual_subject_master_exists
    from public.school_lesson_records actual_row
    join public.school_lesson_records planned on planned.id=actual_row.planned_lesson_id
    left join public.school_students student on student.id=actual_row.student_id
    left join public.school_business_entities entity
      on entity.id=actual_row.business_entity_id
    left join public.school_teachers source_teacher on source_teacher.id=planned.teacher_id
    left join public.school_teachers actual_teacher on actual_teacher.id=actual_row.teacher_id
    left join public.school_subjects source_subject on source_subject.id=planned.subject_id
    left join public.school_subjects actual_subject on actual_subject.id=actual_row.subject_id
    where actual_row.app_type='school' and actual_row.lesson_type='actual'
      and actual_row.status='makeup_completed' and actual_row.voided_at is null
      and planned.app_type='school' and planned.lesson_type='planned'
      and not public.school_is_active_package_credit_origin(planned.id)
      and (p_student_id is null or actual_row.student_id=p_student_id)
  ), cross_month as (
    select fact.* from facts fact
    where fact.source_month<>fact.actual_month
      and (p_year_month is null
        or p_year_month in (fact.source_month,fact.actual_month))
  ), item_payloads as (
    select item.source_month,item.actual_month,item.actual_lesson_date,
      item.actual_lesson_id,jsonb_build_object(
        'actual_lesson_id',item.actual_lesson_id,
        'source_planned_lesson_id',item.source_planned_lesson_id,
        'student_id',item.student_id,'student_display_name',item.student_display_name,
        'student_name_evidence_status',case when item.student_master_exists
          and item.student_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'business_entity_id',item.business_entity_id,
        'business_entity_display_name',item.business_entity_display_name,
        'business_entity_name_evidence_status',case when item.entity_master_exists
          and item.business_entity_display_name is not null then 'current_reference'
          else 'unavailable' end,
        'source_month',item.source_month,'actual_month',item.actual_month,
        'source_lesson_date',item.source_lesson_date,
        'actual_lesson_date',item.actual_lesson_date,
        'actual_start_time',item.actual_start_time,'actual_end_time',item.actual_end_time,
        'actual_minutes',item.actual_minutes,
        'source_teacher_id',item.source_teacher_id,
        'source_teacher_display_name',item.source_teacher_display_name,
        'source_teacher_name_evidence_status',case
          when item.source_teacher_master_exists and item.source_teacher_display_name is not null
          then 'current_reference' else 'unavailable' end,
        'actual_teacher_id',item.actual_teacher_id,
        'actual_teacher_display_name',item.actual_teacher_display_name,
        'actual_teacher_name_evidence_status',case
          when item.actual_teacher_master_exists and item.actual_teacher_display_name is not null
          then 'current_reference' else 'unavailable' end,
        'source_subject_id',item.source_subject_id,
        'source_subject_display_name',item.source_subject_display_name,
        'source_subject_name_evidence_status',case
          when item.source_subject_master_exists and item.source_subject_display_name is not null
          then 'current_reference' else 'unavailable' end,
        'actual_subject_id',item.actual_subject_id,
        'actual_subject_display_name',item.actual_subject_display_name,
        'actual_subject_name_evidence_status',case
          when item.actual_subject_master_exists and item.actual_subject_display_name is not null
          then 'current_reference' else 'unavailable' end,
        'student_settlement_month',item.student_settlement_month,
        'teacher_wage_month',item.teacher_wage_month,'status',item.status,
        'source_view_year_month',item.source_month,
        'source_view_lesson_id',item.source_planned_lesson_id,
        'actual_view_year_month',item.actual_month,
        'actual_view_lesson_id',item.actual_lesson_id,
        'view_mode','pair','evidence_status','current_derived',
        'source_updated_at',item.source_updated_at,'source_row_md5',item.source_row_md5,
        'actual_updated_at',item.actual_updated_at,'actual_row_md5',item.actual_row_md5
      ) payload
    from cross_month item
  )
  select jsonb_build_object(
    'contract_version','cross_month_makeup_projection_v2',
    'actor_role',v_actor.actor_role,
    'identity_contract','one_actual_uuid_one_item_visible_from_source_and_actual_month_v1',
    'items',coalesce((select jsonb_agg(item.payload order by item.source_month,
      item.actual_month,item.actual_lesson_date,item.actual_lesson_id)
      from item_payloads item),'[]'::jsonb),
    'summary',(select jsonb_build_object(
      'distinct_actual_count',count(distinct item.actual_lesson_id),
      'source_month_reference_count',count(*) filter(
        where p_year_month is null or item.source_month=p_year_month),
      'actual_month_fact_count',count(*) filter(
        where p_year_month is null or item.actual_month=p_year_month)
    ) from cross_month item)
  ) into v_result;
  return v_result;
end
$function$;

create function public.school_get_lesson_clearance_dashboard_summary_v1(
  p_student_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_pending jsonb;
  v_overtime jsonb;
  v_package jsonb;
  v_history_count bigint;
begin
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  v_pending:=public.school_list_lesson_clearance_pending_balances_v2(
    p_student_id,false
  )->'summary';
  v_overtime:=public.school_list_lesson_clearance_available_overages_v2(
    p_student_id,false
  )->'summary';
  v_package:=public.school_list_student_package_credit_lots_v2(p_student_id)->'summary';
  select count(*) into v_history_count
  from public.school_lesson_clearances header
  where p_student_id is null or header.student_id=p_student_id;
  return jsonb_build_object(
    'contract_version','lesson_clearance_dashboard_summary_v1',
    'actor_role',v_actor.actor_role,
    'pending_source_count',(v_pending->>'source_count')::bigint,
    'pending_initial_minutes',(v_pending->>'initial_credit_minutes')::bigint,
    'pending_makeup_consumed_minutes',(v_pending->>'makeup_consumed_minutes')::bigint,
    'pending_clearance_allocated_minutes',(v_pending->>'clearance_allocated_minutes')::bigint,
    'pending_clearance_reversed_minutes',(v_pending->>'clearance_reversed_minutes')::bigint,
    'pending_remaining_minutes',(v_pending->>'remaining_minutes')::bigint,
    'pending_currently_allocatable_minutes',
      (v_pending->>'currently_allocatable_minutes')::bigint,
    'overage_source_count',(v_overtime->>'source_count')::bigint,
    'frozen_overtime_minutes',(v_overtime->>'frozen_overtime_minutes')::bigint,
    'overage_clearance_allocated_minutes',
      (v_overtime->>'clearance_allocated_minutes')::bigint,
    'overage_clearance_reversed_minutes',
      (v_overtime->>'clearance_reversed_minutes')::bigint,
    'available_overtime_minutes',(v_overtime->>'available_minutes')::bigint,
    'overage_currently_allocatable_minutes',
      (v_overtime->>'currently_allocatable_minutes')::bigint,
    'package_lot_count',(v_package->>'lot_count')::bigint,
    'package_remaining_minutes',(v_package->>'remaining_minutes')::bigint,
    'history_count',v_history_count,
    'evidence_status','current_derived'
  );
end
$function$;

alter function public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)
  owner to postgres;
alter function public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)
  owner to postgres;
alter function public.school_list_student_package_credit_lots_v2(uuid)
  owner to postgres;
alter function public.school_list_cross_month_makeup_projection_v2(uuid,text)
  owner to postgres;
alter function public.school_get_lesson_clearance_dashboard_summary_v1(uuid)
  owner to postgres;

revoke all on function public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_package_credit_lots_v2(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_cross_month_makeup_projection_v2(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_clearance_dashboard_summary_v1(uuid)
  from public,anon,authenticated,service_role;

grant execute on function public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)
  to authenticated;
grant execute on function public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)
  to authenticated;
grant execute on function public.school_list_student_package_credit_lots_v2(uuid)
  to authenticated;
grant execute on function public.school_list_cross_month_makeup_projection_v2(uuid,text)
  to authenticated;
grant execute on function public.school_get_lesson_clearance_dashboard_summary_v1(uuid)
  to authenticated;

comment on function public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean) is
  'Phase 2C-C-R2 read-only pending candidate contract. DB returns display identity, gross balance decomposition, helper-matched remaining, physical lock, claim, FIFO rank and evidence.';
comment on function public.school_list_lesson_clearance_available_overages_v2(uuid,boolean) is
  'Phase 2C-C-R2 read-only overage candidate contract. DB returns display identity, frozen/gross allocation decomposition, helper-matched availability, physical lock, claim and evidence.';
comment on function public.school_list_student_package_credit_lots_v2(uuid) is
  'Phase 2C-C-R2 immutable package-credit display contract. It explicitly reports package_credit/read-only and exposes no consume or reserve capability.';
comment on function public.school_list_cross_month_makeup_projection_v2(uuid,text) is
  'Phase 2C-C-R2 cross-month makeup display contract. One item per actual UUID carries source/actual identities, months, display references and fingerprints.';
comment on function public.school_get_lesson_clearance_dashboard_summary_v1(uuid) is
  'Phase 2C-C-R2 read-only dashboard totals sourced from versioned candidate readers and clearance history count.';

do $verify$
declare
  v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure,
    'public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)'::regprocedure,
    'public.school_list_student_package_credit_lots_v2(uuid)'::regprocedure,
    'public.school_list_cross_month_makeup_projection_v2(uuid,text)'::regprocedure,
    'public.school_get_lesson_clearance_dashboard_summary_v1(uuid)'::regprocedure
  ] loop
    if exists(select 1 from pg_proc function_row where function_row.oid=v_signature
      and (pg_get_userbyid(function_row.proowner)<>'postgres'
        or not function_row.prosecdef
        or function_row.provolatile<>'s'
        or function_row.proconfig is distinct from array['search_path=pg_catalog, public'])) then
      raise exception 'PHASE2C_C_R2_FUNCTION_SECURITY_INVALID:%',v_signature;
    end if;
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_R2_FUNCTION_ACL_INVALID:%',v_signature;
    end if;
  end loop;
end
$verify$;

\if :{?PHASE2C_C_R2_SKIP_PRODUCTION_MD5}
\else
do $writer_md5$
begin
  if md5(pg_get_functiondef(
      'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure
    ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
      'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
    ))<>'07aefc153a1b2f9f2faacbf28f29447f' then
    raise exception 'PHASE2C_C_R2_WRITER_CHANGED';
  end if;
end
$writer_md5$;
\endif

\if :{?PHASE2C_C_R2_REHEARSAL}
\else
commit;
\endif
