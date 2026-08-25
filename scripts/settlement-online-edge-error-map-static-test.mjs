import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  mapSettlementOnlineError,
} from "../supabase/functions/_shared/student-settlement-online-contract.ts";

// 学生月度结算在线路径的错误身份保全。
//
// 本测试 2026-08-25 重写。初版的前提是错的，记录在此以免重蹈：
//
//   初版试图枚举 DB 会抛出的全部 code，断言每一个都在 DB_ERROR_MAP 里。
//   这条路走不通——「某个 code 能否传到 Edge」是调用图属性，不是文本属性。
//   DB 普遍先把 code 赋给变量、再 raise ... message = v_code，静态扫描既判
//   不出可达性；初版的正则又只匹配 SETTLEMENT_*，必然漏掉 S1_C_* 一类前缀。
//   结果是测试报「未处理 0 个」而实际仍有未映射 code——比没有测试更糟，
//   因为它给出虚假的完整感。由 Codex 审出。
//
// 改为断言两层不变式：
// 1. 生产只读调用图已确认的 owner writer/trigger 可传播 code 必须逐项映射；
// 2. 未来新增而尚未映射的稳定 code 仍必须保留身份，不退化成 INTERNAL_ERROR。

const CONTRACT_TS = "supabase/functions/_shared/student-settlement-online-contract.ts";
const PAGE_JS = "js/pages/settlement-page.js";
const STATE_JS = "js/pages/settlement-online-state.js";

const contract = readFileSync(CONTRACT_TS, "utf8");
const page = readFileSync(PAGE_JS, "utf8");
const state = readFileSync(STATE_JS, "utf8");

// ---------------------------------------------------------------------------
// T1  code 提取正则必须能覆盖两种前缀形态。
//     SETTLEMENT_LESSON_WEEK_NOT_CLOSED 与 S1_C_LOCK_OVERAGE_AGGREGATE_DRIFT
//     都是生产实际存在的 code；提取不到就等于身份从源头就丢了。
// ---------------------------------------------------------------------------
{
  const m = /const STABLE_CODE_PATTERN\s*=\s*(\/.+\/);/.exec(contract);
  assert(m, "未能定位 STABLE_CODE_PATTERN");
  const pattern = new RegExp(m[1].slice(1, m[1].lastIndexOf("/")));
  for (const sample of [
    "SETTLEMENT_LESSON_WEEK_NOT_CLOSED",
    "S1_C_LOCK_OVERAGE_AGGREGATE_DRIFT",
    "SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH",
  ]) {
    const hit = sample.match(pattern);
    assert.equal(
      hit?.[0],
      sample,
      `STABLE_CODE_PATTERN 无法完整提取 ${sample}，未映射时其身份会丢失`
    );
  }
  // 反向：不得把普通英文句子误当成 code
  assert.equal(
    "decimal must be a decimal string".match(pattern),
    null,
    "STABLE_CODE_PATTERN 过宽，会把自由文本当成 code 透出"
  );
}

// ---------------------------------------------------------------------------
// T2  生产 owner writer 调用图中的稳定 code 必须真正进入 curated map。
//
//     2026-08-25 以生产 pg_get_functiondef + trigger catalog 只读递归复核：seed
//     是 school_lock_student_monthly_settlement 及其写表 trigger，递归跟踪直接
//     public.school_* 调用。这里只登记该调用图实际出现、且能作为稳定 token 传播的
//     code；每项都必须返回非 5xx、明确 action 与非通用公开文案。
// ---------------------------------------------------------------------------
{
  const ownerWriterCodes = [
    ["S1_C_LOCK_OVERAGE_AGGREGATE_DRIFT", "repreview"],
    ["SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH", "repreview"],
    ["SETTLEMENT_ADJUSTMENT_SCOPE_INVALID", "repreview"],
    ["SETTLEMENT_ADJUSTMENT_MODE_INVALID", "repreview"],
    ["SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE", "refresh_status"],
    ["SETTLEMENT_LESSON_VARIANCE_CLAIM_COUNT_MISMATCH", "repreview"],
    ["SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED", "refresh_status"],
    ["SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT", "repreview"],
    ["SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK", "refresh_status"],
    ["SETTLEMENT_MONTH_INVALID", "repreview"],
    ["SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED", "stop"],
    ["SETTLEMENT_LESSON_WEEK_NOT_CLOSED", "stop"],
    ["SETTLEMENT_MONTH_NOT_CLOSED", "stop"],
    ["SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH", "repreview"],
    ["SETTLEMENT_EXPLICIT_EXCHANGE_RATE_REQUIRED", "repreview"],
    ["SETTLEMENT_SOURCE_TREATMENT_MODE_INVALID", "repreview"],
    ["SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID", "repreview"],
    ["SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE", "repreview"],
    ["SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_INVALID", "repreview"],
    ["SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED", "repreview"],
    ["SETTLEMENT_LESSON_SOURCE_UNRESOLVED", "repreview"],
    ["SETTLEMENT_LESSON_SOURCE_VALUE_INVALID", "repreview"],
  ];

  for (const [code, action] of ownerWriterCodes) {
    const mapped = mapSettlementOnlineError({
      code: "P0001",
      message: code,
      details: null,
      hint: null,
    });
    assert.equal(mapped.code, code, `${code} 的错误身份被改写`);
    assert.ok(mapped.status < 500, `${code} 未进入 curated map，仍返回 ${mapped.status}`);
    assert.equal(mapped.action, action, `${code} 的 action 不符合恢复路径`);
    assert.doesNotMatch(
      mapped.message,
      /^操作未完成/,
      `${code} 仍使用通用兜底文案`
    );
  }
}

