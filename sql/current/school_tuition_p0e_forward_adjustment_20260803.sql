-- P0-E RPCs: immutable generation-revision forward adjustment and consumed-settlement reader.
-- Business authority: neutralize_historical_carryover_v1 is computed only by DB.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $capture_p0e_baselines$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_validate_tuition_generation_revision_for_bill(uuid)'::regprocedure);
  v_definition:=replace(v_definition,'school_validate_tuition_generation_revision_for_bill',
    'school_p0e_base_validate_revision');
  execute v_definition;
  revoke all on function public.school_p0e_base_validate_revision(uuid)
    from public,anon,authenticated,service_role;
  v_definition:=pg_get_functiondef(
    'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure);
  v_definition:=replace(v_definition,'school_reissue_atomic_student_tuition_generation_local',
    'school_p0e_base_reissue_local');
  execute v_definition;
  revoke all on function public.school_p0e_base_reissue_local(
    uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)
    from public,anon,authenticated,service_role;
end;
$capture_p0e_baselines$;

create function public.school_guard_tuition_generation_revision_adjustment_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='INSERT' then
    if current_setting('school.tuition_operator_authority',true)
         is distinct from 'local_trusted_business_owner_v1'
       or not exists(
         select 1 from public.school_tuition_atomic_writer_context c
         where c.backend_pid=pg_backend_pid() and c.transaction_id=txid_current()
           and c.writer_source='student_tuition_atomic_generate_v1'
       ) then
      raise exception 'TUITION_P0E_ADJUSTMENT_WRITER_FORBIDDEN';
    end if;
    return new;
  end if;
  if tg_op='DELETE' and session_user='postgres'
     and current_setting('tuition.p0d_fixture_cleanup',true)
       ='codex-test tuition-p0d-e2e-readiness-20260803'
     and old.generation_identity_id='d0d00000-0000-4000-8000-000000003001'::uuid then
    return old;
  end if;
  raise exception 'TUITION_P0E_ADJUSTMENT_IMMUTABLE';
end;
$function$;
revoke all on function public.school_guard_tuition_generation_revision_adjustment_immutable()
  from public,anon,authenticated,service_role;
create trigger school_guard_tuition_generation_revision_adjustment_immutable
before insert or update or delete on public.school_student_tuition_generation_revision_adjustments
for each row execute function public.school_guard_tuition_generation_revision_adjustment_immutable();

create function public.school_compute_tuition_p0e_adjustment_line_manifest(
  p_generation_identity_id uuid,p_target_billing_month date,p_source_previous_revision_id uuid,
  p_source_settlement_id uuid,p_adjustment_type text,p_amount_cny numeric,
  p_source_historical_carryover_cny numeric,p_reason text,p_operator_authority text
) returns text language sql immutable set search_path=pg_catalog,public
as $function$
  select encode(sha256(convert_to(jsonb_build_object(
    'contract_version','tuition_forward_adjustment_v1',
    'generation_identity_id',p_generation_identity_id,
    'target_billing_month',to_char(p_target_billing_month,'YYYY-MM'),
    'source_previous_revision_id',p_source_previous_revision_id,
    'source_settlement_id',p_source_settlement_id,
    'adjustment_type',p_adjustment_type,
    'amount_cny',round(p_amount_cny,2),
    'source_historical_carryover_cny',round(p_source_historical_carryover_cny,2),
    'reason',btrim(p_reason),'operator_authority',p_operator_authority
  )::text,'UTF8')),'hex')
$function$;
revoke all on function public.school_compute_tuition_p0e_adjustment_line_manifest(
  uuid,date,uuid,uuid,text,numeric,numeric,text,text) from public,anon,authenticated,service_role;

create function public.school_compute_tuition_p0e_generation_manifest(
  p_base_candidate_manifest_sha256 text,p_generation_identity_id uuid,
  p_source_previous_revision_id uuid,p_source_previous_manifest_sha256 text,
  p_source_settlement_id uuid,p_source_historical_carryover_cny numeric,
  p_billing_exchange_rate numeric,p_total_fee_jpy numeric,p_exchange_amount_cny numeric,
  p_adjustment_type text,p_adjustment_amount_cny numeric,p_final_billing_amount_cny numeric,
  p_reason text,p_line_manifest_sha256 text
) returns text language sql immutable set search_path=pg_catalog,public
as $function$
  select encode(sha256(convert_to(jsonb_build_object(
    'contract_version','tuition_generation_revision_forward_adjustment_v1',
    'base_candidate_manifest_sha256',p_base_candidate_manifest_sha256,
    'generation_identity_id',p_generation_identity_id,
    'source_previous_revision_id',p_source_previous_revision_id,
    'source_previous_manifest_sha256',p_source_previous_manifest_sha256,
    'source_settlement_id',p_source_settlement_id,
    'source_historical_carryover_cny',round(p_source_historical_carryover_cny,2),
    'billing_exchange_rate',p_billing_exchange_rate,'total_fee_jpy',p_total_fee_jpy,
    'exchange_amount_cny',round(p_exchange_amount_cny,2),
    'adjustment_type',p_adjustment_type,'adjustment_amount_cny',round(p_adjustment_amount_cny,2),
    'final_billing_amount_cny',round(p_final_billing_amount_cny,2),
    'reason',btrim(p_reason),'line_manifest_sha256',p_line_manifest_sha256
  )::text,'UTF8')),'hex')
$function$;
revoke all on function public.school_compute_tuition_p0e_generation_manifest(
  text,uuid,uuid,text,uuid,numeric,numeric,numeric,numeric,text,numeric,numeric,text,text)
  from public,anon,authenticated,service_role;

create function public.school_get_atomic_tuition_reissue_preview_p0e(
  p_generation_identity_id uuid,p_previous_revision_id uuid,p_student_id uuid,
  p_business_entity_id uuid,p_billing_month text,p_billing_exchange_rate numeric,
  p_adjustment_type text,p_reason text
) returns table(
  generation_identity_id uuid,previous_revision_id uuid,student_id uuid,business_entity_id uuid,
  billing_month text,candidate_manifest_sha256 text,base_generation_manifest_sha256 text,
  generation_manifest_sha256 text,candidate_count integer,total_lesson_count integer,
  total_duration_hours numeric,total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,billing_exchange_rate numeric,exchange_amount_cny numeric,
  source_settlement_id uuid,source_historical_carryover_cny numeric,adjustment_type text,
  adjustment_amount_cny numeric,final_billing_amount_cny numeric,reason text,
  operator_authority text,line_manifest_sha256 text
) language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_previous_bill public.school_student_tuition_bills%rowtype;
  v_snapshot record; v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_type text:=nullif(btrim(coalesce(p_adjustment_type,'')),'');
  v_operator constant text:='local_trusted_business_owner_v1';
  v_exchange numeric; v_adjustment numeric; v_final numeric; v_line text; v_manifest text;
begin
  if p_generation_identity_id is null or p_previous_revision_id is null
     or p_student_id is null or p_business_entity_id is null
     or p_billing_month is null or p_billing_month!~'^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_billing_exchange_rate is null or p_billing_exchange_rate<=0
     or (v_type is not null and v_type<>'neutralize_historical_carryover_v1')
     or (v_type is not null and v_reason is null) then
    raise exception 'TUITION_P0E_PREVIEW_INPUT_INVALID';
  end if;
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id and g.student_id=p_student_id
    and g.business_entity_id=p_business_entity_id
    and g.billing_month=to_date(p_billing_month||'-01','YYYY-MM-DD');
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.id=p_previous_revision_id and r.generation_identity_id=v_generation.id
    and r.lifecycle_status='voided' and r.manifest_kind='atomic_generation_v1';
  if exists(select 1 from public.school_student_tuition_generation_revisions r
            where r.generation_identity_id=v_generation.id and r.lifecycle_status='active') then
    raise exception 'TUITION_REISSUE_ACTIVE_REVISION_EXISTS';
  end if;
  select b.* into strict v_previous_bill from public.school_student_tuition_bills b
  where b.id=v_previous.tuition_bill_id;
  if v_previous_bill.previous_settlement_id is null
     or round(coalesce(v_previous_bill.previous_carryover_cny,0),2)=0
     or public.school_tuition_p0a_consumed_bill_id(v_previous_bill.previous_settlement_id)
          is distinct from v_previous_bill.id then
    raise exception 'TUITION_P0E_HISTORICAL_CARRY_REQUIRED';
  end if;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate);
  if v_snapshot.business_entity_id is distinct from p_business_entity_id then
    raise exception 'TUITION_P0E_SCOPE_MISMATCH';
  end if;
  v_exchange:=round(v_snapshot.total_fee_jpy*p_billing_exchange_rate,2);
  v_adjustment:=case when v_type is null then 0 else -round(v_previous_bill.previous_carryover_cny,2) end;
  v_final:=round(v_exchange+v_previous_bill.previous_carryover_cny+v_adjustment,2);
  if v_type is not null then
    v_line:=public.school_compute_tuition_p0e_adjustment_line_manifest(
      v_generation.id,v_generation.billing_month,v_previous.id,v_previous_bill.previous_settlement_id,
      v_type,v_adjustment,v_previous_bill.previous_carryover_cny,v_reason,v_operator);
    v_manifest:=public.school_compute_tuition_p0e_generation_manifest(
      v_snapshot.candidate_manifest_sha256,v_generation.id,v_previous.id,
      v_previous.generation_manifest_sha256,v_previous_bill.previous_settlement_id,
      v_previous_bill.previous_carryover_cny,p_billing_exchange_rate,v_snapshot.total_fee_jpy,
      v_exchange,v_type,v_adjustment,v_final,v_reason,v_line);
  end if;
  return query select v_generation.id,v_previous.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,v_snapshot.candidate_manifest_sha256,
    v_snapshot.generation_manifest_sha256,v_manifest,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,v_snapshot.total_fee_jpy,
    p_billing_exchange_rate,v_exchange,v_previous_bill.previous_settlement_id,
    round(v_previous_bill.previous_carryover_cny,2),v_type,v_adjustment,v_final,v_reason,v_operator,v_line;
