\set ON_ERROR_STOP on
\pset pager off
begin read only;
do $verify$
begin
  if to_regprocedure('public.school_tuition_p0b1_lesson_financial_authority()') is null
     or not exists(select 1 from pg_trigger where tgrelid='public.school_lesson_records'::regclass
       and tgname='trg_school_lesson_p0b1_financial_authority' and tgenabled='O') then
    raise exception 'P0B1_AUTHORITY_TRIGGER_MISSING';
  end if;
  if (select count(*) from public.school_lesson_records)<>729
     or exists(select 1 from public.school_lesson_records where lesson_type='planned'
       and lesson_fee<>round(duration_hours*unit_price))
     or exists(select 1 from public.school_lesson_records where lesson_type='actual' and is_billable
       and lesson_fee<>round(duration_hours*unit_price)) then
    raise exception 'P0B1_PRODUCTION_LESSON_DRIFT';
  end if;
  if exists(
    select 1 from public.school_business_entities where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_subjects where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_teachers where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_students where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_lesson_records where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_student_monthly_settlements where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_student_tuition_bills where note='codex-test tuition-p0b1-lesson-authority-20260803'
    union all select 1 from public.school_income_records where note='codex-test tuition-p0b1-lesson-authority-20260803'
  ) then raise exception 'P0B1_FIXTURE_RESIDUE'; end if;
  if (select count(*) from public.school_feature_gates where
      (feature_key='student_tuition_preview' and state='enabled') or
      (feature_key='student_tuition_generate' and state='blocked') or
      (feature_key='student_tuition_cash_submit' and state='blocked'))<>3 then
    raise exception 'P0B1_GATE_DRIFT';
  end if;
end
$verify$;

select feature_key,state,release_version from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;
select count(*) lesson_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) lesson_hash
from public.school_lesson_records t;
select public.school_tuition_p0a_consumed_bill_id('b699209d-2f61-4cfa-959b-45686e2fe19b') zhang_consuming_bill_id;
rollback;
