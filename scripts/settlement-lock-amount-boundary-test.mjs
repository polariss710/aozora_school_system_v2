import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// 锁定金额边界的页面层：用户手打的确认金额只作闸门，不参与 payload 构造。
//
// 定位（2026-08-27 确认）：安全边界在 DB——lock RPC 用库内草稿行重算 preview
// 并比对全部 expected_*，写入前不一致即拒绝。前端拦不住蓄意伪造（supabase 客户端
// 公开导出）。本文件测的是**防误用**：正常路径下 payload 里的金额确实取自权威
// 快照，而非 DOM。全绿不等于「伪造不可能」。
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md 第 6.1 节
// （该节定位已在 2026-08-27 追记中修正）。
//
// 本文件覆盖页面层这一段：权威快照 → buildOnlineDraftLockInput 的 camelCase
// 产出。API 层的 snake_case 最终提交体由 settlement-lock-edge-body-test 覆盖，
// 两者是不同的键名体系，彼此证明不了对方。
//
// 演进记录（每一版都是被证伪后才改的）：
//   初版只有一个 sentinel 场景，且是空转的——sentinel 取 999999.123，与 DB 的
//   40000.00 不匹配，闸门理应拦下、API 根本不会被调用，测试不接触被测代码就
//   通过；DECIMAL_RE 允许任意位小数，999999.123 本就是合法金额，称其为
//   「非法形态」也是错的。拆成五个各自能失败的场景后，fixture 仍由测试自己经
//   公开的 freezeAuthoritativeSnapshot 登记——于是「快照来自 DB」这件事从未被
//   触及，测试用的正是攻击路径用的同一个入口。现在登记入口已收进 API 层模块
//   作用域，权威快照只能经真实读取取得。

import {
  AUTHORITATIVE_CARRY,
  CORRELATION_ID,
  SHA_A,
  SHA_B,
  STUDENT_ID,
  YEAR_MONTH,
  authoritativeFacts,
  containsDeep,
  previewRow,
} from "./lib/settlement-lock-authority.mjs";

const { buildOnlineDraftLockInput, lockConfirmationAccepted } =
  await import("../js/pages/settlement-online-state.js");

const row = { student_id: STUDENT_ID, year_month: YEAR_MONTH };

// 权威事实经真实 API 层取得，在那一层被深拷贝、递归冻结并登记
const { status, preview } = await authoritativeFacts();

function buildFrom(previewResult, note = "") {
  return buildOnlineDraftLockInput({
    row, status, previewResult, membershipRole: "admin",
    note, clientCorrelationId: CORRELATION_ID,
  });
}

// ---------------------------------------------------------------------------
// 场景 1  不匹配的输入必须被闸门拦下
//
//         这是初版唯一的场景。它证明的是「拦得住」，不是「不泄漏」——
//         因为根本走不到构造 payload 那一步。保留它，但不能只有它。
// ---------------------------------------------------------------------------
{
  assert.equal(
    lockConfirmationAccepted("999999.123", AUTHORITATIVE_CARRY), false,
    "不同金额被判为匹配",
  );
  for (const bad of ["", "  ", "abc", "4000", "400000.00", "-40000.00"]) {
    assert.equal(
      lockConfirmationAccepted(bad, AUTHORITATIVE_CARRY), false,
      `输入 ${JSON.stringify(bad)} 不应放行`,
    );
  }
  // 权威值缺失时一律不放行
  assert.equal(lockConfirmationAccepted(AUTHORITATIVE_CARRY, null), false);
  assert.equal(lockConfirmationAccepted(AUTHORITATIVE_CARRY, undefined), false);
}

// ---------------------------------------------------------------------------
// 场景 2  等值但字符串不同 —— 闸门放行，但值绝不能泄漏
//
//         这是「闸门过了、值仍可能进 payload」的窗口，也是初版完全没有覆盖到
//         的场景。canonicalDecimal 判等使 40000.000 与 40000.00 视为同值，
//         所以提交会被允许；此时必须证明提交的是 DB 原值。
//
//         说明：这不是字面意义上的唯一窗口，其他尾零形式等价；若 DOM 与 DB
//         字符串完全相同，误用 DOM 值在结果上无法辨识。它是最合适的可辨识场景。
// ---------------------------------------------------------------------------
{
  const TYPED = "40000.000";
  assert.notEqual(TYPED, AUTHORITATIVE_CARRY, "两者字符串必须不同，否则本场景无意义");
  assert.equal(
    lockConfirmationAccepted(TYPED, AUTHORITATIVE_CARRY), true,
    "等值不同串应被闸门放行，否则用户无法完成合法操作",
  );

  const payload = buildFrom(preview);

  assert.equal(
    payload.expectedFinalCarryoverCny, AUTHORITATIVE_CARRY,
    "提交的结转金额必须是 DB 原值",
  );
  assert.equal(
    containsDeep(payload, TYPED), false,
    `payload 中出现了用户输入的字符串 ${TYPED}`,
  );
}

