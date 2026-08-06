-- Real approved 11-ID correction rehearsal. Performs the full RPC then ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $preflight$
declare
  v_ids uuid[]:=array[
    'f256bca9-fac5-4909-b113-8077efd27d65'::uuid,
    'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid,
    '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid,
    '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid,
    'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
    'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid,
    'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
    'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid,
    '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid,
    'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
    'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
  ];
  v_candidate_count integer;
  v_candidate_jpy numeric;
begin
  if (select count(*) from public.school_lesson_records l
      where l.id=any(v_ids) and l.voided_at is null and l.void_reason is null)<>11
     or (select md5(string_agg(md5(to_jsonb(l)::text),'' order by l.id::text))
         from public.school_lesson_records l where l.id=any(v_ids))
       <>'e2bc9f4380f5bf5a95ff0341ae47183b'
     or (select count(*) from public.school_lesson_exact_correction_events e
         where e.lesson_id=any(v_ids))<>0
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.planned_lesson_id::text))
         from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=any(v_ids))<>'11b2bfdadaf78e6b4d853044c64f576d'
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.actual_lesson_id::text))
         from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids))<>'f5c2e715af4180af16576c32eb46f0ad'
     or public.school_get_lesson_credit_raw_remaining_hours(
       'f759623b-ce28-4c5f-8556-95c4381b6b1b')<>-2 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_PREFLIGHT_MANIFEST_FAILED';
  end if;

  with candidates as (
    select * from public.school_list_student_tuition_candidates(
      'a7b163a0-201e-4867-9b94-372343356a80',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-09',true)
    union all select * from public.school_list_student_tuition_candidates(
      'a7b163a0-201e-4867-9b94-372343356a80',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-10',true)
    union all select * from public.school_list_student_tuition_candidates(
      'a7b163a0-201e-4867-9b94-372343356a80',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-11',true)
  ) select count(*) filter(where candidate_status='candidate'),
           coalesce(sum(lesson_fee) filter(where candidate_status='candidate'),0)
    into v_candidate_count,v_candidate_jpy from candidates;
  if v_candidate_count<>4 or v_candidate_jpy<>104000
     or (select count(*) from public.school_lesson_records l
         where l.id=any(v_ids) and l.lesson_type='actual'
           and l.status in ('completed','makeup_completed')
           and l.voided_at is null)<>3 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_PREFLIGHT_CANDIDATES_FAILED';
  end if;
end;
$preflight$;

select set_config('request.jwt.claims',
  jsonb_build_object(
    'sub','25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid,
    'role','authenticated'
  )::text,true);
set local role authenticated;

select * from public.school_correct_li_wu_test_lessons_v1(
  'li_wu_2026_09_11_test_lessons_void_v1_20260806',
  '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',
  'e2bc9f4380f5bf5a95ff0341ae47183b'
);
reset role;

do $verify_inside$
declare
  v_ids uuid[]:=array[
    'f256bca9-fac5-4909-b113-8077efd27d65'::uuid,
    'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid,
    '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid,
    '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid,
    'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
    'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid,
    'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
    'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid,
    '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid,
    'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
    'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
  ];
begin
  if (select count(*) from public.school_lesson_records l
      where l.id=any(v_ids) and l.voided_at is not null)<>11
     or (select count(*) from public.school_lesson_exact_correction_events e
         where e.correction_batch_id=
           'li_wu_2026_09_11_test_lessons_void_v1_20260806')<>11
     or (select count(*) from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=any(v_ids))<>7
     or (select count(*) from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids))<>4
     or public.school_get_lesson_credit_raw_remaining_hours(
       'f759623b-ce28-4c5f-8556-95c4381b6b1b')<>2 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_CORE_VERIFY_FAILED';
  end if;

  if exists(
       select 1 from public.school_lesson_exact_correction_events e
       where e.correction_batch_id=
         'li_wu_2026_09_11_test_lessons_void_v1_20260806'
         and (e.after_row-array['voided_at','void_reason','updated_at'])
             is distinct from
             (e.before_row-array['voided_at','void_reason','updated_at'])
     )
     or (select count(*) from public.school_lesson_exact_correction_events e
         where e.correction_batch_id=
           'li_wu_2026_09_11_test_lessons_void_v1_20260806'
           and e.before_row->>'lesson_type'='actual'
           and e.before_row->>'lesson_fee'=e.after_row->>'lesson_fee'
           and e.before_row->>'actual_minutes' is not distinct from
               e.after_row->>'actual_minutes'
           and e.before_row->>'is_billable'=e.after_row->>'is_billable')<>4
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.planned_lesson_id::text))
         from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=any(v_ids))<>'11b2bfdadaf78e6b4d853044c64f576d'
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.actual_lesson_id::text))
         from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids))<>'f5c2e715af4180af16576c32eb46f0ad' then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_VOID_ONLY_EVIDENCE_FAILED';
  end if;

  if (select count(*) from public.school_list_student_tuition_candidates(
       'a7b163a0-201e-4867-9b94-372343356a80',
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-09',true)
       where candidate_status='candidate')
     +(select count(*) from public.school_list_student_tuition_candidates(
       'a7b163a0-201e-4867-9b94-372343356a80',
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-10',true)
       where candidate_status='candidate')
     +(select count(*) from public.school_list_student_tuition_candidates(
       'a7b163a0-201e-4867-9b94-372343356a80',
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-11',true)
       where candidate_status='candidate')<>0 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_TUITION_CANDIDATE_REMAINS';
  end if;

  if (select count(*) from public.school_lesson_records l
      where l.id=any(v_ids) and l.lesson_type='actual'
        and l.status in ('completed','makeup_completed')
        and l.voided_at is null
        and coalesce(l.teacher_settlement_month,l.year_month)='2026-11')<>0 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_WAGE_CANDIDATE_REMAINS';
  end if;

  if (select count(*) from public.school_list_lesson_management_records_authoritative(
       '2026-11',null) l where l.id=any(v_ids) and l.voided_at is null)<>0
     or (select count(*) from public.school_list_lesson_management_records_authoritative(
       '2026-11',null) l where l.id=any(v_ids) and l.voided_at is not null)<>7 then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_READER_ROUTING_FAILED';
  end if;
end;
$verify_inside$;

select 'LI_WU_CORRECTION_PRODUCTION_REHEARSAL_IN_TRANSACTION_PASS' result;
rollback;

begin transaction isolation level repeatable read read only;
do $verify_after_rollback$
declare
  v_ids uuid[]:=array[
    'f256bca9-fac5-4909-b113-8077efd27d65'::uuid,
    'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid,
    '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid,
    '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid,
    'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
    'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid,
    'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
    'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid,
    '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid,
    'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
    'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
  ];
begin
  if (select count(*) from public.school_lesson_records l
      where l.id=any(v_ids) and l.voided_at is null and l.void_reason is null)<>11
     or (select count(*) from public.school_lesson_exact_correction_events e
         where e.lesson_id=any(v_ids))<>0
     or (select md5(string_agg(md5(to_jsonb(l)::text),'' order by l.id::text))
         from public.school_lesson_records l where l.id=any(v_ids))
       <>'e2bc9f4380f5bf5a95ff0341ae47183b'
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.planned_lesson_id::text))
         from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=any(v_ids))<>'11b2bfdadaf78e6b4d853044c64f576d'
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.actual_lesson_id::text))
         from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids))<>'f5c2e715af4180af16576c32eb46f0ad'
     or exists(select 1 from auth.users where id::text like 'be130000-%')
     or exists(select 1 from public.school_app_memberships
       where user_id::text like 'be130000-%') then
    raise exception 'LI_WU_CORRECTION_REHEARSAL_ROLLBACK_RESTORE_FAILED';
  end if;
end;
$verify_after_rollback$;
select 'LI_WU_CORRECTION_PRODUCTION_REHEARSAL_ROLLBACK_PASS' result;
rollback;
