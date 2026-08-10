const LESSON_TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

export function isLessonTimeValue(value) {
  return LESSON_TIME_PATTERN.test(String(value ?? "").trim());
}

export function validateLessonTimeGrid(startTime, endTime) {
  const startText = String(startTime ?? "").trim();
  const endText = String(endTime ?? "").trim();

  if (!startText || !endText) {
    return { status: "incomplete" };
  }

  const startMatch = startText.match(LESSON_TIME_PATTERN);
  const endMatch = endText.match(LESSON_TIME_PATTERN);
  if (!startMatch || !endMatch) {
    return {
      status: "error",
      code: "LESSON_TIME_FORMAT_INVALID",
      message: "请填写正确的开始时间和结束时间。",
    };
  }

  const startMinute = Number(startMatch[2]);
  const endMinute = Number(endMatch[2]);
  if (startMinute % 15 !== 0 || endMinute % 15 !== 0) {
    return {
      status: "error",
      code: "LESSON_TIME_GRID_INVALID",
      message: `无法提交：开始和结束时间必须使用15分钟刻度（00、15、30、45）。当前输入${startText}–${endText}不符合规则。`,
    };
  }

  const startMinutes = Number(startMatch[1]) * 60 + startMinute;
  const endMinutes = Number(endMatch[1]) * 60 + endMinute;
  const diffMinutes = endMinutes - startMinutes;
  if (diffMinutes <= 0) {
    return {
      status: "error",
      code: "LESSON_TIME_RANGE_INVALID",
      message: "结束时间必须晚于开始时间。",
    };
  }
  if (diffMinutes % 15 !== 0) {
    return {
      status: "error",
      code: "LESSON_TIME_DURATION_GRID_INVALID",
      message: "开始/结束时间差必须是 15 分钟的整数倍；不会自动四舍五入。",
    };
  }

  return { status: "valid", diffMinutes };
}
