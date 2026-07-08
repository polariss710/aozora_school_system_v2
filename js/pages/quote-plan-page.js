const DEFAULT_EXCHANGE_RATE = 0.05;
const JPY_CNY_RATE_API_URL = "https://api.frankfurter.dev/v2/rate/JPY/CNY";
const DEFAULT_UNIT_PRICE_JPY = 10000;

const COURSE_TRACK_SUBJECTS = {
  science: ["日语", "数学", "物理", "化学"],
  humanities: ["日语", "数学", "文综"],
};

const state = {
  courses: [],
  removedRowKeys: new Set(),
  planSignature: "",
};

const dom = {};

export function initQuotePlanPage() {
  cacheDom();
  restoreDraft();
  bindEvents();
  renderCourseRows();
  renderQuote();
}

function cacheDom() {
  dom.form = document.querySelector("#quotePlanForm");
  dom.messageArea = document.querySelector("#quotePlanMessageArea");
  dom.studentNameInput = document.querySelector("#quoteStudentName");
  dom.quoteTitleInput = document.querySelector("#quoteTitle");
  dom.courseTrackSelect = document.querySelector("#quoteCourseTrack");
  dom.startDateInput = document.querySelector("#quoteStartDate");
  dom.endDateInput = document.querySelector("#quoteEndDate");
  dom.exchangeRateInput = document.querySelector("#quoteExchangeRate");
  dom.exchangeRateFetchButton = document.querySelector("#quoteExchangeRateFetchButton");
  dom.exchangeRateStatus = document.querySelector("#quoteExchangeRateStatus");
  dom.noteInput = document.querySelector("#quoteNote");
  dom.courseList = document.querySelector("#quoteCourseList");
  dom.addCourseButton = document.querySelector("#addQuoteCourseButton");
  dom.preview = document.querySelector("#quotePlanPreview");
  dom.printButton = document.querySelector("#printQuotePlanButton");
  dom.resetButton = document.querySelector("#resetQuotePlanButton");
  dom.summary = document.querySelector("#quotePlanSummary");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => {
    event.preventDefault();
    renderQuote({ showSuccess: true });
  });

  dom.form?.addEventListener("input", () => renderQuote());
  dom.form?.addEventListener("change", (event) => {
    if (event.target === dom.courseTrackSelect) {
      applyCourseTrackPreset();
    }
    renderQuote();
  });

  dom.addCourseButton?.addEventListener("click", () => {
    state.courses.push(createBlankCourse());
    renderCourseRows();
    renderQuote();
  });

  dom.exchangeRateFetchButton?.addEventListener("click", fetchTodayExchangeRate);

  dom.courseList?.addEventListener("input", handleCourseInput);
  dom.courseList?.addEventListener("click", handleCourseClick);
  dom.preview?.addEventListener("click", handlePreviewClick);

  dom.printButton?.addEventListener("click", () => {
    printQuotePlan();
  });

  dom.resetButton?.addEventListener("click", resetDraft);
}

function restoreDraft() {
  const draft = createDefaultDraft();
  dom.studentNameInput.value = draft.studentName || "";
  dom.quoteTitleInput.value = draft.title || "课程计划";
  dom.courseTrackSelect.value = draft.courseTrack || "science";
  dom.startDateInput.value = draft.startDate || getTodayDateValue();
  dom.endDateInput.value = draft.endDate || getDefaultEndDateValue();
  dom.exchangeRateInput.value = toInputNumber(toStrictPositiveNumber(draft.exchangeRate, DEFAULT_EXCHANGE_RATE), DEFAULT_EXCHANGE_RATE);
  dom.noteInput.value = draft.note || "";
  state.courses = draft.courses.map(normalizeCourse);
}

function resetDraft() {
  const draft = createDefaultDraft();
  dom.studentNameInput.value = draft.studentName;
  dom.quoteTitleInput.value = draft.title;
  dom.courseTrackSelect.value = draft.courseTrack;
  dom.startDateInput.value = draft.startDate;
  dom.endDateInput.value = draft.endDate;
  dom.exchangeRateInput.value = draft.exchangeRate;
  dom.noteInput.value = draft.note;
  state.courses = draft.courses.map(normalizeCourse);
  state.removedRowKeys.clear();
  state.planSignature = "";
  renderCourseRows();
  renderQuote({ message: "已恢复默认报价模板。" });
}

function createDefaultDraft() {
  return {
    studentName: "",
    title: "课程计划",
    courseTrack: "science",
    startDate: getTodayDateValue(),
    endDate: getDefaultEndDateValue(),
    exchangeRate: DEFAULT_EXCHANGE_RATE,
    note: "",
    courses: createCoursesForTrack("science"),
  };
}

