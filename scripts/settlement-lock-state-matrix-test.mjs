import assert from "node:assert/strict";
import {
  LOCK_FAILURE_STATES,
  buildOnlineDraftLockInput,
  canUseOnlineDraftLock,
  classifyLockFailure,
  freezeAuthoritativeSnapshot,
  lockStatusStrictlyUnchanged,
  statusConfirmsDraftLock,
} from "../js/pages/settlement-online-state.js";

// Phase D 锁定侧 state 层的行为矩阵。
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md 第 3 节。
// 全部用 mock 数据，不需要 DB、不需要浏览器、不需要等 2026-09-07。

const S = LOCK_FAILURE_STATES;
const SHA_A = "a".repeat(64);
const SHA_B = "b".repeat(64);

const row = { student_id: "S1", year_month: "2026-08" };

// afterStatus 侧的权威事实。必须与 previewResult 分开定义——两者同源就无法
// 验证「复核后的状态是否仍与请求一致」。
const LIVE_PREVIEW = Object.freeze({
  lesson_variance_source_count: 3,
  unused_planned_credit_jpy: "0",
  overage_charge_jpy: "0",
  net_lesson_variance_jpy: "0",
  net_lesson_variance_cny: "0",
  projected_final_carryover_cny: "40000.00",
});
const BASE_SOURCE_DRAFT = Object.freeze({
  draft_id: "SD1", status: "active", updated_at: "2026-09-07T01:00:00Z",
  source_manifest_sha256: "b".repeat(64), source_count: 3,
});

function makeStatus(over = {}) {
  return {
    contract_version: "student_settlement_online_status_v1",
    student_id: "S1",
    year_month: "2026-08",
    can_lock: true,
    requires_repreview: false,
    lock_blocker_code: null,
    save_blocker_code: null,
    immutable_blocker: null,
    preview_manifest_sha256: SHA_A,
    lesson_manifest_sha256: SHA_B,
    business_entity_id: "BE1",
    authoritative_preview: LIVE_PREVIEW,
    authoritative_system_difference_cny: "0",
    physical_settlement: { settlement_id: null, settlement_status: null, locked_at: null },
    effective_state: { effective_status: "incomplete" },
    source_treatment_draft: { ...BASE_SOURCE_DRAFT },
    adjustment_draft: { draft_id: "AD1", status: "active", updated_at: "2026-09-07T01:00:00Z" },
    ...over,
  };
}

function makePreview(over = {}) {
  return {
    preview_manifest_sha256: SHA_A,
    preview: {
      lesson_variance_source_count: 3,
      unused_planned_credit_jpy: "0",
      overage_charge_jpy: "0",
      net_lesson_variance_jpy: "0",
      net_lesson_variance_cny: "0",
      projected_final_carryover_cny: "40000.00",
      ...(over.preview || {}),
    },
    preview_expected_facts: {
      lesson_variance_manifest_sha256: SHA_B,
      system_difference_cny: "0",
      ...(over.preview_expected_facts || {}),
    },
  };
}

const baseStatus = makeStatus();
const basePreview = makePreview();
const baseInput = buildOnlineDraftLockInput({
  row, status: baseStatus, previewResult: basePreview,
  membershipRole: "admin", note: "", clientCorrelationId: "C1",
});

function classify(over = {}) {
  return classifyLockFailure({
    error: over.error ?? { code: "SETTLEMENT_LOCK_CONFLICT", action: "refresh_status" },
    beforeStatus: over.beforeStatus ?? baseStatus,
    afterStatus: over.afterStatus ?? baseStatus,
    statusReadFailed: over.statusReadFailed ?? false,
    previewResult: over.previewResult ?? basePreview,
    membershipRole: over.membershipRole ?? "admin",
    lockInput: over.lockInput ?? baseInput,
  });
}

// ---------------------------------------------------------------------------
// T1  canUseOnlineDraftLock 的每个条件都必须是必要条件
// ---------------------------------------------------------------------------
{
  assert.equal(canUseOnlineDraftLock("admin", baseStatus), true);

  const denials = [
    ["非 admin", "operator", {}],
    ["can_lock 非 true", "admin", { can_lock: false }],
    ["非 incomplete", "admin", { effective_state: { effective_status: "ordinary_locked" } }],
    ["存在 lock blocker", "admin", { lock_blocker_code: "SETTLEMENT_REPREVIEW_REQUIRED" }],
    ["存在 immutable blocker", "admin", { immutable_blocker: { code: "X" } }],
    ["requires_repreview 为 true", "admin", { requires_repreview: true }],
  ];
  for (const [label, role, over] of denials) {
    assert.equal(
      canUseOnlineDraftLock(role, makeStatus(over)), false,
      `canUseOnlineDraftLock 未拒绝：${label}`
    );
  }
}

