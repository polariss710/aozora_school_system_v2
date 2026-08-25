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

// Phase D 起横幅需反映锁定已开放。断言分解为若干必须同时成立的语义要点，
// 而不是钉死整句——整句钉死会让每次文案微调都变成假红。
assert.match(html, /管理员可在线保存已结束月份的未完成月结草稿/);
assert.match(html, /草稿保存后正式锁定/);
assert.match(html, /自然周未结束的月份仅可读取DB权威预览/);
assert.match(html, /锁定不可撤销/);
assert.match(html, /编辑月结草稿/);
// Historical cache-key literals are intentionally not asserted; the settlement app reference remains covered (handoff section 8.6).
assert.match(html, /settlement-app\.js/);
assert.match(page, /saveStudentSettlementDraftOnline\(saveInput\)/);
assert.match(page, /dom\.adjustmentSubmitButton\.disabled = !canSave/);
// Phase D 起页面有正式锁定入口。原断言钉的是 data-lock-settlement-id，
// 与实际命名 data-settlement-lock-id 不符，已是死断言。改为正向断言入口存在，
// 且其可用性由完整的 canUseOnlineDraftLock 判定驱动，而不只看 can_lock。
assert.match(page, /data-settlement-lock-id=/);
assert.match(page, /canUseOnlineDraftLock\(membershipRole, row\.online_status\)/);
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
// Phase D：锁定必须经 Edge，且只允许这一条受控路径。
assert.match(page, /lockStudentSettlementOnline\(lockInput\)/);
// 提交失败一律经 classifyLockFailure 分流，不得就地判断能否重试
assert.match(page, /classifyLockFailure\(/);
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
