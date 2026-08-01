-- School V2 R2-F-E1 rollback-only charged lesson-credit completion tests.
-- Every fixture and business write is enclosed by one transaction and ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off

\echo 'R2_F_E1_ROLLBACK_TEST_BEGIN'
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $tests$
DECLARE
  v_today date:=(statement_timestamp() AT TIME ZONE 'Asia/Tokyo')::date;
  v_tomorrow date:=v_today+1;
  v_week_start date:=date_trunc('week',v_today::timestamp)::date;
  v_student uuid:='eb705aad-de4d-45e6-a391-42dcdd89aeda';
  v_teacher uuid:='ea58874b-3656-4b14-8977-dc8bf9423997';
  v_subject uuid:='a7f9faaa-4480-44c0-9b66-fd70379ab7cb';
  v_entity uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_charged public.school_lesson_records%ROWTYPE;
  v_pending public.school_lesson_records%ROWTYPE;
  v_source_after public.school_lesson_records%ROWTYPE;
  v_future public.school_lesson_records%ROWTYPE;
  v_makeup public.school_lesson_records%ROWTYPE;
  v_relation_template public.school_student_tuition_bill_lessons%ROWTYPE;
  v_relation_id uuid:=gen_random_uuid();
  v_credit_before record;
  v_credit_pending record;
  v_credit_after record;
  v_finance_before jsonb;
  v_finance_after jsonb;
