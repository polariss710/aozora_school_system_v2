-- P0-F trusted local settlement management wrappers and anon writer ACL closure.
-- No business facts or formulas are introduced here. Both wrappers verify a
-- DB-authoritative preview and delegate writes to the existing owner writers.
\set ON_ERROR_STOP on

begin;

create or replace function public.school_save_student_settlement_draft_local(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_year_month text,
  p_source_treatment_mode text,
  p_settlement_exchange_rate numeric,
  p_settlement_exchange_rate_source text,
  p_settlement_exchange_rate_effective_date date,
  p_adjustment_mode text,
  p_explicit_user_amount_cny numeric,
  p_expected_preview_manifest_sha256 text,
  p_expected_lesson_variance_manifest_sha256 text,
  p_expected_source_count integer,
  p_expected_unused_planned_credit_jpy numeric,
  p_expected_overage_charge_jpy numeric,
  p_expected_net_lesson_variance_jpy numeric,
  p_expected_net_lesson_variance_cny numeric,
  p_expected_system_difference_cny numeric,
  p_expected_final_carryover_cny numeric,
  p_reason text,
  p_note text,
  p_operator_authority text,
  p_confirmation text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_preview jsonb;
  v_after jsonb;
  v_source_draft public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment_draft public.school_student_settlement_adjustment_drafts%rowtype;
  v_expected_confirmation text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SETTLEMENT_LOCAL_TRUSTED_ROLE_REQUIRED';
  end if;
  if p_operator_authority is distinct from 'local_trusted_business_owner_v1' then
    raise exception 'SETTLEMENT_LOCAL_OPERATOR_AUTHORITY_MISMATCH';
  end if;
  v_expected_confirmation := format(
    'SAVE STUDENT SETTLEMENT DRAFT %s %s MANIFEST %s',
    p_student_id, p_year_month, p_expected_preview_manifest_sha256
  );
  if p_confirmation is distinct from v_expected_confirmation then
    raise exception 'SETTLEMENT_LOCAL_CONFIRMATION_MISMATCH';
  end if;
  if p_business_entity_id is null
     or not exists (
       select 1 from public.school_students s
       where s.id = p_student_id
         and s.business_entity_id = p_business_entity_id
         and s.app_type = 'school'
     ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_DIALOG_BUSINESS_ENTITY_MISMATCH';
  end if;

  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, p_business_entity_id, p_year_month
  );

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id,
    p_business_entity_id,
    p_year_month,
    p_source_treatment_mode,
    p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode,
    p_explicit_user_amount_cny
  );

  if v_preview->>'preview_manifest_sha256' is distinct from p_expected_preview_manifest_sha256
     or v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256'
          is distinct from p_expected_lesson_variance_manifest_sha256
     or (v_preview->'preview'->>'lesson_variance_source_count')::integer
          is distinct from p_expected_source_count
     or (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric
          is distinct from p_expected_unused_planned_credit_jpy
     or (v_preview->'preview'->>'overage_charge_jpy')::numeric
          is distinct from p_expected_overage_charge_jpy
     or (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric
          is distinct from p_expected_net_lesson_variance_jpy
     or (v_preview->'preview'->>'net_lesson_variance_cny')::numeric
          is distinct from p_expected_net_lesson_variance_cny
     or (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric
          is distinct from p_expected_system_difference_cny
     or (v_preview->'preview'->>'projected_final_carryover_cny')::numeric
          is distinct from p_expected_final_carryover_cny then
    raise exception 'SETTLEMENT_LOCAL_EXPECTED_FACTS_MISMATCH';
  end if;

  perform * from public.school_set_student_settlement_source_treatment_draft(
    p_student_id,
    p_year_month,
    p_source_treatment_mode,
    p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_reason
  );
  perform * from public.school_set_student_monthly_settlement_draft_adjustment(
    p_student_id,
    p_year_month,
    p_explicit_user_amount_cny,
    p_adjustment_mode,
    p_reason,
    p_note
  );

  select * into strict v_source_draft
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.year_month = p_year_month
    and d.status = 'active';
  select * into strict v_adjustment_draft
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.year_month = p_year_month
    and d.status = 'active';

  v_after := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id,
    p_business_entity_id,
    p_year_month,
    p_source_treatment_mode,
    p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode,
    p_explicit_user_amount_cny
  );
  if v_after->>'preview_manifest_sha256' is distinct from p_expected_preview_manifest_sha256
     or v_source_draft.source_manifest_sha256
          is distinct from p_expected_lesson_variance_manifest_sha256
     or v_source_draft.source_count is distinct from p_expected_source_count
     or v_adjustment_draft.adjustment_amount_cny
          is distinct from (v_after->'preview'->>'projected_adjustment_amount_cny')::numeric then
    raise exception 'SETTLEMENT_LOCAL_POSTSAVE_FACTS_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok', true,
    'operation', 'save_student_settlement_draft_local_v1',
    'student_id', p_student_id,
    'business_entity_id', p_business_entity_id,
    'year_month', p_year_month,
    'preview_manifest_sha256', p_expected_preview_manifest_sha256,
    'source_treatment_draft_id', v_source_draft.id,
    'source_treatment_draft_updated_at', v_source_draft.updated_at,
    'adjustment_draft_id', v_adjustment_draft.id,
    'adjustment_draft_updated_at', v_adjustment_draft.updated_at,
    'adjustment_amount_cny', v_adjustment_draft.adjustment_amount_cny,
    'final_carryover_cny', (v_after->'preview'->>'projected_final_carryover_cny')::numeric,
    'lesson_variance_source_count', v_source_draft.source_count,
    'lesson_variance_manifest_sha256', v_source_draft.source_manifest_sha256
  );
end
$function$;

create or replace function public.school_lock_student_monthly_settlement_local(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_year_month text,
  p_source_treatment_mode text,
  p_settlement_exchange_rate numeric,
  p_settlement_exchange_rate_source text,
  p_settlement_exchange_rate_effective_date date,
  p_adjustment_mode text,
  p_explicit_user_amount_cny numeric,
  p_expected_preview_manifest_sha256 text,
  p_expected_lesson_variance_manifest_sha256 text,
  p_expected_source_count integer,
  p_expected_unused_planned_credit_jpy numeric,
  p_expected_overage_charge_jpy numeric,
  p_expected_net_lesson_variance_jpy numeric,
  p_expected_net_lesson_variance_cny numeric,
  p_expected_system_difference_cny numeric,
  p_expected_final_carryover_cny numeric,
  p_expected_source_treatment_draft_id uuid,
  p_expected_source_treatment_draft_updated_at timestamptz,
  p_expected_adjustment_draft_id uuid,
  p_expected_adjustment_draft_updated_at timestamptz,
  p_note text,
  p_operator_authority text,
  p_confirmation text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_preview jsonb;
  v_source_draft public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment_draft public.school_student_settlement_adjustment_drafts%rowtype;
  v_lock record;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_claim_count integer;
  v_expected_confirmation text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SETTLEMENT_LOCAL_TRUSTED_ROLE_REQUIRED';
  end if;
  if p_operator_authority is distinct from 'local_trusted_business_owner_v1' then
    raise exception 'SETTLEMENT_LOCAL_OPERATOR_AUTHORITY_MISMATCH';
  end if;
  v_expected_confirmation := format(
    'LOCK STUDENT SETTLEMENT %s %s MANIFEST %s CARRY %s',
    p_student_id, p_year_month, p_expected_preview_manifest_sha256,
    p_expected_final_carryover_cny
  );
  if p_confirmation is distinct from v_expected_confirmation then
    raise exception 'SETTLEMENT_LOCAL_CONFIRMATION_MISMATCH';
  end if;
  if p_business_entity_id is null
     or not exists (
       select 1 from public.school_students s
       where s.id = p_student_id
         and s.business_entity_id = p_business_entity_id
         and s.app_type = 'school'
     ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_DIALOG_BUSINESS_ENTITY_MISMATCH';
  end if;

  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, p_business_entity_id, p_year_month
  );
  if exists (
    select 1
    from public.school_student_tuition_generation_identities g
    join public.school_student_tuition_generation_revisions r
      on r.generation_identity_id = g.id
    where g.student_id = p_student_id
      and g.business_entity_id = p_business_entity_id
      and g.billing_month = (to_date(p_year_month || '-01', 'YYYY-MM-DD') + interval '1 month')::date
      and r.lifecycle_status = 'active'
  ) then
    raise exception 'TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE';
  end if;

  select * into strict v_source_draft
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.year_month = p_year_month
    and d.status = 'active';
  select * into strict v_adjustment_draft
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.year_month = p_year_month
    and d.status = 'active';
  if v_source_draft.id is distinct from p_expected_source_treatment_draft_id
     or v_source_draft.updated_at is distinct from p_expected_source_treatment_draft_updated_at
     or v_adjustment_draft.id is distinct from p_expected_adjustment_draft_id
     or v_adjustment_draft.updated_at is distinct from p_expected_adjustment_draft_updated_at
     or v_source_draft.source_manifest_sha256
          is distinct from p_expected_lesson_variance_manifest_sha256
     or v_source_draft.source_count is distinct from p_expected_source_count then
    raise exception 'SETTLEMENT_LOCAL_DRAFT_EXPECTED_FACTS_MISMATCH';
  end if;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id,
    p_business_entity_id,
    p_year_month,
    p_source_treatment_mode,
    p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode,
    p_explicit_user_amount_cny
  );
  if v_preview->>'preview_manifest_sha256' is distinct from p_expected_preview_manifest_sha256
     or v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256'
          is distinct from p_expected_lesson_variance_manifest_sha256
     or (v_preview->'preview'->>'lesson_variance_source_count')::integer
          is distinct from p_expected_source_count
     or (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric
          is distinct from p_expected_unused_planned_credit_jpy
     or (v_preview->'preview'->>'overage_charge_jpy')::numeric
          is distinct from p_expected_overage_charge_jpy
     or (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric
          is distinct from p_expected_net_lesson_variance_jpy
     or (v_preview->'preview'->>'net_lesson_variance_cny')::numeric
          is distinct from p_expected_net_lesson_variance_cny
     or (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric
          is distinct from p_expected_system_difference_cny
     or (v_preview->'preview'->>'projected_final_carryover_cny')::numeric
          is distinct from p_expected_final_carryover_cny then
    raise exception 'SETTLEMENT_LOCAL_EXPECTED_FACTS_MISMATCH';
  end if;

  select * into strict v_lock
  from public.school_lock_student_monthly_settlement(
    p_student_id, p_year_month, p_note
  );
  select * into strict v_settlement
  from public.school_student_monthly_settlements s
  where s.id = v_lock.settlement_id;
  select count(*) into v_claim_count
  from public.school_student_settlement_lesson_variance_claims c
  where c.settlement_id = v_settlement.id
    and c.claim_status = 'active';

  if v_settlement.settlement_status is distinct from 'locked'
     or v_settlement.system_difference_cny is distinct from p_expected_system_difference_cny
     or v_settlement.carryover_amount_cny is distinct from p_expected_final_carryover_cny
     or v_settlement.lesson_variance_manifest_sha256
          is distinct from p_expected_lesson_variance_manifest_sha256
     or v_settlement.lesson_variance_source_count is distinct from p_expected_source_count
     or v_claim_count is distinct from p_expected_source_count then
    raise exception 'SETTLEMENT_LOCAL_POSTLOCK_FACTS_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok', true,
    'operation', 'lock_student_monthly_settlement_local_v1',
    'settlement_id', v_settlement.id,
    'student_id', v_settlement.student_id,
    'business_entity_id', v_settlement.business_entity_id,
    'year_month', v_settlement.year_month,
    'settlement_status', v_settlement.settlement_status,
    'locked_at', v_settlement.locked_at,
    'system_difference_cny', v_settlement.system_difference_cny,
    'adjustment_amount_cny', v_settlement.adjustment_amount_cny,
    'final_carryover_cny', v_settlement.carryover_amount_cny,
    'lesson_variance_source_count', v_settlement.lesson_variance_source_count,
    'lesson_variance_manifest_sha256', v_settlement.lesson_variance_manifest_sha256,
    'active_claim_count', v_claim_count,
    'source_treatment_draft_id', v_source_draft.id,
    'adjustment_draft_id', v_adjustment_draft.id
  );
end
$function$;

revoke all on function public.school_save_student_settlement_draft_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text
) from public, anon, authenticated;
grant execute on function public.school_save_student_settlement_draft_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text
) to service_role;

revoke all on function public.school_lock_student_monthly_settlement_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,
  text,text,text
) from public, anon, authenticated;
grant execute on function public.school_lock_student_monthly_settlement_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,
  text,text,text
) to service_role;

