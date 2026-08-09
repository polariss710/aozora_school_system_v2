import fs from "node:fs";
import assert from "node:assert/strict";

const api = fs.readFileSync("js/api/settlement-api.js", "utf8");
const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");
const onlineState = fs.readFileSync("js/pages/settlement-online-state.js", "utf8");
const onlineApi = fs.readFileSync("js/api/student-settlement-online-api.js", "utf8");
const html = fs.readFileSync("settlement.html", "utf8");
const migration = fs.readFileSync(
  "sql/current/school_tuition_p0b2_adjustment_mode_authority_20260803.sql",
  "utf8"
);

assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)[\s\S]{0,180}\.(?:insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(page, /Math\.round/);
assert.doesNotMatch(page, /system_difference_cny\)\s*\+|system_difference_cny\s*\+/);
assert.doesNotMatch(api, /school_apply_student_monthly_settlement_adjustment/);
assert.match(api, /school_preview_student_settlement_adjustment_dialog/);
assert.match(page, /saveStudentSettlementDraftOnline\(saveInput\)/);
assert.match(onlineState, /expectedSystemDifferenceCny:\s*decimalString\(expected\.system_difference_cny/);
assert.match(onlineState, /expectedFinalCarryoverCny:\s*decimalString\(preview\.projected_final_carryover_cny/);
assert.match(onlineState, /manualAdjustmentAmountCny:\s*manualAmount/);
assert.match(onlineApi, /manual_adjustment_amount_cny:\s*optionalDecimal/);
assert.doesNotMatch(page, /Number\(amountText\)|parseFloat\(amountText\)/);
assert.doesNotMatch(onlineState, /Math\.round|parseFloat/);

const optionModes = [...html.matchAll(/<option value="([^"]+)">(?:按最终差额结转|抹平差额|手动调整)<\/option>/g)]
  .map((match) => match[1]);
assert.deepEqual(optionModes, [
  "carry_final_balance",
  "clear_balance",
  "manual_adjustment",
]);
assert.match(html, /数据库计算权威调整额与结转额/);

assert.match(migration, /school_tuition_p0b2_resolve_adjustment/);
assert.match(migration, /v_adjustment := -v_system_difference/);
assert.match(migration, /v_adjustment := round\(p_explicit_user_amount_cny, 2\)/);
assert.match(migration, /round\(v_system_difference \+ v_adjustment, 2\)/);
assert.equal((migration.match(/school_tuition_p0a_lock_settlement_mutation_scope/g) || []).length >= 4, true);
assert.match(migration, /create constraint trigger school_tuition_p0b2_settlement_resolution/i);
assert.match(migration, /school_student_settlement_adjustment_drafts_mode_chk/);
assert.match(migration, /school_student_settlement_adjustments_mode_chk/);
assert.match(migration, /SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE/);
assert.match(migration, /revoke all on function public\.school_apply_student_monthly_settlement_adjustment/);

console.log("settlement P0-B2 adjustment authority static test passed");
