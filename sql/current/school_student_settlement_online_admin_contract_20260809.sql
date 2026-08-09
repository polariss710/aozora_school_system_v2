-- School V2 student monthly settlement online admin DB contract, Phase A.
-- Status: reviewed migration; production execution is recorded in the report.
--
-- Business-model expansion declaration
-- New tables: none.
-- New columns: none.
-- New enum/status values: none.
-- New date/month/attribution concepts: none.
-- New identity concepts: none; auth.users + school_app_memberships remain authoritative.
-- New source concepts: none.
-- New snapshot/version concepts: none; existing draft UUID + updated_at remain the version facts.
-- New writable facts: none.
-- Changed existing-field semantics: none.
-- Changed field mutability: none.
-- Changed writer/reader authority: the explicitly approved online wrappers are service_role-only;
--   the versioned status reader is authenticated active-membership-only.
-- Changed locking rules: the explicitly approved online wrappers hold the actor membership row,
--   existing settlement scope lock, and exact draft-version checks in one transaction.
-- New authoritative sources: none.
-- Legacy fallbacks or dual-read rules: none.
-- Dual-write behavior: none.
-- Historical reinterpretation: none.
-- Destructive schema changes: none.
-- Approval reference: current Phase A task sections I, V-XIII and XVII.

\set ON_ERROR_STOP on
\pset pager off
\if :{?phase_a_rollback}
\else
  \set phase_a_rollback false
\endif

begin;
set local lock_timeout = '8s';
set local statement_timeout = '240s';

do $preflight$
declare
  v_core record;
begin
  if to_regclass('public.school_app_memberships') is null
     or to_regclass('public.school_student_monthly_settlements') is null
     or to_regclass('public.school_student_settlement_source_treatment_drafts') is null
     or to_regclass('public.school_student_settlement_adjustment_drafts') is null then
    raise exception 'SETTLEMENT_ONLINE_PREFLIGHT_OBJECTS_MISSING';
  end if;

  for v_core in
    select * from (values
      ('public.school_lock_student_monthly_settlement(uuid,text,text)',
       'f9d85d62be938c5c92b2feb047616c3c'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
       '9b68480b55736c0602b28f637dcdc7a1'),
      ('public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)',
       '5982596c31fa6cbf6c99df0cc5bee732'),
      ('public.school_unlock_student_monthly_settlement(uuid,text)',
       '653356cc5c9c75b584d0d5cc5104397f'),
      ('public.school_relock_student_monthly_settlement(uuid,text)',
       '6357848be1eb6c1cf11016d01cad14cb'),
      ('public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
       '5296dbdc64dbe2f36ccae242c5740a1c'),
      ('public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamp with time zone,uuid,timestamp with time zone,text,text,text)',
       'd9e07d2f330f34637fafb570743a5a59'),
      ('public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)',
       'a32fdb7e743e10a81712a15d99019246'),
      ('public.school_preview_student_settlement_adjustment_dialog(uuid,uuid,text,text,numeric,text,date,text,numeric)',
       '44c998671550d2288c7f4960d6d52fdc')
    ) expected(signature, definition_md5)
  loop
    if to_regprocedure(v_core.signature) is null
       or md5(pg_get_functiondef(to_regprocedure(v_core.signature))) <> v_core.definition_md5 then
      raise exception 'SETTLEMENT_ONLINE_PREFLIGHT_DEFINITION_DRIFT:%', v_core.signature;
    end if;
  end loop;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r on r.oid = p.proowner
    where n.nspname = 'public'
      and p.proname in (
        'school_lock_student_monthly_settlement',
        'school_set_student_monthly_settlement_draft_adjustment',
        'school_set_student_settlement_source_treatment_draft',
        'school_unlock_student_monthly_settlement',
        'school_relock_student_monthly_settlement'
      )
      and (
        r.rolname <> 'postgres'
        or not p.prosecdef
        or p.proconfig is distinct from array['search_path=pg_catalog, public']::text[]
        or has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('service_role', p.oid, 'EXECUTE')
        or exists (
          select 1
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where a.grantee = 0 and a.privilege_type = 'EXECUTE'
        )
      )
  ) then
    raise exception 'SETTLEMENT_ONLINE_PREFLIGHT_CORE_ACL_DRIFT';
  end if;

  if has_table_privilege('anon', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_monthly_settlements', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('anon', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_settlement_adjustment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('anon', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role', 'public.school_student_settlement_source_treatment_drafts', 'INSERT,UPDATE,DELETE') then
    raise exception 'SETTLEMENT_ONLINE_PREFLIGHT_TABLE_DML_EXPOSED';
  end if;
end
$preflight$;