function createBlankCourse() {
  return {
    name: "",
    content: "",
    hoursPerSession: 2,
    weeklyFrequency: 1,
    unitPriceJpy: DEFAULT_UNIT_PRICE_JPY,
  };
}

function createCoursesForTrack(track) {
  const subjects = COURSE_TRACK_SUBJECTS[track] || COURSE_TRACK_SUBJECTS.science;
  return subjects.map((subject) => ({
    name: subject,
    content: subject,
    hoursPerSession: 2,
    weeklyFrequency: 1,
    unitPriceJpy: DEFAULT_UNIT_PRICE_JPY,
  }));
}

function normalizeCourse(course) {
  return {
    name: String(course?.name || ""),
    content: String(course?.content || course?.name || ""),
    hoursPerSession: toPositiveNumber(course?.hoursPerSession, 2),
    weeklyFrequency: toPositiveInteger(course?.weeklyFrequency, 1),
    unitPriceJpy: toPositiveNumber(course?.unitPriceJpy, 0),
  };
}

function renderCourseRows() {
  if (!dom.courseList) return;

  dom.courseList.innerHTML = state.courses.map((course, index) => `
    <div class="quote-course-row" data-course-index="${index}">
      <label class="field">
        <span>课程</span>
        <input type="text" value="${escapeHtml(course.name)}" data-course-field="name" placeholder="例：EJU日语">
      </label>
      <label class="field">
        <span>内容</span>
        <input type="text" value="${escapeHtml(course.content)}" data-course-field="content" placeholder="显示在报价单上的内容">
      </label>
      <label class="field">
        <span>每次时长(H)</span>
        <input type="number" min="0.25" step="0.25" value="${escapeHtml(toInputNumber(course.hoursPerSession, 2))}" data-course-field="hoursPerSession">
      </label>
      <label class="field">
        <span>每周次数</span>
        <input type="number" min="1" step="1" value="${escapeHtml(toInputNumber(course.weeklyFrequency, 1))}" data-course-field="weeklyFrequency">
      </label>
      <label class="field">
        <span>内部单价(JPY/H)</span>
        <input type="number" min="0" step="100" value="${escapeHtml(toInputNumber(course.unitPriceJpy, 0))}" data-course-field="unitPriceJpy">
      </label>
      <button class="button quote-course-remove-button" type="button" data-course-action="remove" ${state.courses.length <= 1 ? "disabled" : ""}>移除</button>
    </div>
  `).join("");
}

function handleCourseInput(event) {
  const input = event.target.closest("[data-course-field]");
  if (!input) return;

  const row = input.closest("[data-course-index]");
  const index = Number(row?.dataset.courseIndex);
  const field = input.dataset.courseField;
  if (!Number.isInteger(index) || !state.courses[index]) return;

  if (field === "hoursPerSession" || field === "unitPriceJpy") {
    state.courses[index][field] = toPositiveNumber(input.value, 0);
  } else if (field === "weeklyFrequency") {
    state.courses[index][field] = toPositiveInteger(input.value, 1);
  } else {
    state.courses[index][field] = input.value;
  }

  renderQuote();
}

function handleCourseClick(event) {
  const button = event.target.closest("[data-course-action='remove']");
  if (!button) return;

  const row = button.closest("[data-course-index]");
  const index = Number(row?.dataset.courseIndex);
  if (!Number.isInteger(index) || state.courses.length <= 1) return;

  state.courses.splice(index, 1);
  renderCourseRows();
  renderQuote();
}

function handlePreviewClick(event) {
  const button = event.target.closest("[data-quote-delete-row-key]");
  if (!button) return;

  const key = button.dataset.quoteDeleteRowKey;
  if (!key) return;

  state.removedRowKeys.add(key);
  renderQuote({
    message: "已从报价单中移除该课时，打印 / 保存 PDF 将按当前预览输出。",
    preserveManualAdjustments: true,
  });
}

function renderQuote(options = {}) {
  const draft = getDraftFromForm();
  const signature = buildPlanSignature(draft);
  if (!options.preserveManualAdjustments && state.planSignature && signature !== state.planSignature) {
    state.removedRowKeys.clear();
  }
  state.planSignature = signature;

  const result = buildQuotePlan(draft);
  renderSummary(result);
  renderPreview(draft, result);

  if (options.message) {
    showMessage(options.message, "success");
  } else if (options.showSuccess) {
    showMessage("报价单预览已更新。", "success");
  } else if (result.warnings.length) {
    showMessage(result.warnings[0], "warning");
  } else {
    hideMessage();
  }
}

