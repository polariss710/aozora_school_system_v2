-- School V2 Phase 2C-C-R1 versioned clearance read contracts.
-- Read-only RPCs only: no table/schema fact change and no writer semantic change.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_R1_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  perform 'public.school_lesson_clearances'::regclass;
  perform 'public.school_lesson_clearance_details'::regclass;
  perform 'public.school_students'::regclass;
  perform 'public.school_business_entities'::regclass;
  perform 'public.school_teachers'::regclass;
  perform 'public.school_subjects'::regclass;
  perform 'public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure;
  perform 'public.school_list_lesson_clearance_history(uuid)'::regprocedure;
  perform 'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure;
  if to_regprocedure('public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)') is not null
     or to_regprocedure('public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_history_v2(uuid)') is not null then
    raise exception 'PHASE2C_C_R1_READ_CONTRACT_ALREADY_EXISTS';
  end if;
end
$preflight$;

create function public.school_preview_lesson_clearance_v2(
  p_request_identity uuid,
  p_clearance_type text,
  p_pending_source_planned_id uuid,
  p_overtime_source_actual_id uuid,
  p_allocated_minutes integer,
  p_operation_date date,
  p_deviation_reason_code text default null,
  p_deviation_reason_note text default null,
  p_business_note text default null,
  p_administrative_financial_treatment text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_base jsonb;
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
  v_student_name text;
  v_entity_name text;
  v_pending_teacher_name text;
  v_pending_subject_name text;
  v_overtime_teacher_name text;
  v_overtime_subject_name text;
  v_pending_initial integer;
  v_pending_makeup_consumed integer;
  v_pending_clearance_allocated integer;
  v_overtime_frozen integer;
  v_overtime_clearance_allocated integer;
  v_pending_claimed boolean;
  v_overtime_claimed boolean:=false;
  v_pending_month text;
  v_overtime_month text;
  v_pending_locked boolean;
  v_overtime_locked boolean:=false;
  v_pending_lock_evidence jsonb:='[]'::jsonb;
  v_overtime_lock_evidence jsonb:='[]'::jsonb;
  v_recommended uuid;
  v_recommendation_rank bigint;
  v_recommendation_timestamp timestamptz;
  v_recommendation_timestamp_source text;
  v_is_recommended boolean;
  v_deviation_required boolean;
  v_deviation_reason_valid boolean;
  v_same_teacher boolean;
  v_same_subject boolean;
  v_requires_admin boolean;
  v_can_execute boolean;
  v_blocker_code text;
  v_blocker_message text;
  v_pending_md5 text;
  v_overtime_md5 text;
  v_preview_generated_at timestamptz:=transaction_timestamp();
  v_preview_manifest_sha256 text;
begin
  if p_request_identity is null then
    raise exception 'LESSON_CLEARANCE_REQUEST_IDENTITY_INVALID';
  end if;
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();

  -- Reuse the deployed Preview for all authoritative source, balance, scope,
  -- price, claim, lock/forward and amount checks. This function only enriches it.
  v_base:=public.school_preview_lesson_clearance(
    p_clearance_type,p_pending_source_planned_id,p_overtime_source_actual_id,
    p_allocated_minutes,p_operation_date,p_administrative_financial_treatment
  );

  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=p_pending_source_planned_id;
  if p_clearance_type='overtime_offset' then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=p_overtime_source_actual_id;
  end if;

  select coalesce(student.display_name,student.name),entity.name
    into v_student_name,v_entity_name
  from public.school_students student
  join public.school_business_entities entity on entity.id=v_pending.business_entity_id
  where student.id=v_pending.student_id;
  select coalesce(teacher.display_name,teacher.name) into v_pending_teacher_name
  from public.school_teachers teacher where teacher.id=v_pending.teacher_id;
  select subject.name into v_pending_subject_name
  from public.school_subjects subject where subject.id=v_pending.subject_id;
  if p_clearance_type='overtime_offset' then
    select coalesce(teacher.display_name,teacher.name) into v_overtime_teacher_name
    from public.school_teachers teacher where teacher.id=v_overtime.teacher_id;
    select subject.name into v_overtime_subject_name
    from public.school_subjects subject where subject.id=v_overtime.subject_id;
  end if;

  v_pending_initial:=round(coalesce(v_pending.duration_hours,0)*60)::integer;
  select coalesce(sum(round(coalesce(actual_row.duration_hours,0)*60)::integer)
    filter(where actual_row.lesson_type='actual'
      and actual_row.status in ('completed','makeup_completed')
      and actual_row.voided_at is null),0)::integer
  into v_pending_makeup_consumed
  from public.school_lesson_records actual_row
  where actual_row.planned_lesson_id=v_pending.id and actual_row.app_type='school';
  v_pending_clearance_allocated:=public.school_get_lesson_clearance_allocated_minutes(v_pending.id);
  v_pending_claimed:=exists(
    select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=v_pending.id
  );
  v_pending_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_pending.id);
  select exists(select 1 from public.school_student_monthly_settlements settlement
      where settlement.student_id=v_pending.student_id
        and settlement.business_entity_id=v_pending.business_entity_id
        and settlement.year_month=v_pending_month
        and settlement.settlement_status='locked'),
    coalesce(jsonb_agg(jsonb_build_object(
      'settlement_id',settlement.id,'year_month',settlement.year_month,
      'settlement_status',settlement.settlement_status
    ) order by settlement.id) filter(where settlement.id is not null),'[]'::jsonb)
  into v_pending_locked,v_pending_lock_evidence
  from public.school_student_monthly_settlements settlement
  where settlement.student_id=v_pending.student_id
    and settlement.business_entity_id=v_pending.business_entity_id
    and settlement.year_month=v_pending_month
    and settlement.settlement_status='locked';

  if p_clearance_type='overtime_offset' then
    v_overtime_frozen:=v_overtime.student_duration_overage_minutes;
    v_overtime_clearance_allocated:=public.school_get_lesson_clearance_overtime_allocated_minutes(v_overtime.id);
    v_overtime_claimed:=exists(
      select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active'
        and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=v_overtime.id
    );
    v_overtime_month:=v_overtime.student_settlement_month;
    select exists(select 1 from public.school_student_monthly_settlements settlement
        where settlement.student_id=v_overtime.student_id
          and settlement.business_entity_id=v_overtime.business_entity_id
          and settlement.year_month=v_overtime_month
          and settlement.settlement_status='locked'),
      coalesce(jsonb_agg(jsonb_build_object(
        'settlement_id',settlement.id,'year_month',settlement.year_month,
        'settlement_status',settlement.settlement_status
      ) order by settlement.id) filter(where settlement.id is not null),'[]'::jsonb)
    into v_overtime_locked,v_overtime_lock_evidence
    from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_overtime.student_id
      and settlement.business_entity_id=v_overtime.business_entity_id
      and settlement.year_month=v_overtime_month
      and settlement.settlement_status='locked';
    select suggestion.pending_source_planned_id,suggestion.recommendation_rank,
      suggestion.pending_created_at,suggestion.pending_created_at_source
      into v_recommended,v_recommendation_rank,v_recommendation_timestamp,
        v_recommendation_timestamp_source
    from public.school_suggest_lesson_clearance_targets_core(v_overtime.id) suggestion
    order by suggestion.recommendation_rank limit 1;
  end if;

  v_is_recommended:=case when p_clearance_type='overtime_offset'
    then v_recommended is not null and v_recommended=v_pending.id else null end;
  v_deviation_required:=coalesce(p_clearance_type='overtime_offset'
    and v_recommended is not null and v_recommended<>v_pending.id,false);
  v_deviation_reason_valid:=case
    when v_deviation_required then nullif(btrim(coalesce(p_deviation_reason_code,'')),'') is not null
    else p_deviation_reason_code is null and p_deviation_reason_note is null
  end;
  v_same_teacher:=case when p_clearance_type='overtime_offset'
    then v_pending.teacher_id is not distinct from v_overtime.teacher_id else null end;
  v_same_subject:=case when p_clearance_type='overtime_offset'
    then v_pending.subject_id is not distinct from v_overtime.subject_id else null end;
  v_requires_admin:=p_clearance_type<>'overtime_offset'
    or coalesce((v_base->>'requires_forward_adjustment')::boolean,false);
  v_can_execute:=v_deviation_reason_valid
    and nullif(btrim(coalesce(p_business_note,'')),'') is not null
    and (v_actor.actor_role='admin'
      or (v_actor.actor_role='operator' and not v_requires_admin));
  if not v_deviation_reason_valid then
    v_blocker_code:='LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED';
    v_blocker_message:='未采用FIFO建议时必须填写偏离原因；采用推荐对象时不得提交偏离原因。';
  elsif nullif(btrim(coalesce(p_business_note,'')),'') is null then
    v_blocker_code:='LESSON_CLEARANCE_REQUIRED_INPUT_MISSING';
    v_blocker_message:='业务说明不能为空。';
  elsif v_actor.actor_role='read_only' then
    v_blocker_code:='LESSON_CLEARANCE_ROLE_REQUIRED';
    v_blocker_message:='read_only只能查看候选与历史，不能生成可执行清偿Preview。';
  elsif v_actor.actor_role='operator' and v_requires_admin then
    v_blocker_code:=case when p_clearance_type='overtime_offset'
      then 'LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED'
      when p_clearance_type='legacy_consolidated_fulfillment'
        then 'LESSON_CLEARANCE_LEGACY_ADMIN_REQUIRED'
      else 'LESSON_CLEARANCE_ADMIN_REQUIRED' end;
    v_blocker_message:='当前清偿类型或locked forward仅允许active admin执行。';
  end if;

  v_pending_md5:=md5(to_jsonb(v_pending)::text);
  v_overtime_md5:=case when p_clearance_type='overtime_offset'
    then md5(to_jsonb(v_overtime)::text) else null end;
  v_preview_manifest_sha256:=encode(extensions.digest(concat_ws('|',
    'lesson_clearance_preview_v2',p_request_identity::text,p_clearance_type,
    p_pending_source_planned_id::text,coalesce(p_overtime_source_actual_id::text,''),
    p_allocated_minutes::text,p_operation_date::text,
    coalesce(p_deviation_reason_code,''),coalesce(p_deviation_reason_note,''),
    coalesce(p_business_note,''),coalesce(p_administrative_financial_treatment,''),
    v_pending_md5,coalesce(v_overtime_md5,''),v_base::text
  ),'sha256'),'hex');

  return jsonb_build_object(
    'contract_version','lesson_clearance_preview_v2',
    'request_identity',p_request_identity,
    'idempotency_key',p_request_identity::text,
    'clearance_type',p_clearance_type,
    'requested_minutes',p_allocated_minutes,
    'operation_date',p_operation_date,
    'preview_generated_at',v_preview_generated_at,
    'preview_manifest_sha256',v_preview_manifest_sha256,
    'writer_revalidation_required',true,
    'reservation_created',false,
    'pending_source',jsonb_build_object(
      'planned_id',v_pending.id,'student_id',v_pending.student_id,
      'student_name',v_student_name,'business_entity_id',v_pending.business_entity_id,
      'business_entity_name',v_entity_name,'source_date',v_pending.lesson_date,
      'student_settlement_month',v_pending_month,'teacher_id',v_pending.teacher_id,
      'teacher_name',v_pending_teacher_name,'subject_id',v_pending.subject_id,
      'subject_name',v_pending_subject_name,'initial_minutes',v_pending_initial,
      'makeup_consumed_minutes',v_pending_makeup_consumed,
      'clearance_net_allocated_minutes',v_pending_clearance_allocated,
      'before_remaining_minutes',(v_base->>'pending_before_minutes')::integer,
      'allocated_minutes',p_allocated_minutes,
      'after_remaining_minutes',(v_base->>'pending_after_minutes')::integer,
      'unit_price_jpy',(v_base->>'pending_unit_price_jpy')::numeric,
      'amount_jpy',(v_base->>'pending_amount_jpy')::numeric,
      'active_claimed',v_pending_claimed,'source_locked',v_pending_locked,
      'lock_evidence',v_pending_lock_evidence,'updated_at',v_pending.updated_at,
      'row_md5',v_pending_md5,'evidence_status','current_derived'
    ),
    'overtime_source',case when p_clearance_type='overtime_offset' then jsonb_build_object(
      'actual_id',v_overtime.id,'student_id',v_overtime.student_id,
      'student_name',v_student_name,'business_entity_id',v_overtime.business_entity_id,
      'business_entity_name',v_entity_name,'actual_date',v_overtime.lesson_date,
      'student_settlement_month',v_overtime_month,
      'teacher_wage_month',v_overtime.teacher_settlement_month,
      'teacher_id',v_overtime.teacher_id,'teacher_name',v_overtime_teacher_name,
      'subject_id',v_overtime.subject_id,'subject_name',v_overtime_subject_name,
      'frozen_overtime_minutes',v_overtime_frozen,
      'clearance_net_allocated_minutes',v_overtime_clearance_allocated,
      'before_available_minutes',(v_base->>'overtime_before_minutes')::integer,
      'allocated_minutes',p_allocated_minutes,
      'after_available_minutes',(v_base->>'overtime_after_minutes')::integer,
      'unit_price_jpy',(v_base->>'overtime_unit_price_jpy')::numeric,
      'amount_jpy',(v_base->>'overtime_amount_jpy')::numeric,
      'active_claimed',v_overtime_claimed,'source_locked',v_overtime_locked,
      'lock_evidence',v_overtime_lock_evidence,'updated_at',v_overtime.updated_at,
      'row_md5',v_overtime_md5,'evidence_status','current_derived'
    ) else null end,
    'comparison',jsonb_build_object(
      'same_student',case when p_clearance_type='overtime_offset'
        then v_pending.student_id=v_overtime.student_id else null end,
      'same_business_entity',case when p_clearance_type='overtime_offset'
        then v_pending.business_entity_id=v_overtime.business_entity_id else null end,
      'same_unit_price',case when p_clearance_type='overtime_offset'
        then round((v_base->>'pending_unit_price_jpy')::numeric,6)
          =round((v_base->>'overtime_unit_price_jpy')::numeric,6) else null end,
      'same_teacher',v_same_teacher,'same_subject',v_same_subject,
      'cross_teacher',case when v_same_teacher is null then null else not v_same_teacher end,
      'cross_subject',case when v_same_subject is null then null else not v_same_subject end,
      'evidence_status','current_derived'
    ),
    'fifo',jsonb_build_object(
      'recommended_pending_planned_id',v_recommended,
      'recommendation_rank',v_recommendation_rank,
      'recommendation_timestamp',v_recommendation_timestamp,
      'recommendation_timestamp_source',v_recommendation_timestamp_source,
      'selected_pending_planned_id',v_pending.id,
      'is_recommended_target',v_is_recommended,
      'deviation_required',v_deviation_required,
      'deviation_reason_code',p_deviation_reason_code,
      'deviation_reason_note',p_deviation_reason_note,
      'deviation_reason_valid',v_deviation_reason_valid,
      'selection_mode','manual'
    ),
    'financial',jsonb_build_object(
      'pending_amount_jpy',(v_base->>'pending_amount_jpy')::numeric,
      'overtime_amount_jpy',(v_base->>'overtime_amount_jpy')::numeric,
      'net_amount_jpy',(v_base->>'financial_net_amount_jpy')::numeric,
      'requires_forward_adjustment',(v_base->>'requires_forward_adjustment')::boolean,
      'forward_destination_month',v_base->>'financial_year_month',
      'forward_destination_basis','operation_date_month_v1',
      'forward_adjustment_direction',v_base->>'forward_adjustment_direction',
      'forward_adjustment_amount_jpy',(v_base->>'forward_adjustment_amount_jpy')::numeric,
      'amount_rule_version','lesson_clearance_v2_same_price_v1'
    ),
    'authorization',jsonb_build_object(
      'actor_role',v_actor.actor_role,'requires_admin',v_requires_admin,
      'can_execute_for_current_actor',v_can_execute,
      'blocker_code',v_blocker_code,'blocker_message',v_blocker_message
    ),
    'source_versions',jsonb_build_object(
      'pending_updated_at',v_pending.updated_at,'pending_row_md5',v_pending_md5,
      'overtime_updated_at',case when p_clearance_type='overtime_offset'
        then v_overtime.updated_at else null end,
      'overtime_row_md5',v_overtime_md5
    ),
    'legacy_preview',v_base
  );
