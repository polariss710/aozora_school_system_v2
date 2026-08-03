\set ON_ERROR_STOP on
\pset pager off
begin read only;
do $verify$
begin
  if to_regprocedure('public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text)') is null then
    raise exception 'P0D_FINAL_RULE_A_FUNCTION_MISSING';
  end if;
  if position('bill.previous_settlement_month=p_year_month' in pg_get_functiondef(
       'public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text)'::regprocedure))=0
     or position('student_tuition_operation_v1' in pg_get_functiondef(
       'public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text)'::regprocedure))=0 then
    raise exception 'P0D_FINAL_RULE_A_FUNCTION_DRIFT';
  end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.school_student_monthly_settlements'::regclass
      and tgname='school_tuition_consumed_settlement_immutable'
      and (tgtype & 4)=4 and (tgtype & 16)=16 and (tgtype & 8)=8) then
    raise exception 'P0D_FINAL_SETTLEMENT_TRIGGER_SCOPE_DRIFT';
  end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'P0D_FINAL_GATE_DRIFT';
  end if;
end
$verify$;
select count(*) active_zero_carry_previous_period_claims
from public.school_student_tuition_generation_revisions r
join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
where r.lifecycle_status='active' and b.previous_carryover_cny=0;
select feature_key,state from public.school_feature_gates
where feature_key like 'student_tuition_%' order by feature_key;
rollback;
