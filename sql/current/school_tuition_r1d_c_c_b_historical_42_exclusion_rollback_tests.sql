-- R1D-C-C-B rollback rehearsal wrapper.
-- Runs the exact schema/backfill with commit=0, including all negative tests,
-- then proves public-object and business-data residue is zero.

\set ON_ERROR_STOP on
\pset pager off
\set r1d_c_c_b_commit 0

\ir school_tuition_r1d_c_c_b_historical_42_exclusion_schema_backfill.sql

begin isolation level repeatable read read only;

do $rollback_residue$
begin
  if to_regclass('public.school_student_tuition_historical_lesson_exclusions') is not null
     or to_regprocedure('public.school_r1d_c_c_b_fixed_42_manifest()') is not null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_insert()') is not null
     or to_regprocedure('public.school_guard_tuition_historical_lesson_exclusion_immutable()') is not null then
    raise exception 'R1D_C_C_B_ROLLBACK_PUBLIC_OBJECT_RESIDUE';
  end if;

  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1d9149f6e3ff02305d0963f81af9f0b9' then
    raise exception 'R1D_C_C_B_ROLLBACK_CANDIDATE_FUNCTION_DRIFT';
  end if;

  if (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type='planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type='actual') <> 229
     or (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_preview' and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D_C_C_B_ROLLBACK_BUSINESS_RESIDUE';
  end if;
end;
$rollback_residue$;

commit;

-- Re-run the committed read-only fixed-42 audit after rollback.
\ir school_tuition_r1d_c_c_a_current_only_42_billing_fact_readonly.sql
