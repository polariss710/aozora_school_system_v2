-- School V2 R2-F-E1 exact whitelist cleanup for the business-owner UI test.
-- Only removes the exact trailing text "123" from one authorized actual note.
-- updated_at is left to the existing trigger and is never forged.
-- Usage:
--   r2_f_e1_note_commit=0  rehearsal with explicit ROLLBACK
--   r2_f_e1_note_commit=1  formal one-row DML with explicit COMMIT

\set ON_ERROR_STOP on
\pset pager off

\if :{?r2_f_e1_note_commit}
\else
  \echo 'R2_F_E1_NOTE_COMMIT_VARIABLE_REQUIRED'
  \quit 3
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';

DO $cleanup$
DECLARE
  v_id constant uuid:='a1977f69-69d7-45d5-a958-50138d3f80d4';
  v_before jsonb;
  v_after jsonb;
  v_updated integer;
BEGIN
  SELECT to_jsonb(actual)-ARRAY['note','updated_at']
  INTO STRICT v_before
  FROM public.school_lesson_records actual
  WHERE actual.id=v_id
    AND actual.app_type='school'
    AND actual.lesson_type='actual'
    AND actual.student_id='7aef8061-7037-4881-a847-a2cdb031c0f4'
    AND actual.planned_lesson_id='421484ba-a1f8-4210-a9bc-ab40da0c1ece'
    AND actual.year_month='2026-07'
    AND right(actual.note,3)='123'
  FOR UPDATE;

  UPDATE public.school_lesson_records actual
  SET note=left(actual.note,length(actual.note)-3)
  WHERE actual.id=v_id
    AND right(actual.note,3)='123';
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  IF v_updated<>1 THEN
    RAISE EXCEPTION 'R2_F_E1_NOTE_CLEANUP_ROW_COUNT_FAILED';
  END IF;

  SELECT to_jsonb(actual)-ARRAY['note','updated_at']
  INTO STRICT v_after
  FROM public.school_lesson_records actual
  WHERE actual.id=v_id;
  IF v_after IS DISTINCT FROM v_before
     OR (SELECT right(actual.note,3)='123'
         FROM public.school_lesson_records actual WHERE actual.id=v_id)
     OR public.school_resolve_r1d_e_c_lesson_student_month(v_id)<>'2026-07' THEN
    RAISE EXCEPTION 'R2_F_E1_NOTE_CLEANUP_SCOPE_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview'
             AND state='validation_preview_only')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'R2_F_E1_NOTE_CLEANUP_R0_FAILED';
  END IF;
END
$cleanup$;

SELECT id,note,updated_at,
  public.school_resolve_r1d_e_c_lesson_student_month(id) AS resolved_month
FROM public.school_lesson_records
WHERE id='a1977f69-69d7-45d5-a958-50138d3f80d4';

\if :r2_f_e1_note_commit
  COMMIT;
  \echo 'R2_F_E1_WHITELIST_NOTE_CLEANUP_COMMITTED'
\else
  ROLLBACK;
  \echo 'R2_F_E1_WHITELIST_NOTE_CLEANUP_ROLLED_BACK'
\endif
