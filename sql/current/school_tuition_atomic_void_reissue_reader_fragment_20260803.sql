-- Active revision reader/validator cutover. Included inside migration transaction.

create function public.school_validate_tuition_generation_revision_for_bill(p_bill_id uuid)
returns void language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_relation_manifest_count integer;
  v_relation_manifest text;
begin
  select r.* into v_revision from public.school_student_tuition_generation_revisions r
  where r.tuition_bill_id=p_bill_id;
  if not found then return; end if;
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=v_revision.generation_identity_id;
  select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
  where i.id=v_generation.legacy_billing_identity_id;
  select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=p_bill_id;
  select inc.* into strict v_income from public.school_income_records inc where inc.id=v_bill.income_record_id;
  if v_generation.student_id<>v_bill.student_id
     or v_generation.business_entity_id<>v_bill.business_entity_id
     or to_char(v_generation.billing_month,'YYYY-MM')<>v_bill.billing_month
     or v_legacy.student_id<>v_generation.student_id
     or v_legacy.billing_month<>to_char(v_generation.billing_month,'YYYY-MM') then
    raise exception 'TUITION_GENERATION_REVISION_IDENTITY_MISMATCH';
  end if;
  if v_revision.revision_no=1 and v_legacy.canonical_bill_id<>v_bill.id then
    raise exception 'TUITION_GENERATION_REVISION_ONE_BILL_MISMATCH';
  end if;
  if v_revision.revision_no>1 and v_legacy.canonical_bill_id=v_bill.id then
    raise exception 'TUITION_GENERATION_NEXT_REVISION_BILL_MISMATCH';
  end if;
  if (v_revision.lifecycle_status='active' and v_bill.status<>'income_created')
     or (v_revision.lifecycle_status='voided' and v_bill.status<>'cancelled') then
    raise exception 'TUITION_GENERATION_REVISION_LIFECYCLE_MISMATCH';
  end if;
  if v_revision.manifest_kind='historical_registration_v1' then
    if v_revision.revision_no<>1 or v_legacy.source<>'historical_backfill'
       or v_legacy.evidence->>'generation_manifest_sha256' is not null
       or v_bill.source_snapshot->>'generation_manifest_sha256' is not null
       or v_income.source_snapshot->>'generation_manifest_sha256' is not null
       or public.school_compute_historical_tuition_registration_manifest(v_legacy.id)
            <>v_revision.generation_manifest_sha256 then
      raise exception 'TUITION_HISTORICAL_REGISTRATION_REVISION_INVALID';
    end if;
  else
    if v_legacy.source<>'atomic_charge'
       or v_bill.source_snapshot->>'generation_source'<>'student_tuition_atomic_generate_v1'
       or v_income.source_snapshot->>'generation_source'<>'student_tuition_atomic_generate_v1'
       or v_bill.source_snapshot->>'generation_manifest_sha256'<>v_revision.generation_manifest_sha256
       or v_income.source_snapshot->>'generation_manifest_sha256'<>v_revision.generation_manifest_sha256 then
      raise exception 'TUITION_ATOMIC_GENERATION_REVISION_INVALID';
    end if;
    select count(distinct rel.source_snapshot->>'generation_manifest_sha256')::integer,
           min(rel.source_snapshot->>'generation_manifest_sha256')
      into v_relation_manifest_count,v_relation_manifest
    from public.school_student_tuition_bill_lessons rel where rel.tuition_bill_id=v_bill.id;
    if v_relation_manifest_count<>1 or v_relation_manifest<>v_revision.generation_manifest_sha256 then
      raise exception 'TUITION_ATOMIC_REVISION_RELATION_MANIFEST_INVALID';
    end if;
  end if;
