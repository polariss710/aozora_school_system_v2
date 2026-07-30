\set ON_ERROR_STOP on
\pset pager off

-- Aozora V2 actual duration overage S1-B.
-- Activates only the canonical ordinary planned -> completed actual writer.
-- Existing history is not scanned or backfilled. Settlement/candidate/bill/Cash
-- readers remain unchanged. No trigger, RLS, ACL, or table schema is changed.

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
  v_constraint record;
  v_expected_md5 text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'da156f6c951b233a2878ecb100b2748b'
     OR md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'bf856292c268aefa7c1aa036da480ae7' THEN
    RAISE EXCEPTION 'S1_B_WRITER_SOURCE_FUNCTION_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
     )) <> 'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) <> '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure
     )) <> '155e831118acbeadfd04b6640324c7cd'
     OR md5(pg_get_functiondef(
       'public.school_resolve_planned_duration(text,text,numeric)'::regprocedure
     )) <> '4f5b754585c9e3752639e6b0f2fa7a34'
     OR md5(pg_get_functiondef(
       'public.school_calculate_planned_fee_components(uuid,date,uuid,numeric,numeric)'::regprocedure
     )) <> '2dfabf4a920f7138043079855347207b' THEN
    RAISE EXCEPTION 'S1_B_PROTECTED_AUTHORITY_FUNCTION_DRIFT';
  END IF;

  FOR v_constraint IN
    SELECT conname, md5(pg_get_constraintdef(oid, true)) AS definition_md5
    FROM pg_constraint
    WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk'
    )
  LOOP
    v_expected_md5 := CASE v_constraint.conname
      WHEN 'school_lesson_records_duration_overage_amount_chk' THEN 'aeb662dbbe94f4edc762fc7f0cce01af'
      WHEN 'school_lesson_records_duration_overage_bundle_chk' THEN '11734ff65bfe2cd11245b97badc6031e'
      WHEN 'school_lesson_records_duration_overage_context_chk' THEN '8f4ed33a0acde88149edcb3b2a53abba'
      WHEN 'school_student_settlements_duration_overage_amount_chk' THEN '4162bb6cd2c2306524673657e7daa6de'
      WHEN 'school_student_settlements_duration_overage_bundle_chk' THEN 'e9b4974c90d80a032ff56f500276a25a'
      WHEN 'school_student_settlements_duration_overage_policy_chk' THEN '3275c0d1fb1b72e5261019a1f505d00d'
      ELSE NULL
    END;
    IF v_constraint.definition_md5 IS DISTINCT FROM v_expected_md5 THEN
      RAISE EXCEPTION 'S1_B_S1_A_CONSTRAINT_DRIFT: %', v_constraint.conname;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
      'school_lesson_records_duration_overage_bundle_chk',
      'school_lesson_records_duration_overage_context_chk',
      'school_lesson_records_duration_overage_amount_chk',
      'school_student_settlements_duration_overage_bundle_chk',
      'school_student_settlements_duration_overage_policy_chk',
      'school_student_settlements_duration_overage_amount_chk')) <> 6 THEN
    RAISE EXCEPTION 'S1_B_S1_A_CONSTRAINT_COUNT_DRIFT';
  END IF;

  IF public.school_primary_business_entity_id()
       IS DISTINCT FROM '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
     OR NOT EXISTS (
       SELECT 1 FROM public.school_business_entities b
       WHERE b.id = public.school_primary_business_entity_id()
         AND b.code = 'aosora'
         AND b.name = '青空进学塾'
         AND coalesce(b.is_active, true)
     ) THEN
    RAISE EXCEPTION 'S1_B_PRIMARY_BUSINESS_ENTITY_AUTHORITY_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records) <> 649
     OR (SELECT count(*) FROM public.school_lesson_records
         WHERE num_nonnulls(
           student_duration_overage_minutes,
           student_duration_overage_fee_jpy,
           student_duration_overage_policy_version,
           student_duration_overage_source,
           student_duration_overage_decided_at
         ) > 0) <> 0
     OR (SELECT count(*) FROM public.school_student_monthly_settlements
         WHERE num_nonnulls(
           duration_overage_minutes,
           duration_overage_fee_jpy,
           duration_overage_fee_cny,
           duration_overage_actual_count,
           duration_overage_policy_version,
           duration_overage_source
         ) > 0) <> 0 THEN
    RAISE EXCEPTION 'S1_B_NO_BACKFILL_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview' AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_R0_DRIFT';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE s1_b_business_before ON COMMIT DROP AS
