import { updateLessonRecordGuarded } from "../api/lesson-api.js?v=p0f-readfix-20260803-1";
import { formatMonth, safeText } from "../utils/format.js";
import { buildActualOverageDisplay } from "../utils/actual-overage.js?v=p0f-readfix-20260803-1";
import { lessonUserErrorMessage } from "../utils/lesson-error-message.js?v=p0f-readfix-20260803-1";

const LESSON_TYPE_LABELS = {
  planned: "预定",
  actual: "实际",
};

const LESSON_STATUS_LABELS = {
  planned: "待上课",
  completed: "已上课",
  pending_makeup: "待补课",
  makeup_completed: "已补课",
  cancelled: "已取消",
};

const FIXED_ONSITE_LESSON_VENUES = ["Regus公共区", "Regus办公室"];

const EDIT_LESSON_FIELD_IDS = [
  "lessonDate",
  "status",
  "student",
  "teacher",
  "subject",
  "businessEntity",
  "startTime",
  "endTime",
  "lessonDeliveryMode",
  "lessonVenue",
  "durationHours",
  "unitPrice",
  "lessonFee",
  "airconRate",
  "lessonCount",
  "lessonContent",
  "isBillable",
];

export function cacheLessonEditDialogDom(root = document) {
  return {
    dialog: root.querySelector("#editLessonDialog"),
    summary: root.querySelector("#editLessonSummary"),
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
    deliveryModeSelect: root.querySelector("#editLessonDeliveryModeSelect"),
    venueField: root.querySelector("#editLessonVenueField"),
    venueSelect: root.querySelector("#editLessonVenueSelect"),
    onlinePlatformField: root.querySelector("#editLessonOnlinePlatformField"),
    onlinePlatformInput: root.querySelector("#editLessonOnlinePlatformInput"),
    durationInput: root.querySelector("#editLessonDurationInput"),
    unitPriceInput: root.querySelector("#editLessonUnitPriceInput"),
    feeInput: root.querySelector("#editLessonFeeInput"),
    airconRateInput: root.querySelector("#editLessonAirconRateInput"),
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
    getRefreshContext,
    setExternalBusy,
    getLinkedActualExists,
  } = options;
  let currentLesson = null;
  let isSubmitting = false;
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
      ["lessonDeliveryMode", dom.deliveryModeSelect],
      ["lessonVenue", dom.venueSelect],
      ["lessonVenue", dom.onlinePlatformInput],
      ["durationHours", dom.durationInput],
      ["unitPrice", dom.unitPriceInput],
      ["lessonFee", dom.feeInput],
      ["airconRate", dom.airconRateInput],
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
    dom.billableSelect?.addEventListener("change", handleBillableChange);
    dom.deliveryModeSelect?.addEventListener("change", syncVenueFieldModes);
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
        return `当前预定课时状态不允许编辑：${lessonStatusLabel(record.status)}。`;
      }
      if (hasLinkedActual(record.id)) {
        return "该预定课时已有关联实际课时，不能在此编辑。";
      }
      return "";
    }

    if (record.lesson_type === "actual") {
      if (!["completed", "cancelled", "makeup_completed"].includes(record.status)) {
        return `当前实际课时状态不允许编辑：${lessonStatusLabel(record.status)}。`;
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
    const currentBusinessEntityId = safeText(currentLesson?.business_entity_id);
    const currentBusinessEntity = businessEntities.find((entity) => entity.id === currentBusinessEntityId);
    renderEntityOptionsWithPlaceholder(
      dom.studentSelect,
      students.filter(isActiveStudent),
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
      currentBusinessEntity ? [currentBusinessEntity] : [],
      businessEntityName,
      currentBusinessEntity ? "当前业务归属" : "请选择业务归属"
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
    dom.deliveryModeSelect.value = safeText(lesson.lesson_delivery_mode);
    dom.venueSelect.value = lesson.lesson_delivery_mode === "onsite" ? safeText(lesson.lesson_venue) : "";
    dom.onlinePlatformInput.value = lesson.lesson_delivery_mode === "online" ? safeText(lesson.lesson_venue) : "";
    dom.durationInput.value = displayInputNumber(lesson.duration_hours);
    dom.unitPriceInput.value = displayInputNumber(lesson.unit_price || 0);
    dom.feeInput.value = displayInputNumber(lesson.lesson_fee);
    dom.airconRateInput.value = lesson.lesson_type === "planned"
      && lesson.aircon_unit_price_jpy_snapshot !== null
      && lesson.aircon_unit_price_jpy_snapshot !== undefined
      ? displayInputNumber(lesson.aircon_unit_price_jpy_snapshot)
      : "";
    dom.countInput.value = lesson.lesson_count ? String(lesson.lesson_count) : "";
    dom.plannedIdInput.value = safeText(lesson.planned_lesson_id);
    dom.importSourceInput.value = displayImportSource(lesson);
    dom.contentInput.value = safeText(lesson.lesson_content);
    dom.noteInput.value = safeText(lesson.note);
    closeConfirmPending = false;
    syncFieldModes();
    syncVenueFieldModes();
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

    dom.statusSelect.disabled = isActual;
    dom.statusSelect.title = isActual ? "实际课时状态不可在此修改。" : "";
    [...dom.statusSelect.options].forEach((option) => {
      option.disabled = isPlanned
        ? !["planned", "pending_makeup"].includes(option.value)
        : option.value !== lesson.status;
    });

    [dom.studentSelect, dom.teacherSelect, dom.subjectSelect].forEach((element) => {
      element.disabled = isLinkedActual;
      element.title = isLinkedActual ? "已关联来源课时，对象信息不可在此修改。" : "";
    });
    dom.businessEntitySelect.disabled = true;
    dom.businessEntitySelect.title = "课时业务归属不可在编辑中修改；历史记录按原归属保留。";

    [dom.startTimeInput, dom.endTimeInput, dom.durationInput, dom.unitPriceInput].forEach((element) => {
      element.readOnly = isLinkedActual;
      element.title = isLinkedActual
        ? "既有 actual 的时间、时长和单价已冻结；超额时长只能在创建 actual 时由后端判定。"
        : "";
    });

    dom.billableSelect.disabled = isPlanned || isCancelledActual;
    dom.billableSelect.title = isPlanned
      ? "planned 课时固定按计费课时处理；是否实际收费由 actual 和后续结算口径决定。"
      : "";
    dom.feeInput.readOnly = isCancelledActual || (isActual && dom.billableSelect.value === "false");
    const isAirconLocked = Boolean(lesson.fee_components_frozen_at);
    dom.airconRateInput.readOnly = !isPlanned || isAirconLocked;
    dom.airconRateInput.title = !isPlanned
      ? "actual 只能展示来源 planned 的空调收费事实，不能修改。"
      : isAirconLocked
        ? "该 planned 的收费组件已冻结，空调费率只读。"
        : "只提交每条 planned 的独立费率；空调费和课程总价由数据库决定。";
    dom.typeInput.title = "课时类型不可在此修改。";
    dom.plannedIdInput.title = "关联来源不可在此修改。";
    dom.importSourceInput.title = "导入来源不可在此修改。";
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
  }

  function renderSummary(lesson) {
    const plannedLesson = lesson.lesson_type === "actual" && lesson.planned_lesson_id
      ? findLesson(lesson.planned_lesson_id)
      : null;
    const overage = buildActualOverageDisplay(lesson, plannedLesson);
    const rows = [
      ["课时类型", lessonTypeLabel(lesson.lesson_type)],
      ["当前状态", lessonStatusLabel(lesson.status)],
      [lesson.lesson_type === "actual" ? "实际发生日期" : "预计上课日期", safeText(lesson.lesson_date)],
      ["学生", selectedOptionText(dom.studentSelect)],
      ["老师", selectedOptionText(dom.teacherSelect)],
      [lesson.lesson_type === "planned" ? "收费归属月" : "学生结算月",
        formatMonth(authoritativeStudentMonth(lesson))],
      ...(lesson.lesson_type === "planned" ? [[
        "收费自然周",
        formatBillingWeekRange(lesson.billing_week_start_date),
      ]] : []),
      ["老师工资月", formatMonth(lesson.teacher_settlement_month)],
    ];
    if (overage) {
      rows.push(
        ["计划 / 实际时长", `${displayValue(overage.plannedDurationHours)} / ${displayValue(overage.actualDurationHours)} 小时`],
        ["冻结超出时长", `${displayValue(overage.overageMinutes)} 分钟`],
        ["冻结超额金额", `${displayValue(overage.frozenFeeJpy)} JPY`],
        ["超额费用下一学生结算月", formatMonth(overage.nextStudentSettlementMonth)]
      );
    }
    dom.summary.innerHTML = rows.map(([label, value]) => `
      <div class="dialog-summary-row">
        <span class="dialog-summary-label">${escapeHtml(label)}</span>
        <span>${escapeHtml(displayValue(value))}</span>
      </div>
    `).join("");
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
    const refreshContext = getRefreshContext?.() || null;
    let updatedLesson;
    try {
      updatedLesson = await updateLessonRecordGuarded(payload);
    } catch (error) {
      console.error("Lesson update failed", error);
      const message = lessonUserErrorMessage(error, "课时保存失败，请稍后重试。");
      showError(message, fieldIdsForError(message));
      setSubmitting(false);
      return;
    }

    close(true);
    try {
      await onSaved(updatedLesson, refreshContext);
      showMessage("success", `课时已保存：${shortId(updatedLesson.lesson_id || updatedLesson.id)}`);
    } catch (error) {
      console.error("Lesson update refresh failed", error);
      showMessage("error", "课时已保存，但列表刷新失败，请重新查询。");
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
    const lessonDeliveryMode = dom.deliveryModeSelect.value;
    const lessonVenue = lessonDeliveryMode === "onsite"
      ? dom.venueSelect.value
      : lessonDeliveryMode === "online"
        ? dom.onlinePlatformInput.value.trim()
        : "";
    const durationHours = numberFromInput(dom.durationInput.value);
    const unitPrice = numberFromInput(dom.unitPriceInput.value);
    const airconRateJpyPerHour = isPlanned
      ? nullableIntegerFromInput(dom.airconRateInput.value)
      : null;
    const isBillable = isPlanned ? true : dom.billableSelect.value !== "false";
    const lessonFee = null;
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
    if (lessonVenue && !lessonDeliveryMode) invalidFields.push("lessonDeliveryMode", "lessonVenue");
    if (lessonDeliveryMode === "onsite" && !lessonVenue) invalidFields.push("lessonVenue");
    if (lessonDeliveryMode === "onsite" && !FIXED_ONSITE_LESSON_VENUES.includes(lessonVenue)) invalidFields.push("lessonVenue");
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
    if (isLinkedActual && (
      startTime !== formatInputTime(lesson.start_time)
      || endTime !== formatInputTime(lesson.end_time)
      || !numbersEqual(durationHours, Number(lesson.duration_hours))
      || !numbersEqual(unitPrice, Number(lesson.unit_price || 0))
    )) {
      invalidFields.push("startTime", "endTime", "durationHours", "unitPrice");
      validationMessage = "既有 actual 的时间、时长和单价已冻结；如需记录新的超额时长，请从 planned 创建 actual。";
    }
    if (!Number.isFinite(unitPrice) || unitPrice < 0) invalidFields.push("unitPrice");
    const preservesLegacyNullAirconRate = isPlanned
      && lesson.aircon_unit_price_jpy_snapshot == null
      && airconRateJpyPerHour === null;
    if (isPlanned && !preservesLegacyNullAirconRate
        && (!Number.isInteger(airconRateJpyPerHour) || airconRateJpyPerHour < 0)) {
      invalidFields.push("airconRate");
    }
    if (lessonCount !== null && (!Number.isInteger(lessonCount) || lessonCount <= 0)) invalidFields.push("lessonCount");

    if (invalidFields.length) {
      const message = isActual && status !== lesson.status
        ? "实际课时状态不可在此修改。"
        : validationMessage
          || (requiresActualRequiredFields ? "已完成 / 补课完成 actual 必须填写开始时间、结束时间和课程内容。" : "")
          || "请检查编辑课时表单中的必填项和数字格式。";
      showError(message, Array.from(new Set(invalidFields)));
      return null;
    }

    return {
      lessonId: lesson.id,
      lessonType: lesson.lesson_type,
      expectedUpdatedAt: lesson.updated_at,
      lessonDate,
      status,
      studentId,
      teacherId,
      subjectId,
      businessEntityId,
      startTime,
      endTime,
      lessonDeliveryMode,
      lessonVenue,
      durationHours,
      unitPrice,
      lessonFee,
      airconRateJpyPerHour,
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
    if (text.includes("授课方式")) fields.push("lessonDeliveryMode");
    if (text.includes("场地") || text.includes("平台")) fields.push("lessonVenue");
    if (text.includes("时长")) fields.push("durationHours");
    if (text.includes("单价")) fields.push("unitPrice");
    if (text.includes("课时费") || text.includes("金额")) fields.push("lessonFee");
    if (text.includes("空调") || text.includes("AIRCON")) fields.push("airconRate");
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
    syncFieldModes();
    updateFeePreview();
  }

  function updateFeePreview() {
    if (!currentLesson) {
      return;
    }

    dom.feeInput.value = "";
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
      lessonDeliveryMode: dom.deliveryModeSelect.value,
      onsiteVenue: dom.venueSelect.value,
      onlinePlatform: dom.onlinePlatformInput.value,
      durationHours: dom.durationInput.value,
      unitPrice: dom.unitPriceInput.value,
      lessonFee: dom.feeInput.value,
      airconRate: dom.airconRateInput.value,
      lessonCount: dom.countInput.value,
      lessonContent: dom.contentInput.value,
      note: dom.noteInput.value,
    });
  }

  function hasFormChanged() {
    return Boolean(initialFormSnapshot && readFormSnapshot() !== initialFormSnapshot);
  }

  function syncVenueFieldModes() {
    const mode = dom.deliveryModeSelect?.value || "";
    const isOnsite = mode === "onsite";
    const isOnline = mode === "online";
    dom.venueField?.classList.toggle("is-hidden", !isOnsite);
    dom.onlinePlatformField?.classList.toggle("is-hidden", !isOnline);
    if (dom.venueSelect) dom.venueSelect.disabled = !isOnsite;
    if (dom.onlinePlatformInput) dom.onlinePlatformInput.disabled = !isOnline;
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

function isActiveStudent(student) {
  return safeText(student?.status) === "active";
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

function selectedOptionText(selectEl) {
  const text = safeText(selectEl?.selectedOptions?.[0]?.textContent);
  return text === "请选择学生" || text === "请选择老师" || text === "请选择科目" || text === "请选择业务归属"
    ? ""
    : text;
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

function authoritativeStudentMonth(lesson) {
  if (lesson?.lesson_type === "planned") {
    return safeText(lesson.billing_month);
  }
  return safeText(lesson?.authoritative_student_month);
}

function formatBillingWeekRange(weekStart) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(safeText(weekStart))) {
    return "-";
  }
  const start = new Date(`${weekStart}T00:00:00`);
  if (Number.isNaN(start.getTime())) {
    return "-";
  }
  const end = new Date(start.getTime());
  end.setDate(end.getDate() + 6);
  const endValue = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, "0")}-${String(end.getDate()).padStart(2, "0")}`;
  return `${weekStart}至${endValue}`;
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
