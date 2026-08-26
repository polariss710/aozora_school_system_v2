import { isAuthoritativeSnapshot } from "../api/settlement-api.js?v=phase-d-lock-authoritative-source-20260826-1";

const DECIMAL_RE = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/;

export const ONLINE_ADJUSTMENT_MODES = Object.freeze({
  CARRY_FINAL_BALANCE: "carry_final_balance",
  CLEAR_BALANCE: "clear_balance",
  MANUAL_ADJUSTMENT: "manual_adjustment",
});

export const ONLINE_SOURCE_TREATMENT_MODES = Object.freeze({
  SEPARATE: "separate_makeup_and_overage_v1",
  NET_FINANCIAL: "net_lesson_variance_to_financial_credit_v1",
});

const REGISTERED_VARIANCE_CONTRACT_VERSION = "registered_lesson_variance_summary_v1";
const SHA256_RE = /^[0-9a-f]{64}$/;
const REGISTERED_NET_DIRECTIONS = new Set(["pending", "overage", "balanced"]);

export function readRegisteredVarianceSummary(preview) {
  if (preview?.source_treatment_mode !== ONLINE_SOURCE_TREATMENT_MODES.SEPARATE) {
    return { status: "hidden" };
  }
  if (preview.registered_variance_contract_version !== REGISTERED_VARIANCE_CONTRACT_VERSION) {
    return { status: "unavailable" };
  }
  if (preview.variance_summary_status === "empty") {
    return isNonnegativeInteger(preview.registered_source_count)
      && preview.registered_source_count === 0
      ? { status: "empty" }
      : { status: "unavailable" };
  }
  if (preview.variance_summary_status !== "ready"
      || !REGISTERED_NET_DIRECTIONS.has(preview.registered_net_direction)
      || !SHA256_RE.test(String(preview.variance_summary_manifest_sha256 || ""))
      || !isNonnegativeInteger(preview.registered_source_count)
      || preview.registered_source_count < 1
      || !isNonnegativeInteger(preview.unresolved_planned_count)
      || typeof preview.registered_overage_included_in_system_difference !== "boolean") {
    return { status: "unavailable" };
  }
  const numericFields = [
    "registered_pending_hours",
    "registered_pending_amount_jpy",
    "registered_overage_hours",
    "registered_overage_amount_jpy",
    "registered_overage_amount_cny",
    "registered_net_hours",
    "registered_net_amount_jpy",
  ];
  if (numericFields.some((field) => !isNonnegativeDecimal(preview[field]))) {
    return { status: "unavailable" };
  }
  return {
    status: "ready",
    pendingHours: preview.registered_pending_hours,
    pendingAmountJpy: preview.registered_pending_amount_jpy,
    overageHours: preview.registered_overage_hours,
    overageAmountJpy: preview.registered_overage_amount_jpy,
    overageAmountCny: preview.registered_overage_amount_cny,
    netDirection: preview.registered_net_direction,
    netHours: preview.registered_net_hours,
    netAmountJpy: preview.registered_net_amount_jpy,
    unresolvedPlannedCount: preview.unresolved_planned_count,
    overageIncludedInSystemDifference:
      preview.registered_overage_included_in_system_difference,
    sourceCount: preview.registered_source_count,
    manifestSha256: preview.variance_summary_manifest_sha256,
  };
}

export function canUseOnlineDraftSave(membershipRole, status) {
  return membershipRole === "admin"
    && status?.can_save === true
    && status?.effective_state?.effective_status === "incomplete"
    && !status?.save_blocker_code
    && !status?.immutable_blocker;
}

const PREVIEW_ONLY_MONTH_BLOCKERS = new Set([
  "SETTLEMENT_MONTH_NOT_CLOSED",
  "SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED",
  "SETTLEMENT_LESSON_WEEK_NOT_CLOSED",
]);

