-- Allow ordinary Reissue to reuse an unchanged, currently locked carryover.
-- P0-E remains mandatory when the historical source is not currently locked
-- or its current authoritative carry no longer matches the frozen prior bill.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

create or replace function public.school_reissue_atomic_student_tuition_generation_local(
  p_generation_identity_id uuid,
  p_expected_previous_revision_id uuid,
  p_student_id uuid,
  p_business_entity_id uuid,
  p_billing_month text,
  p_expected_candidate_manifest_sha256 text,
  p_expected_generation_manifest_sha256 text,
  p_billing_exchange_rate numeric,
  p_expected_total_fee_jpy numeric,
  p_expected_billing_amount_cny numeric,
  p_note text
) returns table(
  tuition_bill_id uuid,billing_identity_id uuid,income_record_id uuid,student_id uuid,
  business_entity_id uuid,billing_month text,generation_manifest_sha256 text,
  candidate_count integer,total_lesson_count integer,total_duration_hours numeric,
  total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,total_fee_jpy numeric,
  billing_exchange_rate numeric,previous_carryover_cny numeric,billing_amount_cny numeric,
  bill_status text,income_status text,idempotent boolean,message text
) language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_active public.school_student_tuition_generation_revisions%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_snapshot record;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
begin
  if p_generation_identity_id is null or p_expected_previous_revision_id is null
     or p_student_id is null or p_business_entity_id is null or v_note is null
     or p_billing_month is null
     or p_expected_candidate_manifest_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_generation_manifest_sha256 !~ '^[0-9a-f]{64}$'
     or p_billing_exchange_rate is null or p_billing_exchange_rate<=0
     or p_expected_total_fee_jpy is null or p_expected_total_fee_jpy<0
     or p_expected_billing_amount_cny is null then
    raise exception 'TUITION_REISSUE_INPUT_INVALID';
  end if;

  select * into strict v_generation
  from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id
    and g.student_id=p_student_id
    and g.business_entity_id=p_business_entity_id
    and g.billing_month=to_date(p_billing_month||'-01','YYYY-MM-DD')
  for update;
  select * into strict v_previous
  from public.school_student_tuition_generation_revisions r
  where r.id=p_expected_previous_revision_id
    and r.generation_identity_id=v_generation.id
    and r.lifecycle_status='voided'
    and r.manifest_kind='atomic_generation_v1'
  for update;
  select * into v_active
  from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=v_generation.id and r.lifecycle_status='active'
  for update;
  if found and (v_active.previous_revision_id is distinct from v_previous.id
      or v_active.revision_no<>v_previous.revision_no+1
      or v_active.manifest_kind<>'atomic_generation_v1') then
    raise exception 'TUITION_REISSUE_ACTIVE_REVISION_EXISTS';
  end if;

  if v_active.id is not null then
    select * into strict v_bill from public.school_student_tuition_bills b
    where b.id=v_active.tuition_bill_id for update;
    if v_bill.source_snapshot->>'candidate_manifest_sha256'
         is distinct from p_expected_candidate_manifest_sha256
       or v_active.generation_manifest_sha256
         is distinct from p_expected_generation_manifest_sha256
       or v_bill.billing_exchange_rate is distinct from p_billing_exchange_rate
       or v_bill.bill_amount_jpy is distinct from p_expected_total_fee_jpy
       or v_bill.billing_amount_cny is distinct from p_expected_billing_amount_cny then
      raise exception 'TUITION_REISSUE_EXPECTED_FACT_MISMATCH';
    end if;
  else
    select * into strict v_snapshot
    from public.school_build_student_tuition_generation_snapshot(
      p_student_id,p_billing_month,p_billing_exchange_rate
    );
    if v_snapshot.business_entity_id is distinct from p_business_entity_id
       or v_snapshot.candidate_manifest_sha256 is distinct from p_expected_candidate_manifest_sha256
       or v_snapshot.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256
       or v_snapshot.total_fee_jpy is distinct from p_expected_total_fee_jpy
       or v_snapshot.billing_amount_cny is distinct from p_expected_billing_amount_cny then
      raise exception 'TUITION_REISSUE_EXPECTED_FACT_MISMATCH';
    end if;
  end if;

  select b.* into strict v_bill
  from public.school_student_tuition_bills b
  where b.id=v_previous.tuition_bill_id;
  if v_bill.previous_settlement_id is not null
     and round(coalesce(v_bill.previous_carryover_cny,0),2)<>0
     and public.school_tuition_p0a_consumed_bill_id(v_bill.previous_settlement_id)=v_bill.id
     and not exists(
       select 1
       from public.school_student_monthly_settlements s
       where s.id=v_bill.previous_settlement_id
         and s.student_id=v_bill.student_id
         and s.business_entity_id=v_bill.business_entity_id
         and s.year_month=v_bill.previous_settlement_month
         and s.settlement_status='locked'
         and round(coalesce(s.carryover_amount_cny,0),2)
               =round(v_bill.previous_carryover_cny,2)
     ) then
    raise exception 'TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED';
  end if;
  perform set_config('school.tuition_operator_authority','local_trusted_business_owner_v1',true);
  return query select *
  from public.school_generate_student_tuition_bill_atomic_core(
    p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,v_note,null
  );
end
$function$;

revoke all on function public.school_reissue_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text
) from public,anon,authenticated;
grant execute on function public.school_reissue_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text
) to service_role;

comment on function public.school_reissue_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text
) is 'Local trusted ordinary Reissue. A currently locked settlement whose authoritative carry exactly matches the frozen prior bill may be reclaimed; abnormal or changed historical non-zero carry remains P0-E-only.';

commit;