function getDraftFromForm() {
  return {
    studentName: dom.studentNameInput?.value.trim() || "",
    title: dom.quoteTitleInput?.value.trim() || "课程计划",
    courseTrack: dom.courseTrackSelect?.value || "science",
    startDate: dom.startDateInput?.value || "",
    endDate: dom.endDateInput?.value || "",
    exchangeRate: toStrictPositiveNumber(dom.exchangeRateInput?.value, DEFAULT_EXCHANGE_RATE),
    note: dom.noteInput?.value.trim() || "",
    courses: state.courses.map(normalizeCourse),
  };
}

function applyCourseTrackPreset() {
  const track = dom.courseTrackSelect?.value || "science";
  state.courses = createCoursesForTrack(track).map(normalizeCourse);
  state.removedRowKeys.clear();
  state.planSignature = "";
  renderCourseRows();
}

function printQuotePlan() {
  const draft = getDraftFromForm();
  renderQuote();

  const previousTitle = document.title;
  const printTitle = buildQuoteDocumentTitle(draft);
  let restored = false;

  const restoreTitle = () => {
    if (restored) return;
    restored = true;
    document.title = previousTitle;
  };

  document.title = printTitle;
  window.addEventListener("afterprint", restoreTitle, { once: true });
  window.setTimeout(restoreTitle, 30000);
  window.print();
}

function buildQuoteDocumentTitle(draft) {
  const studentName = normalizePdfTitlePart(draft.studentName);
  const title = normalizePdfTitlePart(draft.title) || "课程计划";

  if (!studentName) {
    return title;
  }

  const studentLabel = studentName.endsWith("同学") ? studentName : `${studentName}同学`;
  return `${studentLabel}${title}`;
}

