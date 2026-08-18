-- Phase 2C-D2-A2 production ROLLBACK rehearsal. No writer or fixture is used.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('school_phase2c_d2_a2_20260818',0));

do $preflight$
begin
  if to_regprocedure(
      'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'
    ) is not null then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_READER_V3_PRESENT';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_CLEARANCE_NOT_EMPTY';
  end if;
end
$preflight$;

\set PHASE2C_D2_A2_REHEARSAL 1
\ir school_phase2c_d2_a2_pending_operational_date_reader_v3_migration_20260818.sql

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select membership.user_id from public.school_app_memberships membership
    where membership.is_active is true and membership.role='admin'
    order by membership.created_at,membership.user_id limit 1),
  'role','authenticated')::text,true);

do $payload$
declare
  v_payload jsonb;
  v_row jsonb;
  v_v2 jsonb;
begin
  v_payload:=public.school_list_lesson_clearance_pending_balances_v3(null,false);
  v_v2:=public.school_list_lesson_clearance_pending_balances_v2(null,false);
  if v_payload->>'contract_version'<>'lesson_clearance_pending_balances_v3'
     or jsonb_array_length(v_payload->'items')<>21
     or (v_payload->'summary'->>'remaining_minutes')::integer<>2400
     or v_payload->'summary'->>'operational_ambiguous_evidence_count'<>'0' then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_SUMMARY_INVALID:%',v_payload->'summary';
  end if;
  if (v_payload-'contract_version'-'items'-'summary')
      is distinct from (v_v2-'contract_version'-'items'-'summary') then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_V2_TOP_LEVEL_DRIFT';
  end if;

  select item into strict v_row
  from jsonb_array_elements(v_payload->'items') item
  where item->>'pending_source_planned_id'=
    '8870f57f-bca5-4114-90db-ee592cca2f45';
  if v_row->>'operational_display_date'<>'2026-08-14'
     or v_row->>'operational_display_date_basis'<>'partial_actual_date'
     or v_row->>'origin_partial_actual_id'<>
       '2da1ec9a-6f19-49af-a9bd-48984a255aa9'
     or v_row->>'origin_partial_actual_date'<>'2026-08-14'
     or v_row->>'origin_evidence_status'<>'unique_valid_partial_actual'
     or v_row->>'source_lesson_date'<>'2026-08-10'
     or (v_row->>'remaining_minutes')::integer<>60 then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_TARGET_PARTIAL_INVALID:%',v_row;
  end if;

  select item into strict v_row
  from jsonb_array_elements(v_payload->'items') item
  where item->>'pending_source_planned_id'=
    '06befa0a-1e6c-4e26-8b88-2f321bfaca7f';
  if v_row->>'operational_display_date'<>'2026-08-03'
     or v_row->>'operational_display_date_basis'<>'source_natural_week_start'
     or v_row->>'origin_partial_actual_id' is not null
     or v_row->>'origin_evidence_status'<>'no_valid_partial_actual' then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_CANCELLED_INVALID:%',v_row;
  end if;

  select item into strict v_row
  from jsonb_array_elements(v_payload->'items') item
  where item->>'pending_source_planned_id'=
    '79502518-0c0d-4025-87e8-58e2177ae3dd';
  if v_row->>'source_lesson_date'<>'2026-08-06'
     or v_row->>'operational_display_date'<>'2026-08-03'
     or v_row->>'origin_evidence_status'<>'no_valid_partial_actual' then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_WEEK_MONDAY_INVALID:%',v_row;
  end if;

  if exists(
    select 1
    from jsonb_array_elements(v_payload->'items') v3_item
    join jsonb_array_elements(v_v2->'items') v2_item
      on v2_item->>'pending_source_planned_id'
        =v3_item->>'pending_source_planned_id'
    where (v3_item-
      array['operational_display_date','operational_display_date_basis',
        'origin_partial_actual_id','origin_partial_actual_date',
        'origin_evidence_status','operational_display_explanation'])
      is distinct from v2_item
  ) then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_V2_ITEM_DRIFT';
  end if;
end
$payload$;

do $acl$
declare
  v_signature regprocedure:=
    'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'::regprocedure;
begin
  if not has_function_privilege('authenticated',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_ACL_INVALID';
  end if;
end
$acl$;

do $business_zero$
begin
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_D2_A2_REHEARSAL_BUSINESS_WRITE_DETECTED';
  end if;
end
$business_zero$;

rollback;
