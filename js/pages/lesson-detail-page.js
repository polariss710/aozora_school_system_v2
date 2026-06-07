import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchLessonDetailPage } from "../api/lesson-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

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

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
};

const WAGE_STATUS_LABELS = {
  locked: "已锁定",
  void: "已作废",
};

const WAGE_DETAIL_STATUS_LABELS = {
  completed: "已完成",
  makeup_completed: "补课完成",
};

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const dom = {};

export function initLessonDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const lessonId = readLessonId();
  if (!lessonId) {
    showMessage("error", "缺少课时记录 ID，请从课时管理一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadLessonDetail(lessonId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#lessonDetailMessageArea");
  dom.loadingState = document.querySelector("#lessonDetailLoadingState");
  dom.content = document.querySelector("#lessonDetailContent");
  dom.titleText = document.querySelector("#lessonDetailTitleText");
  dom.basicInfo = document.querySelector("#lessonDetailBasicInfo");
  dom.objectInfo = document.querySelector("#lessonDetailObjectInfo");
  dom.billingInfo = document.querySelector("#lessonDetailBillingInfo");
  dom.systemInfo = document.querySelector("#lessonDetailSystemInfo");
  dom.textBlock = document.querySelector("#lessonDetailTextBlock");
  dom.chainCount = document.querySelector("#lessonDetailChainCount");
  dom.chainEmpty = document.querySelector("#lessonDetailChainEmpty");
  dom.chainRows = document.querySelector("#lessonDetailChainRows");
  dom.settlementCount = document.querySelector("#lessonDetailSettlementCount");
  dom.settlementEmpty = document.querySelector("#lessonDetailSettlementEmpty");
  dom.settlementCards = document.querySelector("#lessonDetailSettlementCards");
  dom.wageCount = document.querySelector("#lessonDetailWageCount");
  dom.wageEmpty = document.querySelector("#lessonDetailWageEmpty");
  dom.wageRows = document.querySelector("#lessonDetailWageRows");
}