export function canUseOnlineDraftPreview(membershipRole, status) {
  if (membershipRole !== "admin"
      || status?.effective_state?.effective_status !== "incomplete") return false;
  if (canUseOnlineDraftSave(membershipRole, status)) return true;
  return PREVIEW_ONLY_MONTH_BLOCKERS.has(status?.save_blocker_code)
    && status?.immutable_blocker?.code === status.save_blocker_code;
}

export function decimalString(value, fieldName = "decimal") {
  const text = value === null || value === undefined ? "" : String(value).trim();
  if (!DECIMAL_RE.test(text)) {
    throw new Error(`${fieldName} must be a decimal string`);
  }
  return text;
}

export function optionalDecimalString(value, fieldName = "decimal") {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  return decimalString(value, fieldName);
}

export function isPositiveDecimalString(value) {
  const text = String(value || "").trim();
  if (!DECIMAL_RE.test(text) || text.startsWith("-")) return false;
  return /[1-9]/.test(text);
}

export function canonicalDecimal(value) {
  const text = decimalString(value);
  const negative = text.startsWith("-");
  const unsigned = negative ? text.slice(1) : text;
  const [integerPart, fractionPart = ""] = unsigned.split(".");
  const integer = integerPart.replace(/^0+(?=\d)/, "");
  const fraction = fractionPart.replace(/0+$/, "");
  const magnitude = fraction ? `${integer}.${fraction}` : integer;
  if (/^0(?:\.0*)?$/.test(magnitude)) return "0";
  return negative ? `-${magnitude}` : magnitude;
}

export function onlineStatusDisplay(status, statusError = null) {
  if (statusError || !status) {
    return {
      key: "unknown",
      label: "在线状态未知",
      detail: "暂时无法读取DB权威在线状态，本条保持只读。",
      className: "status-cancelled",
    };
  }
  const effective = status.effective_state?.effective_status || "incomplete";
  const blocker = status.save_blocker_code
    ? {
      code: status.save_blocker_code,
      detail: status.save_blocker_message || status.immutable_blocker?.detail,
    }
    : status.immutable_blocker;
  if (blocker) {
    return {
      key: blocker.code || "blocked",
      label: blockerLabel(blocker.code),
      detail: blocker.detail || "该月份当前不可修改。",
      className: "status-cancelled",
    };
  }
  if (effective === "ordinary_locked") {
    return { key: effective, label: "已正式锁定", detail: "该月份已正式锁定，只能查看。", className: "status-paid" };
  }
  if (effective === "historically_consumed_immutable") {
    return { key: effective, label: "历史消费只读", detail: "该月份已被历史账单或不可变事实消费，只能查看。", className: "status-paid" };
  }
  if (effective === "historical_zero_carry_complete") {
    return { key: effective, label: "历史零结转已完成", detail: "该月份已通过历史零结转证据完成，只能查看。", className: "status-paid" };
  }
  if (status.requires_repreview === false) {
    return { key: "draft_saved", label: "草稿已保存", detail: "当前草稿与DB权威预览一致，可以正式锁定。", className: "status-paid" };
  }
  // 只有 lock 侧被拦、save 仍可用时，不能沿用上面 blocker 分支的
  // status-cancelled 外观——那会把一个「可以继续操作」的行显示成已冻结。
  // 这类 blocker（主要是 SETTLEMENT_REPREVIEW_REQUIRED）表达的是「下一步要
  // 先保存草稿」，属于正常流程中的一环。
  //
  // 本分支是 2026-08-25 新增：此前 onlineStatusDisplay 只读 save_blocker_code，
  // 从不读 lock_blocker_code，导致 Phase D 上线后 9/7 开闸的引导文案根本不会
  // 被展示。
  if (status.lock_blocker_code) {
    return {
      key: status.lock_blocker_code,
      label: blockerLabel(status.lock_blocker_code),
      detail: status.lock_blocker_message || "需先保存草稿才能正式锁定。",
      className: "status-pending",
    };
  }
  return { key: "incomplete", label: "未完成", detail: "可读取DB权威预览；需先保存草稿才能正式锁定。", className: "status-pending" };
}

