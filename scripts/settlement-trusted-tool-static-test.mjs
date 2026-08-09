import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync("settlement.html", "utf8");
const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");
const api = fs.readFileSync("js/api/settlement-api.js", "utf8");
const tool = fs.readFileSync("scripts/manage-student-settlement.zsh", "utf8");
const sql = fs.readFileSync(
  "sql/current/school_tuition_p0f_local_settlement_management_20260803.sql",
  "utf8"
);

assert.match(html, /V2财务写操作请使用本机受信管理工具执行。/);
assert.match(html, /月结差额 DB 只读 Preview/);
assert.match(html, /settlement-app\.js\?v=settlement-writer-p0-closure-20260809-1/);
assert.match(page, /DB只读 Preview/);
assert.match(page, /dom\.adjustmentSubmitButton\.disabled = true/);
assert.doesNotMatch(page, /data-lock-settlement-id=/);
assert.doesNotMatch(page, /data-settlement-action-id=/);
for (const writer of [
  "lockStudentMonthlySettlement",
  "relockStudentMonthlySettlement",
  "setStudentSettlementSourceTreatmentDraft",
  "setStudentMonthlySettlementDraftAdjustment",
  "unlockStudentMonthlySettlement",
]) {
  assert.doesNotMatch(page, new RegExp(`\\b${writer}\\s*\\(`), `page still calls ${writer}`);
}
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.match(api, /school_preview_student_settlement_adjustment_dialog/);
for (const coreWriter of [
  "school_lock_student_monthly_settlement",
  "school_unlock_student_monthly_settlement",
  "school_relock_student_monthly_settlement",
  "school_set_student_monthly_settlement_draft_adjustment",
  "school_set_student_settlement_source_treatment_draft",
]) {
  assert.doesNotMatch(api, new RegExp(`\\b${coreWriter}\\b`), `browser API still exposes ${coreWriter}`);
}
assert.match(tool, /SAVE STUDENT SETTLEMENT DRAFT/);
assert.match(tool, /LOCK STUDENT SETTLEMENT/);
assert.match(tool, /set local request\.jwt\.claims='\{"role":"service_role"\}'/);
assert.match(sql, /school_save_student_settlement_draft_local/);
assert.match(sql, /school_lock_student_monthly_settlement_local/);
assert.match(sql, /coalesce\(auth\.role\(\), ''\) <> 'service_role'/);
assert.match(sql, /school_tuition_p0a_lock_settlement_mutation_scope/);
assert.doesNotMatch(sql, /grant execute[\s\S]{0,180}school_(?:save_student_settlement_draft_local|lock_student_monthly_settlement_local)[\s\S]{0,180}to anon/i);

console.log("settlement trusted local tool static contract: PASS");
