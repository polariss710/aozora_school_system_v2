\set ON_ERROR_STOP on
begin;
\ir ../current/school_student_status_phase_b4_lesson_candidate_core_20260806.sql

do $test$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.school_expand_planned_lesson_batch_occurrences_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[]'::jsonb
  );
  if v_count<>2 then
    raise exception 'B4_LESSON_REHEARSAL_OCCURRENCE_COUNT_MISMATCH actual=%',v_count;
  end if;
end;
$test$;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','25331ae9-3412-48b9-bdc3-e516caeaeba4',true);

do $runtime$
declare
  v_entity_id uuid;
  v_count integer;
  v_invalid jsonb;
begin
  select business_entity_id into strict v_entity_id
  from public.school_students
  where id='cff85c52-6acc-4b0f-8c92-3db280a5dd77';

  select count(*) into v_count
  from public.school_list_planned_lesson_student_candidates_v1(date '2026-07-01',v_entity_id,null);
  if v_count<>8 then
    raise exception 'B4_LESSON_REHEARSAL_SINGLE_COUNT_MISMATCH actual=%',v_count;
  end if;

  select count(*) into v_count
  from public.school_preflight_planned_lesson_batch_student_candidates_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[]'::jsonb,v_entity_id,null
  );
  if v_count<>7 then
    raise exception 'B4_LESSON_REHEARSAL_BATCH_COUNT_MISMATCH actual=%',v_count;
  end if;

  select invalid_occurrences into strict v_invalid
  from public.school_preflight_planned_lesson_batch_student_candidates_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[]'::jsonb,v_entity_id,'cff85c52-6acc-4b0f-8c92-3db280a5dd77'
  )
  where student_id='cff85c52-6acc-4b0f-8c92-3db280a5dd77';
  if jsonb_array_length(v_invalid)<>1 then
    raise exception 'B4_LESSON_REHEARSAL_SELECTED_EVIDENCE_MISMATCH invalid=%',v_invalid;
  end if;
end;
$runtime$;

select
  p.oid::regprocedure::text as signature,
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  p.proacl
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_expand_planned_lesson_batch_occurrences_v1',
  'school_list_planned_lesson_student_candidates_v1',
  'school_preflight_planned_lesson_batch_student_candidates_v1',
  'school_generate_planned_lessons_batch_r1d_f1_legacy_core'
)
order by signature;

select 'STUDENT_STATUS_PHASE_B4_LESSON_REHEARSAL_PASS' as result;
rollback;