function normalizePdfTitlePart(value) {
  return String(value || "")
    .trim()
    .replace(/[\\/:*?"<>|]/g, "")
    .replace(/\s+/g, "");
}

function buildPlanSignature(draft) {
  return JSON.stringify({
    startDate: draft.startDate,
    endDate: draft.endDate,
    courses: draft.courses.map((course) => ({
      name: course.name,
      hoursPerSession: course.hoursPerSession,
      weeklyFrequency: course.weeklyFrequency,
    })),
  });
}

function buildQuotePlan(draft) {
  const warnings = [];
  const startDate = parseDateValue(draft.startDate);
  const endDate = parseDateValue(draft.endDate);
  const exchangeRate = toStrictPositiveNumber(draft.exchangeRate, DEFAULT_EXCHANGE_RATE);

  if (!startDate || !endDate) {
    warnings.push("请输入课程开始日期和结束日期。");
  } else if (startDate > endDate) {
    warnings.push("课程结束日期不能早于开始日期。");
  }

  const validCourses = draft.courses
    .map((course, index) => ({
      ...normalizeCourse(course),
      courseIndex: index,
    }))
    .filter((course) => course.name.trim() && course.hoursPerSession > 0 && course.weeklyFrequency > 0);

  if (!validCourses.length) {
    warnings.push("至少需要一门有效课程。");
  }

  if (warnings.length) {
    return { warnings, months: [], grandTotalHours: 0, grandTotalJpy: 0, grandTotalCny: 0 };
  }

  const mondays = listMondays(startDate, endDate);
  if (!mondays.length) {
    warnings.push("所选日期范围内没有周一，请扩大日期范围。");
  }

  const allRows = [];

  mondays.forEach((monday) => {
    validCourses.forEach((course) => {
      for (let count = 0; count < course.weeklyFrequency; count += 1) {
        allRows.push({
          rowKey: buildQuoteRowKey(course.courseIndex, monday, count),
          courseIndex: course.courseIndex,
          courseName: course.name,
          monthKey: getMonthKey(monday),
          monthLabel: formatMonthLabel(monday),
          weekLabel: formatWeekLabel(monday),
          content: course.content || course.name,
          hours: course.hoursPerSession,
          amountJpy: course.hoursPerSession * course.unitPriceJpy,
        });
      }
    });
  });

  const visibleRows = allRows.filter((row) => !state.removedRowKeys.has(row.rowKey));
  const counters = new Map(validCourses.map((course) => [course.courseIndex, 0]));
  const monthMap = new Map();

  visibleRows.forEach((row) => {
    const currentCount = (counters.get(row.courseIndex) || 0) + 1;
    counters.set(row.courseIndex, currentCount);

    if (!monthMap.has(row.monthKey)) {
      monthMap.set(row.monthKey, { key: row.monthKey, label: row.monthLabel, rows: [], totalHours: 0, totalJpy: 0 });
    }

    const month = monthMap.get(row.monthKey);
    month.rows.push({
      ...row,
      lessonNumber: currentCount,
    });
    month.totalHours += row.hours;
    month.totalJpy += row.amountJpy;
  });

  const months = Array.from(monthMap.values()).map((month) => ({
    ...month,
    totalCny: month.totalJpy * exchangeRate,
  }));

  const grandTotalHours = months.reduce((sum, month) => sum + month.totalHours, 0);
  const grandTotalJpy = months.reduce((sum, month) => sum + month.totalJpy, 0);
  const grandTotalCny = grandTotalJpy * exchangeRate;

  return { warnings, months, grandTotalHours, grandTotalJpy, grandTotalCny };
}

function renderSummary(result) {
  if (!dom.summary) return;

  dom.summary.innerHTML = `
    <div class="summary-card"><span>报价月份</span><strong>${formatNumber(result.months.length)} 个月</strong></div>
    <div class="summary-card"><span>总课时</span><strong>${formatHours(result.grandTotalHours)} H</strong></div>
    <div class="summary-card"><span>报价合计</span><strong>${formatCurrency(result.grandTotalJpy, "JPY")}</strong></div>
    <div class="summary-card"><span>人民币参考</span><strong>${formatCurrency(result.grandTotalCny, "CNY")}</strong></div>
  `;
}

async function fetchTodayExchangeRate() {
  setExchangeRateFetching(true);
  setExchangeRateStatus("正在获取今日参考汇率...");

  try {
    const rate = await fetchLatestJpyCnyRate();
    dom.exchangeRateInput.value = formatRateValue(rate);
    renderQuote({
      message: "已获取今日参考汇率，可继续手动调整。",
      preserveManualAdjustments: true,
    });
    setExchangeRateStatus("已获取今日参考汇率，可手动调整。");
  } catch (error) {
    setExchangeRateStatus("汇率获取失败，可手动输入。");
    showMessage(`今日汇率获取失败：${error.message || error}。可手动输入汇率继续。`, "error");
  } finally {
    setExchangeRateFetching(false);
  }
}

async function fetchLatestJpyCnyRate() {
  const response = await fetch(JPY_CNY_RATE_API_URL, {
    headers: { accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`Frankfurter API HTTP ${response.status}`);
  }

  const data = await response.json();
  const rate = Number(data?.rate ?? data?.rates?.CNY);
  if (!Number.isFinite(rate) || rate <= 0) {
    throw new Error("Frankfurter API 未返回有效 CNY/JPY 汇率");
  }

  return rate;
}

function setExchangeRateFetching(isFetching) {
  if (dom.exchangeRateFetchButton) {
    dom.exchangeRateFetchButton.disabled = isFetching;
    dom.exchangeRateFetchButton.textContent = isFetching ? "获取中..." : "获取今日汇率";
  }
}

function setExchangeRateStatus(message) {
  if (!dom.exchangeRateStatus) return;
  dom.exchangeRateStatus.textContent = message || "";
}

function renderPreview(draft, result) {
  if (!dom.preview) return;

  if (!result.months.length) {
    dom.preview.innerHTML = `<div class="quote-empty-preview"><p>当前没有可显示课程，请调整报价条件或恢复默认模板。</p></div>`;
    return;
  }

  const studentName = draft.studentName || "未填写学生";
  const title = draft.title || "课程计划";
  const period = `${formatDateForDisplay(draft.startDate)} - ${formatDateForDisplay(draft.endDate)}`;

  dom.preview.innerHTML = result.months.map((month, index) => `
    <article class="quote-print-page">
      <header class="quote-print-header">
        <div>
          <p class="quote-print-kicker">${escapeHtml(studentName)}</p>
          <h2>${escapeHtml(month.label)} ${escapeHtml(title)}</h2>
          <p>${escapeHtml(period)}</p>
        </div>
        <div class="quote-print-page-number">${index + 1} / ${result.months.length}</div>
      </header>
      ${renderQuotePrintSummary(result)}
      <table class="quote-plan-table">
        <thead>
          <tr>
            <th>科目</th>
            <th>日期</th>
            <th>回数</th>
            <th>内容</th>
            <th>时长(H)</th>
          </tr>
        </thead>
        <tbody>
          ${renderGroupedMonthRows(month.rows)}
        </tbody>
      </table>
      <footer class="quote-print-footer">
        <div><span>月度课时</span><strong>${formatHours(month.totalHours)} H</strong></div>
        <div><span>月度合计</span><strong>${formatCurrency(month.totalJpy, "JPY")}</strong></div>
        <div><span>人民币参考</span><strong>${formatCurrency(month.totalCny, "CNY")}</strong></div>
      </footer>
      ${draft.note ? `<p class="quote-print-note">${escapeHtml(draft.note)}</p>` : ""}
    </article>
  `).join("");
}

function renderQuotePrintSummary(result) {
  return `
    <section class="quote-print-summary" aria-label="报价合计">
      <div><span>报价月份</span><strong>${formatNumber(result.months.length)} 个月</strong></div>
      <div><span>总课时</span><strong>${formatHours(result.grandTotalHours)} H</strong></div>
      <div><span>报价合计</span><strong>${formatCurrency(result.grandTotalJpy, "JPY")}</strong></div>
      <div><span>人民币参考</span><strong>${formatCurrency(result.grandTotalCny, "CNY")}</strong></div>
    </section>
  `;
}

function renderGroupedMonthRows(rows) {
  return groupRowsByCourse(rows).map((group) => `
    <tr class="quote-course-group-row">
      <td colspan="5">${escapeHtml(group.courseName)}</td>
    </tr>
    ${group.rows.map((row) => `
      <tr>
        <td>${escapeHtml(row.courseName)}</td>
        <td>${escapeHtml(row.weekLabel)}</td>
        <td>第${formatNumber(row.lessonNumber)}回</td>
        <td>${escapeHtml(row.content)}</td>
        <td>
          <span class="quote-row-hours">
            <span>${formatHours(row.hours)}</span>
            <button class="quote-plan-row-delete-button" type="button" data-quote-delete-row-key="${escapeAttribute(row.rowKey)}">删除</button>
          </span>
        </td>
      </tr>
    `).join("")}
  `).join("");
}

function buildQuoteRowKey(courseIndex, monday, occurrenceIndex) {
  return [
    "course",
    courseIndex,
    "date",
    toDateInputValue(monday),
    "slot",
    occurrenceIndex,
  ].join(":");
}

function groupRowsByCourse(rows) {
  const groups = [];
  const groupMap = new Map();

  rows.forEach((row) => {
    const key = row.courseName || "未命名课程";
    if (!groupMap.has(key)) {
      const group = {
        courseName: key,
        rows: [],
      };
      groupMap.set(key, group);
      groups.push(group);
    }
    groupMap.get(key).rows.push(row);
  });

  return groups;
}

function listMondays(startDate, endDate) {
  const firstMonday = new Date(startDate);
  const day = firstMonday.getDay();
  const offset = day === 1 ? 0 : (8 - day) % 7 || 7;
  firstMonday.setDate(firstMonday.getDate() + offset);

  const mondays = [];
  for (const date = new Date(firstMonday); date <= endDate; date.setDate(date.getDate() + 7)) {
    mondays.push(new Date(date));
  }
  return mondays;
}

function getTodayDateValue() {
  return toDateInputValue(new Date());
}

function getDefaultEndDateValue() {
  const now = new Date();
  now.setMonth(now.getMonth() + 4);
  return toDateInputValue(now);
}

function parseDateValue(value) {
  if (!value) return null;
  const [year, month, day] = value.split("-").map(Number);
  if (!year || !month || !day) return null;
  return new Date(year, month - 1, day);
}

function toDateInputValue(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getMonthKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function formatMonthLabel(date) {
  return `${date.getFullYear()}年${date.getMonth() + 1}月`;
}

function formatWeekLabel(date) {
  return `${date.getMonth() + 1}.${date.getDate()}周`;
}

function formatDateForDisplay(value) {
  const date = parseDateValue(value);
  if (!date) return "-";
  return `${date.getFullYear()}.${date.getMonth() + 1}.${date.getDate()}`;
}

function toPositiveNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function toStrictPositiveNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function toPositiveInteger(value, fallback) {
  const number = Math.floor(Number(value));
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function toInputNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? String(number) : String(fallback);
}

function formatHours(value) {
  const number = Number(value) || 0;
  return Number.isInteger(number) ? String(number) : number.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

function formatCurrency(value, currency) {
  const number = Math.round(Number(value) || 0);
  return `${number.toLocaleString("ja-JP")} ${currency}`;
}

function formatRateValue(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "";
  return number.toFixed(7).replace(/0+$/, "").replace(/\.$/, "");
}

function formatNumber(value) {
  return (Number(value) || 0).toLocaleString("ja-JP");
}

function showMessage(message, type = "info") {
  if (!dom.messageArea) return;
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = message;
}

function hideMessage() {
  if (!dom.messageArea) return;
  dom.messageArea.className = "message is-hidden";
  dom.messageArea.textContent = "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