BEGIN
  SELECT r.* INTO STRICT v_relation_template
  FROM public.school_student_tuition_bill_lessons r
  WHERE r.id='7d3a5842-2101-5fd1-dd6e-706267a3e31f';

  SELECT c.* INTO STRICT v_credit_before
  FROM public.school_get_lesson_credit_summary(v_student,v_entity) c;

  SELECT created.* INTO STRICT v_charged
  FROM public.school_create_planned_lesson_record_with_venue(
    v_week_start,v_student,v_teacher,v_subject,v_entity,
    '03:00','05:00',2,8500,NULL,'planned',1,
    'codex-test R2-F-E1 charged source','codex-test R2-F-E1 rollback',
    'online','R2-F-E1-test',0
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
    v_relation_template.relation_role,v_relation_template.line_no+20000,
    v_student,v_entity,to_char(v_week_start,'YYYY-MM'),v_week_start,
    v_week_start,v_teacher,v_subject,1,2,8500,17000,
    v_charged.updated_at,v_relation_template.source_snapshot,
    v_relation_template.attribution_confidence,
    v_relation_template.snapshot_source,v_relation_template.backfill_batch_id,
    statement_timestamp(),'codex-test-r2-f-e1',17000,NULL,0,0,0,
    'planned_weekend_aircon_v1',NULL,NULL
  );

  SELECT saved.* INTO STRICT v_pending
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_charged.id,v_charged.updated_at,v_charged.lesson_date,
    v_charged.student_id,v_charged.teacher_id,v_charged.subject_id,
    v_charged.business_entity_id,v_charged.start_time,v_charged.end_time,
    v_charged.duration_hours,v_charged.unit_price,NULL,'pending_makeup',true,
    v_charged.lesson_count,v_charged.lesson_content,v_charged.note,
    v_charged.lesson_delivery_mode,v_charged.lesson_venue,0
  ) saved;

  SELECT c.* INTO STRICT v_credit_pending
  FROM public.school_get_lesson_credit_summary(v_student,v_entity) c;
  IF v_pending.status<>'pending_makeup'
     OR v_credit_pending.open_source_count<>v_credit_before.open_source_count+1
     OR v_credit_pending.open_credit_hours<>v_credit_before.open_credit_hours+2
     OR public.school_get_lesson_credit_remaining_hours(v_pending.id)<>2 THEN
    RAISE EXCEPTION 'R2_F_E1_PENDING_CREDIT_CREATION_FAILED';
  END IF;

  SELECT jsonb_build_object(
    'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x),
    'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x),
    'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x),
    'identity',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_billing_identities x)
  ) INTO v_finance_before;

  SELECT actual.* INTO STRICT v_makeup
  FROM public.school_create_lesson_credit_makeup_actual(
    v_pending.id,v_today,v_teacher,v_subject,'03:00','05:00',2,
    'codex-test R2-F-E1 makeup actual','codex-test R2-F-E1 rollback',1,
    'online','R2-F-E1-test'
  ) actual;

  SELECT l.* INTO STRICT v_source_after
  FROM public.school_lesson_records l WHERE l.id=v_pending.id;
  SELECT c.* INTO STRICT v_credit_after
  FROM public.school_get_lesson_credit_summary(v_student,v_entity) c;
  SELECT jsonb_build_object(
    'bills',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bills x),
    'income',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_income_records x),
    'relations',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_bill_lessons x),
    'identity',(SELECT jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' ORDER BY x.id::text),''))) FROM public.school_student_tuition_billing_identities x)
  ) INTO v_finance_after;

  IF v_source_after.status<>'pending_makeup'
     OR v_source_after.student_id IS DISTINCT FROM v_pending.student_id
     OR v_source_after.business_entity_id IS DISTINCT FROM v_pending.business_entity_id
     OR v_source_after.subject_id IS DISTINCT FROM v_pending.subject_id
     OR v_source_after.year_month IS DISTINCT FROM v_pending.year_month
     OR v_source_after.duration_hours IS DISTINCT FROM v_pending.duration_hours
     OR v_source_after.unit_price IS DISTINCT FROM v_pending.unit_price
     OR v_source_after.lesson_fee IS DISTINCT FROM v_pending.lesson_fee
     OR v_makeup.lesson_type<>'actual'
     OR v_makeup.status<>'makeup_completed'
     OR v_makeup.is_billable IS DISTINCT FROM false
     OR v_makeup.lesson_fee<>0
     OR v_makeup.planned_lesson_id IS DISTINCT FROM v_pending.id
     OR v_makeup.student_settlement_month IS DISTINCT FROM
          public.school_resolve_r1d_e_b2_actual_student_month(v_pending.id)
     OR v_makeup.teacher_settlement_month<>to_char(v_today,'YYYY-MM')
     OR public.school_get_lesson_credit_remaining_hours(v_pending.id)<>0
     OR v_credit_after.open_source_count<>v_credit_before.open_source_count
     OR v_credit_after.open_credit_hours<>v_credit_before.open_credit_hours
     OR v_finance_after IS DISTINCT FROM v_finance_before
     OR EXISTS (
       SELECT 1 FROM public.school_list_open_lesson_credit_sources(
         to_char(v_week_start,'YYYY-MM'),to_char(v_week_start,'YYYY-MM'),
         to_char(v_today,'YYYY-MM')
       ) s WHERE s.id=v_pending.id
     )
     OR EXISTS (
       SELECT 1 FROM public.school_list_student_tuition_candidates(
         v_student,v_entity,to_char(v_week_start+35,'YYYY-MM'),false
       ) c WHERE c.planned_lesson_id=v_pending.id
     ) THEN
    RAISE EXCEPTION 'R2_F_E1_CHARGED_MAKEUP_COMPLETION_FAILED';
  END IF;

  BEGIN
    PERFORM * FROM public.school_create_lesson_credit_makeup_actual(
      v_pending.id,v_today,v_teacher,v_subject,'03:00','05:00',2,
      'codex-test R2-F-E1 duplicate makeup','codex-test R2-F-E1 rollback',1,
      'online','R2-F-E1-test'
    );
    RAISE EXCEPTION 'R2_F_E1_EXPECTED_DUPLICATE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'该待补课来源已无剩余课时。' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.school_lesson_records a
      WHERE a.planned_lesson_id=v_pending.id
        AND a.lesson_type='actual' AND a.status='makeup_completed')<>1 THEN
    RAISE EXCEPTION 'R2_F_E1_DUPLICATE_MAKEUP_RESIDUE_FAILED';
  END IF;

  BEGIN
    UPDATE public.school_lesson_records SET unit_price=unit_price+1
    WHERE id=v_pending.id;
    RAISE EXCEPTION 'R2_F_E1_EXPECTED_CHARGE_FREEZE_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' THEN RAISE; END IF;
  END;

  SELECT created.* INTO STRICT v_future
  FROM public.school_create_planned_lesson_record_with_venue(
    v_tomorrow,v_student,v_teacher,v_subject,v_entity,
    '06:00','08:00',2,8500,NULL,'pending_makeup',1,
    'codex-test R2-F-E1 future source','codex-test R2-F-E1 rollback',
    'online','R2-F-E1-test',0
  ) created;
  BEGIN
    PERFORM * FROM public.school_create_lesson_credit_makeup_actual(
      v_future.id,v_tomorrow,v_teacher,v_subject,'06:00','08:00',2,
      'codex-test R2-F-E1 future makeup','codex-test R2-F-E1 rollback',1,
      'online','R2-F-E1-test'
    );
    RAISE EXCEPTION 'R2_F_E1_EXPECTED_FUTURE_MAKEUP_REJECTION_MISSING';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'FUTURE_ACTUAL_COMPLETION_FORBIDDEN' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'R2_F_E1_TEST_IDS source=%, relation=%, makeup_actual=%',
    v_pending.id,v_relation_id,v_makeup.id;
  RAISE NOTICE 'R2_F_E1_ROLLBACK_MATRIX=PASS';
