const VALIDATION_PREVIEW_STATE = "validation_preview_only";

export function validateTuitionValidationPreviewDetails(response, expected = {}) {
  if (!response || response.feature_state !== VALIDATION_PREVIEW_STATE) {
    throw new Error("学费预览状态不是 validation_preview_only，已拒绝显示。");
  }
  if (response.student_id !== expected.studentId) {
    throw new Error("学费预览学生与当前选择不一致，请重新加载。");
  }
  if (response.business_entity_id !== expected.businessEntityId) {
    throw new Error("学费预览业务归属与当前学生不一致，请重新加载。");
  }
  if (response.billing_month !== expected.billingMonth) {
    throw new Error("学费预览月份与当前选择不一致，请重新加载。");
  }
  if (!numbersEqual(response.billing_exchange_rate, expected.billingExchangeRate)) {
    throw new Error("学费预览通知汇率与当前输入不一致，请重新加载。");
  }
  if (!Array.isArray(response.candidates)) {
    throw new Error("学费预览缺少服务端candidate明细，已拒绝显示。");
  }

  const ids = new Set();
  let totalLessonCount = 0;
  let totalDurationHours = 0;
  let totalFeeJpy = 0;
  let previousOrderKey = "";

  for (const candidate of response.candidates) {
    const plannedLessonId = String(candidate?.planned_lesson_id || "");
    if (!plannedLessonId) {
      throw new Error("学费预览candidate缺少planned lesson UUID。");
    }
    if (ids.has(plannedLessonId)) {
      throw new Error(`学费预览包含重复planned lesson UUID：${plannedLessonId}`);
    }
    ids.add(plannedLessonId);

    if (candidate.student_id !== expected.studentId
        || candidate.business_entity_id !== expected.businessEntityId
        || candidate.billing_month !== expected.billingMonth) {
      throw new Error(`学费预览candidate归属不一致：${plannedLessonId}`);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(candidate.billing_week_start_date || ""))) {
      throw new Error(`学费预览candidate缺少权威自然周：${plannedLessonId}`);
    }

    const lessonCount = finiteNumber(candidate.lesson_count, "课次数", plannedLessonId);
    const durationHours = finiteNumber(candidate.duration_hours, "时长", plannedLessonId);
    const lessonFee = finiteNumber(candidate.lesson_fee, "服务端费用", plannedLessonId);
    if (lessonCount <= 0 || durationHours <= 0 || lessonFee <= 0) {
      throw new Error(`学费预览candidate数值无效：${plannedLessonId}`);
    }
    totalLessonCount += lessonCount;
    totalDurationHours += durationHours;
    totalFeeJpy += lessonFee;

    const orderKey = [
      candidate.billing_week_start_date,
      candidate.lesson_date || "",
      plannedLessonId,
    ].join("|");
    if (previousOrderKey && orderKey < previousOrderKey) {
      throw new Error("学费预览candidate顺序不稳定，已拒绝显示。");
    }
    previousOrderKey = orderKey;
  }

  if (Number(response.candidate_count) !== response.candidates.length
      || Number(response.candidate_count) !== ids.size) {
    throw new Error("学费预览candidate数量或UUID唯一性不一致。");
  }
  if (Number(response.total_lesson_count) !== totalLessonCount
      || !numbersEqual(response.total_duration_hours, totalDurationHours)
      || !numbersEqual(response.total_fee_jpy, totalFeeJpy)
      || !numbersEqual(response.bill_amount_jpy, response.total_fee_jpy)) {
    throw new Error("学费预览汇总与candidate明细不一致，已拒绝显示。");
  }
  if (!/^[0-9a-f]{32}$/.test(String(response.candidate_uuid_md5 || ""))
      || !/^[0-9a-f]{64}$/.test(String(response.candidate_manifest_sha256 || ""))) {
    throw new Error("学费预览candidate集合hash无效。");
  }

  return {
    ...response,
    candidates: response.candidates.slice(),
  };
}

export function formatAuthoritativeBillingWeek(weekStart) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(weekStart || ""));
  if (!match) {
    return "-";
  }
  const start = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (Number.isNaN(start.getTime())) {
    return "-";
  }
  const end = new Date(start.getTime());
  end.setUTCDate(end.getUTCDate() + 6);
  return `${formatUtcDate(start)}～${formatUtcDate(end)}`;
}

export function createLatestTuitionPreviewRequestGate() {
  let sequence = 0;
  let activeRequestId = 0;
  return {
    begin(signature) {
      activeRequestId = ++sequence;
      return { requestId: activeRequestId, signature };
    },
    invalidate() {
      activeRequestId = ++sequence;
      return activeRequestId;
    },
    isCurrent(token, signature) {
      return Boolean(token
        && token.requestId === activeRequestId
        && token.signature === signature);
    },
  };
}

function finiteNumber(value, label, plannedLessonId) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    throw new Error(`学费预览candidate${label}无效：${plannedLessonId}`);
  }
  return number;
}

function numbersEqual(left, right) {
  const leftNumber = Number(left);
  const rightNumber = Number(right);
  return Number.isFinite(leftNumber)
    && Number.isFinite(rightNumber)
    && Math.abs(leftNumber - rightNumber) < 0.0000001;
}

function formatUtcDate(date) {
  return [
    date.getUTCFullYear(),
    String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0"),
  ].join("-");
}
