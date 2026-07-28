-- R1D-C-C-C postdeploy read-only verification.

\set ON_ERROR_STOP on
\pset pager off

begin isolation level repeatable read read only;

select transaction_timestamp() as r1d_c_c_c_postdeploy_snapshot_at;

do $postdeploy$
declare
  v_candidate_hash text;
  v_candidate_count bigint;
  v_preview record;
  v_expected record;
begin
  select md5(pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
  )) into v_candidate_hash;

  if v_candidate_hash <> '8981a2ce07abf8c28231bfaf05451368'
     or position(
       'school_student_tuition_historical_lesson_exclusions' in
       pg_get_functiondef(
         'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
       )
     ) = 0
     or position(
       'lesson.billing_month = v_billing_month' in
       pg_get_functiondef(
         'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
       )
     ) = 0
     or position(
       'lesson.year_month = v_billing_month' in
       pg_get_functiondef(
         'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
       )
     ) <> 0 then
    raise exception 'R1D_C_C_C_POSTDEPLOY_DEFINITION_FAILED: %',v_candidate_hash;
  end if;

  if md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     or md5(pg_get_functiondef(
       'public.school_classify_student_tuition_candidate(boolean,boolean,text[],boolean,boolean,text,text,timestamptz,boolean,boolean)'::regprocedure
     )) <> '759738bc62c558b5d29e2078b06ea297' then
    raise exception 'R1D_C_C_C_POSTDEPLOY_CALLER_OR_CLASSIFIER_CHANGED';
  end if;

  if (select pg_get_userbyid(proowner)
      from pg_proc
      where oid='public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)
       <> 'postgres'
     or not (select prosecdef from pg_proc
             where oid='public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure)
     or not has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) then
    raise exception 'R1D_C_C_C_POSTDEPLOY_METADATA_OR_PERMISSION_FAILED';
  end if;

  select count(*) into v_candidate_count
  from (
    select distinct candidate.planned_lesson_id
    from (
      select distinct student_id,business_entity_id,billing_month
      from public.school_lesson_records
      where app_type='school' and lesson_type='planned' and billing_month is not null
    ) scope
    cross join lateral public.school_list_student_tuition_candidates(
      scope.student_id,scope.business_entity_id,scope.billing_month,false
    ) candidate
    where candidate.candidate_status='candidate'
  ) candidate_set;

  if v_candidate_count <> 118 then
    raise exception 'R1D_C_C_C_POSTDEPLOY_CANDIDATE_COUNT_FAILED: %',v_candidate_count;
  end if;

  if (select count(*)
      from public.school_student_tuition_historical_lesson_exclusions exclusion
      join lateral public.school_list_student_tuition_candidates(
        exclusion.student_id_snapshot,
        exclusion.business_entity_id_snapshot,
        exclusion.settlement_month_snapshot,
        false
      ) candidate on candidate.planned_lesson_id=exclusion.planned_lesson_id) <> 0
     or (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 42
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> '680b6e5aaa718569aee4c36fe1cdc058'
     or (select md5(string_agg(t.lesson_old31_hash,'' order by t.planned_lesson_id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> 'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or (select md5(string_agg(t.evidence_hash,'' order by t.planned_lesson_id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> 'dc2546bff536942650db58e437d37f0e' then
    raise exception 'R1D_C_C_C_POSTDEPLOY_FIXED_42_FAILED';
  end if;

  if (select count(*)
      from (
        select distinct candidate.planned_lesson_id
        from (
          select distinct student_id,business_entity_id,billing_month
          from public.school_lesson_records
          where app_type='school' and lesson_type='planned' and billing_month is not null
        ) scope
        cross join lateral public.school_list_student_tuition_candidates(
          scope.student_id,scope.business_entity_id,scope.billing_month,false
        ) candidate
      ) candidate
      full join (
        select lesson_record_id as planned_lesson_id
        from public.school_business_entity_migration_items
        where batch_id in (
          'c1000000-0000-4000-8000-202607279999'::uuid,
          'c1000000-0000-4000-8000-202607289999'::uuid
        )
      ) approved using(planned_lesson_id)
      where candidate.planned_lesson_id is null or approved.planned_lesson_id is null) <> 0 then
    raise exception 'R1D_C_C_C_POSTDEPLOY_FIXED_118_FAILED';
  end if;

  if (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type='planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type='actual') <> 229
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_lesson_records t) <> 'c4f892d857fe674e4060f80d6af56b42'
     or (select count(*) from public.school_lesson_records where billing_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_week_start_date is not null) <> 118
     or (select count(*) from public.school_lesson_records where student_settlement_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_source is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_decided_at is not null) <> 118
     or (select count(*) from public.school_lesson_records where scheduled_lesson_date is not null) <> 0
     or (select count(*) from public.school_lesson_records lesson
         join public.school_student_tuition_historical_lesson_exclusions exclusion
           on exclusion.planned_lesson_id=lesson.id
         where lesson.billing_month is not null) <> 0 then
    raise exception 'R1D_C_C_C_POSTDEPLOY_LESSON_CHANGED';
  end if;

  if (select count(*) from public.school_student_tuition_bills) <> 9
     or (select count(*) from public.school_income_records) <> 42
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121
     or (select count(*) from public.school_student_monthly_settlements) <> 15
     or (select count(*) from public.school_account_transactions) <> 185
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 35
     or (select count(*) from public.school_teacher_wage_locks) <> 95
     or (select count(*) from public.school_teacher_wage_lock_details) <> 556
     or (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_tuition_bills t) <> '0f0323b79e7ff1c47ff6b90c75477a2d'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_income_records t) <> '2a4897b752f272b1f192045418b4940c'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_tuition_bill_lessons t) <> '09dfee7d8833e09384fb41a84f2959e0'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_monthly_settlements t) <> '7925cf3018bd0e669cd29710f6593238'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_account_transactions t) <> '8f4f6c4365035f6c36bac59ba986b28b'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_teacher_wage_locks t) <> '7bbe108d3ac73d4f21530793bf141bc6'
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_teacher_wage_lock_details t) <> '6204dc666b3b8e0f64fac901ecf0686a' then
    raise exception 'R1D_C_C_C_POSTDEPLOY_BUSINESS_BASELINE_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records lesson
      where lesson.lesson_type='planned'
        and lesson.status='pending_makeup'
        and lesson.student_id in (
          '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
          'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
        )
        and lesson.year_month in ('2026-05','2026-06')) <> 6
     or (select md5(string_agg(md5(to_jsonb(lesson)::text),'' order by lesson.id::text))
         from public.school_lesson_records lesson
         where lesson.lesson_type='planned'
           and lesson.status='pending_makeup'
           and lesson.student_id in (
             '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
             'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
           )
           and lesson.year_month in ('2026-05','2026-06'))
        <> '0a30ece80c040491747f320d63c98e3d' then
    raise exception 'R1D_C_C_C_POSTDEPLOY_PENDING_MAKEUP_CHANGED';
  end if;

  if not exists (select 1 from public.school_feature_gates
                 where feature_key='student_tuition_preview'
                   and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D_C_C_C_POSTDEPLOY_R0_CHANGED';
  end if;

  for v_expected in
    select * from (values
      ('b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2026-08'::text,22,44::numeric,374000::numeric),
      ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'2026-08'::text,30,65::numeric,650000::numeric),
      ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'2026-09'::text,24,52::numeric,520000::numeric),
      ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'2026-10'::text,24,52::numeric,520000::numeric),
      ('7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'2026-11'::text,18,41::numeric,410000::numeric)
    ) expected(student_id,billing_month,lesson_count,hours,fee_jpy)
  loop
    select * into v_preview
    from public.school_preview_student_tuition_bill(
      v_expected.student_id,v_expected.billing_month,0.043::numeric
    );
    if v_preview.planned_lesson_count <> v_expected.lesson_count
       or v_preview.planned_lesson_hours <> v_expected.hours
       or v_preview.planned_lesson_fee_jpy <> v_expected.fee_jpy then
      raise exception 'R1D_C_C_C_POSTDEPLOY_PREVIEW_FAILED: expected %, actual %',
        to_jsonb(v_expected),to_jsonb(v_preview);
    end if;
  end loop;

  if to_regclass('pg_temp.r1d_c_c_c_old_candidate_set') is not null
     or to_regclass('pg_temp.r1d_c_c_c_new_candidate_set') is not null
     or to_regclass('pg_temp.r1d_c_c_c_school_business_before') is not null
     or to_regprocedure('pg_temp.r1d_c_c_c_school_business_fingerprint()') is not null then
    raise exception 'R1D_C_C_C_POSTDEPLOY_TEMP_OBJECT_RESIDUE';
  end if;
end;
$postdeploy$;

select md5(pg_get_functiondef(
         'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
       )) as candidate_definition_hash,
       md5(pg_get_functiondef(
         'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
       )) as preview_definition_hash;

select student.display_name,
       lesson.billing_month,
       lesson.business_entity_id,
       lesson.billing_month_source,
       count(*) as candidate_rows,
       sum(lesson.duration_hours) as candidate_hours,
       sum(lesson.lesson_fee) as candidate_fee_jpy
from (
  select distinct candidate.planned_lesson_id
  from (
    select distinct student_id,business_entity_id,billing_month
    from public.school_lesson_records
    where app_type='school' and lesson_type='planned' and billing_month is not null
  ) scope
  cross join lateral public.school_list_student_tuition_candidates(
    scope.student_id,scope.business_entity_id,scope.billing_month,false
  ) candidate
) candidate_set
join public.school_lesson_records lesson on lesson.id=candidate_set.planned_lesson_id
join public.school_students student on student.id=lesson.student_id
group by student.display_name,lesson.billing_month,lesson.business_entity_id,
         lesson.billing_month_source
order by lesson.billing_month,student.display_name;

select feature_key,state
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
order by feature_key;

commit;