function readLessonId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadLessonDetail(lessonId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载课时详情...");

  try {
    const data = await fetchLessonDetailPage(lessonId);
    renderLessonDetail(data);
    setContentVisible(true);
    showMessage("success", "课时详情已加载。");
  } catch (error) {
    setContentVisible(false);
    showMessage("error", `读取课时详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderLessonDetail(data) {
  const { lesson, lookups, sourceChain, settlements, wageReferences } = data;

  dom.titleText.textContent = `${formatDateOnly(lesson.lesson_date)} / ${studentNameById(lookups, lesson.student_id)} / ${lessonTypeLabel(lesson.lesson_type)}`;
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["lesson id", shortId(lesson.id)],
    ["课时类型", lessonTypeLabel(lesson.lesson_type)],
    ["状态", lessonStatusLabel(lesson.status)],
    ["课时日期", formatDateOnly(lesson.lesson_date)],
    ["结算年月", formatMonth(lesson.year_month)],
    ["开始时间", formatTime(lesson.start_time)],
    ["结束时间", formatTime(lesson.end_time)],
    ["时长", displayValue(lesson.duration_hours)],
    ["实际分钟", displayValue(lesson.actual_minutes)],
    ["课次数", displayValue(lesson.lesson_count)],
  ]);

  dom.objectInfo.innerHTML = renderDefinitionList([
    ["学生", studentNameById(lookups, lesson.student_id)],
    ["学生编号", studentCodeById(lookups, lesson.student_id)],
    ["老师", teacherNameById(lookups, lesson.teacher_id)],
    ["老师编号", teacherCodeById(lookups, lesson.teacher_id)],
    ["科目", subjectNameById(lookups, lesson.subject_id)],
    ["科目分类", subjectCategoryById(lookups, lesson.subject_id)],
    ["业务归属", businessNameById(lookups, lesson.business_entity_id)],
    ["业务编码", businessCodeById(lookups, lesson.business_entity_id)],
  ]);

  dom.billingInfo.innerHTML = renderDefinitionList([
    ["计费", booleanLabel(lesson.is_billable)],
    ["单价", formatCurrency(lesson.unit_price, "JPY")],
    ["课时费", formatCurrency(lesson.lesson_fee, "JPY")],
    ["老师结算月", formatMonth(lesson.teacher_settlement_month)],
    ["planned_lesson_id", shortId(lesson.planned_lesson_id)],
  ]);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["import_batch_id", displayValue(lesson.import_batch_id)],
    ["import_source", displayValue(lesson.import_source)],
    ["imported_at", formatDate(lesson.imported_at)],
    ["app_type", displayValue(lesson.app_type)],
    ["created_at", formatDate(lesson.created_at)],
    ["updated_at", formatDate(lesson.updated_at)],
  ]);

  dom.textBlock.textContent = [
    "课程内容：",
    displayValue(lesson.lesson_content),
    "",
    "备注：",
    displayValue(lesson.note),
  ].join("\n");

  renderSourceChain(sourceChain);
  renderSettlementReferences(settlements);
  renderWageReferences(wageReferences);
}

function renderSourceChain(rows) {
  dom.chainCount.textContent = `${rows.length} 条`;
  dom.chainEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.chainRows.innerHTML = "";
    return;
  }

  dom.chainRows.innerHTML = rows.map(({ relation, lesson }) => `
    <tr>
      <td class="lesson-nowrap"><a class="table-action-button" href="./lesson-detail.html?id=${encodeURIComponent(lesson.id)}">详情</a></td>
      <td class="lesson-nowrap">${escapeHtml(displayValue(relation))}</td>
      <td class="lesson-nowrap">${escapeHtml(shortId(lesson.id))}</td>
      <td><span class="status-badge status-neutral">${escapeHtml(lessonTypeLabel(lesson.lesson_type))}</span></td>
      <td><span class="status-badge ${escapeAttribute(lessonStatusClass(lesson.status))}">${escapeHtml(lessonStatusLabel(lesson.status))}</span></td>
      <td class="lesson-nowrap">${escapeHtml(formatDateOnly(lesson.lesson_date))}</td>
      <td class="lesson-nowrap">${escapeHtml(timeRange(lesson.start_time, lesson.end_time))}</td>
      <td class="number-cell">${escapeHtml(displayValue(lesson.duration_hours))}</td>
      <td class="number-cell">${escapeHtml(displayValue(lesson.actual_minutes))}</td>
      <td class="lesson-nowrap">${escapeHtml(booleanLabel(lesson.is_billable))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(lesson.lesson_fee, "JPY"))}</td>
      <td class="lesson-nowrap">${escapeHtml(shortId(lesson.planned_lesson_id))}</td>
      <td class="lesson-content-cell"><span class="table-cell-summary">${escapeHtml(displayValue(lesson.lesson_content))}</span></td>
    </tr>
  `).join("");
}

function renderSettlementReferences(rows) {
  dom.settlementCount.textContent = `${rows.length} 条`;
  dom.settlementEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.settlementCards.innerHTML = "";
    return;
  }

  dom.settlementCards.innerHTML = rows.map((settlement) => `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(settlement.id))}</strong>
        <span class="status-badge ${escapeAttribute(settlementStatusClass(settlement.settlement_status))}">${escapeHtml(settlementStatusLabel(settlement.settlement_status))}</span>
      </div>
      ${renderDefinitionList([
        ["结算年月", formatMonth(settlement.year_month)],
        ["预定学费 JPY", formatCurrency(settlement.planned_lesson_fee_jpy, "JPY")],
        ["预定学费 CNY", formatCurrency(settlement.planned_lesson_fee_cny, "CNY")],
        ["实际学费 JPY", formatCurrency(settlement.actual_lesson_fee_jpy, "JPY")],
        ["实际学费 CNY", formatCurrency(settlement.actual_lesson_fee_cny, "CNY")],
        ["收款 JPY", formatCurrency(settlement.received_jpy, "JPY")],
        ["收款 CNY", formatCurrency(settlement.received_cny, "CNY")],
        ["收款折算 CNY", formatCurrency(settlement.received_equivalent_cny, "CNY")],
        ["结转 CNY", formatCurrency(settlement.carryover_amount_cny, "CNY")],
        ["锁定时间", formatDate(settlement.locked_at)],
      ])}
      <p><a class="table-action-button" href="./settlement-detail.html?id=${encodeURIComponent(settlement.id)}">学生月度结算详情</a></p>
    </article>
  `).join("");
}

function renderWageReferences(rows) {
  dom.wageCount.textContent = `${rows.length} 条`;
  dom.wageEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.wageRows.innerHTML = "";
    return;
  }

  dom.wageRows.innerHTML = rows.map(({ detail, wageLock }) => `
    <tr>
      <td class="lesson-nowrap">${wageLock?.id ? `<a class="table-action-button" href="./wage-detail.html?id=${encodeURIComponent(wageLock.id)}">详情</a>` : "-"}</td>
      <td class="lesson-nowrap">${escapeHtml(shortId(detail.lock_id))}</td>
      <td>${wageLock?.status ? `<span class="status-badge ${escapeAttribute(wageStatusClass(wageLock.status))}">${escapeHtml(wageStatusLabel(wageLock.status))}</span>` : "-"}</td>
      <td class="lesson-nowrap">${escapeHtml(formatMonth(wageLock?.settlement_month))}</td>
      <td>${escapeHtml(displayValue(wageLock?.teacher_name))}</td>
      <td class="number-cell">${escapeHtml(displayValue(detail.pay_hours))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.lesson_wage_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.lesson_wage_cny, "CNY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.transport_fee_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.classroom_fee_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.total_jpy, "JPY"))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(detail.total_cny, "CNY"))}</td>
      <td><span class="status-badge ${escapeAttribute(wageDetailStatusClass(detail.status))}">${escapeHtml(wageDetailStatusLabel(detail.status))}</span></td>
      <td>${escapeHtml(settlementTypeLabel(detail.settlement_type))}</td>
      <td class="number-cell">${escapeHtml(displayValue(detail.exchange_rate))}</td>
    </tr>
  `).join("");
}

function renderDefinitionList(items) {
  return `
    <dl class="detail-definition-list">
      ${items.map(([label, value]) => `
        <div>
          <dt>${escapeHtml(label)}</dt>
          <dd>${escapeHtml(displayValue(value))}</dd>
        </div>
      `).join("")}
    </dl>
  `;
}

function studentNameById(lookups, id) {
  const student = findById(lookups.students, id);
  return displayValue(student?.display_name || student?.name || id);
}

function studentCodeById(lookups, id) {
  return displayValue(findById(lookups.students, id)?.student_code);
}

function teacherNameById(lookups, id) {
  const teacher = findById(lookups.teachers, id);
  return displayValue(teacher?.display_name || teacher?.name || id);
}

function teacherCodeById(lookups, id) {
  return displayValue(findById(lookups.teachers, id)?.teacher_code);
}

function subjectNameById(lookups, id) {
  return displayValue(findById(lookups.subjects, id)?.name || id);
}

function subjectCategoryById(lookups, id) {
  const subject = findById(lookups.subjects, id);
  return displayValue(subject?.primary_category || subject?.category);
}

function businessNameById(lookups, id) {
  return displayValue(findById(lookups.businessEntities, id)?.name || id);
}

function businessCodeById(lookups, id) {
  return displayValue(findById(lookups.businessEntities, id)?.code);
}

function findById(rows, id) {
  return rows.find((row) => row.id === id) || null;
}

function lessonTypeLabel(value) {
  return LESSON_TYPE_LABELS[value] || displayValue(value);
}

function lessonStatusLabel(value) {
  return LESSON_STATUS_LABELS[value] || displayValue(value);
}

function lessonStatusClass(value) {
  if (value === "completed" || value === "makeup_completed") return "status-paid";
  if (value === "planned" || value === "pending_makeup") return "status-pending";
  if (value === "cancelled") return "status-cancelled";
  return "status-neutral";
}

function settlementStatusLabel(value) {
  return SETTLEMENT_STATUS_LABELS[value] || displayValue(value);
}

function settlementStatusClass(value) {
  if (value === "locked") return "status-paid";
  return "status-neutral";
}

function wageStatusLabel(value) {
  return WAGE_STATUS_LABELS[value] || displayValue(value);
}

function wageStatusClass(value) {
  if (value === "locked") return "status-paid";
  if (value === "void") return "status-cancelled";
  return "status-neutral";
}

function wageDetailStatusLabel(value) {
  return WAGE_DETAIL_STATUS_LABELS[value] || displayValue(value);
}

function wageDetailStatusClass(value) {
  if (value === "completed" || value === "makeup_completed") return "status-paid";
  return "status-neutral";
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function booleanLabel(value) {
  if (value === true) return "是";
  if (value === false) return "否";
  return "-";
}

function formatDateOnly(value) {
  if (!value) return "-";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return safeText(value);

  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function formatTime(value) {
  const text = safeText(value);
  if (!text) return "-";
  return text.slice(0, 5);
}

function timeRange(startTime, endTime) {
  const start = formatTime(startTime);
  const end = formatTime(endTime);
  if (start === "-" && end === "-") return "-";
  return `${start} - ${end}`;
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function displayValue(value) {
  return safeText(value) || "-";
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function setContentVisible(isVisible) {
  dom.content.classList.toggle("is-hidden", !isVisible);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
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
