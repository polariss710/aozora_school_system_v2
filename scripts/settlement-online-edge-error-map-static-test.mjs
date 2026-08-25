import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

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
// 改为断言真正可表达的不变式：不再要求映射完整，而要求**未映射的 code 不丢失
// 身份**。这样「哪些 code 可达」这个问题不需要回答。

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
// T2  核心不变式：识别出 code 但未映射时，必须保留该 code，
//     不得折叠成 SETTLEMENT_EDGE_INTERNAL_ERROR。
//
//     静态断言的边界：这里只能证明兜底分支在源码中以 stableCode 构造返回值，
//     不能证明运行时一定走到。契约文件是 TypeScript，node 无法直接 import 求值；
//     真正的运行时验证须由具备 Deno 环境的一方执行。此处标明该限制，不假装
//     覆盖到了。
// ---------------------------------------------------------------------------
{
  const tail = contract.slice(contract.indexOf("export function mapSettlementOnlineError"));
  assert(tail, "未能定位 mapSettlementOnlineError");

  const preserve = /if\s*\(\s*stableCode\s*\)\s*\{[\s\S]{0,400}?new SettlementOnlinePublicError\(\s*\n?\s*stableCode\s*,/
    .exec(tail);
  assert(
    preserve,
    "未映射 code 的保留分支缺失：mapSettlementOnlineError 必须在 stableCode "
      + "非空时以该 code 构造返回值，而不是折叠成 SETTLEMENT_EDGE_INTERNAL_ERROR"
  );

  // INTERNAL_ERROR 只能出现在保留分支之后，作为「连 code 都没提取到」的兜底
  const preserveAt = tail.indexOf(preserve[0]);
  const internalAt = tail.indexOf("SETTLEMENT_EDGE_INTERNAL_ERROR", preserveAt);
  assert(
    internalAt > preserveAt,
    "SETTLEMENT_EDGE_INTERNAL_ERROR 必须排在 code 保留分支之后"
  );
}

// ---------------------------------------------------------------------------
// T3  SETTLEMENT_REPREVIEW_REQUIRED 不得进入 DB_ERROR_MAP。
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
// T4  前端回落到 error.message 时必须先判类型。
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
// T5  渲染必须走 textContent。透出服务端文本的前提是不存在 HTML 注入面。
// ---------------------------------------------------------------------------
assert.match(
  page,
  /function renderDialogBusinessError[\s\S]*?\.textContent\s*=/,
  "renderDialogBusinessError 必须以 textContent 渲染错误文案"
);

console.log("settlement online edge error identity: T1-T5 全部通过");
