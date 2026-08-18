import assert from "node:assert/strict";
import {
  LessonClearanceWorkspaceState,
  lessonClearanceCapabilities,
} from "../js/utils/lesson-clearance-state.js";

const pending = (id, overrides = {}) => ({
  pending_source_planned_id: id,
  student_id: "student-1",
  business_entity_id: "entity-1",
  source_year_month: "2026-08",
  source_row_md5: `pending-${id}`,
  fifo_rank: 1,
  can_be_candidate: true,
  active_claimed: false,
  is_locked: false,
  ...overrides,
});

const overage = (id, overrides = {}) => ({
  overtime_source_actual_id: id,
  student_id: "student-1",
  business_entity_id: "entity-1",
  student_settlement_month: "2026-08",
  source_row_md5: `overage-${id}`,
  display_rank: 1,
  can_be_candidate: true,
  active_claimed: false,
  is_locked: false,
  ...overrides,
});

function makeState(role = "admin", history = []) {
  const state = new LessonClearanceWorkspaceState({ role });
  state.setData({
    pendingPayload: { items: [
      pending("pending-fifo"),
      pending("pending-other", { fifo_rank: 2 }),
      pending("pending-claimed", { active_claimed: true, can_be_candidate: false }),
    ] },
    overagePayload: { items: [overage("overage-1"), overage("overage-locked", { is_locked: true })] },
    packagePayload: { items: [{ package_lot_id: "P002", can_consume: false, read_only: true }] },
    crossMonthPayload: { items: [] },
    summary: {},
    history,
  });
  return state;
}

function selectBase(state, pendingId = "pending-fifo", overtimeId = "overage-1") {
  assert.equal(state.selectPending(pendingId), true);
  assert.equal(state.selectOvertime(overtimeId), true);
  state.setPreviewInput("allocatedMinutes", "60");
  state.setPreviewInput("businessNote", "状态机测试业务说明");
}

function previewFor(state, overrides = {}) {
  const pendingRow = state.selectedPending();
  const overageRow = state.selectedOverage();
  return {
    contract_version: "lesson_clearance_preview_v2",
    request_identity: state.selection.requestIdentity,
    idempotency_key: state.selection.requestIdentity,
    clearance_type: state.selection.clearanceType,
    requested_minutes: Number(state.selection.allocatedMinutes),
    operation_date: state.selection.operationDate,
    preview_manifest_sha256: "manifest-0123456789",
    writer_revalidation_required: true,
    reservation_created: false,
    pending_source: {
      planned_id: state.selection.pendingId,
      student_id: "student-1",
      before_remaining_minutes: 120,
      after_remaining_minutes: 60,
      active_claimed: false,
      source_locked: pendingRow.is_locked,
    },
    overtime_source: {
      actual_id: state.selection.overtimeId,
      student_id: "student-1",
      before_available_minutes: 60,
      after_available_minutes: 0,
      active_claimed: false,
      source_locked: overageRow.is_locked,
    },
    comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: true, same_subject: true },
    fifo: { is_recommended_target: pendingRow.fifo_rank === 1, deviation_required: pendingRow.fifo_rank !== 1, deviation_reason_valid: true },
    financial: { requires_forward_adjustment: false },
    authorization: { can_execute_for_current_actor: true, blocker_code: null },
    source_versions: { pending_row_md5: pendingRow.source_row_md5, overtime_row_md5: overageRow.source_row_md5 },
    ...overrides,
  };
}

function acceptStatePreview(state, overrides = {}) {
  const request = state.previewRequest();
  return state.acceptPreview(previewFor(state, overrides), request);
}

assert.equal(lessonClearanceCapabilities("admin").create, true);
assert.equal(lessonClearanceCapabilities("admin").reverse, true);
assert.equal(lessonClearanceCapabilities("operator").create, true);
assert.equal(lessonClearanceCapabilities("operator").reverse, false);
assert.equal(lessonClearanceCapabilities("read_only").select, false);

