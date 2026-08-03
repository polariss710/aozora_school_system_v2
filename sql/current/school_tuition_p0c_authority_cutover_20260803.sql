-- Active revision reader/validator cutover. Included inside migration transaction.

do $capture_p0c_rollback_baselines$
declare
  v_signature text;
  v_original_name text;
  v_backup_name text;
  v_definition text;
  v_backup_signature text;
begin
  for v_signature,v_original_name,v_backup_name in
    select * from (values
      ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','school_generate_student_tuition_bill_atomic_core','school_p0c_baseline_generate_atomic_core'),
      ('public.school_validate_tuition_identity_for_bill(uuid)','school_validate_tuition_identity_for_bill','school_p0c_baseline_validate_tuition_identity_for_bill'),
      ('public.school_validate_tuition_bill_income_for_bill(uuid)','school_validate_tuition_bill_income_for_bill','school_p0c_baseline_validate_tuition_bill_income_for_bill'),
      ('public.school_validate_tuition_bill_lessons_for_bill(uuid)','school_validate_tuition_bill_lessons_for_bill','school_p0c_baseline_validate_tuition_bill_lessons_for_bill'),
      ('public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)','school_list_student_tuition_candidates','school_p0c_baseline_list_student_tuition_candidates'),
      ('public.school_enforce_r2_e_planned_aircon()','school_enforce_r2_e_planned_aircon','school_p0c_baseline_enforce_r2_e_planned_aircon'),
      ('public.school_tuition_p0b1_lesson_financial_authority()','school_tuition_p0b1_lesson_financial_authority','school_p0c_baseline_tuition_p0b1_lesson_financial_authority'),
      ('public.school_guard_r0_tuition_business_mutation()','school_guard_r0_tuition_business_mutation','school_p0c_baseline_guard_r0_tuition_business_mutation'),
      ('public.school_guard_tuition_identity_or_lesson_immutable()','school_guard_tuition_identity_or_lesson_immutable','school_p0c_baseline_guard_tuition_identity_or_lesson'),
      ('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)','school_update_lesson_record_guarded','school_p0c_baseline_update_lesson_record_guarded'),
      ('public.school_get_student_tuition_validation_preview_details(uuid,text,numeric)','school_get_student_tuition_validation_preview_details','school_p0c_baseline_tuition_preview_details'),
      ('public.school_tuition_p0a_consumed_bill_id(uuid)','school_tuition_p0a_consumed_bill_id','school_p0c_baseline_tuition_p0a_consumed_bill_id'),
      ('public.school_get_cash_income_submission_preflight(uuid[])','school_get_cash_income_submission_preflight','school_p0c_baseline_get_cash_income_submission_preflight'),
      ('public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','school_request_cash_income_confirmation_for_record','school_p0c_baseline_request_cash_income_confirmation_for_record')
    ) x(signature,original_name,backup_name)
  loop
    v_definition:=pg_get_functiondef(v_signature::regprocedure);
    v_definition:=replace(v_definition,v_original_name,v_backup_name);
    execute v_definition;
    v_backup_signature:=replace(v_signature,v_original_name,v_backup_name);
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_backup_signature);
  end loop;
end;
$capture_p0c_rollback_baselines$;

do $patch_atomic_void_writer_context$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_guard_r0_tuition_business_mutation()'::regprocedure);
  v_definition:=replace(v_definition,
    '''student_tuition_atomic_generate_v1'', ''legacy_tuition_cancel''',
    '''student_tuition_atomic_generate_v1'', ''legacy_tuition_cancel'', ''student_tuition_atomic_void_v1''');
  if position('student_tuition_atomic_void_v1' in v_definition)=0 then
    raise exception 'TUITION_VOID_WRITER_CONTEXT_GUARD_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch_atomic_void_writer_context$;

