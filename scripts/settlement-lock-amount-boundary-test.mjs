import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  buildOnlineDraftLockInput,
  freezeAuthoritativeSnapshot,
  lockConfirmationAccepted,
} from "../js/pages/settlement-online-state.js";

// P0 金额边界：用户手打的确认金额只是闸门，绝不进 payload。
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md 第 6.1 节。
//
// 本文件是该边界的第二层——唯一能真正证明数据流的一层。第一层是冻结快照
// （结构约束），第三层是 API 契约的键集比对。
//
// 初版设计只有一个 sentinel 测试，且是空转的：sentinel 取 999999.123，与 DB 的
// 40000.00 不匹配，闸门理应拦下、API 根本不会被调用，测试不接触被测代码就通过。
// 而且 DECIMAL_RE 允许任意位小数，999999.123 本就是合法金额，初版称其为
// 「非法形态」也是错的。由 Codex 审出，现拆为三个各自能失败的场景。

const SHA_A = "a".repeat(64);
const SHA_B = "b".repeat(64);
const AUTHORITATIVE_CARRY = "40000.00";

const row = { student_id: "S1", year_month: "2026-08" };

const status = Object.freeze({
  contract_version: "student_settlement_online_status_v1",
  student_id: "S1",
  year_month: "2026-08",
  can_lock: true,
  requires_repreview: false,
  lock_blocker_code: null,
  save_blocker_code: null,
  immutable_blocker: null,
  preview_manifest_sha256: SHA_A,
  physical_settlement: { settlement_id: null },
  effective_state: { effective_status: "incomplete" },
  source_treatment_draft: { draft_id: "SD1", status: "active", updated_at: "T" },
  adjustment_draft: { draft_id: "AD1", status: "active", updated_at: "T" },
});

function makePreview() {
  return {
    preview_manifest_sha256: SHA_A,
    preview: {
      lesson_variance_source_count: 3,
      unused_planned_credit_jpy: "0",
      overage_charge_jpy: "0",
      net_lesson_variance_jpy: "0",
      net_lesson_variance_cny: "0",
      projected_final_carryover_cny: AUTHORITATIVE_CARRY,
    },
    preview_expected_facts: {
      lesson_variance_manifest_sha256: SHA_B,
      system_difference_cny: "0",
    },
  };
}

function buildFrom(previewResult, note = "") {
  return buildOnlineDraftLockInput({
    row, status, previewResult, membershipRole: "admin",
    note, clientCorrelationId: "C1",
  });
}

// 递归查找 payload 各层级是否出现某个字符串
function containsDeep(value, needle) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.includes(needle);
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).includes(needle);
  }
  if (Array.isArray(value)) return value.some((item) => containsDeep(item, needle));
  if (typeof value === "object") {
    return Object.entries(value).some(
      ([key, item]) => key.includes(needle) || containsDeep(item, needle),
    );
  }
  return false;
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
    "不同金额被判为匹配"
  );
  for (const bad of ["", "  ", "abc", "4000", "400000.00", "-40000.00"]) {
    assert.equal(
      lockConfirmationAccepted(bad, AUTHORITATIVE_CARRY), false,
      `输入 ${JSON.stringify(bad)} 不应放行`
    );
  }
  // 权威值缺失时一律不放行
  assert.equal(lockConfirmationAccepted(AUTHORITATIVE_CARRY, null), false);
  assert.equal(lockConfirmationAccepted(AUTHORITATIVE_CARRY, undefined), false);
}

// ---------------------------------------------------------------------------
// 场景 2  等值但字符串不同 —— 闸门放行，但值绝不能泄漏
//
//         这是唯一「闸门过了、值仍可能进 payload」的窗口，也是初版完全没有
//         覆盖到的场景。canonicalDecimal 判等使 40000.000 与 40000.00 视为
//         同值，所以提交会被允许；此时必须证明提交的是 DB 原值。
// ---------------------------------------------------------------------------
{
  const TYPED = "40000.000";
  assert.notEqual(TYPED, AUTHORITATIVE_CARRY, "两者字符串必须不同，否则本场景无意义");
  assert.equal(
    lockConfirmationAccepted(TYPED, AUTHORITATIVE_CARRY), true,
    "等值不同串应被闸门放行，否则用户无法完成合法操作"
  );

  const payload = buildFrom(freezeAuthoritativeSnapshot(makePreview()));

  assert.equal(
    payload.expectedFinalCarryoverCny, AUTHORITATIVE_CARRY,
    "提交的结转金额必须是 DB 原值"
  );
  assert.equal(
    containsDeep(payload, TYPED), false,
    `payload 中出现了用户输入的字符串 ${TYPED}`
  );
}

// ---------------------------------------------------------------------------
// 场景 3  render 之后篡改权威快照 —— payload 必须不受影响
//
//         这一条覆盖初版第一层「纯函数签名让错误代码写不出来」被推翻后的
//         真实风险：调用方可以先把 DOM 值写进可变的 previewResult 再传给
//         builder。冻结快照才是真正的结构约束。
// ---------------------------------------------------------------------------
{
  const TAMPERED = "999999.99";
  const frozen = freezeAuthoritativeSnapshot(makePreview());

  // 严格模式抛错，非严格模式静默失败——两种都不得改到值
  try { frozen.preview.projected_final_carryover_cny = TAMPERED; } catch { /* 预期 */ }
  try { frozen.preview_expected_facts.system_difference_cny = TAMPERED; } catch { /* 预期 */ }

  const payload = buildFrom(frozen);
  assert.equal(payload.expectedFinalCarryoverCny, AUTHORITATIVE_CARRY, "结转金额被篡改成功");
  assert.equal(payload.expectedSystemDifferenceCny, "0", "系统差额被篡改成功");
  assert.equal(containsDeep(payload, TAMPERED), false, "被篡改的值进入了 payload");

  // 未冻结的对象则会被改到——这条反证冻结确实是那道防线
  const unfrozen = makePreview();
  unfrozen.preview.projected_final_carryover_cny = TAMPERED;
  assert.equal(
    buildFrom(unfrozen).expectedFinalCarryoverCny, TAMPERED,
    "未冻结时也没被改到，说明本场景没有真正验证冻结的作用"
  );
}

// ---------------------------------------------------------------------------
// 场景 4  第三层：payload 的键集必须与契约完全一致，不多不少
// ---------------------------------------------------------------------------
{
  const payload = buildFrom(freezeAuthoritativeSnapshot(makePreview()), "备注");
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
// ---------------------------------------------------------------------------
{
  const page = readFileSync("js/pages/settlement-page.js", "utf8");
  assert.match(
    page, /lockConfirmationAccepted\(/,
    "settlement-page.js 未调用 lockConfirmationAccepted，闸门可能被另写了一份"
  );
  const fn = /function lockConfirmationMatches\(\)[\s\S]*?\n\}/.exec(page);
  assert(fn, "未找到 lockConfirmationMatches");
  assert.doesNotMatch(
    fn[0], /canonicalDecimal\(/,
    "lockConfirmationMatches 内部自行比对了金额，应交给 lockConfirmationAccepted"
  );
  // 提交路径不得把确认输入写进任何 expected 字段
  const submit = /async function handleLockSubmit\(\)[\s\S]*?\n\}/.exec(page);
  assert(submit, "未找到 handleLockSubmit");
  assert.doesNotMatch(
    submit[0], /expected[A-Za-z]*\s*[:=][^\n]*lockConfirmationInput/,
    "handleLockSubmit 把确认输入写进了 expected 字段"
  );
}

console.log("settlement lock amount boundary: 场景 1-5 全部通过");
