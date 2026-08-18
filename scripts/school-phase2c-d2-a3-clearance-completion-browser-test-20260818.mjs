import assert from "node:assert/strict";
import { createRequire } from "node:module";

const moduleRoot = process.env.PHASE2C_D2A_NODE_MODULES;
if (!moduleRoot) throw new Error("PHASE2C_D2A_NODE_MODULES_REQUIRED");
const { chromium } = createRequire(import.meta.url)(`${moduleRoot}/playwright`);
const baseUrl = process.env.PHASE2C_D2A_BASE_URL || "http://127.0.0.1:8019";
const browser = await chromium.launch({ headless: true, executablePath: process.env.PHASE2C_D2A_BROWSER_EXECUTABLE || undefined });

async function createScenario(name) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const consoleProblems = [];
  page.on("console", (message) => {
    if (["error", "warning"].includes(message.type())) consoleProblems.push(`${message.type()}:${message.text()}`);
  });
  page.on("pageerror", (error) => consoleProblems.push(`pageerror:${error.message}`));
  await page.route("**/js/lesson-app.js*", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "export {};" }));
  await page.route("https://cdn.jsdelivr.net/**", (route) => route.fulfill({ status: 200, contentType: "application/javascript", body: "" }));
  await page.goto(`${baseUrl}/lesson.html`, { waitUntil: "domcontentloaded" });
  await page.evaluate(async (scenario) => {
    document.documentElement.classList.remove("auth-pending");
    const { createLessonClearanceWorkspace } = await import("/js/components/lesson-clearance-workspace.js?v=phase2c-d2-a3-clearance-completion-20260818-1");
    const pending = {
      pending_source_planned_id: "10000000-0000-4000-8000-000000000001", student_id: "student-1", student_display_name: "测试学生",
      business_entity_id: "entity-1", teacher_id: "teacher-1", teacher_display_name: "老师甲", subject_id: "subject-1", subject_display_name: "科目甲",
      operational_display_date: "2026-08-14", source_year_month: "2026-08", remaining_minutes: 60, remaining_amount_jpy: 9000,
      currently_allocatable_minutes: 60, source_row_md5: "pending-md5", fifo_rank: 1, can_be_candidate: true, active_claimed: false, is_locked: false,
    };
    const overage = {
      overtime_source_actual_id: "20000000-0000-4000-8000-000000000001", student_id: "student-1", student_display_name: "测试学生",
      business_entity_id: "entity-1", teacher_id: "teacher-1", teacher_display_name: "老师甲", subject_id: "subject-1", subject_display_name: "科目甲",
      actual_lesson_date: "2026-08-11", student_settlement_month: "2026-08", teacher_wage_month: "2026-08", available_minutes: 60,
      available_amount_jpy: 9000, currently_allocatable_minutes: 60, source_row_md5: "overage-md5", display_rank: 1, can_be_candidate: true, active_claimed: false, is_locked: false,
    };
    const metrics = { previewCalls: 0, createCalls: 0, reversalCalls: 0, historyReads: 0, dashboardReads: 0, mainRefreshes: 0, refreshFailures: 0 };
    let history = [];
    const clearanceId = "30000000-0000-4000-8000-000000000001";
    const createResult = (idempotentReplay = false) => ({
      clearance_id: clearanceId, pending_remaining_minutes: 0, overtime_remaining_minutes: 0,
      requires_forward_adjustment: false, recommended_pending_source_id: pending.pending_source_planned_id,
      deviated_from_recommendation: false, idempotent_replay: idempotentReplay,
    });
    const historyRow = (input, mismatch = false) => ({
      clearance_id: clearanceId, clearance_type: input.clearanceType,
      request_identity: input.requestIdentity, idempotency_key: input.requestIdentity,
      pending_source_planned_id: mismatch ? "10000000-0000-4000-8000-000000000099" : input.pendingSourcePlannedId,
      overtime_source_actual_id: input.overtimeSourceActualId, allocated_minutes: input.allocatedMinutes,
      operation_date: input.operationDate, business_note: input.businessNote,
      input_manifest_sha256: "b".repeat(64), is_effective: true, is_reversed: false,
    });
    const api = {
      fetchPendingBalances: async () => ({ items: [structuredClone(pending)], summary: {} }),
      fetchAvailableOverages: async () => ({ items: [structuredClone(overage)], summary: {} }),
      fetchPackageCreditLots: async () => ({ items: [{ package_lot_id: "P002", student_id: "student-2", remaining_minutes: 1200, can_consume: false, can_be_candidate: false, read_only: true }], summary: {} }),
      fetchCrossMonthProjection: async () => ({ items: [], summary: {} }),
      fetchDashboardSummary: async () => { metrics.dashboardReads += 1; return { pending_source_count: 1, pending_remaining_minutes: 60, overage_source_count: 1, available_overtime_minutes: 60, package_lot_count: 1, package_remaining_minutes: 1200, history_count: history.length }; },
      fetchHistory: async () => { metrics.historyReads += 1; return structuredClone(history); },
      previewClearance: async (input) => {
        metrics.previewCalls += 1;
        return {
          request_identity: input.requestIdentity, clearance_type: input.clearanceType, requested_minutes: input.allocatedMinutes,
          operation_date: input.operationDate, preview_manifest_sha256: "a".repeat(64), writer_revalidation_required: true, reservation_created: false,
          pending_source: { planned_id: pending.pending_source_planned_id, student_id: "student-1", student_name: "测试学生", before_remaining_minutes: 60, after_remaining_minutes: 0, amount_jpy: -9000, active_claimed: false, source_locked: false },
          overtime_source: { actual_id: overage.overtime_source_actual_id, student_id: "student-1", student_name: "测试学生", before_available_minutes: 60, after_available_minutes: 0, amount_jpy: 9000, active_claimed: false, source_locked: false },
          comparison: { same_student: true, same_business_entity: true, same_unit_price: true, same_teacher: true, same_subject: true },
          fifo: { recommended_pending_planned_id: pending.pending_source_planned_id, is_recommended_target: true, deviation_required: false, deviation_reason_valid: true },
          financial: { net_amount_jpy: 0, requires_forward_adjustment: false }, authorization: { can_execute_for_current_actor: true },
          source_versions: { pending_row_md5: pending.source_row_md5, overtime_row_md5: overage.source_row_md5 },
        };
      },
      createClearance: async (input) => {
        metrics.createCalls += 1;
        await new Promise((resolve) => setTimeout(resolve, 60));
        if (scenario === "stable-error") throw Object.assign(new Error("LESSON_CLEARANCE_PENDING_BALANCE_INSUFFICIENT"), { code: "P0001" });
        if (scenario === "network-missing") throw new TypeError("Failed to fetch");
        if (scenario === "network-found") { history = [historyRow(input)]; throw new TypeError("Network timeout"); }
        if (scenario === "idempotent-exact") { history = [historyRow(input)]; return [createResult(true)]; }
        if (scenario === "idempotent-mismatch") { history = [historyRow(input, true)]; return [createResult(true)]; }
        return [createResult(false)];
      },
      previewReversal: async () => { throw new Error("REVERSAL_NOT_CALLED"); },
      reverseClearance: async () => { metrics.reversalCalls += 1; throw new Error("REVERSAL_NOT_CALLED"); },
    };
    const onCreateSuccess = async ({ allocatedMinutes }) => {
      metrics.mainRefreshes += 1;
      if (scenario === "refresh-failure") throw new Error("mock reader failed");
      const message = document.querySelector("#lessonMessageArea");
      message.className = "message message-success";
      message.textContent = `课时差额清偿成功：${allocatedMinutes}分钟。`;
    };
    const onCreateRefreshFailure = () => {
      metrics.refreshFailures += 1;
      const message = document.querySelector("#lessonMessageArea");
      message.className = "message message-error";
      message.textContent = "清偿已成功，但页面刷新失败，请重新查询。";
    };
    const controller = createLessonClearanceWorkspace({ api, getRole: () => "admin", onCreateSuccess, onCreateRefreshFailure });
    controller.init();
    globalThis.__A3__ = { controller, metrics, scenario };
  }, name);
  return { page, consoleProblems };
}

