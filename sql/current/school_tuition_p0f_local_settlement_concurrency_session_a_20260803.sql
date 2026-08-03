\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='20s';
set local statement_timeout='45s';
set local request.jwt.claims='{"role":"service_role"}';
do $session_a$
declare
  v_student constant uuid := 'f0f40000-0000-4000-8000-00000000a001';
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_preview jsonb;
  v_result jsonb;
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
  raise notice 'P0F_LOCAL_SESSION_A_LOCKED result=% pid=%',v_result,pg_backend_pid();
  perform pg_sleep(12);
end
$session_a$;
rollback;
\echo 'P0F_LOCAL_SESSION_A_ROLLED_BACK'
