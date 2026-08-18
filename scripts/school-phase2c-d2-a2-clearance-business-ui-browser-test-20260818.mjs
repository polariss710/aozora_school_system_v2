import assert from "node:assert/strict";
import { createRequire } from "node:module";

const moduleRoot = process.env.PHASE2C_D2A_NODE_MODULES;
if (!moduleRoot) throw new Error("PHASE2C_D2A_NODE_MODULES_REQUIRED");
const { chromium } = createRequire(import.meta.url)(`${moduleRoot}/playwright`);
const baseUrl = process.env.PHASE2C_D2A_BASE_URL || "http://127.0.0.1:8019";
const browser = await chromium.launch({ headless: true, executablePath: process.env.PHASE2C_D2A_BROWSER_EXECUTABLE || undefined });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const consoleProblems = [];
page.on("console", (message) => {
  if (["error", "warning"].includes(message.type())) consoleProblems.push(`${message.type()}:${message.text()}`);
});
page.on("pageerror", (error) => consoleProblems.push(`pageerror:${error.message}`));
await page.route("**/js/lesson-app.js*", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "export {};" }));
await page.goto(`${baseUrl}/lesson.html`, { waitUntil: "domcontentloaded" });

await page.evaluate(async () => {
  document.documentElement.classList.remove("auth-pending");
  const { createLessonClearanceWorkspace } = await import("/js/components/lesson-clearance-workspace.js?v=phase2c-d2-a2-business-language-20260818-1");
  const pending = [
    {
      pending_source_planned_id: "8870f57f-bca5-4114-90db-ee592cca2f45", student_id: "student-yuan", student_display_name: "袁振轩",
      business_entity_id: "entity-school", business_entity_display_name: "青空进学塾", teacher_id: "teacher-coco", teacher_display_name: "李雯coco",
      subject_id: "subject-toefl", subject_display_name: "TOEFL", source_lesson_date: "2026-08-10", operational_display_date: "2026-08-14",
      operational_display_date_basis: "partial_actual_date", origin_partial_actual_id: "2da1ec9a-6f19-49af-a9bd-48984a255aa9",
      origin_partial_actual_date: "2026-08-14", origin_evidence_status: "unique_valid_partial_actual", operational_display_explanation: "partial_actual_date_authoritative_v1",
      source_year_month: "2026-08", source_status: "pending_makeup", source_origin_type: "planned_pending_makeup", initial_credit_minutes: 120,
      makeup_consumed_minutes: 60, clearance_allocated_minutes: 0, clearance_reversed_minutes: 0, active_claimed_minutes: 0,
      remaining_minutes: 60, currently_allocatable_minutes: 60, unit_price_jpy: 9000, initial_amount_jpy: 18000, remaining_amount_jpy: 9000,
      active_claimed: false, is_locked: false, can_be_candidate: true, evidence_status: "current_derived", source_row_md5: "pending-target-md5",
      source_updated_at: "2026-08-16T07:47:00Z", credit_origin_sort_at: "2026-08-16T07:47:00Z", credit_origin_sort_source: "causal_actual_created_at", fifo_rank: 1,
    },
    {
      pending_source_planned_id: "06befa0a-1e6c-4e26-8b88-2f321bfaca7f", student_id: "student-yuan", student_display_name: "袁振轩",
      business_entity_id: "entity-school", business_entity_display_name: "青空进学塾", teacher_display_name: "李雯coco", subject_display_name: "TOEFL",
      source_lesson_date: "2026-08-03", operational_display_date: "2026-08-03", operational_display_date_basis: "source_natural_week_start",
      origin_partial_actual_id: null, origin_partial_actual_date: null, origin_evidence_status: "no_valid_partial_actual", operational_display_explanation: "source_natural_week_start_fallback_v1",
      source_year_month: "2026-08", remaining_minutes: 120, currently_allocatable_minutes: 120, remaining_amount_jpy: 18000,
      can_be_candidate: true, active_claimed: false, is_locked: false, evidence_status: "current_derived", source_row_md5: "pending-cancelled-md5", fifo_rank: 2,
    },
    {
      pending_source_planned_id: "44dcd8ac-7303-40cb-92aa-32e91933bd87", student_id: "student-yuan", student_display_name: "袁振轩",
      business_entity_id: "entity-school", business_entity_display_name: "青空进学塾", teacher_display_name: "李雯coco", subject_display_name: "TOEFL",
      source_lesson_date: "2026-08-17", operational_display_date: "2026-08-17", operational_display_date_basis: "source_natural_week_start",
      origin_partial_actual_id: null, origin_partial_actual_date: null, origin_evidence_status: "no_valid_partial_actual", operational_display_explanation: "source_natural_week_start_fallback_v1",
      source_year_month: "2026-08", remaining_minutes: 120, currently_allocatable_minutes: 120, remaining_amount_jpy: 18000,
      can_be_candidate: true, active_claimed: false, is_locked: false, evidence_status: "current_derived", source_row_md5: "pending-future-cancelled-md5", fifo_rank: 3,
    },
  ];
  const overages = [
    {
      overtime_source_actual_id: "e58457a1-89c5-441b-9bcb-73ffc6168d8a", linked_planned_lesson_id: "planned-overage", student_id: "student-yuan", student_display_name: "袁振轩",
      business_entity_id: "entity-school", business_entity_display_name: "青空进学塾", teacher_id: "teacher-coco", teacher_display_name: "李雯coco", subject_id: "subject-toefl", subject_display_name: "TOEFL",
      actual_lesson_date: "2026-08-11", student_settlement_month: "2026-08", teacher_wage_month: "2026-08", frozen_overtime_minutes: 60,
      clearance_allocated_minutes: 0, clearance_reversed_minutes: 0, active_claimed_minutes: 0, available_minutes: 60, currently_allocatable_minutes: 60,
      unit_price_jpy: 9000, frozen_amount_jpy: 9000, available_amount_jpy: 9000, active_claimed: false, is_locked: false, can_be_candidate: true,
      evidence_status: "current_derived", source_row_md5: "overage-target-md5", display_rank: 1, overtime_sort_source: "actual_created_at",
    },
    {
      overtime_source_actual_id: "overage-other-entity", student_id: "student-yuan", student_display_name: "袁振轩", business_entity_id: "entity-other",
      business_entity_display_name: "个人名义", teacher_display_name: "李雯coco", subject_display_name: "TOEFL", actual_lesson_date: "2026-08-12",
      student_settlement_month: "2026-08", available_minutes: 60, currently_allocatable_minutes: 60, available_amount_jpy: 9000,
      can_be_candidate: true, active_claimed: false, is_locked: false, evidence_status: "current_derived", source_row_md5: "overage-other-md5", display_rank: 2,
    },
  ];
  const metrics = { previewCalls: 0, createCalls: 0, reversalCalls: 0 };
  const clone = structuredClone;
  const api = {
    fetchPendingBalances: async () => ({ contract_version: "lesson_clearance_pending_balances_v3", items: clone(pending), summary: {} }),
    fetchAvailableOverages: async () => ({ items: clone(overages), summary: {} }),
    fetchPackageCreditLots: async () => ({ items: [], summary: {} }),
    fetchCrossMonthProjection: async () => ({ items: [], summary: {} }),
    fetchDashboardSummary: async () => ({ pending_source_count: 3, pending_remaining_minutes: 300, overage_source_count: 2, available_overtime_minutes: 120, package_lot_count: 0, package_remaining_minutes: 0, history_count: 0 }),
    fetchHistory: async () => [],
    previewClearance: async (input) => {
      metrics.previewCalls += 1;
      return {
        request_identity: input.requestIdentity, clearance_type: input.clearanceType, requested_minutes: input.allocatedMinutes, operation_date: input.operationDate,
        preview_manifest_sha256: `manifest-${input.requestIdentity}`, writer_revalidation_required: true, reservation_created: false,
        pending_source: { planned_id: pending[0].pending_source_planned_id, student_id: "student-yuan", student_name: "袁振轩", source_date: "2026-08-10", student_settlement_month: "2026-08", before_remaining_minutes: 60, after_remaining_minutes: 0, unit_price_jpy: 9000, amount_jpy: -9000, active_claimed: false, source_locked: false },
        overtime_source: { actual_id: overages[0].overtime_source_actual_id, student_id: "student-yuan", student_name: "袁振轩", actual_date: "2026-08-11", student_settlement_month: "2026-08", before_available_minutes: 60, after_available_minutes: 0, unit_price_jpy: 9000, amount_jpy: 9000, active_claimed: false, source_locked: false },
        comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: true, same_subject: true },
        fifo: { recommended_pending_planned_id: pending[0].pending_source_planned_id, selected_pending_planned_id: pending[0].pending_source_planned_id, is_recommended_target: true, deviation_required: false, deviation_reason_valid: true },
        financial: { net_amount_jpy: 0, requires_forward_adjustment: false, forward_destination_month: null, forward_adjustment_direction: "none", forward_adjustment_amount_jpy: 0 },
        authorization: { can_execute_for_current_actor: true, blocker_code: null },
        source_versions: { pending_row_md5: pending[0].source_row_md5, overtime_row_md5: overages[0].source_row_md5 },
      };
    },
    createClearance: async () => { metrics.createCalls += 1; throw new Error("WRITER_MUST_NOT_RUN"); },
    previewReversal: async () => { throw new Error("REVERSAL_PREVIEW_MUST_NOT_RUN"); },
    reverseClearance: async () => { metrics.reversalCalls += 1; throw new Error("WRITER_MUST_NOT_RUN"); },
  };
  const controller = createLessonClearanceWorkspace({ api, getRole: () => "admin" });
  controller.init();
  globalThis.__D2A2__ = { controller, metrics };
});

