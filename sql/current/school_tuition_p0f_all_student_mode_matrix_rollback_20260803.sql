-- P0-F all-student source-treatment preview matrix. Fixed whitelist fixture;
-- every row is transactionally rolled back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $matrix$
declare
  v_marker constant text:='codex-test tuition-p0f-mode-matrix-20260803';
  v_entity constant uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_student constant uuid:='f0f20000-0000-4000-8000-00000000a001';
  v_teacher constant uuid:='f0f20000-0000-4000-8000-000000007001';
  v_subject_a constant uuid:='f0f20000-0000-4000-8000-00000000d001';
  v_subject_b constant uuid:='f0f20000-0000-4000-8000-00000000d002';
  v_preview record;
  v_actual uuid;
begin
  if exists(select 1 from public.school_students where id=v_student) then
    raise exception 'P0F_MODE_MATRIX_FIXTURE_COLLISION';
  end if;
  insert into public.school_subjects(id,name,category,is_active,note,primary_category)
  values
    (v_subject_a,'codex-test P0-F matrix A','codex-test',true,v_marker,'班课'),
    (v_subject_b,'codex-test P0-F matrix B','codex-test',true,v_marker,'一对一');
  insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
    default_business_entity_id,status,note,app_type)
  values(v_teacher,'codex-test-p0f-matrix','codex-test P0-F matrix teacher',
    'codex-test P0-F matrix teacher',v_subject_a,v_entity,'active',v_marker,'school');
  insert into public.school_students(id,student_code,name,display_name,business_entity_id,
    status,app_type,preset_exchange_rate,previous_balance_cny,note)
  values(v_student,'codex-test-p0f-matrix','codex-test P0-F matrix student',
    'codex-test P0-F matrix student',v_entity,'active','school',0.099,0,v_marker);

  -- 2020-01: unused only (-JPY 10,000).
  -- 2020-02: overage only (+JPY 4,000).
  -- 2020-03: different subject/rate net positive (-3,000 + 8,000 = +5,000).
  -- 2020-04: exact zero (-6,000 + 6,000).
  -- 2020-05: partial actual leaves 0.75h / JPY 5,250 unused.
  -- 2020-06: cancelled and non-billable are resolved but contribute zero.
  -- 2020-07: unresolved planned must fail closed in net mode.
  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,actual_minutes,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,
    billing_month_decided_at
  ) values
    ('f0f20000-0000-4000-8000-000000001001','planned','2020-01-08','2020-01',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',5000,10000,1,120,'online',v_marker,'2020-01','2020-01-06','2020-01-08','2020-01','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001002','planned','2020-02-08','2020-02',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'planned',true,v_marker,'school',4000,8000,1,120,'online',v_marker,'2020-02','2020-02-03','2020-02-08','2020-02','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001003','planned','2020-03-08','2020-03',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',1500,3000,1,120,'online',v_marker,'2020-03','2020-03-02','2020-03-08','2020-03','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001004','planned','2020-03-15','2020-03',v_student,v_teacher,v_subject_b,v_entity,'10:00','12:00',2,v_marker,'planned',true,v_marker,'school',8000,16000,1,120,'online',v_marker,'2020-03','2020-03-09','2020-03-15','2020-03','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001005','planned','2020-04-08','2020-04',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'pending_makeup',true,v_marker,'school',3000,6000,1,120,'online',v_marker,'2020-04','2020-04-06','2020-04-08','2020-04','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001006','planned','2020-04-15','2020-04',v_student,v_teacher,v_subject_b,v_entity,'10:00','12:00',2,v_marker,'planned',true,v_marker,'school',6000,12000,1,120,'online',v_marker,'2020-04','2020-04-13','2020-04-15','2020-04','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001007','planned','2020-05-08','2020-05',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'planned',true,v_marker,'school',7000,14000,1,120,'online',v_marker,'2020-05','2020-05-04','2020-05-08','2020-05','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001008','planned','2020-06-08','2020-06',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'cancelled',true,v_marker,'school',5000,10000,1,120,'online',v_marker,'2020-06','2020-06-08','2020-06-08','2020-06','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001009','planned','2020-06-15','2020-06',v_student,v_teacher,v_subject_b,v_entity,'10:00','12:00',2,v_marker,'planned',false,v_marker,'school',5000,0,1,120,'online',v_marker,'2020-06','2020-06-15','2020-06-15','2020-06','explicit_billing_week_at_create',now()),
    ('f0f20000-0000-4000-8000-000000001010','planned','2020-07-08','2020-07',v_student,v_teacher,v_subject_a,v_entity,'10:00','12:00',2,v_marker,'planned',true,v_marker,'school',5000,10000,1,120,'online',v_marker,'2020-07','2020-07-06','2020-07-08','2020-07','explicit_billing_week_at_create',now());

  select lesson_id into strict v_actual from public.school_create_actual_lesson_from_planned('f0f20000-0000-4000-8000-000000001002','2020-02-08','10:00','13:00',3,4000,null,1,v_marker,v_marker);
  select lesson_id into strict v_actual from public.school_create_actual_lesson_from_planned('f0f20000-0000-4000-8000-000000001004','2020-03-15','10:00','13:00',3,8000,null,1,v_marker,v_marker);
  select lesson_id into strict v_actual from public.school_create_actual_lesson_from_planned('f0f20000-0000-4000-8000-000000001006','2020-04-15','10:00','13:00',3,6000,null,1,v_marker,v_marker);
  perform * from public.school_create_partial_completed_actual_from_planned('f0f20000-0000-4000-8000-000000001007','2020-05-08','10:00','11:15',1.25,v_marker,v_marker);

  insert into public.school_income_records(id,business_entity_id,student_id,income_date,
    year_month,settlement_month,income_category,description,currency,amount,amount_jpy,
    payment_currency,status,is_taxable_income,receipt_status,
    include_in_student_settlement,note,app_type,operational_excluded)
  values
    ('f0f20000-0000-4000-8000-000000007101',v_entity,v_student,'2020-01-20','2020-01','2020-01','tuition',v_marker,'JPY',10000,10000,'JPY','received',false,'codex-test',true,v_marker,'school',false),
    ('f0f20000-0000-4000-8000-000000007102',v_entity,v_student,'2020-02-20','2020-02','2020-02','tuition',v_marker,'JPY',8000,8000,'JPY','received',false,'codex-test',true,v_marker,'school',false),
    ('f0f20000-0000-4000-8000-000000007103',v_entity,v_student,'2020-03-20','2020-03','2020-03','tuition',v_marker,'JPY',19000,19000,'JPY','received',false,'codex-test',true,v_marker,'school',false),
    ('f0f20000-0000-4000-8000-000000007104',v_entity,v_student,'2020-04-20','2020-04','2020-04','tuition',v_marker,'JPY',18000,18000,'JPY','received',false,'codex-test',true,v_marker,'school',false),
    ('f0f20000-0000-4000-8000-000000007105',v_entity,v_student,'2020-05-20','2020-05','2020-05','tuition',v_marker,'JPY',14000,14000,'JPY','received',false,'codex-test',true,v_marker,'school',false);

  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-01','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-01-01');
  if v_preview.unused_planned_credit_jpy<>-10000 or v_preview.overage_charge_jpy<>0 or v_preview.net_lesson_variance_jpy<>-10000 or v_preview.lesson_variance_source_count<>1 then raise exception 'P0F_MATRIX_UNUSED_ONLY_FAILED: %',to_jsonb(v_preview); end if;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-02','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-02-01');
  if v_preview.unused_planned_credit_jpy<>0 or v_preview.overage_charge_jpy<>4000 or v_preview.net_lesson_variance_jpy<>4000 or v_preview.lesson_variance_source_count<>1 then raise exception 'P0F_MATRIX_OVERAGE_ONLY_FAILED: %',to_jsonb(v_preview); end if;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-03','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-03-01');
  if v_preview.unused_planned_credit_jpy<>-3000 or v_preview.overage_charge_jpy<>8000 or v_preview.net_lesson_variance_jpy<>5000 or v_preview.lesson_variance_source_count<>2 then raise exception 'P0F_MATRIX_NET_POSITIVE_DIFFERENT_RATE_FAILED: %',to_jsonb(v_preview); end if;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-04','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-04-01');
  if v_preview.net_lesson_variance_jpy<>0 or v_preview.net_lesson_variance_cny<>0 or v_preview.lesson_variance_source_count<>2 then raise exception 'P0F_MATRIX_NET_ZERO_FAILED: %',to_jsonb(v_preview); end if;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-05','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-05-01');
  if v_preview.pending_makeup_hours<>0.75 or v_preview.unused_planned_credit_jpy<>-5250 or v_preview.lesson_variance_source_count<>1 then raise exception 'P0F_MATRIX_PARTIAL_FAILED: %',to_jsonb(v_preview); end if;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-06','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-06-01');
  if v_preview.net_lesson_variance_jpy<>0 or v_preview.lesson_variance_source_count<>0 then raise exception 'P0F_MATRIX_CANCELLED_NONBILLABLE_FAILED: %',to_jsonb(v_preview); end if;
  begin
    perform * from public.school_preview_student_settlement_source_treatment(v_student,'2020-07','net_lesson_variance_to_financial_credit_v1',0.05,'codex_test_rate','2020-07-01');
    raise exception 'P0F_MATRIX_UNRESOLVED_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_LESSON_SOURCE_UNRESOLVED' in sqlerrm)=0 then raise; end if;
  end;
  select * into strict v_preview from public.school_preview_student_settlement_source_treatment(v_student,'2020-07',null,null,null,null);
  if v_preview.source_treatment_mode<>'separate_makeup_and_overage_v1' or v_preview.net_lesson_variance_cny<>0 or v_preview.lesson_variance_source_count<>0 then raise exception 'P0F_MATRIX_DEFAULT_COMPATIBILITY_FAILED: %',to_jsonb(v_preview); end if;
end
$matrix$;

rollback;
\echo 'P0F_ALL_STUDENT_MODE_MATRIX_PASSED'