const state = makeState();
assert.equal(state.selection.pendingId, "", "FIFO recommendation is never preselected");
assert.equal(state.selection.overtimeId, "", "overage is never preselected");
assert.equal(state.selectPending("P002"), false, "package lot cannot enter ordinary clearance selection");
selectBase(state);
const identity1 = state.selection.requestIdentity;
assert.match(identity1, /^[0-9a-f-]{36}$/i);
assert.match(state.prepareValidationMessage(), /重新核对/);
const request1 = state.previewRequest();
const request2 = state.previewRequest();
assert.equal(request1.requestIdentity, request2.requestIdentity, "same Preview input reuses request identity");
assert.equal(state.acceptPreview(previewFor(state), request1), true);
assert.equal(state.prepareValidationMessage(), "");
assert.equal(state.writerRequest().requestIdentity, identity1);
assert.equal(state.selection.previewInputSnapshot.businessNote, request1.businessNote);
assert.equal(state.selection.previewInputSnapshot.requestIdentity, request1.requestIdentity);
assert.equal(state.selection.previewInputSnapshot.manifest, "manifest-0123456789");
assert.equal(state.writerRequest().businessNote, request1.businessNote, "writer payload reads the Preview input snapshot");

state.setPreviewInput("businessNote", "改变业务备注");
assert.equal(state.selection.preview, null);
assert.equal(state.selection.previewInputSnapshot, null);
assert.notEqual(state.selection.requestIdentity, identity1);

const directMutationState = makeState();
selectBase(directMutationState);
assert.equal(acceptStatePreview(directMutationState), true);
const directMutationIdentity = directMutationState.selection.requestIdentity;
directMutationState.selection.businessNote = "绕过事件修改的当前表单值";
assert.match(directMutationState.prepareValidationMessage(), /重新核对/);
assert.throws(() => directMutationState.writerRequest(), /重新核对/);
assert.equal(directMutationState.selection.previewInputSnapshot.businessNote, "状态机测试业务说明");
assert.equal(directMutationState.selection.previewInputSnapshot.requestIdentity, directMutationIdentity);

const missingNoteSnapshotState = makeState();
selectBase(missingNoteSnapshotState);
assert.equal(acceptStatePreview(missingNoteSnapshotState), true);
missingNoteSnapshotState.selection.previewInputSnapshot = null;
assert.equal(missingNoteSnapshotState.prepareValidationMessage(), "业务说明缺失，请重新核对");

const whitespaceState = makeState();
selectBase(whitespaceState);
whitespaceState.setPreviewInput("businessNote", "  第一行业务说明\n第二行业务说明  ");
const whitespaceRequest = whitespaceState.previewRequest();
assert.equal(whitespaceRequest.businessNote, "第一行业务说明\n第二行业务说明");
assert.equal(whitespaceState.acceptPreview(previewFor(whitespaceState), whitespaceRequest), true);
assert.equal(whitespaceState.selection.previewInputSnapshot.businessNote, whitespaceRequest.businessNote);
assert.equal(whitespaceState.writerRequest().businessNote, whitespaceRequest.businessNote);

const blankNoteState = makeState();
selectBase(blankNoteState);
blankNoteState.setPreviewInput("businessNote", "  \n  ");
assert.equal(blankNoteState.previewValidationMessage(), "请填写业务说明。");

state.selectPending("pending-other");
assert.match(state.previewValidationMessage(), /偏离原因/);
state.setPreviewInput("deviationReasonCode", "other");
assert.match(state.previewValidationMessage(), /必须填写说明/);
state.setPreviewInput("deviationReasonNote", "同一自然周人工清偿");
assert.equal(state.previewValidationMessage(), "");

const crossState = makeState();
selectBase(crossState);
assert.equal(acceptStatePreview(crossState, {
  comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: false, same_subject: false },
}), true);
assert.match(crossState.prepareValidationMessage(), /跨老师/);
const crossIdentity1 = crossState.selection.requestIdentity;
crossState.setConfirmation("crossTeacher", true);
assert.equal(crossState.selection.preview, null);
assert.notEqual(crossState.selection.requestIdentity, crossIdentity1);
crossState.setConfirmation("crossSubject", true);
assert.equal(acceptStatePreview(crossState, {
  comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: false, same_subject: false },
}), true);
assert.equal(crossState.prepareValidationMessage(), "");

const fingerprintState = makeState();
selectBase(fingerprintState);
assert.equal(acceptStatePreview(fingerprintState, {
  source_versions: { pending_row_md5: "changed", overtime_row_md5: "overage-overage-1" },
}), false);
assert.match(fingerprintState.selection.previewError, /所选对象事实已变化/);