await page.click("#openLessonClearanceWorkspaceButton");
await page.waitForSelector("#lessonClearanceWorkspaceContent:not(.is-hidden)");
assert.equal(await page.locator("#lessonClearanceEntityFilter").count(), 0);
const workspaceText = await page.locator("#lessonClearanceWorkspaceDialog").innerText();
assert.doesNotMatch(workspaceText, /个人名义/);
assert.doesNotMatch(workspaceText, /青空进学塾/);
assert.doesNotMatch(workspaceText, /8870f57f|e58457a1/);
for (const expected of ["袁振轩", "2026-08-14", "2026-08-03", "2026-08-17", "建议顺序（较早产生的余额优先）", "可清偿金额"]) {
  assert.match(workspaceText, new RegExp(expected));
}
assert.equal(await page.locator(".lesson-clearance-system-details[open]").count(), 0);
const targetCard = page.locator('[data-clearance-source-id="8870f57f-bca5-4114-90db-ee592cca2f45"]');
if (!(await targetCard.evaluate((node) => node.open))) await targetCard.locator(":scope > summary").click();
assert.match(await targetCard.innerText(), /2026-08-14/);
assert.doesNotMatch(await targetCard.innerText(), /青空进学塾/);
await targetCard.locator(".lesson-clearance-system-details > summary").click();
assert.match(await targetCard.innerText(), /8870f57f-bca5-4114-90db-ee592cca2f45/);
assert.match(await targetCard.innerText(), /青空进学塾/);