create or replace function public.school_get_student_monthly_settlement_wage_blockers(
  p_year_month text,
  p_student_id uuid default null
)
returns table (
  student_id uuid,
  year_month text,
  wage_business_names text,
  active_wage_lock_count integer,
  wage_detail_count integer,
  payment_request_count integer,
  paid_payment_request_count integer,
  expense_count integer,
  account_transaction_count integer,
  blocker_level text,
  blocker_reason text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with active_links as (
    select l.student_id, p_year_month as year_month, w.id as wage_lock_id,
      d.id as wage_detail_id,
      coalesce(nullif(trim(w.business_name), ''), '未设置业务归属') as wage_business_name,
      pr.id as payment_request_id, pr.status as payment_request_status,
      e.id as expense_id, atx.id as account_transaction_id
    from public.school_list_r1d_e_c_student_month_lessons(
      p_student_id, p_year_month
    ) resolved
    join public.school_lesson_records l
      on l.id = resolved.lesson_id and l.lesson_type = 'actual'
    join public.school_teacher_wage_lock_details d
      on d.lesson_record_id = l.id
    join public.school_teacher_wage_locks w on w.id = d.lock_id
    left join public.school_payment_requests pr
      on pr.source_type = 'teacher_wage' and pr.source_id = w.id
    left join public.school_expense_records e
      on e.expense_category = 'teacher_wage'
     and (e.id = pr.paid_expense_id or e.salary_payment_id = pr.id)
    left join public.school_account_transactions atx
      on atx.id = pr.paid_account_transaction_id
      or (atx.related_table = 'school_expense_records' and atx.related_id = e.id)
      or (atx.related_table = 'school_payment_requests' and atx.related_id = pr.id)
    where l.student_id is not null
      and coalesce(w.status, '') <> 'void'
      and w.voided_at is null
      and coalesce(d.is_no_wage, false) = false
      and coalesce(d.settlement_type, '') <> 'no_wage'
  ), aggregated as (
    select al.student_id, al.year_month,
      string_agg(distinct al.wage_business_name, '、') as wage_business_names,
      count(distinct al.wage_lock_id)::integer as active_wage_lock_count,
      count(distinct al.wage_detail_id)::integer as wage_detail_count,
      count(distinct al.payment_request_id)::integer as payment_request_count,
      count(distinct al.payment_request_id) filter (
        where al.payment_request_status = 'paid'
      )::integer as paid_payment_request_count,
      count(distinct al.expense_id)::integer as expense_count,
      count(distinct al.account_transaction_id)::integer as account_transaction_count
    from active_links al
    group by al.student_id, al.year_month
  )
  select a.student_id, a.year_month, a.wage_business_names,
    a.active_wage_lock_count, a.wage_detail_count, a.payment_request_count,
    a.paid_payment_request_count, a.expense_count, a.account_transaction_count,
    case
      when a.account_transaction_count > 0 or a.expense_count > 0
        or a.paid_payment_request_count > 0 then 'payment_completed'
      when a.payment_request_count > 0 then 'payment_requested'
      else 'wage_snapshot'
    end,
    case
      when a.account_transaction_count > 0 or a.expense_count > 0
        or a.paid_payment_request_count > 0 then format(
          '老师工资已支付，涉及%s个工资快照、%s条工资明细、%s个支付请求、%s条支出、%s条账户流水。',
          a.active_wage_lock_count, a.wage_detail_count,
          a.payment_request_count, a.expense_count, a.account_transaction_count
        )
      when a.payment_request_count > 0 then format(
        '已生成工资支付请求，涉及%s个工资快照、%s条工资明细、%s个支付请求。',
        a.active_wage_lock_count, a.wage_detail_count, a.payment_request_count
      )
      else format(
        '已生成老师工资快照，涉及%s个工资快照、%s条工资明细。',
        a.active_wage_lock_count, a.wage_detail_count
      )
    end
  from aggregated a
  where a.active_wage_lock_count > 0
$function$;

create or replace function public.school_assert_student_monthly_settlement_no_wage_blocker(
  p_student_id uuid,
  p_year_month text,
  p_action text default '变更学生月度结算'
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_blocker record;
begin
  perform count(*)
  from public.school_list_r1d_e_c_student_month_lessons(
    p_student_id, p_year_month
  );

  select * into v_blocker
  from public.school_get_student_monthly_settlement_wage_blockers(
    p_year_month, p_student_id
  )
  limit 1;

  if found then
    raise exception '%已被后续老师工资链路引用：% 请先按受控流程处理老师工资快照/支付请求，不能从学生月度结算侧间接改动已进入工资链路的课时。',
      coalesce(nullif(trim(p_action), ''), '变更学生月度结算'),
      v_blocker.blocker_reason;
  end if;
end
$function$;

create or replace function public.school_assert_student_settlement_online_admin(
  p_actor_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid;
begin
  if p_actor_user_id is null then
    raise exception using errcode = '42501', message = 'SETTLEMENT_ADMIN_REQUIRED';
  end if;

  select m.user_id into v_actor
  from public.school_app_memberships m
  join auth.users u on u.id = m.user_id
  where m.user_id = p_actor_user_id
    and m.is_active
    and m.role = 'admin'
  for share of m;

  if v_actor is null then
    raise exception using errcode = '42501', message = 'SETTLEMENT_ADMIN_REQUIRED';
  end if;
end
$function$;

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
  v_effective record;
  v_physical_count integer;
  v_evidence_count integer;
  v_wage_blocker record;
begin
  if p_student_id is null or p_business_entity_id is null
     or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  select count(*) into v_physical_count
  from public.school_student_monthly_settlements s
  where s.student_id = p_student_id and s.year_month = p_year_month;
  select count(*) into v_evidence_count
  from public.school_student_monthly_settlement_historical_completion_evidenc e
  where e.student_id = p_student_id and e.settlement_month = p_year_month;
  if v_physical_count > 1 or v_evidence_count > 1 then
    raise exception 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  select * into strict v_effective
  from public.school_resolve_student_monthly_settlement_effective_state(
    p_student_id, p_year_month, p_business_entity_id
  );

  if v_effective.effective_status = 'ordinary_locked' then
    raise exception 'SETTLEMENT_ORDINARY_ALREADY_LOCKED';
  elsif v_effective.effective_status = 'historically_consumed_immutable' then
    raise exception 'SETTLEMENT_HISTORICALLY_CONSUMED';
  elsif v_effective.effective_status = 'historical_zero_carry_complete' then
    raise exception 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE';
  elsif v_effective.effective_status is distinct from 'incomplete' then
    raise exception 'SETTLEMENT_NOT_INCOMPLETE';
  end if;

  if v_effective.blocker_code = 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then
    raise exception 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;
  if v_physical_count <> 0 then
    raise exception 'SETTLEMENT_NOT_INCOMPLETE';
  end if;

  begin
    perform public.school_assert_tuition_settlement_month_mutable(
      p_student_id, p_year_month
    );
  exception when others then
    if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm) > 0 then
      raise exception 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED';
    elsif position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm) > 0 then
      raise exception 'SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED';
    else
      raise;
    end if;
  end;

  select * into v_wage_blocker
  from public.school_get_student_monthly_settlement_wage_blockers(
    p_year_month, p_student_id
  )
  limit 1;
  if found then
    raise exception 'SETTLEMENT_WAGE_BLOCKED';
  end if;
end
$function$;

create or replace function public.school_assert_student_settlement_online_expected_facts(
  p_preview jsonb,
  p_expected_preview_manifest_sha256 text,
  p_expected_lesson_variance_manifest_sha256 text,
  p_expected_source_count integer,
  p_expected_unused_planned_credit_jpy numeric,
  p_expected_overage_charge_jpy numeric,
  p_expected_net_lesson_variance_jpy numeric,
  p_expected_net_lesson_variance_cny numeric,
  p_expected_system_difference_cny numeric,
  p_expected_final_carryover_cny numeric
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_preview is null
     or p_preview->>'preview_manifest_sha256'
          is distinct from p_expected_preview_manifest_sha256 then
    raise exception 'SETTLEMENT_PREVIEW_MANIFEST_STALE';
  end if;
  if p_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256'
       is distinct from p_expected_lesson_variance_manifest_sha256 then
    raise exception 'SETTLEMENT_LESSON_MANIFEST_STALE';
  end if;
  if (p_preview->'preview'->>'lesson_variance_source_count')::integer
       is distinct from p_expected_source_count
     or (p_preview->'preview'->>'unused_planned_credit_jpy')::numeric
       is distinct from p_expected_unused_planned_credit_jpy
     or (p_preview->'preview'->>'overage_charge_jpy')::numeric
       is distinct from p_expected_overage_charge_jpy
     or (p_preview->'preview'->>'net_lesson_variance_jpy')::numeric
       is distinct from p_expected_net_lesson_variance_jpy
     or (p_preview->'preview'->>'net_lesson_variance_cny')::numeric
       is distinct from p_expected_net_lesson_variance_cny
     or (p_preview->'preview_expected_facts'->>'system_difference_cny')::numeric
       is distinct from p_expected_system_difference_cny
     or (p_preview->'preview'->>'projected_final_carryover_cny')::numeric
       is distinct from p_expected_final_carryover_cny then
    raise exception 'SETTLEMENT_EXPECTED_FACTS_MISMATCH';
  end if;
end
$function$;

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
  v_business_entity_id uuid;
  v_effective record;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_source public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment public.school_student_settlement_adjustment_drafts%rowtype;
  v_preview jsonb;
  v_source_mode text;
  v_adjustment_mode text;
  v_explicit_amount numeric;
  v_blocker_code text;
  v_blocker_detail text;
  v_can_save boolean := false;
  v_can_lock boolean := false;
  v_requires_repreview boolean := true;
  v_mutable boolean := true;
begin
  if p_student_id is null or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school';
  if v_business_entity_id is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  select * into strict v_effective
  from public.school_resolve_student_monthly_settlement_effective_state(
    p_student_id, p_year_month, v_business_entity_id
  );

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

  if v_effective.effective_status = 'ordinary_locked' then
    v_blocker_code := 'SETTLEMENT_ORDINARY_ALREADY_LOCKED';
    v_blocker_detail := '该学生月份已正式锁定。';
  elsif v_effective.effective_status = 'historically_consumed_immutable' then
    v_blocker_code := 'SETTLEMENT_HISTORICALLY_CONSUMED';
    v_blocker_detail := '该学生月份已被历史学费事实消费，只能只读查看。';
  elsif v_effective.effective_status = 'historical_zero_carry_complete' then
    v_blocker_code := 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE';
    v_blocker_detail := '该学生月份已通过历史零结转完成证据结清。';
  elsif v_effective.blocker_code = 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then
    v_blocker_code := 'SETTLEMENT_SCOPE_NOT_UNIQUE';
    v_blocker_detail := '该学生月份存在其他业务归属下的完成事实。';
  elsif v_settlement.id is not null then
    v_blocker_code := 'SETTLEMENT_NOT_INCOMPLETE';
    v_blocker_detail := '该scope存在普通历史settlement，不能走在线普通锁定流程。';
  else
    begin
      perform public.school_assert_tuition_settlement_month_mutable(
        p_student_id, p_year_month
      );
    exception when others then
      v_mutable := false;
      if position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm) > 0 then
        v_blocker_code := 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED';
        v_blocker_detail := '该月份已被后继学费revision冻结。';
      elsif position('TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' in sqlerrm) > 0 then
        v_blocker_code := 'SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED';
        v_blocker_detail := '该月份已被不可变学费事实消费。';
      else
        raise;
      end if;
    end;
    if v_mutable and exists (
      select 1
      from public.school_get_student_monthly_settlement_wage_blockers(
        p_year_month, p_student_id
      )
    ) then
      v_blocker_code := 'SETTLEMENT_WAGE_BLOCKED';
      v_blocker_detail := '该月份已进入非no_wage老师工资不可变链。';
    end if;
  end if;

  v_requires_repreview := not (
    v_effective.effective_status = 'incomplete'
    and v_blocker_code is null
    and v_source.id is not null and v_source.status = 'active'
    and v_adjustment.id is not null and v_adjustment.status = 'active'
    and v_source.source_manifest_sha256 is not distinct from
      v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256'
    and v_source.source_count is not distinct from
      (v_preview->'preview'->>'lesson_variance_source_count')::integer
    and v_adjustment.adjustment_amount_cny is not distinct from
      (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric
  );
  v_can_save := v_effective.effective_status = 'incomplete'
    and v_blocker_code is null;
  v_can_lock := v_can_save and not v_requires_repreview;

  return jsonb_build_object(
    'contract_version', 'student_settlement_online_status_v1',
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
    'immutable_blocker', case when v_blocker_code is null then null else
      jsonb_build_object('code', v_blocker_code, 'detail', v_blocker_detail) end,
    'can_save', v_can_save,
    'can_lock', v_can_lock,
    'requires_repreview', v_requires_repreview
  );
end
$function$;

create or replace function public.school_get_student_monthly_settlement_online_status(
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
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1
    from public.school_app_memberships m
    where m.user_id = v_actor
      and m.is_active
      and m.role in ('admin', 'operator', 'read_only')
  ) then
    raise exception using errcode = '42501',
      message = 'SETTLEMENT_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  return public.school_get_student_monthly_settlement_online_status_core(
    p_student_id, p_year_month
  );
end
$function$;

create or replace function public.school_save_student_monthly_settlement_draft_online_admin(
  p_actor_user_id uuid,
  p_student_id uuid,
  p_year_month text,
  p_source_treatment_mode text,
  p_settlement_exchange_rate numeric,
  p_settlement_exchange_rate_source text,
  p_settlement_exchange_rate_effective_date date,
  p_adjustment_mode text,
  p_explicit_user_amount_cny numeric,
  p_reason text,
  p_note text,
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
  p_request_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_business_entity_id uuid;
  v_preview jsonb;
  v_after jsonb;
  v_source public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment public.school_student_settlement_adjustment_drafts%rowtype;
  v_source_matches boolean;
  v_adjustment_matches boolean;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_resolved_adjustment numeric;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SETTLEMENT_TRUSTED_EDGE_ROLE_REQUIRED';
  end if;
  perform public.school_assert_student_settlement_online_admin(p_actor_user_id);
  if p_student_id is null or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or v_reason is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_INPUT_INVALID';
  end if;

  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school'
  for share;
  if v_business_entity_id is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  begin
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      p_student_id, v_business_entity_id, p_year_month
    );
  exception when lock_not_available or deadlock_detected then
    raise exception using errcode = '55P03', message = 'SETTLEMENT_SCOPE_BUSY';
  end;
  perform public.school_assert_student_monthly_settlement_online_writable(
    p_student_id, p_year_month, v_business_entity_id, 'save_draft'
  );

  select * into v_source
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active'
  for update;
  select * into v_adjustment
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active'
  for update;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    p_source_treatment_mode, p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode, p_explicit_user_amount_cny
  );
  perform public.school_assert_student_settlement_online_expected_facts(
    v_preview, p_expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256, p_expected_source_count,
    p_expected_unused_planned_credit_jpy, p_expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy, p_expected_net_lesson_variance_cny,
    p_expected_system_difference_cny, p_expected_final_carryover_cny
  );
  v_resolved_adjustment :=
    (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric;

  v_source_matches := v_source.id is not null
    and v_source.source_treatment_mode is not distinct from
      v_preview->'preview_expected_facts'->>'source_treatment_mode'
    and v_source.settlement_exchange_rate is not distinct from
      (v_preview->'preview_expected_facts'->>'settlement_exchange_rate')::numeric
    and v_source.settlement_exchange_rate_source is not distinct from
      nullif(v_preview->'preview_expected_facts'->>'settlement_exchange_rate_source', '')
    and v_source.settlement_exchange_rate_effective_date is not distinct from
      (v_preview->'preview_expected_facts'->>'settlement_exchange_rate_effective_date')::date
    and v_source.source_manifest_sha256 is not distinct from
      p_expected_lesson_variance_manifest_sha256
    and v_source.source_count is not distinct from p_expected_source_count
    and v_source.reason is not distinct from v_reason;

  v_adjustment_matches := v_adjustment.id is not null
    and v_adjustment.adjustment_source is not distinct from
      v_preview->'preview_expected_facts'->>'adjustment_mode'
    and v_adjustment.adjustment_amount_cny is not distinct from v_resolved_adjustment
    and v_adjustment.adjustment_reason is not distinct from v_reason
    and v_adjustment.note is not distinct from v_note;

  if v_source_matches and v_adjustment_matches then
    return jsonb_build_object(
      'ok', true, 'idempotent', true,
      'operation', 'save_student_settlement_draft_online_admin_v1',
      'operator_authority', 'authenticated_active_admin_edge_v1',
      'request_correlation_id', p_request_correlation_id,
      'actor_user_id', p_actor_user_id,
      'student_id', p_student_id, 'year_month', p_year_month,
      'business_entity_id', v_business_entity_id,
      'source_treatment_draft_id', v_source.id,
      'source_treatment_draft_updated_at', v_source.updated_at,
      'adjustment_draft_id', v_adjustment.id,
      'adjustment_draft_updated_at', v_adjustment.updated_at,
      'preview_manifest_sha256', p_expected_preview_manifest_sha256,
      'lesson_variance_manifest_sha256', p_expected_lesson_variance_manifest_sha256,
      'authoritative_preview', v_preview,
      'effective_status', 'incomplete'
    );
  end if;

  if not v_source_matches and (
    v_source.id is distinct from p_expected_source_treatment_draft_id
    or (v_source.id is not null and v_source.updated_at is distinct from
      p_expected_source_treatment_draft_updated_at)
  ) then
    raise exception 'SETTLEMENT_SOURCE_DRAFT_STALE';
  end if;
  if not v_adjustment_matches and (
    v_adjustment.id is distinct from p_expected_adjustment_draft_id
    or (v_adjustment.id is not null and v_adjustment.updated_at is distinct from
      p_expected_adjustment_draft_updated_at)
  ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_DRAFT_STALE';
  end if;

  if not v_source_matches then
    perform *
    from public.school_set_student_settlement_source_treatment_draft(
      p_student_id, p_year_month, p_source_treatment_mode,
      p_settlement_exchange_rate, p_settlement_exchange_rate_source,
      p_settlement_exchange_rate_effective_date, v_reason
    );
  end if;
  if not v_adjustment_matches then
    perform *
    from public.school_set_student_monthly_settlement_draft_adjustment(
      p_student_id, p_year_month, p_explicit_user_amount_cny,
      p_adjustment_mode, v_reason, v_note
    );
  end if;

  select * into strict v_source
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active';
  select * into strict v_adjustment
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active';

  v_after := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    p_source_treatment_mode, p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode, p_explicit_user_amount_cny
  );
  perform public.school_assert_student_settlement_online_expected_facts(
    v_after, p_expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256, p_expected_source_count,
    p_expected_unused_planned_credit_jpy, p_expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy, p_expected_net_lesson_variance_cny,
    p_expected_system_difference_cny, p_expected_final_carryover_cny
  );
  if v_source.source_manifest_sha256 is distinct from
       p_expected_lesson_variance_manifest_sha256
     or v_source.source_count is distinct from p_expected_source_count
     or v_adjustment.adjustment_amount_cny is distinct from
       (v_after->'preview'->>'projected_adjustment_amount_cny')::numeric then
    raise exception 'SETTLEMENT_EXPECTED_FACTS_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok', true, 'idempotent', false,
    'operation', 'save_student_settlement_draft_online_admin_v1',
    'operator_authority', 'authenticated_active_admin_edge_v1',
    'request_correlation_id', p_request_correlation_id,
    'actor_user_id', p_actor_user_id,
    'student_id', p_student_id, 'year_month', p_year_month,
    'business_entity_id', v_business_entity_id,
    'source_treatment_draft_id', v_source.id,
    'source_treatment_draft_updated_at', v_source.updated_at,
    'adjustment_draft_id', v_adjustment.id,
    'adjustment_draft_updated_at', v_adjustment.updated_at,
    'preview_manifest_sha256', p_expected_preview_manifest_sha256,
    'lesson_variance_manifest_sha256', p_expected_lesson_variance_manifest_sha256,
    'authoritative_preview', v_after,
    'effective_status', 'incomplete'
  );
