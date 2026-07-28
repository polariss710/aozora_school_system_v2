-- R1D-C-C-C rollback rehearsal wrapper.
-- Runs the exact cutover with rollback-only negative DML, then proves the old
-- function, all business data, permissions and test fields were restored.

\set ON_ERROR_STOP on
\pset pager off
\set r1d_c_c_c_commit 0

\ir school_tuition_r1d_c_c_c_candidate_cutover.sql

begin isolation level repeatable read read only;

do $rollback_residue$
begin
  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1d9149f6e3ff02305d0963f81af9f0b9' then
    raise exception 'R1D_C_C_C_ROLLBACK_FUNCTION_RESIDUE';
  end if;

  if to_regclass('pg_temp.r1d_c_c_c_old_candidate_set') is not null
     or to_regclass('pg_temp.r1d_c_c_c_new_candidate_set') is not null
     or to_regclass('pg_temp.r1d_c_c_c_school_business_before') is not null
     or to_regprocedure('pg_temp.r1d_c_c_c_school_business_fingerprint()') is not null then
    raise exception 'R1D_C_C_C_ROLLBACK_TEMP_OBJECT_RESIDUE';
  end if;

  if (select count(*) from public.school_lesson_records) <> 626
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_lesson_records t) <> 'c4f892d857fe674e4060f80d6af56b42'
     or (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 42
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> '680b6e5aaa718569aee4c36fe1cdc058'
     or (select count(*) from public.school_lesson_records lesson
         where lesson.lesson_type='planned'
           and lesson.status='pending_makeup'
           and lesson.student_id in (
             '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
             'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
           )
           and lesson.year_month in ('2026-05','2026-06')) <> 6
     or (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_C_C_C_ROLLBACK_BUSINESS_OR_TEST_RESIDUE';
  end if;

  if not has_function_privilege(
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
    raise exception 'R1D_C_C_C_ROLLBACK_PERMISSION_RESIDUE';
  end if;
end;
$rollback_residue$;

commit;

-- Existing R1D-C-C-B postdeploy expects the pre-cutover function and proves
-- 160/118/42 plus immutable evidence after rollback.
\ir school_tuition_r1d_c_c_b_historical_42_exclusion_postdeploy.sql