export function buildOnlineDraftSaveInput({ row, status, previewResult, input }) {
  if (!row?.student_id || !row?.year_month) throw new Error("settlement scope is required");
  if (!canUseOnlineDraftSave("admin", status)) throw new Error("status does not allow save");
  if (!previewResult?.preview || !previewResult?.preview_expected_facts) {
    throw new Error("authoritative preview is required");
  }
  const sourceMode = input.sourceTreatmentMode;
  const adjustmentMode = input.adjustmentMode;
  if (!Object.values(ONLINE_SOURCE_TREATMENT_MODES).includes(sourceMode)) {
    throw new Error("source treatment mode is invalid");
  }
  if (!Object.values(ONLINE_ADJUSTMENT_MODES).includes(adjustmentMode)) {
    throw new Error("adjustment mode is invalid");
  }
  const reason = String(input.reason || "").trim();
  const manualAmount = adjustmentMode === ONLINE_ADJUSTMENT_MODES.MANUAL_ADJUSTMENT
    ? decimalString(input.explicitUserAmountCny, "manualAdjustmentAmountCny")
    : null;
  if (!reason) throw new Error("reason is required by the save contract");
  const preview = previewResult.preview;
  const expected = previewResult.preview_expected_facts;
  return {
    studentId: row.student_id,
    settlementMonth: row.year_month,
    sourceTreatmentMode: sourceMode,
    settlementExchangeRate: optionalDecimalString(input.settlementExchangeRate, "settlementExchangeRate"),
    settlementExchangeRateSource: input.settlementExchangeRateSource || null,
    settlementExchangeRateEffectiveDate: input.settlementExchangeRateEffectiveDate || null,
    adjustmentMode,
    manualAdjustmentAmountCny: manualAmount,
    reason,
    note: String(input.note || ""),
    expectedPreviewManifestSha256: previewResult.preview_manifest_sha256,
    expectedLessonVarianceManifestSha256: expected.lesson_variance_manifest_sha256,
    expectedSourceCount: requireSourceCount(preview.lesson_variance_source_count),
    expectedUnusedPlannedCreditJpy: decimalString(preview.unused_planned_credit_jpy, "expectedUnusedPlannedCreditJpy"),
    expectedOverageChargeJpy: decimalString(preview.overage_charge_jpy, "expectedOverageChargeJpy"),
    expectedNetLessonVarianceJpy: decimalString(preview.net_lesson_variance_jpy, "expectedNetLessonVarianceJpy"),
    expectedNetLessonVarianceCny: decimalString(preview.net_lesson_variance_cny, "expectedNetLessonVarianceCny"),
    expectedSystemDifferenceCny: decimalString(expected.system_difference_cny, "expectedSystemDifferenceCny"),
    expectedFinalCarryoverCny: decimalString(preview.projected_final_carryover_cny, "expectedFinalCarryoverCny"),
    expectedSourceTreatmentDraftId: status.source_treatment_draft?.draft_id || null,
    expectedSourceTreatmentDraftUpdatedAt: status.source_treatment_draft?.updated_at || null,
    expectedAdjustmentDraftId: status.adjustment_draft?.draft_id || null,
    expectedAdjustmentDraftUpdatedAt: status.adjustment_draft?.updated_at || null,
  };
}

