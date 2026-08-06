const PREVIEW_STATES = new Set(["validation_preview_only", "enabled"]);
const GENERATE_STATES = new Set(["blocked", "enabled"]);

export function validateTuitionValidationPreviewDetails(response, expected = {}) {
  if (!response || !PREVIEW_STATES.has(response.feature_state)) {
    throw new Error("学费预览状态无效，已拒绝显示。");
  }
  if (!GENERATE_STATES.has(response.generate_feature_state)) {
    throw new Error("学费生成状态无效，已拒绝显示。");
  }
  if (response.student_id !== expected.studentId) {
    throw new Error("学费预览学生与当前选择不一致，请重新加载。");
  }
  if (response.business_entity_id !== expected.businessEntityId) {
    throw new Error("学费预览内部范围与当前学生不一致，请重新加载。");
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
  if (!/^[0-9a-f]{64}$/.test(String(response.generation_manifest_sha256 || ""))) {
    throw new Error("学费预览缺少有效的原子生成manifest，已拒绝显示。");
  }

  const ids = new Set();
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
    const baseLessonFee = finiteNumber(candidate.base_lesson_fee_jpy, "基础课时费", plannedLessonId);
    const airconRate = finiteNumber(candidate.aircon_rate_jpy_per_hour, "空调费率", plannedLessonId);
    const airconFee = finiteNumber(candidate.aircon_fee_jpy, "空调费", plannedLessonId);
    const lessonTotalFee = finiteNumber(candidate.course_total_jpy, "课程总价", plannedLessonId);
    if (lessonCount <= 0
        || durationHours <= 0
        || baseLessonFee <= 0
        || !Number.isInteger(airconRate)
        || airconRate < 0
        || airconFee < 0
        || lessonTotalFee <= 0) {
      throw new Error(`学费预览candidate数值无效：${plannedLessonId}`);
    }
    if (!/^[0-9a-f]{32}$/.test(String(candidate.complete_row_hash || ""))
        || !/^[0-9a-f]{64}$/.test(String(candidate.candidate_line_hash || ""))) {
      throw new Error(`学费预览candidate冻结证据无效：${plannedLessonId}`);
    }
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
  for (const [value, label] of [
    [response.total_lesson_count, "总课次数"],
    [response.total_duration_hours, "总时长"],
    [response.total_base_lesson_fee_jpy, "基础课时费"],
    [response.total_aircon_fee_jpy, "空调费"],
    [response.total_fee_jpy, "课程总额"],
    [response.previous_carryover_cny, "上月结转"],
    [response.billing_amount_cny, "最终通知金额"],
  ]) {
    if (!Number.isFinite(Number(value))) {
      throw new Error(`学费预览${label}无效，已拒绝显示。`);
    }
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

export function createTuitionAtomicGenerateState() {
  let preview = null;
  let submitting = false;

  return {
    storePreview(nextPreview) {
      preview = nextPreview;
      return preview;
    },
    clearPreview() {
      preview = null;
    },
    getPreview() {
      return preview;
    },
    beginSubmission() {
      if (submitting || !preview) {
        return false;
      }
      submitting = true;
      return true;
    },
    endSubmission({ consumePreview = false } = {}) {
      submitting = false;
      if (consumePreview) {
        preview = null;
      }
    },
    isSubmitting() {
      return submitting;
    },
  };
}

export function buildAtomicTuitionGeneratePayload(preview, note = "") {
  if (!preview || !/^[0-9a-f]{64}$/.test(String(preview.generation_manifest_sha256 || ""))) {
    throw new Error("缺少有效的学费生成manifest，请重新预览。");
  }

  return {
    studentId: preview.student_id,
    billingMonth: preview.billing_month,
    billingExchangeRate: preview.billing_exchange_rate,
    expectedGenerationManifestSha256: preview.generation_manifest_sha256,
    note: String(note || "").trim() || null,
  };
}

export function isAtomicTuitionGenerateEnabled(preview) {
  return preview?.feature_state === "enabled"
    && preview?.generate_feature_state === "enabled";
}

export function mapAtomicTuitionGenerateError(error) {
  const rawMessage = String(error?.message || error || "");
  const mappings = [
    ["TUITION_GENERATION_BLOCKED", "学费应收生成功能维护中，当前只能预览。", false],
    ["R2_F_B_STALE_GENERATION_MANIFEST", "课程或收费数据已变化，请重新生成预览。", true],
    ["R2_F_C_TUITION_SOURCE_BUSY", "课时或月结数据正在更新，请稍后重新预览并生成。", true],
    ["R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE", "该学生月份已存在不一致的账单记录，请停止操作并检查。", false],
    ["R2_F_B_ALREADY_BILLED", "该学生本月学费账单已生成，不能重复生成。", false],
    ["R2_F_B_CANDIDATES_EMPTY", "该学生本月没有可生成学费账单的课程。", false],
  ];
  const matched = mappings.find(([code]) => rawMessage.includes(code));
  if (matched) {
    return { code: matched[0], message: matched[1], clearPreview: matched[2] };
  }
  return {
    code: "UNKNOWN",
    message: "学费应收生成失败，未写入成功状态。请检查网络或系统状态后重新预览。",
    clearPreview: false,
  };
}

export function mapTuitionValidationPreviewError(error) {
  const rawMessage = String(error?.message || error || "");
  const mappings = [
    ["R2_F_B_STUDENT_REQUIRED", "请选择学生后再生成学费预览。"],
    ["R2_F_B_STUDENT_NOT_FOUND", "当前学生资料不可用，请刷新页面后重试。"],
    ["R2_F_B_STUDENT_INACTIVE", "当前学生不是有效在读状态，不能生成学费预览。"],
    ["R2_F_B_BUSINESS_ENTITY_REQUIRED", "当前学生缺少内部范围，不能生成学费预览。"],
    ["R2_F_B_BILLING_MONTH_INVALID", "学费月份无效，请重新选择。"],
    ["R2_F_B_EXCHANGE_RATE_INVALID", "通知汇率必须大于零。"],
    ["R2_F_B_TARGET_SETTLEMENT_LOCKED", "本月学生结算已经锁定，不能重新生成学费预览。"],
    ["R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS", "上月锁定结算数据不唯一，请停止操作并联系管理员核对。"],
    ["R2_F_B_ALREADY_BILLED", "该学生本月学费账单已生成，不能重复生成。"],
    ["R2_F_B_CANDIDATES_EMPTY", "该学生本月没有可生成学费账单的课程。"],
    ["R2_F_B_DUPLICATE_CANDIDATE_UUID", "学费候选课时存在重复，请停止操作并联系管理员核对。"],
    ["R2_F_B_CANDIDATE_CONTRACT_MISMATCH", "学费候选课时证据不一致，请停止操作并联系管理员核对。"],
    ["R2_F_B_BILLING_AMOUNT_INVALID", "学费通知金额无效，请停止操作并联系管理员核对。"],
  ];
  const matched = mappings.find(([code]) => rawMessage.includes(code));
  return matched
    ? { code: matched[0], message: matched[1] }
    : { code: "UNKNOWN", message: "学费预览生成失败，请刷新页面后重试；如仍失败请联系管理员核对。" };
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
