\set ON_ERROR_STOP on
\pset pager off
begin read only;

do $verify$
declare r record; v_state record; v_resolver record;
begin
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where lifecycle_status='active')<>15
     or (select count(*) from public.school_student_tuition_generation_void_events)<>0
     or (select count(*) from public.school_student_tuition_generation_revision_adjustments)<>0 then
    raise exception 'P0E_PRODUCTION_GENERATION_BASELINE_DRIFT';
  end if;
  if exists(select 1 from public.school_student_tuition_generation_revisions
            where lifecycle_status='active' group by generation_identity_id having count(*)>1) then
    raise exception 'P0E_DUPLICATE_ACTIVE_REVISION';
  end if;
  for r in select tuition_bill_id from public.school_student_tuition_generation_revisions loop
    perform public.school_validate_tuition_identity_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_generation_revision_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_generation_revision_adjustment_for_bill(r.tuition_bill_id);
  end loop;
  if has_table_privilege('service_role','public.school_student_tuition_generation_revision_adjustments','INSERT')
     or has_table_privilege('service_role','public.school_student_tuition_generation_revision_adjustments','UPDATE')
     or has_table_privilege('service_role','public.school_student_tuition_generation_revision_adjustments','DELETE')
     or has_table_privilege('anon','public.school_student_tuition_generation_revision_adjustments','SELECT')
     or has_function_privilege('anon',
       'public.school_reissue_atomic_student_tuition_generation_p0e_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)','EXECUTE')
     or not has_function_privilege('service_role',
       'public.school_reissue_atomic_student_tuition_generation_p0e_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)','EXECUTE') then
    raise exception 'P0E_ACL_DRIFT';
  end if;
  select e.* into strict v_state
  from public.school_student_monthly_settlements s
  cross join lateral public.school_get_student_monthly_settlement_effective_states(array[s.id]) e
  where s.id='b699209d-2f61-4cfa-959b-45686e2fe19b';
  if v_state.physical_status<>'unlocked'
     or v_state.effective_status<>'historically_consumed_immutable'
     or v_state.frozen_carryover_cny<>107.50
     or v_state.editable or v_state.unlockable or v_state.relockable
     or v_state.immutable_error_code<>'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE'
     or v_state.display_label<>'已被历史学费账单消费（不可重开）' then
    raise exception 'P0E_ZHANG_EFFECTIVE_STATE_DRIFT';
  end if;
  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('clear_balance',null,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>-107.50 or v_resolver.resolved_carryover_cny<>0 then
    raise exception 'P0E_P0B2_CLEAR_REGRESSION';
  end if;
  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('carry_final_balance',null,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>0 or v_resolver.resolved_carryover_cny<>107.50 then
    raise exception 'P0E_P0B2_CARRY_REGRESSION';
  end if;
  select * into strict v_resolver
  from public.school_tuition_p0b2_resolve_adjustment('manual_adjustment',-7.50,107.50);
  if v_resolver.resolved_adjustment_amount_cny<>-7.50 or v_resolver.resolved_carryover_cny<>100 then
    raise exception 'P0E_P0B2_MANUAL_REGRESSION';
  end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'P0E_GATE_DRIFT';
  end if;
end;
$verify$;

select 'generation_identity' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash
from public.school_student_tuition_generation_identities t
union all select 'generation_revision',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_generation_revisions t
union all select 'void_event',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_generation_void_events t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
union all select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t
union all select 'settlement_draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
union all select 'settlement_adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
union all select 'lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t
order by object_name;

select feature_key,state from public.school_feature_gates
where feature_key like 'student_tuition_%' order by feature_key;
rollback;