export function statusConfirmsDraftSave(status, previewResult, input) {
  if (!status || !previewResult?.preview || !previewResult?.preview_expected_facts) return false;
  const source = status.source_treatment_draft || {};
  const adjustment = status.adjustment_draft || {};
  const preview = previewResult.preview;
  const expected = previewResult.preview_expected_facts;
  if (!canUseOnlineDraftSave("admin", status)
      || source.status !== "active" || adjustment.status !== "active"
      || !source.draft_id || !adjustment.draft_id) return false;
  if (status.preview_manifest_sha256 !== previewResult.preview_manifest_sha256
      || status.lesson_manifest_sha256 !== expected.lesson_variance_manifest_sha256
      || source.source_manifest_sha256 !== expected.lesson_variance_manifest_sha256
      || source.source_count !== preview.lesson_variance_source_count
      || source.source_treatment_mode !== input.sourceTreatmentMode
      || adjustment.adjustment_mode !== input.adjustmentMode
      || nullableText(adjustment.reason).trim() !== nullableText(input.reason).trim()
      || nullableText(adjustment.note).trim() !== nullableText(input.note).trim()) return false;
  if (!sameNullableDecimal(source.settlement_exchange_rate, input.settlementExchangeRate)
      || nullableText(source.settlement_exchange_rate_source) !== nullableText(input.settlementExchangeRateSource)
      || nullableText(source.settlement_exchange_rate_effective_date) !== nullableText(input.settlementExchangeRateEffectiveDate)
      || canonicalDecimal(adjustment.adjustment_amount_cny) !== canonicalDecimal(preview.projected_adjustment_amount_cny)) return false;
  return status.requires_repreview === false;
}

export function classifySaveRecovery(beforeStatus, afterStatus, previewResult, input) {
  if (statusConfirmsDraftSave(afterStatus, previewResult, input)) return "confirmed";
  if (sameDraftVersions(beforeStatus, afterStatus)) return "unchanged";
  return "conflict";
}

export function sameDraftVersions(left, right) {
  return ["source_treatment_draft", "adjustment_draft"].every((key) => (
    nullableText(left?.[key]?.draft_id) === nullableText(right?.[key]?.draft_id)
    && nullableText(left?.[key]?.updated_at) === nullableText(right?.[key]?.updated_at)
  ));
}

export function createSingleFlight() {
  let active = false;
  return {
    get active() { return active; },
    async run(task) {
      if (active) return { skipped: true };
      active = true;
      try {
        return { skipped: false, value: await task() };
      } finally {
        active = false;
      }
    },
  };
}

function sameNullableDecimal(left, right) {
  if ((left === null || left === undefined || left === "")
      && (right === null || right === undefined || right === "")) return true;
  try {
    return canonicalDecimal(left) === canonicalDecimal(right);
  } catch (_error) {
    return false;
  }
}

function nullableText(value) {
  return value === null || value === undefined || value === "" ? "" : String(value);
}

function requireSourceCount(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("expectedSourceCount is invalid");
  return value;
}

function isNonnegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function isNonnegativeDecimal(value) {
  if (value === null || value === undefined || value === "") return false;
  const text = String(value).trim();
  return DECIMAL_RE.test(text) && !text.startsWith("-");
}

function blockerLabel(code) {
  return {
    SETTLEMENT_ORDINARY_ALREADY_LOCKED: "已正式锁定",
    SETTLEMENT_HISTORICALLY_CONSUMED: "历史消费只读",
    SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE: "历史零结转已完成",
    SETTLEMENT_SUCCESSOR_REVISION_BLOCKED: "后继学费事实已冻结",
    SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED: "不可变财务事实已消费",
    SETTLEMENT_WAGE_BLOCKED: "工资链路已冻结",
    SETTLEMENT_MONTH_NOT_CLOSED: "当前月份仅可预览",
    SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED: "未来月份仅可预览",
    SETTLEMENT_LESSON_WEEK_NOT_CLOSED: "自然周未结束仅可预览",
    // 只出现在 status JSON 的 lock_blocker_code，从不被 raise，因此不在 Edge
    // 的 DB_ERROR_MAP 中——它的文案归属就是这里。
    SETTLEMENT_REPREVIEW_REQUIRED: "需先保存草稿才能锁定",
    SETTLEMENT_SOURCE_FACTS_EMPTY: "无可结算来源",
    SETTLEMENT_NOT_INCOMPLETE: "非普通未完成状态",
    SETTLEMENT_SCOPE_NOT_UNIQUE: "结算范围不唯一",
  }[code] || "当前不可修改";
}

