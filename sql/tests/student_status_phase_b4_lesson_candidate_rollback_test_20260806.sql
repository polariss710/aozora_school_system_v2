\set ON_ERROR_STOP on
begin read only;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','25331ae9-3412-48b9-bdc3-e516caeaeba4',true);

do $test$
declare
  v_entity_id uuid;
  v_count integer;
  v_status text;
  v_billing_month text;
  v_is_eligible boolean;
  v_invalid jsonb;
begin
  select business_entity_id into strict v_entity_id
  from public.school_students
  where id='cff85c52-6acc-4b0f-8c92-3db280a5dd77';

  select count(*) into v_count
  from public.school_list_planned_lesson_student_candidates_v1(
    date '2026-07-01',v_entity_id,null
  );
  if v_count<>8 then
    raise exception 'B4_LESSON_SINGLE_BOUNDARY_ACTIVE_COUNT_MISMATCH actual=%',v_count;
  end if;

  select billing_month,resolved_status,is_eligible
  into strict v_billing_month,v_status,v_is_eligible
  from public.school_list_planned_lesson_student_candidates_v1(
    date '2026-07-06',v_entity_id,'cff85c52-6acc-4b0f-8c92-3db280a5dd77'
  )
  where student_id='cff85c52-6acc-4b0f-8c92-3db280a5dd77';
  if v_billing_month<>'2026-07' or v_status<>'paused' or v_is_eligible then
    raise exception 'B4_LESSON_SINGLE_PAUSED_OVERRIDE_MISMATCH month=% status=% eligible=%',
      v_billing_month,v_status,v_is_eligible;
  end if;

  select count(*) into v_count
  from public.school_preflight_planned_lesson_batch_student_candidates_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[]'::jsonb,v_entity_id,null
  );
  if v_count<>7 then
    raise exception 'B4_LESSON_BATCH_INTERSECTION_COUNT_MISMATCH actual=%',v_count;
  end if;

  select invalid_occurrences,is_eligible
  into strict v_invalid,v_is_eligible
  from public.school_preflight_planned_lesson_batch_student_candidates_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[]'::jsonb,v_entity_id,'cff85c52-6acc-4b0f-8c92-3db280a5dd77'
  )
  where student_id='cff85c52-6acc-4b0f-8c92-3db280a5dd77';
  if v_is_eligible or jsonb_array_length(v_invalid)<>1
     or v_invalid->0->>'lesson_date'<>'2026-07-06'
     or v_invalid->0->>'billing_month'<>'2026-07'
     or v_invalid->0->>'resolved_status'<>'paused' then
    raise exception 'B4_LESSON_BATCH_SELECTED_EVIDENCE_MISMATCH invalid=% eligible=%',v_invalid,v_is_eligible;
  end if;

  select count(*) into v_count
  from public.school_expand_planned_lesson_batch_occurrences_v1(
    date '2026-06-29',date '2026-07-06',
    '[{"pattern_index":1,"weekday":1,"occurrence_count":1}]'::jsonb,
    '[{"pattern_index":1,"lesson_date":"2026-07-06","occurrence_index":1}]'::jsonb
  );
  if v_count<>1 then
    raise exception 'B4_LESSON_BATCH_EXCLUSION_MISMATCH actual=%',v_count;
  end if;
end;
$test$;

select 'STUDENT_STATUS_PHASE_B4_LESSON_ROLLBACK_TEST_PASS' as result;
rollback;
