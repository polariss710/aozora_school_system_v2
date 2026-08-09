import {
  handleSettlementOnlineRequest,
  parseLockSettlementRequest,
  type LockSettlementRequest,
} from "../_shared/student-settlement-online-contract.ts";
import { createSettlementOnlineDependencies } from "../_shared/student-settlement-online-runtime.ts";

const dependencies = createSettlementOnlineDependencies<LockSettlementRequest>(
  "school_lock_student_monthly_settlement_online_admin",
  (actorUserId, input) => ({
    p_actor_user_id: actorUserId,
    p_student_id: input.student_id,
    p_year_month: input.settlement_month,
    p_expected_source_treatment_draft_id:
      input.expected_source_treatment_draft_id,
    p_expected_source_treatment_draft_updated_at:
      input.expected_source_treatment_draft_updated_at,
    p_expected_adjustment_draft_id: input.expected_adjustment_draft_id,
    p_expected_adjustment_draft_updated_at:
      input.expected_adjustment_draft_updated_at,
    p_expected_preview_manifest_sha256:
      input.expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256:
      input.expected_lesson_variance_manifest_sha256,
    p_expected_source_count: input.expected_source_count,
    p_expected_unused_planned_credit_jpy:
      input.expected_unused_planned_credit_jpy,
    p_expected_overage_charge_jpy: input.expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy:
      input.expected_net_lesson_variance_jpy,
    p_expected_net_lesson_variance_cny:
      input.expected_net_lesson_variance_cny,
    p_expected_system_difference_cny: input.expected_system_difference_cny,
    p_expected_final_carryover_cny: input.expected_final_carryover_cny,
    p_note: input.note,
    p_request_correlation_id: input.client_correlation_id,
  }),
);

Deno.serve((request) => handleSettlementOnlineRequest(request, {
  edgeName: "lock-student-settlement",
  action: "lock",
  parseBody: parseLockSettlementRequest,
  dependencies,
}));
