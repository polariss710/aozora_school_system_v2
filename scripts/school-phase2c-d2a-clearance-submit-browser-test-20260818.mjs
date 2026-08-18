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
await page.route("https://cdn.jsdelivr.net/**", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "" }));
await page.goto(`${baseUrl}/lesson.html`, { waitUntil: "domcontentloaded" });

await page.evaluate(async () => {
  document.documentElement.classList.remove("auth-pending");
  const { createLessonClearanceWorkspace } = await import("/js/components/lesson-clearance-workspace.js?v=phase2c-d2-a2-business-language-20260818-1");
  const test = {
    previewCalls: 0,
    createCalls: 0,
    reversalCalls: 0,
    lastCreate: null,
    lastReversal: null,
    createBehavior: "success",
    historyReads: 0,
    history: [],
  };
  const pending = [
    {
      pending_source_planned_id: "10000000-0000-4000-8000-000000000001", student_id: "student-1", student_display_name: "测试学生",
      business_entity_id: "entity-1", business_entity_display_name: "测试业务归属", teacher_id: "teacher-1", teacher_display_name: "老师甲",
      subject_id: "subject-1", subject_display_name: "EJU数学", source_lesson_date: "2026-08-10", operational_display_date: "2026-08-14", operational_display_date_basis: "partial_actual_date", origin_partial_actual_id: "11000000-0000-4000-8000-000000000001", origin_partial_actual_date: "2026-08-14", origin_evidence_status: "unique_valid_partial_actual", operational_display_explanation: "partial_actual_date_authoritative_v1", source_year_month: "2026-08",
      source_status: "pending_makeup", source_origin_type: "planned_pending_makeup", initial_credit_minutes: 120, makeup_consumed_minutes: 0,
      clearance_allocated_minutes: 0, clearance_reversed_minutes: 0, active_claimed_minutes: 0, remaining_minutes: 120,
      currently_allocatable_minutes: 120, unit_price_jpy: 9000, initial_amount_jpy: 18000, remaining_amount_jpy: 18000,
      active_claimed: false, is_locked: false, package_classification: "ordinary_makeup_credit", can_be_candidate: true,
      evidence_status: "current_derived", source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "pending-md5-1",
      credit_origin_sort_source: "causal_actual_created_at", fifo_rank: 1,
    },
    {
      pending_source_planned_id: "10000000-0000-4000-8000-000000000002", student_id: "student-1", student_display_name: "测试学生",
      business_entity_id: "entity-1", business_entity_display_name: "测试业务归属", teacher_id: "teacher-1", teacher_display_name: "老师甲",
      subject_id: "subject-1", subject_display_name: "EJU数学", source_lesson_date: "2026-08-20", operational_display_date: "2026-08-17", operational_display_date_basis: "source_natural_week_start", origin_partial_actual_id: null, origin_partial_actual_date: null, origin_evidence_status: "no_valid_partial_actual", operational_display_explanation: "source_natural_week_start_fallback_v1", source_year_month: "2026-08",
      remaining_minutes: 60, currently_allocatable_minutes: 60, unit_price_jpy: 9000, remaining_amount_jpy: 9000,
      active_claimed: false, is_locked: false, can_be_candidate: true, evidence_status: "current_derived",
      source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "pending-md5-2", credit_origin_sort_source: "causal_actual_created_at", fifo_rank: 2,
    },
  ];
  const overages = [
    {
      overtime_source_actual_id: "20000000-0000-4000-8000-000000000001", linked_planned_lesson_id: "21000000-0000-4000-8000-000000000001",
      student_id: "student-1", student_display_name: "测试学生", business_entity_id: "entity-1", business_entity_display_name: "测试业务归属",
      teacher_id: "teacher-1", teacher_display_name: "老师甲", subject_id: "subject-1", subject_display_name: "EJU数学",
      actual_lesson_date: "2026-08-11", student_settlement_month: "2026-08", teacher_wage_month: "2026-08",
      frozen_overtime_minutes: 60, active_claimed_minutes: 0, clearance_allocated_minutes: 0, clearance_reversed_minutes: 0,
      available_minutes: 60, currently_allocatable_minutes: 60, unit_price_jpy: 9000, frozen_amount_jpy: 9000, available_amount_jpy: 9000,
      active_claimed: false, is_locked: false, can_be_candidate: true, evidence_status: "current_derived",
      source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "overage-md5-1", display_rank: 1,
    },
    {
      overtime_source_actual_id: "20000000-0000-4000-8000-000000000002", linked_planned_lesson_id: "21000000-0000-4000-8000-000000000002",
      student_id: "student-1", student_display_name: "测试学生", business_entity_id: "entity-1", business_entity_display_name: "测试业务归属",
      teacher_id: "teacher-2", teacher_display_name: "老师乙", subject_id: "subject-2", subject_display_name: "EJU物理",
      actual_lesson_date: "2026-08-12", student_settlement_month: "2026-08", teacher_wage_month: "2026-08",
      frozen_overtime_minutes: 60, available_minutes: 60, currently_allocatable_minutes: 60, unit_price_jpy: 9000, available_amount_jpy: 9000,
      active_claimed: false, is_locked: false, can_be_candidate: true, evidence_status: "current_derived",
      source_updated_at: "2026-08-18T00:00:00Z", source_row_md5: "overage-md5-2", display_rank: 2,
    },
  ];
  const clearanceId = "30000000-0000-4000-8000-000000000001";
  test.history = [{
    clearance_id: clearanceId, clearance_type: "overtime_offset", student_id: "student-1", student_name: "测试学生",
    business_entity_id: "entity-1", business_entity_name: "测试业务归属", pending_source_planned_id: pending[0].pending_source_planned_id,
    overtime_source_actual_id: overages[0].overtime_source_actual_id, allocated_minutes: 60, financial_net_amount_jpy: 0,
    operational_year_month: "2026-08", financial_year_month: "2026-08", requires_forward_adjustment: false,
    deviated_from_recommendation: false, same_teacher: true, same_subject: true, source_comparison_evidence_status: "immutable_reference",
    request_identity: "31000000-0000-4000-8000-000000000001", can_reverse: true, created_at: "2026-08-18T00:00:00Z",
  }];
  const clone = (value) => structuredClone(value);
  const api = {
    fetchPendingBalances: async () => ({ items: clone(pending), summary: {} }),
    fetchAvailableOverages: async () => ({ items: clone(overages), summary: {} }),
    fetchPackageCreditLots: async () => ({ items: [{ package_lot_id: "P002", student_id: "student-1", student_display_name: "测试学生", business_entity_id: "entity-1", business_entity_display_name: "测试业务归属", package_display_label: "套餐余额", package_business_type: "package_credit", remaining_minutes: 1200, total_amount_jpy: 260000, status: "active", read_only: true, can_consume: false, can_reserve: false, evidence_status: "immutable_reference" }], summary: {} }),
    fetchCrossMonthProjection: async () => ({ items: [], summary: {} }),
    fetchDashboardSummary: async () => ({ pending_source_count: 2, pending_remaining_minutes: 180, overage_source_count: 2, available_overtime_minutes: 120, package_lot_count: 1, package_remaining_minutes: 1200, history_count: test.history.length }),
    fetchHistory: async () => { test.historyReads += 1; return clone(test.history); },
    previewClearance: async (input) => {
      test.previewCalls += 1;
      test.lastPreview = clone(input);
      const pendingRow = pending.find((row) => row.pending_source_planned_id === input.pendingSourcePlannedId);
      const overageRow = overages.find((row) => row.overtime_source_actual_id === input.overtimeSourceActualId);
      const sameTeacher = pendingRow.teacher_id === overageRow.teacher_id;
      const sameSubject = pendingRow.subject_id === overageRow.subject_id;
      return {
        contract_version: "lesson_clearance_preview_v2", request_identity: input.requestIdentity, idempotency_key: input.requestIdentity,
        clearance_type: input.clearanceType, requested_minutes: input.allocatedMinutes, operation_date: input.operationDate,
        preview_manifest_sha256: `manifest-${input.requestIdentity}`, writer_revalidation_required: true, reservation_created: false,
        pending_source: { planned_id: pendingRow.pending_source_planned_id, student_id: "student-1", student_name: "测试学生", business_entity_name: "测试业务归属", source_date: pendingRow.source_lesson_date, student_settlement_month: "2026-08", before_remaining_minutes: pendingRow.remaining_minutes, after_remaining_minutes: pendingRow.remaining_minutes - input.allocatedMinutes, unit_price_jpy: 9000, amount_jpy: -9000, active_claimed: false, source_locked: false, lock_evidence: null },
        overtime_source: { actual_id: overageRow.overtime_source_actual_id, student_id: "student-1", student_name: "测试学生", business_entity_name: "测试业务归属", actual_date: overageRow.actual_lesson_date, student_settlement_month: "2026-08", before_available_minutes: 60, after_available_minutes: 60 - input.allocatedMinutes, unit_price_jpy: 9000, amount_jpy: 9000, active_claimed: false, source_locked: false, lock_evidence: null },
        comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: sameTeacher, same_subject: sameSubject },
        fifo: { recommended_pending_planned_id: pending[0].pending_source_planned_id, selected_pending_planned_id: pendingRow.pending_source_planned_id, is_recommended_target: pendingRow.fifo_rank === 1, deviation_required: pendingRow.fifo_rank !== 1, deviation_reason_code: input.deviationReasonCode, deviation_reason_note: input.deviationReasonNote, deviation_reason_valid: pendingRow.fifo_rank === 1 || Boolean(input.deviationReasonCode), selection_mode: "manual" },
        financial: { net_amount_jpy: 0, requires_forward_adjustment: false, forward_destination_month: "2026-08", forward_adjustment_direction: "none", forward_adjustment_amount_jpy: 0 },
        authorization: { actor_role: "admin", can_execute_for_current_actor: true, blocker_code: null },
        source_versions: { pending_row_md5: pendingRow.source_row_md5, overtime_row_md5: overageRow.source_row_md5 },
      };
    },
    createClearance: async (input) => {
      test.createCalls += 1;
      test.lastCreate = clone(input);
      await new Promise((resolve) => setTimeout(resolve, 80));
      if (test.createBehavior === "uncertain-found") {
        test.history.push({ clearance_id: crypto.randomUUID(), student_id: "student-1", request_identity: input.requestIdentity, idempotency_key: input.requestIdentity });
        throw new TypeError("Failed to fetch");
      }
      if (test.createBehavior === "uncertain-missing") throw new TypeError("Network timeout");
      if (test.createBehavior === "stable-error") throw Object.assign(new Error("LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT"), { code: "P0001", details: "DB stable business blocker", hint: "reload sources" });
      return [{ clearance_id: crypto.randomUUID(), idempotent_replay: false }];
    },
    previewReversal: async (input) => ({
      contract_version: "lesson_clearance_reversal_preview_v1", request_identity: input.requestIdentity,
      reversal_manifest_sha256: `reversal-${input.requestIdentity}`, writer_revalidation_required: true,
      original_clearance: { clearance_id: input.clearanceId, allocated_minutes: 60, pending_source_planned_id: pending[0].pending_source_planned_id, overtime_source_actual_id: overages[0].overtime_source_actual_id },
      current_state: { is_effective: true, already_reversed: false, pending_before_reversal_minutes: 60, pending_after_reversal_minutes: 120, overtime_before_reversal_minutes: 0, overtime_after_reversal_minutes: 60, affects_active_claim: false },
      forward: { involves_locked_history: false, only_forward: false, forward_destination_month: null },
      authorization: { can_reverse: true, blocker_code: null },
    }),
    reverseClearance: async (input) => {
      test.reversalCalls += 1;
      test.lastReversal = clone(input);
      await new Promise((resolve) => setTimeout(resolve, 80));
      return [{ reversal_clearance_id: crypto.randomUUID(), idempotent_replay: false }];
    },
  };
  const controller = createLessonClearanceWorkspace({ api, getRole: () => "admin" });
  controller.init();
  globalThis.__PHASE2C_D2A_TEST__ = { controller, test };
});

