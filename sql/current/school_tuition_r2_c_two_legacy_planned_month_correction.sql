-- School V2 tuition P0 R2-C: exact two-row legacy planned month correction.
-- Required psql variable: r2_c_commit=0 for rollback rehearsal, 1 for deploy.
-- Only the two approved legacy planned lessons and their immutable evidence rows
-- are corrected from 2026-08 to 2026-07. No billing attribution bundle is added.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_c_commit}
\else
  \echo 'R2_C_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

LOCK TABLE public.school_legacy_planned_settlement_evidence
  IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.school_lesson_records
  IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
DECLARE
  v_other_lesson_hash text;
  v_other_evidence_hash text;
BEGIN
  IF (SELECT count(*) FROM public.school_lesson_records) <> 652
     OR (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence) <> 279
     OR (SELECT count(*) FROM public.school_legacy_actual_settlement_evidence) <> 234
     OR (SELECT count(*) FROM public.school_student_monthly_settlements) <> 15
     OR (SELECT count(*) FROM public.school_student_tuition_bills) <> 9
     OR (SELECT count(*) FROM public.school_income_records) <> 42
     OR (SELECT count(*) FROM public.school_student_tuition_bill_lessons) <> 121 THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_FIXED_COUNT_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1770f3469dbc3bc030a977381b853deb'
     OR md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) <> '8de65e9787d8d66f2cd7b65eb2479a8c'
     OR md5(pg_get_functiondef(
       'public.school_list_r1d_e_c_student_month_lessons(uuid,text)'::regprocedure
     )) <> '155e831118acbeadfd04b6640324c7cd' THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_READER_OR_R2_B_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked')) <> 3 THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_R0_DRIFT';
  END IF;

  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.school_legacy_planned_settlement_evidence'::regclass
        AND tgname='school_legacy_planned_evidence_row_immutable'
        AND tgenabled='O') <> 1
     OR (SELECT relacl::text FROM pg_class
         WHERE oid='public.school_legacy_planned_settlement_evidence'::regclass)
        IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=r/postgres}' THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_EVIDENCE_PROTECTION_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.school_lesson_records l
      WHERE (l.id='8b737b58-cd14-42c5-afd2-34730dcef963'
             AND md5(to_jsonb(l)::text)='a3a1fd3d7ca7ec9f8ef9ea3cc3f25c9d')
         OR (l.id='685ad45e-b5da-42ca-8f43-7732e8d6e40d'
             AND md5(to_jsonb(l)::text)='b7c4c0c148676390f48668e17779af72')) <> 2 THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_TARGET_LESSON_IDENTITY_DRIFT';
  END IF;

  IF (SELECT count(*)
      FROM public.school_legacy_planned_settlement_evidence e
      WHERE (e.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'
             AND md5(to_jsonb(e)::text)='e149c755dc6d2f04a2692ebf5c2c4a27')
         OR (e.planned_lesson_id='685ad45e-b5da-42ca-8f43-7732e8d6e40d'
             AND md5(to_jsonb(e)::text)='86a6e44c04a415daa971d5ceecfb7877')) <> 2 THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_TARGET_EVIDENCE_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_lesson_records l
    JOIN public.school_legacy_planned_settlement_evidence e
      ON e.planned_lesson_id=l.id
    WHERE l.id IN (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
      AND (l.lesson_type<>'planned' OR l.app_type<>'school'
        OR l.year_month<>'2026-08'
        OR l.lesson_date NOT IN (DATE '2026-08-01',DATE '2026-08-02')
        OR num_nonnulls(l.billing_month,l.billing_week_start_date,
             l.student_settlement_month,l.billing_month_source,
             l.billing_month_decided_at)<>0
        OR e.legacy_student_settlement_month<>'2026-08'
        OR e.approved_manifest IS DISTINCT FROM true
        OR e.evidence_source<>'r1d_e_b1_fixed_legacy_279'
        OR e.evidence_version<>'legacy_settlement_evidence_v1'
        OR public.school_resolve_r1d_e_c_lesson_student_month(l.id)<>'2026-08')
  ) THEN
    RAISE EXCEPTION 'R2_C_PREFLIGHT_TARGET_STRUCTURE_MISMATCH';
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
    RAISE EXCEPTION 'R2_C_PREFLIGHT_OTHER_277_DRIFT';
  END IF;
END
$preflight$;

ALTER TABLE public.school_legacy_planned_settlement_evidence
  DISABLE TRIGGER school_legacy_planned_evidence_row_immutable;

DO $correct_evidence$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.school_legacy_planned_settlement_evidence e
  SET legacy_student_settlement_month='2026-07',
      lesson_identity_md5=CASE e.planned_lesson_id
        WHEN '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
          THEN '0a287ea42649e517879295c772aed039'
        WHEN '685ad45e-b5da-42ca-8f43-7732e8d6e40d'::uuid
          THEN '9efda43df96dfb1a36f0e461fab173e6'
      END
  WHERE e.planned_lesson_id IN (
    '8b737b58-cd14-42c5-afd2-34730dcef963',
    '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
  )
    AND e.legacy_student_settlement_month='2026-08'
    AND e.approved_manifest=true
    AND e.evidence_source='r1d_e_b1_fixed_legacy_279'
    AND e.evidence_version='legacy_settlement_evidence_v1';
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>2 THEN
    RAISE EXCEPTION 'R2_C_EVIDENCE_ROW_COUNT_MISMATCH:%',v_rows;
  END IF;
