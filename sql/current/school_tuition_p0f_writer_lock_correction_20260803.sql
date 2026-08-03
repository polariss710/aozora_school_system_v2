-- P0-F shared-lock correction for every actual/makeup source mutation.
\set ON_ERROR_STOP on
begin;
create or replace function public.school_tuition_p0f_guard_claimed_lesson_source()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_source public.school_lesson_records%rowtype;
begin
  if tg_op in ('INSERT','UPDATE') and new.lesson_type='actual'
     and new.planned_lesson_id is not null then
    select * into strict v_source from public.school_lesson_records
    where id=new.planned_lesson_id;
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      v_source.student_id,v_source.business_entity_id,
      public.school_resolve_r1d_e_c_lesson_student_month(v_source.id)
    );
  elsif tg_op in ('UPDATE','DELETE') and old.lesson_type='planned' then
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      old.student_id,old.business_entity_id,
      public.school_resolve_r1d_e_c_lesson_student_month(old.id)
    );
  end if;
  if tg_op='DELETE' and exists(
    select 1 from public.school_student_settlement_lesson_variance_claims c
    where c.claim_status='active'
      and (c.source_planned_lesson_id=old.id or c.source_actual_lesson_id=old.id)
  ) then raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE'; end if;
  if tg_op in ('INSERT','UPDATE') and new.lesson_type='actual'
     and new.planned_lesson_id is not null and exists(
       select 1 from public.school_student_settlement_lesson_variance_claims c
       where c.claim_status='active' and c.source_type='unused_planned_credit_v1'
         and c.source_planned_lesson_id=new.planned_lesson_id
     ) then raise exception 'SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED'; end if;
  if tg_op='UPDATE' and exists(
    select 1 from public.school_student_settlement_lesson_variance_claims c
    where c.claim_status='active'
      and (c.source_planned_lesson_id=old.id or c.source_actual_lesson_id=old.id)
  ) and to_jsonb(new)-array['updated_at'] is distinct from to_jsonb(old)-array['updated_at'] then
    raise exception 'SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;
revoke all on function public.school_tuition_p0f_guard_claimed_lesson_source()
  from public,anon,authenticated,service_role;
commit;
