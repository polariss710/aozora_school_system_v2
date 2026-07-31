-- School V2 R2-F-E rollback-only business and direct-DML tests.
-- Every fixture and write is enclosed by one explicit transaction and ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

\echo 'R2_F_E_ROLLBACK_TEST_BEGIN'
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

CREATE TEMPORARY TABLE r2_f_e_before ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_lesson_records x),
  'settlements',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_monthly_settlements x),
  'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x),
  'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x),
  'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x),
  'identity',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_billing_identities x),
  'wage_details',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_teacher_wage_lock_details x),
  'accounts',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_account_transactions x),
  'cash_income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_personal_cash_income_linkage_events x)
) AS fingerprint;

DO $tests$
DECLARE
  v_today date:=(statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date;
  v_tomorrow date:=v_today+1;
  v_yesterday date:=v_today-1;
  v_week_start date:=date_trunc('week',v_today::timestamp)::date;
  v_student uuid:='eb705aad-de4d-45e6-a391-42dcdd89aeda';
  v_teacher uuid:='ea58874b-3656-4b14-8977-dc8bf9423997';
  v_other_teacher uuid;
  v_subject uuid:='a7f9faaa-4480-44c0-9b66-fd70379ab7cb';
  v_other_subject uuid;
  v_entity uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_charged public.school_lesson_records%ROWTYPE;
  v_saved public.school_lesson_records%ROWTYPE;
  v_planned public.school_lesson_records%ROWTYPE;
  v_actual record;
  v_actual_row public.school_lesson_records%ROWTYPE;
  v_relation_template public.school_student_tuition_bill_lessons%ROWTYPE;
  v_relation_id uuid:=gen_random_uuid();
  v_initial_relation_count bigint;
  v_remaining numeric;
BEGIN
  SELECT t.id INTO STRICT v_other_teacher
  FROM public.school_teachers t
  WHERE t.app_type='school'
    AND coalesce(t.status,'employed') NOT IN ('inactive','retired')
    AND t.id<>v_teacher
  ORDER BY t.id LIMIT 1;
  SELECT s.id INTO STRICT v_other_subject
  FROM public.school_subjects s
  WHERE coalesce(s.is_active,true) AND s.id<>v_subject
  ORDER BY s.id LIMIT 1;
  SELECT r.* INTO STRICT v_relation_template
  FROM public.school_student_tuition_bill_lessons r
  WHERE r.id='7d3a5842-2101-5fd1-dd6e-706267a3e31f';
  SELECT count(*) INTO v_initial_relation_count
  FROM public.school_student_tuition_bill_lessons;

  -- Synthetic charged planned fixture: public RPC creation plus a rollback-only
  -- deferred relation row. No real lesson or bill row is updated.
  SELECT created.* INTO STRICT v_charged
  FROM public.school_create_planned_lesson_record_with_venue(
    v_week_start,v_student,v_teacher,v_subject,v_entity,
    '03:00','05:00',2,8500,NULL,'planned',1,
    'codex-test R2-F-E charged planned','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;

  INSERT INTO public.school_student_tuition_bill_lessons (
    id,tuition_bill_id,planned_lesson_id,relation_role,line_no,
    student_id_snapshot,business_entity_id_snapshot,billing_month_snapshot,
    week_start_date_snapshot,scheduled_lesson_date_snapshot,
    teacher_id_snapshot,subject_id_snapshot,lesson_count_snapshot,
    duration_hours_snapshot,unit_price_jpy_snapshot,lesson_fee_jpy_snapshot,
    source_lesson_updated_at,source_snapshot,attribution_confidence,
    snapshot_source,backfill_batch_id,created_at,created_by,
    base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
    aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,
    aircon_fee_jpy_snapshot,fee_calculation_version_snapshot,
    lesson_venue_id_snapshot,lesson_venue_code_snapshot
  ) VALUES (
    v_relation_id,v_relation_template.tuition_bill_id,v_charged.id,
    v_relation_template.relation_role,v_relation_template.line_no+10000,
    v_student,v_entity,to_char(v_week_start,'YYYY-MM'),v_week_start,
    v_week_start,v_teacher,v_subject,1,2,8500,17000,
    v_charged.updated_at,v_relation_template.source_snapshot,
    v_relation_template.attribution_confidence,
    v_relation_template.snapshot_source,v_relation_template.backfill_batch_id,
    statement_timestamp(),'codex-test-r2-f-e',17000,NULL,0,0,0,
    'planned_weekend_aircon_v1',NULL,NULL
  );

  SELECT saved.* INTO STRICT v_saved
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_charged.id,v_charged.updated_at,v_week_start+5,
    v_student,v_other_teacher,v_subject,v_entity,
    '04:00','06:00',2,8500,NULL,'pending_makeup',true,1,
    v_charged.lesson_content,v_charged.note,'online','R2-F-E-test',0
  ) saved;

  SELECT public.school_get_lesson_credit_remaining_hours(v_charged.id)
  INTO v_remaining;
  IF v_saved.status<>'pending_makeup'
     OR v_saved.teacher_id IS DISTINCT FROM v_other_teacher
     OR v_saved.lesson_date IS DISTINCT FROM v_week_start+5
     OR v_saved.year_month IS DISTINCT FROM to_char(v_week_start,'YYYY-MM')
     OR v_saved.billing_month IS DISTINCT FROM v_charged.billing_month
     OR v_saved.billing_week_start_date
          IS DISTINCT FROM v_charged.billing_week_start_date
     OR v_saved.student_settlement_month
          IS DISTINCT FROM v_charged.student_settlement_month
     OR v_saved.subject_id IS DISTINCT FROM v_subject
     OR v_saved.duration_hours IS DISTINCT FROM 2::numeric
     OR v_saved.unit_price IS DISTINCT FROM 8500::numeric
     OR v_saved.lesson_fee IS DISTINCT FROM 17000::numeric
     OR v_remaining IS DISTINCT FROM 2::numeric
     OR NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
                    WHERE r.id=v_relation_id AND r.planned_lesson_id=v_charged.id)
     OR EXISTS (SELECT 1 FROM public.school_list_student_tuition_candidates(
                  v_student,v_entity,to_char(v_week_start+35,'YYYY-MM'),false
                ) c WHERE c.planned_lesson_id=v_charged.id) THEN
    RAISE EXCEPTION 'R2_F_E_CHARGED_TO_PENDING_RESULT_FAILED';
  END IF;

  -- Same transition payload remains idempotent and does not create a second
  -- relation or a second credit balance.
  SELECT saved.* INTO STRICT v_saved
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_saved.id,v_saved.updated_at,v_saved.lesson_date,
    v_saved.student_id,v_saved.teacher_id,v_saved.subject_id,
    v_saved.business_entity_id,v_saved.start_time,v_saved.end_time,
    v_saved.duration_hours,v_saved.unit_price,NULL,v_saved.status,true,
    v_saved.lesson_count,v_saved.lesson_content,v_saved.note,
    v_saved.lesson_delivery_mode,v_saved.lesson_venue,0
  ) saved;
  IF public.school_get_lesson_credit_remaining_hours(v_charged.id)
       IS DISTINCT FROM 2::numeric
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)
          <> v_initial_relation_count+1 THEN
    RAISE EXCEPTION 'R2_F_E_CHARGED_PENDING_IDEMPOTENCY_FAILED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records SET subject_id=v_other_subject
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_SUBJECT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET duration_hours=2.25
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_DURATION_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM NOT IN (
      'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE',
      'R1D_F1_CANONICAL_PLANNED_DURATION_INVALID'
    ) THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET unit_price=8501
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_UNIT_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET lesson_fee=17001
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_FEE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET lesson_date=v_week_start+7
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_WEEK_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_DATE_OUTSIDE_CHARGE_WEEK' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.school_lesson_records SET status='planned'
    WHERE id=v_charged.id;
    RAISE EXCEPTION 'R2_F_E_EXPECTED_REOPEN_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN' THEN RAISE; END IF;
  END;

  -- Today completed actual succeeds.
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_today,v_student,v_teacher,v_subject,v_entity,'06:00','08:00',2,8500,
    NULL,'planned',1,'codex-test R2-F-E today','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  SELECT actual.* INTO STRICT v_actual
  FROM public.school_create_actual_lesson_from_planned(
    v_planned.id,v_today,'06:00','08:00',2,8500,NULL,1,
    'codex-test R2-F-E today actual','codex-test R2-F-E rollback'
  ) actual;
  SELECT l.* INTO STRICT v_actual_row
  FROM public.school_lesson_records l WHERE l.id=v_actual.lesson_id;
  IF v_actual_row.status<>'completed'
     OR v_actual_row.lesson_date IS DISTINCT FROM v_today THEN
    RAISE EXCEPTION 'R2_F_E_TODAY_ACTUAL_FAILED';
  END IF;

  -- A completed actual cannot be moved to tomorrow by the guarded editor.
  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_actual_row.id,v_actual_row.updated_at,v_tomorrow,v_actual_row.student_id,
      v_actual_row.teacher_id,v_actual_row.subject_id,v_actual_row.business_entity_id,
      v_actual_row.start_time,v_actual_row.end_time,v_actual_row.duration_hours,
      v_actual_row.unit_price,NULL,v_actual_row.status,v_actual_row.is_billable,
      v_actual_row.lesson_count,v_actual_row.lesson_content,v_actual_row.note,
      v_actual_row.lesson_delivery_mode,v_actual_row.lesson_venue
    );
    RAISE EXCEPTION 'R2_F_E_EXPECTED_EDIT_FUTURE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'FUTURE_ACTUAL_COMPLETION_FORBIDDEN' THEN RAISE; END IF;
  END;

  -- Past completed actual succeeds.
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_yesterday,v_student,v_teacher,v_subject,v_entity,'08:00','10:00',2,8500,
    NULL,'planned',1,'codex-test R2-F-E past','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  SELECT actual.* INTO STRICT v_actual
  FROM public.school_create_actual_lesson_from_planned(
    v_planned.id,v_yesterday,'08:00','10:00',2,8500,NULL,1,
    'codex-test R2-F-E past actual','codex-test R2-F-E rollback'
  ) actual;
  SELECT l.* INTO STRICT v_actual_row
  FROM public.school_lesson_records l WHERE l.id=v_actual.lesson_id;
  IF v_actual_row.lesson_date IS DISTINCT FROM v_yesterday THEN
    RAISE EXCEPTION 'R2_F_E_PAST_ACTUAL_FAILED';
  END IF;

  -- Tomorrow ordinary actual is rejected while future planned remains valid.
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_tomorrow,v_student,v_teacher,v_subject,v_entity,'10:00','12:00',2,8500,
    NULL,'planned',1,'codex-test R2-F-E future planned','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_planned.id,v_tomorrow,'10:00','12:00',2,8500,NULL,1,
      'codex-test R2-F-E future actual','codex-test R2-F-E rollback'
    );
    RAISE EXCEPTION 'R2_F_E_EXPECTED_FUTURE_ACTUAL_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'FUTURE_ACTUAL_COMPLETION_FORBIDDEN' THEN RAISE; END IF;
  END;

  -- Partial writer: today succeeds, tomorrow fails.
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_today,v_student,v_teacher,v_subject,v_entity,'12:00','14:00',2,8500,
    NULL,'planned',1,'codex-test R2-F-E partial today','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  PERFORM * FROM public.school_create_partial_completed_actual_from_planned(
    v_planned.id,v_today,'12:00','13:00',1,
    'codex-test R2-F-E partial today','codex-test R2-F-E rollback'
  );
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_tomorrow,v_student,v_teacher,v_subject,v_entity,'14:00','16:00',2,8500,
    NULL,'planned',1,'codex-test R2-F-E partial future','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  BEGIN
    PERFORM * FROM public.school_create_partial_completed_actual_from_planned(
      v_planned.id,v_tomorrow,'14:00','15:00',1,
      'codex-test R2-F-E partial future','codex-test R2-F-E rollback'
    );
    RAISE EXCEPTION 'R2_F_E_EXPECTED_FUTURE_PARTIAL_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'FUTURE_ACTUAL_COMPLETION_FORBIDDEN' THEN RAISE; END IF;
  END;

  -- Makeup writer: today succeeds, tomorrow fails.
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_today,v_student,v_teacher,v_subject,v_entity,'16:00','18:00',2,8500,
    NULL,'pending_makeup',1,'codex-test R2-F-E makeup today','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  PERFORM * FROM public.school_create_lesson_credit_makeup_actual(
    v_planned.id,v_today,v_teacher,v_subject,'16:00','18:00',2,
    'codex-test R2-F-E makeup today','codex-test R2-F-E rollback',1,
    'online','R2-F-E-test'
  );
  SELECT created.* INTO STRICT v_planned
  FROM public.school_create_planned_lesson_record_with_venue(
    v_tomorrow,v_student,v_teacher,v_subject,v_entity,'18:00','20:00',2,8500,
    NULL,'pending_makeup',1,'codex-test R2-F-E makeup future','codex-test R2-F-E rollback',
    'online','R2-F-E-test',0
  ) created;
  BEGIN
    PERFORM * FROM public.school_create_lesson_credit_makeup_actual(
      v_planned.id,v_tomorrow,v_teacher,v_subject,'18:00','20:00',2,
      'codex-test R2-F-E makeup future','codex-test R2-F-E rollback',1,
      'online','R2-F-E-test'
    );
    RAISE EXCEPTION 'R2_F_E_EXPECTED_FUTURE_MAKEUP_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'FUTURE_ACTUAL_COMPLETION_FORBIDDEN' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'R2_F_E_TEST_IDS charged=%, relation=%, today_actual=%',
    v_charged.id,v_relation_id,v_actual_row.id;
  RAISE NOTICE 'R2_F_E_ROLLBACK_MATRIX=PASS';
END
$tests$;

ROLLBACK;
\echo 'R2_F_E_ROLLBACK_TEST_ROLLED_BACK'

SELECT
  count(*) FILTER (WHERE lesson_content LIKE 'codex-test R2-F-E%') AS lesson_residue,
  count(*) FILTER (WHERE created_by='codex-test-r2-f-e') AS relation_residue
FROM public.school_lesson_records l
FULL JOIN public.school_student_tuition_bill_lessons r ON false;
