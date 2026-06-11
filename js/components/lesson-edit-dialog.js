import { updateLessonRecordGuarded } from "../api/lesson-api.js";
import { formatMonth, safeText } from "../utils/format.js";

const LESSON_TYPE_LABELS = {
  planned: "计划",
  actual: "实际",
};

const LESSON_STATUS_LABELS = {
  planned: "待上课",
  completed: "已完成",
  pending_makeup: "待补课",
  makeup_completed: "补课完成",
  cancelled: "已取消",
};

const EDIT_LESSON_FIELD_IDS = [
  "lessonDate",
  "status",
  "student",
  "teacher",
  "subject",
  "businessEntity",
  "startTime",
  "endTime",
  "durationHours",
  "unitPrice",
  "lessonFee",
  "lessonCount",
  "lessonContent",
  "isBillable",
];

export function cacheLessonEditDialogDom(root = document) {
  return {
    dialog: root.querySelector("#editLessonDialog"),
    summary: root.querySelector("#editLessonSummary"),
    warning: root.querySelector("#editLessonWarning"),
    error: root.querySelector("#editLessonError"),
    typeInput: root.querySelector("#editLessonTypeInput"),
    statusSelect: root.querySelector("#editLessonStatusSelect"),
    dateInput: root.querySelector("#editLessonDateInput"),
    billableSelect: root.querySelector("#editLessonBillableSelect"),
    studentSelect: root.querySelector("#editLessonStudentSelect"),
    teacherSelect: root.querySelector("#editLessonTeacherSelect"),
    subjectSelect: root.querySelector("#editLessonSubjectSelect"),
    businessEntitySelect: root.querySelector("#editLessonBusinessEntitySelect"),
    startTimeInput: root.querySelector("#editLessonStartTimeInput"),
    endTimeInput: root.querySelector("#editLessonEndTimeInput"),
    durationInput: root.querySelector("#editLessonDurationInput"),
    unitPriceInput: root.querySelector("#editLessonUnitPriceInput"),
    feeInput: root.querySelector("#editLessonFeeInput"),
    countInput: root.querySelector("#editLessonCountInput"),
    plannedIdInput: root.querySelector("#editLessonPlannedIdInput"),
    importSourceInput: root.querySelector("#editLessonImportSourceInput"),
    contentInput: root.querySelector("#editLessonContentInput"),
    noteInput: root.querySelector("#editLessonNoteInput"),
    submitButton: root.querySelector("#editLessonSubmitButton"),
    cancelButton: root.querySelector("#editLessonCancelButton"),
  };
}

