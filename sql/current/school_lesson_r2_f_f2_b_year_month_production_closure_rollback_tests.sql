-- School V2 R2-F-F2-B rollback-only production-path acceptance.
-- Fixed codex-test IDs only. Every business write is rolled back.
\set ON_ERROR_STOP on
\pset pager off

BEGIN;

DO $deployed_definition$
BEGIN
  IF position('coalesce(actual.student_settlement_month,actual.year_month)' IN
       pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))>0
     OR position('school_resolve_r1d_e_c_lesson_student_month(actual.id)' IN
       pg_get_functiondef(
       'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
     ))=0
     OR position('m.year_month = c.year_month' IN pg_get_functiondef(
       'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
     ))>0
     OR position('s.year_month = c.year_month' IN pg_get_functiondef(
       'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
     ))>0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_ACTUAL_STATS_RESOLVER_NOT_DEPLOYED';
  END IF;
END
$deployed_definition$;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';

CREATE TEMPORARY TABLE r2_f_f2_b_results(
  test_name text PRIMARY KEY,passed boolean NOT NULL,detail text NOT NULL
) ON COMMIT DROP;

DO $tests$
DECLARE
  v_fixture public.school_lesson_records%ROWTYPE;
  v_student constant uuid:='f2fb0000-0000-4000-8000-00000000a001';
  v_locked_student constant uuid:='f2fb0000-0000-4000-8000-00000000a002';
  v_plan_ids uuid[]:=ARRAY[]::uuid[];
  v_plan uuid;
  v_actual uuid;
  v_batch uuid;
  v_import uuid;
  v_row public.school_lesson_records%ROWTYPE;
  v_index integer;
