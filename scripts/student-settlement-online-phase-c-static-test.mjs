import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync("settlement.html", "utf8");
const page = readFileSync("js/pages/settlement-page.js", "utf8");
const state = readFileSync("js/pages/settlement-online-state.js", "utf8");
const api = readFileSync("js/api/settlement-api.js", "utf8");
const hiddenApi = readFileSync("js/api/student-settlement-online-api.js", "utf8");
const app = readFileSync("js/settlement-app.js", "utf8");
const detailHtml = readFileSync("settlement-detail.html", "utf8");
const detailPage = readFileSync("js/pages/settlement-detail-page.js", "utf8");

assert.match(app, /authContext\.membership\.role/);
assert.match(page, /getStudentSettlementOnlineStatus/);
assert.match(page, /saveStudentSettlementDraftOnline/);
assert.match(page, /canUseOnlineDraftSave\(membershipRole, currentOnlineStatus\)/);
assert.match(page, /canUseOnlineDraftPreview\(membershipRole, currentOnlineStatus\)/);
assert.doesNotMatch(page, /lockStudentSettlementOnline|lock-student-settlement/);
assert.doesNotMatch(html, /data-lock-settlement|lockSettlementDialog|保存并锁定/);
assert.doesNotMatch(detailHtml + detailPage, /school_(?:unlock|relock|lock)_student_monthly_settlement|data-(?:unlock|relock|lock)-settlement/);
assert.doesNotMatch(page, /supabase\s*\.\s*(?:rpc|from)\s*\(/);
assert.doesNotMatch(page, /supabase[\s\S]{0,120}\.(?:insert|update|delete|upsert)\s*\(/);
assert.doesNotMatch(page + state + hiddenApi, /SCHOOL_SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY/);
assert.doesNotMatch(page, /actor_user_id|operator_authority|canonical_confirmation|business_entity_id\s*:/);
assert.doesNotMatch(state, /Math\.round|parseFloat|Number\(/);
assert.match(state, /decimalString\(expected\.system_difference_cny/);
assert.match(state, /decimalString\(preview\.projected_final_carryover_cny/);
assert.match(api, /getStudentSettlementOnlineStatus\(row\.student_id, row\.year_month\)/);
assert.match(api, /mapOnlineStatusOnlyRow\(selectedStudentId, yearMonth, status\)/);
assert.match(page, /fetchStudentSettlements\(filters\.month, filters\.studentId \|\| null\)/);
assert.match(api, /status\?\.save_blocker_code/);
assert.match(api, /status\?\.save_blocker_message/);
assert.match(api, /Math\.min\(concurrency, rows\.length\)/);
assert.match(api, /online_status_error/);
assert.match(api, /p_business_entity_id:\s*status\.business_entity_id/);
assert.doesNotMatch(api, /carryover_amount_cny:\s*status\?\.final_carryover_cny/);
assert.doesNotMatch(page, /businessEntityId/);
assert.match(state, /!status\?\.save_blocker_code/);
assert.match(state, /SETTLEMENT_MONTH_NOT_CLOSED/);
assert.match(state, /SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED/);
assert.doesNotMatch(state, /Date\s*\(|currentYearMonth|new Date/);
assert.match(state, /SETTLEMENT_SOURCE_FACTS_EMPTY/);
assert.doesNotMatch(state + page, /后继学费revision/);
assert.match(page, /该月份没有可用于月结的课时或收款来源，不能保存草稿。/);

for (const mode of [
  "separate_makeup_and_overage_v1",
  "net_lesson_variance_to_financial_credit_v1",
  "carry_final_balance",
  "clear_balance",
  "manual_adjustment",
]) assert.match(html, new RegExp(`value="${mode}"`));
assert.match(html, /id="settlementAdjustmentAmountField" class="field is-hidden"/);
assert.match(page, /adjustmentAmountField\.classList\.toggle\("is-hidden", !isManual\)/);
assert.match(page, /invalidateAdjustmentPreview\(\)/);
assert.match(page, /currentAdjustmentPreviewSignature/);
assert.match(page, /createSingleFlight\(\)/);
assert.match(page, /classifySaveRecovery/);
assert.match(page, /不明确，正在确认服务器状态/);
assert.doesNotMatch(page, /saveStudentSettlementDraftOnline[\s\S]{0,500}saveStudentSettlementDraftOnline/);

assert.doesNotMatch(page, /yearFilter\.addEventListener\("change",\s*applyQuery\)/);
assert.doesNotMatch(page, /monthFilter\.addEventListener\("change",\s*applyQuery\)/);
assert.doesNotMatch(page, /includeInactiveCheckbox\.addEventListener\("change",\s*applyQuery\)/);
assert.match(page, /filterForm\.addEventListener\("submit"/);
assert.match(page, /const requestSequence = \+\+queryRequestSequence/);
assert.match(page, /requestSequence !== queryRequestSequence/);
assert.match(page, /if \(updateUrl\) syncSettlementQuery\(appliedFilters\)/);
assert.match(page, /window\.addEventListener\("popstate"/);
assert.match(html, /settlement-loading-slot/);

assert.match(hiddenApi, /supabase\.functions\.invoke\(functionName, \{ body \}\)/);
assert.match(hiddenApi, /SETTLEMENT_EDGE_RESULT_UNCERTAIN/);
assert.doesNotMatch(page, /functions\.invoke/);
assert.doesNotMatch(page + html, /业务归属|个人名义/);

console.log("STUDENT_SETTLEMENT_ONLINE_PHASE_C_STATIC_PASS");
