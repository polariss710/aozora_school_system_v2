\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare v_peng record; v_eligible integer;
begin
  if (select count(*) from information_schema.columns
      where table_schema='public' and table_name='school_student_monthly_settlements'
        and column_name in ('source_treatment_mode','settlement_exchange_rate',
          'settlement_exchange_rate_source','settlement_exchange_rate_effective_date',
          'lesson_variance_calculation_version','unused_planned_credit_jpy',
          'unused_planned_credit_cny','pending_makeup_hours',
          'lesson_variance_display_hours','net_lesson_variance_jpy',
          'net_lesson_variance_cny','lesson_variance_source_count',
          'lesson_variance_manifest_sha256'))<>13
     or to_regclass('public.school_student_settlement_source_treatment_drafts') is null
     or to_regclass('public.school_student_settlement_lesson_variance_claims') is null then
    raise exception 'P0F_POSTDEPLOY_OBJECTS_MISSING';
  end if;
  if exists(select 1 from public.school_student_monthly_settlements
    where source_treatment_mode is not null or settlement_exchange_rate is not null)
     or (select count(*) from public.school_student_settlement_source_treatment_drafts)<>0
     or (select count(*) from public.school_student_settlement_lesson_variance_claims)<>0 then
    raise exception 'P0F_POSTDEPLOY_UNEXPECTED_BUSINESS_WRITE';
  end if;
  if has_table_privilege('anon','public.school_student_settlement_source_treatment_drafts','INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.school_student_settlement_lesson_variance_claims','INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','public.school_student_settlement_lesson_variance_claims','INSERT,UPDATE,DELETE')
     or not has_table_privilege('service_role','public.school_student_settlement_lesson_variance_claims','SELECT')
     or has_function_privilege('anon','public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)','EXECUTE') then
    raise exception 'P0F_POSTDEPLOY_PERMISSION_FAILED';
  end if;
  if position('FM999999990.000000' in pg_get_functiondef(
       'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure))=0
     or position('school_tuition_p0a_lock_settlement_mutation_scope' in pg_get_functiondef(
       'public.school_tuition_p0f_guard_claimed_lesson_source()'::regprocedure))=0
     or position('school_student_settlement_lesson_variance_claims' in pg_get_functiondef(
       'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))=0
     or position('school_void_planned_lesson_after_tuition_void' in pg_get_functiondef(
       'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure))=0
     or not has_function_privilege('authenticated',
       'public.school_get_tuition_income_forward_adjustment_display(uuid[])','EXECUTE')
     or has_function_privilege('anon',
       'public.school_get_tuition_income_forward_adjustment_display(uuid[])','EXECUTE')
     or not has_function_privilege('authenticated',
       'public.school_get_planned_lesson_tuition_history_state(uuid[])','EXECUTE')
     or not has_function_privilege('anon',
       'public.school_get_planned_lesson_tuition_history_state(uuid[])','EXECUTE')
     or has_function_privilege('anon',
       'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)','EXECUTE')
     or has_function_privilege('anon',
       'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)','EXECUTE') then
    raise exception 'P0F_POSTDEPLOY_FUNCTION_MARKER_FAILED';
  end if;
  if not exists(select 1 from public.school_feature_gates
      where feature_key='student_tuition_preview' and state='enabled')
     or not exists(select 1 from public.school_feature_gates
      where feature_key='student_tuition_generate' and state='blocked')
     or not exists(select 1 from public.school_feature_gates
      where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'P0F_POSTDEPLOY_GATE_CHANGED';
  end if;
  select * into strict v_peng
  from public.school_preview_student_settlement_source_treatment(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda','2026-07',
    'net_lesson_variance_to_financial_credit_v1',0.042,
    'business_owner_confirmed_monthly_settlement_rate_v1','2026-07-01'
  );
  if v_peng.pending_makeup_hours<>2 or v_peng.overage_hours<>0.25
     or v_peng.unused_planned_credit_jpy<>-17000
     or v_peng.overage_charge_jpy<>2125
     or v_peng.net_lesson_variance_jpy<>-14875
     or v_peng.net_lesson_variance_cny<>-624.75
     or v_peng.system_difference_cny<>-624.75
     or v_peng.lesson_variance_source_count<>2 then
    raise exception 'P0F_POSTDEPLOY_PENG_PREVIEW_FAILED';
  end if;
  if not exists(
    select 1 from public.school_get_tuition_income_forward_adjustment_display(
      array['d980cedd-ebba-4be1-afcb-b25dfa26798a'::uuid]
    )
    where historical_carryover_cny=107.50
      and forward_adjustment_cny=-107.50
      and net_carryover_impact_cny=0
      and final_notice_amount_cny=27950.00
  ) then
    raise exception 'P0F_POSTDEPLOY_P0E_INCOME_DISPLAY_FAILED';
  end if;

  with target_lessons as (
    select l.* from public.school_lesson_records l
    where l.student_id in (
      'eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,
      'a7b163a0-201e-4867-9b94-372343356a80'::uuid
    ) and l.lesson_type='planned' and l.billing_month='2026-08'
      and l.voided_at is null
  ), eligible as (
    select l.id from target_lessons l
    where l.status in ('planned','pending_makeup')
      and exists(select 1 from public.school_student_tuition_bill_lessons bl
        join public.school_student_tuition_generation_revisions r
          on r.tuition_bill_id=bl.tuition_bill_id
        where bl.planned_lesson_id=l.id and r.lifecycle_status='voided')
      and not exists(select 1 from public.school_student_tuition_bill_lessons bl
        join public.school_student_tuition_generation_revisions r
          on r.tuition_bill_id=bl.tuition_bill_id
        where bl.planned_lesson_id=l.id and r.lifecycle_status='active')
      and not exists(select 1 from public.school_lesson_records a
        where a.lesson_type='actual' and a.planned_lesson_id=l.id)
      and not exists(select 1 from public.school_teacher_wage_lock_details w
        where w.lesson_record_id=l.id)
      and not exists(select 1 from public.school_student_monthly_settlements s
        where s.student_id=l.student_id and s.business_entity_id=l.business_entity_id
          and s.year_month=public.school_resolve_r1d_e_c_lesson_student_month(l.id)
          and s.settlement_status='locked')
      and not exists(select 1 from public.school_student_settlement_lesson_variance_claims c
        where c.claim_status='active' and c.source_planned_lesson_id=l.id)
  ) select count(*) into v_eligible from eligible;
  if v_eligible<>31 then raise exception 'P0F_POSTDEPLOY_CONTROLLED_VOID_ELIGIBLE_DRIFT: %',v_eligible; end if;
  if exists(select 1 from public.school_students where note='codex-test tuition-p0f-commit-20260803')
     or exists(select 1 from public.school_lesson_records where note='codex-test tuition-p0f-commit-20260803') then
    raise exception 'P0F_POSTDEPLOY_FIXTURE_RESIDUE';
  end if;
end
$postdeploy$;

select feature_key,state from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select 'lesson' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash
from public.school_lesson_records t
union all select 'settlement_legacy_projection',count(*),
  md5(coalesce(string_agg(md5((to_jsonb(t)-array[
    'source_treatment_mode','settlement_exchange_rate','settlement_exchange_rate_source',
    'settlement_exchange_rate_effective_date','lesson_variance_calculation_version',
    'unused_planned_credit_jpy','unused_planned_credit_cny','pending_makeup_hours',
    'lesson_variance_display_hours','net_lesson_variance_jpy','net_lesson_variance_cny',
    'lesson_variance_source_count','lesson_variance_manifest_sha256'])::text),'' order by t.id::text),''))
from public.school_student_monthly_settlements t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
order by object_name;