do $patch_fixed_fixture_cleanup_guard$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_guard_tuition_identity_or_lesson_immutable()'::regprocedure);
  v_definition:=replace(v_definition,
    'begin
  raise exception',
    'begin
  if tg_op=''DELETE'' and session_user=''postgres''
     and current_setting(''tuition.p0c_fixture_cleanup'',true)
       =''codex-test atomic-void-reissue-p0c-20260803''
     and ((tg_table_name=''school_student_tuition_billing_identities''
           and old.id=''c0c00000-0000-4000-8000-000000002001''::uuid)
       or (tg_table_name=''school_student_tuition_bill_lessons''
           and old.id in (''c0c00000-0000-4000-8000-000000005001''::uuid,
                          ''c0c00000-0000-4000-8000-000000005002''::uuid))) then
    return old;
  end if;
  raise exception');
  if position('c0c00000-0000-4000-8000-000000002001' in v_definition)=0 then
    raise exception 'TUITION_P0C_FIXTURE_IMMUTABLE_GUARD_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch_fixed_fixture_cleanup_guard$;

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
     or (v_revision.manifest_kind='atomic_generation_v1'
       and v_generation.business_entity_id<>v_bill.business_entity_id)
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
    and (r.manifest_kind='historical_registration_v1'
      or g.business_entity_id=v_bill.business_entity_id)
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
declare v_definition text; v_signature text;
begin
  -- The charge-candidate wrapper delegates to the raw candidate reader below;
  -- it does not read normalized relations directly.
  foreach v_signature in array array[
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
    'public.school_enforce_r2_e_planned_aircon()',
    'public.school_tuition_p0b1_lesson_financial_authority()',
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'
  ] loop
    v_definition:=pg_get_functiondef(v_signature::regprocedure);
    if position('public.school_student_tuition_bill_lessons' in v_definition)>0 then
      v_definition:=replace(v_definition,'public.school_student_tuition_bill_lessons',
        'public.school_active_student_tuition_bill_lessons');
    end if;
    if v_signature='public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)' then
      v_definition:=replace(v_definition,
        'FROM public.school_student_tuition_bills bill',
        'FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status=''active''');
      if position('active_revision.lifecycle_status=''active''' in v_definition)=0 then
        raise exception 'TUITION_ACTIVE_SNAPSHOT_READER_PATCH_FAILED';
      end if;
    end if;
    execute v_definition;
    if position('public.school_student_tuition_bill_lessons' in
      pg_get_functiondef(v_signature::regprocedure))>0 then
      raise exception 'TUITION_ACTIVE_RELATION_READER_PATCH_FAILED: %',v_signature;
    end if;
  end loop;
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
  v_snapshot record; v_active_count integer; v_next_revision_no integer:=1; v_message text;
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
    select coalesce(max(r.revision_no),0)+1 into v_next_revision_no
    from public.school_student_tuition_generation_revisions r
    where r.generation_identity_id=v_generation.id;
  elsif exists(select 1 from public.school_student_tuition_billing_identities i
    where i.student_id=p_student_id and i.billing_month=v_month) then
    raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
  end if;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,v_month,p_billing_exchange_rate);
  v_message:=format('将生成 revision %s；%s',v_next_revision_no,
    case when v_generate_state='enabled' then 'authoritative preview ready for atomic generation; no business data written'
      else 'validation preview only; no business data written' end);
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

create or replace function public.school_tuition_p0a_consumed_bill_id(
  p_settlement_id uuid
) returns uuid
language sql stable security definer set search_path=pg_catalog,public
as $function$
  select bill.id
  from public.school_student_tuition_generation_revisions revision
  join public.school_student_tuition_generation_identities generation
    on generation.id=revision.generation_identity_id
  join public.school_student_tuition_bills bill
    on bill.id=revision.tuition_bill_id
  where bill.previous_settlement_id=p_settlement_id
    and bill.app_type='school'
    and bill.billing_role='canonical_charge'
    and generation.student_id=bill.student_id
    and generation.business_entity_id=bill.business_entity_id
    and to_char(generation.billing_month,'YYYY-MM')=bill.billing_month
  order by revision.created_at,revision.id
  limit 1
$function$;
revoke all on function public.school_tuition_p0a_consumed_bill_id(uuid)
  from public,anon,authenticated,service_role;

