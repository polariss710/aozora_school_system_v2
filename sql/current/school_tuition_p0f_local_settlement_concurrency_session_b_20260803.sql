\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='20s';
set local statement_timeout='45s';
set local request.jwt.claims='{"role":"service_role"}';
do $session_b$
declare
  v_student constant uuid := 'f0f40000-0000-4000-8000-00000000a001';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_preview jsonb;
  v_result jsonb;
  v_start timestamptz := clock_timestamp();
  v_elapsed numeric;
begin
  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    v_student,v_entity,'2021-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2021-07-01','carry_final_balance',null
  );
  v_result := public.school_save_student_settlement_draft_local(
    v_student,v_entity,'2021-07','net_lesson_variance_to_financial_credit_v1',
    0.042,'codex_test_confirmed_rate_v1','2021-07-01','carry_final_balance',null,
    v_preview->>'preview_manifest_sha256',
    v_preview->'preview_expected_facts'->>'lesson_variance_manifest_sha256',
    (v_preview->'preview'->>'lesson_variance_source_count')::integer,
    (v_preview->'preview'->>'unused_planned_credit_jpy')::numeric,
    (v_preview->'preview'->>'overage_charge_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_jpy')::numeric,
    (v_preview->'preview'->>'net_lesson_variance_cny')::numeric,
    (v_preview->'preview_expected_facts'->>'system_difference_cny')::numeric,
    (v_preview->'preview'->>'projected_final_carryover_cny')::numeric,
    'codex-test tuition-p0f-local-tool-20260803',null,
    'local_trusted_business_owner_v1',format(
      'SAVE STUDENT SETTLEMENT DRAFT %s %s MANIFEST %s',
      v_student,'2021-07',v_preview->>'preview_manifest_sha256'
    )
  );
  v_elapsed := extract(epoch from clock_timestamp()-v_start);
  if v_elapsed < 2 then
    raise exception 'P0F_LOCAL_EXPECTED_BLOCKING_MISSING: elapsed=%',v_elapsed;
  end if;
  raise notice 'P0F_LOCAL_SESSION_B_BLOCKED_THEN_COMPLETED elapsed=% result=% pid=%',
    v_elapsed,v_result,pg_backend_pid();
end
$session_b$;
rollback;
\echo 'P0F_LOCAL_SESSION_B_ROLLED_BACK'
