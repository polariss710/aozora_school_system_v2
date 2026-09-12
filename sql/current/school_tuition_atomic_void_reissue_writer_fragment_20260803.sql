-- Atomic Generate revision writer and dedicated Void. Included inside migration transaction.

do $clone_base_core$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure);
  v_definition:=replace(v_definition,
    'school_generate_student_tuition_bill_atomic_core',
    'school_generate_student_tuition_bill_atomic_base_core_v1');
  v_definition:=replace(v_definition,
    'PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
      PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);',
    'NULL; -- revision wrapper validates after registering revision authority');
  v_definition:=replace(v_definition,
    'PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);',
    'NULL; -- revision wrapper validates after registering revision authority');
  execute v_definition;
end;
$clone_base_core$;
revoke all on function public.school_generate_student_tuition_bill_atomic_base_core_v1(
  uuid,text,numeric,text,text,text) from public,anon,authenticated,service_role;

create function public.school_generate_student_tuition_next_revision_core(
  p_generation_identity_id uuid,p_previous_revision_id uuid,p_student_id uuid,
  p_billing_month text,p_billing_exchange_rate numeric,
  p_expected_generation_manifest_sha256 text,p_note text,p_test_fail_after_step text
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
  v_legacy public.school_student_tuition_billing_identities%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_snapshot record; v_ids uuid[]; v_locked_ids uuid[]; v_line jsonb; v_line_no integer:=0;
  v_revision_no integer; v_revision_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp(); v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_operator text:='service_role_v2_operations_v1';
begin
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id for update;
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.id=p_previous_revision_id and r.generation_identity_id=v_generation.id for update;
  if v_previous.lifecycle_status<>'voided' or v_previous.manifest_kind<>'atomic_generation_v1' then
    raise exception 'TUITION_REISSUE_PREVIOUS_REVISION_INVALID';
  end if;
  v_revision_no:=v_previous.revision_no+1;
  select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
  where i.id=v_generation.legacy_billing_identity_id;
  lock table public.school_lesson_records in share mode;
  lock table public.school_student_monthly_settlements in share mode;
  lock table public.school_student_settlement_carryovers in share mode;
  lock table public.school_student_settlement_adjustment_drafts in share mode;
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if cardinality(v_ids)=0 then raise exception 'R2_F_B_CANDIDATES_EMPTY'; end if;
  perform public.school_assert_active_tuition_lesson_claim(x) from unnest(v_ids) x order by x;
  perform 1 from public.school_lesson_records l where l.id=any(v_ids) order by l.id for update;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate);
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_locked_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if v_locked_ids is distinct from v_ids then raise exception 'R2_F_B_CANDIDATE_SET_CHANGED_DURING_LOCK'; end if;
  if v_snapshot.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256 then
    raise exception 'R2_F_B_STALE_GENERATION_MANIFEST';
  end if;
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  insert into public.school_student_tuition_bills(
    student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) values(
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,v_snapshot.total_duration_hours,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,
      'generation_identity_id',v_generation.id,'generation_revision_id',v_revision_id,
      'revision_no',v_revision_no,'previous_revision_id',v_previous.id,
      'student_id',v_snapshot.student_id,'business_entity_id',v_snapshot.business_entity_id,
      'billing_month',v_snapshot.billing_month,'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence',v_snapshot.carryover_evidence,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_duration_hours',v_snapshot.total_duration_hours,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'planned_lesson_ids',(select jsonb_agg(line->'planned_lesson_id') from jsonb_array_elements(v_snapshot.candidates) line),
      'candidate_lines',v_snapshot.candidates,'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,'billing_amount_currency','CNY'
    ),v_note,'school',v_operator,v_operator,v_now,v_now,v_snapshot.billing_exchange_rate,
    v_snapshot.billing_amount_cny,v_now,'canonical_charge',false
  ) returning * into v_bill;
  for v_line in select value from jsonb_array_elements(v_snapshot.candidates) loop
    v_line_no:=v_line_no+1;
    insert into public.school_student_tuition_bill_lessons(
      tuition_bill_id,planned_lesson_id,relation_role,line_no,student_id_snapshot,
      business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
      scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
      lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
      lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,attribution_confidence,
      snapshot_source,created_by,base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
      aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy_snapshot,
      fee_calculation_version_snapshot,lesson_venue_id_snapshot,lesson_venue_code_snapshot
    ) values(
      v_bill.id,(v_line->>'planned_lesson_id')::uuid,'canonical_charge',v_line_no,
      (v_line->>'student_id')::uuid,(v_line->>'business_entity_id')::uuid,v_line->>'billing_month',
      (v_line->>'billing_week_start_date')::date,(v_line->>'lesson_date')::date,
      (v_line->>'teacher_id')::uuid,(v_line->>'subject_id')::uuid,
      (v_line->>'lesson_count')::integer,(v_line->>'duration_hours')::numeric,
      (v_line->>'unit_price_jpy')::numeric,(v_line->>'course_total_jpy')::numeric,
      (v_line->>'source_lesson_updated_at')::timestamptz,
      v_line||jsonb_build_object('generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256),
      'high','student_tuition_atomic_generate_v1',v_operator,
      (v_line->>'base_lesson_fee_jpy')::numeric,null,
      (v_line->>'aircon_rate_jpy_per_hour')::integer,(v_line->>'aircon_billable_hours')::numeric,
      (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
      nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code');
  end loop;
  if p_test_fail_after_step='after_relations' then raise exception 'R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS'; end if;
  insert into public.school_income_records(
    business_entity_id,student_id,student_payment_id,account_id,income_date,year_month,
    settlement_month,income_category,description,currency,amount,amount_jpy,amount_cny,
    exchange_rate,payment_currency,payment_method,status,is_taxable_income,tax_category,
    receipt_status,include_in_student_settlement,note,source_type,source_id,source_label,
    source_snapshot,app_type,created_at,updated_at,tuition_bill_id,cash_submission_blocked,
    operational_excluded
  ) values(
    v_snapshot.business_entity_id,v_snapshot.student_id,null,null,current_date,v_snapshot.billing_month,
    v_snapshot.billing_month,'tuition',v_snapshot.billing_month||' 学费应收','JPY',
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,null,null,'JPY',null,'pending',false,null,
    'Cash待提交',true,v_note,'student_tuition_bill',v_bill.id,v_snapshot.billing_month||' 学费应收',
    jsonb_build_object('generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,'tuition_bill_id',v_bill.id,
      'billing_identity_id',v_legacy.id,'generation_identity_id',v_generation.id,
      'generation_revision_id',v_revision_id,'revision_no',v_revision_no,
      'billing_month',v_snapshot.billing_month,'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'),'school',v_now,v_now,v_bill.id,false,false
  ) returning * into v_income;
  update public.school_student_tuition_bills set status='income_created',income_record_id=v_income.id,
    income_created_at=v_now,updated_by=v_operator,updated_at=v_now where id=v_bill.id returning * into v_bill;
  insert into public.school_student_tuition_generation_revisions(
    id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
    generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority
  ) values(v_revision_id,v_generation.id,v_bill.id,v_revision_no,v_previous.id,
    v_snapshot.generation_manifest_sha256,'atomic_generation_v1','active',v_now,v_operator);
  delete from public.school_tuition_atomic_writer_context where backend_pid=pg_backend_pid()
    and transaction_id=txid_current();
  perform public.school_validate_tuition_identity_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  return query select v_bill.id,v_legacy.id,v_income.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,v_snapshot.generation_manifest_sha256,
    v_snapshot.candidate_count,v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,v_snapshot.total_fee_jpy,
    v_snapshot.billing_exchange_rate,v_snapshot.previous_carryover_cny,v_snapshot.billing_amount_cny,
    v_bill.status,v_income.status,false,'atomic tuition revision created'::text;
end;
$function$;
revoke all on function public.school_generate_student_tuition_next_revision_core(
  uuid,uuid,uuid,text,numeric,text,text,text) from public,anon,authenticated,service_role;

create or replace function public.school_generate_student_tuition_bill_atomic_core(
  p_student_id uuid,p_billing_month text,p_billing_exchange_rate numeric,
  p_expected_generation_manifest_sha256 text,p_note text default null,
  p_test_fail_after_step text default null
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
  v_student public.school_students%rowtype; v_generation public.school_student_tuition_generation_identities%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_bill public.school_student_tuition_bills%rowtype; v_income public.school_income_records%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype; v_result record;
  v_month date;
begin
  if p_billing_month is null or btrim(p_billing_month)!~'^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_billing_exchange_rate is null or p_billing_exchange_rate<=0
     or p_expected_generation_manifest_sha256!~'^[0-9a-f]{64}$' then
    raise exception 'R2_F_B_GENERATION_INPUT_INVALID';
  end if;
  v_month:=to_date(btrim(p_billing_month)||'-01','YYYY-MM-DD');
  select s.* into strict v_student from public.school_students s
  where s.id=p_student_id and s.app_type='school';
  perform public.school_lock_student_tuition_operation(p_student_id,v_student.business_entity_id,(v_month-interval '1 month')::date);
  perform public.school_lock_student_tuition_operation(p_student_id,v_student.business_entity_id,v_month);
  select g.* into v_generation from public.school_student_tuition_generation_identities g
  where g.student_id=p_student_id and g.business_entity_id=v_student.business_entity_id
    and g.billing_month=v_month for update;
  if not found then
    select * into strict v_result from public.school_generate_student_tuition_bill_atomic_base_core_v1(
      p_student_id,p_billing_month,p_billing_exchange_rate,p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step);
    select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
    where i.id=v_result.billing_identity_id;
    insert into public.school_student_tuition_generation_identities(
      id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
    ) values(gen_random_uuid(),p_student_id,v_student.business_entity_id,v_month,v_legacy.id,now(),'service_role_v2_operations_v1')
    returning * into v_generation;
    insert into public.school_student_tuition_generation_revisions(
      id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
      generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority
    ) values(gen_random_uuid(),v_generation.id,v_result.tuition_bill_id,1,null,
      p_expected_generation_manifest_sha256,'atomic_generation_v1','active',now(),'service_role_v2_operations_v1');
    perform public.school_validate_tuition_identity_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_result.tuition_bill_id);
    return query select v_result.*; return;
  end if;
  select r.* into v_revision from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=v_generation.id and r.lifecycle_status='active' for update;
  if found then
    if v_revision.manifest_kind<>'atomic_generation_v1'
       or v_revision.generation_manifest_sha256<>p_expected_generation_manifest_sha256 then
      raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
    end if;
    select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_revision.tuition_bill_id for update;
    select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id for update;
    select l.* into strict v_legacy from public.school_student_tuition_billing_identities l
      where l.id=v_generation.legacy_billing_identity_id;
    if v_bill.billing_exchange_rate<>p_billing_exchange_rate or v_bill.status<>'income_created'
       or v_income.status<>'pending' then raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'; end if;
    perform public.school_validate_tuition_identity_for_bill(v_bill.id);
    perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
    return query select v_bill.id,v_legacy.id,v_income.id,v_bill.student_id,v_bill.business_entity_id,
      v_bill.billing_month,v_revision.generation_manifest_sha256,v_bill.planned_lesson_count,
      (v_bill.source_snapshot->>'total_lesson_count')::integer,v_bill.planned_lesson_hours,
      (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric,
      (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric,v_bill.bill_amount_jpy,
      v_bill.billing_exchange_rate,v_bill.previous_carryover_cny,v_bill.billing_amount_cny,
      v_bill.status,v_income.status,true,'existing active tuition revision returned idempotently'::text;
    return;
  end if;
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=v_generation.id order by r.revision_no desc limit 1 for update;
  if v_previous.manifest_kind='historical_registration_v1' then
    raise exception 'TUITION_HISTORICAL_REVISION_REISSUE_FORBIDDEN';
  end if;
  return query select * from public.school_generate_student_tuition_next_revision_core(
    v_generation.id,v_previous.id,p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step);
end;
$function$;
revoke all on function public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)
  from public,anon,authenticated,service_role;

create function public.school_void_atomic_student_tuition_generation_core(
  p_income_record_id uuid,p_expected_generation_manifest_sha256 text,p_reason text
) returns table(
  generation_identity_id uuid,generation_revision_id uuid,tuition_bill_id uuid,
  income_record_id uuid,revision_no integer,lifecycle_status text,bill_status text,
  income_status text,void_event_id uuid,idempotent boolean,message text
) language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_income_initial public.school_income_records%rowtype; v_income public.school_income_records%rowtype;
  v_bill public.school_student_tuition_bills%rowtype; v_generation public.school_student_tuition_generation_identities%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype; v_event public.school_student_tuition_generation_void_events%rowtype;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),''); v_now timestamptz:=clock_timestamp();
  v_linkage_count integer; v_event_id uuid:=gen_random_uuid();
begin
  if p_income_record_id is null or p_expected_generation_manifest_sha256!~'^[0-9a-f]{64}$' or v_reason is null then
    raise exception 'TUITION_ATOMIC_VOID_INPUT_INVALID';
  end if;
  select i.* into strict v_income_initial from public.school_income_records i where i.id=p_income_record_id;
  select b.* into strict v_bill from public.school_student_tuition_bills b
  where b.id=v_income_initial.tuition_bill_id;
  perform public.school_lock_student_tuition_operation(v_bill.student_id,v_bill.business_entity_id,
    to_date(v_bill.billing_month||'-01','YYYY-MM-DD'));
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.student_id=v_bill.student_id and g.business_entity_id=v_bill.business_entity_id
    and g.billing_month=to_date(v_bill.billing_month||'-01','YYYY-MM-DD') for update;
  select r.* into v_revision from public.school_student_tuition_generation_revisions r
  where r.tuition_bill_id=v_bill.id for update;
  if not found then raise exception 'TUITION_ATOMIC_VOID_REVISION_NOT_FOUND'; end if;
  if v_revision.manifest_kind='historical_registration_v1' then
    raise exception 'TUITION_HISTORICAL_REVISION_VOID_FORBIDDEN';
  end if;
  select e.* into v_event from public.school_student_tuition_generation_void_events e
  where e.generation_revision_id=v_revision.id;
  if v_revision.lifecycle_status='voided' and found then
    if v_event.expected_generation_manifest_sha256<>p_expected_generation_manifest_sha256
       or v_event.reason<>v_reason then raise exception 'TUITION_ATOMIC_VOID_IDEMPOTENCY_CONFLICT'; end if;
    return query select v_generation.id,v_revision.id,v_bill.id,p_income_record_id,v_revision.revision_no,
      v_revision.lifecycle_status,v_bill.status,v_income_initial.status,v_event.id,true,
      'existing atomic tuition void returned idempotently'::text; return;
  end if;
  if v_revision.lifecycle_status<>'active' or v_revision.generation_manifest_sha256<>p_expected_generation_manifest_sha256 then
    raise exception 'TUITION_ATOMIC_VOID_STALE_MANIFEST_OR_REVISION';
  end if;
  select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_revision.tuition_bill_id for update;
  select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id for update;
  if v_income.id<>p_income_record_id or v_income.status<>'pending' or v_bill.status<>'income_created'
     or v_bill.source_snapshot->>'generation_source'<>'student_tuition_atomic_generate_v1' then
    raise exception 'TUITION_ATOMIC_VOID_CHAIN_INELIGIBLE';
  end if;
  perform public.school_validate_tuition_identity_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  select count(*)::integer into v_linkage_count from public.school_personal_cash_income_linkage_events e
  where e.income_record_id=v_income.id or (e.source_table='school_income_records' and e.source_id=v_income.id);
  if v_linkage_count<>0 then raise exception 'TUITION_ATOMIC_VOID_CASH_RESERVATION_EXISTS'; end if;
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
    values(pg_backend_pid(),txid_current(),'student_tuition_atomic_void_v1');
  update public.school_student_tuition_generation_revisions set lifecycle_status='voided'
    where id=v_revision.id returning * into v_revision;
  update public.school_income_records set status='cancelled',cancelled_at=v_now,
    cancelled_reason=v_reason,cancelled_by='service_role_v2_operations_v1',updated_at=v_now
    where id=v_income.id returning * into v_income;
  update public.school_student_tuition_bills set status='cancelled',cancelled_at=v_now,
    cancelled_reason=v_reason,updated_at=v_now,updated_by='service_role_v2_operations_v1'
    where id=v_bill.id returning * into v_bill;
  insert into public.school_student_tuition_generation_void_events(
    id,generation_revision_id,expected_generation_manifest_sha256,reason,operator_authority,
    precondition_evidence,result_evidence,created_at
  ) values(v_event_id,v_revision.id,p_expected_generation_manifest_sha256,v_reason,
    'service_role_v2_operations_v1',jsonb_build_object('income_status','pending','bill_status','income_created',
      'linkage_count',v_linkage_count,'manifest_kind',v_revision.manifest_kind),
    jsonb_build_object('income_status',v_income.status,'bill_status',v_bill.status,
      'revision_status',v_revision.lifecycle_status),v_now);
  delete from public.school_tuition_atomic_writer_context where backend_pid=pg_backend_pid()
    and transaction_id=txid_current();
  return query select v_generation.id,v_revision.id,v_bill.id,v_income.id,v_revision.revision_no,
    v_revision.lifecycle_status,v_bill.status,v_income.status,v_event_id,false,
    'atomic tuition generation voided; historical chain retained'::text;
end;
$function$;
revoke all on function public.school_void_atomic_student_tuition_generation_core(uuid,text,text)
  from public,anon,authenticated,service_role;

create function public.school_void_atomic_student_tuition_generation(
  p_income_record_id uuid,p_expected_generation_manifest_sha256 text,p_reason text
) returns table(
  generation_identity_id uuid,generation_revision_id uuid,tuition_bill_id uuid,
  income_record_id uuid,revision_no integer,lifecycle_status text,bill_status text,
  income_status text,void_event_id uuid,idempotent boolean,message text
) language sql security definer set search_path=pg_catalog,public
as $function$
  select * from public.school_void_atomic_student_tuition_generation_core(
    p_income_record_id,p_expected_generation_manifest_sha256,p_reason);
$function$;
revoke all on function public.school_void_atomic_student_tuition_generation(uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.school_void_atomic_student_tuition_generation(uuid,text,text)
  to service_role;
