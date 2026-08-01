-- School V2 2026-08: align atomic idempotency validation with approved carryover authority.
-- Required psql variable: tuition_202608_core_commit=0 rehearsal or 1 deploy.
-- No business row DML. The generate gate must remain blocked during this cutover.

\set ON_ERROR_STOP on
\pset pager off

\if :{?tuition_202608_core_commit}
\else
  \echo 'TUITION_202608_CORE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $cutover$
DECLARE
  v_definition text;
  v_old text:=$old$
       OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='locked_settlement_v1'
            AND (
              v_bill.previous_settlement_id IS NULL
              OR nullif(v_bill.source_snapshot->'carryover_evidence'->>'settlement_id','')::uuid
                   IS DISTINCT FROM v_bill.previous_settlement_id
              OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_status'
                   IS DISTINCT FROM 'locked'
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM v_bill.previous_carryover_cny
            )
          )
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='zero_carryover_verified_v1'
            AND (
              v_bill.previous_settlement_id IS NOT NULL
              OR v_bill.previous_carryover_cny<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'settlement_row_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_bill_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'settlement_income_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_carryover_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'active_adjustment_draft_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'planned_fee_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'received_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'received_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'inherited_carryover_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'adjustment_amount_cny')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_actual_count')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_minutes')::integer<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_fee_jpy')::numeric<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'duration_overage_fee_cny')::numeric<>0
            )
          )
       OR coalesce(v_bill.source_snapshot->'carryover_evidence'->>'mode','')
            NOT IN ('locked_settlement_v1','zero_carryover_verified_v1')
$old$;
  v_new text:=$new$
       OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR v_bill.source_snapshot->'carryover_evidence'->>'authority'
            IS DISTINCT FROM 'locked_previous_settlement_only'
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='locked_settlement_v1'
            AND (
              v_bill.previous_settlement_id IS NULL
              OR nullif(v_bill.source_snapshot->'carryover_evidence'->>'settlement_id','')::uuid
                   IS DISTINCT FROM v_bill.previous_settlement_id
              OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_status'
                   IS DISTINCT FROM 'locked'
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM v_bill.previous_carryover_cny
            )
          )
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='zero_carryover_verified_v1'
            AND (
              v_bill.previous_settlement_id IS NOT NULL
              OR v_bill.previous_carryover_cny<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'locked_settlement_count')::integer
                   IS DISTINCT FROM 0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM 0
            )
          )
       OR coalesce(v_bill.source_snapshot->'carryover_evidence'->>'mode','')
            NOT IN ('locked_settlement_v1','zero_carryover_verified_v1')
$new$;
BEGIN
  IF (SELECT count(*) FROM public.school_feature_gates
      WHERE (feature_key='student_tuition_preview' AND state='enabled')
         OR (feature_key='student_tuition_generate' AND state='blocked')
         OR (feature_key='student_tuition_cash_submit' AND state='blocked'))<>3 THEN
    RAISE EXCEPTION 'TUITION_202608_CORE_GATE_BASELINE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'c6bd995a4703306d049ea30a9fb2ae17' THEN
    RAISE EXCEPTION 'TUITION_202608_CORE_SOURCE_DRIFT';
  END IF;
  SELECT pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'TUITION_202608_CORE_OLD_CONTRACT_NOT_FOUND';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);
  IF position(v_old IN v_definition)>0
     OR position(v_new IN v_definition)=0 THEN
    RAISE EXCEPTION 'TUITION_202608_CORE_CONTRACT_REPLACE_FAILED';
  END IF;
  EXECUTE v_definition;
END
$cutover$;

DO $verify$
DECLARE v_definition text;
BEGIN
  v_definition:=pg_get_functiondef(
    'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
  );
  IF position('locked_previous_settlement_only' IN v_definition)=0
     OR position('locked_settlement_count' IN v_definition)=0
     OR position('active_adjustment_draft_count' IN v_definition)>0
     OR position('duration_overage_fee_cny' IN v_definition)>0 THEN
    RAISE EXCEPTION 'TUITION_202608_CORE_AUTHORITY_VERIFY_FAILED';
  END IF;
END
$verify$;

SELECT md5(pg_get_functiondef(
  'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
)) AS target_atomic_core_definition_md5;

\if :tuition_202608_core_commit
  COMMIT;
  \echo 'TUITION_202608_CORE_DEPLOYED'
\else
  ROLLBACK;
  \echo 'TUITION_202608_CORE_REHEARSAL_ROLLED_BACK'
\endif
