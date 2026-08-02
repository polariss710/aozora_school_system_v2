-- Committed synthetic fixture lifecycle for P0-A multi-session tests.
-- Required psql variable p0a_fixture_action: preflight | insert | cleanup | residue.
-- Every DELETE target is an exact fixed UUID; no Cash DB object is referenced.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0a_fixture_action}
\else
  \echo 'P0A_FIXTURE_ACTION_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';
select set_config('tuition.p0a_fixture_action',:'p0a_fixture_action',true);

do $lifecycle$
declare
  v_action constant text:=current_setting('tuition.p0a_fixture_action');
  v_marker constant text:='codex-test tuition-p0a-concurrency-20260803';
  v_entity constant uuid:='a0a00000-0000-4000-8000-00000000e100';
  v_subject constant uuid:='a0a00000-0000-4000-8000-00000000e101';
  v_teacher constant uuid:='a0a00000-0000-4000-8000-00000000e102';
  v_student constant uuid:='a0a00000-0000-4000-8000-00000000a100';
  v_lesson constant uuid:='a0a00000-0000-4000-8000-00000000a101';
  v_settlement constant uuid:='a0a00000-0000-4000-8000-00000000b100';
  v_preview record;
begin
  if v_action not in ('preflight','insert','cleanup','residue') then
    raise exception 'TUITION_P0A_FIXTURE_ACTION_INVALID: %',v_action;
  end if;

  if v_action in ('preflight','insert') then
    if exists (
      select 1 from public.school_business_entities where id=v_entity or code='codex-test-p0a-concurrency'
      union all select 1 from public.school_subjects where id=v_subject or name='codex-test P0-A subject'
      union all select 1 from public.school_teachers where id=v_teacher or teacher_code='codex-test-p0a-teacher'
      union all select 1 from public.school_students where id=v_student or student_code='codex-test-p0a-concurrency'
      union all select 1 from public.school_lesson_records where id=v_lesson
      union all select 1 from public.school_student_monthly_settlements where id=v_settlement
      union all select 1 from public.school_student_tuition_bills where student_id=v_student
      union all select 1 from public.school_student_tuition_billing_identities where student_id=v_student
      union all select 1 from public.school_income_records where student_id=v_student
      union all select 1 from public.school_personal_cash_income_linkage_events where note=v_marker
    ) then raise exception 'TUITION_P0A_FIXTURE_PREFLIGHT_COLLISION'; end if;
  end if;

  if v_action='insert' then
    insert into public.school_business_entities(
      id,code,name,entity_type,default_currency,is_active,note
    ) values (v_entity,'codex-test-p0a-concurrency','codex-test P0-A concurrency entity','company','JPY',true,v_marker);
    insert into public.school_subjects(
      id,name,category,is_active,note,primary_category
    ) values (v_subject,'codex-test P0-A subject','codex-test',true,v_marker,'班课');
    insert into public.school_teachers(
      id,teacher_code,name,display_name,default_subject_id,
      default_business_entity_id,status,note,app_type
    ) values (v_teacher,'codex-test-p0a-teacher','codex-test P0-A teacher',
      'codex-test P0-A teacher',v_subject,v_entity,'active',v_marker,'school');
    insert into public.school_students(
      id,student_code,name,display_name,business_entity_id,status,app_type,
      preset_exchange_rate,previous_balance_cny,note
    ) values (v_student,'codex-test-p0a-concurrency','codex-test P0-A concurrency student',
      'codex-test P0-A concurrency student',v_entity,'active','school',0.05,0,v_marker);

    insert into public.school_lesson_records(
      id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
      business_entity_id,start_time,end_time,duration_hours,lesson_content,
      status,is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
      lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
      scheduled_lesson_date,student_settlement_month,billing_month_source,
      billing_month_decided_at
    ) values (
      v_lesson,'planned',date '2020-06-10','2020-06',v_student,v_teacher,v_subject,
      v_entity,'15:00','17:00',2,v_marker,'planned',true,v_marker,'school',
      10000,20000,2,'online',v_marker,'2020-06',date '2020-06-08',
      date '2020-06-10','2020-06','explicit_billing_week_at_create',now()
    );

    insert into public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id,preset_exchange_rate,
      planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
      actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
      received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
      carryover_amount_cny,settlement_status,locked_at,note,
      duration_overage_minutes,duration_overage_fee_jpy,
      duration_overage_fee_cny,duration_overage_actual_count,
      duration_overage_policy_version,duration_overage_source
    ) values (
      v_settlement,v_student,'2020-05',v_entity,0.05,0,0,0,0,0,0,0,0,0,0,0,
      'locked',now(),v_marker,0,0,0,0,'student_duration_overage_v1','monthly_settlement_lock'
    );

    select * into strict v_preview
    from public.school_get_student_tuition_validation_preview_details(
      v_student,'2020-06',0.05);
    if v_preview.candidate_count<>1
       or v_preview.generation_manifest_sha256 !~ '^[0-9a-f]{64}$'
       or v_preview.previous_settlement_id<>v_settlement then
      raise exception 'TUITION_P0A_FIXTURE_PREVIEW_INVALID';
    end if;
  elsif v_action='cleanup' then
    if (select count(*) from public.school_business_entities where id=v_entity and note=v_marker)<>1
       or (select count(*) from public.school_subjects where id=v_subject and note=v_marker)<>1
       or (select count(*) from public.school_teachers where id=v_teacher and note=v_marker)<>1
       or (select count(*) from public.school_students where id=v_student and note=v_marker)<>1
       or (select count(*) from public.school_lesson_records where id=v_lesson and note=v_marker)<>1
       or (select count(*) from public.school_student_monthly_settlements where id=v_settlement and note=v_marker)<>1 then
      raise exception 'TUITION_P0A_FIXTURE_CLEANUP_OWNERSHIP_FAILED';
    end if;
    if exists (
      select 1 from public.school_student_tuition_bills where student_id=v_student
      union all select 1 from public.school_student_tuition_billing_identities where student_id=v_student
      union all select 1 from public.school_student_tuition_bill_lessons where planned_lesson_id=v_lesson
      union all select 1 from public.school_income_records where student_id=v_student
      union all select 1 from public.school_student_settlement_adjustment_drafts where student_id=v_student
      union all select 1 from public.school_student_settlement_adjustments where student_id=v_student
      union all select 1 from public.school_student_settlement_carryovers where student_id=v_student
      union all select 1 from public.school_personal_cash_income_linkage_events where note=v_marker
    ) then raise exception 'TUITION_P0A_FIXTURE_CLEANUP_UNEXPECTED_REFERENCE'; end if;

    delete from public.school_student_monthly_settlements where id=v_settlement;
    delete from public.school_lesson_records where id=v_lesson;
    delete from public.school_students where id=v_student;
    delete from public.school_teachers where id=v_teacher;
    delete from public.school_subjects where id=v_subject;
    delete from public.school_business_entities where id=v_entity;
  end if;

  if v_action in ('preflight','residue','cleanup') and exists (
    select 1 from public.school_business_entities where id=v_entity or note=v_marker
    union all select 1 from public.school_subjects where id=v_subject or note=v_marker
    union all select 1 from public.school_teachers where id=v_teacher or note=v_marker
    union all select 1 from public.school_students where id=v_student or note=v_marker
    union all select 1 from public.school_lesson_records where id=v_lesson or note=v_marker
    union all select 1 from public.school_student_monthly_settlements where id=v_settlement or note=v_marker
    union all select 1 from public.school_student_settlement_adjustment_drafts where note=v_marker
    union all select 1 from public.school_student_settlement_adjustments where note=v_marker
    union all select 1 from public.school_student_settlement_carryovers where note=v_marker
    union all select 1 from public.school_student_tuition_bills where student_id=v_student or note=v_marker
    union all select 1 from public.school_student_tuition_billing_identities where student_id=v_student
    union all select 1 from public.school_income_records where student_id=v_student or note=v_marker
    union all select 1 from public.school_personal_cash_income_linkage_events where note=v_marker
  ) then raise exception 'TUITION_P0A_FIXTURE_RESIDUE_NOT_ZERO'; end if;
end
$lifecycle$;

select :'p0a_fixture_action' as action,
  (select count(*) from public.school_students where id='a0a00000-0000-4000-8000-00000000a100') as student_count,
  (select count(*) from public.school_lesson_records where id='a0a00000-0000-4000-8000-00000000a101') as lesson_count,
  (select count(*) from public.school_student_monthly_settlements where id='a0a00000-0000-4000-8000-00000000b100') as settlement_count;
commit;