const openWorkspace = async () => {
  await page.click("#openLessonClearanceWorkspaceButton");
  await page.waitForSelector("#lessonClearanceWorkspaceContent:not(.is-hidden)");
};
const prepareCreate = async (
  overageId = "20000000-0000-4000-8000-000000000001",
  businessNote = "Mock业务负责人核对",
) => {
  await page.selectOption("#lessonClearancePendingSelect", "10000000-0000-4000-8000-000000000001");
  await page.selectOption("#lessonClearanceOverageSelect", overageId);
  await page.fill("#lessonClearanceAllocatedMinutesInput", "60");
  await page.dispatchEvent("#lessonClearanceAllocatedMinutesInput", "change");
  await page.fill("#lessonClearanceBusinessNoteInput", businessNote);
  await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
  try {
    await page.waitForSelector(".lesson-clearance-preview-card", { timeout: 3000 });
  } catch (error) {
    const diagnostic = await page.evaluate(() => ({
      selection: structuredClone(globalThis.__PHASE2C_D2A_TEST__.controller.state.selection),
      counters: structuredClone(globalThis.__PHASE2C_D2A_TEST__.controller.counters),
      selectionText: document.querySelector("#lessonClearanceSelectionPanel")?.innerText,
      previewText: document.querySelector("#lessonClearancePreviewPanel")?.innerText,
    }));
    throw new Error(`Preview did not render: ${JSON.stringify(diagnostic)}; ${error.message}`);
  }
};

