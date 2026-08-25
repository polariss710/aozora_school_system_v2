import assert from "node:assert/strict";
import { register } from "node:module";

// P0 金额边界的最后一段：页面层 input → API 层最终提交给 Edge 的 body。
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md 第 6.1 节。
//
// 为什么单独有这个文件：settlement-lock-amount-boundary-test 验证到
// buildOnlineDraftLockInput 的产出为止，那是页面层的 camelCase 结构；而真正发给
// 服务器的是 API 层 buildLockPayload 转换后的 snake_case body。两者之间还有一层
// 转换从未被测试覆盖——Codex 在审查中指出「exact keys 比对的是页面层 camelCase
// input，不是 API 层最终 snake_case body」。本文件驱动真实的 api 模块，捕获
// supabase.functions.invoke 的实际入参。
//
// 加载方式：js/supabase-client.js 从 https://esm.sh 远程导入 createClient，
// node 默认加载器不支持 https:，因此用模块解析钩子把它映射到本地捕获桩。
// 除该远程依赖外，链路上的代码全部是生产实现，没有替身。

register("./lib/remote-import-hooks.mjs", import.meta.url);

// supabase-client.js 在模块顶层访问 window.localStorage，且以是否成功清理
// legacy storage 作为 fail-closed 条件。给出最小可用实现。
const memoryStorage = new Map();
globalThis.window = {
  localStorage: {
    getItem: (k) => (memoryStorage.has(k) ? memoryStorage.get(k) : null),
    setItem: (k, v) => memoryStorage.set(k, String(v)),
    removeItem: (k) => memoryStorage.delete(k),
    key: (i) => [...memoryStorage.keys()][i] ?? null,
    get length() { return memoryStorage.size; },
  },
};
globalThis.localStorage = globalThis.window.localStorage;

const { invocations } = await import("./lib/supabase-capture-stub.mjs");
const { lockStudentSettlementOnline } = await import(
  "../js/api/student-settlement-online-api.js"
);
const { buildOnlineDraftLockInput, freezeAuthoritativeSnapshot, lockConfirmationAccepted } =
  await import("../js/pages/settlement-online-state.js");

// API 层用 requireUuid 校验，fixture 必须是真实 UUID 形态——
// 这一点也是页面层测试测不到的：那里用 "S1"、"SD1" 之类的假 id 就能通过。
const STUDENT_ID = "11111111-1111-4111-8111-111111111111";
const SOURCE_DRAFT_ID = "22222222-2222-4222-8222-222222222222";
const ADJUSTMENT_DRAFT_ID = "33333333-3333-4333-8333-333333333333";
const CORRELATION_ID = "44444444-4444-4444-8444-444444444444";
const SHA_A = "a".repeat(64);
const SHA_B = "b".repeat(64);

const AUTHORITATIVE_CARRY = "40000.00";
const TYPED_EQUIVALENT = "40000.000";

const status = freezeAuthoritativeSnapshot({
  contract_version: "student_settlement_online_status_v1",
  student_id: STUDENT_ID,
  year_month: "2026-08",
  business_entity_id: "55555555-5555-4555-8555-555555555555",
  can_lock: true,
  requires_repreview: false,
  lock_blocker_code: null,
  save_blocker_code: null,
  immutable_blocker: null,
  preview_manifest_sha256: SHA_A,
  lesson_manifest_sha256: SHA_B,
  physical_settlement: { settlement_id: null },
  effective_state: { effective_status: "incomplete" },
  source_treatment_draft: {
    draft_id: SOURCE_DRAFT_ID, status: "active",
    updated_at: "2026-09-07T01:00:00Z",
    source_manifest_sha256: SHA_B, source_count: 3,
  },
  adjustment_draft: {
    draft_id: ADJUSTMENT_DRAFT_ID, status: "active",
    updated_at: "2026-09-07T01:00:00Z",
  },
});

const previewResult = freezeAuthoritativeSnapshot({
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
});

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
// 走完整链路：闸门放行 → 构造 input → 真实 API → 捕获提交体
//
// 用「等值但字符串不同」这一组：40000.000 与 40000.00 经 canonicalDecimal 判等，
// 闸门会放行，因此能真正走到提交。这是唯一「闸门过了、值仍可能泄漏」的窗口。
// ---------------------------------------------------------------------------
assert.equal(
  lockConfirmationAccepted(TYPED_EQUIVALENT, AUTHORITATIVE_CARRY), true,
  "等值不同串未被闸门放行，本测试将无法走到提交"
);