// ===========================================================================
// Phase D —— 正式锁定（lock）侧
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md
// 与 save 侧严格对称，canonicalDecimal / sameDraftVersions / createSingleFlight
// 直接复用，不复制。
// ===========================================================================

// 权威快照的登记与判据都在 API 层（js/api/settlement-api.js）。
//
// 本模块只导入只读的 isAuthoritativeSnapshot，拿不到登记入口——这是刻意的。
// 早先版本在此导出 freezeAuthoritativeSnapshot，页面因而可以先把 DOM 值写进
// 一个对象、再调该函数登记它，登记检查就只是一道检查而非来源约束。
//
// 注意：判据依赖 API 模块内的 WeakSet，因此本模块与 settlement-page.js 对
// settlement-api.js 的导入查询串必须完全一致——不同查询串会产生不同模块实例、
// 各自持有互不相通的 WeakSet，使所有权威快照在另一实例中判为 false。
// 这是功能性不变式，不只是缓存卫生问题，已由静态断言看住。

/**
 * 确认闸门：用户手打的金额是否与 DB 权威结转一致。
 *
 * 抽成纯函数有两个理由：一是让它可以脱离 DOM 直接测试——这道闸门是 P0 金额
 * 边界的唯一入口，不能因为「需要浏览器」而在日常回归中被跳过；二是明确它的
 * 职责只有比对，不产生任何将被提交的值。
 *
 * 返回 true 只代表可以放行提交，提交的金额仍一律取自权威快照。
 */
export function lockConfirmationAccepted(typedValue, authoritativeValue) {
  if (authoritativeValue === null || authoritativeValue === undefined) return false;
  const typed = String(typedValue ?? "").trim();
  if (!typed) return false;
  try {
    return canonicalDecimal(typed) === canonicalDecimal(authoritativeValue);
  } catch {
    return false;
  }
}

export function canUseOnlineDraftLock(membershipRole, status) {
  return membershipRole === "admin"
    && status?.can_lock === true
    && status?.effective_state?.effective_status === "incomplete"
    && !status?.lock_blocker_code
    && !status?.immutable_blocker
    && status?.requires_repreview === false;
}

/**
 * 产出 lockStudentSettlementOnline 所需输入。
 *
 * 参数表中没有确认金额——但这不是保障，JS 的参数表证明不了对象来源。
 * 保障来自传入的 status / previewResult 必须是 API 层权威读取入口产出的快照，
 * 而那两个入口的参数表只含 scope，页面递不进任何值。
 * 每一个 expected_* 字段都取自快照，无一项由前端计算或来自 DOM。
 */
