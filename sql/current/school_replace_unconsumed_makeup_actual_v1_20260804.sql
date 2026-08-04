-- School V2: controlled replacement of the single approved unconsumed makeup actual.
-- Business-model expansion declaration:
--   New tables/columns/statuses/facts/fallbacks/dual writes/history reinterpretation: none.
--   Changed writer authority: the explicitly approved service-role-only function
--   public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamptz,uuid,date,text,text).

\set ON_ERROR_STOP on
\pset pager off

\if :{?makeup_replacement_commit}
\else
  \echo 'MAKEUP_REPLACEMENT_COMMIT_VARIABLE_REQUIRED'
  \quit 3
\endif

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

CREATE OR REPLACE FUNCTION public.school_replace_unconsumed_makeup_actual_v1(
  p_actual_id uuid,
  p_expected_updated_at timestamptz,
  p_source_planned_id uuid,
  p_correct_actual_date date,
  p_reason text,
  p_confirmation text
) RETURNS TABLE (
  replaced_actual_id uuid,
  new_actual_id uuid,
  source_planned_id uuid,
  correct_actual_date date,
  lesson_fee numeric,
  teacher_settlement_month text,
  student_settlement_month text,
  remaining_makeup_hours numeric,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actual public.school_lesson_records%ROWTYPE;
  v_deleted public.school_lesson_records%ROWTYPE;
  v_source public.school_lesson_records%ROWTYPE;
  v_original public.school_lesson_records%ROWTYPE;
  v_new public.school_lesson_records%ROWTYPE;
  v_student_name text;
  v_teacher_name text;
  v_subject_name text;
  v_old_student_month text;
  v_correct_month text;
  v_original_count integer;
  v_deleted_count integer;
  v_remaining numeric;
  v_is_test_scope boolean := false;
  v_test_marker constant text := 'codex-test makeup-actual-replacement-v1-20260804';
  v_source_before jsonb;
  v_original_before jsonb;
  v_bill_before jsonb;
  v_income_before jsonb;
BEGIN
  IF coalesce(auth.role()::text, '') <> 'service_role' THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_SERVICE_ROLE_REQUIRED';
  END IF;
  IF p_actual_id IS NULL OR p_expected_updated_at IS NULL
     OR p_source_planned_id IS NULL OR p_correct_actual_date IS NULL THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_INPUT_REQUIRED';
  END IF;
  IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_REASON_REQUIRED';
  END IF;
  IF p_confirmation IS DISTINCT FROM 'REPLACE_UNCONSUMED_MAKEUP_ACTUAL' THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_CONFIRMATION_MISMATCH';
  END IF;

  SELECT a.* INTO v_actual
  FROM public.school_lesson_records a
  WHERE a.id = p_actual_id AND a.app_type = 'school';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_NOT_FOUND';
  END IF;
  v_old_student_month := public.school_resolve_r1d_e_c_lesson_student_month(v_actual.id);
  v_correct_month := to_char(p_correct_actual_date, 'YYYY-MM');
  IF v_old_student_month IS NULL OR v_correct_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_MONTH_UNCLASSIFIED';
  END IF;

  -- Use the existing tuition-operation lock order before row locks or DML.
  PERFORM public.school_tuition_p0b1_lock_lesson_scopes(jsonb_build_array(
    jsonb_build_object(
      'student_id', v_actual.student_id,
      'business_entity_id', v_actual.business_entity_id,
      'year_month', v_old_student_month
    ),
    jsonb_build_object(
      'student_id', v_actual.student_id,
      'business_entity_id', v_actual.business_entity_id,
      'year_month', v_correct_month
    )
  ));

  SELECT p.* INTO v_source
  FROM public.school_lesson_records p
  WHERE p.id = p_source_planned_id AND p.app_type = 'school'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_SOURCE_NOT_FOUND';
  END IF;
  SELECT a.* INTO v_actual
  FROM public.school_lesson_records a
  WHERE a.id = p_actual_id AND a.app_type = 'school'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_NOT_FOUND';
  END IF;
  IF v_actual.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_STALE_ACTUAL';
  END IF;

  v_is_test_scope := session_user = 'postgres'
    AND current_setting('school.makeup_actual_replacement_test_scope', true)
          = v_test_marker
    AND v_actual.student_id = 'a4a40000-0000-4000-8000-000000000001'::uuid
    AND v_actual.note = v_test_marker
    AND v_source.note = v_test_marker;

  IF NOT v_is_test_scope AND (
       p_actual_id IS DISTINCT FROM 'd1c60932-0f8a-43e3-98b8-bb362921ccf8'::uuid
       OR p_source_planned_id IS DISTINCT FROM 'd4e3e060-1951-4fdd-9340-e6feb6687b7f'::uuid
       OR p_correct_actual_date IS DISTINCT FROM DATE '2026-08-02'
     ) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_SCOPE_NOT_APPROVED';
  END IF;

  SELECT s.name, t.name, sub.name
    INTO STRICT v_student_name, v_teacher_name, v_subject_name
  FROM public.school_students s
  JOIN public.school_teachers t ON t.id = v_actual.teacher_id
  JOIN public.school_subjects sub ON sub.id = v_actual.subject_id
  WHERE s.id = v_actual.student_id;

  IF NOT v_is_test_scope AND (
       v_actual.student_id IS DISTINCT FROM 'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
       OR v_actual.teacher_id IS DISTINCT FROM 'f3b8735b-1966-4dae-ac4e-846cbedc54e6'::uuid
       OR v_actual.subject_id IS DISTINCT FROM 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid
       OR v_student_name IS DISTINCT FROM '陈红卓'
       OR v_teacher_name IS DISTINCT FROM '王亚楠'
       OR v_subject_name IS DISTINCT FROM 'EJU日语'
     ) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_BUSINESS_IDENTITY_MISMATCH';
  END IF;

  IF v_actual.lesson_type IS DISTINCT FROM 'actual'
     OR v_actual.lesson_date IS DISTINCT FROM DATE '2026-07-31'
     OR v_actual.year_month IS DISTINCT FROM '2026-07'
     OR v_actual.start_time IS DISTINCT FROM '13:00'
     OR v_actual.end_time IS DISTINCT FROM '14:00'
     OR v_actual.duration_hours IS DISTINCT FROM 1::numeric
     OR v_actual.actual_minutes IS DISTINCT FROM 60
     OR v_actual.status IS DISTINCT FROM 'makeup_completed'
     OR v_actual.is_billable IS DISTINCT FROM false
     OR v_actual.lesson_fee IS DISTINCT FROM 0::numeric
     OR v_actual.planned_lesson_id IS DISTINCT FROM p_source_planned_id
     OR v_actual.voided_at IS NOT NULL THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_FACTS_MISMATCH';
  END IF;
  IF v_source.lesson_type IS DISTINCT FROM 'planned'
     OR v_source.lesson_date IS DISTINCT FROM DATE '2026-07-20'
     OR v_source.duration_hours IS DISTINCT FROM 2::numeric
     OR v_source.status IS DISTINCT FROM 'pending_makeup'
     OR v_source.is_billable IS DISTINCT FROM true
     OR v_source.student_id IS DISTINCT FROM v_actual.student_id
     OR v_source.business_entity_id IS DISTINCT FROM v_actual.business_entity_id
     OR v_source.voided_at IS NOT NULL THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_SOURCE_FACTS_MISMATCH';
  END IF;

  SELECT count(*) INTO v_original_count
  FROM public.school_lesson_records a
  WHERE a.planned_lesson_id = v_source.id
    AND a.id <> v_actual.id
    AND a.app_type = 'school'
    AND a.lesson_type = 'actual'
    AND a.status = 'completed';
  IF v_original_count <> 1 THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ORIGINAL_ACTUAL_COUNT_MISMATCH';
  END IF;
  SELECT a.* INTO STRICT v_original
  FROM public.school_lesson_records a
  WHERE a.planned_lesson_id = v_source.id
    AND a.id <> v_actual.id
    AND a.app_type = 'school'
    AND a.lesson_type = 'actual'
    AND a.status = 'completed'
  FOR UPDATE;
  IF v_original.lesson_date IS DISTINCT FROM DATE '2026-07-20'
     OR v_original.duration_hours IS DISTINCT FROM 1::numeric
     OR v_original.student_id IS DISTINCT FROM v_source.student_id
     OR v_original.teacher_id IS DISTINCT FROM v_actual.teacher_id
     OR v_original.subject_id IS DISTINCT FROM v_actual.subject_id THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ORIGINAL_ACTUAL_FACTS_MISMATCH';
  END IF;
  IF NOT v_is_test_scope AND (
       v_original.id IS DISTINCT FROM 'e28d255d-4f6b-45e4-9766-d8d16f97d37b'::uuid
       OR md5(to_jsonb(v_original)::text) IS DISTINCT FROM '0813f33689c87d799fe967826e37a8a2'
       OR md5(to_jsonb(v_source)::text) IS DISTINCT FROM '349111f8a6818c44a0cf4e1886cda97d'
       OR md5(to_jsonb(v_actual)::text) IS DISTINCT FROM '77b35e350c60c4ae1dc33b0f45a7656e'
     ) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_APPROVED_ROW_DRIFT';
  END IF;
  IF public.school_get_lesson_credit_remaining_hours(v_source.id) IS DISTINCT FROM 0::numeric THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_PREDELETE_BALANCE_MISMATCH';
  END IF;

  -- Reject every known immutable or external consumer of the actual itself.
  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details d
             WHERE d.lesson_record_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
                WHERE w.teacher_id = v_actual.teacher_id
                  AND w.business_entity_id IS NOT DISTINCT FROM v_actual.business_entity_id
                  AND w.settlement_month IN (v_old_student_month, v_correct_month)) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_WAGE_CONSUMED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
             WHERE s.student_id = v_actual.student_id
               AND s.business_entity_id IS NOT DISTINCT FROM v_actual.business_entity_id
               AND s.year_month IN (v_old_student_month, v_correct_month)) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_SETTLEMENT_CONSUMED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_settlement_lesson_variance_claims c
             WHERE c.source_actual_lesson_id = v_actual.id
                OR c.source_planned_lesson_id = v_source.id) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_CLAIM_CONSUMED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons r
             WHERE r.planned_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_income_records i
                WHERE position(v_actual.id::text IN to_jsonb(i)::text) > 0)
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                WHERE position(v_actual.id::text IN to_jsonb(b)::text) > 0) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_ACTUAL_FINANCIAL_RELATION';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
             WHERE e.actual_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_student_tuition_historical_lesson_exclusions e
                WHERE e.linked_actual_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_business_entity_migration_items i
                WHERE i.lesson_record_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_planned_writer_commands c
                WHERE c.result_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_tuition_billing_attribution_override_audit a
                WHERE a.planned_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_lesson_records a
                WHERE a.planned_lesson_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_account_transactions a
                WHERE a.related_id = v_actual.id)
     OR EXISTS (SELECT 1 FROM public.school_personal_cash_income_linkage_events e
                WHERE position(v_actual.id::text IN to_jsonb(e)::text) > 0)
     OR EXISTS (SELECT 1 FROM public.school_personal_cash_linkage_events e
                WHERE position(v_actual.id::text IN to_jsonb(e)::text) > 0)
     OR EXISTS (SELECT 1 FROM public.school_part_time_work_monthly_settlement_details d
                WHERE d.actual_lesson_id = v_actual.id) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_OTHER_IMMUTABLE_RELATION';
  END IF;

  v_source_before := to_jsonb(v_source);
  v_original_before := to_jsonb(v_original);
  IF NOT v_is_test_scope THEN
    SELECT to_jsonb(b) INTO STRICT v_bill_before
    FROM public.school_student_tuition_bills b
    WHERE b.id = '7472f73f-fa19-4565-9180-a517c7151835'::uuid;
    SELECT to_jsonb(i) INTO STRICT v_income_before
    FROM public.school_income_records i
    WHERE i.id = '3a5542c5-5397-4688-999e-a08bb678f40d'::uuid;
    IF md5(v_bill_before::text) IS DISTINCT FROM 'bfa62da082009fbcef7fa8612152fc0a'
       OR md5(v_income_before::text) IS DISTINCT FROM '9071f5eb1b0ad2c0108b6673e375f751'
       OR NOT EXISTS (
         SELECT 1 FROM public.school_student_tuition_bill_lessons r
         WHERE r.tuition_bill_id = '7472f73f-fa19-4565-9180-a517c7151835'::uuid
           AND r.planned_lesson_id = v_source.id
       ) THEN
      RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_PLANNED_CHARGE_DRIFT';
    END IF;
  END IF;

  DELETE FROM public.school_lesson_records a
  WHERE a.id = v_actual.id
    AND a.updated_at = p_expected_updated_at
  RETURNING a.* INTO v_deleted;
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  IF v_deleted_count <> 1 OR v_deleted.id IS DISTINCT FROM v_actual.id THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_DELETE_COUNT_MISMATCH';
  END IF;
  v_remaining := public.school_get_lesson_credit_remaining_hours(v_source.id);
  IF v_remaining IS DISTINCT FROM 1::numeric THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_POSTDELETE_BALANCE_MISMATCH';
  END IF;

  SELECT created.* INTO STRICT v_new
  FROM public.school_create_lesson_credit_makeup_actual(
    v_source.id,
    p_correct_actual_date,
    v_deleted.teacher_id,
    v_deleted.subject_id,
    v_deleted.start_time,
    v_deleted.end_time,
    v_deleted.duration_hours,
    v_deleted.lesson_content,
    v_deleted.note,
    v_deleted.lesson_count,
    v_deleted.lesson_delivery_mode,
    v_deleted.lesson_venue
  ) created;

  IF v_new.id IS NULL OR v_new.id = v_deleted.id
     OR v_new.lesson_type IS DISTINCT FROM 'actual'
     OR v_new.lesson_date IS DISTINCT FROM p_correct_actual_date
     OR v_new.start_time IS DISTINCT FROM v_deleted.start_time
     OR v_new.end_time IS DISTINCT FROM v_deleted.end_time
     OR v_new.duration_hours IS DISTINCT FROM v_deleted.duration_hours
     OR v_new.actual_minutes IS DISTINCT FROM v_deleted.actual_minutes
     OR v_new.teacher_id IS DISTINCT FROM v_deleted.teacher_id
     OR v_new.subject_id IS DISTINCT FROM v_deleted.subject_id
     OR v_new.lesson_content IS DISTINCT FROM v_deleted.lesson_content
     OR v_new.note IS DISTINCT FROM v_deleted.note
     OR v_new.lesson_delivery_mode IS DISTINCT FROM v_deleted.lesson_delivery_mode
     OR v_new.lesson_venue IS DISTINCT FROM v_deleted.lesson_venue
     OR v_new.status IS DISTINCT FROM 'makeup_completed'
     OR v_new.is_billable IS DISTINCT FROM false
     OR v_new.lesson_fee IS DISTINCT FROM 0::numeric
     OR v_new.planned_lesson_id IS DISTINCT FROM v_source.id
     OR v_new.teacher_settlement_month IS DISTINCT FROM v_correct_month
     OR v_new.student_settlement_month IS DISTINCT FROM
          public.school_resolve_r1d_e_b2_actual_student_month(v_source.id)
     OR v_new.year_month IS DISTINCT FROM v_new.student_settlement_month
     OR coalesce(v_new.student_duration_overage_minutes, 0) <> 0
     OR coalesce(v_new.student_duration_overage_fee_jpy, 0) <> 0 THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_NEW_ACTUAL_MISMATCH';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_lesson_records a WHERE a.id = v_deleted.id)
     OR public.school_get_lesson_credit_remaining_hours(v_source.id) IS DISTINCT FROM 0::numeric
     OR (SELECT count(*) FROM public.school_lesson_records a
         WHERE a.planned_lesson_id = v_source.id
           AND a.lesson_type = 'actual'
           AND a.status = 'makeup_completed') <> 1
     OR (SELECT to_jsonb(p) FROM public.school_lesson_records p WHERE p.id = v_source.id)
          IS DISTINCT FROM v_source_before
     OR (SELECT to_jsonb(a) FROM public.school_lesson_records a WHERE a.id = v_original.id)
          IS DISTINCT FROM v_original_before THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_POSTWRITE_INVARIANT_FAILED';
  END IF;
  IF NOT v_is_test_scope AND (
       (SELECT to_jsonb(b) FROM public.school_student_tuition_bills b
        WHERE b.id = '7472f73f-fa19-4565-9180-a517c7151835'::uuid)
          IS DISTINCT FROM v_bill_before
       OR (SELECT to_jsonb(i) FROM public.school_income_records i
           WHERE i.id = '3a5542c5-5397-4688-999e-a08bb678f40d'::uuid)
          IS DISTINCT FROM v_income_before
     ) THEN
    RAISE EXCEPTION 'MAKEUP_ACTUAL_REPLACEMENT_PLANNED_FINANCE_CHANGED';
  END IF;

  RETURN QUERY SELECT
    v_deleted.id,
    v_new.id,
    v_source.id,
    v_new.lesson_date,
    v_new.lesson_fee,
    v_new.teacher_settlement_month,
    v_new.student_settlement_month,
    public.school_get_lesson_credit_remaining_hours(v_source.id),
    'MAKEUP_ACTUAL_REPLACEMENT_COMPLETED'::text;
END
$function$;

COMMENT ON FUNCTION public.school_replace_unconsumed_makeup_actual_v1(
  uuid,timestamptz,uuid,date,text,text
) IS
  'Service-role-only atomic correction for the approved unconsumed non-billable makeup actual. It locks both tuition scopes, rejects immutable consumers, deletes exactly one approved actual, and delegates recreation to school_create_lesson_credit_makeup_actual. No generic delete is exposed.';

REVOKE ALL ON FUNCTION public.school_replace_unconsumed_makeup_actual_v1(
  uuid,timestamptz,uuid,date,text,text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_replace_unconsumed_makeup_actual_v1(
  uuid,timestamptz,uuid,date,text,text
) TO service_role;

\if :makeup_replacement_commit
  COMMIT;
  \echo 'MAKEUP_REPLACEMENT_WRITER_DEPLOYED'
\else
  ROLLBACK;
  \echo 'MAKEUP_REPLACEMENT_WRITER_REHEARSAL_ROLLED_BACK'
\endif