end;
$function$;
revoke all on function public.school_get_atomic_tuition_reissue_preview_p0e(
  uuid,uuid,uuid,uuid,text,numeric,text,text) from public,anon,authenticated;
grant execute on function public.school_get_atomic_tuition_reissue_preview_p0e(
  uuid,uuid,uuid,uuid,text,numeric,text,text) to service_role;

create function public.school_get_student_monthly_settlement_effective_states(p_settlement_ids uuid[])
returns table(
  settlement_id uuid,physical_status text,effective_status text,immutable_error_code text,
  consumed_generation_identity_id uuid,consumed_revision_id uuid,consumed_bill_id uuid,
  frozen_carryover_cny numeric,editable boolean,unlockable boolean,relockable boolean,
  display_label text,immutable_reason text
) language sql stable security definer set search_path=pg_catalog,public
as $function$
  with requested as (
    select s.* from public.school_student_monthly_settlements s
    where s.id=any(coalesce(p_settlement_ids,'{}'::uuid[]))
  ), claims as (
    select s.*,
      ar.generation_identity_id active_generation_id,ar.id active_revision_id,ab.id active_bill_id,
      ab.previous_carryover_cny active_carry,
      hr.generation_identity_id historical_generation_id,hr.id historical_revision_id,hb.id historical_bill_id,
      hb.previous_carryover_cny historical_carry
    from requested s
    left join lateral (
      select b.* from public.school_student_tuition_generation_revisions r
      join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
      where r.lifecycle_status='active' and b.previous_settlement_id=s.id
      order by r.created_at desc,r.id desc limit 1
    ) ab on true
    left join public.school_student_tuition_generation_revisions ar on ar.tuition_bill_id=ab.id
    left join lateral (
      select b.* from public.school_student_tuition_generation_revisions r
      join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
      where b.previous_settlement_id=s.id
      order by r.created_at desc,r.id desc limit 1
    ) hb on true
    left join public.school_student_tuition_generation_revisions hr on hr.tuition_bill_id=hb.id
  )
  select id,settlement_status,
    case when historical_bill_id is not null then 'historically_consumed_immutable'
         else settlement_status end,
    case when historical_bill_id is not null then 'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE'
         when active_bill_id is not null then 'TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' end,
    coalesce(historical_generation_id,active_generation_id),
    coalesce(historical_revision_id,active_revision_id),coalesce(historical_bill_id,active_bill_id),
    coalesce(historical_carry,active_carry,carryover_amount_cny),
    (active_bill_id is null and historical_bill_id is null),
    (active_bill_id is null and historical_bill_id is null and settlement_status='locked'),
    (active_bill_id is null and historical_bill_id is null and settlement_status='unlocked'),
    case when historical_bill_id is not null then '已被历史学费账单消费（不可重开）'
         when active_bill_id is not null then '已被当前学费账单冻结（不可修改）'
         when settlement_status='locked' then '已锁定' else '锁定已撤销' end,
    case when historical_bill_id is not null then
           '该结算已被历史学费账单消费，作为冻结历史事实保留，不能重新打开或覆盖。'
         when active_bill_id is not null then
           '该结算已被当前有效学费账单作为前期结转消费，所有修改入口均已冻结。' end
  from claims
