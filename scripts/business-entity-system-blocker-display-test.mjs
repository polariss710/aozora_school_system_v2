import assert from "node:assert/strict";
import fs from "node:fs";
import { formatTeacherWageBlockerDisplayReason } from "../js/utils/system-blocker-display.js";

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const prohibitedDisplay = /业务归属|个人名义|business_entity_id/i;

const fixtures = [
  {
    blockerLevel: "wage_snapshot",
    counts: { activeWageLockCount: 3, wageDetailCount: 17 },
    hasBlocker: true,
    expected: ["老师工资已生成或锁定", "3个工资快照", "17条工资明细", "工资快照保护"],
  },
  {
    blockerLevel: "payment_requested",
    counts: { activeWageLockCount: 2, wageDetailCount: 8, paymentRequestCount: 1 },
    hasBlocker: true,
    expected: ["工资支付请求已生成", "1个支付请求", "工资链路保护"],
  },
  {
    blockerLevel: "payment_completed",
    counts: { activeWageLockCount: 1, wageDetailCount: 4, expenseCount: 1, accountTransactionCount: 1 },
    hasBlocker: true,
    expected: ["老师工资已支付", "1条支出", "1条账户流水", "已完成工资链路保护"],
  },
];

for (const fixture of fixtures) {
  const display = formatTeacherWageBlockerDisplayReason(fixture);
  assert.doesNotMatch(display, prohibitedDisplay);
  for (const fragment of fixture.expected) assert.match(display, new RegExp(fragment));
}

assert.equal(formatTeacherWageBlockerDisplayReason(), "");
assert.match(formatTeacherWageBlockerDisplayReason({ hasBlocker: true }), /工资链路保护/);

const utility = read("js/utils/system-blocker-display.js");
assert.doesNotMatch(utility, prohibitedDisplay);

for (const pagePath of ["js/pages/settlement-page.js", "js/pages/settlement-detail-page.js"]) {
  const page = read(pagePath);
  assert.match(page, /formatTeacherWageBlockerDisplayReason/);
  assert.doesNotMatch(page, /return safeText\((?:row|settlement)\?\.teacher_wage_blocker_reason\)/);
}

for (const apiPath of ["js/api/settlement-api.js", "js/api/settlement-detail-api.js"]) {
  const api = read(apiPath);
  assert.match(api, /teacher_wage_blocker_reason:\s*blocker\.blocker_reason \|\| ""/);
}

console.log("BE_SYSTEM_BLOCKER_DISPLAY_TEST_PASS");