END
$correct_evidence$;

ALTER TABLE public.school_legacy_planned_settlement_evidence
  ENABLE TRIGGER school_legacy_planned_evidence_row_immutable;

DO $correct_lessons$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.school_lesson_records l
  SET year_month='2026-07'
  WHERE l.id IN (
    '8b737b58-cd14-42c5-afd2-34730dcef963',
    '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
  )
    AND l.lesson_type='planned'
    AND l.app_type='school'
    AND l.year_month='2026-08'
    AND num_nonnulls(l.billing_month,l.billing_week_start_date,
          l.student_settlement_month,l.billing_month_source,
          l.billing_month_decided_at)=0;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>2 THEN
    RAISE EXCEPTION 'R2_C_LESSON_ROW_COUNT_MISMATCH:%',v_rows;
  END IF;
END
$correct_lessons$;

DO $verify$
DECLARE
  v_other_lesson_hash text;
  v_other_evidence_hash text;
BEGIN
  IF (SELECT count(*) FROM public.school_legacy_planned_settlement_evidence)<>279
     OR (SELECT count(*) FROM public.school_lesson_records l
         JOIN public.school_legacy_planned_settlement_evidence e
           ON e.planned_lesson_id=l.id
         WHERE l.id IN (
           '8b737b58-cd14-42c5-afd2-34730dcef963',
           '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
         )
           AND l.year_month='2026-07'
           AND e.legacy_student_settlement_month='2026-07'
           AND e.lesson_identity_md5=md5(concat_ws('|',l.id::text,
             coalesce(l.student_id::text,'<NULL>'),
             coalesce(l.business_entity_id::text,'<NULL>'),
             coalesce(l.year_month,'<NULL>'),l.lesson_type,l.app_type))
           AND public.school_resolve_r1d_e_c_lesson_student_month(l.id)='2026-07')<>2 THEN
    RAISE EXCEPTION 'R2_C_VERIFY_TARGET_CORRECTION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_lesson_records l
    WHERE l.id IN (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
      AND (l.lesson_date NOT IN (DATE '2026-08-01',DATE '2026-08-02')
        OR num_nonnulls(l.billing_month,l.billing_week_start_date,
             l.student_settlement_month,l.billing_month_source,
             l.billing_month_decided_at)<>0)
  ) THEN
    RAISE EXCEPTION 'R2_C_VERIFY_LESSON_DATE_OR_LEGACY_BUNDLE_CHANGED';
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
     OR v_other_evidence_hash<>'072666dd4191a5009d7f92af680e02fc'
     OR (SELECT count(*) FROM pg_trigger
         WHERE tgrelid='public.school_legacy_planned_settlement_evidence'::regclass
           AND tgname='school_legacy_planned_evidence_row_immutable'
           AND tgenabled='O')<>1
     OR (SELECT relacl::text FROM pg_class
         WHERE oid='public.school_legacy_planned_settlement_evidence'::regclass)
        IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=r/postgres}' THEN
    RAISE EXCEPTION 'R2_C_VERIFY_OTHER_277_OR_PROTECTION_CHANGED';
  END IF;

  IF md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     ))<>'1770f3469dbc3bc030a977381b853deb'
     OR (SELECT count(*) FROM public.school_feature_gates
         WHERE (feature_key='student_tuition_preview' AND state='validation_preview_only')
            OR (feature_key='student_tuition_generate' AND state='blocked')
            OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_C_VERIFY_R2_B_OR_R0_CHANGED';
  END IF;

  RAISE NOTICE 'R2_C_CORRECTED_LESSONS=2';
  RAISE NOTICE 'R2_C_CORRECTED_EVIDENCE=2';
  RAISE NOTICE 'R2_C_OTHER_277_LESSON_MD5=%',v_other_lesson_hash;
  RAISE NOTICE 'R2_C_OTHER_277_EVIDENCE_MD5=%',v_other_evidence_hash;
END
$verify$;

SELECT l.id,l.lesson_date,l.year_month,
  e.legacy_student_settlement_month,e.lesson_identity_md5,
  public.school_resolve_r1d_e_c_lesson_student_month(l.id) AS resolver_month,
  l.updated_at
FROM public.school_lesson_records l
JOIN public.school_legacy_planned_settlement_evidence e
  ON e.planned_lesson_id=l.id
WHERE l.id IN (
  '8b737b58-cd14-42c5-afd2-34730dcef963',
  '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
)
ORDER BY l.id;

\if :r2_c_commit
  COMMIT;
  \echo 'R2_C_CORRECTIVE_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_C_CORRECTIVE_REHEARSAL_ROLLED_BACK'
\endif
