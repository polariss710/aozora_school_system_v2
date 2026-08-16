-- Exact rollback for the 2026-08-16 registered variance Preview extension.
-- Restores the production definition MD5 44c998671550d2288c7f4960d6d52fdc,
-- owner/security/search_path, ACL and comment captured by the read-only preflight.
-- Execute atomically with psql -1. No business DML.
\set ON_ERROR_STOP on
\pset pager off

create or replace function public.school_preview_student_settlement_adjustment_dialog(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_year_month text,
  p_source_treatment_mode text,
  p_settlement_exchange_rate numeric,
  p_settlement_exchange_rate_source text,
  p_settlement_exchange_rate_effective_date date,
  p_adjustment_mode text,
  p_explicit_user_amount_cny numeric default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_preview record;
  v_resolved record;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_source_draft public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment_draft public.school_student_settlement_adjustment_drafts%rowtype;
  v_source_lines jsonb := '[]'::jsonb;
  v_source_updated_at timestamptz;
  v_expected_facts jsonb;
  v_preview_manifest text;
  v_generated_at timestamptz := clock_timestamp();
begin
  if p_student_id is null
     or p_business_entity_id is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_ADJUSTMENT_DIALOG_SCOPE_INVALID';
  end if;

  select * into strict v_preview
  from public.school_preview_student_settlement_source_treatment(
    p_student_id,
    p_year_month,
    p_source_treatment_mode,
    p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date
  );

  if v_preview.business_entity_id is distinct from p_business_entity_id then
    raise exception 'SETTLEMENT_ADJUSTMENT_DIALOG_BUSINESS_ENTITY_MISMATCH';
  end if;

  select * into strict v_resolved
  from public.school_tuition_p0b2_resolve_adjustment(
    p_adjustment_mode,
    p_explicit_user_amount_cny,
    v_preview.system_difference_cny
  );

  select m.* into v_settlement
  from public.school_student_monthly_settlements m
  where m.student_id=p_student_id
    and m.business_entity_id=p_business_entity_id
    and m.year_month=p_year_month
  order by m.updated_at desc,m.id
  limit 1;

  select d.* into v_source_draft
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id=p_student_id
    and d.business_entity_id=p_business_entity_id
    and d.year_month=p_year_month
    and d.status='active'
  order by d.created_at desc,d.id
  limit 1;

  select d.* into v_adjustment_draft
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id=p_student_id
    and d.business_entity_id=p_business_entity_id
    and d.year_month=p_year_month
    and d.status='active'
  order by d.created_at desc,d.id
  limit 1;

  if v_preview.source_treatment_mode='net_lesson_variance_to_financial_credit_v1' then
    with source_rows as (
      select
        l.*,
        p.lesson_date as planned_lesson_date,
        a.lesson_date as actual_lesson_date,
        coalesce(sa.name,sp.name) as subject_name,
        coalesce(ta.display_name,ta.name,tp.display_name,tp.name) as teacher_name,
        coalesce(a.unit_price,p.unit_price) as unit_price_jpy,
        a.student_duration_overage_minutes as overage_minutes,
        greatest(p.updated_at,a.updated_at) as source_updated_at
      from public.school_tuition_p0f_source_lines(
        p_student_id,p_business_entity_id,p_year_month,
        v_preview.settlement_exchange_rate,false
      ) l
      left join public.school_lesson_records p on p.id=l.source_planned_lesson_id
      left join public.school_lesson_records a on a.id=l.source_actual_lesson_id
      left join public.school_subjects sp on sp.id=p.subject_id
      left join public.school_subjects sa on sa.id=a.subject_id
      left join public.school_teachers tp on tp.id=p.teacher_id
      left join public.school_teachers ta on ta.id=a.teacher_id
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'source_type',r.source_type,
        'source_planned_lesson_id',r.source_planned_lesson_id,
        'source_actual_lesson_id',r.source_actual_lesson_id,
        'planned_lesson_date',r.planned_lesson_date,
        'actual_lesson_date',r.actual_lesson_date,
        'subject_name',r.subject_name,
        'teacher_name',r.teacher_name,
        'remaining_hours',case when r.source_type='unused_planned_credit_v1'
          then -r.source_hours else null end,
        'overage_minutes',r.overage_minutes,
        'overage_hours',case when r.source_type='actual_duration_overage_charge_v1'
          then r.source_hours else null end,
        'unit_price_jpy',r.unit_price_jpy,
        'source_amount_jpy',r.source_amount_jpy,
        'source_amount_cny',r.source_amount_cny,
        'claim_eligible',true,
        'exclusion_reason',null,
        'source_updated_at',r.source_updated_at,
        'line_manifest_sha256',r.line_manifest_sha256
      ) order by r.source_type,r.source_planned_lesson_id,r.source_actual_lesson_id),'[]'::jsonb),
      max(r.source_updated_at)
    into v_source_lines,v_source_updated_at
    from source_rows r;
  end if;

  v_expected_facts := jsonb_build_object(
    'student_id',p_student_id,
    'business_entity_id',p_business_entity_id,
    'year_month',p_year_month,
    'source_treatment_mode',v_preview.source_treatment_mode,
    'settlement_exchange_rate',v_preview.settlement_exchange_rate,
    'settlement_exchange_rate_source',v_preview.settlement_exchange_rate_source,
    'settlement_exchange_rate_effective_date',v_preview.settlement_exchange_rate_effective_date,
    'adjustment_mode',v_resolved.adjustment_mode,
    'explicit_user_amount_cny',p_explicit_user_amount_cny,
    'system_difference_cny',v_resolved.authoritative_system_difference_cny,
    'lesson_variance_manifest_sha256',v_preview.lesson_variance_manifest_sha256
  );

  v_preview_manifest := encode(extensions.digest(concat_ws('|',
    'settlement_adjustment_dialog_preview_v1',
    p_student_id::text,p_business_entity_id::text,p_year_month,
    v_preview.source_treatment_mode,
    coalesce(to_char(v_preview.settlement_exchange_rate,'FM999999990.000000'),''),
    coalesce(v_preview.settlement_exchange_rate_source,''),
    coalesce(v_preview.settlement_exchange_rate_effective_date::text,''),
    v_resolved.adjustment_mode,
    coalesce(to_char(p_explicit_user_amount_cny,'FM999999990.00'),''),
    to_char(v_resolved.authoritative_system_difference_cny,'FM999999990.00'),
    v_preview.lesson_variance_manifest_sha256
  ),'sha256'),'hex');

  return jsonb_build_object(
    'contract_version','settlement_adjustment_dialog_preview_v1',
    'student_id',p_student_id,
    'business_entity_id',p_business_entity_id,
    'year_month',p_year_month,
    'current_state',jsonb_build_object(
      'is_saved',v_settlement.id is not null
        or v_source_draft.id is not null or v_adjustment_draft.id is not null,
      'settlement_id',v_settlement.id,
      'settlement_status',v_settlement.settlement_status,
      'is_locked',coalesce(v_settlement.settlement_status='locked',false),
      'source_treatment_draft_id',v_source_draft.id,
      'source_treatment_draft_status',v_source_draft.status,
      'source_treatment_mode',coalesce(v_source_draft.source_treatment_mode,
        v_settlement.source_treatment_mode),
      'settlement_exchange_rate',coalesce(v_source_draft.settlement_exchange_rate,
        v_settlement.settlement_exchange_rate),
      'settlement_exchange_rate_source',coalesce(v_source_draft.settlement_exchange_rate_source,
        v_settlement.settlement_exchange_rate_source),
      'settlement_exchange_rate_effective_date',coalesce(
        v_source_draft.settlement_exchange_rate_effective_date,
        v_settlement.settlement_exchange_rate_effective_date),
      'adjustment_draft_id',v_adjustment_draft.id,
      'adjustment_draft_status',v_adjustment_draft.status,
      'adjustment_mode',v_adjustment_draft.adjustment_source,
      'draft_adjustment_amount_cny',v_adjustment_draft.adjustment_amount_cny,
      'posted_adjustment_amount_cny',v_settlement.adjustment_amount_cny,
      'posted_carryover_cny',v_settlement.carryover_amount_cny
    ),
    'preview',to_jsonb(v_preview) || jsonb_build_object(
      'base_receivable_difference_cny',round(
        v_preview.planned_fee_cny+v_preview.previous_carryover_cny
        -v_preview.received_equivalent_cny,2),
      'projected_adjustment_amount_cny',v_resolved.resolved_adjustment_amount_cny,
      'projected_final_carryover_cny',v_resolved.resolved_carryover_cny,
      'source_lines',v_source_lines,
      'source_updated_at',v_source_updated_at
    ),
    'preview_expected_facts',v_expected_facts,
    'preview_manifest_sha256',v_preview_manifest,
    'preview_generated_at',v_generated_at
  );
