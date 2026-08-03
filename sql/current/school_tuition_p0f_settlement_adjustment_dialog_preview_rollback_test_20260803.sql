\set ON_ERROR_STOP on
begin read only;
set local role anon;

select
  result->>'contract_version' as contract_version,
  result->'current_state'->>'is_saved' as current_is_saved,
  result->'preview'->>'pending_makeup_hours' as pending_makeup_hours,
  result->'preview'->>'overage_hours' as overage_hours,
  result->'preview'->>'lesson_variance_display_hours' as net_hours,
  result->'preview'->>'unused_planned_credit_jpy' as unused_jpy,
  result->'preview'->>'overage_charge_jpy' as overage_jpy,
  result->'preview'->>'net_lesson_variance_jpy' as net_jpy,
  result->'preview'->>'net_lesson_variance_cny' as net_cny,
  result->'preview'->>'system_difference_cny' as system_difference_cny,
  result->'preview'->>'projected_final_carryover_cny' as projected_final_carryover_cny,
  jsonb_array_length(result->'preview'->'source_lines') as source_count,
  length(result->>'preview_manifest_sha256') as preview_manifest_length
from (
  select public.school_preview_student_settlement_adjustment_dialog(
    'eb705aad-de4d-45e6-a391-42dcdd89aeda'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-07','net_lesson_variance_to_financial_credit_v1',0.042,
    'business_owner_confirmed_monthly_settlement_rate_v1','2026-07-01'::date,
    'carry_final_balance',null
  ) result
) q;

rollback;
