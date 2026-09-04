// 工行卡跨币种（JPY 消费 / CNY 结算）的前端与 Edge 契约静态测试。
//
// 这个测试锁的是 2026-09-04 那轮改动里**最容易被无声改回去**的几条：
//
//   1. CNY 卡不再因为币种被禁用（原来有两条币种规则，都删了）
//   2. 结算金额字段的显隐同时取决于「路线」和「所选卡是否跨币种」
//   3. 提交与 Edge 请求体成对携带 settlement_amount / settlement_currency
//   4. 全链路不出现汇率字段——原币与结算额都是已知事实，反推汇率没有业务用途
//   5. 两个 Edge 的 select 清单都取了 original_* 两列
//
// 第 4 条尤其值得钉住：即时账户路线是有 exchange_rate / rounding_mode 的，
// 后来者很容易「顺手」把固定路线也补上，那会凭空多出一个权威来源。

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const detailPage = readFileSync("js/pages/expense-detail-page.js", "utf8");
const detailApi = readFileSync("js/api/expense-detail-api.js", "utf8");
const html = readFileSync("expense-detail.html", "utf8");
const shared = readFileSync("supabase/functions/_shared/expense-cash-attempt-v2.js", "utf8");
const requestEdge = readFileSync(
  "supabase/functions/request-cash-expense-confirmation/index.ts",
  "utf8",
);
const syncEdge = readFileSync(
  "supabase/functions/sync-cash-request-result/index.ts",
  "utf8",
);

// --- 1. CNY 卡不再被币种规则禁用 -------------------------------------------
assert.match(detailPage, /function cashCardUnavailableReason\(card\)/);
assert.doesNotMatch(
  detailPage,
  /return `币种不符/,
  "币种不符那条禁用规则应已删除——跨币种现在是支持的",
);
assert.doesNotMatch(
  detailPage,
  /该币种的提交路径尚未启用/,
  "「尚未启用」那条禁用规则应已删除——prepare RPC 现在接得了金额",
);
assert.match(detailPage, /function isCrossCurrencyCard\(card, expenseCurrency\)/);

// --- 2. 结算金额字段：路线 + 卡币种双重条件 --------------------------------
assert.match(html, /data-cash-expense-field="settlementAmount"/);
assert.match(html, /data-cash-expense-route="fixed_credit_card"[^>]*>\s*<span id="cashExpenseSettlementAmountLabel"/s);
assert.match(html, /id="cashExpenseSettlementAmountInput"/);
assert.match(
  detailPage,
  /const crossCurrency = route === "fixed_credit_card"\s*&& isCrossCurrencyCard\(/,
  "显隐必须同时看路线与卡，只看路线会让西武卡也冒出一个必填字段",
);
// 隐藏时必须清空：留着一个看不见的旧值，提交时会被当成用户意图传出去
assert.match(detailPage, /if \(!crossCurrency && dom\.cashExpenseSettlementAmountInput\)/);

// --- 3. 成对携带 ------------------------------------------------------------
assert.match(detailPage, /settlementAmount,\s*\n\s*settlementCurrency,/);
assert.match(detailApi, /settlement_amount: payload\.settlementAmount \?\? null/);
assert.match(detailApi, /settlement_currency: payload\.settlementCurrency \?\? null/);
assert.match(requestEdge, /SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_PAIR_REQUIRED/);
assert.match(requestEdge, /p_payment_amount: settlementAmount/);
assert.match(requestEdge, /p_payment_currency: settlementCurrency/);

// 卡币种前置校验——首轮审核 P2 的修复，不能被删掉
assert.match(requestEdge, /SCHOOL_EXPENSE_CASH_FIXED_CARD_CURRENCY_MISMATCH/);
assert.match(
  requestEdge,
  /schedule\.settlement_currency\.toUpperCase\(\) !== effectiveSettlementCurrency/,
);

// --- 4. 固定路线全链路不得出现汇率 ------------------------------------------
const fixedBranchStart = requestEdge.indexOf('if (paymentRoute === "fixed_credit_card")');
const fixedBranchEnd = requestEdge.indexOf("const fixedSubmittedEvidence");
assert.ok(fixedBranchStart > 0 && fixedBranchEnd > fixedBranchStart, "找不到 fixed 分支范围");
const fixedBranch = requestEdge.slice(fixedBranchStart, fixedBranchEnd);
// 盯的是**真实用法**而不是散文——注释里提到「即时路线有汇率」是正当的，
// 光匹配裸词会把解释性注释也判成违规（本测试初稿就栽在这上面）。
assert.doesNotMatch(
  fixedBranch,
  /body\.exchange_rate|body\.rounding_mode|p_exchange_rate|p_payment_rounding_mode|exchangeRate\s*[,:)]/,
  "固定路线不接受汇率与取整：原币与结算额都是已知事实，反推汇率没有业务用途",
);

// --- 5. 两个 Edge 都取了原币两列 --------------------------------------------
for (const [name, source] of [["request", requestEdge], ["sync", syncEdge]]) {
  assert.match(source, /"original_amount"/, `${name} Edge 的 select 清单缺 original_amount`);
  assert.match(source, /"original_currency"/, `${name} Edge 的 select 清单缺 original_currency`);
}
// builder 从请求行取，不从 payload_snapshot 取（列有类型且被触发器冻结）
assert.match(shared, /p_original_amount: requiredAmount\(cashRequest\.original_amount/);
assert.match(shared, /p_original_currency: requiredText\(\s*cashRequest\.original_currency/s);
// approved 分支仍以 Cash 批准证据为准
assert.match(shared, /p_original_amount: requiredAmount\(approvalEvidence\.original_amount/);

console.log("cash-fixed-cross-currency-static-test: 全部通过");