export function createLessonEditDialogController(options) {
  const {
    dom,
    getLessonRecords,
    getMasterData,
    hasSupabaseConfig,
    showMessage,
    onSaved,
    setExternalBusy,
    getLinkedActualExists,
  } = options;
  let currentLesson = null;
  let isSubmitting = false;
  let isFeeManual = false;
  let initialFormSnapshot = null;
  let closeConfirmPending = false;
  let isInitialized = false;

  function init() {
    if (isInitialized) {
      return;
    }
    isInitialized = true;

    dom.cancelButton?.addEventListener("click", () => close());
    dom.submitButton?.addEventListener("click", handleSubmit);

    dom.dialog?.addEventListener("click", (event) => {
      if (event.target === dom.dialog) {
        blockDirectDismiss();
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && isDialogOpen()) {
        event.preventDefault();
        blockDirectDismiss();
      }
    });

    [
      ["lessonDate", dom.dateInput],
      ["status", dom.statusSelect],
      ["student", dom.studentSelect],
      ["teacher", dom.teacherSelect],
      ["subject", dom.subjectSelect],
      ["businessEntity", dom.businessEntitySelect],
      ["startTime", dom.startTimeInput],
      ["endTime", dom.endTimeInput],
      ["durationHours", dom.durationInput],
      ["unitPrice", dom.unitPriceInput],
      ["lessonFee", dom.feeInput],
      ["lessonCount", dom.countInput],
      ["lessonContent", dom.contentInput],
      ["isBillable", dom.billableSelect],
    ].forEach(([fieldId, element]) => {
      element?.addEventListener("input", () => {
        closeConfirmPending = false;
        clearFieldInvalid(fieldId);
        hideErrorIfClean();
      });
      element?.addEventListener("change", () => {
        closeConfirmPending = false;
        clearFieldInvalid(fieldId);
        hideErrorIfClean();
      });
    });

    dom.startTimeInput?.addEventListener("input", syncDurationFromTimeRange);
    dom.startTimeInput?.addEventListener("change", syncDurationFromTimeRange);
    dom.endTimeInput?.addEventListener("input", syncDurationFromTimeRange);
    dom.endTimeInput?.addEventListener("change", syncDurationFromTimeRange);
    dom.durationInput?.addEventListener("input", updateFeePreview);
    dom.unitPriceInput?.addEventListener("input", updateFeePreview);
    dom.feeInput?.addEventListener("input", () => {
      isFeeManual = dom.feeInput.value.trim() !== "";
    });
    dom.billableSelect?.addEventListener("change", handleBillableChange);
  }

  function open(lessonId) {
    if (!hasSupabaseConfig()) {
      showMessage("error", "当前 Supabase 配置不可用，不能编辑课时。");
      return;
    }

    const lesson = findLesson(lessonId);
    if (!lesson) {
      showMessage("error", "未找到要编辑的课时。");
      return;
    }

    const reason = blockReason(lesson);
    if (reason) {
      showMessage("error", reason);
      return;
    }

    currentLesson = lesson;
    renderOptions();
    resetForm(lesson);
    renderSummary(lesson);
    clearErrors();
    setSubmitting(false);
    dom.dialog.classList.remove("is-hidden");
    dom.dialog.setAttribute("aria-hidden", "false");
    dom.dateInput.focus();
  }

  function close(force = false) {
    if (isSubmitting && !force) {
      return;
    }

    if (!force && hasFormChanged()) {
      if (!closeConfirmPending) {
        closeConfirmPending = true;
        showError("表单已有修改。再次点击取消将放弃输入。");
        return;
      }
    }

    dom.dialog?.classList.add("is-hidden");
    dom.dialog?.setAttribute("aria-hidden", "true");
    currentLesson = null;
    initialFormSnapshot = null;
    closeConfirmPending = false;
  }

  function renderAction(record) {
    const reason = blockReason(record);
    if (reason) {
      return `<button class="button table-action-button" type="button" disabled title="${escapeAttribute(reason)}">不可编辑</button>`;
    }

    return `<button class="button table-action-button" type="button" data-edit-lesson-id="${escapeAttribute(record.id)}">编辑</button>`;
  }

  function blockReason(record) {
    if (!record || !record.id) {
      return "缺少课时记录。";
    }

    if (record.lesson_type === "planned") {
      if (record.voided_at) {
        return "该预定课时已作废，不能编辑。";
      }
      if (!["planned", "pending_makeup"].includes(record.status)) {
        return `当前 planned 状态不允许编辑：${lessonStatusLabel(record.status)}。`;
      }
      if (hasLinkedActual(record.id)) {
        return "该 planned 已有关联 actual，V1 不允许编辑。";
      }
      return "";
    }

    if (record.lesson_type === "actual") {
      if (!["completed", "cancelled", "makeup_completed"].includes(record.status)) {
        return `当前 actual 状态不允许编辑：${lessonStatusLabel(record.status)}。`;
      }
      return "";
    }

    return `不支持编辑该课时类型：${lessonTypeLabel(record.lesson_type)}。`;
  }

  function findLesson(lessonId) {
    return (getLessonRecords() || []).find((record) => record.id === lessonId) || null;
  }

  function hasLinkedActual(plannedLessonId) {
    if (typeof getLinkedActualExists === "function") {
      return getLinkedActualExists(plannedLessonId);
    }

    return (getLessonRecords() || []).some((record) => (
      record.lesson_type === "actual"
      && record.planned_lesson_id === plannedLessonId
    ));
  }

  function renderOptions() {
    const { students = [], teachers = [], subjects = [], businessEntities = [] } = getMasterData() || {};
    renderEntityOptionsWithPlaceholder(
      dom.studentSelect,
      students.filter((student) => !["inactive", "graduated"].includes(safeText(student.status))),
      studentName,
      "请选择学生"
    );
    renderEntityOptionsWithPlaceholder(
      dom.teacherSelect,
      teachers.filter((teacher) => !["inactive", "retired"].includes(safeText(teacher.status))),
      teacherName,
      "请选择老师"
    );
    renderEntityOptionsWithPlaceholder(
      dom.subjectSelect,
      subjects.filter((subject) => subject.is_active !== false),
      subjectName,
      "请选择科目"
    );
    renderEntityOptionsWithPlaceholder(
      dom.businessEntitySelect,
      businessEntities.filter((entity) => entity.is_active !== false),
      businessEntityName,
      "请选择业务归属"
    );
  }

  function resetForm(lesson) {
    dom.typeInput.value = lessonTypeLabel(lesson.lesson_type);
    dom.statusSelect.value = safeText(lesson.status);
    dom.dateInput.value = safeText(lesson.lesson_date);
    dom.billableSelect.value = lesson.is_billable === false ? "false" : "true";
    dom.studentSelect.value = safeText(lesson.student_id);
    dom.teacherSelect.value = safeText(lesson.teacher_id);
    dom.subjectSelect.value = safeText(lesson.subject_id);
    dom.businessEntitySelect.value = safeText(lesson.business_entity_id);
    dom.startTimeInput.value = formatInputTime(lesson.start_time);
    dom.endTimeInput.value = formatInputTime(lesson.end_time);
    dom.durationInput.value = displayInputNumber(lesson.duration_hours);
    dom.unitPriceInput.value = displayInputNumber(lesson.unit_price || 0);
    dom.feeInput.value = displayInputNumber(lesson.lesson_fee);
    dom.countInput.value = lesson.lesson_count ? String(lesson.lesson_count) : "";
    dom.plannedIdInput.value = safeText(lesson.planned_lesson_id);
    dom.importSourceInput.value = displayImportSource(lesson);
    dom.contentInput.value = safeText(lesson.lesson_content);
    dom.noteInput.value = safeText(lesson.note);
    isFeeManual = false;
    closeConfirmPending = false;
    syncFieldModes();
    initialFormSnapshot = readFormSnapshot();
  }

  function syncFieldModes() {
    const lesson = currentLesson;
    if (!lesson) {
      return;
    }

    const isPlanned = lesson.lesson_type === "planned";
    const isActual = lesson.lesson_type === "actual";
    const isLinkedActual = isActual && Boolean(lesson.planned_lesson_id);
    const isCancelledActual = isActual && lesson.status === "cancelled";
    const actualStatusReason = "actual 状态由生成链路决定，V1 编辑保持只读；如需改成取消、已上课或补课完成，需要走独立 guarded 流程。";
    const linkedMasterReason = "该 actual 已关联 planned，学生、老师、科目、业务归属必须保持与来源 planned 一致，V1 不允许在编辑中修改。";
    const plannedReadonlyReason = "课时类型、planned_lesson_id 和导入信息只读；planned 只允许调整日期、对象、时间、金额、内容、备注和 planned/pending_makeup 状态。";
    const importReadonlyReason = "导入元数据只作为来源审计信息保留，编辑课时时不可修改。";

    dom.statusSelect.disabled = isActual;
    dom.statusSelect.title = isActual ? actualStatusReason : "";
    [...dom.statusSelect.options].forEach((option) => {
      option.disabled = isPlanned
        ? !["planned", "pending_makeup"].includes(option.value)
        : option.value !== lesson.status;
    });

    [dom.studentSelect, dom.teacherSelect, dom.subjectSelect, dom.businessEntitySelect].forEach((element) => {
      element.disabled = isLinkedActual;
      element.title = isLinkedActual ? linkedMasterReason : "";
    });

    dom.billableSelect.disabled = isPlanned || isCancelledActual;
    dom.billableSelect.title = isPlanned
      ? "planned 课时固定按计费课时处理；是否实际收费由 actual 和后续结算口径决定。"
      : "";
    dom.feeInput.readOnly = isCancelledActual || (isActual && dom.billableSelect.value === "false");
    dom.typeInput.title = "课时类型由创建链路决定，编辑时不可修改。";
    dom.plannedIdInput.title = "关联预定ID由 actual 生成链路决定，编辑时不可修改。";
    dom.importSourceInput.title = importReadonlyReason;
    if (isPlanned) {
      dom.billableSelect.value = "true";
    }
    if (isCancelledActual) {
      dom.billableSelect.value = "false";
      dom.feeInput.value = "0";
    }
    if (isActual && dom.billableSelect.value === "false") {
      dom.feeInput.value = "0";
    }

    const warnings = [];
    if (isActual) {
      warnings.push(actualStatusReason);
    }
    if (isLinkedActual) {
      warnings.push(linkedMasterReason);
    }
    if (isPlanned) {
      warnings.push(`${plannedReadonlyReason} 如已有关联 actual，RPC 会拒绝编辑。`);
    } else {
      warnings.push("课时类型、planned_lesson_id 和导入信息只读。");
    }
    renderWarning(warnings);
  }

  function renderSummary(lesson) {
    dom.summary.innerHTML = [
      ["课时 ID", shortId(lesson.id)],
      ["当前状态", lessonStatusLabel(lesson.status)],
      ["学生结算月", formatMonth(lesson.year_month)],
      ["老师结算月", formatMonth(lesson.teacher_settlement_month)],
      ["版本", safeText(lesson.updated_at) ? "updated_at 已记录" : "缺少 updated_at"],
    ].map(([label, value]) => `
      <div class="dialog-summary-row">
        <span class="dialog-summary-label">${escapeHtml(label)}</span>
        <span>${escapeHtml(displayValue(value))}</span>
      </div>
    `).join("");
  }

  function renderWarning(warnings) {
    if (!warnings.length) {
      dom.warning.textContent = "";
      dom.warning.classList.add("is-hidden");
      return;
    }

    dom.warning.textContent = warnings.join(" ");
    dom.warning.classList.remove("is-hidden");
  }

  async function handleSubmit() {
    if (isSubmitting) {
      return;
    }

    clearErrors();
    const payload = readPayload();
    if (!payload) {
      return;
    }

    setSubmitting(true);

    try {
      const updatedLesson = await updateLessonRecordGuarded(payload);
      close(true);
      await onSaved(updatedLesson);
      showMessage("success", `课时已保存：${shortId(updatedLesson.lesson_id || updatedLesson.id)}`);
    } catch (error) {
      const message = error.message || String(error);
      showError(message, fieldIdsForError(message));
    } finally {
      setSubmitting(false);
    }
  }

  function readPayload() {
    if (!currentLesson) {
      showError("缺少要编辑的课时，请重新打开编辑窗口。");
      return null;
    }

    const lesson = currentLesson;
    const isPlanned = lesson.lesson_type === "planned";
    const isActual = lesson.lesson_type === "actual";
    const isLinkedActual = isActual && Boolean(lesson.planned_lesson_id);
    const lessonDate = dom.dateInput.value;
    const status = dom.statusSelect.value;
    const studentId = dom.studentSelect.value;
    const teacherId = dom.teacherSelect.value;
    const subjectId = dom.subjectSelect.value;
    const businessEntityId = dom.businessEntitySelect.value;
    const startTime = dom.startTimeInput.value;
    const endTime = dom.endTimeInput.value;
    const durationHours = numberFromInput(dom.durationInput.value);
    const unitPrice = numberFromInput(dom.unitPriceInput.value);
    const isBillable = isPlanned ? true : dom.billableSelect.value !== "false";
    const lessonFee = isActual && !isBillable ? 0 : nullableNumberFromInput(dom.feeInput.value);
    const lessonCount = nullableIntegerFromInput(dom.countInput.value);
    const lessonContent = dom.contentInput.value.trim();
    const requiresActualRequiredFields = isActual && ["completed", "makeup_completed"].includes(status);
    const invalidFields = [];

    if (!lesson.updated_at) invalidFields.push("lessonDate");
    if (!lessonDate || Number.isNaN(new Date(`${lessonDate}T00:00:00`).getTime())) invalidFields.push("lessonDate");
    if (isPlanned && !["planned", "pending_makeup"].includes(status)) invalidFields.push("status");
    if (isActual && status !== lesson.status) invalidFields.push("status");
    if (!studentId) invalidFields.push("student");
    if (!teacherId) invalidFields.push("teacher");
    if (!subjectId) invalidFields.push("subject");
    if (!businessEntityId) invalidFields.push("businessEntity");
    if (isLinkedActual && (
      studentId !== lesson.student_id
      || teacherId !== lesson.teacher_id
      || subjectId !== lesson.subject_id
      || businessEntityId !== lesson.business_entity_id
    )) {
      invalidFields.push("student", "teacher", "subject", "businessEntity");
    }
    if (startTime && !isTimeValue(startTime)) invalidFields.push("startTime");
    if (endTime && !isTimeValue(endTime)) invalidFields.push("endTime");
    if (requiresActualRequiredFields) {
      if (!startTime) invalidFields.push("startTime");
      if (!endTime) invalidFields.push("endTime");
      if (!lessonContent) invalidFields.push("lessonContent");
    }
    const timeValidation = validateLessonTimeRange(startTime, endTime);
    let validationMessage = "";
    if (timeValidation.status === "error") {
      invalidFields.push("startTime", "endTime", "durationHours");
      validationMessage = timeValidation.message;
    } else if (
      timeValidation.status === "valid"
      && (!Number.isFinite(durationHours) || !numbersEqual(durationHours, timeValidation.durationHours))
    ) {
      invalidFields.push("durationHours");
      validationMessage = `时长必须按开始/结束时间自动计算为 ${displayInputNumber(timeValidation.durationHours)}。`;
    }
    if (!Number.isFinite(durationHours) || durationHours <= 0) invalidFields.push("durationHours");
    if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
    if (lessonFee !== null && (!Number.isFinite(lessonFee) || lessonFee < 0)) invalidFields.push("lessonFee");
    if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

    if (invalidFields.length) {
      const message = isActual && status !== lesson.status
        ? "actual 课时 V1 不允许修改状态。"
        : validationMessage
          || (requiresActualRequiredFields ? "已完成 / 补课完成 actual 必须填写开始时间、结束时间和课程内容。" : "")
          || "请检查编辑课时表单中的必填项和数字格式。";
      showError(message, Array.from(new Set(invalidFields)));
      return null;
    }

    return {
      lessonId: lesson.id,
      expectedUpdatedAt: lesson.updated_at,
      lessonDate,
      status,
      studentId,
      teacherId,
      subjectId,
      businessEntityId,
      startTime,
      endTime,
      durationHours,
      unitPrice,
      lessonFee,
      isBillable,
      lessonCount,
      lessonContent,
      note: dom.noteInput.value.trim(),
    };
  }

  function setSubmitting(nextIsSubmitting) {
    isSubmitting = nextIsSubmitting;
    dom.submitButton.disabled = nextIsSubmitting;
    dom.cancelButton.disabled = nextIsSubmitting;
    setExternalBusy?.(nextIsSubmitting);
    dom.submitButton.textContent = nextIsSubmitting ? "保存中..." : "保存";
  }

  function clearErrors() {
    dom.error.textContent = "";
    dom.error.classList.add("is-hidden");
    for (const fieldId of EDIT_LESSON_FIELD_IDS) {
      clearFieldInvalid(fieldId);
    }
  }

  function showError(message, fieldIds = []) {
    dom.error.textContent = message;
    dom.error.classList.remove("is-hidden");
    for (const fieldId of fieldIds) {
      setFieldInvalid(fieldId, true);
    }
    dom.dialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
  }

  function fieldIdsForError(message) {
    const text = safeText(message);
    const fields = [];
    if (text.includes("日期") || text.includes("月份") || text.includes("结算") || text.includes("工资")) fields.push("lessonDate");
    if (text.includes("状态")) fields.push("status");
    if (text.includes("学生")) fields.push("student");
    if (text.includes("老师")) fields.push("teacher");
    if (text.includes("科目")) fields.push("subject");
    if (text.includes("业务归属")) fields.push("businessEntity");
    if (text.includes("开始时间")) fields.push("startTime");
    if (text.includes("结束时间")) fields.push("endTime");
    if (text.includes("时长")) fields.push("durationHours");
    if (text.includes("单价")) fields.push("unitPrice");
    if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
    if (text.includes("回数")) fields.push("lessonCount");
    if (text.includes("内容") || text.includes("课程内容")) fields.push("lessonContent");
    if (text.includes("计费")) fields.push("isBillable");
    if (text.includes("版本") || text.includes("刷新") || text.includes("updated_at")) fields.push("lessonDate");
    return fields;
  }

  function setFieldInvalid(fieldId, invalid) {
    const field = dom.dialog.querySelector(`[data-edit-lesson-field="${fieldId}"]`);
    field?.classList.toggle("is-invalid", invalid);
  }

  function clearFieldInvalid(fieldId) {
    setFieldInvalid(fieldId, false);
  }

  function hideErrorIfClean() {
    const hasInvalidField = Boolean(dom.dialog.querySelector(".field.is-invalid"));
    if (!hasInvalidField) {
      dom.error.textContent = "";
      dom.error.classList.add("is-hidden");
    }
  }

  function handleBillableChange() {
    isFeeManual = false;
    syncFieldModes();
    updateFeePreview();
  }

  function updateFeePreview() {
    if (!currentLesson) {
      return;
    }

    const isActual = currentLesson.lesson_type === "actual";
    const isCancelledActual = isActual && currentLesson.status === "cancelled";
    const isBillable = dom.billableSelect.value !== "false";

    if (isCancelledActual || (isActual && !isBillable)) {
      dom.feeInput.value = "0";
      return;
    }

    if (isFeeManual) {
      return;
    }

    const durationHours = numberFromInput(dom.durationInput.value);
    const unitPrice = numberFromInput(dom.unitPriceInput.value);
    if (!Number.isFinite(durationHours) || !Number.isFinite(unitPrice) || durationHours <= 0 || unitPrice < 0) {
      dom.feeInput.value = "";
      return;
    }

    dom.feeInput.value = String(Math.round(durationHours * unitPrice));
  }

  function isDialogOpen() {
    return Boolean(dom.dialog && !dom.dialog.classList.contains("is-hidden"));
  }

  function blockDirectDismiss() {
    if (!isDialogOpen() || isSubmitting) {
      return;
    }

    showError("请使用取消按钮关闭编辑窗口；表单已有修改时需要二次确认。");
  }

  function readFormSnapshot() {
    return JSON.stringify({
      lessonDate: dom.dateInput.value,
      status: dom.statusSelect.value,
      billable: dom.billableSelect.value,
      student: dom.studentSelect.value,
      teacher: dom.teacherSelect.value,
      subject: dom.subjectSelect.value,
      businessEntity: dom.businessEntitySelect.value,
      startTime: dom.startTimeInput.value,
      endTime: dom.endTimeInput.value,
      durationHours: dom.durationInput.value,
      unitPrice: dom.unitPriceInput.value,
      lessonFee: dom.feeInput.value,
      lessonCount: dom.countInput.value,
      lessonContent: dom.contentInput.value,
      note: dom.noteInput.value,
    });
  }

  function hasFormChanged() {
    return Boolean(initialFormSnapshot && readFormSnapshot() !== initialFormSnapshot);
  }

  function syncDurationFromTimeRange() {
    const result = validateLessonTimeRange(dom.startTimeInput.value, dom.endTimeInput.value);
    if (result.status === "incomplete") {
      return;
    }

    if (result.status === "error") {
      showError(result.message, ["startTime", "endTime", "durationHours"]);
      return;
    }

    dom.durationInput.value = displayInputNumber(result.durationHours);
    clearFieldInvalid("startTime");
    clearFieldInvalid("endTime");
    clearFieldInvalid("durationHours");
    hideErrorIfClean();
    updateFeePreview();
  }

  init();
  return {
    init,
    open,
    close,
    renderAction,
    blockReason,
  };
}

