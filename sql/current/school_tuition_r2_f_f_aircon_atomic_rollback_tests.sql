-- School V2 R2-F-F rollback-only aircon and atomic-generate acceptance.
-- All fixture business writes are marked codex-test and end in ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off

\echo 'R2_F_F_ROLLBACK_TEST_BEGIN'
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';

CREATE TEMPORARY TABLE r2_f_f_results(
  test_name text PRIMARY KEY,passed boolean NOT NULL,detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_student_a constant uuid:='f2ff0000-0000-4000-8000-00000000a001';
  v_student_b constant uuid:='f2ff0000-0000-4000-8000-00000000a002';
  v_plan_a uuid;
  v_plan_b uuid;
  v_actual_a uuid;
  v_calc record;
  v_row public.school_lesson_records%ROWTYPE;
  v_actual public.school_lesson_records%ROWTYPE;
  v_preview_before record;
  v_preview_public record;
  v_preview_final record;
  v_preview_b record;
  v_generated record;
  v_idempotent record;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_relation public.school_student_tuition_bill_lessons%ROWTYPE;
  v_failed boolean;
BEGIN
  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  JOIN public.school_students student ON student.id=lesson.student_id
  WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
    AND lesson.teacher_id IS NOT NULL AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND student.business_entity_id IS NOT DISTINCT FROM lesson.business_entity_id
  ORDER BY lesson.id LIMIT 1;

  -- Pure policy matrix: structured venue, delivery mode, weekday and floor().
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','onsite',NULL,'Regus办公室',2,17000,330
  );
  IF v_calc.aircon_billable_hours<>2 OR v_calc.aircon_fee_jpy<>660
     OR v_calc.lesson_total_fee_jpy<>17660 THEN
    RAISE EXCEPTION 'R2_F_F_CASE_A_OFFICE_WEEKEND_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','onsite',NULL,'Regus公共区',2,17000,330
  );
  IF v_calc.aircon_billable_hours<>0 OR v_calc.aircon_fee_jpy<>0
     OR v_calc.fee_block_reason_code<>'AIRCON_VENUE_NOT_ELIGIBLE' THEN
    RAISE EXCEPTION 'R2_F_F_CASE_B_NONBILLABLE_VENUE_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','online',NULL,'Regus办公室',2,17000,330
  );
  IF v_calc.aircon_billable_hours<>0 OR v_calc.aircon_fee_jpy<>0
     OR v_calc.fee_block_reason_code<>'AIRCON_NOT_ONSITE' THEN
    RAISE EXCEPTION 'R2_F_F_CASE_C_ONLINE_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-10','2026-08','onsite',NULL,'Regus办公室',2,17000,330
  );
  IF v_calc.aircon_billable_hours<>0 OR v_calc.aircon_fee_jpy<>0
     OR v_calc.fee_block_reason_code<>'AIRCON_WEEKDAY' THEN
    RAISE EXCEPTION 'R2_F_F_CASE_D_WEEKDAY_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','onsite',NULL,'Regus办公室',2.5,17000,330
  );
  IF v_calc.aircon_billable_hours<>2 OR v_calc.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F_CASE_E_WHOLE_HOUR_FLOOR_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2026-08-08','2026-08','onsite',NULL,'Regus办公室',0.5,4250,330
  );
  IF v_calc.aircon_billable_hours<>0 OR v_calc.aircon_fee_jpy<>0
     OR v_calc.fee_block_reason_code<>'AIRCON_NO_WHOLE_HOUR' THEN
    RAISE EXCEPTION 'R2_F_F_CASE_E_SUBHOUR_FAILED';
  END IF;
  BEGIN
    PERFORM * FROM public.school_r2_e_calculate_planned_aircon_fee(
      DATE '2026-08-08','2026-08',2,17000,330
    );
    RAISE EXCEPTION 'R2_F_F_OLD_CALCULATOR_BYPASS_NOT_BLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F_OLD_CALCULATOR_BYPASS_NOT_BLOCKED' THEN RAISE; END IF;
    IF position('R2_F_F_AIRCON_VENUE_CONTEXT_REQUIRED' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  INSERT INTO r2_f_f_results VALUES
    ('policy_matrix',true,'office/nonbillable/online/weekday/2.5h/0.5h and legacy bypass');

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES
    (v_student_a,'codex-r2ff-a','codex-test R2-F-F A','codex-test R2-F-F A',
     v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-f'),
    (v_student_b,'codex-r2ff-b','codex-test R2-F-F B','codex-test R2-F-F B',
     v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-f');

  SELECT created.id INTO STRICT v_plan_a
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2032-08-07',v_student_a,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',1,
    'codex-test R2-F-F planned A','codex-test r2-f-f',
    'onsite','Regus办公室',330
  ) created;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan_a;
  IF v_row.fee_calculation_version<>'planned_weekend_venue_whole_hour_aircon_v2'
     OR v_row.aircon_billable_hours_snapshot<>2 OR v_row.aircon_fee_jpy<>660
     OR v_row.lesson_fee<>20000 OR v_row.lesson_total_fee_jpy<>20660 THEN
    RAISE EXCEPTION 'R2_F_F_WRITER_V2_BUNDLE_FAILED';
  END IF;

  -- Actual overage never participates in the planned aircon calculation.
  SELECT actual.lesson_id INTO STRICT v_actual_a
  FROM public.school_create_actual_lesson_from_planned(
    v_plan_a,(clock_timestamp() AT TIME ZONE 'Asia/Tokyo')::date,
    '15:00','17:15',2.25,10000,NULL,1,
    'codex-test R2-F-F actual overage','codex-test r2-f-f'
  ) actual;
  SELECT * INTO STRICT v_actual FROM public.school_lesson_records WHERE id=v_actual_a;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan_a;
  IF num_nonnulls(v_actual.base_lesson_fee_jpy,v_actual.aircon_charge_status,
       v_actual.aircon_unit_price_jpy_snapshot,v_actual.aircon_billable_hours_snapshot,
       v_actual.aircon_fee_jpy,v_actual.fee_calculation_version,
       v_actual.lesson_total_fee_jpy)<>0
     OR v_actual.student_duration_overage_minutes<>15
     OR v_actual.student_duration_overage_fee_jpy<>2500
     OR v_row.aircon_billable_hours_snapshot<>2 OR v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F_ACTUAL_OVERAGE_ISOLATION_FAILED';
  END IF;
  INSERT INTO r2_f_f_results VALUES
    ('actual_overage_isolation',true,'2h planned stays JPY660; 2.25h actual freezes only 15min/JPY2500 overage');

  SELECT * INTO STRICT v_preview_before
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2032-08',0.05
  );
  IF v_preview_before.feature_state<>'enabled'
     OR v_preview_before.generate_feature_state<>'enabled'
     OR v_preview_before.candidate_count<>1 OR v_preview_before.total_lesson_count<>1
     OR v_preview_before.total_duration_hours<>2
     OR v_preview_before.total_base_lesson_fee_jpy<>20000
     OR v_preview_before.total_aircon_fee_jpy<>660
     OR v_preview_before.total_fee_jpy<>20660
     OR v_preview_before.billing_amount_cny<>1033
     OR v_preview_before.candidates->0->>'fee_policy_version'
          <>'planned_weekend_venue_whole_hour_aircon_v2'
     OR (v_preview_before.candidates->0->>'aircon_billable_hours')::numeric<>2
     OR v_preview_before.candidates->0->>'lesson_venue_code'<>'Regus办公室' THEN
    RAISE EXCEPTION 'R2_F_F_PREVIEW_V2_CONTRACT_FAILED';
  END IF;

  UPDATE public.school_lesson_records
  SET lesson_venue='Regus公共区'
  WHERE id=v_plan_a;
  SELECT * INTO STRICT v_preview_public
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2032-08',0.05
  );
  IF v_preview_public.total_aircon_fee_jpy<>0
     OR v_preview_public.total_fee_jpy<>20000
     OR v_preview_public.generation_manifest_sha256=
          v_preview_before.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F_VENUE_RECALC_OR_MANIFEST_FAILED';
  END IF;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2032-08',0.05,
      v_preview_before.generation_manifest_sha256,NULL,NULL
    );
    RAISE EXCEPTION 'R2_F_F_STALE_MANIFEST_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F_STALE_MANIFEST_NOT_REJECTED' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  UPDATE public.school_lesson_records
  SET lesson_venue='Regus办公室'
  WHERE id=v_plan_a;
  SELECT * INTO STRICT v_preview_final
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_a,'2032-08',0.05
  );
  IF v_preview_final.total_aircon_fee_jpy<>660
     OR v_preview_final.generation_manifest_sha256<>
          v_preview_before.generation_manifest_sha256
     OR v_preview_final.generation_manifest_sha256=
          v_preview_public.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F_MANIFEST_REFRESH_FAILED';
  END IF;
  INSERT INTO r2_f_f_results VALUES
    ('venue_manifest',true,'venue change recalculates fee/hash; stale manifest rejects; restored facts restore stable manifest');

  SELECT * INTO STRICT v_generated
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_a,'2032-08',0.05,v_preview_final.generation_manifest_sha256,
    'codex-test r2-f-f atomic',NULL
  );
  SELECT * INTO STRICT v_bill FROM public.school_student_tuition_bills
  WHERE id=v_generated.tuition_bill_id;
  SELECT * INTO STRICT v_income FROM public.school_income_records
  WHERE id=v_generated.income_record_id;
  SELECT * INTO STRICT v_identity FROM public.school_student_tuition_billing_identities
  WHERE id=v_generated.billing_identity_id;
  SELECT * INTO STRICT v_relation FROM public.school_student_tuition_bill_lessons
  WHERE tuition_bill_id=v_generated.tuition_bill_id;
  IF v_generated.total_aircon_fee_jpy<>660 OR v_generated.total_fee_jpy<>20660
     OR v_bill.bill_amount_jpy<>20660 OR v_income.amount<>20660
     OR v_relation.base_lesson_fee_jpy_snapshot<>20000
     OR v_relation.aircon_unit_price_jpy_snapshot<>330
     OR v_relation.aircon_billable_hours_snapshot<>2
     OR v_relation.aircon_fee_jpy_snapshot<>660
     OR v_relation.lesson_fee_jpy_snapshot<>20660
     OR v_relation.fee_calculation_version_snapshot
          <>'planned_weekend_venue_whole_hour_aircon_v2'
     OR v_bill.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_income.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_identity.evidence->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_relation.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F_ATOMIC_FOUR_OBJECT_AIRCON_MISMATCH';
  END IF;
  PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  SELECT * INTO STRICT v_idempotent
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student_a,'2032-08',0.05,v_preview_final.generation_manifest_sha256,
    'ignored idempotent note',NULL
  );
  IF NOT v_idempotent.idempotent
     OR v_idempotent.tuition_bill_id<>v_generated.tuition_bill_id
     OR v_idempotent.income_record_id<>v_generated.income_record_id THEN
    RAISE EXCEPTION 'R2_F_F_ATOMIC_IDEMPOTENCY_FAILED';
  END IF;
  INSERT INTO r2_f_f_results VALUES
    ('atomic_consistency',true,'bill/relation/identity/income v2 fee and manifest agree; idempotency returns same IDs');

  SELECT created.id INTO STRICT v_plan_b
  FROM public.school_create_planned_lesson_record_with_venue(
    DATE '2032-08-14',v_student_b,v_fixture.teacher_id,v_fixture.subject_id,
    v_fixture.business_entity_id,'15:00','17:00',0,10000,NULL,'planned',1,
    'codex-test R2-F-F planned B','codex-test r2-f-f',
    'onsite','Regus办公室',330
  ) created;
  SELECT * INTO STRICT v_preview_b
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student_b,'2032-08',0.05
  );
  v_failed:=false;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student_b,'2032-08',0.05,v_preview_b.generation_manifest_sha256,
      'codex-test injected failure','after_relations'
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS' IN SQLERRM)=0 THEN RAISE; END IF;
    v_failed:=true;
  END;
  IF NOT v_failed
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_billing_identities
                WHERE student_id=v_student_b AND billing_month='2032-08')
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bills
                WHERE student_id=v_student_b AND billing_month='2032-08')
     OR EXISTS (SELECT 1 FROM public.school_income_records
                WHERE student_id=v_student_b AND settlement_month='2032-08')
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
                JOIN public.school_student_tuition_bills bill
                  ON bill.id=relation.tuition_bill_id
                WHERE bill.student_id=v_student_b AND bill.billing_month='2032-08') THEN
    RAISE EXCEPTION 'R2_F_F_ATOMIC_FAILURE_RESIDUE';
  END IF;
  INSERT INTO r2_f_f_results VALUES
    ('atomic_failure',true,'injected failure after relations leaves no four-object residue');

  RAISE NOTICE 'R2_F_F_TEST_IDS student_a=%,student_b=%,planned_a=%,actual_a=%,planned_b=%,bill=%,identity=%,income=%',
    v_student_a,v_student_b,v_plan_a,v_actual_a,v_plan_b,
    v_generated.tuition_bill_id,v_generated.billing_identity_id,v_generated.income_record_id;
