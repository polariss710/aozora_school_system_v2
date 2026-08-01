const OVERAGE_FIELDS = [
  "student_duration_overage_minutes",
  "student_duration_overage_fee_jpy",
  "student_duration_overage_policy_version",
  "student_duration_overage_source",
  "student_duration_overage_decided_at",
];

const SETTLEMENT_OVERAGE_FIELDS = [
  "duration_overage_minutes",
  "duration_overage_fee_jpy",
  "duration_overage_fee_cny",
  "duration_overage_actual_count",
  "duration_overage_policy_version",
  "duration_overage_source",
];

export const PARTIAL_ACTUAL_REQUIRED_MESSAGE =
  "实际时长小于计划时长；普通 actual 不能提交，请勾选“部分完成，剩余转待补”并使用 partial 流程。";

export function validateActualDurationForFlow({
  actualDurationHours,
  plannedDurationHours,
  isPartial = false,
} = {}) {
  const actual = Number(actualDurationHours);
  const planned = Number(plannedDurationHours);

  if (!Number.isFinite(actual) || actual <= 0) {
    return {
      valid: false,
      message: "实际时长必须是大于 0 的数字。",
    };
  }

  if (!Number.isFinite(planned) || planned <= 0) {
    return {
      valid: false,
      message: "来源 planned 缺少合法计划时长，请刷新后重试。",
    };
  }

  if (isPartial) {
    if (actual >= planned) {
      return {
        valid: false,
        message: "partial 实际时长必须大于 0 且小于计划时长；等于或超过计划时长请取消 partial。",
      };
    }
    return { valid: true, message: "" };
  }

  if (actual < planned) {
    return {
      valid: false,
      message: PARTIAL_ACTUAL_REQUIRED_MESSAGE,
    };
  }

  return { valid: true, message: "" };
}

export function hasFrozenActualOverage(record) {
  return Boolean(record && OVERAGE_FIELDS.every((field) => (
    record[field] !== null && record[field] !== undefined
  )));
}

export function hasFrozenSettlementOverage(record) {
  return Boolean(record && SETTLEMENT_OVERAGE_FIELDS.every((field) => (
    record[field] !== null && record[field] !== undefined
  )));
}

export function nextNaturalYearMonth(yearMonth) {
  const match = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(String(yearMonth || ""));
  if (!match) {
    return "";
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const nextYear = month === 12 ? year + 1 : year;
  const nextMonth = month === 12 ? 1 : month + 1;
  return `${String(nextYear).padStart(4, "0")}-${String(nextMonth).padStart(2, "0")}`;
}

export function buildActualOverageDisplay(actualLesson, plannedLesson) {
  if (!hasFrozenActualOverage(actualLesson)) {
    return null;
  }

  const sourceStudentMonth = String(actualLesson.authoritative_student_month || "");
  return {
    plannedDurationHours: plannedLesson?.duration_hours ?? null,
    actualDurationHours: actualLesson.duration_hours,
    overageMinutes: actualLesson.student_duration_overage_minutes,
    frozenFeeJpy: actualLesson.student_duration_overage_fee_jpy,
    policyVersion: actualLesson.student_duration_overage_policy_version,
    source: actualLesson.student_duration_overage_source,
    decidedAt: actualLesson.student_duration_overage_decided_at,
    sourceStudentMonth,
    nextStudentSettlementMonth: nextNaturalYearMonth(sourceStudentMonth),
  };
}

export function buildLessonMonthSemantics(record) {
  const isPlanned = record?.lesson_type === "planned";
  return {
    studentSettlementMonth: String(
      isPlanned
        ? (record?.billing_month || "")
        : (record?.authoritative_student_month || "")
    ),
    teacherWageMonth: String(record?.teacher_settlement_month || ""),
    occurrenceDate: String(record?.lesson_date || ""),
  };
}