// ---------------------------------------------------------------------------
// T2  9/7 的真实场景：开闸但尚无草稿时，can_lock 必须为 false
//     生产查明 6 个 scope 当前两份草稿均为 null、requires_repreview=true
// ---------------------------------------------------------------------------
{
  const justOpened = makeStatus({
    can_save: true,
    can_lock: false,
    requires_repreview: true,
    save_blocker_code: null,
    lock_blocker_code: "SETTLEMENT_REPREVIEW_REQUIRED",
    source_treatment_draft: null,
    adjustment_draft: null,
  });
  assert.equal(canUseOnlineDraftLock("admin", justOpened), false,
    "9/7 开闸但无草稿时不得允许锁定");
  assert.throws(
    () => buildOnlineDraftLockInput({
      row, status: justOpened, previewResult: basePreview,
      membershipRole: "admin", note: "", clientCorrelationId: "C1",
    }),
    /status does not allow lock/,
    "无草稿时 builder 必须拒绝构造 payload"
  );
}

// ---------------------------------------------------------------------------
// T3  builder 的产出必须全部来自权威快照
// ---------------------------------------------------------------------------
{
  assert.equal(baseInput.expectedFinalCarryoverCny, "40000.00");
  assert.equal(baseInput.expectedSourceTreatmentDraftId, "SD1");
  assert.equal(baseInput.confirmLock, true);
  // 契约中不得出现确认输入或 canonical confirmation
  const keys = Object.keys(baseInput);
  for (const forbidden of ["confirmationAmount", "canonicalConfirmation", "canonical_confirmation"]) {
    assert.ok(!keys.includes(forbidden), `payload 不应包含 ${forbidden}`);
  }
}

// ---------------------------------------------------------------------------
// T4  权威快照必须真的冻结，且冻结后篡改不影响 payload
// ---------------------------------------------------------------------------
{
  const frozen = freezeAuthoritativeSnapshot(makePreview());
  assert.ok(Object.isFrozen(frozen), "顶层未冻结");
  assert.ok(Object.isFrozen(frozen.preview), "嵌套对象未冻结");

  // 非严格模式下静默失败，严格模式下抛错——两种都不得改到值
  try { frozen.preview.projected_final_carryover_cny = "999999.123"; } catch { /* 严格模式抛错 */ }
  assert.equal(
    frozen.preview.projected_final_carryover_cny, "40000.00",
    "冻结后仍被篡改成功"
  );

  const inputFromFrozen = buildOnlineDraftLockInput({
    row, status: baseStatus, previewResult: frozen,
    membershipRole: "admin", note: "", clientCorrelationId: "C1",
  });
  assert.equal(inputFromFrozen.expectedFinalCarryoverCny, "40000.00",
    "payload 取到了被篡改的值");

  // 深拷贝：改原始对象不应影响已冻结快照
  const original = makePreview();
  const snapshot = freezeAuthoritativeSnapshot(original);
  original.preview.projected_final_carryover_cny = "1";
  assert.equal(snapshot.preview.projected_final_carryover_cny, "40000.00",
    "快照与原对象共享引用");
}

// ---------------------------------------------------------------------------
// T5  statusConfirmsDraftLock：只有终态 + 两份 consumed + manifest 一致才算成功
// ---------------------------------------------------------------------------
{
  const locked = makeStatus({
    physical_settlement: { settlement_id: "SET1", settlement_status: "locked", locked_at: "T" },
    effective_state: { effective_status: "ordinary_locked" },
    source_treatment_draft: { draft_id: "SD1", status: "consumed", updated_at: "T" },
    adjustment_draft: { draft_id: "AD1", status: "consumed", updated_at: "T" },
  });
  assert.equal(statusConfirmsDraftLock(locked, basePreview), true);

  assert.equal(statusConfirmsDraftLock(baseStatus, basePreview), false,
    "incomplete 不应判为已锁定");
  assert.equal(
    statusConfirmsDraftLock(makeStatus({
      effective_state: { effective_status: "ordinary_locked" },
      source_treatment_draft: { draft_id: "SD1", status: "active", updated_at: "T" },
      adjustment_draft: { draft_id: "AD1", status: "consumed", updated_at: "T" },
    }), basePreview),
    false,
    "草稿未全部 consumed 时不应判为成功"
  );
  assert.equal(
    statusConfirmsDraftLock({ ...locked, preview_manifest_sha256: SHA_B }, basePreview),
    false,
    "manifest 不一致时不应判为成功"
  );
}