// ---------------------------------------------------------------------------
// 场景 3  只有 API 层读来的快照能进 builder
//
//         判据的三次演进都记在这里，每一条都是一个曾经真实成立的绕法：
//           1. 「纯函数签名让错误代码写不出来」——JS 参数表证明不了对象来源，
//              调用方可先把 DOM 值写进可变的 previewResult 再传入。
//           2. Object.isFrozen——构造污染对象再手动 freeze 即可通过，
//              实测把 999999.99 送进过 payload。
//           3. 页面层导出的登记函数——先污染再登记即可，入口是公开的。
//         现在登记入口已收进 API 层模块作用域，下列自造形态都必须被拒绝。
//
//         本场景只覆盖「进 builder」这一段。2026-08-26 审查发现 builder 的产出
//         未冻结、writer 公开接受任意 payload，绕开 builder 即可送入脏值——
//         那条路本文件测不到。
// ---------------------------------------------------------------------------
{
  const TAMPERED = "999999.99";

  // 真权威快照是递归冻结的：严格模式抛错、非严格模式静默失败，两种都改不到值
  try { preview.preview.projected_final_carryover_cny = TAMPERED; } catch { /* 预期 */ }
  try { preview.preview_expected_facts.system_difference_cny = TAMPERED; } catch { /* 预期 */ }

  const payload = buildFrom(preview);
  assert.equal(payload.expectedFinalCarryoverCny, AUTHORITATIVE_CARRY, "结转金额被篡改成功");
  assert.equal(payload.expectedSystemDifferenceCny, "0", "系统差额被篡改成功");
  assert.equal(containsDeep(payload, TAMPERED), false, "被篡改的值进入了 payload");

  // 未冻结的自造对象
  const unfrozen = previewRow(TAMPERED);

  // 手动冻结的污染对象。只查 Object.isFrozen 时这一条会通过。
  const manuallyFrozen = Object.freeze({
    preview_manifest_sha256: SHA_A,
    preview: Object.freeze({
      lesson_variance_source_count: 3,
      unused_planned_credit_jpy: "0",
      overage_charge_jpy: "0",
      net_lesson_variance_jpy: "0",
      net_lesson_variance_cny: "0",
      projected_final_carryover_cny: TAMPERED,
    }),
    preview_expected_facts: Object.freeze({
      lesson_variance_manifest_sha256: SHA_B,
      system_difference_cny: "0",
    }),
  });
  assert.ok(Object.isFrozen(manuallyFrozen), "该对象确实处于冻结状态");

  // 内容与权威快照完全一致、只是丢了登记的副本
  const clonedCopy = structuredClone(preview);

  for (const [label, candidate] of [
    ["未冻结的自造对象", unfrozen],
    ["手动 Object.freeze 的污染对象", manuallyFrozen],
    ["权威快照的 structuredClone 副本", clonedCopy],
  ]) {
    assert.throws(
      () => buildFrom(candidate),
      /authoritative snapshot/,
      `${label} 被 builder 接受了`,
    );
  }

  // status 侧同样必须是登记过的权威快照——展开复制即失去登记
  assert.throws(
    () => buildOnlineDraftLockInput({
      row, status: { ...status }, previewResult: preview,
      membershipRole: "admin", note: "", clientCorrelationId: CORRELATION_ID,
    }),
    /authoritative snapshot/,
    "builder 接受了未登记的 status",
  );
}

// ---------------------------------------------------------------------------
// 场景 4  payload 的键集必须与契约完全一致，不多不少
// ---------------------------------------------------------------------------
{
  const payload = buildFrom(preview, "备注");
  const expectedKeys = [
    "studentId", "settlementMonth",
    "expectedSourceTreatmentDraftId", "expectedSourceTreatmentDraftUpdatedAt",
    "expectedAdjustmentDraftId", "expectedAdjustmentDraftUpdatedAt",
    "expectedPreviewManifestSha256", "expectedLessonVarianceManifestSha256",
    "expectedSourceCount",
    "expectedUnusedPlannedCreditJpy", "expectedOverageChargeJpy",
    "expectedNetLessonVarianceJpy", "expectedNetLessonVarianceCny",
    "expectedSystemDifferenceCny", "expectedFinalCarryoverCny",
    "note", "confirmLock", "clientCorrelationId",
  ].sort();
  assert.deepEqual(Object.keys(payload).sort(), expectedKeys, "payload 键集与契约不符");

  for (const forbidden of [
    "canonical_confirmation", "canonicalConfirmation",
    "confirmationAmount", "confirmationInput", "typedCarryover",
  ]) {
    assert.ok(!(forbidden in payload), `payload 不应包含 ${forbidden}`);
  }
}

// ---------------------------------------------------------------------------
// 场景 5  DOM 层必须使用该纯函数，而不是自己再写一份比对
//
//         闸门逻辑抽成纯函数是为了能脱离浏览器测试；若 handler 绕开它另写
//         一套，上面四个场景就都白测了。
//
//         这是静态断言，只能证明页面某处调用了该纯函数，证明不了 handler 确实
//         把它的结果当作提交前提——那需要端到端驱动 DOM，见
//         settlement-lock-edge-body-test 末尾的记录。
// ---------------------------------------------------------------------------
{
  const page = readFileSync("js/pages/settlement-page.js", "utf8");
  assert.match(
    page, /lockConfirmationAccepted\(/,
    "settlement-page.js 未调用 lockConfirmationAccepted，闸门可能被另写了一份",
  );
  const fn = /function lockConfirmationMatches\(\)[\s\S]*?\n\}/.exec(page);
  assert(fn, "未找到 lockConfirmationMatches");
  assert.doesNotMatch(
    fn[0], /canonicalDecimal\(/,
    "lockConfirmationMatches 内部自行比对了金额，应交给 lockConfirmationAccepted",
  );
  // 提交路径不得把确认输入写进任何 expected 字段
  const submit = /async function handleLockSubmit\(\)[\s\S]*?\n\}/.exec(page);
  assert(submit, "未找到 handleLockSubmit");
  assert.doesNotMatch(
    submit[0], /expected[A-Za-z]*\s*[:=][^\n]*lockConfirmationInput/,
    "handleLockSubmit 把确认输入写进了 expected 字段",
  );
}

console.log("settlement lock amount boundary: 场景 1-5 全部通过");
