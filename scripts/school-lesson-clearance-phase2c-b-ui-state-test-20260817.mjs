import assert from "node:assert/strict";
import { createLessonClearanceApi } from "../local/phase2c-b/phase2c-b-api-contract.mjs";
import {
  createPhase2CBMockAdapter,
  FIXTURE_IDS,
  PHASE2C_B_FIXTURES,
} from "../local/phase2c-b/phase2c-b-mock-adapter.mjs";
import { LessonClearanceState, getRoleCapabilities } from "../local/phase2c-b/phase2c-b-state.mjs";

let passed = 0;
const results = [];
async function test(name, fn) {
  await fn();
  passed += 1;
  results.push(`PASS ${String(passed).padStart(2, "0")} ${name}`);
}

async function setup(role = "operator") {
  const adapter = createPhase2CBMockAdapter();
  const api = createLessonClearanceApi(adapter);
  const state = new LessonClearanceState(api, { role });
  await state.load();
  return { adapter, api, state };
}

async function prepareClearance(state, pendingId = FIXTURE_IDS.fifoPending) {
  state.openDialog();
  await state.selectOvertime(FIXTURE_IDS.overtime);
  state.selectPending(pendingId);
}

await test("API contract rejects incomplete adapter", () => {
  assert.throws(() => createLessonClearanceApi({}), /PHASE2C_B_ADAPTER_MISSING/);
});
await test("operator has view and ordinary clearance", () => {
  assert.deepEqual(getRoleCapabilities("operator"), { view: true, clearance: true, locked: false, writeoff: false, reverse: false });
});
await test("admin has locked/writeoff/reverse authority", () => {
  assert.equal(getRoleCapabilities("admin").locked, true);
  assert.equal(getRoleCapabilities("admin").writeoff, true);
  assert.equal(getRoleCapabilities("admin").reverse, true);
});
await test("read_only can view but cannot write", () => {
  assert.equal(getRoleCapabilities("read_only").view, true);
  assert.equal(getRoleCapabilities("read_only").clearance, false);
});
await test("inactive has no access", () => assert.equal(getRoleCapabilities("inactive").view, false));
await test("no membership has no access", () => assert.equal(getRoleCapabilities("no_membership").view, false));
await test("anon has no access", () => assert.equal(getRoleCapabilities("anon").view, false));
await test("initial load uses five reader calls and no writer", async () => {
  const { adapter } = await setup();
  assert.deepEqual(adapter.counters, { reads: 5, previews: 0, creates: 0, reversals: 0 });
});
await test("pending balances use integer minutes", async () => {
  const { state } = await setup();
  assert.ok(state.data.pending.every((row) => Number.isInteger(row.remainingMinutes)));
});
await test("overages use integer minutes", async () => {
  const { state } = await setup();
  assert.ok(state.data.overages.every((row) => Number.isInteger(row.availableMinutes)));
});
await test("P002 is package_credit", async () => {
  const { state } = await setup();
  assert.equal(state.data.packages[0].classification, "package_credit");
});
await test("P002 authoritative balance is 1200 minutes", async () => {
  const { state } = await setup();
  assert.deepEqual([state.data.packages[0].initialMinutes, state.data.packages[0].consumedMinutes, state.data.packages[0].remainingMinutes], [1200, 0, 1200]);
});
await test("P002 preserves origin planned UUID", async () => {
  const { state } = await setup();
  assert.match(state.data.packages[0].originPlannedLessonId, /^[0-9a-f-]{36}$/);
});
await test("M006 renders 30 minutes without truncation", async () => {
  const { state } = await setup();
  assert.equal(state.data.history.find((row) => row.code === "M006").allocatedMinutes, 30);
});
await test("M008 renders 45 minutes without truncation", async () => {
  const { state } = await setup();
  assert.equal(state.data.history.find((row) => row.code === "M008").allocatedMinutes, 45);
});
await test("cross-month source and actual reference identical UUID", async () => {
  const { state } = await setup();
  assert.equal(state.data.crossMonth.sourceMonthRows[0].actualId, state.data.crossMonth.actualMonthRows[0].actualId);
});
await test("cross-month distinct actual count remains one", async () => {
  const { state } = await setup();
  assert.equal(state.data.crossMonth.distinctActualCount, 1);
});
await test("opening dialog causes no writer", async () => {
  const { state, adapter } = await setup();
  state.openDialog();
  assert.equal(adapter.counters.creates, 0);
});
await test("selecting overtime causes no writer", async () => {
  const { state, adapter } = await setup();
  state.openDialog();
  await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(adapter.counters.creates, 0);
});
await test("FIFO suggestion is first", async () => {
  const { state } = await setup();
  state.openDialog();
  const rows = await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(rows[0].id, FIXTURE_IDS.lockedPending);
});
await test("FIFO suggestion never auto-selects", async () => {
  const { state } = await setup();
  state.openDialog();
  await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(state.dialog.selectedPendingId, null);
});
await test("recommendations exclude another student/entity", async () => {
  const { state } = await setup();
  state.openDialog();
  const rows = await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(rows.some((row) => row.id === FIXTURE_IDS.excludedStudentPending), false);
});
await test("missing manual selection blocks preview", async () => {
  const { state } = await setup();
  state.openDialog();
  await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(await state.requestPreview(), null);
  assert.equal(state.dialog.error, "请选择待补来源");
});
await test("operator cannot process locked source", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.lockedPending);
  assert.equal(await state.requestPreview(), null);
  assert.match(state.dialog.error, /仅允许active admin/);
});
await test("different price fails with stable policy code", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.priceMismatch);
  state.setDeviation("customer_agreement");
  assert.equal(await state.requestPreview(), null);
  assert.equal(state.dialog.error, "LESSON_CLEARANCE_PRICE_POLICY_REQUIRED");
});
await test("non-FIFO selection requires reason", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  assert.equal(await state.requestPreview(), null);
  assert.match(state.dialog.error, /必须选择原因/);
});
await test("other deviation reason requires note", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("other", "");
  assert.equal(await state.requestPreview(), null);
  assert.match(state.dialog.error, /必须填写说明/);
});
await test("cross teacher/subject is allowed after explicit reason", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("teacher_subject_match");
  assert.ok(await state.requestPreview());
});
await test("preview calls no writer", async () => {
  const { state, adapter } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  await state.requestPreview();
  assert.equal(adapter.counters.creates, 0);
});
await test("preview exposes authoritative before/after minutes", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  const preview = await state.requestPreview();
  assert.deepEqual([preview.pendingBeforeMinutes, preview.pendingAfterMinutes, preview.overtimeBeforeMinutes, preview.overtimeAfterMinutes], [90, 30, 60, 0]);
});
await test("preview exposes authoritative amount and direction", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  const preview = await state.requestPreview();
  assert.deepEqual([preview.adjustmentAmountJpy, preview.adjustmentDirection], [8500, "pending_reduced"]);
});
await test("preview proves student fee and teacher wage unchanged", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  const preview = await state.requestPreview();
  assert.deepEqual([preview.studentFeeChangeJpy, preview.teacherWageChangeJpy], [0, 0]);
});
await test("preview includes manifest and idempotency key", async () => {
  const { state } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  const preview = await state.requestPreview();
  assert.ok(preview.manifest.includes("idempotency"));
  assert.equal(preview.idempotencyKey, state.dialog.idempotencyKey);
});
await test("ordinary same-price preview can be confirmed once", async () => {
  const { state, adapter } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  await state.requestPreview();
  const result = await state.confirm();
  assert.equal(result.committed, true);
  assert.equal(adapter.counters.creates, 1);
});
await test("second UI confirm is blocked after result", async () => {
  const { state, adapter } = await setup();
  await prepareClearance(state, FIXTURE_IDS.crossPending);
  state.setDeviation("customer_agreement");
  await state.requestPreview();
  await state.confirm();
  await assert.rejects(() => state.confirm(), /CONFIRM_BLOCKED/);
  assert.equal(adapter.counters.creates, 1);
});
await test("adapter idempotency returns same clearance", async () => {
  const adapter = createPhase2CBMockAdapter();
  const first = await adapter.createClearance({ idempotencyKey: "same" });
  const second = await adapter.createClearance({ idempotencyKey: "same" });
  assert.equal(second.clearanceId, first.clearanceId);
  assert.equal(second.idempotentReplay, true);
});
await test("admin locked preview requires forward confirmation before confirm", async () => {
  const { state } = await setup("admin");
  await prepareClearance(state, FIXTURE_IDS.lockedPending);
  const preview = await state.requestPreview();
  assert.equal(preview.requiresForwardAdjustment, true);
  assert.equal(state.canConfirm(), false);
});
await test("admin forward confirmation enables confirm", async () => {
  const { state } = await setup("admin");
  await prepareClearance(state, FIXTURE_IDS.lockedPending);
  await state.requestPreview();
  state.setForwardConfirmed(true);
  assert.equal(state.canConfirm(), true);
});
await test("operator cannot open admin writeoff", async () => {
  const { state } = await setup("operator");
  assert.throws(() => state.openDialog("admin_writeoff", FIXTURE_IDS.writeoffPending), /ADMIN_REQUIRED/);
});
await test("read_only cannot open clearance", async () => {
  const { state } = await setup("read_only");
  assert.throws(() => state.openDialog(), /WRITE_FORBIDDEN/);
});
await test("admin M016 writeoff requires reason", async () => {
  const { state } = await setup("admin");
  state.openDialog("admin_writeoff", FIXTURE_IDS.writeoffPending);
  assert.equal(await state.requestPreview(), null);
  assert.match(state.dialog.error, /核销原因/);
});
await test("M016 administrative zero preview is authoritative", async () => {
  const { state } = await setup("admin");
  state.openDialog("admin_writeoff", FIXTURE_IDS.writeoffPending);
  state.setDeviation("business_confirmed");
  const preview = await state.requestPreview();
  assert.deepEqual([preview.pendingBeforeMinutes, preview.pendingAfterMinutes, preview.adjustmentAmountJpy], [120, 0, 0]);
});
await test("M016 writeoff creates no teacher wage", async () => {
  const { state } = await setup("admin");
  state.openDialog("admin_writeoff", FIXTURE_IDS.writeoffPending);
  state.setDeviation("business_confirmed");
  const preview = await state.requestPreview();
  assert.equal(preview.teacherWageChangeJpy, 0);
});
await test("future charge treatment requires forward confirmation", async () => {
  const { state } = await setup("admin");
  state.openDialog("admin_writeoff", FIXTURE_IDS.writeoffPending);
  state.setTreatment("forward_charge");
  state.setDeviation("business_confirmed");
  const preview = await state.requestPreview();
  assert.equal(preview.requiresForwardAdjustment, true);
  assert.equal(state.canConfirm(), false);
});
await test("cancel/reset causes zero writer calls", async () => {
  const { state, adapter } = await setup();
  state.openDialog();
  await state.selectOvertime(FIXTURE_IDS.overtime);
  state.closeDialog();
  assert.equal(adapter.counters.creates, 0);
});
await test("changing role closes open dialog", async () => {
  const { state } = await setup();
  state.openDialog();
  state.setRole("read_only");
  assert.equal(state.dialog.open, false);
});
await test("admin can reverse history", async () => {
  const { state, adapter } = await setup("admin");
  const result = await state.reverse(PHASE2C_B_FIXTURES.history[0].id);
  assert.equal(result.reversed, true);
  assert.equal(adapter.counters.reversals, 1);
});
await test("operator cannot reverse history", async () => {
  const { state } = await setup("operator");
  await assert.rejects(() => state.reverse(PHASE2C_B_FIXTURES.history[0].id), /ADMIN_REQUIRED/);
});
await test("package list is not offered by FIFO suggestions", async () => {
  const { state } = await setup();
  state.openDialog();
  const suggestions = await state.selectOvertime(FIXTURE_IDS.overtime);
  assert.equal(suggestions.some((row) => row.id === FIXTURE_IDS.packageP002), false);
});
await test("clearance history is not an actual lesson", async () => {
  const { state } = await setup();
  assert.ok(state.data.history.every((row) => row.action === "clearance" && !("actualDate" in row)));
});
await test("unknown role fails closed", () => {
  assert.equal(getRoleCapabilities("unexpected").view, false);
});

assert.ok(passed >= 40, `expected at least 40 cases, got ${passed}`);
console.log(results.join("\n"));
console.log(`Phase 2C-B local state matrix: ${passed} passed`);
