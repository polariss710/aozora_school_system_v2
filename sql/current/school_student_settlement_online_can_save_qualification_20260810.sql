\set ON_ERROR_STOP on

-- Phase C-R1: make online status can_save and the online save/lock structural
-- guard consume one owner-only eligibility result.
--
-- Scope:
-- - function definitions, ACL and comments only;
-- - no business-row DML and no month-close rule;
-- - no amount, exchange-rate, carryover, adjustment or manifest changes;
-- - historical business-entity, bill, revision, identity and income facts stay
--   immutable and are only read as existing authority/evidence.

begin;
set local lock_timeout = '8s';
set local statement_timeout = '120s';

do $preflight$
begin
  if to_regprocedure(
       'public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)'
     ) is null
     or to_regprocedure(
       'public.school_assert_tuition_settlement_month_mutable(uuid,text)'
     ) is null
     or to_regprocedure(
       'public.school_get_student_monthly_settlement_wage_blockers(text,uuid)'
     ) is null
     or to_regprocedure(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'
     ) is null
     or to_regprocedure(
       'public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)'
     ) is null
     or to_regprocedure(
       'public.school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text)'
     ) is null
     or to_regprocedure(
       'public.school_get_student_monthly_settlement_online_status_core(uuid,text)'
     ) is null then
    raise exception 'SETTLEMENT_ONLINE_CAN_SAVE_R1_DEPENDENCY_MISSING';
  end if;
end
$preflight$;