await openWorkspace();
assert.equal(await page.locator("#lessonClearancePendingSelect").inputValue(), "", "FIFO recommendation is not auto-selected");
assert.equal(await page.locator("#lessonClearanceOverageSelect").inputValue(), "", "overage is not auto-selected");
assert.equal(await page.locator("#lessonClearanceConfirmButton").isDisabled(), true);

await prepareCreate();
assert.equal(await page.locator("#lessonClearanceConfirmButton").isDisabled(), false);
const beforeSafeCreate = await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls);
await page.click("#lessonClearanceConfirmButton");
await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), beforeSafeCreate, "safe prepare never calls writer");
assert.equal(await page.evaluate(() => document.activeElement?.id), "lessonClearanceFinalConfirmCloseButton", "final dialog receives focus");
const dialogText = await page.locator("#lessonClearanceFinalConfirmContent").innerText();
for (const expected of ["测试学生", "2026-08-14", "老师甲 / EJU数学", "60分钟", "符合建议顺序", "业务说明", "Mock业务负责人核对", "不修改原课时、老师工资、既有账单或收款"]) assert.match(dialogText, new RegExp(expected));
assert.doesNotMatch(dialogText, /测试业务归属|10000000-0000|20000000-0000|manifest|request identity|fingerprint/);
assert.equal(await page.locator("#lessonClearanceFinalConfirmDialog .lesson-clearance-system-details").first().evaluate((node) => node.open), false, "system details default collapsed");
assert.equal(await page.locator(".lesson-clearance-final-note > p").textContent(), "Mock业务负责人核对");
await page.keyboard.press("Escape");
await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmDialog")?.classList.contains("is-hidden"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), beforeSafeCreate, "Escape closes safe dialog without writer");

