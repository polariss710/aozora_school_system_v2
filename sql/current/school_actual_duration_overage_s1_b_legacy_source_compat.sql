\set ON_ERROR_STOP on
\pset pager off

-- S1-B approved legacy planned source compatibility patch.
-- Replaces only the ordinary planned -> completed actual writer definition.
-- No lesson, evidence, settlement, bill, income, Cash, or R0 data is changed.

BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '180s';

LOCK TABLE public.school_lesson_records IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_WRITER_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
     )) <> 'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     )) <> '4a163f6691c779531a65a10be0f4422e'
     OR md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     )) <> '08f3c60890d4afab8d9c730eec286c8d'
     OR md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
     )) <> 'd24b82f51053b3960ce0e4839613ddc7'
     OR md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
     )) <> 'f9f5e0fffc2d0fcb5f917cc374c9e9ac'
     OR md5(pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
     )) <> '523058b631837025101d558668ce10c8'
     OR md5(pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> '5b313cc696057a4a1f960ed8f1b50124' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_PROTECTED_FUNCTION_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_lesson_records p
    JOIN public.school_business_entities b ON b.id = p.business_entity_id
    JOIN public.school_legacy_planned_settlement_evidence e
      ON e.planned_lesson_id = p.id
    WHERE p.id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
      AND p.app_type = 'school'
      AND p.lesson_type = 'planned'
      AND p.status = 'planned'
      AND p.voided_at IS NULL
      AND p.is_billable IS TRUE
      AND p.duration_hours = 2
      AND p.unit_price = 10000
      AND b.code = 'aosora'
      AND b.name = '青空进学塾'
      AND e.approved_manifest IS TRUE
      AND e.evidence_source = 'r1d_e_b1_fixed_legacy_279'
      AND e.evidence_version = 'legacy_settlement_evidence_v1'
      AND e.student_id_snapshot IS NOT DISTINCT FROM p.student_id
      AND e.business_entity_id_snapshot IS NOT DISTINCT FROM p.business_entity_id
      AND e.legacy_student_settlement_month = '2026-07'
      AND e.lesson_identity_md5 = md5(concat_ws('|',
        p.id::text,
        coalesce(p.student_id::text, '<NULL>'),
        coalesce(p.business_entity_id::text, '<NULL>'),
        coalesce(p.year_month, '<NULL>'),
        p.lesson_type,
        p.app_type
      ))
      AND num_nonnulls(
        p.billing_month,
        p.billing_week_start_date,
        p.student_settlement_month,
        p.billing_month_source,
        p.billing_month_decided_at
      ) = 0
      AND public.school_resolve_r1d_e_b2_actual_student_month(p.id) = '2026-07'
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_SOURCE_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records a
    WHERE a.lesson_type = 'actual'
      AND a.planned_lesson_id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_ALREADY_HAS_ACTUAL';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_monthly_settlements s
    JOIN public.school_lesson_records p ON p.student_id = s.student_id
    WHERE p.id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
      AND s.business_entity_id IS NOT DISTINCT FROM p.business_entity_id
      AND s.year_month = '2026-07'
      AND s.settlement_status = 'locked'
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_SOURCE_MONTH_LOCKED';
  END IF;

  IF (SELECT count(*)
      FROM public.school_feature_gates
      WHERE (feature_key = 'student_tuition_preview'
             AND state = 'validation_preview_only')
         OR (feature_key = 'student_tuition_generate' AND state = 'blocked')
         OR (feature_key = 'student_tuition_cash_submit' AND state = 'blocked')) <> 3 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_R0_DRIFT';
  END IF;
END
$preflight$;

CREATE TEMPORARY TABLE s1_b_legacy_compat_business_before
ON COMMIT DROP
AS
SELECT jsonb_build_object(
  'lessons', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
    FROM public.school_lesson_records x
  ),
  'planned_evidence', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.planned_lesson_id::text), '')))
    FROM public.school_legacy_planned_settlement_evidence x
  ),
  'settlements', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
    FROM public.school_student_monthly_settlements x
  ),
  'bills', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
    FROM public.school_student_tuition_bills x
  ),
  'income', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
    FROM public.school_income_records x
  ),
  'bill_lessons', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
    FROM public.school_student_tuition_bill_lessons x
  ),
  'gates', (
    SELECT jsonb_build_array(count(*),
      md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.feature_key), '')))
    FROM public.school_feature_gates x
  )
) AS fingerprint;

