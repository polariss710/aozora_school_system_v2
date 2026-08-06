-- Phase B3 read-only postdeploy: exact writer definitions, authority boundaries,
-- ACLs, preserved contracts and zero test residue.
\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare
  v record;
  v_definition text;
  v_expected record;
  v_helper regprocedure :=
    'public.school_assert_student_active_at_business_month_v1(uuid,date,text)'::regprocedure;
  v_cancel regprocedure :=
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
begin
  for v_expected in
    select * from (values
      ('public.school_assert_student_active_at_business_month_v1(uuid,date,text)'::regprocedure,'7dc0f8c7fdd57f07cffc468d569cf319'),
      ('public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,'4e7ddd85b884bf3607f14bb905bd9ed6'),
      ('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,'ff5181679cda96b26d2f27c17f6b9665'),
      ('public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,'e1d7414424dada7e1a77c0130c67d159'),
      ('public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,'23ee5d41a11f8a7b6ebf46283f3b0f6a'),
      ('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,'5727fa8abbb3037dfbcbff1ae06ddacd'),
      ('public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,'1b603474f0a0372652c4000ef0fec13d'),
      ('public.school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure,'5f8dec3835568ec0310a66ff6d41f0aa'),
      ('public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,'8f8343a3adef2278e0392f003cfb62fe'),
      ('public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure,'524b4703b08c6f91d366ac8ad4e969a0'),
      ('public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure,'87d3b1d7bed93a7c43d39748a1d69762'),
      ('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,'c684da67b5b35e6de1aeb0a14230e2f0'),
      ('public.school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure,'3a20185c9548f1d3182c0585bbc2fd74')
    ) expected(proc,definition_md5)
  loop
    if md5(pg_get_functiondef(v_expected.proc))<>v_expected.definition_md5 then
      raise exception 'STUDENT_STATUS_B3_POSTDEPLOY_MD5_DRIFT:%:%',
        v_expected.proc,md5(pg_get_functiondef(v_expected.proc));
    end if;
  end loop;

  if pg_get_userbyid((select proowner from pg_proc where oid=v_helper))<>'postgres'
     or not (select prosecdef from pg_proc where oid=v_helper)
     or (select proconfig from pg_proc where oid=v_helper)
        <>'{"search_path=pg_catalog, public"}'::text[]
     or has_function_privilege('public',v_helper,'EXECUTE')
     or has_function_privilege('anon',v_helper,'EXECUTE')
     or has_function_privilege('authenticated',v_helper,'EXECUTE')
     or has_function_privilege('service_role',v_helper,'EXECUTE') then
    raise exception 'STUDENT_STATUS_B3_HELPER_METADATA_INVALID';
  end if;

  if pg_get_userbyid((select proowner from pg_proc where oid=v_cancel))<>'postgres'
     or not (select prosecdef from pg_proc where oid=v_cancel)
     or (select proconfig from pg_proc where oid=v_cancel)
        <>'{"search_path=pg_catalog, public"}'::text[]
     or has_function_privilege('public',v_cancel,'EXECUTE')
     or has_function_privilege('anon',v_cancel,'EXECUTE')
     or not has_function_privilege('authenticated',v_cancel,'EXECUTE')
     or has_function_privilege('service_role',v_cancel,'EXECUTE') then
    raise exception 'STUDENT_STATUS_B3_CANCEL_METADATA_INVALID';
  end if;

  v_definition:=pg_get_functiondef(v_cancel);
  if position('school_tuition_p0b1_lock_existing_lesson_scope' in v_definition)=0
     or position('for update' in lower(v_definition))=0
     or position($needle$v_membership_role not in ('admin','operator')$needle$ in v_definition)=0
     or position('school_tuition_p0a_consumed_bill_id(settlement.id)' in v_definition)=0
     or position('extract(epoch from (v_end_value - v_start_value))' in v_definition)=0
     or position('actual_minutes, teacher_settlement_month' in v_definition)=0
     or position($needle$set status = 'pending_makeup'$needle$ in lower(v_definition))=0 then
    raise exception 'STUDENT_STATUS_B3_CANCEL_CONTRACT_MISSING';
  end if;

  -- Runtime target functions must no longer consult the frozen student master
  -- status as business eligibility. Diagnostic/baseline functions are excluded.
  for v in
    select p.oid::regprocedure proc,pg_get_functiondef(p.oid) definition
    from pg_proc p
    where p.oid=any(array[
      'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,
      'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
      'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
      'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
      'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
      'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
      'public.school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure,
      'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
      'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure,
      'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure,
      'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
      'public.school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure
    ])
  loop
    if lower(v.definition) like '%coalesce(s.status%inactive%'
       or lower(v.definition) like '%coalesce(student.status%inactive%'
       or lower(v.definition) like '%v_student.status%inactive%'
       or lower(v.definition) like '%v_student.status%停用%' then
      raise exception 'STUDENT_STATUS_B3_RUNTIME_LEGACY_PREDICATE:%',v.proc;
    end if;
  end loop;

  if md5(pg_get_functiondef(
       'public.school_get_weekly_lesson_operations(date)'::regprocedure
     ))<>'e7eac5f3bb07c31ad15e750e8721c01f'
     or has_function_privilege(
       'authenticated',
       'public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'STUDENT_STATUS_B3_PHASE_A_B1_BOUNDARY_REGRESSION';
  end if;

  if (select state from public.school_feature_gates
      where feature_key='student_tuition_generate')<>'blocked'
     or (select state from public.school_feature_gates
         where feature_key='student_tuition_preview')<>'enabled'
     or (select state from public.school_feature_gates
         where feature_key='student_tuition_cash_submit')<>'enabled' then
    raise exception 'STUDENT_STATUS_B3_GATE_DRIFT';
  end if;

  if exists(select 1 from auth.users where id::text like 'b3010000-%')
     or exists(select 1 from public.school_students where id::text like 'b3020000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'b3030000-%')
     or exists(select 1 from public.school_student_status_events where id::text like 'b3050000-%')
     or exists(select 1 from public.school_teacher_wage_rules where id::text like 'b3060000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'c6080000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'c6090000-%') then
    raise exception 'STUDENT_STATUS_B3_TEST_RESIDUE';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure::text signature,
       md5(pg_get_functiondef(p.oid)) definition_md5,
       pg_get_userbyid(p.proowner) owner,
       p.prosecdef security_definer,
       p.proconfig,
       p.proacl
from pg_proc p
where p.oid=any(array[
  'public.school_assert_student_active_at_business_month_v1(uuid,date,text)'::regprocedure,
  'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
  'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
])
order by signature;

select 'STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_POSTDEPLOY_PASS' result;
