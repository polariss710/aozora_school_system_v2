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

assert.match(html, /管理员可在线保存已结束月份的未完成月结草稿；当前及未来月份仅可读取DB权威预览，正式锁定暂未开放。/);
assert.match(html, /编辑月结草稿/);
assert.match(html, /settlement-app\.js\?v=filter-contract-b3-20260822-1/);
assert.match(page, /saveStudentSettlementDraftOnline\(saveInput\)/);
assert.match(page, /dom\.adjustmentSubmitButton\.disabled = !canSave/);
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
assert.doesNotMatch(page, /lockStudentSettlementOnline|lock-student-settlement/);
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
