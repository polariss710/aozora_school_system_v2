-- School V2 R2-F-F1 rollback-only planned edit/aircon/atomic acceptance.
-- All fixture writes use fixed codex-test IDs and end in ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';

CREATE TEMPORARY TABLE r2_f_f1_results(
  test_name text PRIMARY KEY,passed boolean NOT NULL,detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_student constant uuid:='f2f10000-0000-4000-8000-00000000a001';
  v_plan constant uuid:='f2f10000-0000-4000-8000-00000000b001';
  v_row public.school_lesson_records%ROWTYPE;
  v_calc record;
  v_preview_office record;
  v_preview_public record;
  v_preview_final record;
  v_generated record;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_relation public.school_student_tuition_bill_lessons%ROWTYPE;
BEGIN
  IF EXISTS(SELECT 1 FROM public.school_students WHERE id=v_student)
     OR EXISTS(SELECT 1 FROM public.school_lesson_records WHERE id=v_plan) THEN
    RAISE EXCEPTION 'R2_F_F1_FIXTURE_ID_COLLISION';
  END IF;

  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  JOIN public.school_students student ON student.id=lesson.student_id
  WHERE lesson.app_type='school' AND lesson.lesson_type='planned'
    AND lesson.teacher_id IS NOT NULL AND lesson.subject_id IS NOT NULL
    AND lesson.business_entity_id IS NOT NULL
    AND student.business_entity_id IS NOT DISTINCT FROM lesson.business_entity_id
  ORDER BY lesson.id LIMIT 1;

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES (
    v_student,'codex-r2ff1','codex-test R2-F-F1','codex-test R2-F-F1',
    v_fixture.business_entity_id,'active','school',0.05,0,'codex-test r2-f-f1'
  );

  INSERT INTO public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,aircon_unit_price_jpy_snapshot
  ) VALUES (
    v_plan,'planned',DATE '2032-08-08','2032-08',v_student,
    v_fixture.teacher_id,v_fixture.subject_id,v_fixture.business_entity_id,
    '15:00','17:00',2,'codex-test R2-F-F1 planned','planned',true,
    'codex-test r2-f-f1','school',8500,17000,1,'onsite','Regus办公室',330
  );

  -- Case 1: simulate a pre-aircon legacy NULL bundle, then use the exact UI RPC.
  ALTER TABLE public.school_lesson_records
    DISABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  UPDATE public.school_lesson_records
  SET base_lesson_fee_jpy=NULL,aircon_charge_status=NULL,aircon_rate_id=NULL,
      aircon_unit_price_jpy_snapshot=NULL,aircon_billable_hours_snapshot=NULL,
      aircon_fee_jpy=NULL,aircon_calculated_at=NULL,
      fee_calculation_version=NULL,fee_block_reason_code=NULL,
      fee_components_frozen_at=NULL,lesson_total_fee_jpy=NULL
  WHERE id=v_plan;
  ALTER TABLE public.school_lesson_records
    ENABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test NULL bundle','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.fee_calculation_version<>'planned_weekend_venue_whole_hour_aircon_v2'
     OR v_row.aircon_unit_price_jpy_snapshot<>330
     OR v_row.aircon_billable_hours_snapshot<>2
     OR v_row.aircon_fee_jpy<>660 OR v_row.lesson_total_fee_jpy<>17660 THEN
    RAISE EXCEPTION 'R2_F_F1_NULL_BUNDLE_RECALC_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('legacy_null_bundle',true,'exact edit RPC recalculates NULL bundle to JPY660');

  -- Case 2: a complete valid v2 zero-rate bundle must recalculate to a fee.
  ALTER TABLE public.school_lesson_records
    DISABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  UPDATE public.school_lesson_records
  SET base_lesson_fee_jpy=17000,aircon_charge_status='configured_zero',
      aircon_rate_id=NULL,aircon_unit_price_jpy_snapshot=0,
      aircon_billable_hours_snapshot=2,aircon_fee_jpy=0,
      aircon_calculated_at=statement_timestamp(),
      fee_calculation_version='planned_weekend_venue_whole_hour_aircon_v2',
      fee_block_reason_code='AIRCON_RATE_ZERO',fee_components_frozen_at=NULL,
      lesson_total_fee_jpy=17000
  WHERE id=v_plan;
  ALTER TABLE public.school_lesson_records
    ENABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test zero bundle','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>660 OR v_row.lesson_total_fee_jpy<>17660 THEN
    RAISE EXCEPTION 'R2_F_F1_ZERO_BUNDLE_RECALC_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('valid_zero_bundle',true,'exact edit RPC recalculates complete v2 zero-rate bundle to JPY660');

  -- A complete valid v1 zero-rate bundle must also migrate through v2 authority.
  ALTER TABLE public.school_lesson_records
    DISABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  UPDATE public.school_lesson_records
  SET base_lesson_fee_jpy=17000,aircon_charge_status='configured_zero',
      aircon_rate_id=NULL,aircon_unit_price_jpy_snapshot=0,
      aircon_billable_hours_snapshot=2,aircon_fee_jpy=0,
      aircon_calculated_at=statement_timestamp(),
      fee_calculation_version='planned_weekend_aircon_v1',
      fee_block_reason_code='AIRCON_RATE_ZERO',fee_components_frozen_at=NULL,
      lesson_total_fee_jpy=17000
  WHERE id=v_plan;
  ALTER TABLE public.school_lesson_records
    ENABLE TRIGGER trg_school_lesson_r2_e_planned_aircon;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test v1 zero bundle','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.fee_calculation_version<>'planned_weekend_venue_whole_hour_aircon_v2'
     OR v_row.aircon_fee_jpy<>660 OR v_row.lesson_total_fee_jpy<>17660 THEN
    RAISE EXCEPTION 'R2_F_F1_V1_ZERO_BUNDLE_RECALC_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('valid_v1_zero_bundle',true,'complete v1 zero-rate bundle migrates to v2 JPY660');

  -- Cases 3/6: date changes recalculate both directions.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-02',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test weekday','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>0 OR v_row.lesson_total_fee_jpy<>17000
     OR v_row.fee_block_reason_code<>'AIRCON_WEEKDAY' THEN
    RAISE EXCEPTION 'R2_F_F1_WEEKEND_TO_WEEKDAY_FAILED';
  END IF;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test weekend','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F1_WEEKDAY_TO_WEEKEND_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('date_recalculation',true,'weekday zero and weekend JPY660');

  -- Cases 4/7: venue changes recalculate both directions.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test public venue','codex-test r2-f-f1',
    'onsite','Regus公共区',330
  ) updated;
  IF v_row.aircon_fee_jpy<>0 OR v_row.fee_block_reason_code<>'AIRCON_VENUE_NOT_ELIGIBLE' THEN
    RAISE EXCEPTION 'R2_F_F1_OFFICE_TO_PUBLIC_FAILED';
  END IF;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test office venue','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F1_PUBLIC_TO_OFFICE_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('venue_recalculation',true,'public zero and office JPY660');

  -- Delivery mode changes use the same authoritative calculator.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test online mode','codex-test r2-f-f1',
    'online','Zoom',330
  ) updated;
  IF v_row.aircon_fee_jpy<>0 OR v_row.fee_block_reason_code<>'AIRCON_NOT_ONSITE' THEN
    RAISE EXCEPTION 'R2_F_F1_ONSITE_TO_ONLINE_FAILED';
  END IF;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test onsite mode','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F1_ONLINE_TO_ONSITE_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('mode_recalculation',true,'online zero and onsite office JPY660');

  -- Case 5: the saved rate participates on every edit.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test zero rate','codex-test r2-f-f1',
    'onsite','Regus办公室',0
  ) updated;
  IF v_row.aircon_fee_jpy<>0 OR v_row.lesson_total_fee_jpy<>17000 THEN
    RAISE EXCEPTION 'R2_F_F1_RATE_TO_ZERO_FAILED';
  END IF;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test rate 330','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F1_ZERO_TO_330_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('rate_recalculation',true,'rate zero then 330 recalculates');

  -- Case 8: writer-supported duration changes recalculate; the pure policy
  -- still proves whole-hour floor for a fractional duration.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','18:00',3,8500,NULL,
    'planned',true,1,'codex-test 3 hours','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.lesson_fee<>25500 OR v_row.aircon_billable_hours_snapshot<>3
     OR v_row.aircon_fee_jpy<>990 OR v_row.lesson_total_fee_jpy<>26490 THEN
    RAISE EXCEPTION 'R2_F_F1_WRITER_DURATION_RECALC_FAILED';
  END IF;
  SELECT * INTO STRICT v_calc
  FROM public.school_r2_e_calculate_planned_aircon_fee(
    DATE '2032-08-08','2032-08','onsite',NULL,'Regus办公室',2.5,21250,330
  );
  IF v_calc.aircon_billable_hours<>2 OR v_calc.aircon_fee_jpy<>660
     OR v_calc.lesson_total_fee_jpy<>21910 THEN
    RAISE EXCEPTION 'R2_F_F1_DURATION_FLOOR_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('duration_recalculation',true,'writer 3h is JPY990; pure 2.5h policy floors to JPY660');

  -- Restore the canonical 2h office fact and prove preview/manifest changes.
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test manifest office','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  SELECT * INTO STRICT v_preview_office
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student,'2032-08',0.05
  );
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test manifest public','codex-test r2-f-f1',
    'onsite','Regus公共区',330
  ) updated;
  SELECT * INTO STRICT v_preview_public
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student,'2032-08',0.05
  );
  IF v_preview_office.total_aircon_fee_jpy<>660
     OR v_preview_public.total_aircon_fee_jpy<>0
     OR v_preview_office.generation_manifest_sha256=v_preview_public.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F1_PREVIEW_MANIFEST_CHANGE_FAILED';
  END IF;
  BEGIN
    PERFORM * FROM public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2032-08',0.05,v_preview_office.generation_manifest_sha256,
      'codex-test stale manifest',NULL
    );
    RAISE EXCEPTION 'R2_F_F1_STALE_MANIFEST_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F1_STALE_MANIFEST_NOT_REJECTED' THEN RAISE; END IF;
    IF position('R2_F_B_STALE_GENERATION_MANIFEST' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
    'planned',true,1,'codex-test manifest final','codex-test r2-f-f1',
    'onsite','Regus办公室',330
  ) updated;
  SELECT * INTO STRICT v_preview_final
  FROM public.school_get_student_tuition_validation_preview_details(
    v_student,'2032-08',0.05
  );
  IF v_preview_final.total_aircon_fee_jpy<>660
     OR v_preview_final.total_fee_jpy<>17660
     OR v_preview_final.generation_manifest_sha256=v_preview_public.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F1_PREVIEW_FINAL_FAILED';
  END IF;
  INSERT INTO r2_f_f1_results VALUES
    ('preview_manifest',true,'candidate fee and manifest follow authoritative venue changes');

  -- Cases 9/10: rollback-only atomic four objects freeze the same fee; billed edit rejects.
  SELECT * INTO STRICT v_generated
  FROM public.school_generate_student_tuition_bill_atomic_core(
    v_student,'2032-08',0.05,v_preview_final.generation_manifest_sha256,
    'codex-test r2-f-f1 atomic',NULL
  );
  SELECT * INTO STRICT v_bill FROM public.school_student_tuition_bills
  WHERE id=v_generated.tuition_bill_id;
  SELECT * INTO STRICT v_income FROM public.school_income_records
  WHERE id=v_generated.income_record_id;
  SELECT * INTO STRICT v_identity FROM public.school_student_tuition_billing_identities
  WHERE id=v_generated.billing_identity_id;
  SELECT * INTO STRICT v_relation FROM public.school_student_tuition_bill_lessons
  WHERE tuition_bill_id=v_generated.tuition_bill_id;
  IF v_generated.total_aircon_fee_jpy<>660 OR v_generated.total_fee_jpy<>17660
     OR v_bill.bill_amount_jpy<>17660 OR v_income.amount<>17660
     OR v_relation.aircon_unit_price_jpy_snapshot<>330
     OR v_relation.aircon_billable_hours_snapshot<>2
     OR v_relation.aircon_fee_jpy_snapshot<>660
     OR v_relation.lesson_fee_jpy_snapshot<>17660
     OR v_relation.fee_calculation_version_snapshot<>'planned_weekend_venue_whole_hour_aircon_v2'
     OR v_bill.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_income.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_identity.evidence->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256
     OR v_relation.source_snapshot->>'generation_manifest_sha256'
          <>v_preview_final.generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_F1_ATOMIC_FOUR_OBJECT_MISMATCH';
  END IF;
  PERFORM public.school_validate_tuition_identity_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_plan,v_row.updated_at,DATE '2032-08-08',v_student,v_row.teacher_id,
      v_row.subject_id,v_row.business_entity_id,'15:00','17:00',2,8500,NULL,
      'planned',true,1,'codex-test billed mutation','codex-test r2-f-f1',
      'onsite','Regus办公室',331
    );
    RAISE EXCEPTION 'R2_F_F1_BILLED_EDIT_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F1_BILLED_EDIT_NOT_REJECTED' THEN RAISE; END IF;
    IF position('R2_F_E_BILLED_PLANNED_CHARGE_FACT_IMMUTABLE' IN SQLERRM)=0 THEN
      RAISE;
    END IF;
  END;
  INSERT INTO r2_f_f1_results VALUES
    ('atomic_and_billed_guard',true,'four objects agree; billed rate mutation rejected');
END
$tests$;

TABLE r2_f_f1_results ORDER BY test_name;
ROLLBACK;

SELECT
  (SELECT count(*) FROM public.school_students
   WHERE id='f2f10000-0000-4000-8000-00000000a001') AS student_residue,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE id='f2f10000-0000-4000-8000-00000000b001') AS lesson_residue,
  (SELECT count(*) FROM public.school_student_tuition_billing_identities
   WHERE student_id='f2f10000-0000-4000-8000-00000000a001') AS identity_residue,
  (SELECT count(*) FROM public.school_student_tuition_bills
   WHERE student_id='f2f10000-0000-4000-8000-00000000a001') AS bill_residue;
