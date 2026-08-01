-- School V2 R2-F-F2 rollback-only billing-week/reader acceptance.
-- All fixture writes use fixed codex-test IDs and end in ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';

CREATE TEMPORARY TABLE r2_f_f2_results(
  test_name text PRIMARY KEY,passed boolean NOT NULL,detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_target public.school_lesson_records%ROWTYPE;
  v_student constant uuid:='f2f20000-0000-4000-8000-00000000a001';
  v_plan constant uuid:='f2f20000-0000-4000-8000-00000000b001';
  v_legacy constant uuid:='f2f20000-0000-4000-8000-00000000b002';
  v_row public.school_lesson_records%ROWTYPE;
  v_stats record;
BEGIN
  IF EXISTS(SELECT 1 FROM public.school_students WHERE id=v_student)
     OR EXISTS(SELECT 1 FROM public.school_lesson_records
               WHERE id IN (v_plan,v_legacy)) THEN
    RAISE EXCEPTION 'R2_F_F2_FIXTURE_ID_COLLISION';
  END IF;

  SELECT lesson.* INTO STRICT v_target
  FROM public.school_lesson_records lesson
  WHERE lesson.id='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES (
    v_student,'codex-r2ff2','codex-test R2-F-F2','codex-test R2-F-F2',
    v_target.business_entity_id,'active','school',0.05,0,'codex-test r2-f-f2'
  );

  INSERT INTO public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,aircon_unit_price_jpy_snapshot,
    import_source
  ) VALUES (
    v_plan,'planned',DATE '2032-08-30','2032-08',v_student,
    v_target.teacher_id,v_target.subject_id,v_target.business_entity_id,
    '14:00','16:00',2,'codex-test R2-F-F2 canonical','planned',true,
    'codex-test r2-f-f2','school',8500,17000,1,'onsite','Regus办公室',330,
    'codex-test r2-f-f2 single create'
  );

  SELECT * INTO STRICT v_row
  FROM public.school_lesson_records WHERE id=v_plan;
  IF v_row.billing_week_start_date<>DATE '2032-08-30'
     OR v_row.billing_month<>'2032-08'
     OR v_row.student_settlement_month<>'2032-08'
     OR v_row.aircon_fee_jpy<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_CREATE_ATTRIBUTION_FAILED';
  END IF;
  INSERT INTO r2_f_f2_results VALUES
    ('create_canonical_week',true,'2032-08-30 week/month/student month frozen');

  SELECT updated.* INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    v_plan,v_row.updated_at,DATE '2032-09-05',v_student,v_row.teacher_id,
    v_row.subject_id,v_row.business_entity_id,'14:00','16:00',2,8500,NULL,
    'planned',true,1,'codex-test R2-F-F2 Sunday','codex-test r2-f-f2',
    'onsite','Regus办公室',330
  ) updated;
  IF v_row.lesson_date<>DATE '2032-09-05'
     OR v_row.year_month<>'2032-09'
     OR v_row.billing_week_start_date<>DATE '2032-08-30'
     OR v_row.billing_month<>'2032-08'
     OR v_row.student_settlement_month<>'2032-08'
     OR v_row.aircon_unit_price_jpy_snapshot<>330
     OR v_row.aircon_billable_hours_snapshot<>2
     OR v_row.aircon_fee_jpy<>660
     OR v_row.lesson_total_fee_jpy<>17660 THEN
    RAISE EXCEPTION 'R2_F_F2_WITHIN_WEEK_EDIT_FAILED';
  END IF;
  INSERT INTO r2_f_f2_results VALUES
    ('cross_month_within_week_edit',true,'date moved to Sunday; attribution stayed August; aircon=660');

  IF (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2032-08',NULL
      ) lesson WHERE lesson.id=v_plan)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2032-08',DATE '2032-08-30'
      ) lesson WHERE lesson.id=v_plan)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2032-09',NULL
      ) lesson WHERE lesson.id=v_plan)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_AUTHORITATIVE_READER_FAILED';
  END IF;
  SELECT * INTO STRICT v_stats
  FROM public.school_get_lesson_management_stats_filtered(
    '2032-08',v_student,NULL,NULL,NULL,NULL,v_target.business_entity_id,
    NULL,NULL,DATE '2032-08-30'
  );
  IF v_stats.planned_hours<>2 OR v_stats.planned_fee_jpy<>17000
     OR v_stats.record_count<>1 THEN
    RAISE EXCEPTION 'R2_F_F2_AUTHORITATIVE_STATS_FAILED';
  END IF;
  INSERT INTO r2_f_f2_results VALUES
    ('month_week_reader_and_stats',true,'August month/week includes; September excludes; stats agree');

  BEGIN
    PERFORM * FROM public.school_update_lesson_record_guarded_with_venue(
      v_plan,v_row.updated_at,DATE '2032-09-06',v_student,v_row.teacher_id,
      v_row.subject_id,v_row.business_entity_id,'14:00','16:00',2,8500,NULL,
      'planned',true,1,'codex-test outside week','codex-test r2-f-f2',
      'onsite','Regus办公室',330
    );
    RAISE EXCEPTION 'R2_F_F2_OUTSIDE_WEEK_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F2_OUTSIDE_WEEK_NOT_REJECTED' THEN RAISE; END IF;
    IF position('PLANNED_DATE_OUTSIDE_BILLING_WEEK' IN SQLERRM)=0 THEN
      RAISE;
    END IF;
  END;
  SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan;
  IF v_row.lesson_date<>DATE '2032-09-05'
     OR v_row.aircon_fee_jpy<>660 THEN
    RAISE EXCEPTION 'R2_F_F2_OUTSIDE_WEEK_FAILURE_LEFT_MUTATION';
  END IF;
  INSERT INTO r2_f_f2_results VALUES
    ('outside_week_rejected',true,'next Monday rejected and RPC subtransaction left no mutation');

  BEGIN
    UPDATE public.school_lesson_records
    SET student_settlement_month='2032-09'
    WHERE id=v_plan;
    RAISE EXCEPTION 'R2_F_F2_ATTRIBUTION_MUTATION_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F2_ATTRIBUTION_MUTATION_NOT_REJECTED' THEN RAISE; END IF;
    IF position('PLANNED_BILLING_ATTRIBUTION_IMMUTABLE' IN SQLERRM)=0 THEN
      RAISE;
    END IF;
  END;
  INSERT INTO r2_f_f2_results VALUES
    ('attribution_immutable',true,'direct student-month mutation rejected by table trigger');

  ALTER TABLE public.school_lesson_records
    DISABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
  INSERT INTO public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,aircon_unit_price_jpy_snapshot,
    import_source
  ) VALUES (
    v_legacy,'planned',DATE '2032-08-30','2032-08',v_student,
    v_target.teacher_id,v_target.subject_id,v_target.business_entity_id,
    '10:00','12:00',2,'codex-test R2-F-F2 legacy','planned',true,
    'codex-test r2-f-f2 legacy','school',8500,17000,1,
    'onsite','Regus办公室',330,'codex-test r2-f-f2 legacy'
  );
  ALTER TABLE public.school_lesson_records
    ENABLE TRIGGER trg_school_lesson_r1d_f1_planned_attribution;
  BEGIN
    UPDATE public.school_lesson_records
    SET lesson_date=DATE '2032-08-31'
    WHERE id=v_legacy;
    RAISE EXCEPTION 'R2_F_F2_LEGACY_DATE_EDIT_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F2_LEGACY_DATE_EDIT_NOT_REJECTED' THEN RAISE; END IF;
    IF position('PLANNED_BILLING_ATTRIBUTION_REQUIRED' IN SQLERRM)=0 THEN
      RAISE;
    END IF;
  END;
  INSERT INTO r2_f_f2_results VALUES
    ('legacy_date_edit_fail_closed',true,'all-null attribution cannot be silently derived from edited date');

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records lesson
    WHERE lesson.id=v_plan AND (
      lesson.billing_month<>to_char(lesson.billing_week_start_date,'YYYY-MM')
      OR lesson.student_settlement_month<>lesson.billing_month
      OR lesson.lesson_date NOT BETWEEN lesson.billing_week_start_date
                                    AND lesson.billing_week_start_date+6
    )
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_FINAL_FIXTURE_INVARIANT_FAILED';
  END IF;
  INSERT INTO r2_f_f2_results VALUES
    ('final_fixture_invariant',true,'month/week/student month/date remain consistent');
END
$tests$;

TABLE r2_f_f2_results ORDER BY test_name;
ROLLBACK;

SELECT
  (SELECT count(*) FROM public.school_students
   WHERE id='f2f20000-0000-4000-8000-00000000a001') AS student_residue,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE id IN (
     'f2f20000-0000-4000-8000-00000000b001',
     'f2f20000-0000-4000-8000-00000000b002'
   )) AS lesson_residue;
