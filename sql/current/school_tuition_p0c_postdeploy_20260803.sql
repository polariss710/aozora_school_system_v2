\set ON_ERROR_STOP on
\pset pager off
do $assert$
declare r record;
begin
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where lifecycle_status='active')<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='atomic_generation_v1')<>8
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='historical_registration_v1')<>7
     or exists(select 1 from public.school_student_tuition_generation_revisions where generation_manifest_sha256 is null)
     or exists(select 1 from public.school_student_tuition_generation_void_events) then
    raise exception 'TUITION_P0C_POSTDEPLOY_REGISTRATION_INVALID';
  end if;
  if exists(select 1 from pg_indexes where schemaname='public'
    and indexname='school_tuition_bill_lessons_canonical_planned_key') then
    raise exception 'TUITION_P0C_OLD_LESSON_INDEX_STILL_PRESENT';
  end if;
  if has_table_privilege('anon','public.school_student_tuition_generation_revisions','INSERT')
     or has_table_privilege('authenticated','public.school_student_tuition_generation_revisions','UPDATE')
     or has_table_privilege('service_role','public.school_student_tuition_generation_void_events','INSERT')
     or has_function_privilege('authenticated','public.school_void_atomic_student_tuition_generation(uuid,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_void_atomic_student_tuition_generation(uuid,uuid,uuid,text,text)','EXECUTE') then
    raise exception 'TUITION_P0C_ACL_INVALID';
  end if;
  for r in select tuition_bill_id from public.school_student_tuition_generation_revisions order by tuition_bill_id loop
    perform public.school_validate_tuition_identity_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_generation_revision_for_bill(r.tuition_bill_id);
  end loop;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled')
      or (feature_key='student_tuition_generate' and state='blocked')
      or (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'TUITION_P0C_GATE_DRIFT';
  end if;
  if exists(select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'TUITION_P0C_WRITER_CONTEXT_RESIDUE';
  end if;
end;
$assert$;
select manifest_kind,count(*) total,
       count(*) filter(where lifecycle_status='active') active
from public.school_student_tuition_generation_revisions group by manifest_kind order by manifest_kind;
select feature_key,state from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;
