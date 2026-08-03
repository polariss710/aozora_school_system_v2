-- P0-C postdeploy correction: align the read-only Void preflight with the
-- already-authoritative owner-only core settlement blocker.
\set ON_ERROR_STOP on
\pset pager off
begin;

do $patch$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_get_atomic_tuition_void_preflight(uuid)'::regprocedure);
  if position('v_settlement_count integer:=0' in v_definition)>0 then
    return;
  end if;
  v_definition:=replace(v_definition,
    'v_actual_count integer:=0; v_wage_count integer:=0; v_lesson_count integer:=0;',
    'v_actual_count integer:=0; v_wage_count integer:=0; v_settlement_count integer:=0;
  v_lesson_count integer:=0;');
  v_definition:=replace(v_definition,
    '  if v_revision.id is not null then',
    '    select count(*)::integer into v_settlement_count
    from public.school_student_monthly_settlements settlement
    where settlement.student_id=v_bill.student_id
      and settlement.business_entity_id is not distinct from v_bill.business_entity_id
      and settlement.year_month=v_bill.billing_month
      and settlement.settlement_status=''locked'';
  if v_revision.id is not null then');
  v_definition:=replace(v_definition,
    'elsif v_transaction_count>0 or v_actual_count>0 or v_wage_count>0 then',
    'elsif v_transaction_count>0 or v_actual_count>0 or v_wage_count>0
        or v_settlement_count>0 then');
  if position('v_settlement_count integer:=0' in v_definition)=0
     or position('or v_settlement_count>0 then' in v_definition)=0 then
    raise exception 'TUITION_P0C_SETTLEMENT_PREFLIGHT_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch$;

do $verify$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_get_atomic_tuition_void_preflight(uuid)'::regprocedure);
  if position('school_student_monthly_settlements' in lower(v_definition))=0
     or position('v_settlement_count>0' in lower(v_definition))=0 then
    raise exception 'TUITION_P0C_SETTLEMENT_PREFLIGHT_VERIFY_FAILED';
  end if;
end;
$verify$;

commit;
\echo 'P0C_SETTLEMENT_PREFLIGHT_GUARD_CORRECTED'
