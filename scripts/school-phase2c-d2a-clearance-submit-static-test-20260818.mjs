import assert from "node:assert/strict";
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const read = (path) => fs.readFileSync(path, "utf8");
const html = read("lesson.html");
const app = read("js/lesson-app.js");
const page = read("js/pages/lesson-page.js");
const api = read("js/api/lesson-clearance-api.js");
const component = read("js/components/lesson-clearance-workspace.js");
const state = read("js/utils/lesson-clearance-state.js");
const config = read("js/config.js");

assert.match(config, /APP_VERSION = "v10\.5\.52"/);
for (const source of [html, app, page, component]) {
  assert.doesNotMatch(source, /phase2c-d1-clearance-workspace-20260817-2/);
}
assert.match(html, /phase2c-d2-a3-clearance-completion-20260818-1/);
assert.match(html, /id="lessonClearanceConfirmButton"[^>]*disabled>核对并准备清偿</);
assert.match(html, /id="lessonClearanceFinalConfirmDialog"/);
assert.match(html, /id="lessonClearanceFinalSubmitButton"/);
assert.match(html, /点击后会立即写入正式清偿记录/);
assert.match(component, /本动作只建立课时差额清偿事实，不修改原课时、老师工资、既有账单或收款/);
assert.match(component, /确认清偿\$\{integerLabel\(preview\.requested_minutes\)\}分钟/);
assert.match(component, /确认撤销该清偿/);
assert.match(component, /businessNoteValue\.textContent = inputSnapshot\.businessNote/);
assert.match(component, /businessNoteLabel\.textContent = "业务说明"/);
assert.doesNotMatch(component, /\$\{inputSnapshot\.businessNote\}/);

assert.doesNotMatch(page + component + state + html, /\.rpc\s*\(/);
assert.doesNotMatch(page + component + state + html, /\.from\s*\([^)]*\)\s*\.\s*(insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(api + page + component + state + html, /service_role|serviceRole|SUPABASE_SERVICE/);
assert.doesNotMatch(component + state, /localStorage|sessionStorage/);

const readRpcNames = [
  "school_list_lesson_clearance_pending_balances_v3",
  "school_list_lesson_clearance_available_overages_v2",
  "school_list_student_package_credit_lots_v2",
  "school_list_cross_month_makeup_projection_v2",
  "school_get_lesson_clearance_dashboard_summary_v1",
  "school_preview_lesson_clearance_v2",
  "school_preview_lesson_clearance_reversal_v1",
  "school_list_lesson_clearance_history_v2",
];
for (const name of readRpcNames) assert.equal(api.split(name).length - 1, 1, name);
assert.equal(api.split("school_create_lesson_clearance").length - 1, 1);
assert.equal(api.split("school_reverse_lesson_clearance").length - 1, 1);
assert.equal((api.match(/supabase\.rpc\(/g) || []).length, 2, "one read and one write transport only");

for (const param of [
  "p_clearance_type", "p_pending_source_planned_id", "p_overtime_source_actual_id",
  "p_allocated_minutes", "p_operation_date", "p_deviation_reason_code", "p_deviation_note",
  "p_business_note", "p_administrative_financial_treatment", "p_idempotency_key",
]) assert.match(api, new RegExp(`${param}:`));
for (const param of ["p_original_clearance_id", "p_operation_date", "p_reason", "p_idempotency_key"]) {
  assert.match(api, new RegExp(`${param}:`));
}

const createBody = component.match(/async function submitCreate\(\) \{[\s\S]*?\n  \}/)?.[0] || "";
const reversalBody = component.match(/async function submitReversal\(\) \{[\s\S]*?\n  \}/)?.[0] || "";
assert.equal((component.match(/api\.createClearance\(/g) || []).length, 1);
assert.equal((component.match(/api\.reverseClearance\(/g) || []).length, 1);
assert.match(createBody, /api\.createClearance\(payload\)/);
assert.match(reversalBody, /api\.reverseClearance\(payload\)/);
assert.match(component, /dom\.confirmButton\?\.addEventListener\("click", openCreateFinalDialog\)/);
assert.match(component, /if \(dom\.finalDialog\.dataset\.mode === "create"\) submitCreate\(\)/);
assert.match(component, /if \(dom\.finalDialog\.dataset\.mode === "reversal"\) submitReversal\(\)/);
assert.match(component, /state\.selection\.submitting/);
assert.match(component, /resolveUncertainResult/);
assert.match(component, /清偿结果正在确认，请勿重复提交/);
assert.match(state, /previewBinding/);
assert.match(state, /previewInputSnapshot/);
assert.match(state, /业务说明缺失，请重新核对/);
assert.match(state, /return clone\(this\.snapshotRequestFields\(\)\)/);
assert.match(state, /preview_manifest_sha256/);
assert.match(state, /pending_row_md5/);
assert.match(state, /overtime_row_md5/);
assert.match(state, /setConfirmation/);
assert.match(state, /invalidatePreview\(true, true\)/);
assert.match(state, /can_execute_for_current_actor/);
assert.match(state, /this\.capabilities\(\)\.locked/);
assert.match(component, /请选择，不自动勾选/);
assert.match(component, /P002不会进入本区/);

const changed = execFileSync("git", ["diff", "--name-only"], { encoding: "utf8" }).trim().split("\n").filter(Boolean);
assert.equal(changed.filter((path) => path.startsWith("sql/")).every(
  (path) => path.includes("school_phase2c_d2_a2_pending_operational_date_reader_v3"),
), true, "only the approved versioned read-only reader SQL may change");

console.log(JSON.stringify({ changed, readRpcNames, writeRpcNames: ["school_create_lesson_clearance", "school_reverse_lesson_clearance"] }));
console.log("SCHOOL_PHASE2C_D2A_CLEARANCE_SUBMIT_STATIC_PASS");
