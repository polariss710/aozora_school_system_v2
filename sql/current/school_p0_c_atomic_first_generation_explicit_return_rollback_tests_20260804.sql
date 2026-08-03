-- P0-C first-generation explicit-return regression. Test fixtures always roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $tests$
declare
  v_student constant uuid := 'c0c00000-0000-4000-8000-000000000001';
  v_marker constant text := 'codex-test p0-c explicit first-generation return 20260804';
  v_source public.school_lesson_records%rowtype;
  v_preview record;
  v_first record;
  v_second record;
  v_lesson uuid;
  v_generation_id uuid;
  v_revision_id uuid;
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='enabled')
         or (feature_key in ('student_tuition_generate','student_tuition_cash_submit') and state='blocked'))<>3 then
    raise exception 'P0_C_TEST_REQUIRED_GATE_STATE_INVALID';
  end if;
  if exists(select 1 from public.school_students where id=v_student) then
    raise exception 'P0_C_TEST_STUDENT_WHITELIST_COLLISION';
  end if;

  select lesson.* into strict v_source
  from public.school_lesson_records lesson
  join public.school_students student on student.id=lesson.student_id
  where lesson.app_type='school' and lesson.lesson_type='planned'
    and lesson.status='planned' and lesson.voided_at is null
    and lesson.teacher_id is not null and lesson.subject_id is not null
    and lesson.business_entity_id is not null
    and student.business_entity_id is not distinct from lesson.business_entity_id
  order by lesson.id limit 1;

  insert into public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) values(
    v_student,'codex-p0-c-explicit-return','codex-test P0-C explicit return',
    'codex-test P0-C explicit return',v_source.business_entity_id,'active','school',
    0.05,0,v_marker
  );
  select created.lesson_id into strict v_lesson
  from public.school_create_planned_lesson_record(
    date '2099-10-12',v_student,v_source.teacher_id,v_source.subject_id,
    v_source.business_entity_id,'15:00','17:00',0,12000,null,
    'planned',2,'codex-test P0-C first generation',v_marker
  ) created;

  select * into strict v_preview
  from public.school_get_student_tuition_validation_preview_details(v_student,'2099-10',0.05);
  if v_preview.candidate_count<>1 or v_preview.total_lesson_count<>2
     or v_preview.generation_manifest_sha256!~'^[0-9a-f]{64}$' then
    raise exception 'P0_C_TEST_PREVIEW_INVALID';
  end if;

  select * into strict v_first
  from public.school_generate_student_tuition_bill_atomic_core(
    v_student,'2099-10',0.05,v_preview.generation_manifest_sha256,v_marker,null
  );
  if v_first.idempotent or v_first.student_id<>v_student
     or v_first.billing_month<>'2099-10'
     or v_first.generation_manifest_sha256<>v_preview.generation_manifest_sha256
     or jsonb_object_length(to_jsonb(v_first))<>20 then
    raise exception 'P0_C_TEST_FIRST_RETURN_CONTRACT_INVALID';
  end if;

  select generation.id into strict v_generation_id
  from public.school_student_tuition_generation_identities generation
  where generation.student_id=v_student
    and generation.legacy_billing_identity_id=v_first.billing_identity_id;
  select revision.id into strict v_revision_id
  from public.school_student_tuition_generation_revisions revision
  where revision.generation_identity_id=v_generation_id
    and revision.tuition_bill_id=v_first.tuition_bill_id
    and revision.revision_no=1 and revision.lifecycle_status='active'
    and revision.generation_manifest_sha256=v_first.generation_manifest_sha256;
  if (select count(*) from public.school_student_tuition_billing_identities where student_id=v_student)<>1
     or (select count(*) from public.school_student_tuition_generation_identities where student_id=v_student)<>1
     or (select count(*) from public.school_student_tuition_generation_revisions where generation_identity_id=v_generation_id)<>1
     or (select count(*) from public.school_student_tuition_bills where student_id=v_student)<>1
     or (select count(*) from public.school_income_records where student_id=v_student)<>1
     or (select count(*) from public.school_student_tuition_bill_lessons where tuition_bill_id=v_first.tuition_bill_id)<>1 then
    raise exception 'P0_C_TEST_FIRST_GENERATION_CARDINALITY_INVALID';
  end if;

  perform public.school_validate_tuition_identity_for_bill(v_first.tuition_bill_id);
  perform public.school_validate_tuition_bill_income_for_bill(v_first.tuition_bill_id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_first.tuition_bill_id);
  perform public.school_validate_tuition_generation_revision_for_bill(v_first.tuition_bill_id);

  select * into strict v_second
  from public.school_generate_student_tuition_bill_atomic_core(
    v_student,'2099-10',0.05,v_preview.generation_manifest_sha256,v_marker,null
  );
  if not v_second.idempotent
     or v_second.tuition_bill_id<>v_first.tuition_bill_id
     or v_second.billing_identity_id<>v_first.billing_identity_id
     or v_second.income_record_id<>v_first.income_record_id
     or v_second.generation_manifest_sha256<>v_first.generation_manifest_sha256
     or (select count(*) from public.school_student_tuition_generation_revisions where generation_identity_id=v_generation_id)<>1 then
    raise exception 'P0_C_TEST_IDEMPOTENT_RETURN_INVALID';
  end if;

  begin
    perform * from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2099-10',0.05,repeat('0',64),v_marker,null
    );
    raise exception 'P0_C_EXPECTED_STALE_MANIFEST_REJECTION_MISSING';
  exception when others then
    if sqlerrm='P0_C_EXPECTED_STALE_MANIFEST_REJECTION_MISSING'
       or position('R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE' in sqlerrm)=0 then
      raise;
    end if;
  end;

  if (select count(*) from public.school_student_tuition_generation_revisions where generation_identity_id=v_generation_id)<>1
     or not exists(select 1 from public.school_student_tuition_generation_revisions where id=v_revision_id)
     or exists(select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'P0_C_TEST_POST_REJECTION_STATE_INVALID';
  end if;

  raise notice 'P0_C_FIRST_GENERATION_RETURN_PASS student=% lesson=% bill=% income=% generation=% revision=%',
    v_student,v_lesson,v_first.tuition_bill_id,v_first.income_record_id,v_generation_id,v_revision_id;
end;
$tests$;

rollback;

begin transaction read only;
do $residue$
declare v_student constant uuid := 'c0c00000-0000-4000-8000-000000000001';
begin
  if (select count(*) from public.school_students where id=v_student)
     +(select count(*) from public.school_lesson_records where student_id=v_student)
     +(select count(*) from public.school_student_tuition_billing_identities where student_id=v_student)
     +(select count(*) from public.school_student_tuition_generation_identities where student_id=v_student)
     +(select count(*) from public.school_student_tuition_bills where student_id=v_student)
     +(select count(*) from public.school_income_records where student_id=v_student)<>0
     or exists(select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'P0_C_TEST_FIXTURE_RESIDUE';
  end if;
end;
$residue$;
select 'P0_C_FIRST_GENERATION_EXPLICIT_RETURN_ROLLBACK_TEST_PASS' as result;
rollback;
