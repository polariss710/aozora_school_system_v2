import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge = readFileSync("supabase/functions/request-cash-income-confirmation/index.ts", "utf8");
const incomeApi = readFileSync("js/api/income-api.js", "utf8");
const detailApi = readFileSync("js/api/income-detail-api.js", "utf8");
const incomePage = readFileSync("js/pages/income-page.js", "utf8");
const detailPage = readFileSync("js/pages/income-detail-page.js", "utf8");

assert.match(edge, /gateData\?\.state !== "enabled"/);
assert.doesNotMatch(edge, /R0 不提供学费 Cash enabled 路径/);
assert.match(edge, /TUITION_CASH_CLIENT_AMOUNT_FORBIDDEN/);
assert.match(edge, /body\.actual_received_amount/);
assert.match(edge, /body\.actual_received_currency/);
assert.match(edge, /body\.exchange_rate/);
assert.match(edge, /body\.rounding_mode/);
assert.match(edge, /p_payment_amount: actualReceivedAmount/);
assert.match(edge, /p_payment_currency: isTuitionBill \? null/);
assert.match(edge, /p_exchange_rate: isTuitionBill\s*\? null/);
assert.match(edge, /p_payment_rounding_mode: isTuitionBill\s*\? null/);
assert.match(edge, /const cashAmount = Number\(schoolRequest\.payment_amount\)/);
assert.match(edge, /p_amount: cashAmount/);
assert.match(edge, /p_currency: schoolRequest\.payment_currency/);

for (const api of [incomeApi, detailApi]) {
  const tuitionBody = api.match(/const body = payload\.isTuition[\s\S]*?\n    : \{/u)?.[0] ?? "";
  assert.match(tuitionBody, /income_record_id/);
  assert.match(tuitionBody, /cash_account_id/);
  assert.doesNotMatch(tuitionBody, /actual_received_amount/);
  assert.doesNotMatch(tuitionBody, /actual_received_currency/);
  assert.doesNotMatch(tuitionBody, /exchange_rate/);
  assert.doesNotMatch(tuitionBody, /rounding_mode/);
  assert.match(api, /school_get_cash_income_submission_preflight/);
}

assert.match(incomePage, /cashSubmissionPreflight\?\.eligible === true/);
assert.match(detailPage, /cashSubmissionPreflight\?\.eligible === true/);
assert.match(incomePage, /isTuition: true/);
assert.match(detailPage, /isTuition: true/);
assert.doesNotMatch(detailApi, /school_retry_personal_cash_income_linkage_event/);
assert.doesNotMatch(detailPage, /retryPersonalCashIncomeLinkageEvent/);

for (const page of [incomePage, detailPage]) {
  assert.doesNotMatch(page, /\bsupabase\s*\./);
  assert.doesNotMatch(page, /\.rpc\s*\(/);
}

console.log("TUITION_CASH_SUBMIT_HARDENING_STATIC_TEST_PASS");