-- Browser V2 is anon read-only. Keep the existing authenticated/service_role
-- grants, but remove PUBLIC/anon access to all monthly settlement writers.
revoke execute on function public.school_set_student_monthly_settlement_draft_adjustment(
  uuid,text,numeric,text,text,text
) from public, anon;
grant execute on function public.school_set_student_monthly_settlement_draft_adjustment(
  uuid,text,numeric,text,text,text
) to authenticated, service_role;
revoke execute on function public.school_lock_student_monthly_settlement(uuid,text,text)
  from public, anon;
grant execute on function public.school_lock_student_monthly_settlement(uuid,text,text)
  to authenticated, service_role;
revoke execute on function public.school_unlock_student_monthly_settlement(uuid,text)
  from public, anon;
grant execute on function public.school_unlock_student_monthly_settlement(uuid,text)
  to authenticated, service_role;
revoke execute on function public.school_relock_student_monthly_settlement(uuid,text)
  from public, anon;
grant execute on function public.school_relock_student_monthly_settlement(uuid,text)
  to authenticated, service_role;

comment on function public.school_save_student_settlement_draft_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text
) is 'P0-F local trusted service_role-only exact-facts wrapper; delegates source and adjustment draft writes to existing DB-authoritative writers.';
comment on function public.school_lock_student_monthly_settlement_local(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,
  text,text,text
) is 'P0-F local trusted service_role-only exact-facts wrapper; delegates final lock to the existing DB-authoritative lock writer.';

commit;
