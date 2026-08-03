-- Exact rollback for P0-E. Run only after fixture cleanup proves adjustment row count is zero.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $restore_rule_priority_baseline$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_p0e_base_assert_settlement_mutable(uuid)'::regprocedure);
  v_definition:=replace(v_definition,'school_p0e_base_assert_settlement_mutable',
    'school_assert_tuition_settlement_mutable');
  execute v_definition;
end;
$restore_rule_priority_baseline$;
revoke all on function public.school_assert_tuition_settlement_mutable(uuid)
  from public,anon,authenticated,service_role;
drop function public.school_p0e_base_assert_settlement_mutable(uuid);

do $restore_p0e_baselines$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_p0e_base_validate_revision(uuid)'::regprocedure);
  v_definition:=replace(v_definition,'school_p0e_base_validate_revision',
    'school_validate_tuition_generation_revision_for_bill');
  execute v_definition;
  v_definition:=pg_get_functiondef(
    'public.school_p0e_base_reissue_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure);
  v_definition:=replace(v_definition,'school_p0e_base_reissue_local',
    'school_reissue_atomic_student_tuition_generation_local');
  execute v_definition;
end;
$restore_p0e_baselines$;
revoke all on function public.school_validate_tuition_generation_revision_for_bill(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_reissue_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)
  from public,anon,authenticated;
grant execute on function public.school_reissue_atomic_student_tuition_generation_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text) to service_role;

drop function public.school_p0e_base_validate_revision(uuid);
drop function public.school_p0e_base_reissue_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text);
drop function public.school_reissue_atomic_student_tuition_generation_p0e_local(
  uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text);
drop function public.school_generate_student_tuition_next_revision_p0e_core(
  uuid,uuid,uuid,text,numeric,text,text,text);
drop function public.school_get_atomic_tuition_reissue_preview_p0e(
  uuid,uuid,uuid,uuid,text,numeric,text,text);
drop function public.school_get_student_monthly_settlement_effective_states(uuid[]);
drop function public.school_validate_tuition_generation_revision_adjustment_for_bill(uuid);
drop function public.school_compute_tuition_p0e_generation_manifest(
  text,uuid,uuid,text,uuid,numeric,numeric,numeric,numeric,text,numeric,numeric,text,text);
drop function public.school_compute_tuition_p0e_adjustment_line_manifest(
  uuid,date,uuid,uuid,text,numeric,numeric,text,text);
drop trigger school_guard_tuition_generation_revision_adjustment_immutable
  on public.school_student_tuition_generation_revision_adjustments;
drop function public.school_guard_tuition_generation_revision_adjustment_immutable();

do $assert_p0e_table_empty$
begin
  if exists(select 1 from public.school_student_tuition_generation_revision_adjustments) then
    raise exception 'TUITION_P0E_ROLLBACK_TABLE_NOT_EMPTY';
  end if;
end;
$assert_p0e_table_empty$;
drop table public.school_student_tuition_generation_revision_adjustments;

commit;
