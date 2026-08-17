import assert from "node:assert/strict";
import {
  LESSON_CLEARANCE_DEFAULT_FILTERS,
  LessonClearanceWorkspaceState,
  lessonClearanceCapabilities,
} from "../js/utils/lesson-clearance-state.js";

const pending = (id, overrides = {}) => ({
  pending_source_planned_id: id,
  student_id: "student-1",
  business_entity_id: "entity-1",
  source_year_month: "2026-08",
  evidence_status: "current_derived",
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
  evidence_status: "current_derived",
  display_rank: 1,
  can_be_candidate: true,
  active_claimed: false,
  is_locked: false,
  ...overrides,
});

const state = new LessonClearanceWorkspaceState({ role: "admin" });
state.setData({
  pendingPayload: { items: [pending("pending-fifo"), pending("pending-other", { fifo_rank: 2 }), pending("pending-claimed", { fifo_rank: null, active_claimed: true, can_be_candidate: false })] },
  overagePayload: { items: [overage("overage-1"), overage("overage-locked", { is_locked: true })] },
  packagePayload: { items: [{ package_lot_id: "P002", student_id: "student-1", business_entity_id: "entity-1", student_settlement_month: "2026-07", evidence_status: "immutable_reference" }] },
  crossMonthPayload: { items: [{ actual_lesson_id: "actual-1", student_id: "student-1", business_entity_id: "entity-1", actual_month: "2026-08", evidence_status: "current_derived" }] },
  summary: { pending_source_count: 3 },
  history: [],
});

assert.deepEqual(state.draftFilters, LESSON_CLEARANCE_DEFAULT_FILTERS);
assert.equal(state.selection.pendingId, "");
assert.equal(state.selection.overtimeId, "");
assert.equal(state.selection.requestIdentity, "");
assert.equal(state.selection.preview, null);
assert.equal(lessonClearanceCapabilities("admin").preview, true);
assert.equal(lessonClearanceCapabilities("operator").preview, true);
assert.equal(lessonClearanceCapabilities("read_only").select, false);
assert.equal(lessonClearanceCapabilities("inactive").view, false);

assert.equal(state.selectPending("pending-fifo"), true);
assert.equal(state.selection.requestIdentity, "", "one source does not create identity");
assert.equal(state.selectOvertime("overage-1"), true);
const firstIdentity = state.selection.requestIdentity;
assert.match(firstIdentity, /^[0-9a-f-]{36}$/i);
state.setPreviewInput("allocatedMinutes", "15");
const minutesIdentity = state.selection.requestIdentity;
assert.notEqual(minutesIdentity, firstIdentity);
const request1 = state.previewRequest();
const request2 = state.previewRequest();
assert.equal(request1.requestIdentity, minutesIdentity);
assert.equal(request2.requestIdentity, minutesIdentity, "same input reuses identity");
assert.equal(state.acceptPreview({ request_identity: minutesIdentity, comparison: {} }), true);
assert.ok(state.selection.preview);
state.setPreviewInput("businessNote", "人工备注");
assert.equal(state.selection.preview, null);
assert.notEqual(state.selection.requestIdentity, minutesIdentity);

state.selectPending("pending-other");
state.setPreviewInput("allocatedMinutes", "15");
assert.match(state.previewValidationMessage(), /偏离原因/);
state.setPreviewInput("deviationReasonCode", "other");
assert.match(state.previewValidationMessage(), /必须填写说明/);
state.setPreviewInput("deviationReasonNote", "客户明确选择");
assert.equal(state.previewValidationMessage(), "");
const deviationIdentity = state.selection.requestIdentity;
state.setPreviewInput("deviationReasonNote", "客户明确选择");
assert.equal(state.selection.requestIdentity, deviationIdentity, "same reason does not rotate identity");

assert.equal(state.selectPending("pending-claimed"), false);
state.setDraftFilter("status", "claimed");
state.applyDraftFilters();
assert.deepEqual(state.pendingRows().map((row) => row.pending_source_planned_id), ["pending-claimed"]);
state.setDraftFilter("fifoOnly", true);
state.setDraftFilter("status", "");
state.applyDraftFilters();
assert.deepEqual(state.pendingRows().map((row) => row.pending_source_planned_id), ["pending-fifo"]);
assert.equal(state.shouldOpenRow(state.pendingRows()[0], "pending"), true);

state.setDraftFilter("studentId", "student-1");
state.resetDraftFilters();
assert.deepEqual(state.draftFilters, LESSON_CLEARANCE_DEFAULT_FILTERS);
assert.equal(state.appliedFilters.fifoOnly, true, "reset changes draft only");

state.setRole("read_only");
assert.equal(state.selectPending("pending-fifo"), false);
assert.match(state.previewValidationMessage(), /只能查看余额/);
state.setRole("operator");
assert.equal(state.capabilities().locked, false);
state.setRole("inactive");
assert.equal(state.capabilities().view, false);

state.setRole("admin");
state.selectPending("pending-fifo");
state.selectOvertime("overage-1");
state.setPreviewInput("allocatedMinutes", "15");
const currentIdentity = state.selection.requestIdentity;
assert.equal(state.acceptPreview({ request_identity: "stale-identity" }), false);
assert.equal(state.selection.preview, null);
assert.match(state.selection.previewError, /来源事实已变化/);
assert.notEqual(currentIdentity, "stale-identity");

state.clearSelection();
assert.equal(state.selection.requestIdentity, "");
assert.equal(state.selection.reversalPreview, null);

console.log("SCHOOL_PHASE2C_D1_CLEARANCE_WORKSPACE_STATE_PASS");
