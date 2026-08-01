const YEAR_MONTH_PATTERN = /^(\d{4})-(0[1-9]|1[0-2])$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function listStudentSettlementMonthWeeks(yearMonth) {
  const match = YEAR_MONTH_PATTERN.exec(String(yearMonth || ""));
  if (!match) {
    return [];
  }

  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1;
  const firstDay = new Date(Date.UTC(year, monthIndex, 1));
  const firstMondayOffset = (8 - firstDay.getUTCDay()) % 7;
  const monday = new Date(firstDay);
  monday.setUTCDate(monday.getUTCDate() + firstMondayOffset);

  const weeks = [];
  while (monday.getUTCFullYear() === year && monday.getUTCMonth() === monthIndex) {
    const sunday = new Date(monday);
    sunday.setUTCDate(sunday.getUTCDate() + 6);
    weeks.push({
      weekStart: formatUtcDate(monday),
      weekEnd: formatUtcDate(sunday),
    });
    monday.setUTCDate(monday.getUTCDate() + 7);
  }
  return weeks;
}

export function normalizeStudentSettlementWeekStart(yearMonth, value) {
  const weekStart = String(value || "");
  if (!DATE_PATTERN.test(weekStart)) {
    return "";
  }
  return listStudentSettlementMonthWeeks(yearMonth).some((week) => (
    week.weekStart === weekStart
  )) ? weekStart : "";
}

export function validateAuthoritativeLessonRecords(records, { yearMonth, weekStart = "" } = {}) {
  if (!Array.isArray(records)) {
    throw new Error("课时读取结果格式无效，请重新加载。");
  }
  if (!YEAR_MONTH_PATTERN.test(String(yearMonth || ""))) {
    throw new Error("收费归属月无效，请重新选择。");
  }

  const normalizedWeekStart = normalizeStudentSettlementWeekStart(yearMonth, weekStart);
  if (weekStart && !normalizedWeekStart) {
    throw new Error("所选自然周不属于当前学生结算月，请重新选择。");
  }
  validateUniqueLessonRecordIds(records, "课时读取结果");

  for (const record of records) {
    const id = String(record?.id || "");
    const lessonType = String(record?.lesson_type || "");
    const authoritativeMonth = lessonType === "planned"
      ? String(record?.billing_month || "")
      : lessonType === "actual"
        ? String(record?.authoritative_student_month || "")
        : String(record?.authoritative_student_month || "");
    if (authoritativeMonth !== yearMonth) {
      throw new Error(`课时 ${id} 的权威收费/结算月与当前筛选不一致，已拒绝显示。`);
    }
    if (normalizedWeekStart && lessonType === "planned"
        && String(record?.billing_week_start_date || "") !== normalizedWeekStart) {
      throw new Error(`课时 ${id} 不属于当前收费自然周，已拒绝显示。`);
    }
  }

  return [...records];
}

export function validateUniqueLessonRecordIds(records, label = "课时读取结果") {
  if (!Array.isArray(records)) {
    throw new Error(`${label}格式无效，请重新加载。`);
  }
  const ids = new Set();
  for (const record of records) {
    const id = String(record?.id || "");
    if (!id) {
      throw new Error(`${label}缺少UUID，已拒绝显示。`);
    }
    if (ids.has(id)) {
      throw new Error(`${label}包含重复UUID：${id}，已拒绝显示。`);
    }
    ids.add(id);
  }
  return [...records];
}

export function createLatestRequestGate() {
  let currentToken = 0;
  return {
    begin() {
      currentToken += 1;
      return currentToken;
    },
    isCurrent(token) {
      return token === currentToken;
    },
  };
}

function formatUtcDate(date) {
  return [
    String(date.getUTCFullYear()).padStart(4, "0"),
    String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0"),
  ].join("-");
}