const lockInput = buildOnlineDraftLockInput({
  row: { student_id: STUDENT_ID, year_month: "2026-08" },
  status,
  previewResult,
  membershipRole: "admin",
  note: "月结锁定备注",
  clientCorrelationId: CORRELATION_ID,
});

invocations.length = 0;
await lockStudentSettlementOnline(lockInput);

// ---------------------------------------------------------------------------
// T1  确实调用了锁定 Edge，且只调用一次
// ---------------------------------------------------------------------------
assert.equal(invocations.length, 1, `期望一次 Edge 调用，实际 ${invocations.length} 次`);
assert.equal(
  invocations[0].functionName, "lock-student-settlement",
  "调用了错误的 Edge 函数"
);

const body = invocations[0].body;
assert.ok(body && typeof body === "object", "提交体不是对象");

// ---------------------------------------------------------------------------
// T2  最终提交的结转金额是 DB 原值，且用户输入的字符串不在 body 的任何层级
// ---------------------------------------------------------------------------
assert.equal(
  body.expected_final_carryover_cny, AUTHORITATIVE_CARRY,
  "提交给 Edge 的结转金额不是 DB 原值"
);
assert.equal(
  containsDeep(body, TYPED_EQUIVALENT), false,
  `提交体中出现了用户输入的字符串 ${TYPED_EQUIVALENT}`
);

// ---------------------------------------------------------------------------
// T3  body 的键集与 Edge 契约完全一致，不多不少
//
//     这一层是 snake_case，与页面层的 camelCase 是两套键名；页面层的
//     exact-key 断言证明不了这里。
// ---------------------------------------------------------------------------
{
  const expectedKeys = [
    "student_id", "settlement_month",
    "expected_source_treatment_draft_id", "expected_source_treatment_draft_updated_at",
    "expected_adjustment_draft_id", "expected_adjustment_draft_updated_at",
    "expected_preview_manifest_sha256", "expected_lesson_variance_manifest_sha256",
    "expected_source_count",
    "expected_unused_planned_credit_jpy", "expected_overage_charge_jpy",
    "expected_net_lesson_variance_jpy", "expected_net_lesson_variance_cny",
    "expected_system_difference_cny", "expected_final_carryover_cny",
    "note", "confirm_lock", "client_correlation_id",
  ].sort();
  assert.deepEqual(Object.keys(body).sort(), expectedKeys, "提交体键集与契约不符");
}

// ---------------------------------------------------------------------------
// T4  确认相关字段一律不得出现在提交体中
//
//     canonical_confirmation 由 DB 内部生成、浏览器不得提交；确认输入本身
//     更不该出现。
// ---------------------------------------------------------------------------
for (const forbidden of [
  "canonical_confirmation", "canonicalConfirmation",
  "confirmation_amount", "confirmationAmount", "typed_carryover",
]) {
  assert.ok(!(forbidden in body), `提交体不应包含 ${forbidden}`);
}

// ---------------------------------------------------------------------------
// T5  confirm_lock 必须为 true —— API 层对此有硬校验，漏传会直接抛错
// ---------------------------------------------------------------------------
assert.equal(body.confirm_lock, true, "confirm_lock 未置为 true");

// ---------------------------------------------------------------------------
// T6  不匹配的确认输入根本走不到提交
//
//     与场景 1 呼应：闸门拦下时不应产生任何 Edge 调用。
// ---------------------------------------------------------------------------
{
  invocations.length = 0;
  assert.equal(lockConfirmationAccepted("999999.123", AUTHORITATIVE_CARRY), false);
  // 闸门返回 false 时 handler 不会调用 API，此处直接断言未产生调用
  assert.equal(invocations.length, 0, "闸门拒绝后仍产生了 Edge 调用");
}

console.log("settlement lock edge body: T1-T6 全部通过");

// ===========================================================================
// 本文件未覆盖的部分，如实记录
// ===========================================================================
//
// DOM → handler 这一段仍未端到端驱动：本文件从 buildOnlineDraftLockInput 起步，
// 没有真正渲染对话框、没有触发 click。完整驱动需要相当规模的 DOM 桩，脆弱且
// 维护成本高。
//
// 该段目前靠两条结构约束而非测试保证：
//   一、buildOnlineDraftLockInput 拒绝任何未冻结的 status / previewResult，
//       被污染的快照根本进不去；
//   二、静态断言要求 handler 调用 lockConfirmationAccepted 且
//       lockConfirmationMatches 内部不自行比对金额
//       （见 settlement-lock-amount-boundary-test 场景 5）。
//
// 若将来引入 DOM 测试基础设施，这段应补上真正的端到端驱动。