do $patch_cash_preflight_active_revision$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_get_cash_income_submission_preflight(uuid[])'::regprocedure);
  v_definition:=replace(v_definition,
    'left join public.school_student_tuition_billing_identities identity_row
      on identity_row.canonical_bill_id = bill_row.id
     and identity_row.student_id = bill_row.student_id
     and identity_row.billing_month = bill_row.billing_month',
    'left join public.school_student_tuition_generation_revisions revision_row
      on revision_row.tuition_bill_id = bill_row.id
     and revision_row.lifecycle_status = ''active''
    left join public.school_student_tuition_generation_identities generation_row
      on generation_row.id = revision_row.generation_identity_id
     and generation_row.student_id = bill_row.student_id
     and (revision_row.manifest_kind = ''historical_registration_v1''
       or generation_row.business_entity_id = bill_row.business_entity_id)
     and to_char(generation_row.billing_month,''YYYY-MM'') = bill_row.billing_month
    left join public.school_student_tuition_billing_identities identity_row
      on identity_row.id = generation_row.legacy_billing_identity_id');
  if position('revision_row.lifecycle_status = ''active''' in v_definition)=0 then
    raise exception 'TUITION_CASH_PREFLIGHT_ACTIVE_REVISION_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch_cash_preflight_active_revision$;

create function public.school_get_atomic_tuition_void_preflight(p_income_record_id uuid)
returns table(
  income_record_id uuid,tuition_bill_id uuid,generation_identity_id uuid,
  generation_revision_id uuid,revision_no integer,manifest_kind text,
  generation_manifest_sha256 text,lifecycle_status text,student_id uuid,
  student_name text,business_entity_id uuid,business_entity_name text,billing_month text,
  bill_status text,income_status text,bill_amount_jpy numeric,billing_amount_cny numeric,
  billing_exchange_rate numeric,lesson_count integer,previous_carryover_cny numeric,
  school_cash_linkage_count integer,school_account_transaction_count integer,
  downstream_actual_count integer,downstream_wage_count integer,
  eligible boolean,blocker_code text,blocker_message text,
  void_reason text,voided_at timestamptz,next_revision_no integer
)
language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare
  v_income public.school_income_records%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_event public.school_student_tuition_generation_void_events%rowtype;
  v_student_name text; v_entity_name text;
  v_linkage_count integer:=0; v_transaction_count integer:=0;
  v_actual_count integer:=0; v_wage_count integer:=0; v_settlement_count integer:=0;
  v_lesson_count integer:=0;
  v_code text; v_message text; v_valid boolean:=true;
begin
  select i.* into v_income from public.school_income_records i where i.id=p_income_record_id;
  if not found then raise exception 'TUITION_VOID_INCOME_NOT_FOUND'; end if;
  select b.* into v_bill from public.school_student_tuition_bills b
  where b.id=v_income.tuition_bill_id and b.id=v_income.source_id;
  select r.* into v_revision from public.school_student_tuition_generation_revisions r
  where r.tuition_bill_id=v_bill.id;
  if found then
    select g.* into v_generation from public.school_student_tuition_generation_identities g
    where g.id=v_revision.generation_identity_id;
    select e.* into v_event from public.school_student_tuition_generation_void_events e
    where e.generation_revision_id=v_revision.id;
  end if;
  select coalesce(s.display_name,s.name) into v_student_name
  from public.school_students s where s.id=v_income.student_id;
  select e.name into v_entity_name from public.school_business_entities e
  where e.id=v_income.business_entity_id;
  if v_bill.id is not null then
    select count(*)::integer into v_lesson_count
    from public.school_student_tuition_bill_lessons r where r.tuition_bill_id=v_bill.id;
    select count(*)::integer into v_linkage_count
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id=v_income.id
       or (e.source_table='school_income_records' and e.source_id=v_income.id);
    select count(*)::integer into v_transaction_count
    from public.school_account_transactions t
    where t.related_id in (v_income.id,v_bill.id);
    select count(*)::integer into v_actual_count
    from public.school_lesson_records actual
    where actual.lesson_type='actual' and actual.planned_lesson_id in (
      select rel.planned_lesson_id from public.school_student_tuition_bill_lessons rel
      where rel.tuition_bill_id=v_bill.id
    );
    select count(*)::integer into v_wage_count
    from public.school_teacher_wage_lock_details wage
    where wage.lesson_record_id in (
      select rel.planned_lesson_id from public.school_student_tuition_bill_lessons rel
      where rel.tuition_bill_id=v_bill.id
      union
      select actual.id from public.school_lesson_records actual
      where actual.lesson_type='actual' and actual.planned_lesson_id in (
        select rel.planned_lesson_id from public.school_student_tuition_bill_lessons rel
        where rel.tuition_bill_id=v_bill.id
      )
    );
    select count(*)::integer into v_settlement_count
    from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_bill.student_id
      and settlement.business_entity_id is not distinct from v_bill.business_entity_id
      and settlement.year_month=v_bill.billing_month
      and settlement.settlement_status='locked';
  end if;
  if v_revision.id is not null then
    begin
      perform public.school_validate_tuition_identity_for_bill(v_bill.id);
      perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
      perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
    exception when others then v_valid:=false; end;
  end if;
  if v_income.source_type is distinct from 'student_tuition_bill'
     or v_bill.id is null or v_revision.id is null
     or v_revision.manifest_kind is distinct from 'atomic_generation_v1'
     or v_bill.source_snapshot->>'generation_source' is distinct from 'student_tuition_atomic_generate_v1' then
    v_code:='TUITION_VOID_NOT_ATOMIC'; v_message:='不是可由第一版专用流程作废的 Atomic Tuition chain。';
  elsif v_revision.lifecycle_status='voided' then
    v_code:='TUITION_VOID_ALREADY_VOIDED'; v_message:='该 revision 已作废，只能查看历史记录。';
  elsif v_revision.lifecycle_status<>'active' then
    v_code:='TUITION_VOID_NOT_ACTIVE_REVISION'; v_message:='该账单不是当前 active revision。';
  elsif v_revision.generation_manifest_sha256 is distinct from
        v_bill.source_snapshot->>'generation_manifest_sha256' or not v_valid then
    v_code:='TUITION_VOID_MANIFEST_MISMATCH'; v_message:='账单、收入、课时或 manifest 全链验证失败。';
  elsif v_income.status<>'pending' or v_bill.status<>'income_created' then
    v_code:='TUITION_VOID_INCOME_NOT_PENDING'; v_message:='仅 pending income / income_created bill 可作废。';
  elsif v_linkage_count>0 then
    v_code:='TUITION_VOID_CASH_FACT_EXISTS'; v_message:='已存在 School Cash linkage/reservation。';
  elsif v_transaction_count>0 or v_actual_count>0 or v_wage_count>0
        or v_settlement_count>0 then
    v_code:='TUITION_VOID_DOWNSTREAM_FACT_EXISTS'; v_message:='已存在账户流水、actual、工资或其他履约下游事实。';
  else
    v_code:=null; v_message:='School 侧前置通过；受信后端仍须实时确认 Cash DB 无 request/transaction。';
  end if;
  return query select v_income.id,v_bill.id,v_generation.id,v_revision.id,v_revision.revision_no,
    v_revision.manifest_kind,v_revision.generation_manifest_sha256,v_revision.lifecycle_status,
    v_income.student_id,v_student_name,v_income.business_entity_id,v_entity_name,v_bill.billing_month,
    v_bill.status,v_income.status,v_bill.bill_amount_jpy,v_bill.billing_amount_cny,
    v_bill.billing_exchange_rate,v_lesson_count,v_bill.previous_carryover_cny,
    v_linkage_count,v_transaction_count,v_actual_count,v_wage_count,v_code is null,v_code,v_message,
    v_event.reason,v_event.created_at,coalesce(v_revision.revision_no,0)+1;
end;
$function$;
revoke all on function public.school_get_atomic_tuition_void_preflight(uuid)
  from public,anon;
grant execute on function public.school_get_atomic_tuition_void_preflight(uuid)
  to authenticated,service_role;