export function buildOnlineDraftLockInput({
  row, status, previewResult, membershipRole, note, clientCorrelationId,
}) {
  if (!row?.student_id || !row?.year_month) throw new Error("settlement scope is required");
  if (!canUseOnlineDraftLock(membershipRole, status)) {
    throw new Error("status does not allow lock");
  }
  if (!previewResult?.preview || !previewResult?.preview_expected_facts) {
    throw new Error("authoritative preview is required");
  }
  // 只接受 API 层权威读取入口产出的快照。
  //
  // 判据的演进（每一步都是被证伪后才改的）：
  //   1. 「纯函数签名让错误代码写不出来」——错。JS 参数表证明不了对象来源，
  //      调用方可先把 DOM 值写进可变的 previewResult 再传进来。
  //   2. Object.isFrozen——不够。构造一个被污染的对象再手动 Object.freeze
  //      就能通过，实测可以把 999999.99 送进 payload。
  //   3. 页面层导出的 freezeAuthoritativeSnapshot 登记——仍不够。登记入口是
  //      公开的且无条件登记任意对象，先污染再登记即可绕过。
  //
  // 现在判据是「是否来自 API 层的 scope-only 读取入口」：登记入口是
  // settlement-api.js 的模块私有函数，没有任何模块能登记自己构造的对象；
  // 对外的两个入口只收 studentId + yearMonth，其余 RPC 参数在 API 层从
  // status 现取。这才是来源约束，而不是又一道检查。
  if (!isAuthoritativeSnapshot(previewResult)) {
    throw new Error("previewResult must be a frozen authoritative snapshot");
  }
  if (!isAuthoritativeSnapshot(status)) {
    throw new Error("status must be a frozen authoritative snapshot");
  }
  const sourceDraftId = status.source_treatment_draft?.draft_id;
  const adjustmentDraftId = status.adjustment_draft?.draft_id;
  if (!sourceDraftId || !adjustmentDraftId) {
    throw new Error("both drafts are required before lock");
  }
  const preview = previewResult.preview;
  const expected = previewResult.preview_expected_facts;
  return {
    studentId: row.student_id,
    settlementMonth: row.year_month,
    expectedSourceTreatmentDraftId: sourceDraftId,
    expectedSourceTreatmentDraftUpdatedAt: status.source_treatment_draft?.updated_at || null,
    expectedAdjustmentDraftId: adjustmentDraftId,
    expectedAdjustmentDraftUpdatedAt: status.adjustment_draft?.updated_at || null,
    expectedPreviewManifestSha256: previewResult.preview_manifest_sha256,
    expectedLessonVarianceManifestSha256: expected.lesson_variance_manifest_sha256,
    expectedSourceCount: requireSourceCount(preview.lesson_variance_source_count),
    expectedUnusedPlannedCreditJpy: decimalString(preview.unused_planned_credit_jpy, "expectedUnusedPlannedCreditJpy"),
    expectedOverageChargeJpy: decimalString(preview.overage_charge_jpy, "expectedOverageChargeJpy"),
    expectedNetLessonVarianceJpy: decimalString(preview.net_lesson_variance_jpy, "expectedNetLessonVarianceJpy"),
    expectedNetLessonVarianceCny: decimalString(preview.net_lesson_variance_cny, "expectedNetLessonVarianceCny"),
    expectedSystemDifferenceCny: decimalString(expected.system_difference_cny, "expectedSystemDifferenceCny"),
    expectedFinalCarryoverCny: decimalString(preview.projected_final_carryover_cny, "expectedFinalCarryoverCny"),
    note: String(note || ""),
    confirmLock: true,
    clientCorrelationId: clientCorrelationId || null,
  };
}

/**
 * 判定锁定确实落库。
 * lock 会产生终态，因此比 save 侧更好判定：effective_status 翻为
 * ordinary_locked，且两份草稿由 active 变为 consumed。
 * 生产已确认该行为，实例 6ec3b815-…（彭宇晗 2026-07）。
 */
export function statusConfirmsDraftLock(status, previewResult) {
  if (!status || !previewResult?.preview_expected_facts) return false;
  if (status.effective_state?.effective_status !== "ordinary_locked") return false;
  const source = status.source_treatment_draft || {};
  const adjustment = status.adjustment_draft || {};
  if (source.status !== "consumed" || adjustment.status !== "consumed") return false;
  return status.preview_manifest_sha256 === previewResult.preview_manifest_sha256;
}

/**
 * 「严格未变」——比 save 侧的 sameDraftVersions 严格得多。
 *
 * 只看草稿版本不够：权限错误、body 校验错误发生时 status 完全没变，
 * 若据此允许重试，就是在重放一个必然再次失败的请求。
 * 九条判据全部成立才算未变。
 */