create or replace function public.school_get_student_settlement_online_save_eligibility_core(
  p_student_id uuid,
  p_year_month text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_business_entity_id uuid;
  v_effective record;
  v_physical_count integer;
  v_evidence_count integer;
  v_source_facts_available boolean := false;
  v_blocker_code text;
  v_blocker_message text;
  v_active_successor boolean := false;
  v_current_entity_canonical_bill boolean := false;
  v_cross_entity_canonical_bill boolean := false;
begin
  if p_student_id is null or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    return jsonb_build_object(
      'contract_version', 'student_settlement_online_save_eligibility_v1',
      'student_id', p_student_id,
      'year_month', p_year_month,
      'business_entity_id', null,
      'effective_state', null,
      'source_facts_available', false,
      'can_save', false,
      'save_blocker_code', 'SETTLEMENT_SCOPE_NOT_UNIQUE',
      'save_blocker_message', '该学生月份无法解析唯一结算范围，不能保存草稿。'
    );
  end if;

  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school';
  if v_business_entity_id is null then
    return jsonb_build_object(
      'contract_version', 'student_settlement_online_save_eligibility_v1',
      'student_id', p_student_id,
      'year_month', p_year_month,
      'business_entity_id', null,
      'effective_state', null,
      'source_facts_available', false,
      'can_save', false,
      'save_blocker_code', 'SETTLEMENT_SCOPE_NOT_UNIQUE',
      'save_blocker_message', '该学生月份无法解析唯一结算范围，不能保存草稿。'
    );
  end if;

  select count(*) into v_physical_count
  from public.school_student_monthly_settlements s
  where s.student_id = p_student_id and s.year_month = p_year_month;
  select count(*) into v_evidence_count
  from public.school_student_monthly_settlement_historical_completion_evidence e
  where e.student_id = p_student_id and e.settlement_month = p_year_month;

  select * into strict v_effective
  from public.school_resolve_student_monthly_settlement_effective_state(
    p_student_id, p_year_month, v_business_entity_id
  );

  select (
    exists (
      select 1
      from public.school_list_r1d_e_c_student_month_lessons(
        p_student_id, p_year_month
      ) resolved
      join public.school_lesson_records l on l.id = resolved.lesson_id
      where not (l.lesson_type = 'planned' and l.voided_at is not null)
    )
    or exists (
      select 1
      from public.school_income_records i
      where i.app_type = 'school'
        and i.student_id = p_student_id
        and coalesce(i.settlement_month, i.year_month) = p_year_month
        and i.income_category = 'tuition'
        and i.status = 'received'
        and coalesce(i.include_in_student_settlement, true) = true
    )
  ) into v_source_facts_available;

  if v_physical_count > 1 or v_evidence_count > 1
     or v_effective.blocker_code = 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then
    v_blocker_code := 'SETTLEMENT_SCOPE_NOT_UNIQUE';
    v_blocker_message := '该学生月份存在无法唯一解析的历史结算范围，不能保存草稿。';
  elsif v_effective.effective_status = 'ordinary_locked' then
    v_blocker_code := 'SETTLEMENT_ORDINARY_ALREADY_LOCKED';
    v_blocker_message := '该月份已正式锁定，只能查看。';
  elsif v_effective.effective_status = 'historically_consumed_immutable' then
    v_blocker_code := 'SETTLEMENT_HISTORICALLY_CONSUMED';
    v_blocker_message := '该月份已被历史账单或不可变事实消费，不能修改。';
  elsif v_effective.effective_status = 'historical_zero_carry_complete' then
    v_blocker_code := 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE';
    v_blocker_message := '该月份已通过历史零结转证据完成，只能查看。';
  elsif v_effective.effective_status is distinct from 'incomplete' then
    v_blocker_code := 'SETTLEMENT_NOT_INCOMPLETE';
    v_blocker_message := '该月份不是可保存草稿的普通未完成状态。';
  elsif v_physical_count <> 0 then
    v_blocker_code := 'SETTLEMENT_NOT_INCOMPLETE';
    v_blocker_message := '该月份已存在普通历史结算记录，不能保存新的草稿。';
  end if;

  if v_blocker_code is null then
    begin
      perform public.school_assert_tuition_settlement_month_mutable(
        p_student_id, p_year_month
      );
    exception when others then
      if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm) > 0 then
        v_blocker_code := 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED';
        v_blocker_message := '该月份已存在后继学费账单或不可变结算事实，不能保存新的月结草稿。';
      elsif position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm) > 0 then
        v_blocker_code := 'SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED';
        v_blocker_message := '该月份已被不可变学费事实消费，不能保存新的月结草稿。';
      else
        raise;
      end if;
    end;
  end if;

  if v_blocker_code is null then
    select exists (
      select 1
      from public.school_student_tuition_generation_revisions r
      join public.school_student_tuition_generation_identities g
        on g.id = r.generation_identity_id
      join public.school_student_tuition_bills b
        on b.id = r.tuition_bill_id
      where r.lifecycle_status = 'active'
        and g.student_id = p_student_id
        and g.business_entity_id = v_business_entity_id
        and g.billing_month = (
          to_date(p_year_month || '-01', 'YYYY-MM-DD') + interval '1 month'
        )::date
        and b.student_id = p_student_id
        and b.previous_settlement_month = p_year_month
        and b.app_type = 'school'
        and b.billing_role = 'canonical_charge'
        and b.cancelled_at is null
        and coalesce(b.status, '') <> 'cancelled'
    ) into v_active_successor;
    if v_active_successor then
      v_blocker_code := 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED';
      v_blocker_message := '该月份已存在后继学费账单或不可变结算事实，不能保存新的月结草稿。';
    end if;
  end if;

  if v_blocker_code is null then
    select exists (
      select 1
      from public.school_student_tuition_bills b
      where b.student_id = p_student_id
        and b.business_entity_id = v_business_entity_id
        and b.previous_settlement_month = p_year_month
        and b.app_type = 'school'
        and b.billing_role = 'canonical_charge'
        and b.cancelled_at is null
        and coalesce(b.status, '') <> 'cancelled'
    ) into v_current_entity_canonical_bill;
    if v_current_entity_canonical_bill then
      v_blocker_code := 'SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED';
      v_blocker_message := '该月份已存在后继学费账单或不可变结算事实，不能保存新的月结草稿。';
    end if;
  end if;

  if v_blocker_code is null then
    select exists (
      select 1
      from public.school_student_tuition_bills b
      where b.student_id = p_student_id
        and b.business_entity_id is distinct from v_business_entity_id
        and b.previous_settlement_month = p_year_month
        and b.app_type = 'school'
        and b.billing_role = 'canonical_charge'
        and b.cancelled_at is null
        and coalesce(b.status, '') <> 'cancelled'
    ) into v_cross_entity_canonical_bill;
    if v_cross_entity_canonical_bill then
      v_blocker_code := 'SETTLEMENT_SCOPE_NOT_UNIQUE';
      v_blocker_message := '该学生月份存在无法唯一解析的历史结算范围，不能保存草稿。';
    end if;
  end if;

  if v_blocker_code is null and exists (
    select 1
    from public.school_get_student_monthly_settlement_wage_blockers(
      p_year_month, p_student_id
    )
  ) then
    v_blocker_code := 'SETTLEMENT_WAGE_BLOCKED';
    v_blocker_message := '该月份已进入不可变工资链，不能保存新的月结草稿。';
  end if;

  if v_blocker_code is null and not v_source_facts_available then
    v_blocker_code := 'SETTLEMENT_SOURCE_FACTS_EMPTY';
    v_blocker_message := '该月份没有可用于月结的课时或收款来源，不能保存草稿。';
  end if;

  return jsonb_build_object(
    'contract_version', 'student_settlement_online_save_eligibility_v1',
    'student_id', p_student_id,
    'year_month', p_year_month,
    'business_entity_id', v_business_entity_id,
    'effective_state', jsonb_build_object(
      'effective_complete', v_effective.effective_complete,
      'effective_status', v_effective.effective_status,
      'source_type', v_effective.source_type,
      'source_id', v_effective.source_id,
      'carry_cny', v_effective.carry_cny
    ),
    'source_facts_available', v_source_facts_available,
    'can_save', v_blocker_code is null,
    'save_blocker_code', v_blocker_code,
    'save_blocker_message', v_blocker_message
  );