async function openAndPrepare(page, { submit = false, doubleClick = false } = {}) {
  await page.click("#openLessonClearanceWorkspaceButton");
  await page.waitForSelector("#lessonClearanceWorkspaceContent:not(.is-hidden)");
  await page.selectOption("#lessonClearancePendingSelect", "10000000-0000-4000-8000-000000000001");
  await page.selectOption("#lessonClearanceOverageSelect", "20000000-0000-4000-8000-000000000001");
  await page.fill("#lessonClearanceAllocatedMinutesInput", "60");
  await page.dispatchEvent("#lessonClearanceAllocatedMinutesInput", "change");
  await page.fill("#lessonClearanceOperationDateInput", "2026-08-18");
  await page.dispatchEvent("#lessonClearanceOperationDateInput", "change");
  await page.fill("#lessonClearanceBusinessNoteInput", "A3浏览器清偿说明");
  await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
  await page.waitForSelector(".lesson-clearance-preview-card");
  await page.click("#lessonClearanceConfirmButton");
  await page.waitForSelector("#lessonClearanceFinalConfirmDialog:not(.is-hidden)");
  if (submit) {
    if (doubleClick) await page.locator("#lessonClearanceFinalSubmitButton").evaluate((button) => { button.click(); button.click(); });
    else await page.click("#lessonClearanceFinalSubmitButton");
  }
}