function renderEntityOptionsWithPlaceholder(selectEl, rows, labelGetter, placeholder) {
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function teacherName(teacher) {
  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function subjectName(subject) {
  return safeText(subject.name) || "未设置";
}

function businessEntityName(entity) {
  return safeText(entity.name) || "未设置";
}

function lessonTypeLabel(value) {
  return LESSON_TYPE_LABELS[value] || displayValue(value);
}

function lessonStatusLabel(value) {
  return LESSON_STATUS_LABELS[value] || displayValue(value);
}

function formatInputTime(value) {
  const text = safeText(value);
  return text ? text.slice(0, 5) : "";
}

function displayInputNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }

  return String(value);
}

function isTimeValue(value) {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(safeText(value));
}

function validateLessonTimeRange(startTime, endTime) {
  const startText = safeText(startTime);
  const endText = safeText(endTime);
  if (!startText && !endText) {
    return { status: "incomplete" };
  }
  if (!startText || !endText) {
    return { status: "incomplete" };
  }
  if (!isTimeValue(startText) || !isTimeValue(endText)) {
    return {
      status: "error",
      message: "请填写正确的开始时间和结束时间。",
    };
  }

  const startMinutes = clockMinutes(startText);
  const endMinutes = clockMinutes(endText);
  const diffMinutes = endMinutes - startMinutes;
  if (diffMinutes <= 0) {
    return {
      status: "error",
      message: "结束时间必须晚于开始时间。",
    };
  }
  if (diffMinutes % 15 !== 0) {
    return {
      status: "error",
      message: "开始/结束时间差必须是 15 分钟的整数倍；不会自动四舍五入。",
    };
  }

  return {
    status: "valid",
    durationHours: Number((diffMinutes / 60).toFixed(2)),
  };
}

function clockMinutes(value) {
  const [hour, minute] = safeText(value).split(":").map(Number);
  return hour * 60 + minute;
}

function numbersEqual(left, right) {
  return Math.abs(Number(left) - Number(right)) < 0.000001;
}

function numberFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return Number.NaN;
  }

  return Number(text);
}

function nullableNumberFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return null;
  }

  return Number(text);
}

function nullableIntegerFromInput(value) {
  const text = safeText(value).trim();
  if (!text) {
    return null;
  }

  return Number(text);
}

function displayImportSource(lesson) {
  const parts = [
    safeText(lesson.import_source),
    lesson.import_batch_id ? `batch ${shortId(lesson.import_batch_id)}` : "",
    lesson.imported_at ? `imported ${safeText(lesson.imported_at).slice(0, 19)}` : "",
  ].filter(Boolean);
  return parts.join(" / ");
}

function displayValue(value) {
  return safeText(value) || "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function escapeHtml(value) {
  return safeText(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