end
$function$;

create or replace function public.school_lock_student_monthly_settlement_online_admin(
  p_actor_user_id uuid,
  p_student_id uuid,
  p_year_month text,
  p_expected_source_treatment_draft_id uuid,
  p_expected_source_treatment_draft_updated_at timestamptz,
  p_expected_adjustment_draft_id uuid,
  p_expected_adjustment_draft_updated_at timestamptz,
  p_expected_preview_manifest_sha256 text,
  p_expected_lesson_variance_manifest_sha256 text,
  p_expected_source_count integer,
  p_expected_unused_planned_credit_jpy numeric,
  p_expected_overage_charge_jpy numeric,
  p_expected_net_lesson_variance_jpy numeric,
  p_expected_net_lesson_variance_cny numeric,
  p_expected_system_difference_cny numeric,
  p_expected_final_carryover_cny numeric,
  p_note text,
  p_request_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_business_entity_id uuid;
  v_effective record;
  v_source public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment public.school_student_settlement_adjustment_drafts%rowtype;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_preview jsonb;
  v_lock record;
  v_adjustment_mode text;
  v_explicit_amount numeric;
  v_canonical_confirmation text;
  v_idempotent boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SETTLEMENT_TRUSTED_EDGE_ROLE_REQUIRED';
  end if;
  perform public.school_assert_student_settlement_online_admin(p_actor_user_id);
  if p_student_id is null or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_expected_source_treatment_draft_id is null
     or p_expected_source_treatment_draft_updated_at is null
     or p_expected_adjustment_draft_id is null
     or p_expected_adjustment_draft_updated_at is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_INPUT_INVALID';
  end if;

  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school'
  for share;
  if v_business_entity_id is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  begin
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      p_student_id, v_business_entity_id, p_year_month
    );
  exception when lock_not_available or deadlock_detected then
    raise exception using errcode = '55P03', message = 'SETTLEMENT_SCOPE_BUSY';
  end;
  select * into strict v_effective
  from public.school_resolve_student_monthly_settlement_effective_state(
    p_student_id, p_year_month, v_business_entity_id
  );

  if v_effective.effective_status in (
    'historically_consumed_immutable', 'historical_zero_carry_complete'
  ) then
    if v_effective.effective_status = 'historically_consumed_immutable' then
      raise exception 'SETTLEMENT_HISTORICALLY_CONSUMED';
    else
      raise exception 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE';
    end if;
  end if;

  if v_effective.effective_status = 'ordinary_locked' then
    select * into strict v_settlement
    from public.school_student_monthly_settlements s
    where s.id = v_effective.source_id and s.settlement_status = 'locked';
    select * into v_source
    from public.school_student_settlement_source_treatment_drafts d
    where d.id = p_expected_source_treatment_draft_id
      and d.settlement_id = v_settlement.id and d.status = 'consumed';
    select * into v_adjustment
    from public.school_student_settlement_adjustment_drafts d
    where d.id = p_expected_adjustment_draft_id
      and d.settlement_id = v_settlement.id and d.status = 'consumed';
    if v_source.id is null or v_adjustment.id is null
       or p_expected_source_treatment_draft_updated_at < v_source.created_at
       or p_expected_source_treatment_draft_updated_at > v_source.consumed_at
       or p_expected_adjustment_draft_updated_at < v_adjustment.created_at
       or p_expected_adjustment_draft_updated_at > v_adjustment.consumed_at then
      raise exception 'SETTLEMENT_LOCK_CONFLICT';
    end if;
    v_idempotent := true;
  elsif v_effective.effective_status = 'incomplete' then
    perform public.school_assert_student_monthly_settlement_online_writable(
      p_student_id, p_year_month, v_business_entity_id, 'lock'
    );
    select * into v_source
    from public.school_student_settlement_source_treatment_drafts d
    where d.student_id = p_student_id
      and d.business_entity_id = v_business_entity_id
      and d.year_month = p_year_month and d.status = 'active'
    for update;
    if v_source.id is null
       or v_source.id is distinct from p_expected_source_treatment_draft_id
       or v_source.updated_at is distinct from
         p_expected_source_treatment_draft_updated_at then
      raise exception 'SETTLEMENT_SOURCE_DRAFT_STALE';
    end if;
    select * into v_adjustment
    from public.school_student_settlement_adjustment_drafts d
    where d.student_id = p_student_id
      and d.business_entity_id = v_business_entity_id
      and d.year_month = p_year_month and d.status = 'active'
    for update;
    if v_adjustment.id is null
       or v_adjustment.id is distinct from p_expected_adjustment_draft_id
       or v_adjustment.updated_at is distinct from
         p_expected_adjustment_draft_updated_at then
      raise exception 'SETTLEMENT_ADJUSTMENT_DRAFT_STALE';
    end if;
  else
    raise exception 'SETTLEMENT_NOT_INCOMPLETE';
  end if;

  v_adjustment_mode := v_adjustment.adjustment_source;
  v_explicit_amount := case when v_adjustment_mode = 'manual_adjustment'
    then v_adjustment.adjustment_amount_cny else null end;
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    v_source.source_treatment_mode, v_source.settlement_exchange_rate,
    v_source.settlement_exchange_rate_source,
    v_source.settlement_exchange_rate_effective_date,
    v_adjustment_mode, v_explicit_amount
  );
  perform public.school_assert_student_settlement_online_expected_facts(
    v_preview, p_expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256, p_expected_source_count,
    p_expected_unused_planned_credit_jpy, p_expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy, p_expected_net_lesson_variance_cny,
    p_expected_system_difference_cny, p_expected_final_carryover_cny
  );
  if v_source.source_manifest_sha256 is distinct from
       p_expected_lesson_variance_manifest_sha256
     or v_source.source_count is distinct from p_expected_source_count
     or v_adjustment.adjustment_amount_cny is distinct from
       (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric then
    raise exception 'SETTLEMENT_LOCK_CONFLICT';
  end if;

  v_canonical_confirmation := format(
    'LOCK ONLINE STUDENT SETTLEMENT %s %s MANIFEST %s CARRY %s',
    p_student_id, p_year_month, p_expected_preview_manifest_sha256,
    p_expected_final_carryover_cny
  );

  if not v_idempotent then
    select * into strict v_lock
    from public.school_lock_student_monthly_settlement(
      p_student_id, p_year_month, p_note
    );
    select * into strict v_settlement
    from public.school_student_monthly_settlements s
    where s.id = v_lock.settlement_id;
  end if;

  if v_settlement.settlement_status is distinct from 'locked'
     or v_settlement.system_difference_cny is distinct from
       p_expected_system_difference_cny
     or v_settlement.carryover_amount_cny is distinct from
       p_expected_final_carryover_cny
     or coalesce(v_settlement.lesson_variance_source_count, 0)
       is distinct from p_expected_source_count
     or coalesce(v_settlement.lesson_variance_manifest_sha256,
       p_expected_lesson_variance_manifest_sha256)
       is distinct from p_expected_lesson_variance_manifest_sha256 then
    raise exception 'SETTLEMENT_LOCK_CONFLICT';
  end if;

  return jsonb_build_object(
    'ok', true, 'idempotent', v_idempotent,
    'operation', 'lock_student_monthly_settlement_online_admin_v1',
    'operator_authority', 'authenticated_active_admin_edge_v1',
    'canonical_confirmation', v_canonical_confirmation,
    'request_correlation_id', p_request_correlation_id,
    'actor_user_id', p_actor_user_id,
    'settlement_id', v_settlement.id,
    'student_id', v_settlement.student_id,
    'year_month', v_settlement.year_month,
    'business_entity_id', v_settlement.business_entity_id,
    'settlement_status', v_settlement.settlement_status,
    'locked_at', v_settlement.locked_at,
    'system_difference_cny', v_settlement.system_difference_cny,
    'adjustment_amount_cny', v_settlement.adjustment_amount_cny,
    'final_carryover_cny', v_settlement.carryover_amount_cny,
    'lesson_variance_source_count', p_expected_source_count,
    'lesson_variance_manifest_sha256', p_expected_lesson_variance_manifest_sha256,
    'preview_manifest_sha256', p_expected_preview_manifest_sha256,
    'source_treatment_draft_id', v_source.id,
    'source_treatment_draft_updated_at', v_source.updated_at,
    'adjustment_draft_id', v_adjustment.id,
    'adjustment_draft_updated_at', v_adjustment.updated_at,
    'effective_status', 'ordinary_locked'
  );
end
$function$;

alter function public.school_get_student_monthly_settlement_wage_blockers(text,uuid)
  owner to postgres;
alter function public.school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)
  owner to postgres;
