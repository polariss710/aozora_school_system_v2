\set ON_ERROR_STOP on
-- P0-D local trusted Atomic Tuition management contract.
-- VERIFIED AND DEPLOYED 2026-08-03; rollback-tested; no new table/column/status/amount formula.

begin;

do $patch_operator_authority$
declare
  v_definition text;
begin
  v_definition := pg_get_functiondef(
    'public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)'::regprocedure
  );
  if position('school.tuition_operator_authority' in v_definition)>0 then
    null;
  elsif position('v_operator text:=''service_role_v2_operations_v1''' in v_definition) = 0 then
    raise exception 'TUITION_P0D_REISSUE_OPERATOR_PATCH_SOURCE_DRIFT';
  else
    v_definition := replace(
      v_definition,
      'v_operator text:=''service_role_v2_operations_v1''',
      'v_operator text:=coalesce(nullif(current_setting(''school.tuition_operator_authority'',true),''''),''service_role_v2_operations_v1'')'
    );
    execute v_definition;
  end if;

  v_definition := pg_get_functiondef(
    'public.school_void_atomic_student_tuition_generation_core(uuid,uuid,uuid,text,text)'::regprocedure
  );
  if position('school.tuition_operator_authority' in v_definition)>0 then
    null;
  elsif position('v_reason text:=nullif' in v_definition) = 0
     or position('''service_role_v2_operations_v1''' in v_definition) = 0 then
    raise exception 'TUITION_P0D_VOID_OPERATOR_PATCH_SOURCE_DRIFT';
  else
    v_definition := replace(v_definition, '''service_role_v2_operations_v1''', 'v_operator');
    v_definition := replace(
      v_definition,
      'v_reason text:=nullif',
      'v_operator text:=coalesce(nullif(current_setting(''school.tuition_operator_authority'',true),''''),''service_role_v2_operations_v1'');
  v_reason text:=nullif'
    );
    execute v_definition;
  end if;
end
$patch_operator_authority$;

create or replace function public.school_guard_p0c_generation_direct_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if session_user='postgres' and (
       current_setting('tuition.p0c_fixture_cleanup',true)
         ='codex-test atomic-void-reissue-p0c-20260803'
       or current_setting('tuition.p0d_fixture_cleanup',true)
         ='codex-test tuition-p0d-e2e-readiness-20260803'
     ) then
    return null;
  end if;
  raise exception 'TUITION_P0C_DIRECT_DELETE_FORBIDDEN';
end
$function$;
revoke all on function public.school_guard_p0c_generation_direct_delete()
  from public,anon,authenticated,service_role;

create or replace function public.school_guard_tuition_identity_or_lesson_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres' then
    if current_setting('tuition.p0c_fixture_cleanup',true)
         ='codex-test atomic-void-reissue-p0c-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and old.id='c0c00000-0000-4000-8000-000000002001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and old.id in ('c0c00000-0000-4000-8000-000000005001'::uuid,
                            'c0c00000-0000-4000-8000-000000005002'::uuid))) then
      return old;
    end if;
    if current_setting('tuition.p0d_fixture_cleanup',true)
         ='codex-test tuition-p0d-e2e-readiness-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and old.id='d0d00000-0000-4000-8000-000000002001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and old.id in ('d0d00000-0000-4000-8000-000000005001'::uuid,
                            'd0d00000-0000-4000-8000-000000005002'::uuid))) then
      return old;
    end if;
  end if;
  raise exception 'TUITION_IMMUTABLE_ROW: % rows cannot be updated or deleted.',tg_table_name;
end
$function$;
revoke all on function public.school_guard_tuition_identity_or_lesson_immutable()
  from public,anon,authenticated,service_role;

create or replace function public.school_guard_tuition_generation_identity_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres' and (
       (current_setting('tuition.p0c_fixture_cleanup',true)
          ='codex-test atomic-void-reissue-p0c-20260803'
        and old.id='c0c00000-0000-4000-8000-000000003001'::uuid)
       or (current_setting('tuition.p0d_fixture_cleanup',true)
          ='codex-test tuition-p0d-e2e-readiness-20260803'
        and old.id='d0d00000-0000-4000-8000-000000003001'::uuid)
     ) then return old; end if;
  raise exception 'TUITION_GENERATION_IDENTITY_IMMUTABLE';
end
$function$;

