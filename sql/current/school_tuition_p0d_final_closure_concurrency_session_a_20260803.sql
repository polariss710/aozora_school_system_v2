\set ON_ERROR_STOP on
\if :{?p0d_final_scenario}
\else
  \echo 'P0D_FINAL_SCENARIO_REQUIRED'
  \quit
\endif
begin;
set local lock_timeout='8s';
set local statement_timeout='30s';
select set_config('tuition.p0d_final_scenario',:'p0d_final_scenario',true);
do $a$
declare
  v_scenario text:=current_setting('tuition.p0d_final_scenario');
  v_revision record;
begin
  if v_scenario='generate_reissue_vs_settlement' then
    perform public.school_tuition_p0a_lock_generate_scope(
      'd0d00000-0000-4000-8000-00000000a001','d0d00000-0000-4000-8000-00000000e001',
      array['2020-08','2020-07']);
  elsif v_scenario='void_vs_settlement' then
    select r.id revision_id,r.tuition_bill_id,b.income_record_id,r.generation_manifest_sha256
    into strict v_revision
    from public.school_student_tuition_generation_revisions r
    join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
    where r.generation_identity_id='d0d00000-0000-4000-8000-000000003001'
      and r.lifecycle_status='active';
    perform * from public.school_void_atomic_student_tuition_generation_local(
      v_revision.revision_id,v_revision.tuition_bill_id,v_revision.income_record_id,
      v_revision.generation_manifest_sha256,'codex-test P0-D final concurrency');
  else
    raise exception 'P0D_FINAL_SCENARIO_INVALID';
  end if;
  perform pg_sleep(5);
end
$a$;
rollback;
select :'p0d_final_scenario' scenario,'session_a_rolled_back' result;
