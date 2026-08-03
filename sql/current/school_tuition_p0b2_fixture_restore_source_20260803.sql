-- Restore the fixed synthetic lesson after the committed concurrency source change.
\set ON_ERROR_STOP on
begin;
do $restore$
declare
  v_lesson constant uuid:='b1b10000-0000-4000-8000-000000001101';
  v_updated timestamptz;
begin
  select updated_at into strict v_updated
  from public.school_lesson_records
  where id=v_lesson
    and note='codex-test tuition-p0b1-lesson-authority-20260803'
    and student_id='b1b10000-0000-4000-8000-00000000a100';
  perform * from public.school_update_lesson_record_guarded(
    v_lesson,v_updated,'2020-06-10',
    'b1b10000-0000-4000-8000-00000000a100'::uuid,
    'b1b10000-0000-4000-8000-000000007100'::uuid,
    'b1b10000-0000-4000-8000-00000000d100'::uuid,
    'b1b10000-0000-4000-8000-00000000e100'::uuid,
    '15:00','17:00',2,10000,1,'planned',true,2,
    'codex-test tuition-p0b2-source-restore-20260803',
    'codex-test tuition-p0b1-lesson-authority-20260803');
  if (select lesson_fee from public.school_lesson_records where id=v_lesson)<>20000 then
    raise exception 'P0B2_FIXTURE_SOURCE_RESTORE_FAILED';
  end if;
end
$restore$;
commit;