end;
$function$;
revoke all on function public.school_validate_tuition_generation_revision_for_bill(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.school_validate_tuition_identity_for_bill(p_bill_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_revision_count integer;
  v_legacy_count integer;
  v_matching_count integer;
begin
  if p_bill_id is null then return; end if;
  select b.* into v_bill from public.school_student_tuition_bills b where b.id=p_bill_id;
  if not found then return; end if;
  select count(*)::integer into v_revision_count
  from public.school_student_tuition_generation_revisions r where r.tuition_bill_id=p_bill_id;
  select count(*)::integer into v_legacy_count
  from public.school_student_tuition_billing_identities i where i.canonical_bill_id=p_bill_id;
  select count(*)::integer into v_matching_count
  from public.school_student_tuition_generation_revisions r
  join public.school_student_tuition_generation_identities g on g.id=r.generation_identity_id
  join public.school_student_tuition_billing_identities i on i.id=g.legacy_billing_identity_id
  where r.tuition_bill_id=p_bill_id and g.student_id=v_bill.student_id
    and g.business_entity_id=v_bill.business_entity_id
    and to_char(g.billing_month,'YYYY-MM')=v_bill.billing_month
    and i.student_id=g.student_id and i.billing_month=v_bill.billing_month;
  if v_bill.billing_role='canonical_charge' then
    if v_revision_count<>1 or v_matching_count<>1 or v_legacy_count not in (0,1) then
      raise exception 'TUITION_IDENTITY_MISMATCH: canonical bill % revision identity invalid.',p_bill_id;
    end if;
  elsif v_revision_count<>0 or v_legacy_count<>0 then
    raise exception 'TUITION_IDENTITY_MISMATCH: noncanonical bill % has generation identity.',p_bill_id;
  end if;
  perform public.school_validate_tuition_generation_revision_for_bill(p_bill_id);
end;
$function$;
revoke all on function public.school_validate_tuition_identity_for_bill(uuid)
  from public,anon,authenticated;
grant execute on function public.school_validate_tuition_identity_for_bill(uuid) to service_role;

do $patch_validators$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef('public.school_validate_tuition_bill_income_for_bill(uuid)'::regprocedure);
  if position('school_validate_tuition_generation_revision_for_bill' in v_definition)=0 then
    v_definition:=replace(v_definition,'begin
  if p_bill_id is null then','begin
  perform public.school_validate_tuition_generation_revision_for_bill(p_bill_id);
  if p_bill_id is null then');
    if position('school_validate_tuition_generation_revision_for_bill' in v_definition)=0 then
      raise exception 'TUITION_INCOME_VALIDATOR_PATCH_FAILED';
    end if;
    execute v_definition;
  end if;

  v_definition:=pg_get_functiondef('public.school_validate_tuition_bill_lessons_for_bill(uuid)'::regprocedure);
  v_definition:=replace(v_definition,
    'v_identity public.school_student_tuition_billing_identities%ROWTYPE;',
    'v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_revision public.school_student_tuition_generation_revisions%ROWTYPE;');
  v_definition:=replace(v_definition,
    'BEGIN
  IF p_bill_id IS NULL THEN RETURN; END IF;',
    'BEGIN
  PERFORM public.school_validate_tuition_generation_revision_for_bill(p_bill_id);
  IF p_bill_id IS NULL THEN RETURN; END IF;');
  v_definition:=replace(v_definition,
    'SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.canonical_bill_id=v_bill.id;',
    'SELECT revision_row.* INTO v_revision
  FROM public.school_student_tuition_generation_revisions revision_row
  WHERE revision_row.tuition_bill_id=v_bill.id;
  SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_generation_identities generation_row
  JOIN public.school_student_tuition_billing_identities identity_row
    ON identity_row.id=generation_row.legacy_billing_identity_id
  WHERE generation_row.id=v_revision.generation_identity_id;');
  v_definition:=replace(v_definition,
    'IF v_identity.source=''atomic_charge''
     AND v_identity.evidence->>''generation_source''=''student_tuition_atomic_generate_v1'' THEN',
    'IF v_revision.manifest_kind=''atomic_generation_v1'' THEN');
  v_definition:=replace(v_definition,
    'OR v_identity.evidence->>''generation_manifest_sha256''
            IS DISTINCT FROM v_bill.source_snapshot->>''generation_manifest_sha256''
       OR v_identity.evidence->>''candidate_manifest_sha256''
            IS DISTINCT FROM v_bill.source_snapshot->>''candidate_manifest_sha256''',
    'OR v_revision.generation_manifest_sha256
            IS DISTINCT FROM v_bill.source_snapshot->>''generation_manifest_sha256''');
  v_definition:=replace(v_definition,
    'OR v_identity.evidence->>''business_entity_id''
            IS DISTINCT FROM v_bill.business_entity_id::text','');
  if position('v_revision.manifest_kind=''atomic_generation_v1''' in v_definition)=0
     or position('school_validate_tuition_generation_revision_for_bill' in v_definition)=0 then
    raise exception 'TUITION_LESSON_VALIDATOR_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch_validators$;

do $patch_active_readers$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_list_student_tuition_charge_candidates(uuid,uuid,text,boolean)'::regprocedure);
  if position('school_active_student_tuition_bill_lessons' in v_definition)=0 then
    v_definition:=replace(v_definition,'public.school_student_tuition_bill_lessons',
      'public.school_active_student_tuition_bill_lessons');
    if position('school_active_student_tuition_bill_lessons' in v_definition)=0 then
      raise exception 'TUITION_CANDIDATE_ACTIVE_READER_PATCH_FAILED';
    end if;
    execute v_definition;
  end if;
  v_definition:=pg_get_functiondef('public.school_enforce_r2_e_planned_aircon()'::regprocedure);
  if position('school_active_student_tuition_bill_lessons' in v_definition)=0 then
    v_definition:=replace(v_definition,'public.school_student_tuition_bill_lessons',
      'public.school_active_student_tuition_bill_lessons');
    if position('school_active_student_tuition_bill_lessons' in v_definition)=0 then
      raise exception 'TUITION_LESSON_GUARD_ACTIVE_READER_PATCH_FAILED';
    end if;
    execute v_definition;
  end if;
end;
$patch_active_readers$;

create or replace function public.school_get_student_tuition_validation_preview_details(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric
) returns table(
  feature_state text,generate_feature_state text,student_id uuid,business_entity_id uuid,
  billing_month text,previous_settlement_month text,previous_settlement_id uuid,
  previous_carryover_cny numeric,candidate_count integer,total_lesson_count integer,
  total_duration_hours numeric,total_base_lesson_fee_jpy numeric,total_aircon_fee_jpy numeric,
  total_fee_jpy numeric,bill_amount_jpy numeric,currency text,billing_exchange_rate numeric,
  billing_amount_cny numeric,billing_amount_currency text,existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,existing_income_record_id uuid,existing_income_status text,
  candidate_uuid_md5 text,candidate_manifest_sha256 text,generation_manifest_sha256 text,
  candidates jsonb,message text
) language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare
  v_preview_state text; v_generate_state text; v_month text:=btrim(coalesce(p_billing_month,''));
  v_student public.school_students%rowtype; v_generation public.school_student_tuition_generation_identities%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_bill public.school_student_tuition_bills%rowtype; v_income public.school_income_records%rowtype;
  v_snapshot record; v_active_count integer; v_message text;
begin
  select state into strict v_preview_state from public.school_feature_gates where feature_key='student_tuition_preview';
  select state into strict v_generate_state from public.school_feature_gates where feature_key='student_tuition_generate';
  if v_preview_state not in ('validation_preview_only','enabled') or v_generate_state not in ('blocked','enabled') then
    raise exception 'TUITION_PREVIEW_BLOCKED';
  end if;
  if p_student_id is null or v_month!~'^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_billing_exchange_rate is null or p_billing_exchange_rate<=0 then
    raise exception 'R2_F_B_PREVIEW_INPUT_INVALID';
  end if;
  select s.* into strict v_student from public.school_students s
  where s.id=p_student_id and s.app_type='school';
  if v_student.business_entity_id is null then raise exception 'R2_F_B_BUSINESS_ENTITY_REQUIRED'; end if;
  select g.* into v_generation from public.school_student_tuition_generation_identities g
  where g.student_id=p_student_id and g.business_entity_id=v_student.business_entity_id
    and g.billing_month=to_date(v_month||'-01','YYYY-MM-DD');
  if found then
    select count(*)::integer into v_active_count from public.school_student_tuition_generation_revisions r
    where r.generation_identity_id=v_generation.id and r.lifecycle_status='active';
    if v_active_count>1 then raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'; end if;
    if v_active_count=1 then
      select r.* into strict v_revision from public.school_student_tuition_generation_revisions r
      where r.generation_identity_id=v_generation.id and r.lifecycle_status='active';
      select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_revision.tuition_bill_id;
      select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id;
      perform public.school_validate_tuition_identity_for_bill(v_bill.id);
      perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
      perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
      if v_bill.status<>'income_created' or v_income.status not in ('pending','received') then
        raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
      end if;
      raise exception 'R2_F_B_ALREADY_BILLED';
    end if;
  elsif exists(select 1 from public.school_student_tuition_billing_identities i
    where i.student_id=p_student_id and i.billing_month=v_month) then
    raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
  end if;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,v_month,p_billing_exchange_rate);
  v_message:=case when v_generate_state='enabled' then 'authoritative preview ready for atomic generation; no business data written'
    else 'validation preview only; no business data written' end;
  return query select v_preview_state,v_generate_state,v_snapshot.student_id,v_snapshot.business_entity_id,
    v_snapshot.billing_month,v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,v_snapshot.total_lesson_count,
    v_snapshot.total_duration_hours,v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY'::text,v_snapshot.billing_exchange_rate,
    v_snapshot.billing_amount_cny,'CNY'::text,null::uuid,null::text,null::uuid,null::text,
    v_snapshot.candidate_uuid_md5,v_snapshot.candidate_manifest_sha256,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidates,v_message;
end;
$function$;
revoke all on function public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  from public,anon;
grant execute on function public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)
  to authenticated,service_role;