// ---------------------------------------------------------------------------
// T6  分流第一层：Edge 明确响应的四类 action
// ---------------------------------------------------------------------------
{
  const cases = [
    [{ code: "SETTLEMENT_ADMIN_REQUIRED", action: "stop" }, S.BLOCKED],
    [{ code: "SETTLEMENT_EDGE_UNAUTHORIZED", action: "reauthenticate" }, S.BLOCKED],
    [{ code: "SETTLEMENT_PREVIEW_MANIFEST_STALE", action: "repreview" }, S.STALE],
    [{ code: "SETTLEMENT_SCOPE_BUSY", action: "retry_later" }, S.BUSY],
  ];
  for (const [error, expected] of cases) {
    assert.equal(classify({ error }), expected,
      `${error.action} 应分流为 ${expected}`);
  }
}

// ---------------------------------------------------------------------------
// T7  分流第二层：refresh_status 且严格未变 → retriable
// ---------------------------------------------------------------------------
{
  // 初版把这里写成 retriable，是错的：SETTLEMENT_LOCK_CONFLICT 表达的是
  // 「现有正式结算与本次请求不一致」，重放同一 payload 只会同样失败。
  // 由 Codex 逐码走查 9 个 refresh_status code 后指出，无一可安全重放。
  assert.equal(
    classify({ error: { code: "SETTLEMENT_LOCK_CONFLICT", action: "refresh_status" } }),
    S.CONFLICT,
    "refresh_status 不得默认放行重试"
  );

  // 全部 9 个生产 refresh_status code 逐一验证，一个都不许是 retriable
  const REFRESH_STATUS_CODES = [
    "SETTLEMENT_NOT_INCOMPLETE",
    "SETTLEMENT_ORDINARY_ALREADY_LOCKED",
    "SETTLEMENT_SOURCE_DRAFT_STALE",
    "SETTLEMENT_ADJUSTMENT_DRAFT_STALE",
    "SETTLEMENT_LOCK_CONFLICT",
    "SETTLEMENT_ONLINE_SAVE_STRUCTURALLY_BLOCKED",
    "SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE",
    "SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED",
    "SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK",
  ];
  for (const code of REFRESH_STATUS_CODES) {
    const got = classify({ error: { code, action: "refresh_status" } });
    assert.notEqual(got, S.RETRIABLE, `${code} 被判为可重放`);
  }

  // 未知 action 必须 fail-closed，不得落进第二层后被放行
  assert.equal(
    classify({ error: { code: "SETTLEMENT_FUTURE_THING", action: "future_action" } }),
    S.UNKNOWN,
    "未知 action 必须按结果未知处理"
  );
}

// ---------------------------------------------------------------------------
// T8  核心安全不变式：结果未知的三类，即使严格未变也绝不可 retriable
//
//     invokeSettlementEdge 用 Promise.race 实现超时，无 AbortController，
//     底层请求仍在继续，可能稍后落库。「此刻未变」证明不了「将来不变」。
// ---------------------------------------------------------------------------
{
  for (const code of [
    "SETTLEMENT_EDGE_RESULT_UNCERTAIN",
    "SETTLEMENT_EDGE_RESPONSE_INVALID",
    "SETTLEMENT_EDGE_REQUEST_FAILED",
  ]) {
    const got = classify({ error: { code, action: "refresh_status" } });
    assert.equal(got, S.UNKNOWN,
      `${code} 在严格未变时被判成 ${got}，必须是 unknown——超时不取消底层请求`);
    assert.notEqual(got, S.RETRIABLE, `${code} 绝不可判为可重试`);
  }
  // 没有 action 的裸异常同样按结果未知处理
  assert.equal(classify({ error: { code: "", action: "" } }), S.UNKNOWN);
}

// ---------------------------------------------------------------------------
// T9  status 读取失败一律 unknown，且优先于其余判定
// ---------------------------------------------------------------------------
{
  assert.equal(
    classify({
      error: { code: "SETTLEMENT_LOCK_CONFLICT", action: "refresh_status" },
      statusReadFailed: true,
    }),
    S.UNKNOWN
  );
}

// ---------------------------------------------------------------------------
// T10 已落库时判为 confirmed，即使来源是超时
// ---------------------------------------------------------------------------
{
  const locked = makeStatus({
    physical_settlement: { settlement_id: "SET1", settlement_status: "locked", locked_at: "T" },
    effective_state: { effective_status: "ordinary_locked" },
    source_treatment_draft: { draft_id: "SD1", status: "consumed", updated_at: "T" },
    adjustment_draft: { draft_id: "AD1", status: "consumed", updated_at: "T" },
  });
  assert.equal(
    classify({
      error: { code: "SETTLEMENT_EDGE_RESULT_UNCERTAIN", action: "refresh_status" },
      afterStatus: locked,
    }),
    S.CONFIRMED,
    "超时后若 status 证明已锁定，应判为成功"
  );
}

