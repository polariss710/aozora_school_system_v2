import assert from "node:assert/strict";
import { createRequire } from "node:module";

const moduleRoot = process.env.PHASE2C_D1_NODE_MODULES;
if (!moduleRoot) throw new Error("PHASE2C_D1_NODE_MODULES_REQUIRED");
const { chromium } = createRequire(import.meta.url)(`${moduleRoot}/playwright`);
const baseUrl = process.env.PHASE2C_D1_BASE_URL || "http://127.0.0.1:8018";

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PHASE2C_D1_BROWSER_EXECUTABLE || undefined,
});
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const consoleProblems = [];
page.on("console", (message) => {
  if (["error", "warning"].includes(message.type())) consoleProblems.push(`${message.type()}:${message.text()}`);
});
page.on("pageerror", (error) => consoleProblems.push(`pageerror:${error.message}`));
await page.route("**/js/lesson-app.js*", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "export {};" }));
await page.route("https://cdn.jsdelivr.net/**", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "" }));
await page.goto(`${baseUrl}/lesson.html`, { waitUntil: "domcontentloaded" });

await page.evaluate(async () => {
  document.documentElement.classList.remove("auth-pending");
  const { createLessonClearanceWorkspace } = await import("/js/components/lesson-clearance-workspace.js?v=phase2c-d1-clearance-workspace-20260817-1");
  const counters = { readers: 0, previews: 0, reversalPreviews: 0, writers: 0 };
  const pending = [
    {
      pending_source_planned_id: "10000000-0000-4000-8000-000000000001",
      student_id: "student-1", student_display_name: "测试学生", student_name_evidence_status: "current_reference", student_status: "active",
      business_entity_id: "entity-1", business_entity_display_name: "青空进学塾", business_entity_name_evidence_status: "current_reference",
      teacher_id: "teacher-1", teacher_display_name: "老师甲", teacher_name_evidence_status: "current_reference",
      subject_id: "subject-1", subject_display_name: "EJU物理", subject_name_evidence_status: "current_reference",
      source_lesson_date: "2026-08-01", source_year_month: "2026-08", source_status: "pending_makeup", source_origin_type: "planned_pending_makeup",
      initial_credit_minutes: 120, makeup_consumed_minutes: 0, clearance_allocated_minutes: 0, clearance_reversed_minutes: 0,
      active_claimed_minutes: 0, remaining_minutes: 120, currently_allocatable_minutes: 120, unit_price_jpy: 9000,
      initial_amount_jpy: 18000, remaining_amount_jpy: 18000, active_claimed: false, is_locked: false, lock_reason_code: null,
      package_classification: "ordinary_makeup_credit", can_be_candidate: true, candidate_blocker_code: null,
      evidence_status: "current_derived", source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "pending-md5",
      credit_origin_sort_at: "2026-08-01T00:00:00Z", credit_origin_sort_source: "causal_actual_created_at", fifo_rank: 1,
    },
  ];
  const overages = [
    {
      overtime_source_actual_id: "20000000-0000-4000-8000-000000000001", linked_planned_lesson_id: "21000000-0000-4000-8000-000000000001",
      student_id: "student-1", student_display_name: "测试学生", student_status: "active",
      business_entity_id: "entity-1", business_entity_display_name: "青空进学塾",
      teacher_id: "teacher-2", teacher_display_name: "老师乙", subject_id: "subject-2", subject_display_name: "EJU数学",
      actual_lesson_date: "2026-08-11", actual_start_time: "13:00", actual_end_time: "14:00", student_settlement_month: "2026-08", teacher_wage_month: "2026-08",
      overage_policy_version: "student_duration_overage_v1", overage_source: "ordinary_actual_rpc", frozen_overtime_minutes: 60,
      active_claimed_minutes: 0, clearance_allocated_minutes: 0, clearance_reversed_minutes: 0, available_minutes: 60,
      currently_allocatable_minutes: 60, unit_price_jpy: 9000, frozen_amount_jpy: 9000, available_amount_jpy: 9000,
      active_claimed: false, is_locked: false, can_be_candidate: true, candidate_blocker_code: null,
      evidence_status: "current_derived", source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "overage-md5", display_rank: 1,
    },
  ];
  const packageRows = [{
    package_lot_id: "P002", origin_planned_lesson_id: "30000000-0000-4000-8000-000000000001", student_id: "student-1", student_display_name: "测试学生",
    business_entity_id: "entity-1", business_entity_display_name: "青空进学塾", package_business_type: "package_credit", package_display_label: "套餐余额",
    classification_reason: "P002 package", initial_minutes: 1200, consumed_minutes: 0, remaining_minutes: 1200, unit_price_jpy: 13000,
    total_amount_jpy: 260000, student_settlement_month: "2026-07", status: "active", can_consume: false, can_reserve: false, read_only: true,
    evidence_status: "immutable_reference", origin_row_md5: "package-md5", student_name_evidence_status: "current_reference", business_entity_name_evidence_status: "current_reference",
  }];
  const crossRows = [{
    actual_lesson_id: "40000000-0000-4000-8000-000000000001", source_planned_lesson_id: "41000000-0000-4000-8000-000000000001",
    student_id: "student-1", student_display_name: "测试学生", business_entity_id: "entity-1", business_entity_display_name: "青空进学塾",
    source_month: "2026-07", actual_month: "2026-08", actual_lesson_date: "2026-08-11", actual_start_time: "13:00", actual_end_time: "14:00", actual_minutes: 60,
    source_teacher_display_name: "老师甲", actual_teacher_display_name: "老师乙", source_subject_display_name: "EJU物理", actual_subject_display_name: "EJU数学",
    student_settlement_month: "2026-07", teacher_wage_month: "2026-08", evidence_status: "current_derived", source_row_md5: "source-md5", actual_row_md5: "actual-md5",
  }];
  const read = (value) => { counters.readers += 1; return structuredClone(value); };
  const api = {
    fetchPendingBalances: async () => read({ items: pending, summary: {} }),
    fetchAvailableOverages: async () => read({ items: overages, summary: {} }),
    fetchPackageCreditLots: async () => read({ items: packageRows, summary: {} }),
    fetchCrossMonthProjection: async () => read({ items: crossRows, summary: { distinct_actual_count: 1 } }),
    fetchDashboardSummary: async () => read({ pending_source_count: 1, pending_remaining_minutes: 120, overage_source_count: 1, available_overtime_minutes: 60, package_lot_count: 1, package_remaining_minutes: 1200, history_count: 0 }),
    fetchHistory: async () => read([]),
    previewClearance: async (input) => {
      counters.previews += 1;
      return {
        request_identity: input.requestIdentity, requested_minutes: input.allocatedMinutes,
        preview_manifest_sha256: "preview-manifest", writer_revalidation_required: true, reservation_created: false,
        pending_source: { planned_id: input.pendingSourcePlannedId, student_name: "测试学生", before_remaining_minutes: 120, after_remaining_minutes: 105, amount_jpy: -2250, source_locked: false },
        overtime_source: { actual_id: input.overtimeSourceActualId, student_name: "测试学生", before_available_minutes: 60, after_available_minutes: 45, amount_jpy: 2250, source_locked: false },
        comparison: { same_teacher: false, same_subject: false },
        financial: { net_amount_jpy: 0, requires_forward_adjustment: false, forward_destination_month: null },
        fifo: { recommended_pending_planned_id: input.pendingSourcePlannedId, is_recommended_target: true },
        authorization: { blocker_code: null }, source_versions: { pending_row_md5: "pending-md5", overtime_row_md5: "overage-md5" },
      };
    },
    previewReversal: async () => { counters.reversalPreviews += 1; return {}; },
  };
  const controller = createLessonClearanceWorkspace({ api, getRole: () => "admin" });
  controller.init();
  globalThis.__PHASE2C_D1_TEST__ = { controller, counters };
});