SELECT jsonb_build_object(
  'lessons', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_lesson_records x),
  'settlements', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_monthly_settlements x),
  'bills', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_tuition_bills x),
  'income', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_income_records x),
  'bill_lessons', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_tuition_bill_lessons x),
  'gates', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.feature_key), ''))) FROM public.school_feature_gates x)
) AS fingerprint;

DO $replace_ordinary_writer$
DECLARE
  v_definition text;
  v_replaced text;
  v_declaration_old text := $old$
  v_student_business_entity_id uuid;
$old$;
  v_declaration_new text := $new$
  v_student_business_entity_id uuid;
  v_overage_duration numeric;
  v_overage_minutes integer;
  v_overage_fee_jpy numeric;
  v_overage_source_student_month text;
  v_overage_target_student_month text;
  v_overage_policy_version text;
  v_overage_source text;
  v_overage_decided_at timestamptz;
$new$;
  v_duration_old text := $old$
  if v_duration_hours <> v_planned.duration_hours then
    raise exception '实际完成时长与预定不一致；部分完成请使用“部分完成，剩余转待补”流程。';
  end if;
$old$;
  v_duration_new text := $new$
  if v_planned.duration_hours is null or v_planned.duration_hours <= 0 then
    raise exception '来源预定课时时长无效，不能生成 actual。';
  elsif v_duration_hours < v_planned.duration_hours then
    raise exception '实际完成时长小于预定时长；部分完成请使用“部分完成，剩余转待补”流程。';
  elsif v_duration_hours > v_planned.duration_hours then
    if num_nonnulls(
         v_planned.billing_month,
         v_planned.billing_week_start_date,
         v_planned.student_settlement_month,
         v_planned.billing_month_source,
         v_planned.billing_month_decided_at
       ) <> 5 then
      raise exception 'S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED';
    end if;

    if v_planned.business_entity_id is distinct from public.school_primary_business_entity_id() then
      raise exception 'S1_B_OVERAGE_PRIMARY_BUSINESS_ENTITY_REQUIRED';
    end if;

    if v_planned.is_billable is distinct from true then
      raise exception 'S1_B_OVERAGE_BILLABLE_SOURCE_REQUIRED';
    end if;

    v_overage_source_student_month :=
      public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
    if v_overage_source_student_month is distinct from v_planned.student_settlement_month
       or v_overage_source_student_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
      raise exception 'S1_B_OVERAGE_SOURCE_STUDENT_MONTH_INVALID';
    end if;

    v_overage_target_student_month := to_char(
      (to_date(v_overage_source_student_month || '-01', 'YYYY-MM-DD')
        + interval '1 month')::date,
      'YYYY-MM'
    );
    if v_overage_target_student_month = v_overage_source_student_month then
      raise exception 'S1_B_OVERAGE_TARGET_STUDENT_MONTH_INVALID';
    end if;

    if v_planned.unit_price is null or v_planned.unit_price <= 0 then
      raise exception 'S1_B_OVERAGE_SOURCE_UNIT_PRICE_REQUIRED';
    end if;

    v_overage_duration := v_duration_hours - v_planned.duration_hours;
    v_overage_minutes := round(v_overage_duration * 60)::integer;
    v_overage_fee_jpy := round(v_overage_duration * v_planned.unit_price);
    if v_overage_minutes <= 0 or v_overage_fee_jpy <= 0 then
      raise exception 'S1_B_OVERAGE_POSITIVE_AMOUNT_REQUIRED';
    end if;

    v_overage_policy_version := 'student_duration_overage_v1';
    v_overage_source := 'ordinary_actual_rpc';
    v_overage_decided_at := statement_timestamp();
  end if;
$new$;
  v_columns_old text := $old$
    actual_minutes,
    teacher_settlement_month
  )
$old$;
  v_columns_new text := $new$
    actual_minutes,
    teacher_settlement_month,
    student_duration_overage_minutes,
    student_duration_overage_fee_jpy,
    student_duration_overage_policy_version,
    student_duration_overage_source,
    student_duration_overage_decided_at
  )
$new$;
  v_values_old text := $old$
    v_actual_minutes,
    v_teacher_settlement_month
  )
