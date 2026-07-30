-- R2-C read-only postdeploy acceptance for the exact two corrected legacy lessons.

\set ON_ERROR_STOP on
\pset pager off

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='180s';

DO $postdeploy$
DECLARE
  v_other_lesson_hash text;
  v_other_evidence_hash text;
  v_historical_19_hash text;
  v_stats_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  ) INTO STRICT v_stats_definition;
  IF (SELECT count(*) FROM public.school_lesson_records)<>652
     OR (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence)<>234
     OR (SELECT count(*) FROM public.school_student_monthly_settlements)<>15
     OR (SELECT count(*) FROM public.school_student_tuition_bills)<>9
     OR (SELECT count(*) FROM public.school_income_records)<>42
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons)<>121 THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_FIXED_COUNT_DRIFT';
  END IF;

  IF (SELECT count(*)
      FROM public.school_lesson_records l
      JOIN public.school_legacy_planned_settlement_evidence e
        ON e.planned_lesson_id=l.id
      WHERE l.id IN (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
        AND l.lesson_type='planned'
        AND l.app_type='school'
        AND l.year_month='2026-07'
        AND e.legacy_student_settlement_month='2026-07'
        AND e.approved_manifest=true
        AND e.evidence_source='r1d_e_b1_fixed_legacy_279'
        AND e.evidence_version='legacy_settlement_evidence_v1'
        AND e.lesson_identity_md5=md5(concat_ws('|',l.id::text,
          coalesce(l.student_id::text,'<NULL>'),
          coalesce(l.business_entity_id::text,'<NULL>'),
          coalesce(l.year_month,'<NULL>'),l.lesson_type,l.app_type))
        AND public.school_resolve_r1d_e_c_lesson_student_month(l.id)='2026-07'
        AND num_nonnulls(l.billing_month,l.billing_week_start_date,
              l.student_settlement_month,l.billing_month_source,
              l.billing_month_decided_at)=0)<>2 THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_TARGET_CORRECTION_MISMATCH';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records l
      WHERE (l.id='8b737b58-cd14-42c5-afd2-34730dcef963'
             AND l.lesson_date=DATE '2026-08-01'
             AND md5((to_jsonb(l)-ARRAY['year_month','updated_at'])::text)
                 ='3b9caa118d24370e92049acb131b9304')
         OR (l.id='685ad45e-b5da-42ca-8f43-7732e8d6e40d'
             AND l.lesson_date=DATE '2026-08-02'
             AND md5((to_jsonb(l)-ARRAY['year_month','updated_at'])::text)
                 ='8905c986902a804234efb2b706e338d7'))<>2 THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_TARGET_PROTECTED_LESSON_FIELDS_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence e
      WHERE (e.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'
             AND e.lesson_identity_md5='0a287ea42649e517879295c772aed039'
             AND md5((to_jsonb(e)-ARRAY[
               'legacy_student_settlement_month','lesson_identity_md5'
             ])::text)='c42e28ff7dd5a8c787f8d0620dbf1ffb')
         OR (e.planned_lesson_id='685ad45e-b5da-42ca-8f43-7732e8d6e40d'
             AND e.lesson_identity_md5='9efda43df96dfb1a36f0e461fab173e6'
             AND md5((to_jsonb(e)-ARRAY[
               'legacy_student_settlement_month','lesson_identity_md5'
             ])::text)='814bc9a89c7a2a3a772da5f60905b519'))<>2 THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_TARGET_EVIDENCE_FIELDS_CHANGED';
  END IF;

  SELECT md5(coalesce(string_agg(md5(to_jsonb(l)::text),'' ORDER BY l.id::text),''))
  INTO v_other_lesson_hash
  FROM public.school_lesson_records l
  JOIN public.school_legacy_planned_settlement_evidence e
    ON e.planned_lesson_id=l.id
  WHERE l.id NOT IN (
    '8b737b58-cd14-42c5-afd2-34730dcef963',
    '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
  );

  SELECT md5(coalesce(string_agg(md5(to_jsonb(e)::text),''
           ORDER BY e.planned_lesson_id::text),''))
  INTO v_other_evidence_hash
  FROM public.school_legacy_planned_settlement_evidence e
  WHERE e.planned_lesson_id NOT IN (
    '8b737b58-cd14-42c5-afd2-34730dcef963',
    '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
  );

  IF v_other_lesson_hash<>'e7229e67b167b794112ab7a0efa0c946'
     OR v_other_evidence_hash<>'072666dd4191a5009d7f92af680e02fc' THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_OTHER_277_CHANGED';
  END IF;

  IF (SELECT count(*) FROM public.school_list_r1d_e_c_student_month_lessons(
       'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-07') r
      WHERE r.lesson_id IN (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      ) AND r.attribution_class='legacy_planned')<>2
     OR EXISTS (
       SELECT 1 FROM public.school_list_r1d_e_c_student_month_lessons(
         'b17abc58-2f64-4bad-bf20-c9643ead60bc','2026-08') r
       WHERE r.lesson_id IN (
         '8b737b58-cd14-42c5-afd2-34730dcef963',
         '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
       )
     ) THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_READER_COLLECTION_MISMATCH';
  END IF;

  IF (SELECT count(*) FROM public.school_student_tuition_bill_lessons r
      JOIN public.school_student_tuition_bills b ON b.id=r.tuition_bill_id
      WHERE r.planned_lesson_id IN (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
        AND r.relation_role='canonical_charge'
        AND b.id='2a9f1c25-a060-461e-ae10-b02295dec381'
        AND b.billing_month='2026-07'
        AND b.status='income_created'
        AND b.income_record_id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e')<>2 THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_EXISTING_CHARGE_FACT_MISMATCH';
  END IF;

  IF (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.actual_lesson_id::text),''))
      FROM public.school_legacy_actual_settlement_evidence x)
       <>'e685566ddeb27bc9deb8ceb20a272374'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.settlement_snapshot_id::text),''))
         FROM public.school_legacy_settlement_snapshot_basis_evidence x)
       <>'f235ba58a0bac368ad50229e50a97ef7'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.id::text),'')) FROM public.school_student_monthly_settlements x)
       <>'8d40d937d45c64eca0ec0ba7b1c5e65d'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.id::text),'')) FROM public.school_student_tuition_bills x)
       <>'0f0323b79e7ff1c47ff6b90c75477a2d'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.id::text),'')) FROM public.school_income_records x)
       <>'2a4897b752f272b1f192045418b4940c'
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(x)::text),''
         ORDER BY x.id::text),'')) FROM public.school_student_tuition_bill_lessons x)
       <>'285172fedeb923c67ea9a179480d8692' THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_ACTUAL_SNAPSHOT_OR_FINANCIAL_DRIFT';
  END IF;

  SELECT md5(string_agg(l.id::text||':'||l.duration_hours::text||':'||
    l.lesson_fee::text||':'||l.updated_at::text,',' ORDER BY l.id::text))
  INTO v_historical_19_hash
  FROM public.school_lesson_records l
  WHERE l.id IN (
    '14f0ad66-6a72-4562-bdf6-f867f5e7901d','1cb708d2-404b-4fed-a9cb-fb9b974da41c',
    '4645f239-d6f7-473f-96e0-75647cf2b937','4c0214ac-6ce5-4afd-b518-e3d6bd9ab978',
    '555faff7-6658-4860-8277-22f2bc4a9c65','5e0786c6-8b10-4e10-9e84-addaedd5509e',
    '6a3641db-4740-4d95-b1c9-8e3ae77516c2','6e16fea8-c408-421a-adc2-05107f987f5b',
    '714c671d-b98a-464f-afe2-629ed4ba148b','78301f55-e157-4219-8c29-8a87f5a8fa0b',
    '7f468446-13e2-489d-aec5-2b64aeca4f9a','a13b216e-4524-4315-b5aa-c1d2cc053082',
    'a7275d9c-15f1-4829-a78e-fc48b9e88e14','a97f7d25-061d-4504-a47e-53490ba81061',
    'acbc65c8-ba47-4595-b2db-244ae74f83d0','ae53ba74-3cb6-4090-ac7d-d19332dcad9d',
    'b74f743a-0acc-4156-9f00-2d6dfe388ce2','bb4a9aa8-f3dc-4681-a934-e049ff3dce33',
    'eefe54b0-5a01-4836-b1d1-ffcca570447d'
  );

  IF v_historical_19_hash<>'352e72ac33d648a23be84bb27b3580d1'
     OR EXISTS (SELECT 1 FROM public.school_lesson_records l
       WHERE l.id IN (
         '14f0ad66-6a72-4562-bdf6-f867f5e7901d','1cb708d2-404b-4fed-a9cb-fb9b974da41c',
         '4645f239-d6f7-473f-96e0-75647cf2b937','4c0214ac-6ce5-4afd-b518-e3d6bd9ab978',
         '555faff7-6658-4860-8277-22f2bc4a9c65','5e0786c6-8b10-4e10-9e84-addaedd5509e',
         '6a3641db-4740-4d95-b1c9-8e3ae77516c2','6e16fea8-c408-421a-adc2-05107f987f5b',
         '714c671d-b98a-464f-afe2-629ed4ba148b','78301f55-e157-4219-8c29-8a87f5a8fa0b',
         '7f468446-13e2-489d-aec5-2b64aeca4f9a','a13b216e-4524-4315-b5aa-c1d2cc053082',
         'a7275d9c-15f1-4829-a78e-fc48b9e88e14','a97f7d25-061d-4504-a47e-53490ba81061',
         'acbc65c8-ba47-4595-b2db-244ae74f83d0','ae53ba74-3cb6-4090-ac7d-d19332dcad9d',
         'b74f743a-0acc-4156-9f00-2d6dfe388ce2','bb4a9aa8-f3dc-4681-a934-e049ff3dce33',
         'eefe54b0-5a01-4836-b1d1-ffcca570447d'
       ) AND num_nonnulls(student_duration_overage_minutes,
         student_duration_overage_fee_jpy,student_duration_overage_policy_version,
         student_duration_overage_source,student_duration_overage_decided_at)>0) THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_HISTORICAL_19_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'1770f3469dbc3bc030a977381b853deb'
     OR md5(v_stats_definition)<>'f535f4649f870097a350208b64da643e'
     OR position('l.year_month=p_year_month' IN v_stats_definition)=0
     OR position('l.lesson_date>=p_week_start' IN v_stats_definition)=0
     OR position('p_week_start IS NOT NULL' IN v_stats_definition)>0
     OR (SELECT count(*) FROM public.school_feature_gates
         WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
            OR (feature_key='student_tuition_generate' AND state='blocked')
            OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_legacy_planned_settlement_evidence'::regclass
           AND tgname='school_legacy_planned_evidence_row_immutable'
           AND tgenabled='O')<>1
     OR (SELECT relacl::text FROM pg_class
         WHERE oid='public.school_legacy_planned_settlement_evidence'::regclass)
        IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=r/postgres}' THEN
    RAISE EXCEPTION 'R2_C_POSTDEPLOY_R2_B_R0_OR_PROTECTION_DRIFT';
  END IF;

  RAISE NOTICE 'R2_C_POSTDEPLOY_OK';
  RAISE NOTICE 'R2_C_OTHER_277_LESSON_MD5=%',v_other_lesson_hash;
  RAISE NOTICE 'R2_C_OTHER_277_EVIDENCE_MD5=%',v_other_evidence_hash;
  RAISE NOTICE 'R2_C_HISTORICAL_19_MD5=%',v_historical_19_hash;
END
$postdeploy$;

SELECT l.id,l.lesson_date,l.year_month,
  e.legacy_student_settlement_month,
  public.school_resolve_r1d_e_c_lesson_student_month(l.id) AS resolver_month,
  e.lesson_identity_md5,l.updated_at
FROM public.school_lesson_records l
JOIN public.school_legacy_planned_settlement_evidence e
  ON e.planned_lesson_id=l.id
WHERE l.id IN (
  '8b737b58-cd14-42c5-afd2-34730dcef963',
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
)
ORDER BY l.id;

ROLLBACK;
\echo 'R2_C_POSTDEPLOY_READ_ONLY_ROLLED_BACK'