const firstBinding = await page.evaluate(() => {
  const selection = globalThis.__PHASE2C_D2A_TEST__.controller.state.selection;
  return { identity: selection.requestIdentity, manifest: selection.previewInputSnapshot.manifest };
});
await page.fill("#lessonClearanceBusinessNoteInput", "重新Preview后的业务说明");
await page.waitForFunction(() => document.querySelector("#lessonClearanceConfirmButton")?.disabled === true);
const invalidated = await page.evaluate(() => {
  const selection = globalThis.__PHASE2C_D2A_TEST__.controller.state.selection;
  return { identity: selection.requestIdentity, preview: selection.preview, snapshot: selection.previewInputSnapshot };
});
assert.notEqual(invalidated.identity, firstBinding.identity, "business note change rotates request identity");
assert.equal(invalidated.preview, null, "business note change invalidates Preview");
assert.equal(invalidated.snapshot, null, "business note change removes Preview input snapshot");
assert.equal(await page.locator("#lessonClearanceFinalConfirmDialog").getAttribute("aria-hidden"), "true");
await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
try {
  await page.waitForSelector(".lesson-clearance-preview-card", { timeout: 3000 });
} catch (error) {
  const diagnostic = await page.evaluate(() => ({
    selection: structuredClone(globalThis.__PHASE2C_D2A_TEST__.controller.state.selection),
    previewCalls: globalThis.__PHASE2C_D2A_TEST__.test.previewCalls,
    lastPreview: structuredClone(globalThis.__PHASE2C_D2A_TEST__.test.lastPreview),
    selectionText: document.querySelector("#lessonClearanceSelectionPanel")?.innerText,
    previewText: document.querySelector("#lessonClearancePreviewPanel")?.innerText,
    workspaceMessage: document.querySelector("#lessonClearanceWorkspaceMessage")?.innerText,
  }));
  throw new Error(`Re-Preview did not render: ${JSON.stringify(diagnostic)}; ${error.message}`);
}
const rebound = await page.evaluate(() => {
  const selection = globalThis.__PHASE2C_D2A_TEST__.controller.state.selection;
  return { identity: selection.requestIdentity, manifest: selection.previewInputSnapshot.manifest, note: selection.previewInputSnapshot.businessNote };
});
assert.notEqual(rebound.identity, firstBinding.identity, "re-Preview uses new request identity");
assert.notEqual(rebound.manifest, firstBinding.manifest, "re-Preview uses new manifest");
assert.equal(rebound.note, "重新Preview后的业务说明");
await page.click("#lessonClearanceConfirmButton");
await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
assert.equal(await page.locator(".lesson-clearance-final-note > p").textContent(), "重新Preview后的业务说明");
await page.click("#lessonClearanceFinalConfirmCloseButton");

