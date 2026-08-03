-- Exact P0-C rollback. Refuses once any post-registration production revision/void exists.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

do $rollback_preflight$
begin
  if to_regclass('public.school_student_tuition_generation_revisions') is null then
    raise exception 'TUITION_P0C_ROLLBACK_TARGET_NOT_DEPLOYED';
  end if;
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or exists(select 1 from public.school_student_tuition_generation_revisions where revision_no<>1 or lifecycle_status<>'active')
     or exists(select 1 from public.school_student_tuition_generation_void_events) then
    raise exception 'TUITION_P0C_ROLLBACK_AFTER_BUSINESS_USE_FORBIDDEN';
  end if;
end;
$rollback_preflight$;

do $restore_baselines$
declare v_original_name text; v_backup_name text; v_backup_signature text; v_definition text;
begin
  for v_original_name,v_backup_name,v_backup_signature in select * from (values
    ('school_generate_student_tuition_bill_atomic_core','school_p0c_baseline_generate_atomic_core','public.school_p0c_baseline_generate_atomic_core(uuid,text,numeric,text,text,text)'),
    ('school_validate_tuition_identity_for_bill','school_p0c_baseline_validate_tuition_identity_for_bill','public.school_p0c_baseline_validate_tuition_identity_for_bill(uuid)'),
    ('school_validate_tuition_bill_income_for_bill','school_p0c_baseline_validate_tuition_bill_income_for_bill','public.school_p0c_baseline_validate_tuition_bill_income_for_bill(uuid)'),
    ('school_validate_tuition_bill_lessons_for_bill','school_p0c_baseline_validate_tuition_bill_lessons_for_bill','public.school_p0c_baseline_validate_tuition_bill_lessons_for_bill(uuid)'),
    ('school_list_student_tuition_candidates','school_p0c_baseline_list_student_tuition_candidates','public.school_p0c_baseline_list_student_tuition_candidates(uuid,uuid,text,boolean)'),
    ('school_enforce_r2_e_planned_aircon','school_p0c_baseline_enforce_r2_e_planned_aircon','public.school_p0c_baseline_enforce_r2_e_planned_aircon()'),
    ('school_tuition_p0b1_lesson_financial_authority','school_p0c_baseline_tuition_p0b1_lesson_financial_authority','public.school_p0c_baseline_tuition_p0b1_lesson_financial_authority()'),
    ('school_guard_r0_tuition_business_mutation','school_p0c_baseline_guard_r0_tuition_business_mutation','public.school_p0c_baseline_guard_r0_tuition_business_mutation()'),
    ('school_guard_tuition_identity_or_lesson_immutable','school_p0c_baseline_guard_tuition_identity_or_lesson','public.school_p0c_baseline_guard_tuition_identity_or_lesson()'),
    ('school_update_lesson_record_guarded','school_p0c_baseline_update_lesson_record_guarded','public.school_p0c_baseline_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'),
    ('school_get_student_tuition_validation_preview_details','school_p0c_baseline_tuition_preview_details','public.school_p0c_baseline_tuition_preview_details(uuid,text,numeric)'),
    ('school_tuition_p0a_consumed_bill_id','school_p0c_baseline_tuition_p0a_consumed_bill_id','public.school_p0c_baseline_tuition_p0a_consumed_bill_id(uuid)'),
    ('school_get_cash_income_submission_preflight','school_p0c_baseline_get_cash_income_submission_preflight','public.school_p0c_baseline_get_cash_income_submission_preflight(uuid[])'),
    ('school_request_cash_income_confirmation_for_record','school_p0c_baseline_request_cash_income_confirmation_for_record','public.school_p0c_baseline_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)')
  ) x(original_name,backup_name,backup_signature) loop
    v_definition:=pg_get_functiondef(v_backup_signature::regprocedure);
    v_definition:=replace(v_definition,v_backup_name,v_original_name);
    execute v_definition;
  end loop;
end;
$restore_baselines$;

create unique index school_tuition_bill_lessons_canonical_planned_key
  on public.school_student_tuition_bill_lessons(planned_lesson_id)
  where relation_role='canonical_charge';

drop function public.school_void_atomic_student_tuition_generation(uuid,uuid,uuid,text,text);
drop function public.school_void_atomic_student_tuition_generation_core(uuid,uuid,uuid,text,text);
drop function public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text);
drop function public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text);
drop function public.school_get_atomic_tuition_void_preflight(uuid);

drop trigger school_enforce_active_tuition_lesson_claim_on_relation
  on public.school_student_tuition_bill_lessons;
drop trigger school_enforce_active_tuition_lesson_claim_on_revision
  on public.school_student_tuition_generation_revisions;
drop trigger school_enforce_active_tuition_carryover_claim_on_revision
  on public.school_student_tuition_generation_revisions;
drop trigger school_tuition_generation_identity_immutable
  on public.school_student_tuition_generation_identities;
drop trigger school_tuition_generation_identity_truncate_forbidden
  on public.school_student_tuition_generation_identities;
