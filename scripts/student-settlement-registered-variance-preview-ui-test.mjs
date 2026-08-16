import assert from "node:assert/strict";
import fs from "node:fs";
import { readRegisteredVarianceSummary } from "../js/pages/settlement-online-state.js";

const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");
const state = fs.readFileSync("js/pages/settlement-online-state.js", "utf8");
const html = fs.readFileSync("settlement.html", "utf8");
const app = fs.readFileSync("js/settlement-app.js", "utf8");
const css = fs.readFileSync("css/app.css", "utf8");
const config = fs.readFileSync("js/config.js", "utf8");

const baseReady = {
  source_treatment_mode: "separate_makeup_and_overage_v1",
  registered_variance_contract_version: "registered_lesson_variance_summary_v1",
  variance_summary_status: "ready",
  registered_pending_hours: "7.000000",
  registered_pending_amount_jpy: "63000.00",
  registered_overage_hours: "1.000000",
  registered_overage_amount_jpy: "9000.00",
  registered_overage_amount_cny: "373.50",
  registered_net_direction: "pending",
  registered_net_hours: "6.000000",
  registered_net_amount_jpy: "54000.00",
  registered_source_count: 5,
  unresolved_planned_count: 6,
  registered_overage_included_in_system_difference: true,
  variance_summary_manifest_sha256: "0".repeat(64),
};

const mixed = readRegisteredVarianceSummary(baseReady);
assert.deepEqual(mixed, {
  status: "ready",
  pendingHours: "7.000000",
  pendingAmountJpy: "63000.00",
  overageHours: "1.000000",
  overageAmountJpy: "9000.00",
  overageAmountCny: "373.50",
  netDirection: "pending",
  netHours: "6.000000",
  netAmountJpy: "54000.00",
  unresolvedPlannedCount: 6,
  overageIncludedInSystemDifference: true,
  sourceCount: 5,
  manifestSha256: "0".repeat(64),
});

const pendingOnly = readRegisteredVarianceSummary({
  ...baseReady,
  registered_pending_hours: "2",
  registered_pending_amount_jpy: "18000",
  registered_overage_hours: "0",
  registered_overage_amount_jpy: "0",
  registered_overage_amount_cny: "0",
  registered_net_hours: "2",
  registered_net_amount_jpy: "18000",
  registered_source_count: 1,
  unresolved_planned_count: 0,
  registered_overage_included_in_system_difference: false,
});
assert.equal(pendingOnly.status, "ready");
assert.equal(pendingOnly.netDirection, "pending");

const overageOnly = readRegisteredVarianceSummary({
  ...baseReady,
  registered_pending_hours: "0",
  registered_pending_amount_jpy: "0",
  registered_overage_hours: "0.5",
  registered_overage_amount_jpy: "4500",
  registered_overage_amount_cny: "186.75",
  registered_net_direction: "overage",
  registered_net_hours: "0.5",
  registered_net_amount_jpy: "4500",
  registered_source_count: 1,
  unresolved_planned_count: 3,
});
assert.equal(overageOnly.status, "ready");
assert.equal(overageOnly.unresolvedPlannedCount, 3);

assert.deepEqual(readRegisteredVarianceSummary({
  source_treatment_mode: "separate_makeup_and_overage_v1",
  registered_variance_contract_version: "registered_lesson_variance_summary_v1",
  variance_summary_status: "empty",
  registered_source_count: 0,
}), { status: "empty" });
assert.deepEqual(readRegisteredVarianceSummary({
  ...baseReady,
  registered_overage_amount_cny: null,
}), { status: "unavailable" });
assert.deepEqual(readRegisteredVarianceSummary({
  ...baseReady,
  variance_summary_status: "unavailable",
}), { status: "unavailable" });
assert.deepEqual(readRegisteredVarianceSummary({
  ...baseReady,
  source_treatment_mode: "net_lesson_variance_to_financial_credit_v1",
}), { status: "hidden" });

for (const text of [
  "当前已登记课时差额",
  "已登记待补",
  "已登记超额",
  "当前已登记净差额",
  "已计入当前 system difference",
  "当前没有已登记的待补或超额事实。",
  "暂时无法读取已登记课时差额，请重新预览。",
  "当前为“待补与超额分别处理”模式，上述差额仅展示已登记事实，不在本模式中执行财务净额化。",
  "当前不能生成可保存的 net Preview",
]) {
  assert.ok(page.includes(text), `missing UI text: ${text}`);
}
assert.doesNotMatch(page, /当前模式没有可财务净额化的 source/);
assert.doesNotMatch(page, /registered_(?:pending|overage|net)_[a-z_]+\s*[+\-*/]/);
assert.match(state, /numericFields\.some/);
assert.match(state, /return \{ status: "unavailable" \}/);

const renderBody = page.slice(
  page.indexOf("function renderRegisteredVarianceSummary"),
  page.indexOf("function applySourceTreatmentMode"),
);
assert.doesNotMatch(renderBody, /fetchStudent|saveStudent|lockStudent|\.rpc\s*\(/);
assert.doesNotMatch(page, /supabase\s*\.|\.rpc\s*\(/);

assert.match(css, /\.settlement-registered-variance-card\s*\{[\s\S]*?min-width:\s*0/);
assert.match(css, /overflow-wrap:\s*anywhere/);
assert.match(config, /v10\.5\.47/);
for (const content of [html, app]) {
  assert.match(content, /student-settlement-registered-variance-preview-20260816-1/);
}
assert.match(app, /student-settlement-registered-variance-preview-20260816-1/);

console.log("student settlement registered variance Preview UI contract: PASS");