// ---------------------------------------------------------------------------
// T11 「严格未变」的九条判据，每一条都必须是必要条件
// ---------------------------------------------------------------------------
{
  assert.equal(lockStatusStrictlyUnchanged({
    beforeStatus: baseStatus, afterStatus: baseStatus,
    previewResult: basePreview, membershipRole: "admin", lockInput: baseInput,
  }), true, "基准场景应判为严格未变");

  const breaks = [
    ["草稿版本变了", { source_treatment_draft: { draft_id: "SD1", status: "active", updated_at: "CHANGED" } }],
    ["已非 incomplete", { effective_state: { effective_status: "ordinary_locked" } }],
    ["物理 settlement 已存在", { physical_settlement: { settlement_id: "SET1" } }],
    ["契约版本变了", { contract_version: "v2" }],
    ["scope 学生不符", { student_id: "OTHER" }],
    ["scope 月份不符", { year_month: "2026-07" }],
    ["requires_repreview 变真", { requires_repreview: true }],
    ["出现 lock blocker", { lock_blocker_code: "X" }],
    ["出现 save blocker", { save_blocker_code: "X" }],
    ["草稿变为 consumed", { source_treatment_draft: { draft_id: "SD1", status: "consumed", updated_at: "2026-09-07T01:00:00Z" } }],
    ["草稿 id 变了", { adjustment_draft: { draft_id: "AD2", status: "active", updated_at: "2026-09-07T01:00:00Z" } }],
  ];
  for (const [label, over] of breaks) {
    assert.equal(
      lockStatusStrictlyUnchanged({
        beforeStatus: baseStatus, afterStatus: makeStatus(over),
        previewResult: basePreview, membershipRole: "admin", lockInput: baseInput,
      }),
      false,
      `未判出变化：${label}`
    );
  }

  // afterStatus 的权威事实变化必须判出。初版这一段拿 previewResult 与 lockInput
  // 互比，而后者本就由前者构造，恒真——改 afterStatus 的 manifest 完全不影响
  // 结果。由 Codex 动态反证。
  const authoritativeBreaks = [
    ["afterStatus 的 preview manifest 变了", { preview_manifest_sha256: "c".repeat(64) }],
    ["afterStatus 的 lesson manifest 变了", { lesson_manifest_sha256: "c".repeat(64) }],
    ["business entity 变了", { business_entity_id: "BE2" }],
    ["权威结转变了", { authoritative_preview: { ...LIVE_PREVIEW, projected_final_carryover_cny: "50000.00" } }],
    ["权威系统差额变了", { authoritative_system_difference_cny: "77" }],
    ["source count 变了", { source_treatment_draft: { ...BASE_SOURCE_DRAFT, source_count: 9 } }],
  ];
  for (const [label, over] of authoritativeBreaks) {
    assert.equal(
      lockStatusStrictlyUnchanged({
        beforeStatus: baseStatus, afterStatus: makeStatus(over),
        previewResult: basePreview, membershipRole: "admin", lockInput: baseInput,
      }),
      false,
      `未判出变化：${label}`
    );
  }

  // 角色必须用当前真实值，不得写死 admin
  assert.equal(
    lockStatusStrictlyUnchanged({
      beforeStatus: baseStatus, afterStatus: baseStatus,
      previewResult: basePreview, membershipRole: "operator", lockInput: baseInput,
    }),
    false,
    "角色降级后仍判为严格未变——不得写死 admin"
  );

  // canonicalDecimal 判等：afterStatus 的权威结转写成 40000.000 时，
  // 与 payload 的 40000.00 应视为同值，不算变化。
  // 注意基准是 afterStatus 而非 previewResult——初版在这里操作 previewResult，
  // 而它已不再是比对基准，那样的断言测不到任何东西。
  assert.equal(
    lockStatusStrictlyUnchanged({
      beforeStatus: baseStatus,
      afterStatus: makeStatus({
        authoritative_preview: { ...LIVE_PREVIEW, projected_final_carryover_cny: "40000.000" },
      }),
      previewResult: basePreview, membershipRole: "admin", lockInput: baseInput,
    }),
    true,
    "同值不同字符串被误判为变化"
  );
}

console.log("settlement lock state matrix: T1-T11 全部通过");