end
$function$;

revoke all on function public.school_get_student_settlement_online_save_eligibility_core(
  uuid, text
) from public, anon, authenticated, service_role;

comment on function public.school_get_student_settlement_online_save_eligibility_core(
  uuid, text
) is 'Owner-only Phase C-R1 structural eligibility source shared by online status and the online save/lock guard. Reads existing effective state, immutable tuition/wage facts and exact writer source-fact availability; performs no business DML and adds no month-close rule.';

create or replace function public.school_assert_student_monthly_settlement_online_writable(
  p_student_id uuid,
  p_year_month text,
  p_business_entity_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_eligibility jsonb;
  v_code text;
begin
  v_eligibility := public.school_get_student_settlement_online_save_eligibility_core(
    p_student_id, p_year_month
  );
  if p_business_entity_id is null
     or p_business_entity_id is distinct from
       (v_eligibility->>'business_entity_id')::uuid then
    raise exception using errcode = 'P0001', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;
  if coalesce((v_eligibility->>'can_save')::boolean, false) then
    return;
  end if;
  v_code := coalesce(
    nullif(v_eligibility->>'save_blocker_code', ''),
    'SETTLEMENT_ONLINE_SAVE_STRUCTURALLY_BLOCKED'
  );
  raise exception using errcode = 'P0001', message = v_code;
end
$function$;

revoke all on function public.school_assert_student_monthly_settlement_online_writable(
  uuid, text, uuid, text
) from public, anon, authenticated, service_role;

comment on function public.school_assert_student_monthly_settlement_online_writable(
  uuid, text, uuid, text
) is 'Owner-only online save/lock structural guard. Delegates to the single Phase C-R1 eligibility source before Preview or draft writes and raises its stable blocker code.';

create or replace function public.school_get_student_monthly_settlement_online_status_core(
  p_student_id uuid,
  p_year_month text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_eligibility jsonb;
  v_business_entity_id uuid;
  v_effective jsonb;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_source public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment public.school_student_settlement_adjustment_drafts%rowtype;
  v_preview jsonb;
  v_source_mode text;
  v_adjustment_mode text;
  v_explicit_amount numeric;
  v_blocker_code text;
  v_blocker_message text;
  v_can_save boolean := false;
  v_can_lock boolean := false;
  v_requires_repreview boolean := true;
  v_lock_blocker_code text;
  v_lock_blocker_message text;
begin
  v_eligibility := public.school_get_student_settlement_online_save_eligibility_core(
    p_student_id, p_year_month
  );
  v_business_entity_id := (v_eligibility->>'business_entity_id')::uuid;
  if v_business_entity_id is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;
  v_effective := v_eligibility->'effective_state';
  v_blocker_code := nullif(v_eligibility->>'save_blocker_code', '');
  v_blocker_message := nullif(v_eligibility->>'save_blocker_message', '');
  v_can_save := coalesce((v_eligibility->>'can_save')::boolean, false);

  select * into v_settlement
  from public.school_student_monthly_settlements s
  where s.student_id = p_student_id and s.year_month = p_year_month
  order by s.updated_at desc, s.id
  limit 1;

  select * into v_source
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month
    and (
      d.status = 'active'
      or (v_settlement.id is not null and d.status = 'consumed'
        and d.settlement_id = v_settlement.id)
    )
  order by case when d.status = 'active' then 0 else 1 end,
    d.updated_at desc, d.id
  limit 1;

  select * into v_adjustment
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month
    and (
      d.status = 'active'
      or (v_settlement.id is not null and d.status = 'consumed'
        and d.settlement_id = v_settlement.id)
    )
  order by case when d.status = 'active' then 0 else 1 end,
    d.updated_at desc, d.id
  limit 1;

  v_source_mode := coalesce(
    v_source.source_treatment_mode, v_settlement.source_treatment_mode,
    'separate_makeup_and_overage_v1'
  );
  v_adjustment_mode := coalesce(v_adjustment.adjustment_source, 'carry_final_balance');
  v_explicit_amount := case when v_adjustment_mode = 'manual_adjustment'
    then v_adjustment.adjustment_amount_cny else null end;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    v_source_mode, v_source.settlement_exchange_rate,
    v_source.settlement_exchange_rate_source,
    v_source.settlement_exchange_rate_effective_date,
    v_adjustment_mode, v_explicit_amount
  );

  v_requires_repreview := not (
    v_can_save
    and v_source.id is not null and v_source.status = 'active'
    and v_adjustment.id is not null and v_adjustment.status = 'active'
    and v_source.source_manifest_sha256 is not distinct from
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256'
    and v_source.source_count is not distinct from
      (v_preview->'preview'->>'lesson_variance_source_count')::integer
    and v_adjustment.adjustment_amount_cny is not distinct from
      (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric
  );
  v_can_lock := v_can_save and not v_requires_repreview;
  if v_blocker_code is not null then
    v_lock_blocker_code := v_blocker_code;
    v_lock_blocker_message := v_blocker_message;
  elsif v_requires_repreview then
    v_lock_blocker_code := 'SETTLEMENT_REPREVIEW_REQUIRED';
    v_lock_blocker_message := '正式锁定前必须先保存与DB权威预览一致的草稿。';
  end if;

  return jsonb_build_object(
    'contract_version', 'student_settlement_online_status_v1',
    'student_id', p_student_id,
    'year_month', p_year_month,
    'business_entity_id', v_business_entity_id,
    'effective_state', v_effective,
    'physical_settlement', jsonb_build_object(
      'settlement_id', v_settlement.id,
      'settlement_status', v_settlement.settlement_status,
      'locked_at', v_settlement.locked_at
    ),
    'source_treatment_draft', jsonb_build_object(
      'draft_id', v_source.id,
      'status', v_source.status,
      'updated_at', v_source.updated_at,
      'source_treatment_mode', v_source.source_treatment_mode,
      'settlement_exchange_rate', v_source.settlement_exchange_rate,
      'settlement_exchange_rate_source', v_source.settlement_exchange_rate_source,
      'settlement_exchange_rate_effective_date', v_source.settlement_exchange_rate_effective_date,
      'source_manifest_sha256', v_source.source_manifest_sha256,
      'source_count', v_source.source_count
    ),
    'adjustment_draft', jsonb_build_object(
      'draft_id', v_adjustment.id,
      'status', v_adjustment.status,
      'updated_at', v_adjustment.updated_at,
      'adjustment_mode', v_adjustment.adjustment_source,
      'adjustment_amount_cny', v_adjustment.adjustment_amount_cny,
      'reason', v_adjustment.adjustment_reason,
      'note', v_adjustment.note
    ),
    'preview_manifest_sha256', v_preview->>'preview_manifest_sha256',
    'lesson_manifest_sha256',
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    'authoritative_preview', v_preview->'preview',
    'authoritative_system_difference_cny',
      (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    'resolved_adjustment_amount_cny',
      (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric,
    'final_carryover_cny',
      (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    'source_facts_available',
      coalesce((v_eligibility->>'source_facts_available')::boolean, false),
    'immutable_blocker', case when v_blocker_code is null then null else
      jsonb_build_object('code', v_blocker_code, 'detail', v_blocker_message) end,
    'can_save', v_can_save,
    'save_blocker_code', v_blocker_code,
    'save_blocker_message', v_blocker_message,
    'can_lock', v_can_lock,
    'lock_blocker_code', v_lock_blocker_code,
    'lock_blocker_message', v_lock_blocker_message,
    'requires_repreview', v_requires_repreview
  );
end
$function$;

revoke all on function public.school_get_student_monthly_settlement_online_status_core(
  uuid, text
) from public, anon, authenticated, service_role;

comment on function public.school_get_student_monthly_settlement_online_status_core(
  uuid, text
) is 'Owner-only Phase C-R1 status core. Preserves the status_v1 shape, adds save/lock blocker fields, and consumes the same structural eligibility source as online save/lock before returning DB-authoritative Preview facts.';

\if :{?C_R1_REHEARSAL}
rollback;
\else
commit;
\endif
