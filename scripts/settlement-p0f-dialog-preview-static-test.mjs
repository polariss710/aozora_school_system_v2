import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync("settlement.html", "utf8");
const css = fs.readFileSync("css/app.css", "utf8");
const api = fs.readFileSync("js/api/settlement-api.js", "utf8");
const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");
const app = fs.readFileSync("js/settlement-app.js", "utf8");
const rpc = fs.readFileSync(
  "sql/current/school_tuition_p0f_settlement_adjustment_dialog_preview_20260803.sql",
  "utf8"
);

assert.match(html, /settlement-adjustment-dialog-grid/);
assert.match(html, /当前已保存状态/);
assert.match(html, /表单待提交 Preview/);
assert.match(html, /id="settlementAdjustmentPreviewButton"[^>]*>重新预览/);
assert.match(html, /id="settlementAdjustmentSubmitButton"[^>]*disabled[^>]*>保存草稿/);
assert.match(html, /settlement-app\.js\?v=student-settlement-tokyo-month-close-20260810-2/);

assert.match(css, /\.settlement-adjustment-dialog-panel\s*\{[\s\S]*?width:\s*min\(1040px, 100%\)/);
assert.match(css, /grid-template-columns:\s*minmax\(0, 1\.12fr\) minmax\(330px, 0\.88fr\)/);
assert.match(css, /\.settlement-adjustment-dialog-body\s*\{[\s\S]*?overflow-y:\s*auto/);
assert.match(css, /\.settlement-adjustment-footer\s*\{[\s\S]*?flex:\s*0 0 auto/);
assert.match(css, /\.settlement-adjustment-dialog-grid,[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);

assert.match(api, /school_preview_student_settlement_adjustment_dialog/);
for (const parameter of [
  "p_student_id",
  "p_business_entity_id",
  "p_year_month",
  "p_source_treatment_mode",
  "p_settlement_exchange_rate",
  "p_settlement_exchange_rate_source",
  "p_settlement_exchange_rate_effective_date",
  "p_adjustment_mode",
  "p_explicit_user_amount_cny",
]) {
  assert.ok(api.includes(parameter), `missing API parameter ${parameter}`);
}

assert.doesNotMatch(page, /supabase\s*\.|\.rpc\s*\(/);
assert.match(page, /adjustmentPreviewRequestSequence \+= 1/);
assert.match(page, /requestSequence !== adjustmentPreviewRequestSequence/);
assert.match(page, /responsePreviewSignature\(result\) !== requestSignature/);
assert.match(page, /表单已变更，旧预览已失效/);
assert.match(page, /以下金额为数据库权威预览/);
assert.match(page, /dom\.adjustmentSubmitButton\.disabled = !canSave/);
assert.match(page, /projected_final_carryover_cny/);
assert.match(page, /source_planned_lesson_id/);
assert.match(page, /source_actual_lesson_id/);
assert.doesNotMatch(page, /net_lesson_variance_jpy\s*[+\-*\/]|system_difference_cny\s*[+\-*\/]/);

assert.match(app, /student-settlement-tokyo-month-close-20260810-2/g);
assert.match(rpc, /security definer/);
assert.match(rpc, /set search_path=pg_catalog,public/);
assert.match(rpc, /school_tuition_p0f_source_lines/);
assert.match(rpc, /school_tuition_p0b2_resolve_adjustment/);
assert.match(rpc, /grant execute[\s\S]*to anon,authenticated,service_role/);
const functionBody = rpc.match(/as \$function\$([\s\S]*?)\$function\$/)?.[1] || "";
assert.doesNotMatch(functionBody, /\b(insert|update|delete|merge|truncate)\b/i);

console.log("settlement P0-F dialog preview static contract: PASS");