create or replace function public.school_guard_tuition_generation_void_event_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres' and (
       (current_setting('tuition.p0c_fixture_cleanup',true)
          ='codex-test atomic-void-reissue-p0c-20260803'
        and old.id='c0c00000-0000-4000-8000-000000008001'::uuid)
       or (current_setting('tuition.p0d_fixture_cleanup',true)
          ='codex-test tuition-p0d-e2e-readiness-20260803'
        and old.generation_identity_id='d0d00000-0000-4000-8000-000000003001'::uuid)
     ) then return old; end if;
  raise exception 'TUITION_GENERATION_VOID_EVENT_IMMUTABLE';
end
$function$;

create or replace function public.school_guard_tuition_generation_revision()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_context_ok boolean;
begin
  if tg_op='DELETE' then
    if session_user='postgres' and (
       (current_setting('tuition.p0c_fixture_cleanup',true)
          ='codex-test atomic-void-reissue-p0c-20260803'
        and old.id='c0c00000-0000-4000-8000-000000004001'::uuid)
       or (current_setting('tuition.p0d_fixture_cleanup',true)
          ='codex-test tuition-p0d-e2e-readiness-20260803'
        and old.generation_identity_id='d0d00000-0000-4000-8000-000000003001'::uuid)
    ) then return old; end if;
    raise exception 'TUITION_GENERATION_REVISION_DELETE_FORBIDDEN';
  end if;
  if tg_op='UPDATE' then
    select exists(select 1 from public.school_tuition_atomic_writer_context c
      where c.backend_pid=pg_backend_pid() and c.transaction_id=txid_current()
        and c.writer_source='student_tuition_atomic_void_v1') into v_context_ok;
    if not v_context_ok or old.lifecycle_status<>'active' or new.lifecycle_status<>'voided'
       or new.voided_at is null or nullif(btrim(new.voided_by_authority),'') is null
       or (to_jsonb(new)-array['lifecycle_status','voided_at','voided_by_authority'])
          is distinct from
          (to_jsonb(old)-array['lifecycle_status','voided_at','voided_by_authority']) then
      raise exception 'TUITION_GENERATION_REVISION_MUTATION_FORBIDDEN';
    end if;
    return new;
  end if;
  if new.revision_no=1 then
    if new.previous_revision_id is not null then
      raise exception 'TUITION_GENERATION_REVISION_ONE_PREVIOUS_FORBIDDEN';
    end if;
  else
    select r.* into v_previous from public.school_student_tuition_generation_revisions r
    where r.id=new.previous_revision_id for share;
    if not found or v_previous.generation_identity_id<>new.generation_identity_id
       or v_previous.revision_no<>new.revision_no-1 or v_previous.lifecycle_status<>'voided'
       or new.manifest_kind<>'atomic_generation_v1' then
      raise exception 'TUITION_GENERATION_REVISION_CHAIN_INVALID';
    end if;
  end if;
  if new.manifest_kind='historical_registration_v1' and new.revision_no<>1 then
    raise exception 'TUITION_HISTORICAL_REVISION_NEXT_FORBIDDEN';
  end if;
  return new;
end
$function$;
revoke all on function public.school_guard_tuition_generation_revision()
  from public,anon,authenticated,service_role;

create or replace function public.school_void_atomic_student_tuition_generation_local(
  p_generation_revision_id uuid,
  p_tuition_bill_id uuid,
  p_income_record_id uuid,
  p_expected_generation_manifest_sha256 text,
  p_reason text
) returns table(
  generation_identity_id uuid,generation_revision_id uuid,tuition_bill_id uuid,
  income_record_id uuid,revision_no integer,lifecycle_status text,bill_status text,
  income_status text,void_event_id uuid,released_lesson_count integer,
  next_revision_no integer,message text
) language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  perform set_config('school.tuition_operator_authority','local_trusted_business_owner_v1',true);
  return query select *
  from public.school_void_atomic_student_tuition_generation_core(
    p_generation_revision_id,p_tuition_bill_id,p_income_record_id,
    p_expected_generation_manifest_sha256,p_reason
  );
end
$function$;
revoke all on function public.school_void_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function public.school_void_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,text,text
) to service_role;

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

comment on function public.school_void_atomic_student_tuition_generation_local(uuid,uuid,uuid,text,text)
is 'P0-D single-generation local trusted owner Void; fixed operator authority; still uses P0-C core.';
comment on function public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)
is 'P0-D existing-voided-generation-only local trusted Reissue; Gate bypass is limited by exact prior revision and DB snapshot facts.';

commit;