end
$function$;

alter function public.school_preview_student_settlement_adjustment_dialog(
  uuid,uuid,text,text,numeric,text,date,text,numeric
) owner to postgres;
revoke all on function public.school_preview_student_settlement_adjustment_dialog(
  uuid,uuid,text,text,numeric,text,date,text,numeric
) from public,anon,authenticated,service_role;
grant execute on function public.school_preview_student_settlement_adjustment_dialog(
  uuid,uuid,text,text,numeric,text,date,text,numeric
) to anon,authenticated,service_role;

comment on function public.school_preview_student_settlement_adjustment_dialog(
  uuid,uuid,text,text,numeric,text,date,text,numeric
) is 'Pure read-only P0-F dialog preview. Composes the existing P0-F source reader and P0-B2 adjustment resolver, exposes current saved state separately from pending form preview, and performs no business DML.';

do $rollback_postflight$
declare
  v_signature constant regprocedure :=
    'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_signature::oid)) <> '44c998671550d2288c7f4960d6d52fdc'
     or pg_get_userbyid((select p.proowner from pg_proc p where p.oid=v_signature::oid)) <> 'postgres'
     or not (select p.prosecdef from pg_proc p where p.oid=v_signature::oid)
     or (select p.proconfig from pg_proc p where p.oid=v_signature::oid)
        is distinct from array['search_path=pg_catalog, public']::text[]
     or not has_function_privilege('anon',v_signature,'EXECUTE')
     or not has_function_privilege('authenticated',v_signature,'EXECUTE')
     or not has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'REGISTERED_VARIANCE_PREVIEW_EXACT_ROLLBACK_FAILED';
  end if;
end
$rollback_postflight$;