BEGIN
  IF EXISTS(SELECT 1 FROM public.school_students
            WHERE id IN (v_student,v_locked_student))
     OR EXISTS(SELECT 1 FROM public.school_lesson_records
               WHERE id::text LIKE 'f2fb0000-0000-4000-8000-%') THEN
    RAISE EXCEPTION 'R2_F_F2_B_FIXTURE_ID_COLLISION';
  END IF;

  SELECT lesson.* INTO STRICT v_fixture
  FROM public.school_lesson_records lesson
  WHERE lesson.id='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';

  INSERT INTO public.school_students(
    id,student_code,name,display_name,business_entity_id,status,app_type,
    preset_exchange_rate,previous_balance_cny,note
  ) VALUES
    (v_student,'codex-r2ff2b-a','codex-test R2-F-F2-B A',
     'codex-test R2-F-F2-B A',v_fixture.business_entity_id,'active','school',
     0.05,0,'codex-test r2-f-f2-b'),
    (v_locked_student,'codex-r2ff2b-b','codex-test R2-F-F2-B B',
     'codex-test R2-F-F2-B B',v_fixture.business_entity_id,'active','school',
     0.05,0,'codex-test r2-f-f2-b');

  -- Wrong raw date month (September) is locked. Canonical August is open.
  INSERT INTO public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,carryover_amount_cny,
    settlement_status,locked_at,note
  ) VALUES (
    'f2fb0000-0000-4000-8000-00000000c001',v_student,'2020-09',
    v_fixture.business_entity_id,0,'locked',now(),
    'codex-test wrong raw date month lock'
  );

  -- Create seven cross-month canonical planned sources before testing writers.
  FOR v_index IN 1..7 LOOP
    SELECT created.lesson_id INTO STRICT v_plan
    FROM public.school_create_planned_lesson_record(
      DATE '2020-09-06',v_student,v_fixture.teacher_id,v_fixture.subject_id,
      v_fixture.business_entity_id,
      (ARRAY['08:00','10:00','12:00','14:00','16:00','18:00','20:00'])[v_index],
      (ARRAY['10:00','12:00','14:00','16:00','18:00','20:00','22:00'])[v_index],
      0,8500,NULL,CASE WHEN v_index=4 THEN 'pending_makeup' ELSE 'planned' END,
      v_index,'codex-test R2-F-F2-B cross-month source',
      'codex-test r2-f-f2-b'
    ) created;
    v_plan_ids:=array_append(v_plan_ids,v_plan);
    SELECT * INTO STRICT v_row FROM public.school_lesson_records WHERE id=v_plan;
    IF v_row.year_month<>'2020-09' OR v_row.billing_month<>'2020-08'
       OR v_row.student_settlement_month<>'2020-08'
       OR v_row.billing_week_start_date<>DATE '2020-08-31' THEN
      RAISE EXCEPTION 'R2_F_F2_B_SINGLE_CREATE_ATTRIBUTION_FAILED';
    END IF;
  END LOOP;
  INSERT INTO r2_f_f2_b_results VALUES
    ('single_writer_lock_month',true,
     'September locked; seven September-6 planned rows created under canonical August');

  SELECT actual.lesson_id INTO STRICT v_actual
  FROM public.school_create_actual_lesson_from_planned(
    v_plan_ids[1],DATE '2020-09-06','08:00','10:00',2,8500,NULL,1,
    'codex-test ordinary actual','codex-test r2-f-f2-b'
  ) actual;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual)<>'2020-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_ORDINARY_ACTUAL_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('ordinary_actual_lock_month',true,'ordinary actual used canonical August');

  SELECT actual.id INTO STRICT v_actual
  FROM public.school_create_partial_completed_actual_from_planned(
    v_plan_ids[2],DATE '2020-09-06','10:00','11:00',1,
    'codex-test partial actual','codex-test r2-f-f2-b'
  ) actual;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual)<>'2020-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_PARTIAL_ACTUAL_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('partial_actual_lock_month',true,'partial actual used canonical August');

  SELECT actual.lesson_id INTO STRICT v_actual
  FROM public.school_create_cancelled_actual_lesson_from_planned(
    v_plan_ids[3],DATE '2020-09-06','12:00','14:00',2,8500,3,
    'codex-test cancelled actual','codex-test r2-f-f2-b'
  ) actual;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_actual)<>'2020-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_CANCELLED_ACTUAL_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('cancelled_actual_lock_month',true,'cancelled actual used canonical August');

  IF NOT EXISTS (
    SELECT 1 FROM public.school_list_open_lesson_credit_sources(
      '2020-08','2020-08','2020-09'
    ) source
    WHERE source.id=v_plan_ids[4] AND source.year_month='2020-08'
  ) THEN
    RAISE EXCEPTION 'R2_F_F2_B_OPEN_CREDIT_SOURCE_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('open_credit_source_month',true,'compatibility year_month output is resolver August');

  SELECT * INTO STRICT v_row FROM public.school_lesson_records
  WHERE id=v_plan_ids[5];
  PERFORM * FROM public.school_void_planned_lesson(
    v_row.id,v_row.updated_at,'codex-test r2-f-f2-b void'
  );
  IF NOT EXISTS(SELECT 1 FROM public.school_lesson_records
                WHERE id=v_row.id AND voided_at IS NOT NULL) THEN
    RAISE EXCEPTION 'R2_F_F2_B_VOID_WRONG_MONTH_BLOCKED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('void_lock_month',true,'September lock did not falsely block August void');

  SELECT * INTO STRICT v_row FROM public.school_lesson_records
  WHERE id=v_plan_ids[6];
  PERFORM * FROM public.school_delete_fresh_planned_lesson(
    v_row.id,v_row.updated_at,true
  );
  IF EXISTS(SELECT 1 FROM public.school_lesson_records WHERE id=v_row.id) THEN
    RAISE EXCEPTION 'R2_F_F2_B_DELETE_WRONG_MONTH_BLOCKED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('delete_lock_month',true,'September lock did not falsely block August delete');

  IF (SELECT record_count FROM public.school_get_lesson_management_stats(
        '2020-08',v_student,NULL,NULL,NULL,NULL,v_fixture.business_entity_id
      ))=0
     OR (SELECT record_count FROM public.school_get_lesson_management_stats(
        '2020-09',v_student,NULL,NULL,'planned',NULL,v_fixture.business_entity_id
      ))<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_B_COMPAT_STATS_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('compat_stats_month',true,'old stats agrees with authoritative August reader');

  -- Batch and import lock prechecks use the existing planned attribution resolver.
  SELECT result.created_lesson_id INTO STRICT v_batch
  FROM public.school_generate_planned_lessons_batch(
    'f2fb0000-0000-4000-8000-00000000d001',v_student,
    v_fixture.business_entity_id,DATE '2020-09-06',DATE '2020-09-06',
    jsonb_build_array(jsonb_build_object(
      'pattern_index',1,'weekday',0,'status','planned',
      'teacher_id',v_fixture.teacher_id,'subject_id',v_fixture.subject_id,
      'start_time','06:00','end_time','08:00','duration_hours',0,
      'unit_price',8500,'occurrence_count',1,'lesson_count',8,
      'lesson_content','codex-test R2-F-F2-B batch'
    )),'[]'::jsonb,'codex-test r2-f-f2-b'
  ) result
  WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_batch)<>'2020-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_BATCH_MONTH_FAILED';
  END IF;

  SELECT result.created_lesson_id INTO STRICT v_import
  FROM public.school_import_lesson_records_batch(
    'f2fb0000-0000-4000-8000-00000000d002',
    'codex-test-r2-f-f2-b.csv','codex-test-r2-f-f2-b-hash',
    jsonb_build_array(jsonb_build_object(
      'row_index',1,'source_row_no',2,'row_key','r2-f-f2-b-import',
      'lesson_type','planned','status','planned','lesson_date','2020-09-06',
      'start_time','05:00','end_time','07:00','duration_hours',0,
      'lesson_count',9,'unit_price',8500,'lesson_fee',NULL,'is_billable',true,
      'student_id',v_student,'teacher_id',v_fixture.teacher_id,
      'subject_id',v_fixture.subject_id,
      'business_entity_id',v_fixture.business_entity_id,
      'planned_lesson_id',NULL,'lesson_content','codex-test R2-F-F2-B import',
      'note','codex-test r2-f-f2-b'
    )),'codex-test r2-f-f2-b'
  ) result
  WHERE result.batch_committed AND result.created_lesson_id IS NOT NULL;
  IF public.school_resolve_r1d_e_c_lesson_student_month(v_import)<>'2020-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_IMPORT_MONTH_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('batch_import_lock_month',true,
     'batch/import passed September lock and resolved canonical August');

  -- A lock on the actual canonical month must still fail closed.
  SELECT created.lesson_id INTO STRICT v_plan
  FROM public.school_create_planned_lesson_record(
    DATE '2020-09-06',v_locked_student,v_fixture.teacher_id,
    v_fixture.subject_id,v_fixture.business_entity_id,'08:00','10:00',0,
    8500,NULL,'planned',1,'codex-test locked August source',
    'codex-test r2-f-f2-b'
  ) created;
  INSERT INTO public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,carryover_amount_cny,
    settlement_status,locked_at,note
  ) VALUES (
    'f2fb0000-0000-4000-8000-00000000c002',v_locked_student,'2020-08',
    v_fixture.business_entity_id,0,'locked',now(),
    'codex-test canonical August lock'
  );
  BEGIN
    PERFORM * FROM public.school_create_actual_lesson_from_planned(
      v_plan,DATE '2020-09-06','08:00','10:00',2,8500,NULL,1,
      'codex-test should reject','codex-test r2-f-f2-b'
    );
    RAISE EXCEPTION 'R2_F_F2_B_CANONICAL_LOCK_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='R2_F_F2_B_CANONICAL_LOCK_NOT_REJECTED' THEN RAISE; END IF;
    IF position('月度结算已锁定' IN SQLERRM)=0 THEN RAISE; END IF;
  END;
  INSERT INTO r2_f_f2_b_results VALUES
    ('canonical_lock_fail_closed',true,'August lock still rejects actual generation');

  IF public.school_resolve_lesson_student_month_authoritative(
       'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'
     )<>'2026-08' THEN
    RAISE EXCEPTION 'R2_F_F2_B_PUBLIC_READ_WRAPPER_FAILED';
  END IF;
  INSERT INTO r2_f_f2_b_results VALUES
    ('read_wrapper',true,'target UUID resolves to 2026-08');
END
$tests$;

TABLE r2_f_f2_b_results ORDER BY test_name;
ROLLBACK;

SELECT
  (SELECT count(*) FROM public.school_students
   WHERE id IN (
     'f2fb0000-0000-4000-8000-00000000a001',
     'f2fb0000-0000-4000-8000-00000000a002'
   )) AS student_residue,
  (SELECT count(*) FROM public.school_lesson_records
   WHERE note='codex-test r2-f-f2-b') AS lesson_residue,
  (SELECT count(*) FROM public.school_student_monthly_settlements
   WHERE id IN (
     'f2fb0000-0000-4000-8000-00000000c001',
     'f2fb0000-0000-4000-8000-00000000c002'
   )) AS settlement_residue;