$function$;
revoke all on function public.school_get_student_monthly_settlement_effective_states(uuid[])
  from public;
grant execute on function public.school_get_student_monthly_settlement_effective_states(uuid[])
  to anon,authenticated,service_role;

-- Clone the verified P0-C next-revision core and inject only the approved P0-E authority override.
do $clone_p0e_core$
declare v_definition text; v_anchor text; v_injection text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)'::regprocedure);
  v_definition:=replace(v_definition,'school_generate_student_tuition_next_revision_core',
    'school_generate_student_tuition_next_revision_p0e_core');
  v_anchor:='select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate);';
  v_injection:=v_anchor||'
  if v_snapshot.candidate_manifest_sha256 is distinct from current_setting(''tuition.p0e_candidate_manifest'',true)
     or v_snapshot.total_fee_jpy is distinct from current_setting(''tuition.p0e_total_fee_jpy'',true)::numeric then
    raise exception ''TUITION_P0E_EXPECTED_FACT_MISMATCH'';
  end if;
  select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_previous.tuition_bill_id;
  if v_bill.previous_settlement_id is distinct from current_setting(''tuition.p0e_source_settlement_id'',true)::uuid
     or round(v_bill.previous_carryover_cny,2) is distinct from current_setting(''tuition.p0e_historical_carry'',true)::numeric
     or public.school_tuition_p0a_consumed_bill_id(v_bill.previous_settlement_id) is distinct from v_bill.id then
    raise exception ''TUITION_P0E_SOURCE_EVIDENCE_CHANGED'';
  end if;
  v_snapshot.previous_settlement_month:=v_bill.previous_settlement_month;
  v_snapshot.previous_settlement_id:=v_bill.previous_settlement_id;
  v_snapshot.previous_carryover_cny:=v_bill.previous_carryover_cny;
  v_snapshot.carryover_evidence:=v_bill.source_snapshot->''carryover_evidence'';
  v_snapshot.billing_amount_cny:=current_setting(''tuition.p0e_final_amount'',true)::numeric;
  v_snapshot.generation_manifest_sha256:=p_expected_generation_manifest_sha256;';
  v_definition:=replace(v_definition,v_anchor,v_injection);
  if v_definition=v_definition or position('TUITION_P0E_SOURCE_EVIDENCE_CHANGED' in v_definition)=0 then
    null;
  end if;
  v_definition:=replace(v_definition,
    '''billing_amount_currency'',''CNY''',
    '''billing_amount_currency'',''CNY'',''forward_adjustment'',current_setting(''tuition.p0e_snapshot'',true)::jsonb');
  v_anchor:='delete from public.school_tuition_atomic_writer_context where backend_pid=pg_backend_pid()
    and transaction_id=txid_current();';
  v_injection:='insert into public.school_student_tuition_generation_revision_adjustments(
    generation_identity_id,target_revision_id,target_billing_month,source_previous_revision_id,
    source_settlement_id,adjustment_type,amount_cny,source_historical_carryover_cny,
    reason,operator_authority,line_manifest_sha256
  ) values(v_generation.id,v_revision_id,v_generation.billing_month,v_previous.id,
    current_setting(''tuition.p0e_source_settlement_id'',true)::uuid,
    ''neutralize_historical_carryover_v1'',current_setting(''tuition.p0e_adjustment'',true)::numeric,
    current_setting(''tuition.p0e_historical_carry'',true)::numeric,
    current_setting(''tuition.p0e_reason'',true),''local_trusted_business_owner_v1'',
    current_setting(''tuition.p0e_line_manifest'',true));
  '||v_anchor;
  v_definition:=replace(v_definition,v_anchor,v_injection);
  if position('school_generate_student_tuition_next_revision_p0e_core' in v_definition)=0
     or position('TUITION_P0E_SOURCE_EVIDENCE_CHANGED' in v_definition)=0
     or position('forward_adjustment' in v_definition)=0
     or position('school_student_tuition_generation_revision_adjustments' in v_definition)=0 then
    raise exception 'TUITION_P0E_CORE_CLONE_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$clone_p0e_core$;
revoke all on function public.school_generate_student_tuition_next_revision_p0e_core(
  uuid,uuid,uuid,text,numeric,text,text,text) from public,anon,authenticated,service_role;

create function public.school_validate_tuition_generation_revision_adjustment_for_bill(p_bill_id uuid)
returns void language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_adjust public.school_student_tuition_generation_revision_adjustments%rowtype;
  v_source_revision public.school_student_tuition_generation_revisions%rowtype;
  v_source_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype; v_snapshot jsonb; v_expected_line text; v_expected_manifest text;
begin
  select b.* into v_bill from public.school_student_tuition_bills b where b.id=p_bill_id;
  if not found then return; end if;
  select r.* into v_revision from public.school_student_tuition_generation_revisions r where r.tuition_bill_id=p_bill_id;
  if not found then return; end if;
  select a.* into v_adjust from public.school_student_tuition_generation_revision_adjustments a
  where a.target_revision_id=v_revision.id;
  if not found then
    if v_bill.source_snapshot ? 'forward_adjustment' then
      raise exception 'TUITION_P0E_ADJUSTMENT_ROW_MISSING';
    end if;
    return;
  end if;
  select r.* into strict v_source_revision from public.school_student_tuition_generation_revisions r
  where r.id=v_adjust.source_previous_revision_id;
  select b.* into strict v_source_bill from public.school_student_tuition_bills b
  where b.id=v_source_revision.tuition_bill_id;
  select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id;
  v_snapshot:=v_bill.source_snapshot->'forward_adjustment';
  v_expected_line:=public.school_compute_tuition_p0e_adjustment_line_manifest(
    v_adjust.generation_identity_id,v_adjust.target_billing_month,v_adjust.source_previous_revision_id,
    v_adjust.source_settlement_id,v_adjust.adjustment_type,v_adjust.amount_cny,
    v_adjust.source_historical_carryover_cny,v_adjust.reason,v_adjust.operator_authority);
  v_expected_manifest:=public.school_compute_tuition_p0e_generation_manifest(
    v_bill.source_snapshot->>'candidate_manifest_sha256',v_adjust.generation_identity_id,
    v_adjust.source_previous_revision_id,v_source_revision.generation_manifest_sha256,
    v_adjust.source_settlement_id,v_adjust.source_historical_carryover_cny,
    v_bill.billing_exchange_rate,v_bill.bill_amount_jpy,
    (v_snapshot->>'exchange_amount_cny')::numeric,v_adjust.adjustment_type,v_adjust.amount_cny,
    v_bill.billing_amount_cny,v_adjust.reason,v_adjust.line_manifest_sha256);
  if v_adjust.generation_identity_id is distinct from v_revision.generation_identity_id
     or v_adjust.target_billing_month is distinct from (v_bill.billing_month||'-01')::date
     or v_source_revision.id is distinct from v_revision.previous_revision_id
     or v_adjust.source_settlement_id is distinct from v_source_bill.previous_settlement_id
     or v_adjust.source_historical_carryover_cny is distinct from round(v_source_bill.previous_carryover_cny,2)
     or v_adjust.amount_cny is distinct from -round(v_adjust.source_historical_carryover_cny,2)
     or v_bill.previous_settlement_id is distinct from v_adjust.source_settlement_id
     or v_bill.previous_carryover_cny is distinct from v_adjust.source_historical_carryover_cny
     or v_bill.billing_amount_cny is distinct from round(
          v_bill.bill_amount_jpy*v_bill.billing_exchange_rate
          +v_adjust.source_historical_carryover_cny+v_adjust.amount_cny,2)
     or v_adjust.line_manifest_sha256 is distinct from v_expected_line
     or v_revision.generation_manifest_sha256 is distinct from v_expected_manifest
     or v_bill.source_snapshot->>'generation_manifest_sha256' is distinct from v_expected_manifest
     or v_income.source_snapshot->>'generation_manifest_sha256' is distinct from v_expected_manifest
     or v_income.source_snapshot->'forward_adjustment' is distinct from v_snapshot
     or v_snapshot->>'adjustment_type' is distinct from v_adjust.adjustment_type
     or (v_snapshot->>'adjustment_amount_cny')::numeric is distinct from v_adjust.amount_cny
     or (v_snapshot->>'source_historical_carryover_cny')::numeric is distinct from v_adjust.source_historical_carryover_cny
     or v_snapshot->>'line_manifest_sha256' is distinct from v_adjust.line_manifest_sha256
     or v_snapshot->>'reason' is distinct from v_adjust.reason then
    raise exception 'TUITION_P0E_ADJUSTMENT_VALIDATION_FAILED';
  end if;
end;
$function$;
revoke all on function public.school_validate_tuition_generation_revision_adjustment_for_bill(uuid)
  from public,anon,authenticated,service_role;

-- Make the normal revision validator transitively validate the P0-E evidence.
do $patch_revision_validator$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_validate_tuition_generation_revision_for_bill(uuid)'::regprocedure);
  v_definition:=replace(v_definition,
    E'\nend;\n$function$\n',
    E'\n  perform public.school_validate_tuition_generation_revision_adjustment_for_bill(p_bill_id);\nend;\n$function$\n');
  if position('school_validate_tuition_generation_revision_adjustment_for_bill' in v_definition)=0 then
    raise exception 'TUITION_P0E_REVISION_VALIDATOR_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch_revision_validator$;

create function public.school_reissue_atomic_student_tuition_generation_p0e_local(
  p_generation_identity_id uuid,p_expected_previous_revision_id uuid,p_student_id uuid,
  p_business_entity_id uuid,p_billing_month text,p_expected_candidate_manifest_sha256 text,
  p_expected_generation_manifest_sha256 text,p_billing_exchange_rate numeric,
  p_expected_total_fee_jpy numeric,p_expected_exchange_amount_cny numeric,
  p_expected_source_settlement_id uuid,p_expected_historical_carryover_cny numeric,
  p_adjustment_type text,p_expected_adjustment_amount_cny numeric,
  p_expected_line_manifest_sha256 text,p_expected_final_billing_amount_cny numeric,
  p_reason text,p_note text
) returns table(
  tuition_bill_id uuid,billing_identity_id uuid,income_record_id uuid,generation_revision_id uuid,
  generation_manifest_sha256 text,candidate_manifest_sha256 text,total_fee_jpy numeric,
  billing_exchange_rate numeric,exchange_amount_cny numeric,source_settlement_id uuid,
  source_historical_carryover_cny numeric,adjustment_type text,adjustment_amount_cny numeric,
  final_billing_amount_cny numeric,line_manifest_sha256 text,idempotent boolean,message text
) language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_preview record; v_result record; v_active public.school_student_tuition_generation_revisions%rowtype;
  v_adjust public.school_student_tuition_generation_revision_adjustments%rowtype;
  v_bill public.school_student_tuition_bills%rowtype; v_income public.school_income_records%rowtype;
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype;
  v_note text:=nullif(btrim(coalesce(p_note,'')),''); v_forward jsonb;
begin
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id and g.student_id=p_student_id
    and g.business_entity_id=p_business_entity_id
    and g.billing_month=to_date(p_billing_month||'-01','YYYY-MM-DD');
  null; -- P0E shared lock entry
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    (to_date(p_billing_month||'-01','YYYY-MM-DD')-interval '1 month')::date);
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    to_date(p_billing_month||'-01','YYYY-MM-DD'));
  select r.* into v_active from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=p_generation_identity_id and r.lifecycle_status='active' for update;
  if found then
    select a.* into strict v_adjust from public.school_student_tuition_generation_revision_adjustments a
    where a.target_revision_id=v_active.id;
    select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_active.tuition_bill_id;
    select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id;
    select l.* into strict v_legacy from public.school_student_tuition_billing_identities l
    where l.id=v_generation.legacy_billing_identity_id;
    if v_active.previous_revision_id is distinct from p_expected_previous_revision_id
       or v_active.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256
       or v_bill.source_snapshot->>'candidate_manifest_sha256' is distinct from p_expected_candidate_manifest_sha256
       or v_bill.bill_amount_jpy is distinct from p_expected_total_fee_jpy
       or v_bill.billing_exchange_rate is distinct from p_billing_exchange_rate
       or (v_bill.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric
            is distinct from p_expected_exchange_amount_cny
       or v_adjust.source_settlement_id is distinct from p_expected_source_settlement_id
       or v_adjust.source_historical_carryover_cny is distinct from p_expected_historical_carryover_cny
       or v_adjust.adjustment_type is distinct from p_adjustment_type
       or v_adjust.amount_cny is distinct from p_expected_adjustment_amount_cny
       or v_adjust.line_manifest_sha256 is distinct from p_expected_line_manifest_sha256
       or v_bill.billing_amount_cny is distinct from p_expected_final_billing_amount_cny
       or v_adjust.reason is distinct from btrim(p_reason) then
      raise exception 'TUITION_P0E_IDEMPOTENCY_CONFLICT';
    end if;
    perform public.school_validate_tuition_generation_revision_for_bill(v_bill.id);
    return query select v_bill.id,v_legacy.id,v_income.id,v_active.id,
      v_active.generation_manifest_sha256,v_bill.source_snapshot->>'candidate_manifest_sha256',
      v_bill.bill_amount_jpy,v_bill.billing_exchange_rate,
      (v_bill.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric,
      v_adjust.source_settlement_id,v_adjust.source_historical_carryover_cny,
      v_adjust.adjustment_type,v_adjust.amount_cny,v_bill.billing_amount_cny,
      v_adjust.line_manifest_sha256,true,'existing P0-E active revision returned idempotently'::text;
    return;
  end if;
  select * into strict v_preview from public.school_get_atomic_tuition_reissue_preview_p0e(
    p_generation_identity_id,p_expected_previous_revision_id,p_student_id,p_business_entity_id,
    p_billing_month,p_billing_exchange_rate,p_adjustment_type,p_reason);
  if v_preview.candidate_manifest_sha256 is distinct from p_expected_candidate_manifest_sha256
     or v_preview.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256
     or v_preview.total_fee_jpy is distinct from p_expected_total_fee_jpy
     or v_preview.exchange_amount_cny is distinct from p_expected_exchange_amount_cny
     or v_preview.source_settlement_id is distinct from p_expected_source_settlement_id
     or v_preview.source_historical_carryover_cny is distinct from p_expected_historical_carryover_cny
     or v_preview.adjustment_amount_cny is distinct from p_expected_adjustment_amount_cny
     or v_preview.line_manifest_sha256 is distinct from p_expected_line_manifest_sha256
     or v_preview.final_billing_amount_cny is distinct from p_expected_final_billing_amount_cny then
    raise exception 'TUITION_P0E_EXPECTED_FACT_MISMATCH';
  end if;
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    (to_date(p_billing_month||'-01','YYYY-MM-DD')-interval '1 month')::date);
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    to_date(p_billing_month||'-01','YYYY-MM-DD'));
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id for update;
  select r.* into v_active from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=p_generation_identity_id and r.lifecycle_status='active' for update;
  if found then
    select a.* into strict v_adjust from public.school_student_tuition_generation_revision_adjustments a
    where a.target_revision_id=v_active.id;
    select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_active.tuition_bill_id;
    select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id;
    select l.* into strict v_legacy from public.school_student_tuition_billing_identities l
    where l.id=v_generation.legacy_billing_identity_id;
    if v_active.previous_revision_id is distinct from p_expected_previous_revision_id
       or v_active.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256
       or v_adjust.line_manifest_sha256 is distinct from p_expected_line_manifest_sha256
       or v_bill.billing_amount_cny is distinct from p_expected_final_billing_amount_cny then
      raise exception 'TUITION_P0E_IDEMPOTENCY_CONFLICT';
    end if;
    perform public.school_validate_tuition_generation_revision_for_bill(v_bill.id);
    return query select v_bill.id,v_legacy.id,v_income.id,v_active.id,
      v_active.generation_manifest_sha256,v_bill.source_snapshot->>'candidate_manifest_sha256',
      v_bill.bill_amount_jpy,v_bill.billing_exchange_rate,
      (v_bill.source_snapshot->'forward_adjustment'->>'exchange_amount_cny')::numeric,
      v_adjust.source_settlement_id,v_adjust.source_historical_carryover_cny,
      v_adjust.adjustment_type,v_adjust.amount_cny,v_bill.billing_amount_cny,
      v_adjust.line_manifest_sha256,true,'existing P0-E active revision returned idempotently'::text;
    return;
  end if;
  v_forward:=jsonb_build_object(
    'contract_version','tuition_generation_revision_forward_adjustment_v1',
    'source_previous_revision_id',p_expected_previous_revision_id,
    'source_settlement_id',v_preview.source_settlement_id,
    'source_historical_carryover_cny',v_preview.source_historical_carryover_cny,
    'exchange_amount_cny',v_preview.exchange_amount_cny,'adjustment_type',v_preview.adjustment_type,
    'adjustment_amount_cny',v_preview.adjustment_amount_cny,
    'final_billing_amount_cny',v_preview.final_billing_amount_cny,
    'reason',v_preview.reason,'operator_authority',v_preview.operator_authority,
    'line_manifest_sha256',v_preview.line_manifest_sha256,
    'base_generation_manifest_sha256',v_preview.base_generation_manifest_sha256);
  perform set_config('school.tuition_operator_authority','local_trusted_business_owner_v1',true);
  perform set_config('tuition.p0e_candidate_manifest',v_preview.candidate_manifest_sha256,true);
  perform set_config('tuition.p0e_total_fee_jpy',v_preview.total_fee_jpy::text,true);
  perform set_config('tuition.p0e_source_settlement_id',v_preview.source_settlement_id::text,true);
  perform set_config('tuition.p0e_historical_carry',v_preview.source_historical_carryover_cny::text,true);
  perform set_config('tuition.p0e_adjustment',v_preview.adjustment_amount_cny::text,true);
  perform set_config('tuition.p0e_final_amount',v_preview.final_billing_amount_cny::text,true);
  perform set_config('tuition.p0e_reason',v_preview.reason,true);
  perform set_config('tuition.p0e_line_manifest',v_preview.line_manifest_sha256,true);
  perform set_config('tuition.p0e_snapshot',v_forward::text,true);
  select * into strict v_result from public.school_generate_student_tuition_next_revision_p0e_core(
    p_generation_identity_id,p_expected_previous_revision_id,p_student_id,p_billing_month,
    p_billing_exchange_rate,p_expected_generation_manifest_sha256,v_note,null);
  select r.* into strict v_active from public.school_student_tuition_generation_revisions r
  where r.tuition_bill_id=v_result.tuition_bill_id;
  select a.* into strict v_adjust from public.school_student_tuition_generation_revision_adjustments a
  where a.target_revision_id=v_active.id;
  perform public.school_validate_tuition_generation_revision_for_bill(v_result.tuition_bill_id);
  return query select v_result.tuition_bill_id,v_result.billing_identity_id,v_result.income_record_id,
    v_active.id,v_result.generation_manifest_sha256,v_preview.candidate_manifest_sha256,
    v_result.total_fee_jpy,v_result.billing_exchange_rate,v_preview.exchange_amount_cny,
    v_adjust.source_settlement_id,v_adjust.source_historical_carryover_cny,v_adjust.adjustment_type,
    v_adjust.amount_cny,v_result.billing_amount_cny,v_adjust.line_manifest_sha256,false,
    'P0-E atomic tuition revision created'::text;
end;
$function$;
revoke all on function public.school_reissue_atomic_student_tuition_generation_p0e_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)
  from public,anon,authenticated;
grant execute on function public.school_reissue_atomic_student_tuition_generation_p0e_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)
  to service_role;

-- The ordinary Reissue path must not silently reuse a historically consumed non-zero carry.
do $guard_ordinary_reissue$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure);
  v_definition:=replace(v_definition,
    'perform set_config(''school.tuition_operator_authority'',''local_trusted_business_owner_v1'',true);',
    'select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_previous.tuition_bill_id;
  if v_bill.previous_settlement_id is not null and round(coalesce(v_bill.previous_carryover_cny,0),2)<>0
     and public.school_tuition_p0a_consumed_bill_id(v_bill.previous_settlement_id)=v_bill.id then
    raise exception ''TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED'';
  end if;
  perform set_config(''school.tuition_operator_authority'',''local_trusted_business_owner_v1'',true);');
  if position('TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED' in v_definition)=0 then
    raise exception 'TUITION_P0E_ORDINARY_REISSUE_GUARD_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$guard_ordinary_reissue$;

comment on function public.school_get_student_monthly_settlement_effective_states(uuid[]) is
  'P0-E read-only effective settlement state. Physical row remains untouched; Rule A precedes permanent Rule B.';
comment on function public.school_reissue_atomic_student_tuition_generation_p0e_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)
is 'P0-E dedicated local trusted Reissue; every monetary fact and immutable line manifest is DB authoritative.';

commit;