export function lockStatusStrictlyUnchanged({
  beforeStatus, afterStatus, previewResult, membershipRole, lockInput,
}) {
  if (!beforeStatus || !afterStatus || !previewResult || !lockInput) return false;

  if (!sameDraftVersions(beforeStatus, afterStatus)) return false;
  if (afterStatus.effective_state?.effective_status !== "incomplete") return false;
  // lock 的直接后果就是创建物理 settlement 行；它一旦存在就不是「未变」。
  // 字段路径是 status.physical_settlement.settlement_id——effective_state 下
  // 只有 effective_complete / effective_status / source_type / source_id /
  // carry_cny，没有 settlement_id。初版写成 effective_state.settlement_id，
  // 取到的永远是 undefined，该判据成了永不触发的死代码。
  if (afterStatus.physical_settlement?.settlement_id) return false;
  // 必须用当前真实角色，不得写死 "admin"——角色可能在此期间变化
  if (!canUseOnlineDraftLock(membershipRole, afterStatus)) return false;
  // 契约版本变化意味着语义可能已变，不能跨版本比较
  if (nullableText(beforeStatus.contract_version) !== nullableText(afterStatus.contract_version)) return false;
  if (nullableText(afterStatus.student_id) !== nullableText(lockInput.studentId)) return false;
  if (nullableText(afterStatus.year_month) !== nullableText(lockInput.settlementMonth)) return false;
  if (afterStatus.requires_repreview !== false) return false;
  if (afterStatus.lock_blocker_code || afterStatus.save_blocker_code || afterStatus.immutable_blocker) return false;

  const source = afterStatus.source_treatment_draft || {};
  const adjustment = afterStatus.adjustment_draft || {};
  if (source.status !== "active" || adjustment.status !== "active") return false;
  if (nullableText(source.draft_id) !== nullableText(lockInput.expectedSourceTreatmentDraftId)) return false;
  if (nullableText(adjustment.draft_id) !== nullableText(lockInput.expectedAdjustmentDraftId)) return false;

  // 与 afterStatus 逐项比对——不是与 previewResult 比。
  //
  // 初版这里拿 previewResult 与 lockInput 互比，而 lockInput 本就是从
  // previewResult 构造的，等于自己跟自己比，恒真。动态反证：改
  // afterStatus.preview_manifest_sha256 或 business_entity_id 后仍返回 true。
  // 由 Codex 审出。要证明「复核后的 DB 状态与本次请求一致」，比对对象必须是
  // 复核读回来的 afterStatus。
  if (nullableText(beforeStatus.business_entity_id) !== nullableText(afterStatus.business_entity_id)) return false;
  if (nullableText(afterStatus.preview_manifest_sha256) !== nullableText(lockInput.expectedPreviewManifestSha256)) return false;
  if (nullableText(afterStatus.lesson_manifest_sha256) !== nullableText(lockInput.expectedLessonVarianceManifestSha256)) return false;

  const afterSource = afterStatus.source_treatment_draft || {};
  if (nullableText(afterSource.source_manifest_sha256) !== nullableText(lockInput.expectedLessonVarianceManifestSha256)) return false;
  if (afterSource.source_count !== lockInput.expectedSourceCount) return false;
  if (nullableText(afterSource.updated_at) !== nullableText(lockInput.expectedSourceTreatmentDraftUpdatedAt)) return false;
  const afterAdjustment = afterStatus.adjustment_draft || {};
  if (nullableText(afterAdjustment.updated_at) !== nullableText(lockInput.expectedAdjustmentDraftUpdatedAt)) return false;

  const live = afterStatus.authoritative_preview || {};
  const pairs = [
    [live.unused_planned_credit_jpy, lockInput.expectedUnusedPlannedCreditJpy],
    [live.overage_charge_jpy, lockInput.expectedOverageChargeJpy],
    [live.net_lesson_variance_jpy, lockInput.expectedNetLessonVarianceJpy],
    [live.net_lesson_variance_cny, lockInput.expectedNetLessonVarianceCny],
    [afterStatus.authoritative_system_difference_cny, lockInput.expectedSystemDifferenceCny],
    [live.projected_final_carryover_cny, lockInput.expectedFinalCarryoverCny],
  ];
  return pairs.every(([liveValue, sent]) => {
    if (liveValue === null || liveValue === undefined) return false;
    try {
      return canonicalDecimal(liveValue) === canonicalDecimal(sent);
    } catch {
      return false;
    }
  });
}