// ---------------------------------------------------------------------------
// T3  未知稳定 code 的运行时兜底必须保留身份；只有无法提取稳定 code 时才用
//     SETTLEMENT_EDGE_INTERNAL_ERROR。这一组直接执行 TypeScript，不再靠源码正则。
// ---------------------------------------------------------------------------
{
  const unknown = mapSettlementOnlineError({
    code: "P0001",
    message: "FUTURE_SETTLEMENT_OWNER_GUARD",
  });
  assert.equal(unknown.code, "FUTURE_SETTLEMENT_OWNER_GUARD");
  assert.equal(unknown.status, 500);
  assert.equal(unknown.action, "refresh_status");

  const internal = mapSettlementOnlineError({
    code: "P0001",
    message: "ordinary database error text",
  });
  assert.equal(internal.code, "SETTLEMENT_EDGE_INTERNAL_ERROR");
}

// ---------------------------------------------------------------------------
// T4  SETTLEMENT_REPREVIEW_REQUIRED 不得进入 DB_ERROR_MAP。
//     它只在 status JSON 构造时赋值给 v_lock_blocker_code，从不被 raise，
//     因此永远到不了该映射。放进去是死代码，且会让人以为它经 Edge 返回。
//     文案归属在前端 blockerLabel。
// ---------------------------------------------------------------------------
{
  const mapBlock = /const DB_ERROR_MAP[^=]*=\s*\{([\s\S]*?)\n\};/.exec(contract);
  assert(mapBlock, "未能定位 DB_ERROR_MAP");
  assert.doesNotMatch(
    mapBlock[1],
    /^\s{2}SETTLEMENT_REPREVIEW_REQUIRED:/m,
    "SETTLEMENT_REPREVIEW_REQUIRED 不应在 DB_ERROR_MAP 中——它从不被 raise，"
      + "文案应在前端 blockerLabel 给"
  );
  assert.match(
    state,
    /SETTLEMENT_REPREVIEW_REQUIRED:\s*"/,
    "前端 blockerLabel 缺少 SETTLEMENT_REPREVIEW_REQUIRED 的文案"
  );
}

// ---------------------------------------------------------------------------
// T5  前端回落到 error.message 时必须先判类型。
//
//     safeOnlineErrorDisplay 也接收非 Edge 异常——buildOnlineDraftSaveInput
//     抛出的普通 Error，message 是 "decimal must be a decimal string" 这类
//     内部英文文本。无条件回落会把它显示给用户。
//     2026-08-25 初版即如此，属真实回归，由 Codex 审出。
// ---------------------------------------------------------------------------
{
  const fn = /function safeOnlineErrorDisplay[\s\S]*?\n\}/.exec(page);
  assert(fn, "未能定位 safeOnlineErrorDisplay");
  const body = fn[0];

  if (/error\?\.message|error\.message/.test(body)) {
    assert.match(
      body,
      /error instanceof StudentSettlementOnlineError\s*\?/,
      "safeOnlineErrorDisplay 回落到 error.message 时必须先判 "
        + "instanceof StudentSettlementOnlineError，否则会把内部异常文本显示给用户"
    );
  }
  assert.match(
    page,
    /StudentSettlementOnlineError/,
    "settlement-page.js 未引入 StudentSettlementOnlineError，类型判断无从谈起"
  );
}

// ---------------------------------------------------------------------------
// T6  渲染必须走 textContent。透出服务端文本的前提是不存在 HTML 注入面。
// ---------------------------------------------------------------------------
assert.match(
  page,
  /function renderDialogBusinessError[\s\S]*?\.textContent\s*=/,
  "renderDialogBusinessError 必须以 textContent 渲染错误文案"
);

console.log("settlement online edge error mapping: T1-T6 全部通过");