alter function public.school_assert_student_settlement_online_admin(uuid)
  owner to postgres;
alter function public.school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text)
  owner to postgres;
alter function public.school_assert_student_settlement_online_expected_facts(
  jsonb,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric
) owner to postgres;
alter function public.school_get_student_monthly_settlement_online_status_core(uuid,text)
  owner to postgres;
alter function public.school_get_student_monthly_settlement_online_status(uuid,text)
  owner to postgres;
alter function public.school_save_student_monthly_settlement_draft_online_admin(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid
) owner to postgres;
alter function public.school_lock_student_monthly_settlement_online_admin(
  uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,uuid
) owner to postgres;

revoke all on function public.school_get_student_monthly_settlement_wage_blockers(text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_student_monthly_settlement_wage_blockers(text,uuid)
  to anon, authenticated, service_role;
revoke all on function public.school_assert_student_monthly_settlement_no_wage_blocker(uuid,text,text)
  from public, anon, authenticated, service_role;

revoke all on function public.school_assert_student_settlement_online_admin(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_assert_student_settlement_online_expected_facts(
  jsonb,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric
) from public, anon, authenticated, service_role;
revoke all on function public.school_get_student_monthly_settlement_online_status_core(uuid,text)
  from public, anon, authenticated, service_role;

revoke all on function public.school_get_student_monthly_settlement_online_status(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_student_monthly_settlement_online_status(uuid,text)
  to authenticated;

revoke all on function public.school_save_student_monthly_settlement_draft_online_admin(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid
) from public, anon, authenticated, service_role;
grant execute on function public.school_save_student_monthly_settlement_draft_online_admin(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid
) to service_role;

revoke all on function public.school_lock_student_monthly_settlement_online_admin(
  uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,uuid
) from public, anon, authenticated, service_role;
grant execute on function public.school_lock_student_monthly_settlement_online_admin(
  uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,uuid
) to service_role;

comment on function public.school_assert_student_settlement_online_admin(uuid) is
  'Owner-only Phase A assertion. The caller-supplied UUID is accepted only after an auth.users-backed active admin membership row is locked FOR SHARE. JWT-to-actor binding remains an Edge responsibility.';
comment on function public.school_assert_student_monthly_settlement_online_writable(uuid,text,uuid,text) is
  'Owner-only online ordinary-settlement guard. It requires unified effective incomplete state and rejects historical completion, physical history, successor tuition, immutable consumption, and non-no_wage wage dependencies.';
comment on function public.school_get_student_monthly_settlement_online_status(uuid,text) is
  'Authenticated active-membership read-only recovery contract for ordinary, historically consumed, historical zero-carry, and incomplete settlement states. Performs no business DML.';
comment on function public.school_save_student_monthly_settlement_draft_online_admin(
  uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid
) is 'Phase A service_role-only online save wrapper. Revalidates active-admin actor, effective state, scope, manifests, DB amounts, existing draft versions, and semantic idempotency; never locks a settlement.';
comment on function public.school_lock_student_monthly_settlement_online_admin(
  uuid,uuid,text,uuid,timestamptz,uuid,timestamptz,text,text,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,text,uuid
) is 'Phase A service_role-only online lock wrapper. Revalidates active-admin actor, effective state, saved drafts, manifests and DB amounts, then delegates only to the owner core lock; never unlocks or relocks.';

do $postdefine$
declare
  v_name text;
begin
  foreach v_name in array array[
    'school_assert_student_settlement_online_admin',
    'school_assert_student_monthly_settlement_online_writable',
    'school_assert_student_settlement_online_expected_facts',
    'school_get_student_monthly_settlement_online_status_core',
    'school_get_student_monthly_settlement_online_status',
    'school_save_student_monthly_settlement_draft_online_admin',
    'school_lock_student_monthly_settlement_online_admin'
  ] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      join pg_roles r on r.oid = p.proowner
      where n.nspname = 'public' and p.proname = v_name
        and r.rolname = 'postgres' and p.prosecdef
        and p.proconfig = array['search_path=pg_catalog, public']::text[]
    ) then
      raise exception 'SETTLEMENT_ONLINE_POSTDEFINE_INVALID:%', v_name;
    end if;
  end loop;

  if has_function_privilege('public',
       'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.school_save_student_monthly_settlement_draft_online_admin(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,uuid)', 'EXECUTE') then
    raise exception 'SETTLEMENT_ONLINE_SAVE_ACL_INVALID';
  end if;
end
$postdefine$;

\if :phase_a_rollback
  rollback;
\else
  commit;
\endif
