const STABLE_BUSINESS_CODE_PATTERN = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}\b/;
const SQLSTATE_PATTERN = /^[0-9A-Z]{5}$/;
const NETWORK_ERROR_PATTERN = /(?:failed to fetch|networkerror|network request|load failed|connection.*(?:failed|closed))/i;
const SAFE_CHINESE_PATTERN = /[\u3400-\u9fff]/;
const TECHNICAL_TEXT_PATTERN = /(?:SQLSTATE|PostgREST|duplicate key|violates|relation\s+"|column\s+"|function\s+[^\s]+\()/i;

const SETTLEMENT_BUSINESS_ERROR_MESSAGES = new Map([
  ["SETTLEMENT_EXPLICIT_EXCHANGE_RATE_REQUIRED", () => "财务净额模式需要填写有效的结算汇率、汇率来源和汇率生效日。"],
  ["SETTLEMENT_EXCHANGE_RATE_EFFECTIVE_DATE_MISMATCH", ({ yearMonth }) => {
    const range = settlementMonthDateRange(yearMonth);
    return range
      ? `汇率生效日必须位于结算月份${yearMonth}内，请选择${range.min}至${range.max}之间的日期。`
      : "汇率生效日必须位于当前结算月份内。";
  }],
  ["SETTLEMENT_SOURCE_TREATMENT_MODE_INVALID", () => "课时差额处理方式无效，请重新选择。"],
  ["SETTLEMENT_SOURCE_TREATMENT_SCOPE_INVALID", () => "学生或结算月份范围无效，请刷新数据后重试。"],
  ["SETTLEMENT_SOURCE_TREATMENT_REASON_REQUIRED", () => "请填写课时差额处理理由。"],
  ["SETTLEMENT_SOURCE_TREATMENT_LOCKED_READ_ONLY", () => "该月结算已锁定，不能修改课时差额处理设置。"],
  ["SETTLEMENT_ADJUSTMENT_DIALOG_SCOPE_INVALID", () => "月结预览范围无效，请刷新数据后重试。"],
  ["SETTLEMENT_ADJUSTMENT_DIALOG_BUSINESS_ENTITY_MISMATCH", () => "学生内部范围与当前月结不一致，请刷新数据后重试。"],
  ["SETTLEMENT_LESSON_SOURCE_UNRESOLVED", () => "结算月份内仍有未明确处理结果的预定课时，请先核对课时状态。"],
  ["SETTLEMENT_LESSON_SOURCE_VALUE_INVALID", () => "结算课时来源的时长或金额事实无效，请先核对课时数据。"],
  ["SETTLEMENT_ADJUSTMENT_MODE_INVALID", () => "差额调整方式无效，请重新选择。"],
  ["SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE", () => "当前调整方式的金额必须由数据库计算，不能手动传入。"],
  ["SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED", () => "手动调整必须明确填写调整金额。"],
  ["SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_INVALID", () => "手动调整金额无效，请填写有效数字。"],
  ["SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH", () => "差额调整预览与数据库权威结果不一致，请刷新数据后重新预览。"],
  ["SETTLEMENT_ADJUSTMENT_SCOPE_INVALID", () => "差额调整的学生或结算月份范围无效，请刷新数据后重试。"],
  ["SETTLEMENT_ADJUSTMENT_REASON_REQUIRED", () => "请填写差额调整理由。"],
  ["SETTLEMENT_ADJUSTMENT_LOCKED_READ_ONLY", () => "该月结算已锁定，不能修改差额调整。"],
  ["SETTLEMENT_ADJUSTMENT_SOURCE_FACTS_EMPTY", () => "当前月份没有可用于差额调整的数据库权威来源事实。"],
  ["SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE", () => "已固化的月结调整不可修改。"],
  ["SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED", () => "锁定前必须先保存课时差额处理设置。"],
  ["SETTLEMENT_SOURCE_TREATMENT_DRAFT_REQUIRED_FOR_RELOCK", () => "重新锁定前必须先保存课时差额处理设置。"],
  ["SETTLEMENT_LESSON_VARIANCE_SOURCE_CHANGED_AFTER_DRAFT", () => "课时来源在预览后发生变化，请刷新数据并重新预览。"],
  ["SETTLEMENT_LESSON_VARIANCE_CLAIM_COUNT_MISMATCH", () => "课时差额来源数量已变化，请刷新数据并重新预览。"],
  ["SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED", () => "待补课时来源已被其他有效月结消费，不能重复使用。"],
  ["SETTLEMENT_LESSON_VARIANCE_SOURCE_IMMUTABLE", () => "该课时差额来源已经固化，不能再次修改或消费。"],
  ["TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE", () => "该月结算已被当前有效学费账单作为前期结转引用，不能修改。"],
  ["TUITION_CONSUMED_SETTLEMENT_IMMUTABLE", () => "该月结算曾被历史学费账单消费，已永久冻结，不能重开。"],
  ["R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE", () => "该历史锁定快照不可重新计算或修改。"],
]);

const SETTLEMENT_SQLSTATE_MESSAGES = new Map([
  ["42501", "当前页面没有执行该财务写操作的受信权限，请使用本机管理工具。"],
  ["55P03", "另一项月结或学费操作正在处理同一业务范围，请刷新数据后重试。"],
]);

export function formatSettlementBusinessError(error, context = {}) {
  const rawMessage = String(error?.message || error || "").trim();
  const businessCode = extractStableBusinessErrorCode(error);
  const messageFactory = businessCode
    ? SETTLEMENT_BUSINESS_ERROR_MESSAGES.get(businessCode)
    : null;
  const transportCode = safeTransportCode(error?.code);

  if (messageFactory) {
    return {
      message: messageFactory(context),
      code: businessCode,
      transportCode,
    };
  }

  if (transportCode && SETTLEMENT_SQLSTATE_MESSAGES.has(transportCode)) {
    return {
      message: SETTLEMENT_SQLSTATE_MESSAGES.get(transportCode),
      code: transportCode,
      transportCode,
    };
  }

  if (!businessCode && NETWORK_ERROR_PATTERN.test(rawMessage)) {
    return {
      message: "网络连接异常，请检查网络后重试。",
      code: transportCode,
      transportCode,
    };
  }

  if (!businessCode && isSafeChineseMessage(rawMessage)) {
    return {
      message: rawMessage,
      code: transportCode,
      transportCode,
    };
  }

  return {
    message: "操作未完成，请检查输入或刷新数据后重试。",
    code: businessCode || transportCode,
    transportCode,
  };
}

export function extractStableBusinessErrorCode(error) {
  const candidates = [error?.message, error?.details, error?.hint, error]
    .filter((value) => typeof value === "string");
  for (const candidate of candidates) {
    const matches = candidate.match(STABLE_BUSINESS_CODE_PATTERN) || [];
    if (matches.length) {
      return matches[0];
    }
  }
  return "";
}

export function settlementMonthDateRange(yearMonth) {
  const value = String(yearMonth || "");
  const match = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return {
    min: `${value}-01`,
    max: `${value}-${String(lastDay).padStart(2, "0")}`,
  };
}

function safeTransportCode(code) {
  const value = String(code || "").trim().toUpperCase();
  return SQLSTATE_PATTERN.test(value) && value !== "P0001" ? value : "";
}

function isSafeChineseMessage(message) {
  return Boolean(
    message
    && SAFE_CHINESE_PATTERN.test(message)
    && !STABLE_BUSINESS_CODE_PATTERN.test(message)
    && !TECHNICAL_TEXT_PATTERN.test(message)
  );
}

export const SETTLEMENT_BUSINESS_ERROR_CODES = Object.freeze(
  [...SETTLEMENT_BUSINESS_ERROR_MESSAGES.keys()]
);
