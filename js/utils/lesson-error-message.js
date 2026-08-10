const LESSON_ERROR_CODE_MESSAGES = new Map([
  ["LESSON_TIME_GRID_INVALID", "无法保存课时：开始或结束时间不符合15分钟刻度规则，请使用00、15、30或45分钟。重复提交不会解决此问题。"],
  ["FUTURE_ACTUAL_COMPLETION_FORBIDDEN", "实际完成日期不能晚于东京当前业务日期。"],
  ["R2_E_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN", "已收费课时不允许执行该状态变更。"],
  ["R2_F_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN", "已收费课时不允许执行该状态变更。"],
  ["PLANNED_DATE_OUTSIDE_BILLING_WEEK", "预计上课日期必须位于原收费自然周内。"],
  ["PLANNED_BILLING_ATTRIBUTION_IMMUTABLE", "普通编辑不能修改课时的收费自然周或收费月份。"],
  ["PLANNED_BILLING_ATTRIBUTION_REQUIRED", "该历史课时缺少收费归属，请先完成数据整理。"],
]);

const SYSTEM_IDENTIFIER_PATTERN = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}\b/;
const TECHNICAL_TEXT_PATTERN = /(?:SQLSTATE|PostgREST|duplicate key|violates|relation\s+"|column\s+"|function\s+[^\s]+\()/i;
const NETWORK_TEXT_PATTERN = /(?:failed to fetch|networkerror|network request|load failed|connection.*(?:failed|closed))/i;

export function lessonUserErrorMessage(error, fallback = "课时操作失败，请稍后重试。") {
  const rawMessage = String(error?.message || error || "").trim();
  const stableErrorText = [rawMessage, error?.details, error?.hint, error?.code]
    .filter((value) => value !== null && value !== undefined && String(value).trim())
    .map((value) => String(value).trim())
    .join(" ");
  for (const [code, message] of LESSON_ERROR_CODE_MESSAGES) {
    if (stableErrorText.includes(code)) {
      return message;
    }
  }

  if (NETWORK_TEXT_PATTERN.test(rawMessage)) {
    return "网络连接异常，请检查网络后重试。";
  }

  const cleanedMessage = rawMessage
    .replace(/[（(]\s*[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}\s*[）)]/g, "")
    .trim();
  if (
    cleanedMessage
    && /[\u3400-\u9fff]/.test(cleanedMessage)
    && !SYSTEM_IDENTIFIER_PATTERN.test(cleanedMessage)
    && !TECHNICAL_TEXT_PATTERN.test(cleanedMessage)
  ) {
    return cleanedMessage;
  }

  return fallback;
}
