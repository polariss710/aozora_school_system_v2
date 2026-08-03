-- Committed whitelist fixture for the local tool save-draft path.
-- Lock is covered by rollback and production-authorized commit tests because
-- P0-F claim rows are intentionally delete-forbidden audit facts.
-- Required: -v p0f_local_fixture_action=preflight|insert|verify|cleanup|residue
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0f_local_fixture_action}
\else
  \echo 'P0F_LOCAL_FIXTURE_ACTION_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';
select set_config('school.p0f_local_fixture_action',:'p0f_local_fixture_action',true);

do $fixture$
declare
  v_action text := current_setting('school.p0f_local_fixture_action');
  v_marker constant text := 'codex-test tuition-p0f-local-tool-20260803';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_subject constant uuid := 'f0f40000-0000-4000-8000-00000000d001';
  v_teacher constant uuid := 'f0f40000-0000-4000-8000-000000007001';
  v_student constant uuid := 'f0f40000-0000-4000-8000-00000000a001';
  v_unused constant uuid := 'f0f40000-0000-4000-8000-000000001001';
  v_fulfilled constant uuid := 'f0f40000-0000-4000-8000-000000001002';
  v_income constant uuid := 'f0f40000-0000-4000-8000-000000007101';
  v_preview jsonb;
begin
  if v_action not in ('preflight','insert','verify','cleanup','residue') then
    raise exception 'P0F_LOCAL_FIXTURE_ACTION_INVALID';
  end if;

  if v_action in ('preflight','residue') then
    if exists(select 1 from public.school_subjects where id=v_subject or note=v_marker)
       or exists(select 1 from public.school_teachers where id=v_teacher or note=v_marker)
       or exists(select 1 from public.school_students where id=v_student or note=v_marker)
       or exists(select 1 from public.school_lesson_records where student_id=v_student or note=v_marker)
       or exists(select 1 from public.school_income_records where id=v_income or note=v_marker)
       or exists(select 1 from public.school_student_settlement_source_treatment_drafts where student_id=v_student)
       or exists(select 1 from public.school_student_settlement_adjustment_drafts where student_id=v_student)
       or exists(select 1 from public.school_student_monthly_settlements where student_id=v_student)
       or exists(select 1 from public.school_student_settlement_lesson_variance_claims where student_id=v_student) then
      raise exception 'P0F_LOCAL_FIXTURE_RESIDUE';
    end if;
  elsif v_action='insert' then
    if exists(select 1 from public.school_students where id=v_student)
       or exists(select 1 from public.school_lesson_records where id in (v_unused,v_fulfilled)) then
      raise exception 'P0F_LOCAL_FIXTURE_COLLISION';
    end if;
    insert into public.school_subjects(id,name,category,is_active,note,primary_category)
    values(v_subject,'codex-test P0-F local tool subject','codex-test',true,v_marker,'班课');
    insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
      default_business_entity_id,status,note,app_type)
    values(v_teacher,'codex-test-p0f-local-tool','codex-test P0-F local tool teacher',
      'codex-test P0-F local tool teacher',v_subject,v_entity,'active',v_marker,'school');
    insert into public.school_students(id,student_code,name,display_name,business_entity_id,
      status,app_type,preset_exchange_rate,previous_balance_cny,note)
    values(v_student,'codex-test-p0f-local-tool','codex-test P0-F local tool student',
      'codex-test P0-F local tool student',v_entity,'active','school',0.05,0,v_marker);
    insert into public.school_lesson_records(
      id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
      business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
      is_billable,note,app_type,unit_price,lesson_fee,lesson_count,actual_minutes,
      lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
      scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
    ) values
      (v_unused,'planned','2021-07-08','2021-07',v_student,v_teacher,v_subject,v_entity,
        '10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',8500,17000,1,120,
        'online',v_marker,'2021-07','2021-07-05','2021-07-08','2021-07',
        'explicit_billing_week_at_create',now()),
      (v_fulfilled,'planned','2021-07-15','2021-07',v_student,v_teacher,v_subject,v_entity,
        '10:00','12:00',2,v_marker,'planned',true,v_marker,'school',8500,17000,1,120,
        'online',v_marker,'2021-07','2021-07-12','2021-07-15','2021-07',
        'explicit_billing_week_at_create',now());
    perform * from public.school_create_actual_lesson_from_planned(
      v_fulfilled,'2021-07-15','10:00','12:15',2.25,8500,null,1,v_marker,v_marker
    );
    insert into public.school_income_records(
      id,business_entity_id,student_id,income_date,year_month,settlement_month,
      income_category,description,currency,amount,amount_jpy,payment_currency,status,
      is_taxable_income,receipt_status,include_in_student_settlement,note,app_type,
      operational_excluded
    ) values(v_income,v_entity,v_student,'2021-07-20','2021-07','2021-07','tuition',
      v_marker,'JPY',34000,34000,'JPY','received',false,'codex-test',true,v_marker,'school',false);
  elsif v_action='verify' then
    v_preview := public.school_preview_student_settlement_adjustment_dialog(
      v_student,v_entity,'2021-07','net_lesson_variance_to_financial_credit_v1',
      0.042,'codex_test_confirmed_rate_v1','2021-07-01','carry_final_balance',null
    );
    if (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric<>-17000
       or (v_preview->'preview'->>'overage_charge_jpy')::numeric<>2125
       or (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric<>-14875
       or (v_preview->'preview'->>'net_lesson_variance_cny')::numeric<>-624.75
       or (v_preview->'preview'->>'projected_final_carryover_cny')::numeric<>-624.75
       or (v_preview->'preview'->>'lesson_variance_source_count')::integer<>2
       or (select count(*) from public.school_student_settlement_source_treatment_drafts
          where student_id=v_student and status='active')<>1
       or (select count(*) from public.school_student_settlement_adjustment_drafts
          where student_id=v_student and status='active')<>1
       or exists(select 1 from public.school_student_monthly_settlements where student_id=v_student)
       or exists(select 1 from public.school_student_settlement_lesson_variance_claims where student_id=v_student) then
      raise exception 'P0F_LOCAL_FIXTURE_VERIFY_FAILED: %',v_preview;
    end if;
  elsif v_action='cleanup' then
    if (select count(*) from public.school_students where id=v_student and note=v_marker)<>1
       or (select count(*) from public.school_lesson_records where student_id=v_student and note=v_marker)<>3
       or (select count(*) from public.school_income_records where id=v_income and note=v_marker)<>1
       or (select count(*) from public.school_student_settlement_source_treatment_drafts
          where student_id=v_student) > 1
       or exists(select 1 from public.school_student_settlement_source_treatment_drafts
          where student_id=v_student and reason is distinct from v_marker)
       or (select count(*) from public.school_student_settlement_adjustment_drafts
          where student_id=v_student) > 1
       or exists(select 1 from public.school_student_settlement_adjustment_drafts
          where student_id=v_student and adjustment_reason is distinct from v_marker)
       or exists(select 1 from public.school_student_monthly_settlements where student_id=v_student)
       or exists(select 1 from public.school_student_settlement_lesson_variance_claims where student_id=v_student) then
      raise exception 'P0F_LOCAL_FIXTURE_CLEANUP_OWNERSHIP_FAILED';
    end if;
    perform set_config('school.p0f_draft_writer','on',true);
    delete from public.school_student_settlement_source_treatment_drafts
      where student_id=v_student and reason=v_marker;
    perform set_config('school.p0f_draft_writer','off',true);
    delete from public.school_student_settlement_adjustment_drafts
      where student_id=v_student and adjustment_reason=v_marker;
    delete from public.school_income_records where id=v_income and note=v_marker;
    delete from public.school_lesson_records where student_id=v_student and lesson_type='actual' and note=v_marker;
    delete from public.school_lesson_records where student_id=v_student and lesson_type='planned' and note=v_marker;
    delete from public.school_students where id=v_student and note=v_marker;
    delete from public.school_teachers where id=v_teacher and note=v_marker;
    delete from public.school_subjects where id=v_subject and note=v_marker;
  end if;
end
$fixture$;
commit;