$old$;
  v_values_new text := $new$
    v_actual_minutes,
    v_teacher_settlement_month,
    v_overage_minutes,
    v_overage_fee_jpy,
    v_overage_policy_version,
    v_overage_source,
    v_overage_decided_at
  )
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  ) INTO v_definition;

  IF md5(v_definition) <> 'da156f6c951b233a2878ecb100b2748b'
     OR position(v_declaration_old IN v_definition) = 0
     OR position(v_duration_old IN v_definition) = 0
     OR position(v_columns_old IN v_definition) = 0
     OR position(v_values_old IN v_definition) = 0 THEN
    RAISE EXCEPTION 'S1_B_ORDINARY_WRITER_SOURCE_FRAGMENT_DRIFT';
  END IF;

  v_replaced := replace(v_definition, v_declaration_old, v_declaration_new);
  v_replaced := replace(v_replaced, v_duration_old, v_duration_new);
  v_replaced := replace(v_replaced, v_columns_old, v_columns_new);
  v_replaced := replace(v_replaced, v_values_old, v_values_new);

  IF v_replaced = v_definition
     OR position('S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED' IN v_replaced) = 0
     OR position('student_duration_overage_decided_at' IN v_replaced) = 0
     OR position(v_duration_old IN v_replaced) > 0 THEN
    RAISE EXCEPTION 'S1_B_ORDINARY_WRITER_REPLACEMENT_FAILED';
  END IF;

  EXECUTE v_replaced;
END
$replace_ordinary_writer$;

COMMENT ON FUNCTION public.school_create_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,numeric,integer,text,text
) IS
  'S1-B ordinary actual writer. Shorter actuals must use partial completion; equal actuals preserve the existing all-NULL overage behavior; longer actuals atomically freeze a canonical Aozora-only pure-duration overage snapshot using source planned student month and source planned unit price. No settlement, candidate, bill, Cash, aircon, or historical backfill is performed.';

DO $replace_guarded_update$
DECLARE
  v_definition text;
  v_replaced text;
  v_old_fragment text := $old$
    if v_status <> v_lesson.status then
      raise exception 'actual 课时 V1 不允许修改状态。';
    end if;

    if v_status in ('completed', 'makeup_completed') then
$old$;
  v_new_fragment text := $new$
    if v_status <> v_lesson.status then
      raise exception 'actual 课时 V1 不允许修改状态。';
    end if;

    if v_lesson.student_duration_overage_policy_version = 'student_duration_overage_v1'
       and v_lesson.student_duration_overage_source = 'ordinary_actual_rpc'
       and (
         v_duration_hours is distinct from v_lesson.duration_hours
         or v_unit_price is distinct from v_lesson.unit_price
       ) then
      raise exception 'S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE';
    end if;

    if v_status in ('completed', 'makeup_completed') then
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  ) INTO v_definition;

  IF md5(v_definition) <> 'bf856292c268aefa7c1aa036da480ae7'
     OR position(v_old_fragment IN v_definition) = 0 THEN
    RAISE EXCEPTION 'S1_B_GUARDED_UPDATE_SOURCE_FRAGMENT_DRIFT';
  END IF;

  v_replaced := replace(v_definition, v_old_fragment, v_new_fragment);
  IF v_replaced = v_definition
     OR position('S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE' IN v_replaced) = 0
     OR position(v_old_fragment IN v_replaced) > 0 THEN
    RAISE EXCEPTION 'S1_B_GUARDED_UPDATE_REPLACEMENT_FAILED';
  END IF;

  EXECUTE v_replaced;
END
$replace_guarded_update$;

COMMENT ON FUNCTION public.school_update_lesson_record_guarded(
  uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,
  text,boolean,integer,text,text
) IS
  'R1D-E-B2 guarded updater plus S1-B normal-application protection: canonical actual student attribution remains frozen, and an ordinary actual carrying the S1-B overage bundle cannot change duration or unit price. Existing non-charge edits remain available; direct-table ACL/RLS debt is outside this phase.';

DO $verify$
DECLARE
  v_after jsonb;
BEGIN
  IF position('S1_B_OVERAGE_CANONICAL_SOURCE_REQUIRED' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('S1_B_OVERAGE_CHARGE_FIELDS_IMMUTABLE' IN pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) = 0 THEN
    RAISE EXCEPTION 'S1_B_WRITER_MARKER_MISSING';
  END IF;

  SELECT jsonb_build_object(
    'lessons', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_lesson_records x),
    'settlements', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_monthly_settlements x),
    'bills', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_tuition_bills x),
    'income', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_income_records x),
    'bill_lessons', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), ''))) FROM public.school_student_tuition_bill_lessons x),
    'gates', (SELECT jsonb_build_array(count(*), md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.feature_key), ''))) FROM public.school_feature_gates x)
  ) INTO v_after;

  IF v_after IS DISTINCT FROM (SELECT fingerprint FROM s1_b_business_before) THEN
    RAISE EXCEPTION 'S1_B_DEPLOYMENT_CHANGED_BUSINESS_DATA';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  )) AS ordinary_writer_md5,
  md5(pg_get_functiondef(
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  )) AS guarded_writer_md5;

COMMIT;
