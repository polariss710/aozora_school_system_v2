import assert from "node:assert/strict";
import fs from "node:fs";
import {
  extractStableBusinessErrorCode,
  formatSettlementBusinessError,
  settlementMonthDateRange,
  SETTLEMENT_BUSINESS_ERROR_CODES,
} from "../js/api/business-error.js";

const html = fs.readFileSync("settlement.html", "utf8");
const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");

assert.deepEqual(settlementMonthDateRange("2026-07"), {
  min: "2026-07-01",
  max: "2026-07-31",
});
assert.deepEqual(settlementMonthDateRange("2028-02"), {
  min: "2028-02-01",
  max: "2028-02-29",
});
assert.equal(settlementMonthDateRange("2026-13"), null);

const mismatch = formatSettlementBusinessError(
  { code: "P0001", message: "SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH" },
  { yearMonth: "2026-07" }
);
assert.equal(
  mismatch.message,
  "汇率生效日必须位于结算月份2026-07内，请选择2026-07-01至2026-07-31之间的日期。"
);
assert.equal(mismatch.code, "SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH");
assert.equal(
  extractStableBusinessErrorCode({ message: "SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED: detail" }),
  "SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED"
);

const unknown = formatSettlementBusinessError({
  code: "P0001",
  message: "SETTLEMENT_NEW_UNKNOWN_CODE: internal English details",
});
assert.equal(unknown.message, "操作未完成，请检查输入或刷新数据后重试。");
assert.equal(unknown.code, "SETTLEMENT_NEW_UNKNOWN_CODE");
assert.equal(formatSettlementBusinessError({ code: "55P03", message: "lock not available" }).code, "55P03");
const permissionDenied = formatSettlementBusinessError({ code: "42501", message: "permission denied" });
assert.equal(permissionDenied.message, "当前页面没有执行该财务写操作的受信权限，请使用本机管理工具。");
assert.equal(permissionDenied.code, "42501");

for (const code of [
  "SETTLEMENT_EXPLICIT_EXCHANGE_RATE_REQUIRED",
  "SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH",
  "SETTLEMENT_SOURCE_TREATMENT_MODE_INVALID",
  "SETTLEMENT_LESSON_SOURCE_UNRESOLVED",
  "SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED",
  "TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE",
  "TUITION_CONSUMED_SETTLEMENT_IMMUTABLE",
  "SETTLEMENT_ADJUSTMENT_MODE_INVALID",
  "SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED",
  "SETTLEMENT_ADJUSTMENT_LOCKED_READ_ONLY",
  "SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT",
]) {
  assert.ok(SETTLEMENT_BUSINESS_ERROR_CODES.includes(code), `missing settlement mapping ${code}`);
}

assert.match(html, /id="settlementExchangeRateEffectiveDateInput" type="date"/);
assert.match(html, /请选择结算月份内的汇率生效日。该日期用于冻结本次结算采用的汇率依据。/);
assert.match(page, /settlementExchangeRateEffectiveDateInput\.min = range\?\.min/);
assert.match(page, /settlementExchangeRateEffectiveDateInput\.max = range\?\.max/);
assert.match(page, /SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH/);
assert.match(page, /renderAdjustmentPendingPreview\(null, displayError\.message, "失败"\)/);
assert.match(page, /showAdjustmentError\(displayError\)/);
assert.match(page, /dom\.adjustmentSubmitButton\.disabled = true/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.equal(fs.existsSync("js/legacy-core.js"), false);

console.log("settlement business error localization static contract: PASS");
