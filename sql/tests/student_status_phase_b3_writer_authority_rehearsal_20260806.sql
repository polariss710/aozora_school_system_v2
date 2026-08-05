-- Phase B3 exact deployment rehearsal. Applies the full cutover and rolls it back.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir ../current/school_student_status_phase_b3_writer_authority_core_20260806.sql
\ir ../current/school_student_status_phase_b3_writer_authority_postdeploy_20260806.sql

select p.oid::regprocedure::text as signature,
       md5(pg_get_functiondef(p.oid)) as rehearsal_md5,
       p.proacl
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'school_assert_student_active_at_business_month_v1',
    'school_build_student_tuition_generation_snapshot',
    'school_create_actual_lesson_from_planned',
    'school_create_cancelled_actual_lesson_from_planned',
    'school_create_lesson_credit_makeup_actual',
    'school_create_partial_completed_actual_from_planned',
    'school_create_planned_lesson_record_r1d_f1_legacy_core',
    'school_create_teacher_wage_rule_config',
    'school_generate_planned_lessons_batch_r1d_f1_legacy_core',
    'school_import_lesson_records_batch_r1d_f1_legacy_core',
    'school_preview_student_tuition_bill',
    'school_update_lesson_record_guarded',
    'school_update_teacher_wage_rule_config'
  )
order by signature;

select 'STUDENT_STATUS_PHASE_B3_WRITER_AUTHORITY_REHEARSAL_PASS' as result;
rollback;
