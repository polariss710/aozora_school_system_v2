-- P0-B2 concurrency session A. Required p0b2_scenario.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0b2_scenario}
\else
  \echo 'P0B2_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='15s';
set local statement_timeout='120s';
select set_config('tuition.p0b2_scenario',:'p0b2_scenario',true);
do $a$
declare
  v_scenario constant text:=current_setting('tuition.p0b2_scenario');
  v_marker constant text:='codex-test tuition-p0b2-concurrency-20260803';
  v_student constant uuid:='b1b10000-0000-4000-8000-00000000a100';
  v_lesson constant uuid:='b1b10000-0000-4000-8000-000000001101';
  v_teacher constant uuid:='b1b10000-0000-4000-8000-000000007100';
  v_subject constant uuid:='b1b10000-0000-4000-8000-00000000d100';
  v_entity constant uuid:='b1b10000-0000-4000-8000-00000000e100';
  v_updated timestamptz;
  v_locked uuid;
begin
  if v_scenario in ('draft_edit','draft_pair') then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'carry_final_balance',v_marker,v_marker);
  elsif v_scenario='draft_actual' then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  elsif v_scenario='draft_lock' then
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',1.235,'manual_adjustment',v_marker,v_marker);
  elsif v_scenario='lock_generate' then
    perform * from public.school_lock_student_monthly_settlement(
      v_student,'2020-06',v_marker);
  elsif v_scenario='unlock_draft' then
    select settlement_id into strict v_locked
    from public.school_lock_student_monthly_settlement(v_student,'2020-06',v_marker);
    perform * from public.school_unlock_student_monthly_settlement(v_locked,v_marker);
  elsif v_scenario='preview_edit' then
    perform * from public.school_get_student_monthly_settlement_preview(
      v_student,'2020-06');
  elsif v_scenario='source_change_lock' then
    select updated_at into strict v_updated
    from public.school_lesson_records where id=v_lesson;
    perform * from public.school_update_lesson_record_guarded(
      v_lesson,v_updated,'2020-06-10',v_student,v_teacher,v_subject,v_entity,
      '15:00','17:00',2,12000,1,'planned',true,2,v_marker,
      'codex-test tuition-p0b1-lesson-authority-20260803');
  else
    raise exception 'P0B2_SCENARIO_INVALID: %',v_scenario;
  end if;
  raise notice 'P0B2_SESSION_A_LOCK_HELD scenario=% pid=%',v_scenario,pg_backend_pid();
  perform pg_sleep(5);
end
$a$;
select :'p0b2_scenario'='source_change_lock' as p0b2_commit_source_change \gset
\if :p0b2_commit_source_change
  commit;
  \echo 'P0B2_SESSION_A_COMMITTED_WHITELIST_SOURCE_CHANGE'
\else
  rollback;
  \echo 'P0B2_SESSION_A_ROLLED_BACK'
\endif
