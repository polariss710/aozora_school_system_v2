-- Exact P0-F rollback. Refuses to remove any P0-F business evidence.
-- Usage: psql -v p0f_rollback_commit=0|1 -f this_file.sql
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0f_rollback_commit}
\else
  \set p0f_rollback_commit 0
\endif
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

do $preflight$
begin
  if (select count(*) from public.school_student_settlement_source_treatment_drafts)<>0
     or (select count(*) from public.school_student_settlement_lesson_variance_claims)<>0
     or exists(select 1 from public.school_student_monthly_settlements
       where source_treatment_mode is not null
          or settlement_exchange_rate is not null
          or lesson_variance_manifest_sha256 is not null) then
    raise exception 'P0F_ROLLBACK_BUSINESS_EVIDENCE_PRESENT';
  end if;
end
$preflight$;

drop function public.school_get_tuition_income_forward_adjustment_display(uuid[]);
drop function public.school_get_planned_lesson_tuition_history_state(uuid[]);

do $restore_open_credit_reader$
declare v_definition text; v_restored text;
begin
  select pg_get_functiondef(
    'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
  ) into v_definition;
  if position('school_student_settlement_lesson_variance_claims' in v_definition)=0 then
    raise exception 'P0F_OPEN_CREDIT_READER_ROLLBACK_SOURCE_DRIFT';
  end if;
  v_restored:=regexp_replace(v_definition,
    E'WHERE s\\.remaining_hours>0\\n    and not exists \\([\\s\\S]*?and c\\.source_planned_lesson_id=s\\.id\\n    \\)',
    'WHERE s.remaining_hours>0');
  execute v_restored;
end
$restore_open_credit_reader$;

drop function public.school_void_planned_lesson(uuid,timestamptz,text);
alter function public.school_void_planned_lesson_p0f_legacy(uuid,timestamptz,text)
  rename to school_void_planned_lesson;

drop trigger school_tuition_p0f_claimed_lesson_source_guard
  on public.school_lesson_records;
drop trigger school_tuition_p0f_settlement_after
  on public.school_student_monthly_settlements;
drop trigger school_tuition_p0f_settlement_before
  on public.school_student_monthly_settlements;
drop trigger school_tuition_p0f_claim_rpc_only
  on public.school_student_settlement_lesson_variance_claims;
drop trigger school_tuition_p0f_draft_rpc_only
  on public.school_student_settlement_source_treatment_drafts;

drop function public.school_void_planned_lesson_after_tuition_void(uuid,timestamptz,text,text);
drop function public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text);
drop function public.school_preview_student_settlement_source_treatment(uuid,text,text,numeric,text,date);
drop function public.school_tuition_p0f_guard_claimed_lesson_source();
drop function public.school_tuition_p0f_settlement_after();
drop function public.school_tuition_p0f_settlement_before();
drop function public.school_tuition_p0f_guard_claim_dml();
drop function public.school_tuition_p0f_guard_draft_dml();
drop function public.school_tuition_p0f_assert_sources_resolved(uuid,uuid,text);
drop function public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean);

drop function public.school_get_student_monthly_settlement_summary(uuid,text);
alter function public.school_get_student_monthly_settlement_summary_p0f_legacy(uuid,text)
  rename to school_get_student_monthly_settlement_summary;

drop table public.school_student_settlement_lesson_variance_claims;
drop table public.school_student_settlement_source_treatment_drafts;

alter table public.school_student_monthly_settlements
  drop column source_treatment_mode,
  drop column settlement_exchange_rate,
  drop column settlement_exchange_rate_source,
  drop column settlement_exchange_rate_effective_date,
  drop column lesson_variance_calculation_version,
  drop column unused_planned_credit_jpy,
  drop column unused_planned_credit_cny,
  drop column pending_makeup_hours,
  drop column lesson_variance_display_hours,
  drop column net_lesson_variance_jpy,
  drop column net_lesson_variance_cny,
  drop column lesson_variance_source_count,
  drop column lesson_variance_manifest_sha256;

\if :p0f_rollback_commit
  commit;
\else
  rollback;
\endif
