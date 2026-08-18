import assert from "node:assert/strict";
import {
  LESSON_CLEARANCE_DEFAULT_FILTERS,
  LessonClearanceWorkspaceState,
} from "../js/utils/lesson-clearance-state.js";

const pending = (id, overrides = {}) => ({
  pending_source_planned_id: id,
  student_id: "student-1",
  business_entity_id: "entity-1",
  operational_display_date: "2026-08-14",
  operational_display_date_basis: "partial_actual_date",
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
  actual_lesson_date: "2026-08-11",
  student_settlement_month: "2026-08",
  source_row_md5: `overage-${id}`,
  display_rank: 1,
  can_be_candidate: true,
  active_claimed: false,
  is_locked: false,
  ...overrides,
});

function build(role = "admin") {
  const state = new LessonClearanceWorkspaceState({ role });
  state.setData({
    pendingPayload: { contract_version: "lesson_clearance_pending_balances_v3", items: [
      pending("partial"),
      pending("cancelled", { operational_display_date: "2026-08-03", operational_display_date_basis: "source_natural_week_start", fifo_rank: 2 }),
      pending("other-entity", { business_entity_id: "entity-2", fifo_rank: 3 }),
    ] },
    overagePayload: { items: [overage("overage-1"), overage("other-entity", { business_entity_id: "entity-2" })] },
    packagePayload: { items: [] },
    crossMonthPayload: { items: [] },
    summary: {},
    history: [],
  });
  return state;
}

assert.equal("businessEntityId" in LESSON_CLEARANCE_DEFAULT_FILTERS, false);
const state = build();
assert.equal(state.data.pendingPayload.items[0].operational_display_date, "2026-08-14");
assert.equal(state.data.pendingPayload.items[1].operational_display_date, "2026-08-03");
assert.deepEqual(state.pendingRows().map((row) => row.pending_source_planned_id), ["partial", "cancelled", "other-entity"]);

assert.equal(state.selectPending("partial"), true);
assert.equal(state.selectOvertime("other-entity"), true);
state.setPreviewInput("allocatedMinutes", "60");
state.setPreviewInput("businessNote", "跨业务范围测试");
assert.equal(
  state.previewValidationMessage(),
  "该学生存在不同业务范围的课时余额，当前不能合并清偿，请分别处理。",
);
assert.throws(() => state.previewRequest(), /不同业务范围/);
assert.equal(state.selectedPending().business_entity_id, "entity-1");
assert.equal(state.selectedOverage().business_entity_id, "entity-2");

state.selectOvertime("overage-1");
assert.equal(state.previewValidationMessage(), "");
const request = state.previewRequest();
assert.equal(request.pendingSourcePlannedId, "partial");
assert.equal(request.overtimeSourceActualId, "overage-1");
assert.equal("businessEntityId" in request, false, "RPC signature remains unchanged; DB resolves and revalidates scope from exact source IDs");

state.setDraftFilter("fifoOnly", true);
state.applyDraftFilters();
assert.deepEqual(state.pendingRows().map((row) => row.pending_source_planned_id), ["partial"]);
state.resetDraftFilters();
assert.equal(state.appliedFilters.fifoOnly, true, "reset remains draft-only");

const readOnly = build("read_only");
assert.equal(readOnly.selectPending("partial"), false);
assert.match(readOnly.previewValidationMessage(), /只能查看余额/);

console.log("SCHOOL_PHASE2C_D2_A2_CLEARANCE_BUSINESS_UI_STATE_PASS");
