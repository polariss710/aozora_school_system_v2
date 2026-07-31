const LESSON_ERROR_CODE_MESSAGES = new Map([
  ["FUTURE_ACTUAL_COMPLETION_FORBIDDEN", "实际完成日期不能晚于东京当前业务日期。"],
  ["R2_E_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN", "已收费课时不允许执行该状态变更。"],
  ["R2_F_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN", "已收费课时不允许执行该状态变更。"],
]);

const SYSTEM_IDENTIFIER_PATTERN = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}\b/;
const TECHNICAL_TEXT_PATTERN = /(?:SQLSTATE|PostgREST|duplicate key|violates|relation\s+"|column\s+"|function\s+[^\s]+\()/i;
const NETWORK_TEXT_PATTERN = /(?:failed to fetch|networkerror|network request|load failed|connection.*(?:failed|closed))/i;

export function lessonUserErrorMessage(error, fallback = "课时操作失败，请稍后重试。") {
  const rawMessage = String(error?.message || error || "").trim();
  for (const [code, message] of LESSON_ERROR_CODE_MESSAGES) {
    if (rawMessage.includes(code)) {
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
