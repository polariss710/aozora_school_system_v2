import assert from "node:assert/strict";
import { LessonClearanceWorkspaceState } from "../js/utils/lesson-clearance-state.js";

const pending = {
  pending_source_planned_id: "10000000-0000-4000-8000-000000000001",
  student_id: "student-1", business_entity_id: "entity-1", source_row_md5: "pending-md5",
  fifo_rank: 1, can_be_candidate: true, remaining_minutes: 60,
};
const overage = {
  overtime_source_actual_id: "20000000-0000-4000-8000-000000000001",
  student_id: "student-1", business_entity_id: "entity-1", source_row_md5: "overage-md5",
  display_rank: 1, can_be_candidate: true, available_minutes: 60,
};

function readyState(role = "admin") {
  const state = new LessonClearanceWorkspaceState({ role });
  state.setData({ pendingPayload: { items: [pending] }, overagePayload: { items: [overage] }, packagePayload: { items: [{ package_lot_id: "P002", can_consume: false }] }, crossMonthPayload: { items: [] }, summary: {}, history: [] });
  if (role === "read_only") return state;
  state.selectPending(pending.pending_source_planned_id);
  state.selectOvertime(overage.overtime_source_actual_id);
  state.setPreviewInput("allocatedMinutes", "60");
  state.setPreviewInput("operationDate", "2026-08-18");
  state.setPreviewInput("businessNote", "A3状态机清偿说明");
  const request = state.previewRequest();
  const preview = {
    request_identity: request.requestIdentity, clearance_type: "overtime_offset", requested_minutes: 60,
    operation_date: "2026-08-18", preview_manifest_sha256: "a".repeat(64), writer_revalidation_required: true,
    reservation_created: false,
    pending_source: { planned_id: pending.pending_source_planned_id, student_id: "student-1", before_remaining_minutes: 60, after_remaining_minutes: 0, active_claimed: false },
    overtime_source: { actual_id: overage.overtime_source_actual_id, student_id: "student-1", before_available_minutes: 60, after_available_minutes: 0, active_claimed: false },
    comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: true, same_subject: true },
    fifo: { recommended_pending_planned_id: pending.pending_source_planned_id, is_recommended_target: true, deviation_required: false, deviation_reason_valid: true },
    financial: { requires_forward_adjustment: false }, authorization: { can_execute_for_current_actor: true },
    source_versions: { pending_row_md5: pending.source_row_md5, overtime_row_md5: overage.source_row_md5 },
  };
  assert.equal(state.acceptPreview(preview, request), true);
  return state;
}

const state = readyState();
const result = {
  clearance_id: "30000000-0000-4000-8000-000000000001",
  pending_remaining_minutes: 0, overtime_remaining_minutes: 0,
  requires_forward_adjustment: false,
  recommended_pending_source_id: pending.pending_source_planned_id,
  deviated_from_recommendation: false, idempotent_replay: false,
};
assert.equal(state.createResultMatchesSnapshot(result), true);
assert.equal(state.createResultMatchesSnapshot({ ...result, overtime_remaining_minutes: 1 }), false);
assert.equal(state.createResultMatchesSnapshot({ ...result, idempotent_replay: "false" }), false);

const snapshot = state.selection.previewInputSnapshot;
const history = {
  clearance_id: result.clearance_id, clearance_type: snapshot.clearanceType,
  request_identity: snapshot.requestIdentity, idempotency_key: snapshot.requestIdentity,
  pending_source_planned_id: snapshot.pendingSourcePlannedId,
  overtime_source_actual_id: snapshot.overtimeSourceActualId,
  allocated_minutes: snapshot.allocatedMinutes, operation_date: snapshot.operationDate,
  business_note: snapshot.businessNote, input_manifest_sha256: "b".repeat(64),
  is_effective: true, is_reversed: false,
};
assert.equal(state.historyMatchesCreateSnapshot(history, result.clearance_id), true);
assert.equal(state.historyMatchesCreateSnapshot({ ...history, allocated_minutes: 45 }, result.clearance_id), false);
assert.equal(state.historyMatchesCreateSnapshot({ ...history, input_manifest_sha256: snapshot.manifest }, result.clearance_id), true, "preview and persisted manifests are independently bound and may be different or equal");
assert.equal(state.historyMatchesCreateSnapshot({ ...history, business_note: "其他说明" }, result.clearance_id), false);
assert.equal(state.historyMatchesCreateSnapshot({ ...history, request_identity: "other", idempotency_key: "other" }, result.clearance_id), false);

const originalIdentity = state.selection.requestIdentity;
state.rejectCreate("待补对象当前余额不足，请重新加载。", "P0001");
assert.equal(state.selection.preview, null);
assert.equal(state.selection.previewInputSnapshot, null);
assert.notEqual(state.selection.requestIdentity, originalIdentity);
assert.equal(state.selection.previewError, "待补对象当前余额不足，请重新加载。");

const dateMissing = new LessonClearanceWorkspaceState({ role: "admin" });
dateMissing.setData({ pendingPayload: { items: [pending] }, overagePayload: { items: [overage] }, packagePayload: { items: [] }, crossMonthPayload: { items: [] }, summary: {}, history: [] });
dateMissing.selectPending(pending.pending_source_planned_id);
dateMissing.selectOvertime(overage.overtime_source_actual_id);
dateMissing.setPreviewInput("allocatedMinutes", "60");
dateMissing.setPreviewInput("operationDate", "");
dateMissing.setPreviewInput("businessNote", "说明");
assert.equal(dateMissing.previewValidationMessage(), "请选择清偿日期。");
dateMissing.setPreviewInput("operationDate", "2026-08-18");
dateMissing.setPreviewInput("businessNote", "");
assert.equal(dateMissing.previewValidationMessage(), "请填写业务说明。");
dateMissing.setPreviewInput("businessNote", "说明");
dateMissing.setPreviewInput("allocatedMinutes", "0");
assert.match(dateMissing.previewValidationMessage(), /大于0的整数分钟/);

assert.equal(readyState("operator").prepareValidationMessage(), "");
assert.match(readyState("read_only").previewValidationMessage(), /只能查看/);
assert.equal(readyState().selectPending("P002"), false);

console.log("SCHOOL_PHASE2C_D2_A3_CLEARANCE_COMPLETION_STATE_PASS");