await page.click("#openLessonClearanceWorkspaceButton");
await page.waitForSelector("#lessonClearanceWorkspaceContent:not(.is-hidden)");
assert.equal(await page.locator("#lessonClearancePendingSelect").inputValue(), "");
assert.equal(await page.locator("#lessonClearanceOverageSelect").inputValue(), "");
assert.equal(await page.locator("#lessonClearanceConfirmButton").isDisabled(), true);
assert.match(await page.locator("#lessonClearanceSummary").innerText(), /120分钟/);

await page.selectOption("#lessonClearancePendingSelect", "10000000-0000-4000-8000-000000000001");
await page.selectOption("#lessonClearanceOverageSelect", "20000000-0000-4000-8000-000000000001");
await page.fill("#lessonClearanceAllocatedMinutesInput", "15");
await page.dispatchEvent("#lessonClearanceAllocatedMinutesInput", "change");
const identity1 = await page.locator(".lesson-clearance-preview-actions code").innerText();
await page.click("#lessonClearancePreviewButton");
await page.waitForSelector(".lesson-clearance-preview-card");
assert.match(await page.locator(".lesson-clearance-preview-card").innerText(), /确认跨老师/);
assert.match(await page.locator(".lesson-clearance-preview-card").innerText(), /确认跨科目/);
await page.click("#lessonClearancePreviewButton");
const identity2 = await page.locator(".lesson-clearance-preview-actions code").innerText();
assert.equal(identity2, identity1, "same input reuses request identity");
await page.fill("#lessonClearanceAllocatedMinutesInput", "30");
await page.dispatchEvent("#lessonClearanceAllocatedMinutesInput", "change");
const identity3 = await page.locator(".lesson-clearance-preview-actions code").innerText();
assert.notEqual(identity3, identity2, "changed minutes rotates request identity");
assert.equal(await page.locator(".lesson-clearance-preview-card").count(), 0, "changed input invalidates preview");