// 这三个 code 表示「请求是否落库未知」：invokeSettlementEdge 用 Promise.race
// 实现超时，没有 AbortController，超时只是停止等待，底层调用仍在继续。
// 因此它们绝不能进入 retriable——「此刻未变」证明不了「将来不变」。
const LOCK_OUTCOME_UNKNOWN_CODES = new Set([
  "SETTLEMENT_EDGE_RESULT_UNCERTAIN",
  "SETTLEMENT_EDGE_RESPONSE_INVALID",
  "SETTLEMENT_EDGE_REQUEST_FAILED",
]);

export const LOCK_FAILURE_STATES = Object.freeze({
  CONFIRMED: "confirmed",
  BLOCKED: "blocked",
  STALE: "stale",
  BUSY: "busy",
  RETRIABLE: "retriable",
  CONFLICT: "conflict",
  UNKNOWN: "unknown",
});

/**
 * 锁定失败分流。先按错误来源与 action 判定，只有结果确实不明确时才比对状态。
 *
 * 关键区分：「请求已明确终止」与「请求结果未知」。前者可依据 status 判断能否
 * 重试；后者一律不得重试，因为底层请求可能稍后落库。
 */
// Edge 契约中已知的 action。未知 action 一律按结果未知处理，不得 fail-open——
// 新增一个 action 就悄悄放行重试，是最容易被忽略的回归面。
const KNOWN_LOCK_ACTIONS = new Set([
  "stop", "reauthenticate", "repreview", "retry_later", "refresh_status",
]);

// 允许重放同一 payload 的 code 白名单。
//
// 当前为空，且这是有意的：Codex 逐条走查了 9 个 refresh_status code
// （NOT_INCOMPLETE / ORDINARY_ALREADY_LOCKED / SOURCE_DRAFT_STALE /
//  ADJUSTMENT_DRAFT_STALE / LOCK_CONFLICT / ONLINE_SAVE_STRUCTURALLY_BLOCKED /
//  POSTED_ADJUSTMENT_IMMUTABLE / SOURCE_TREATMENT_DRAFT_REQUIRED /
//  SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK），没有任何一个能证明「原 payload
//  可以安全重放」——它们表达的都是「当前状态与本次请求不符」。
//
// 初版对 refresh_status 无差别放行为 retriable，直接违反设计稿「不能默认未变
// 即可重试」，而矩阵测试还把 LOCK_CONFLICT → retriable 写成了正确答案。
// 在服务器明确给出「同 payload 重试」契约之前，本白名单保持为空。
const LOCK_REPLAY_SAFE_CODES = new Set([]);

export function classifyLockFailure({
  error, beforeStatus, afterStatus, statusReadFailed,
  previewResult, membershipRole, lockInput,
}) {
  const S = LOCK_FAILURE_STATES;
  const code = String(error?.code || "");
  const action = String(error?.action || "");
  const outcomeUnknown = LOCK_OUTCOME_UNKNOWN_CODES.has(code)
    || !action
    || !KNOWN_LOCK_ACTIONS.has(action);

  if (!outcomeUnknown) {
    if (action === "stop" || action === "reauthenticate") return S.BLOCKED;
    if (action === "repreview") return S.STALE;
    if (action === "retry_later") return S.BUSY;
    // refresh_status 落到第二层
  }

  if (statusReadFailed) return S.UNKNOWN;
  if (statusConfirmsDraftLock(afterStatus, previewResult)) return S.CONFIRMED;

  const unchanged = lockStatusStrictlyUnchanged({
    beforeStatus, afterStatus, previewResult, membershipRole, lockInput,
  });
  if (!unchanged) return S.CONFLICT;

  // 结果未知时，即使严格未变也不得重试——超时不取消底层请求
  if (outcomeUnknown) return S.UNKNOWN;
  // 请求已明确终止且状态未变，但服务器仍拒绝了它：除非该 code 明确属于可重放，
  // 否则重放同一 payload 只会以同样方式再次失败。
  return LOCK_REPLAY_SAFE_CODES.has(code) ? S.RETRIABLE : S.CONFLICT;
}
