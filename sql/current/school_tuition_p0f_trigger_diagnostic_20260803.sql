\set ON_ERROR_STOP on
begin;
create or replace function public.school_tuition_p0f_settlement_before()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_draft record; v_preview record; v_preset numeric; v_lines jsonb;
begin
  if new.settlement_status='locked'
     and (tg_op='INSERT' or old.settlement_status is distinct from 'locked') then
    select * into v_draft
    from public.school_student_settlement_source_treatment_drafts d
    where d.student_id=new.student_id and d.business_entity_id=new.business_entity_id
      and d.year_month=new.year_month and d.status='active'
    order by d.created_at desc limit 1;
    if tg_op='UPDATE'
       and old.source_treatment_mode='net_lesson_variance_to_financial_credit_v1'
       and v_draft.id is null then
      raise exception 'SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK';
    end if;
    select * into strict v_preview
    from public.school_preview_student_settlement_source_treatment(
      new.student_id,new.year_month,
      coalesce(v_draft.source_treatment_mode,'separate_makeup_and_overage_v1'),
      v_draft.settlement_exchange_rate,v_draft.settlement_exchange_rate_source,
      v_draft.settlement_exchange_rate_effective_date
    );
    if v_draft.id is not null
       and v_draft.source_manifest_sha256 is distinct from v_preview.lesson_variance_manifest_sha256 then
      select jsonb_agg(to_jsonb(l) order by l.source_type,l.source_planned_lesson_id,l.source_actual_lesson_id)
      into v_lines from public.school_tuition_p0f_source_lines(
        new.student_id,new.business_entity_id,new.year_month,v_draft.settlement_exchange_rate,false
      ) l;
      raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT: draft=% current=% lines=%',
        v_draft.source_manifest_sha256,v_preview.lesson_variance_manifest_sha256,v_lines;
    end if;
    new.source_treatment_mode:=v_preview.source_treatment_mode;
    if v_preview.source_treatment_mode='net_lesson_variance_to_financial_credit_v1' then
      select s.preset_exchange_rate into v_preset from public.school_students s where s.id=new.student_id;
      new.preset_exchange_rate:=v_preset;
      new.settlement_exchange_rate:=v_preview.settlement_exchange_rate;
      new.settlement_exchange_rate_source:=v_preview.settlement_exchange_rate_source;
      new.settlement_exchange_rate_effective_date:=v_preview.settlement_exchange_rate_effective_date;
      new.lesson_variance_calculation_version:='lesson_variance_financial_netting_v1';
      new.unused_planned_credit_jpy:=v_preview.unused_planned_credit_jpy;
      new.unused_planned_credit_cny:=v_preview.unused_planned_credit_cny;
      new.pending_makeup_hours:=v_preview.pending_makeup_hours;
      new.lesson_variance_display_hours:=v_preview.lesson_variance_display_hours;
      new.net_lesson_variance_jpy:=v_preview.net_lesson_variance_jpy;
      new.net_lesson_variance_cny:=v_preview.net_lesson_variance_cny;
      new.lesson_variance_source_count:=v_preview.lesson_variance_source_count;
      new.lesson_variance_manifest_sha256:=v_preview.lesson_variance_manifest_sha256;
    else
      new.settlement_exchange_rate:=null;
      new.settlement_exchange_rate_source:=null;
      new.settlement_exchange_rate_effective_date:=null;
      new.lesson_variance_calculation_version:=null;
      new.unused_planned_credit_jpy:=null; new.unused_planned_credit_cny:=null;
      new.pending_makeup_hours:=null; new.lesson_variance_display_hours:=null;
      new.net_lesson_variance_jpy:=null; new.net_lesson_variance_cny:=null;
      new.lesson_variance_source_count:=null; new.lesson_variance_manifest_sha256:=null;
    end if;
  end if;
  return new;
end
$function$;
revoke all on function public.school_tuition_p0f_settlement_before()
  from public,anon,authenticated,service_role;
commit;