end
$function$;

create function public.school_preview_lesson_clearance_reversal_v1(
  p_request_identity uuid,
  p_clearance_id uuid,
  p_operation_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor record;
  v_original public.school_lesson_clearances%rowtype;
  v_detail public.school_lesson_clearance_details%rowtype;
  v_reversal public.school_lesson_clearances%rowtype;
  v_pending public.school_lesson_records%rowtype;
  v_overtime public.school_lesson_records%rowtype;
  v_pending_before integer;
  v_overtime_before integer;
  v_pending_claimed boolean;
  v_overtime_claimed boolean:=false;
  v_locked_history boolean;
  v_forward_direction text:='none';
  v_forward_amount numeric:=0;
  v_can_reverse boolean;
  v_blocker_code text;
  v_blocker_message text;
  v_pending_md5 text;
  v_overtime_md5 text;
  v_manifest text;
begin
  if p_request_identity is null then
    raise exception 'LESSON_CLEARANCE_REQUEST_IDENTITY_INVALID';
  end if;
  if p_operation_date is null then
    raise exception 'LESSON_CLEARANCE_REVERSAL_REQUIRED_INPUT_MISSING';
  end if;
  select * into strict v_actor from public.school_assert_lesson_clearance_reader();
  select * into v_original from public.school_lesson_clearances header
  where header.id=p_clearance_id;
  if not found then raise exception 'LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID'; end if;
  select * into strict v_detail from public.school_lesson_clearance_details detail
  where detail.clearance_id=v_original.id and detail.line_no=1;
  select * into strict v_pending from public.school_lesson_records lesson
  where lesson.id=v_detail.pending_source_planned_id;
  if v_detail.overtime_source_actual_id is not null then
    select * into strict v_overtime from public.school_lesson_records lesson
    where lesson.id=v_detail.overtime_source_actual_id;
  end if;
  select * into v_reversal from public.school_lesson_clearances header
  where header.reverses_clearance_id=v_original.id;
  v_pending_before:=public.school_get_lesson_clearance_pending_remaining_minutes(v_pending.id);
  if v_detail.overtime_source_actual_id is not null then
    v_overtime_before:=public.school_get_lesson_clearance_overtime_remaining_minutes(v_overtime.id);
  end if;
  v_pending_claimed:=exists(select 1
    from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=v_pending.id);
  if v_detail.overtime_source_actual_id is not null then
    v_overtime_claimed:=exists(select 1
      from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active'
        and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=v_overtime.id);
  end if;
  v_locked_history:=v_original.requires_forward_adjustment or exists(
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_original.student_id
      and settlement.business_entity_id=v_original.business_entity_id
      and settlement.year_month=coalesce(v_original.financial_year_month,
        v_original.operational_year_month)
      and settlement.settlement_status='locked'
  );
  if v_locked_history and v_detail.forward_adjustment_direction='increase_student_due' then
    v_forward_direction:='decrease_student_due';
    v_forward_amount:=v_detail.forward_adjustment_amount_jpy;
  elsif v_locked_history and v_detail.forward_adjustment_direction='decrease_student_due' then
    v_forward_direction:='increase_student_due';
    v_forward_amount:=v_detail.forward_adjustment_amount_jpy;
  end if;
  v_can_reverse:=v_actor.actor_role='admin'
    and v_original.clearance_type<>'reversal' and v_reversal.id is null;
  if v_actor.actor_role<>'admin' then
    v_blocker_code:='LESSON_CLEARANCE_REVERSAL_ADMIN_REQUIRED';
    v_blocker_message:='只有active admin可以执行clearance reversal。';
  elsif v_original.clearance_type='reversal' then
    v_blocker_code:='LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID';
    v_blocker_message:='reversal事实不能再次作为reversal来源。';
  elsif v_reversal.id is not null then
    v_blocker_code:='LESSON_CLEARANCE_ALREADY_REVERSED';
    v_blocker_message:='该clearance已经存在reversal，不能重复冲正。';
  end if;
  v_pending_md5:=md5(to_jsonb(v_pending)::text);
  v_overtime_md5:=case when v_detail.overtime_source_actual_id is null
    then null else md5(to_jsonb(v_overtime)::text) end;
  v_manifest:=encode(extensions.digest(concat_ws('|',
    'lesson_clearance_reversal_preview_v1',p_request_identity::text,
    v_original.id::text,p_operation_date::text,v_original.input_manifest_sha256,
    v_detail.pending_source_row_md5,coalesce(v_detail.overtime_source_row_md5,''),
    v_pending_md5,coalesce(v_overtime_md5,''),coalesce(v_reversal.id::text,'')
  ),'sha256'),'hex');
  return jsonb_build_object(
    'contract_version','lesson_clearance_reversal_preview_v1',
    'request_identity',p_request_identity,'idempotency_key',p_request_identity::text,
    'preview_generated_at',transaction_timestamp(),
    'reversal_manifest_sha256',v_manifest,'reservation_created',false,
    'original_clearance',jsonb_build_object(
      'clearance_id',v_original.id,'clearance_type',v_original.clearance_type,
      'actor_user_id',v_original.actor_user_id,'actor_role',v_original.actor_role,
      'created_at',v_original.created_at,'allocated_minutes',v_detail.allocated_minutes,
      'pending_source_planned_id',v_detail.pending_source_planned_id,
      'overtime_source_actual_id',v_detail.overtime_source_actual_id,
      'pending_unit_price_jpy',v_detail.pending_unit_price_jpy,
      'overtime_unit_price_jpy',v_detail.overtime_unit_price_jpy,
      'forward_adjustment_direction',v_detail.forward_adjustment_direction,
      'forward_adjustment_amount_jpy',v_detail.forward_adjustment_amount_jpy,
      'input_manifest_sha256',v_original.input_manifest_sha256
    ),
    'current_state',jsonb_build_object(
      'is_effective',v_reversal.id is null,
      'already_reversed',v_reversal.id is not null,
      'reversal_clearance_id',v_reversal.id,
      'pending_before_reversal_minutes',v_pending_before,
      'pending_after_reversal_minutes',v_pending_before+v_detail.allocated_minutes,
      'overtime_before_reversal_minutes',v_overtime_before,
      'overtime_after_reversal_minutes',case when v_detail.overtime_source_actual_id is null
        then null else v_overtime_before+v_detail.allocated_minutes end,
      'pending_active_claimed',v_pending_claimed,
      'overtime_active_claimed',v_overtime_claimed,
      'affects_active_claim',v_pending_claimed or v_overtime_claimed,
      'entered_settlement_source',null,
      'entered_settlement_source_evidence_status','unavailable'
    ),
    'forward',jsonb_build_object(
      'involves_locked_history',v_locked_history,
      'only_forward',v_locked_history,
      'forward_destination_month',case when v_locked_history
        then to_char(p_operation_date,'YYYY-MM') else null end,
      'forward_destination_basis','reversal_operation_date_month_v1',
      'forward_adjustment_direction',v_forward_direction,
      'forward_adjustment_amount_jpy',v_forward_amount
    ),
    'authorization',jsonb_build_object(
      'actor_role',v_actor.actor_role,'requires_admin',true,
      'can_reverse',v_can_reverse,'blocker_code',v_blocker_code,
      'blocker_message',v_blocker_message
    ),
    'source_versions',jsonb_build_object(
      'pending_saved_row_md5',v_detail.pending_source_row_md5,
      'pending_current_row_md5',v_pending_md5,
      'pending_evidence_status',case when v_pending_md5=v_detail.pending_source_row_md5
        then 'immutable_reference' else 'unavailable' end,
      'overtime_saved_row_md5',v_detail.overtime_source_row_md5,
      'overtime_current_row_md5',v_overtime_md5,
      'overtime_evidence_status',case
        when v_detail.overtime_source_actual_id is null then 'unavailable'
        when v_overtime_md5=v_detail.overtime_source_row_md5 then 'immutable_reference'
        else 'unavailable' end
    ),
    'writer_revalidation_required',true
  );
end
$function$;

create function public.school_list_lesson_clearance_history_v2(
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
  select coalesce(jsonb_agg(item.payload order by item.created_at desc,item.clearance_id),'[]'::jsonb)
  into v_result
  from (
    select header.created_at,header.id clearance_id,jsonb_build_object(
      'contract_version','lesson_clearance_history_v2',
      'clearance_id',header.id,'clearance_type',header.clearance_type,
      'student_id',header.student_id,
      'student_name',coalesce(student.display_name,student.name),
      'business_entity_id',header.business_entity_id,'business_entity_name',entity.name,
      'operation_date',header.operation_date,
      'operational_year_month',header.operational_year_month,
      'financial_year_month',header.financial_year_month,
      'pending_source_planned_id',detail.pending_source_planned_id,
      'overtime_source_actual_id',detail.overtime_source_actual_id,
      'allocated_minutes',detail.allocated_minutes,'balance_effect',detail.balance_effect,
      'pending_unit_price_jpy',detail.pending_unit_price_jpy,
      'overtime_unit_price_jpy',detail.overtime_unit_price_jpy,
      'pending_amount_jpy',-round(detail.pending_unit_price_jpy*detail.allocated_minutes/60.0,2),
      'overtime_amount_jpy',case when detail.overtime_unit_price_jpy is null then 0
        else round(detail.overtime_unit_price_jpy*detail.allocated_minutes/60.0,2) end,
      'financial_net_amount_jpy',case when detail.overtime_unit_price_jpy is null then 0
        else round((detail.overtime_unit_price_jpy-detail.pending_unit_price_jpy)
          *detail.allocated_minutes/60.0,2) end,
      'recommended_pending_planned_id',header.recommended_pending_source_id,
      'selected_pending_planned_id',detail.pending_source_planned_id,
      'is_recommended_target',case when header.clearance_type='overtime_offset'
        then not header.deviated_from_recommendation else null end,
      'deviated_from_recommendation',header.deviated_from_recommendation,
      'deviation_reason_code',header.deviation_reason_code,
      'deviation_reason_note',header.deviation_note,
      'same_teacher',case when detail.overtime_source_actual_id is null then null
        when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
         and md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
        then pending_row.teacher_id is not distinct from overtime_row.teacher_id else null end,
      'cross_teacher',case when detail.overtime_source_actual_id is null then null
        when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
         and md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
        then not (pending_row.teacher_id is not distinct from overtime_row.teacher_id) else null end,
      'same_subject',case when detail.overtime_source_actual_id is null then null
        when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
         and md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
        then pending_row.subject_id is not distinct from overtime_row.subject_id else null end,
      'cross_subject',case when detail.overtime_source_actual_id is null then null
        when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
         and md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
        then not (pending_row.subject_id is not distinct from overtime_row.subject_id) else null end,
      'source_comparison_evidence_status',case
        when detail.overtime_source_actual_id is null then 'unavailable'
        when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
         and md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
        then 'immutable_reference' else 'unavailable' end,
      'pending_source_locked_at_operation',null,
      'overtime_source_locked_at_operation',null,
      'source_lock_evidence_status','unavailable',
      'requires_forward_adjustment',header.requires_forward_adjustment,
      'forward_destination_month',header.financial_year_month,
      'forward_adjustment_direction',detail.forward_adjustment_direction,
      'forward_adjustment_amount_jpy',detail.forward_adjustment_amount_jpy
    ) || jsonb_build_object(
      'request_identity',case when header.idempotency_key
        ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then header.idempotency_key else null end,
      'idempotency_key',header.idempotency_key,
      'input_manifest_sha256',header.input_manifest_sha256,
      'actor_user_id',header.actor_user_id,'actor_role',header.actor_role,
      'business_note',header.business_note,'created_at',header.created_at,
      'is_effective',case when header.clearance_type='reversal' then true
        else reversal.id is null end,
      'is_reversed',reversal.id is not null,'reversal_clearance_id',reversal.id,
      'reversal_created_at',reversal.created_at,
      'reversal_actor_user_id',reversal.actor_user_id,
      'reversal_actor_role',reversal.actor_role,
      'effective_allocated_minutes',case when header.clearance_type='reversal'
        then -detail.allocated_minutes when reversal.id is null then detail.allocated_minutes else 0 end,
      'can_reverse',v_actor.actor_role='admin'
        and header.clearance_type<>'reversal' and reversal.id is null,
      'reverse_blocker_code',case
        when v_actor.actor_role<>'admin' then 'LESSON_CLEARANCE_REVERSAL_ADMIN_REQUIRED'
        when header.clearance_type='reversal' then 'LESSON_CLEARANCE_REVERSAL_SOURCE_INVALID'
        when reversal.id is not null then 'LESSON_CLEARANCE_ALREADY_REVERSED'
        else null end,
      'evidence_status',jsonb_build_object(
        'selection','snapshot','forward','snapshot','request_identity','snapshot',
        'pending_source',case when md5(to_jsonb(pending_row)::text)=detail.pending_source_row_md5
          then 'immutable_reference' else 'unavailable' end,
        'overtime_source',case
          when detail.overtime_source_actual_id is null then 'unavailable'
          when md5(to_jsonb(overtime_row)::text)=detail.overtime_source_row_md5
            then 'immutable_reference' else 'unavailable' end,
        'source_lock_at_operation','unavailable'
      )
    ) payload
    from public.school_lesson_clearances header
    join public.school_lesson_clearance_details detail
      on detail.clearance_id=header.id and detail.line_no=1
    join public.school_students student on student.id=header.student_id
    join public.school_business_entities entity on entity.id=header.business_entity_id
    join public.school_lesson_records pending_row
      on pending_row.id=detail.pending_source_planned_id
    left join public.school_lesson_records overtime_row
      on overtime_row.id=detail.overtime_source_actual_id
    left join public.school_lesson_clearances reversal
      on reversal.reverses_clearance_id=header.id
    where p_student_id is null or header.student_id=p_student_id
  ) item;
  return v_result;
end
$function$;

alter function public.school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text) owner to postgres;
alter function public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)
  owner to postgres;
alter function public.school_list_lesson_clearance_history_v2(uuid) owner to postgres;

revoke all on function public.school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text) to authenticated;
revoke all on function public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)
  from public,anon,authenticated,service_role;
grant execute on function public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)
  to authenticated;
revoke all on function public.school_list_lesson_clearance_history_v2(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_history_v2(uuid)
  to authenticated;

comment on function public.school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text) is
  'Phase 2C-C-R1 read-only authoritative clearance Preview. Request identity is the future writer idempotency key; no reservation is created.';
comment on function public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date) is
  'Phase 2C-C-R1 read-only reversal eligibility/impact Preview. It never calls the reversal writer.';
comment on function public.school_list_lesson_clearance_history_v2(uuid) is
  'Phase 2C-C-R1 JSON history with snapshot/current-reference evidence status and reversal state.';

\if :{?PHASE2C_C_R1_REHEARSAL}
\else
commit;
\endif
