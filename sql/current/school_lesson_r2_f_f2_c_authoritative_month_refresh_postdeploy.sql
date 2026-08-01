-- School V2 R2-F-F2-C read-only postdeploy acceptance.
\set ON_ERROR_STOP on
\pset pager off

BEGIN READ ONLY;
SET LOCAL statement_timeout='180s';

DO $assertions$
DECLARE
  v_target constant uuid:='300751ba-2ea5-41f0-97dd-45251af8e9d1';
  v_cross_month constant uuid:='aa55dc2e-3b1b-4d2d-863f-9f64e84b8578';
  v_definition text := pg_get_functiondef(
    'public.school_get_lesson_management_stats_filtered(text,uuid,uuid,uuid,text,text,uuid,boolean,text,date)'::regprocedure
  );
BEGIN
  IF position('public.school_resolve_r1d_e_c_lesson_student_month(' IN
       v_definition)>0
     OR (length(v_definition)-length(replace(
       v_definition,
       'public.school_resolve_lesson_student_month_authoritative(',''
     )))/length('public.school_resolve_lesson_student_month_authoritative(')<>2 THEN
    RAISE EXCEPTION 'R2_F_F2_C_FILTERED_STATS_RESOLVER_CONTRACT_FAILED';
  END IF;
  IF public.school_resolve_lesson_student_month_authoritative(v_target)
       <>'2026-08'
     OR NOT EXISTS (
       SELECT 1
       FROM public.school_list_r1d_e_c_student_month_lessons(NULL,'2026-08') r
       WHERE r.lesson_id=v_target AND r.attribution_class='legacy_planned'
         AND r.authoritative_student_month='2026-08'
     ) THEN
    RAISE EXCEPTION 'R2_F_F2_C_TARGET_AUTHORITY_FAILED';
  END IF;
  IF (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-08',NULL
      ) lesson WHERE lesson.id=v_target)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-09',NULL
      ) lesson WHERE lesson.id=v_target)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_C_TARGET_READER_SCOPE_FAILED';
  END IF;
  IF (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-08',NULL
      ) lesson WHERE lesson.id=v_cross_month)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-08',DATE '2026-08-31'
      ) lesson WHERE lesson.id=v_cross_month)<>1
     OR (SELECT count(*) FROM
      public.school_list_lesson_management_records_authoritative(
        '2026-09',NULL
      ) lesson WHERE lesson.id=v_cross_month)<>0 THEN
    RAISE EXCEPTION 'R2_F_F2_C_CROSS_MONTH_SCOPE_FAILED';
  END IF;
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_F2_C_GATE_DRIFT';
  END IF;
END
$assertions$;

SET LOCAL ROLE authenticated;

DO $authenticated_stats$
DECLARE
  v_august_count bigint;
  v_september_count bigint;
  v_august_reader_count bigint;
  v_september_reader_count bigint;
BEGIN
  SELECT stats.record_count INTO STRICT v_august_count
  FROM public.school_get_lesson_management_stats_filtered(
    '2026-08',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
  ) stats;
  SELECT stats.record_count INTO STRICT v_september_count
  FROM public.school_get_lesson_management_stats_filtered(
    '2026-09',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
  ) stats;
  SELECT count(*) INTO STRICT v_august_reader_count
  FROM public.school_list_lesson_management_records_authoritative(
    '2026-08',NULL
  );
  SELECT count(*) INTO STRICT v_september_reader_count
  FROM public.school_list_lesson_management_records_authoritative(
    '2026-09',NULL
  );
  IF v_august_count<>v_august_reader_count
     OR v_september_count<>v_september_reader_count THEN
    RAISE EXCEPTION 'R2_F_F2_C_AUTHENTICATED_STATS_SCOPE: % / %',
      v_august_count,v_september_count;
  END IF;
END
$authenticated_stats$;

RESET ROLE;

SELECT feature_key,state
FROM public.school_feature_gates
WHERE feature_key IN (
  'student_tuition_preview','student_tuition_generate',
  'student_tuition_cash_submit'
)
ORDER BY feature_key;

COMMIT;