const pendingOptions = await page.locator("#lessonClearancePendingSelect option").allTextContents();
assert.ok(pendingOptions.some((value) => value.includes("袁振轩｜2026-08-14｜李雯coco｜TOEFL｜待补60分钟")));
assert.equal(pendingOptions.some((value) => /8870f57f|青空进学塾/.test(value)), false);

await page.selectOption("#lessonClearancePendingSelect", "8870f57f-bca5-4114-90db-ee592cca2f45");
await page.selectOption("#lessonClearanceOverageSelect", "overage-other-entity");
await page.fill("#lessonClearanceAllocatedMinutesInput", "60");
await page.fill("#lessonClearanceOperationDateInput", "2026-08-18");
await page.dispatchEvent("#lessonClearanceOperationDateInput", "change");
await page.fill("#lessonClearanceBusinessNoteInput", "跨业务范围测试");
await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
await page.waitForTimeout(50);
assert.match(await page.locator("#lessonClearanceSelectionPanel").innerText(), /不同业务范围/);
assert.equal(await page.evaluate(() => globalThis.__D2A2__.metrics.previewCalls), 0, "mixed entity blocks before Preview RPC");

await page.selectOption("#lessonClearanceOverageSelect", "e58457a1-89c5-441b-9bcb-73ffc6168d8a");
await page.fill("#lessonClearanceBusinessNoteInput", "同一自然周课时差额清偿：2026-08-11超额1小时清偿2026-08-14部分履约不足1小时。");
await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
await page.waitForSelector(".lesson-clearance-preview-card");
assert.equal(await page.evaluate(() => globalThis.__D2A2__.metrics.previewCalls), 1);
const previewText = await page.locator("#lessonClearancePreviewPanel").innerText();
for (const expected of ["系统核对结果", "待补对象日期", "2026-08-14", "超额日期", "2026-08-11", "符合建议顺序"]) assert.match(previewText, new RegExp(expected));
assert.doesNotMatch(previewText, /8870f57f|e58457a1|manifest-/);

await page.click("#lessonClearanceConfirmButton");
await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
const finalText = await page.locator("#lessonClearanceFinalConfirmContent").innerText();
for (const expected of ["袁振轩", "2026-08-14", "2026-08-11", "60分钟", "业务说明", "同一自然周课时差额清偿"]) assert.match(finalText, new RegExp(expected));
assert.doesNotMatch(finalText, /8870f57f|e58457a1|青空进学塾|manifest-/);
assert.equal(await page.locator("#lessonClearanceFinalConfirmDialog .lesson-clearance-system-details").evaluate((node) => node.open), false);
await page.screenshot({ path: "/private/tmp/phase2c-d2-a2-final-dialog-desktop.png", fullPage: false });

await page.setViewportSize({ width: 390, height: 844 });
const mobile = await page.evaluate(() => ({
  documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  dialogOverflow: document.querySelector("#lessonClearanceFinalConfirmDialog").scrollWidth - document.querySelector("#lessonClearanceFinalConfirmDialog").clientWidth,
  panelOverflow: document.querySelector(".lesson-clearance-final-dialog-panel").scrollWidth - document.querySelector(".lesson-clearance-final-dialog-panel").clientWidth,
}));
assert.ok(mobile.documentOverflow <= 0 && mobile.dialogOverflow <= 0 && mobile.panelOverflow <= 0);
await page.screenshot({ path: "/private/tmp/phase2c-d2-a2-final-dialog-390.png", fullPage: false });

assert.deepEqual(await page.evaluate(() => globalThis.__D2A2__.metrics), { previewCalls: 1, createCalls: 0, reversalCalls: 0 });
assert.deepEqual(consoleProblems, []);
await browser.close();
console.log(JSON.stringify({ mobile, consoleProblems, screenshots: ["/private/tmp/phase2c-d2-a2-final-dialog-desktop.png", "/private/tmp/phase2c-d2-a2-final-dialog-390.png"], writerCalls: 0 }));
console.log("SCHOOL_PHASE2C_D2_A2_CLEARANCE_BUSINESS_UI_BROWSER_PASS");