DO $replace_ordinary_writer$
DECLARE
  v_definition text;
  v_replaced text;
  v_duration_old text := $old$
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
$old$;
  v_duration_new text := $new$
  if v_planned.duration_hours is null or v_planned.duration_hours <= 0 then
    raise exception '来源预定课时时长无效，不能生成 actual。';
  elsif v_duration_hours < v_planned.duration_hours then
    raise exception '实际完成时长小于预定时长；部分完成请使用“部分完成，剩余转待补”流程。';
  elsif v_duration_hours > v_planned.duration_hours then
    if v_planned.business_entity_id is distinct from public.school_primary_business_entity_id() then
      raise exception 'S1_B_OVERAGE_PRIMARY_BUSINESS_ENTITY_REQUIRED';
    end if;

    if v_planned.is_billable is distinct from true then
      raise exception 'S1_B_OVERAGE_BILLABLE_SOURCE_REQUIRED';
    end if;

    if num_nonnulls(
         v_planned.billing_month,
         v_planned.billing_week_start_date,
         v_planned.student_settlement_month,
         v_planned.billing_month_source,
         v_planned.billing_month_decided_at
       ) = 5 then
      v_overage_source_student_month :=
        public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
      if v_overage_source_student_month is distinct from v_planned.student_settlement_month then
        raise exception 'S1_B_OVERAGE_SOURCE_STUDENT_MONTH_INVALID';
      end if;
    elsif num_nonnulls(
         v_planned.billing_month,
         v_planned.billing_week_start_date,
         v_planned.student_settlement_month,
         v_planned.billing_month_source,
         v_planned.billing_month_decided_at
       ) = 0 then
      if (select count(*)
          from public.school_legacy_planned_settlement_evidence e
          where e.planned_lesson_id = v_planned.id
            and e.approved_manifest is true
            and e.evidence_source = 'r1d_e_b1_fixed_legacy_279'
            and e.evidence_version = 'legacy_settlement_evidence_v1') <> 1 then
        raise exception 'S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED';
      end if;

      v_overage_source_student_month :=
        public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
      if v_overage_source_student_month is distinct from (
           select e.legacy_student_settlement_month
           from public.school_legacy_planned_settlement_evidence e
           where e.planned_lesson_id = v_planned.id
         ) then
        raise exception 'S1_B_OVERAGE_LEGACY_SOURCE_MONTH_INVALID';
      end if;
    else
      raise exception 'S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED';
    end if;

    if v_overage_source_student_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
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
  v_lock_old text := $old$
      and s.year_month = v_planned.year_month
$old$;
  v_lock_new text := $new$
      and s.year_month = coalesce(v_overage_source_student_month, v_planned.year_month)
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  ) INTO v_definition;

  IF md5(v_definition) <> 'e3d9dd24f3fd7c533301bb5c1a27fa4f'
     OR position(v_duration_old IN v_definition) = 0
     OR position(v_lock_old IN v_definition) = 0
     OR position('S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED' IN v_definition) > 0 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_SOURCE_FRAGMENT_DRIFT';
  END IF;

  v_replaced := replace(v_definition, v_duration_old, v_duration_new);
  v_replaced := replace(v_replaced, v_lock_old, v_lock_new);

  IF v_replaced = v_definition
     OR position(v_duration_old IN v_replaced) > 0
     OR position(v_lock_old IN v_replaced) > 0
     OR position('S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED' IN v_replaced) = 0
     OR position('S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED' IN v_replaced) = 0
     OR position(v_lock_new IN v_replaced) = 0 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_REPLACEMENT_FAILED';
  END IF;

  EXECUTE v_replaced;