for (const [override, expected] of [
  [{ comparison: { same_student: false, same_business_entity: true, same_unit_price: true } }, /不同学生/],
  [{ comparison: { same_student: true, same_business_entity: false, same_unit_price: true } }, /不同业务范围/],
  [{ comparison: { same_student: true, same_business_entity: true, same_unit_price: false } }, /相同单价/],
  [{ pending_source: { planned_id: "pending-fifo", active_claimed: true } }, /其他结算或清偿流程占用/],
]) {
  const gateState = makeState();
  selectBase(gateState);
  assert.equal(acceptStatePreview(gateState, override), true);
  assert.match(gateState.prepareValidationMessage(), expected);
}

const operator = makeState("operator");
selectBase(operator, "pending-fifo", "overage-locked");
assert.equal(acceptStatePreview(operator, {
  financial: { requires_forward_adjustment: true },
  authorization: { can_execute_for_current_actor: false, blocker_code: "LESSON_CLEARANCE_ADMIN_REQUIRED", blocker_message: "必须由admin处理" },
}), true);
assert.match(operator.prepareValidationMessage(), /权限/);

const lockedAdmin = makeState("admin");
selectBase(lockedAdmin, "pending-fifo", "overage-locked");
assert.equal(acceptStatePreview(lockedAdmin, {
  financial: { requires_forward_adjustment: true },
  authorization: { can_execute_for_current_actor: true, blocker_code: null },
}), true);
assert.match(lockedAdmin.prepareValidationMessage(), /锁定月份/);
lockedAdmin.setConfirmation("forward", true);
assert.equal(acceptStatePreview(lockedAdmin, {
  financial: { requires_forward_adjustment: true },
  authorization: { can_execute_for_current_actor: true, blocker_code: null },
}), true);
assert.equal(lockedAdmin.prepareValidationMessage(), "");

const readOnly = makeState("read_only");
assert.equal(readOnly.selectPending("pending-fifo"), false);
assert.match(readOnly.previewValidationMessage(), /只能查看/);

const clearanceId = "30000000-0000-4000-8000-000000000001";
const reversal = makeState("admin", [{ clearance_id: clearanceId, can_reverse: true }]);
assert.equal(reversal.beginReversal(clearanceId), true);
const reversalRequest = reversal.reversalPreviewRequest();
assert.equal(reversalRequest.clearanceId, clearanceId);
assert.equal(reversal.acceptReversalPreview({
  request_identity: reversalRequest.requestIdentity,
  reversal_manifest_sha256: "reversal-manifest",
  original_clearance: { clearance_id: clearanceId },
  current_state: { is_effective: true, already_reversed: false },
  authorization: { can_reverse: true },
}), true);
assert.throws(() => reversal.reversalWriterRequest(), /撤销原因/);
reversal.selection.reversalReason = "业务负责人确认撤销";
assert.equal(reversal.reversalWriterRequest().requestIdentity, reversalRequest.requestIdentity);

const alreadyReversed = makeState("admin", [{ clearance_id: clearanceId, can_reverse: true }]);
alreadyReversed.beginReversal(clearanceId);
assert.equal(alreadyReversed.acceptReversalPreview({
  request_identity: alreadyReversed.selection.reversalRequestIdentity,
  reversal_manifest_sha256: "reversal-manifest",
  original_clearance: { clearance_id: clearanceId },
  current_state: { is_effective: false, already_reversed: true },
  authorization: { can_reverse: false, blocker_message: "已经撤销" },
}), false);
assert.match(alreadyReversed.selection.reversalError, /已经撤销/);

const downstreamBlocked = makeState("admin", [{ clearance_id: clearanceId, can_reverse: true }]);
downstreamBlocked.beginReversal(clearanceId);
assert.equal(downstreamBlocked.acceptReversalPreview({
  request_identity: downstreamBlocked.selection.reversalRequestIdentity,
  reversal_manifest_sha256: "reversal-manifest",
  original_clearance: { clearance_id: clearanceId },
  current_state: { is_effective: true, already_reversed: false, affects_active_claim: true },
  authorization: { can_reverse: false, blocker_message: "存在downstream dependency" },
}), false);
assert.match(downstreamBlocked.selection.reversalError, /downstream dependency/);

console.log("SCHOOL_PHASE2C_D2A_CLEARANCE_SUBMIT_STATE_PASS");