const beforeReset = await page.evaluate(() => ({
  counters: structuredClone(globalThis.__PHASE2C_D1_TEST__.controller.counters),
  tabHash: document.querySelector("#lessonClearanceTabPanel").innerHTML,
}));
await page.selectOption("#lessonClearanceStatusFilter", "locked");
await page.click("#lessonClearanceFilterResetButton");
const afterReset = await page.evaluate(() => ({
  counters: structuredClone(globalThis.__PHASE2C_D1_TEST__.controller.counters),
  tabHash: document.querySelector("#lessonClearanceTabPanel").innerHTML,
  toast: document.querySelector("#lessonClearanceWorkspaceMessage").textContent,
}));
assert.deepEqual(afterReset.counters, beforeReset.counters);
assert.equal(afterReset.tabHash, beforeReset.tabHash);
assert.equal(afterReset.toast, "已重置筛选条件");

const layoutMeasurements = [];
for (const width of [1440, 1024, 768, 390]) {
  await page.setViewportSize({ width, height: 900 });
  const overflow = await page.evaluate(() => ({
    document: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    dialog: document.querySelector("#lessonClearanceWorkspaceDialog").scrollWidth - document.querySelector("#lessonClearanceWorkspaceDialog").clientWidth,
    panel: document.querySelector(".lesson-clearance-dialog-panel").scrollWidth - document.querySelector(".lesson-clearance-dialog-panel").clientWidth,
    widest: [...document.querySelectorAll(".lesson-clearance-dialog-panel *")]
      .map((element) => ({ tag: element.tagName, className: element.className, width: element.getBoundingClientRect().width, scrollWidth: element.scrollWidth, clientWidth: element.clientWidth }))
      .sort((left, right) => (right.scrollWidth - right.clientWidth) - (left.scrollWidth - left.clientWidth))[0],
  }));
  assert.ok(overflow.document <= 0, `${width}px document overflow ${overflow.document}`);
  assert.ok(overflow.dialog <= 0, `${width}px dialog overflow ${overflow.dialog} ${JSON.stringify(overflow.widest)}`);
  assert.ok(overflow.panel <= 0, `${width}px panel overflow ${overflow.panel} ${JSON.stringify(overflow.widest)}`);
  layoutMeasurements.push({ width, documentOverflow: overflow.document, dialogOverflow: overflow.dialog, panelOverflow: overflow.panel });
}

const finalCounters = await page.evaluate(() => globalThis.__PHASE2C_D1_TEST__.counters);
assert.equal(finalCounters.writers, 0);
assert.equal(finalCounters.previews, 2);
assert.deepEqual(consoleProblems, []);
await browser.close();
console.log(JSON.stringify({ layoutMeasurements, consoleProblems, writerCalls: finalCounters.writers }));
console.log("SCHOOL_PHASE2C_D1_CLEARANCE_WORKSPACE_BROWSER_PASS");