END
$tests$;

DO $resolver_tests$
DECLARE
  v_actual public.school_lesson_records%ROWTYPE;
  v_evidence_hash text;
  v_definition text;
BEGIN
  SELECT actual.* INTO STRICT v_actual
  FROM public.school_lesson_records actual
  WHERE actual.id='a1977f69-69d7-45d5-a958-50138d3f80d4';
  SELECT md5(to_jsonb(evidence)::text) INTO STRICT v_evidence_hash
  FROM public.school_legacy_actual_settlement_evidence evidence
  WHERE evidence.actual_lesson_id=v_actual.id;

  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual.id)<>'2026-07' THEN
    RAISE EXCEPTION 'R2_F_E1_EXISTING_LEGACY_EDIT_RESOLUTION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id=v_actual.student_id
      AND settlement.business_entity_id IS NOT DISTINCT FROM v_actual.business_entity_id
      AND settlement.year_month='2026-07'
      AND settlement.settlement_status='locked'
  ) THEN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_actual.id,v_actual.updated_at,v_actual.lesson_date,v_actual.student_id,
      v_actual.teacher_id,v_actual.subject_id,v_actual.business_entity_id,
      v_actual.start_time,v_actual.end_time,v_actual.duration_hours,
      v_actual.unit_price,v_actual.lesson_fee,v_actual.status,
      v_actual.is_billable,v_actual.lesson_count,v_actual.lesson_content,
      coalesce(v_actual.note,'')||' codex-test R2-F-E1 legal note edit',
      v_actual.lesson_delivery_mode,v_actual.lesson_venue
    );
  ELSE
    RAISE NOTICE 'R2_F_E1_LEGACY_EDIT_SKIPPED_LOCKED_SETTLEMENT actual=%',v_actual.id;
  END IF;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual.id)<>'2026-07'
     OR (SELECT md5(to_jsonb(evidence)::text)
         FROM public.school_legacy_actual_settlement_evidence evidence
         WHERE evidence.actual_lesson_id=v_actual.id) IS DISTINCT FROM
          v_evidence_hash THEN
    RAISE EXCEPTION 'R2_F_E1_LEGAL_NOTE_EDIT_CONTRACT_FAILED';
  END IF;

  SELECT pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) INTO STRICT v_definition;
  IF position('v_actual_evidence.source_planned_lesson_id IS DISTINCT FROM' IN
       v_definition)=0
     OR position('v_actual_evidence.student_id_snapshot IS DISTINCT FROM' IN
       v_definition)=0
     OR position('v_actual_evidence.business_entity_id_snapshot IS DISTINCT FROM' IN
       v_definition)=0
     OR position('v_actual_evidence.legacy_year_month IS DISTINCT FROM' IN
       v_definition)=0
     OR position('v_actual_evidence.teacher_id_snapshot' IN v_definition)>0
     OR position('v_actual_evidence.subject_id_snapshot' IN v_definition)>0
     OR position('v_actual_evidence.lesson_date_snapshot' IN v_definition)>0
     OR position('to_jsonb(v_lesson)' IN v_definition)>0 THEN
    RAISE EXCEPTION 'R2_F_E1_STRUCTURED_EVIDENCE_STATIC_CONTRACT_FAILED';
  END IF;
  RAISE NOTICE 'R2_F_E1_LEGACY_EDIT_TEST_ID actual=%',v_actual.id;
  RAISE NOTICE 'R2_F_E1_STRUCTURED_EVIDENCE_MATRIX=PASS';
END
$resolver_tests$;

ROLLBACK;
\echo 'R2_F_E1_ROLLBACK_TEST_ROLLED_BACK'

SELECT
  count(*) FILTER (WHERE l.lesson_content LIKE 'codex-test R2-F-E1%') AS lesson_residue,
  count(*) FILTER (WHERE r.created_by='codex-test-r2-f-e1') AS relation_residue
FROM public.school_lesson_records l
FULL JOIN public.school_student_tuition_bill_lessons r ON false;