await page.evaluate(() => {
  globalThis.__PHASE2C_D2A_TEST__.controller.state.selection.previewInputSnapshot = null;
});
await page.click("#lessonClearanceConfirmButton");
await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceMessage")?.textContent.includes("业务说明缺失，请重新核对"));
assert.equal(await page.locator("#lessonClearanceFinalConfirmDialog").getAttribute("aria-hidden"), "true");
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), beforeSafeCreate, "missing snapshot never calls writer");

const injectionNote = `第一行<script>globalThis.__INJECTED__=true</script>\n第二行 <b>粗体</b> "引号" '单引号'`;
await prepareCreate("20000000-0000-4000-8000-000000000001", injectionNote);
await page.click("#lessonClearanceConfirmButton");
await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
assert.equal(await page.locator(".lesson-clearance-final-note > p").textContent(), injectionNote, "HTML-like business note renders as exact text");
assert.equal(await page.locator(".lesson-clearance-final-note script").count(), 0, "business note never creates script nodes");
assert.equal(await page.locator(".lesson-clearance-final-note b").count(), 0, "business note never creates HTML nodes");
assert.equal(await page.evaluate(() => globalThis.__INJECTED__ === true), false, "business note script text never executes");
await page.click("#lessonClearanceFinalConfirmCloseButton");

const longBusinessNote = `同一自然周课时差额清偿：${"这是一段用于验证中文长说明自动换行且不会拉伸网格或按钮区的审计文字。".repeat(8)}\n第二行继续验证换行。`;
await prepareCreate("20000000-0000-4000-8000-000000000001", longBusinessNote);
await page.click("#lessonClearanceConfirmButton");
await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
assert.equal(await page.locator(".lesson-clearance-final-note > p").textContent(), longBusinessNote);

const layoutMeasurements = [];
for (const width of [1440, 1024, 768, 390]) {
  await page.setViewportSize({ width, height: 900 });
  const measurement = await page.evaluate(() => ({
    documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    dialogOverflow: document.querySelector("#lessonClearanceFinalConfirmDialog").scrollWidth - document.querySelector("#lessonClearanceFinalConfirmDialog").clientWidth,
    panelOverflow: document.querySelector(".lesson-clearance-final-dialog-panel").scrollWidth - document.querySelector(".lesson-clearance-final-dialog-panel").clientWidth,
    bodyScrollable: document.querySelector(".lesson-clearance-final-dialog-body").scrollHeight >= document.querySelector(".lesson-clearance-final-dialog-body").clientHeight,
    noteOverflow: document.querySelector(".lesson-clearance-final-note").scrollWidth - document.querySelector(".lesson-clearance-final-note").clientWidth,
    footerVisible: Boolean(document.querySelector(".lesson-clearance-final-dialog-panel footer")?.getClientRects().length),
  }));
  assert.ok(measurement.documentOverflow <= 0, `${width}px document overflow`);
  assert.ok(measurement.dialogOverflow <= 0, `${width}px dialog overflow`);
  assert.ok(measurement.panelOverflow <= 0, `${width}px panel overflow`);
  assert.ok(measurement.noteOverflow <= 0, `${width}px business note overflow`);
  assert.equal(measurement.footerVisible, true, `${width}px dialog footer remains rendered`);
  layoutMeasurements.push({ width, ...measurement });
}

await page.setViewportSize({ width: 1440, height: 1000 });
await page.evaluate(() => {
  const button = document.querySelector("#lessonClearanceFinalSubmitButton");
  button.click();
  button.click();
});
await page.waitForFunction(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls === 1);
await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmDialog")?.classList.contains("is-hidden"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), 1, "double click produces one mock writer call");
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.lastCreate.businessNote), longBusinessNote, "mock writer receives the bound Preview snapshot note");

await prepareCreate();
await page.evaluate(() => { globalThis.__PHASE2C_D2A_TEST__.test.createBehavior = "uncertain-found"; });
await page.click("#lessonClearanceConfirmButton");
await page.click("#lessonClearanceFinalSubmitButton");
await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceMessage").textContent.includes("没有重复提交"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), 2, "uncertain result does not retry writer");