drop trigger school_tuition_generation_revision_guard
  on public.school_student_tuition_generation_revisions;
drop trigger school_tuition_generation_revision_truncate_forbidden
  on public.school_student_tuition_generation_revisions;
drop trigger school_tuition_generation_void_event_immutable
  on public.school_student_tuition_generation_void_events;
drop trigger school_tuition_generation_void_event_truncate_forbidden
  on public.school_student_tuition_generation_void_events;
drop trigger school_tuition_generation_identity_delete_statement_guard
  on public.school_student_tuition_generation_identities;
drop trigger school_tuition_generation_revision_delete_statement_guard
  on public.school_student_tuition_generation_revisions;
drop trigger school_tuition_generation_void_event_delete_statement_guard
  on public.school_student_tuition_generation_void_events;

drop view public.school_active_student_tuition_bill_lessons;

delete from public.school_student_tuition_generation_revisions where id in (
  '96000000-0000-4000-8000-202608031001','96000000-0000-4000-8000-202608031002',
  '96000000-0000-4000-8000-202608031003','96000000-0000-4000-8000-202608031004',
  '96000000-0000-4000-8000-202608031005','96000000-0000-4000-8000-202608031006',
  '96000000-0000-4000-8000-202608031007','96000000-0000-4000-8000-202608031008',
  '96000000-0000-4000-8000-202608031009','96000000-0000-4000-8000-202608031010',
  '96000000-0000-4000-8000-202608031011','96000000-0000-4000-8000-202608031012',
  '96000000-0000-4000-8000-202608031013','96000000-0000-4000-8000-202608031014',
  '96000000-0000-4000-8000-202608031015'
);
delete from public.school_student_tuition_generation_identities where id in (
  '96000000-0000-4000-8000-202608030001','96000000-0000-4000-8000-202608030002',
  '96000000-0000-4000-8000-202608030003','96000000-0000-4000-8000-202608030004',
  '96000000-0000-4000-8000-202608030005','96000000-0000-4000-8000-202608030006',
  '96000000-0000-4000-8000-202608030007','96000000-0000-4000-8000-202608030008',
  '96000000-0000-4000-8000-202608030009','96000000-0000-4000-8000-202608030010',
  '96000000-0000-4000-8000-202608030011','96000000-0000-4000-8000-202608030012',
  '96000000-0000-4000-8000-202608030013','96000000-0000-4000-8000-202608030014',
  '96000000-0000-4000-8000-202608030015'
);

drop function public.school_enforce_active_tuition_carryover_claim_on_revision();
drop function public.school_assert_active_tuition_carryover_claim(uuid);
drop function public.school_enforce_active_tuition_lesson_claim_on_revision();
drop function public.school_enforce_active_tuition_lesson_claim_on_relation();
drop function public.school_assert_active_tuition_lesson_claim(uuid);
drop function public.school_guard_tuition_generation_void_event_immutable();
drop function public.school_guard_tuition_generation_revision();
drop function public.school_guard_tuition_generation_identity_immutable();
drop function public.school_guard_p0c_generation_direct_delete();
drop function public.school_validate_tuition_generation_revision_for_bill(uuid);
drop function public.school_compute_historical_tuition_registration_manifest(uuid);
drop function public.school_lock_student_tuition_operation(uuid,uuid,date);

drop table public.school_student_tuition_generation_void_events;
drop table public.school_student_tuition_generation_revisions;
drop table public.school_student_tuition_generation_identities;

alter table public.school_tuition_atomic_writer_context
  drop constraint school_tuition_atomic_writer_context_source_check;
alter table public.school_tuition_atomic_writer_context
  add constraint school_tuition_atomic_writer_context_source_check
  check (writer_source in ('student_tuition_atomic_generate_v1','legacy_tuition_cancel'));

drop function public.school_p0c_baseline_generate_atomic_core(uuid,text,numeric,text,text,text);
drop function public.school_p0c_baseline_validate_tuition_identity_for_bill(uuid);
drop function public.school_p0c_baseline_validate_tuition_bill_income_for_bill(uuid);
drop function public.school_p0c_baseline_validate_tuition_bill_lessons_for_bill(uuid);
drop function public.school_p0c_baseline_list_student_tuition_candidates(uuid,uuid,text,boolean);
drop function public.school_p0c_baseline_enforce_r2_e_planned_aircon();
drop function public.school_p0c_baseline_tuition_p0b1_lesson_financial_authority();
drop function public.school_p0c_baseline_guard_r0_tuition_business_mutation();
drop function public.school_p0c_baseline_guard_tuition_identity_or_lesson();
drop function public.school_p0c_baseline_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text);
drop function public.school_p0c_baseline_tuition_preview_details(uuid,text,numeric);
drop function public.school_p0c_baseline_tuition_p0a_consumed_bill_id(uuid);
drop function public.school_p0c_baseline_get_cash_income_submission_preflight(uuid[]);
drop function public.school_p0c_baseline_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text);

commit;
\echo 'P0C_EXACT_ROLLBACK_COMMITTED'
