-- P0-E regression correction: mutation guard must report active Rule A before permanent Rule B.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $capture_rule_priority_baseline$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef('public.school_assert_tuition_settlement_mutable(uuid)'::regprocedure);
  v_definition:=replace(v_definition,'school_assert_tuition_settlement_mutable',
    'school_p0e_base_assert_settlement_mutable');
  execute v_definition;
  revoke all on function public.school_p0e_base_assert_settlement_mutable(uuid)
    from public,anon,authenticated,service_role;
end;
$capture_rule_priority_baseline$;

create or replace function public.school_assert_tuition_settlement_mutable(p_settlement_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_bill_id uuid;
  v_settlement public.school_student_monthly_settlements%rowtype;
begin
  if p_settlement_id is null then return; end if;
  select * into v_settlement
  from public.school_student_monthly_settlements
  where id=p_settlement_id;
  if found then
    perform public.school_assert_active_tuition_previous_period_claim(
      v_settlement.student_id,v_settlement.business_entity_id,v_settlement.year_month
    );
  end if;
  v_bill_id:=public.school_tuition_p0a_consumed_bill_id(p_settlement_id);
  if v_bill_id is not null then
    raise exception using errcode='P0001',message=format(
      'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE: settlement %s was consumed by tuition bill %s; historical settlement remains permanently immutable and correction requires a forward adjustment.',
      p_settlement_id,v_bill_id
    );
  end if;
end;
$function$;
revoke all on function public.school_assert_tuition_settlement_mutable(uuid)
  from public,anon,authenticated,service_role;

commit;