END
$replace_ordinary_writer$;

COMMENT ON FUNCTION public.school_create_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,numeric,integer,text,text
) IS
  'S1-B ordinary actual writer with approved legacy planned compatibility. Longer actuals atomically freeze an Aozora-only pure-duration overage snapshot from either a complete canonical R1D source or an all-NULL source with unique immutable R1D-E-B1 approved evidence and an E-B2-resolved student month. Partial attribution, unapproved legacy, locked source month, non-billable, duplicate, voided and non-Aozora sources fail closed. No planned backfill, settlement consumer change, historical scan, bill, income, Cash or R0 change is performed.';

DO $verify$
DECLARE
  v_after jsonb;
BEGIN
  IF position('S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0
     OR position('coalesce(v_overage_source_student_month, v_planned.year_month)' IN pg_get_functiondef(
       'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
     )) = 0 THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_WRITER_MARKER_MISSING';
  END IF;

  SELECT jsonb_build_object(
    'lessons', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
      FROM public.school_lesson_records x
    ),
    'planned_evidence', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.planned_lesson_id::text), '')))
      FROM public.school_legacy_planned_settlement_evidence x
    ),
    'settlements', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
      FROM public.school_student_monthly_settlements x
    ),
    'bills', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
      FROM public.school_student_tuition_bills x
    ),
    'income', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
      FROM public.school_income_records x
    ),
    'bill_lessons', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.id::text), '')))
      FROM public.school_student_tuition_bill_lessons x
    ),
    'gates', (
      SELECT jsonb_build_array(count(*),
        md5(coalesce(string_agg(md5(to_jsonb(x)::text), '' ORDER BY x.feature_key), '')))
      FROM public.school_feature_gates x
    )
  ) INTO v_after;

  IF v_after IS DISTINCT FROM (
       SELECT fingerprint FROM s1_b_legacy_compat_business_before
     ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_DEPLOYMENT_CHANGED_BUSINESS_DATA';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records a
    WHERE a.lesson_type = 'actual'
      AND a.planned_lesson_id = '20533154-0de9-49b7-bbbd-907aa2a254ee'::uuid
  ) THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_TARGET_CHANGED_DURING_DEPLOYMENT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
     )) <> 'ca52667c94a86608b4ab712f543b04b1'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
     )) <> 'b83f0a270a79c4ed07663ab2c296360e'
     OR md5(pg_get_functiondef(
       'public.school_get_student_duration_overage_aggregate(uuid,text)'::regprocedure
     )) <> 'd24b82f51053b3960ce0e4839613ddc7'
     OR md5(pg_get_functiondef(
       'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
     )) <> 'f9f5e0fffc2d0fcb5f917cc374c9e9ac'
     OR md5(pg_get_functiondef(
       'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure
     )) <> '523058b631837025101d558668ce10c8'
     OR md5(pg_get_functiondef(
       'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure
     )) <> '5b313cc696057a4a1f960ed8f1b50124' THEN
    RAISE EXCEPTION 'S1_B_LEGACY_COMPAT_CHANGED_PROTECTED_FUNCTION';
  END IF;
END
$verify$;

SELECT
  md5(pg_get_functiondef(
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure
  )) AS ordinary_writer_after_md5,
  md5(pg_get_functiondef(
    'public.school_resolve_r1d_e_b2_actual_student_month(uuid)'::regprocedure
  )) AS resolver_md5,
  md5(pg_get_functiondef(
    'public.school_get_student_monthly_settlement_summary(uuid,text)'::regprocedure
  )) AS s1_c_summary_md5;

COMMIT;
