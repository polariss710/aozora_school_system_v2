import { deleteFreshPlannedLesson } from "../api/lesson-api.js?v=p0f-readfix-20260803-1";
import { formatMonth, safeText } from "../utils/format.js";
import { lessonUserErrorMessage } from "../utils/lesson-error-message.js?v=p0f-readfix-20260803-1";

const DELETE_LESSON_FIELD_IDS = ["confirm"];

export function cacheLessonDeleteDialogDom(root = document) {
  return {
    dialog: root.querySelector("#deleteLessonDialog"),
    summary: root.querySelector("#deleteLessonSummary"),
    error: root.querySelector("#deleteLessonError"),
    confirmCheckbox: root.querySelector("#deleteLessonConfirmCheckbox"),
    submitButton: root.querySelector("#deleteLessonSubmitButton"),
    cancelButton: root.querySelector("#deleteLessonCancelButton"),
  };
}

export function createLessonDeleteDialogController(options) {
  const {
    dom,
    getLessonRecords,
    hasSupabaseConfig,
    showMessage,
    onDeleted,
    setExternalBusy,
    getLinkedActualExists,
  } = options;
  let currentLesson = null;
  let isSubmitting = false;
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

    dom.confirmCheckbox?.addEventListener("change", () => {
      closeConfirmPending = false;
      clearFieldInvalid("confirm");
      hideErrorIfClean();
    });
  }

  function open(lessonId) {
    if (!hasSupabaseConfig()) {
      showMessage("error", "当前 Supabase 配置不可用，不能删除预定课时。");
      return;
    }

    const lesson = findLesson(lessonId);
    if (!lesson) {
      showMessage("error", "未找到要删除的预定课时。");
      return;
    }

    const reason = blockReason(lesson);
    if (reason) {
      showMessage("error", reason);
      return;
    }

    currentLesson = lesson;
    resetForm();
    renderSummary(lesson);
    clearErrors();
    setSubmitting(false);
    dom.dialog.classList.remove("is-hidden");
    dom.dialog.setAttribute("aria-hidden", "false");
    dom.confirmCheckbox.focus();
  }

  function close(force = false) {
    if (isSubmitting && !force) {
      return;
    }

    if (!force && dom.confirmCheckbox.checked) {
      if (!closeConfirmPending) {
        closeConfirmPending = true;
        showError("已勾选删除确认。再次点击取消将关闭窗口。");
        return;
      }
    }

    dom.dialog?.classList.add("is-hidden");
    dom.dialog?.setAttribute("aria-hidden", "true");
    currentLesson = null;
    closeConfirmPending = false;
  }

  function blockDirectDismiss() {
    showError("删除确认窗口不能通过背景或 Esc 关闭，请点击取消。");
  }

  function renderAction(record) {
    const reason = blockReason(record);
    if (reason) {
      return "";
    }

    return `<button class="button button-danger table-action-button" type="button" data-delete-planned-lesson-id="${escapeAttribute(record.id)}">删除</button>`;
  }

  function blockReason(record) {
    if (!record || !record.id) {
      return "缺少课时记录。";
    }

    if (record.lesson_type !== "planned") {
      return "只允许删除 planned 预定课时。";
    }

    if (record.voided_at) {
      return "该预定课时已作废，不能删除。";
    }

    if (record.status !== "planned") {
      return `只有全新的待上课预定课时可以删除；当前状态为：${lessonStatusLabel(record.status)}。`;
    }

    if (hasLinkedActual(record.id)) {
      return "该 planned 已有关联实际课时、取消课或补课记录，不能删除。";
    }

    if (!safeText(record.updated_at)) {
      return "缺少 updated_at，不能删除。";
    }

    return "";
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

  function resetForm() {
    dom.confirmCheckbox.checked = false;
    closeConfirmPending = false;
  }

  function renderSummary(lesson) {
    dom.summary.innerHTML = [
      ["planned id", shortId(lesson.id)],
      ["当前状态", lessonStatusLabel(lesson.status)],
      ["课时日期", displayValue(lesson.lesson_date)],
      ["收费归属月", formatMonth(lesson.authoritative_student_month)],
      ["版本", safeText(lesson.updated_at) ? "updated_at 已记录" : "缺少 updated_at"],
    ].map(([label, value]) => `
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

    try {
      const sourceLesson = currentLesson;
      const result = await deleteFreshPlannedLesson(payload);
      close(true);
      if (typeof onDeleted === "function") {
        try {
          await onDeleted(result, sourceLesson);
        } catch (refreshError) {
          console.error("Lesson delete refresh failed", refreshError);
          showMessage("error", "预定课时已删除，但列表刷新失败，请重新查询。");
        }
      }
    } catch (error) {
      console.error("Lesson delete failed", error);
      showError(lessonUserErrorMessage(error, "预定课时删除失败，请稍后重试。"));
    } finally {
      setSubmitting(false);
    }
  }

  function readPayload() {
    if (!currentLesson) {
      showError("缺少要删除的预定课时，请重新打开窗口。");
      return null;
    }

    if (!dom.confirmCheckbox.checked) {
      showError("请勾选确认删除。", ["confirm"]);
      return null;
    }

    return {
      lessonId: currentLesson.id,
      expectedUpdatedAt: currentLesson.updated_at,
      confirmDelete: true,
    };
  }

  function setSubmitting(isBusy) {
    isSubmitting = isBusy;
    dom.submitButton.disabled = isBusy;
    dom.cancelButton.disabled = isBusy;
    if (typeof setExternalBusy === "function") {
      setExternalBusy(isBusy);
    }
    dom.submitButton.textContent = isBusy ? "删除中..." : "确认删除";
  }

  function clearErrors() {
    dom.error.textContent = "";
    dom.error.classList.add("is-hidden");
    for (const fieldId of DELETE_LESSON_FIELD_IDS) {
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

  function setFieldInvalid(fieldId, invalid) {
    const field = dom.dialog.querySelector(`[data-delete-lesson-field="${fieldId}"]`);
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

  function isDialogOpen() {
    return Boolean(dom.dialog && !dom.dialog.classList.contains("is-hidden"));
  }

  return {
    init,
    open,
    close,
    renderAction,
    blockReason,
  };
}

function lessonStatusLabel(value) {
  const labels = {
    planned: "待上课",
    pending_makeup: "待补课",
    completed: "已完成",
    cancelled: "已取消",
    makeup_completed: "补课完成",
  };
  return labels[value] || displayValue(value);
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function displayValue(value) {
  return safeText(value) || "-";
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