END
$tests$;

SELECT test_name,passed,detail FROM r2_f_f_results ORDER BY test_name;
\echo 'R2_F_F_ROLLBACK_TEST_ROLLBACK'
ROLLBACK;

BEGIN READ ONLY;
DO $residual$
BEGIN
  IF EXISTS (SELECT 1 FROM public.school_students
      WHERE id IN ('f2ff0000-0000-4000-8000-00000000a001',
                   'f2ff0000-0000-4000-8000-00000000a002'))
     OR EXISTS (SELECT 1 FROM public.school_lesson_records
       WHERE note='codex-test r2-f-f')
     OR EXISTS (SELECT 1 FROM public.school_tuition_atomic_writer_context) THEN
    RAISE EXCEPTION 'R2_F_F_ROLLBACK_TEST_RESIDUE';
  END IF;
  IF (SELECT count(*)<>9 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'0f0323b79e7ff1c47ff6b90c75477a2d'
      FROM public.school_student_tuition_bills t)
     OR (SELECT count(*)<>42 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'2a4897b752f272b1f192045418b4940c'
      FROM public.school_income_records t)
     OR (SELECT count(*)<>121 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'285172fedeb923c67ea9a179480d8692'
      FROM public.school_student_tuition_bill_lessons t)
     OR (SELECT count(*)<>7 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'4d91a5a1074f90389822fc367a7e5467'
      FROM public.school_student_tuition_billing_identities t)
     OR (SELECT count(*)<>17 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'1d7328654f6488952dba20640072c3e2'
      FROM public.school_student_monthly_settlements t)
     OR (SELECT count(*)<>659 OR md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY t.id::text),''))<>'9ce7c36283cfa51f8b2a334801f646dd'
      FROM public.school_lesson_records t) THEN
    RAISE EXCEPTION 'R2_F_F_ROLLBACK_HISTORY_FINGERPRINT_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='enabled')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F_ROLLBACK_GATE_DRIFT';
  END IF;
END
$residual$;
SELECT true AS rollback_tests_pass,0 AS persisted_fixture_rows;
ROLLBACK;
\echo 'R2_F_F_ROLLBACK_TEST_COMPLETE'
