\set ON_ERROR_STOP on
\pset pager off
begin read only;
do $verify$
declare r record;
begin
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where lifecycle_status='active')<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='atomic_generation_v1')<>8
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='historical_registration_v1')<>7
     or (select count(*) from public.school_student_tuition_generation_void_events)<>0 then
    raise exception 'P0D_GENERATION_BASELINE_DRIFT';
  end if;
  if exists(select 1 from public.school_student_tuition_generation_revisions where generation_manifest_sha256 is null)
     or exists(select 1 from public.school_student_tuition_generation_identities group by student_id,business_entity_id,billing_month having count(*)>1)
     or exists(select 1 from public.school_student_tuition_generation_revisions where lifecycle_status='active' group by generation_identity_id having count(*)>1) then
    raise exception 'P0D_AUTHORITY_DUPLICATE_OR_NULL';
  end if;
  for r in select tuition_bill_id from public.school_student_tuition_generation_revisions loop
    perform public.school_validate_tuition_identity_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(r.tuition_bill_id);
    perform public.school_validate_tuition_generation_revision_for_bill(r.tuition_bill_id);
  end loop;
  if has_function_privilege('anon','public.school_get_atomic_tuition_void_preflight(uuid)','EXECUTE')
     or has_function_privilege('anon','public.school_void_atomic_student_tuition_generation(uuid,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_void_atomic_student_tuition_generation_local(uuid,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('anon','public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)','EXECUTE') then
    raise exception 'P0D_ANON_PRIVILEGE_REGRESSION';
  end if;
  if exists(select 1 from public.school_business_entities where note='codex-test tuition-p0d-e2e-readiness-20260803'
    union all select 1 from public.school_students where note='codex-test tuition-p0d-e2e-readiness-20260803'
    union all select 1 from public.school_lesson_records where note='codex-test tuition-p0d-e2e-readiness-20260803'
    union all select 1 from public.school_student_monthly_settlements where note='codex-test tuition-p0d-e2e-readiness-20260803'
    union all select 1 from public.school_student_tuition_bills where note='codex-test tuition-p0d-e2e-readiness-20260803'
    union all select 1 from public.school_income_records where note='codex-test tuition-p0d-e2e-readiness-20260803') then
    raise exception 'P0D_FIXTURE_RESIDUE';
  end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'P0D_GATE_DRIFT';
  end if;
end
$verify$;
select count(*) lesson_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) lesson_hash
from public.school_lesson_records t;
select feature_key,state from public.school_feature_gates where feature_key like 'student_tuition_%' order by feature_key;
rollback;