await prepareCreate();
await page.evaluate(() => { globalThis.__PHASE2C_D2A_TEST__.test.createBehavior = "uncertain-missing"; });
await page.click("#lessonClearanceConfirmButton");
await page.click("#lessonClearanceFinalSubmitButton");
await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceMessage").textContent.includes("尚未找到本次请求"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), 3, "missing uncertain result invalidates instead of retrying writer");

await prepareCreate();
await page.evaluate(() => { globalThis.__PHASE2C_D2A_TEST__.test.createBehavior = "stable-error"; });
await page.click("#lessonClearanceConfirmButton");
await page.click("#lessonClearanceFinalSubmitButton");
await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmMessage").textContent.includes("待补对象当前余额不足"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.createCalls), 4);
const errorLayout = await page.evaluate(() => ({
  dialogOverflow: document.querySelector("#lessonClearanceFinalConfirmDialog").scrollWidth - document.querySelector("#lessonClearanceFinalConfirmDialog").clientWidth,
  panelOverflow: document.querySelector(".lesson-clearance-final-dialog-panel").scrollWidth - document.querySelector(".lesson-clearance-final-dialog-panel").clientWidth,
}));
assert.ok(errorLayout.dialogOverflow <= 0 && errorLayout.panelOverflow <= 0, "stable error message does not stretch dialog grid");
await page.click("#lessonClearanceFinalConfirmCancelButton");

await prepareCreate("20000000-0000-4000-8000-000000000002");
const crossIdentity1 = await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.controller.state.selection.requestIdentity);
assert.match(await page.locator(".lesson-clearance-preview-card").innerText(), /确认跨老师/);
await page.check('[data-clearance-confirmation="crossTeacher"]');
const crossIdentity2 = await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.controller.state.selection.requestIdentity);
assert.notEqual(crossIdentity2, crossIdentity1, "cross-teacher confirmation invalidates Preview and rotates identity");
assert.equal(await page.locator("#lessonClearanceConfirmButton").isDisabled(), true);
await page.check('[data-clearance-confirmation="crossSubject"]');
await page.click("#lessonClearancePreviewButton");
assert.equal(await page.locator("#lessonClearanceConfirmButton").isDisabled(), false);

await page.click('[data-clearance-tab="history"]');
await page.click('[data-preview-clearance-reversal="30000000-0000-4000-8000-000000000001"]');
await page.waitForSelector("#lessonClearanceReversalReasonInput");
await page.fill("#lessonClearanceReversalReasonInput", "Mock撤销原因");
const beforeSafeReversal = await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.reversalCalls);
await page.click("#lessonClearancePrepareReversalButton");
await page.waitForSelector('#lessonClearanceFinalConfirmDialog[data-mode="reversal"]:not(.is-hidden)');
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.reversalCalls), beforeSafeReversal, "safe reversal prepare never calls writer");
await page.evaluate(() => {
  const button = document.querySelector("#lessonClearanceFinalSubmitButton");
  button.click();
  button.click();
});
await page.waitForFunction(() => globalThis.__PHASE2C_D2A_TEST__.test.reversalCalls === 1);
await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmDialog")?.classList.contains("is-hidden"));
assert.equal(await page.evaluate(() => globalThis.__PHASE2C_D2A_TEST__.test.reversalCalls), 1, "reversal double click produces one mock writer call");

const final = await page.evaluate(() => ({ test: globalThis.__PHASE2C_D2A_TEST__.test, counters: globalThis.__PHASE2C_D2A_TEST__.controller.counters }));
assert.equal(final.counters.createWriters, 4);
assert.equal(final.counters.reversalWriters, 1);
assert.ok(final.test.historyReads >= 1);
assert.deepEqual(consoleProblems, []);
const labels = await page.evaluate(() => [
  "lessonClearancePendingSelect", "lessonClearanceOverageSelect", "lessonClearanceAllocatedMinutesInput", "lessonClearanceOperationDateInput",
].every((id) => document.getElementById(id)?.labels?.length > 0));
assert.equal(labels, true, "selection fields retain accessible labels");
await browser.close();
console.log(JSON.stringify({ layoutMeasurements, errorLayout, consoleProblems, createWriterCalls: final.test.createCalls, reversalWriterCalls: final.test.reversalCalls, historyReads: final.test.historyReads }));
console.log("SCHOOL_PHASE2C_D2A_CLEARANCE_SUBMIT_BROWSER_PASS");