{
  const { page, consoleProblems } = await createScenario("success");
  await page.click("#openLessonClearanceWorkspaceButton");
  await page.waitForSelector("#lessonClearanceWorkspaceContent:not(.is-hidden)");
  const required = await page.locator("#lessonClearanceSelectionPanel .required-mark").allTextContents();
  assert.deepEqual(required, ["必填", "必填", "必填", "必填", "必填"]);
  for (const id of ["lessonClearancePendingSelect", "lessonClearanceOverageSelect", "lessonClearanceAllocatedMinutesInput", "lessonClearanceOperationDateInput", "lessonClearanceBusinessNoteInput"]) {
    assert.ok(await page.locator(`#${id}`).evaluate((element) => element.labels?.length === 1), `${id} has one accessible label`);
  }
  assert.equal((await page.locator("#lessonClearancePendingSelect").inputValue()), "");
  await page.click("#lessonClearancePreviewButton");
  assert.match(await page.locator("#lessonClearanceSelectionPanel").innerText(), /请选择一个待补对象和一条可用超额/);
  assert.equal(await page.evaluate(() => globalThis.__A3__.metrics.previewCalls), 0);
  await page.selectOption("#lessonClearancePendingSelect", "10000000-0000-4000-8000-000000000001");
  await page.selectOption("#lessonClearanceOverageSelect", "20000000-0000-4000-8000-000000000001");
  await page.fill("#lessonClearanceAllocatedMinutesInput", "0");
  await page.fill("#lessonClearanceBusinessNoteInput", "说明");
  await page.click("#lessonClearancePreviewButton");
  assert.match(await page.locator("#lessonClearanceSelectionPanel").innerText(), /大于0的整数分钟/);
  await page.fill("#lessonClearanceAllocatedMinutesInput", "60");
  await page.locator("#lessonClearanceOperationDateInput").evaluate((input) => {
    input.value = "";
    input.dispatchEvent(new Event("change", { bubbles: true }));
  });
  assert.equal(await page.locator("#lessonClearanceOperationDateInput").inputValue(), "");
  await page.fill("#lessonClearanceBusinessNoteInput", "说明");
  await page.locator("#lessonClearancePreviewButton").evaluate((button) => button.click());
  await page.waitForTimeout(100);
  const dateValidation = await page.evaluate(() => ({
    error: globalThis.__A3__.controller.state.selection.previewError,
    operationDate: globalThis.__A3__.controller.state.selection.operationDate,
    businessNote: globalThis.__A3__.controller.state.selection.businessNote,
  }));
  assert.match(dateValidation.error, /请选择清偿日期/, JSON.stringify(dateValidation));
  assert.match(await page.locator("#lessonClearanceSelectionPanel").innerText(), /请选择清偿日期/);
  assert.equal(await page.evaluate(() => globalThis.__A3__.metrics.createCalls), 0);
  for (const width of [1440, 1024, 768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    const overflow = await page.evaluate(() => ({
      document: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      dialog: document.querySelector("#lessonClearanceWorkspaceDialog").scrollWidth - document.querySelector("#lessonClearanceWorkspaceDialog").clientWidth,
      panel: document.querySelector(".lesson-clearance-dialog-panel").scrollWidth - document.querySelector(".lesson-clearance-dialog-panel").clientWidth,
    }));
    assert.ok(overflow.document <= 0 && overflow.dialog <= 0 && overflow.panel <= 0, `${width}px no horizontal overflow`);
  }
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

{
  const { page, consoleProblems } = await createScenario("success");
  await openAndPrepare(page, { submit: true, doubleClick: true });
  await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceDialog")?.classList.contains("is-hidden"));
  const outcome = await page.evaluate(() => ({ metrics: globalThis.__A3__.metrics, message: document.querySelector("#lessonMessageArea")?.textContent, selection: globalThis.__A3__.controller.state.selection }));
  assert.equal(outcome.metrics.previewCalls, 1);
  assert.equal(outcome.metrics.createCalls, 1);
  assert.equal(outcome.metrics.mainRefreshes, 1);
  assert.equal(outcome.message, "课时差额清偿成功：60分钟。");
  assert.equal(outcome.selection.preview, null);
  assert.equal(outcome.selection.previewInputSnapshot, null);
  assert.equal(outcome.selection.requestIdentity, "");
  assert.equal(await page.locator("#lessonClearanceFinalConfirmDialog").getAttribute("aria-hidden"), "true");
  const readsBeforeReopen = outcome.metrics.dashboardReads;
  await page.click("#openLessonClearanceWorkspaceButton");
  await page.waitForFunction((before) => globalThis.__A3__.metrics.dashboardReads === before + 1, readsBeforeReopen);
  assert.equal(await page.locator("#lessonClearancePendingSelect").inputValue(), "");
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

for (const scenario of ["idempotent-exact", "network-found"]) {
  const { page, consoleProblems } = await createScenario(scenario);
  await openAndPrepare(page, { submit: true });
  await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceDialog")?.classList.contains("is-hidden"));
  const metrics = await page.evaluate(() => globalThis.__A3__.metrics);
  assert.equal(metrics.createCalls, 1);
  assert.equal(metrics.historyReads, 2, `${scenario} includes initial History load plus one result confirmation read`);
  assert.equal(metrics.mainRefreshes, 1);
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

for (const scenario of ["idempotent-mismatch", "network-missing"]) {
  const { page, consoleProblems } = await createScenario(scenario);
  await openAndPrepare(page, { submit: true });
  await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmMessage")?.textContent.includes("请勿重复提交"));
  const frozen = await page.evaluate(() => ({
    metrics: globalThis.__A3__.metrics,
    identity: globalThis.__A3__.controller.state.selection.requestIdentity,
    snapshot: globalThis.__A3__.controller.state.selection.previewInputSnapshot,
  }));
  assert.equal(frozen.metrics.createCalls, 1);
  assert.equal(frozen.metrics.mainRefreshes, 0);
  assert.ok(frozen.identity && frozen.snapshot?.requestIdentity === frozen.identity);
  assert.equal(await page.locator("#lessonClearanceFinalSubmitButton").isDisabled(), true);
  assert.equal(await page.locator("#lessonClearanceWorkspaceDialog").getAttribute("aria-hidden"), "false");
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

{
  const { page, consoleProblems } = await createScenario("stable-error");
  await openAndPrepare(page, { submit: true });
  await page.waitForFunction(() => document.querySelector("#lessonClearanceFinalConfirmDialog")?.classList.contains("is-hidden"));
  assert.equal(await page.locator("#lessonClearanceWorkspaceDialog").getAttribute("aria-hidden"), "false");
  assert.match(await page.locator("#lessonClearanceWorkspaceMessage").innerText(), /待补对象当前余额不足/);
  const rejected = await page.evaluate(() => ({ metrics: globalThis.__A3__.metrics, selection: globalThis.__A3__.controller.state.selection }));
  assert.equal(rejected.metrics.createCalls, 1);
  assert.equal(rejected.metrics.mainRefreshes, 0);
  assert.equal(rejected.selection.preview, null);
  assert.equal(rejected.selection.previewInputSnapshot, null);
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

{
  const { page, consoleProblems } = await createScenario("refresh-failure");
  await openAndPrepare(page, { submit: true });
  await page.waitForFunction(() => document.querySelector("#lessonClearanceWorkspaceDialog")?.classList.contains("is-hidden"));
  const result = await page.evaluate(() => ({ metrics: globalThis.__A3__.metrics, message: document.querySelector("#lessonMessageArea")?.textContent }));
  assert.equal(result.metrics.createCalls, 1);
  assert.equal(result.metrics.mainRefreshes, 1);
  assert.equal(result.metrics.refreshFailures, 1);
  assert.equal(result.message, "清偿已成功，但页面刷新失败，请重新查询。");
  assert.deepEqual(consoleProblems, []);
  await page.close();
}

await browser.close();
console.log("SCHOOL_PHASE2C_D2_A3_CLEARANCE_COMPLETION_BROWSER_PASS");
