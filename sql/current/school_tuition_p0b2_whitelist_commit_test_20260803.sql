-- Whitelist commit test lifecycle for the fixed synthetic fixture only.
-- Required p0b2_commit_action: write | cleanup | residue.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0b2_commit_action}
\else
  \echo 'P0B2_COMMIT_ACTION_REQUIRED'
  \quit
\endif
begin;
select set_config('tuition.p0b2_commit_action',:'p0b2_commit_action',true);

do $test$
declare
  v_action constant text:=current_setting('tuition.p0b2_commit_action');
  v_student constant uuid:='b1b10000-0000-4000-8000-00000000a100';
  v_fixture_marker constant text:='codex-test tuition-p0b1-lesson-authority-20260803';
  v_marker constant text:='codex-test tuition-p0b2-whitelist-commit-20260803';
  v_row record;
  v_id uuid;
begin
  if v_action not in ('write','cleanup','residue') then
    raise exception 'P0B2_COMMIT_ACTION_INVALID';
  end if;
  if (select count(*) from public.school_students
      where id=v_student and note=v_fixture_marker)<>1 then
    raise exception 'P0B2_COMMIT_FIXTURE_OWNERSHIP_FAILED';
  end if;
  if v_action='write' then
    if exists (
      select 1 from public.school_student_settlement_adjustment_drafts
      where student_id=v_student
    ) then raise exception 'P0B2_COMMIT_PREFLIGHT_DRAFT_EXISTS'; end if;
    select * into strict v_row
    from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
    if v_row.adjustment_source<>'clear_balance'
       or v_row.adjustment_amount_cny<>-3000
       or v_row.locked_carryover_cny<>0 then
      raise exception 'P0B2_COMMIT_RESULT_INVALID';
    end if;
  elsif v_action='cleanup' then
    select id into strict v_id
    from public.school_student_settlement_adjustment_drafts
    where student_id=v_student and year_month='2020-06'
      and adjustment_source='clear_balance'
      and adjustment_amount_cny=-3000 and note=v_marker
      and adjustment_reason=v_marker and status='active';
    delete from public.school_student_settlement_adjustment_drafts
    where id=v_id and student_id=v_student and note=v_marker;
    if not found then raise exception 'P0B2_COMMIT_CLEANUP_FAILED'; end if;
  end if;
  if v_action in ('cleanup','residue') and exists (
    select 1 from public.school_student_settlement_adjustment_drafts
    where student_id=v_student or note=v_marker
  ) then raise exception 'P0B2_COMMIT_RESIDUE_NOT_ZERO'; end if;
end
$test$;

select :'p0b2_commit_action' action,id,student_id,year_month,
  adjustment_source,adjustment_amount_cny,status,note
from public.school_student_settlement_adjustment_drafts
where student_id='b1b10000-0000-4000-8000-00000000a100';
commit;
