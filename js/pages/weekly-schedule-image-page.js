import {
  fetchLessonRecords,
  fetchLessonStudentsByIds,
  fetchLessonSubjects,
  fetchLessonTeachers,
} from "../api/lesson-api.js?v=phase-b4-remaining-20260807-1";
import {
  fetchStudentRangeCandidates,
  readStudentCandidateQuery,
  renderStudentRangeCandidateOptions,
  writeStudentCandidateQuery,
} from "../api/student-status-api.js?v=phase-b4-remaining-20260807-1";

const WEEKDAY_LABELS = ["日", "一", "二", "三", "四", "五", "六"];
const IMAGE_WIDTH = 1080;
const IMAGE_PADDING = 64;
const CARD_RADIUS = 28;
const RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";
const PENDING_MESSAGE = "筛选条件已变更；点击“查询”后刷新结果。";

const state = {
  students: [],
  studentCandidates: [],
  teachers: [],
  subjects: [],
  schedules: [],
  initialWeekStart: "",
  initialStudentId: "",
  initialIncludeInactive: false,
  appliedFilters: null,
  mainRequestSequence: 0,
  candidateRequestSequence: 0,
};

const dom = {};

export function initWeeklyScheduleImagePage() {
  cacheDom();
  readInitialQuery();
  bindEvents();
  setDefaultWeek();
  const initializationGeneration = state.mainRequestSequence;
  loadLookups()
    .then(() => {
      if (initializationGeneration !== state.mainRequestSequence) return false;
      return refreshStudentCandidates(state.initialStudentId);
    })
    .then((isCurrent) => {
      if (isCurrent === false || initializationGeneration !== state.mainRequestSequence) return;
      return loadSchedules();
    })
    .catch((error) => {
      if (initializationGeneration !== state.mainRequestSequence) return;
      showMessage("error", `读取课表基础数据失败：${error.message || error}`);
    });
}

function cacheDom() {
  dom.messageArea = document.querySelector("#weeklyScheduleMessageArea");
  dom.form = document.querySelector("#weeklyScheduleForm");
  dom.weekStartInput = document.querySelector("#weeklyScheduleWeekStart");
  dom.studentSelect = document.querySelector("#weeklyScheduleStudentSelect");
  dom.includeInactiveCheckbox = document.querySelector("#weeklyScheduleIncludeInactiveCheckbox");
  dom.loadButton = document.querySelector("#weeklyScheduleLoadButton");
  dom.resetButton = document.querySelector("#weeklyScheduleResetButton");
  dom.downloadAllButton = document.querySelector("#weeklyScheduleDownloadAllButton");
  dom.countText = document.querySelector("#weeklyScheduleCount");
  dom.preview = document.querySelector("#weeklySchedulePreview");
  dom.emptyState = document.querySelector("#weeklyScheduleEmptyState");
  dom.loadingState = document.querySelector("#weeklyScheduleLoadingState");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => {
    event.preventDefault();
    loadSchedules();
  });

  dom.weekStartInput?.addEventListener("change", handleCandidateScopeChange);
  dom.includeInactiveCheckbox?.addEventListener("change", handleCandidateScopeChange);
  dom.studentSelect?.addEventListener("change", handleDraftFilterChange);

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    clearQueryResults();
    syncDraftUrl();
    showMessage("info", RESET_MESSAGE);
    refreshStudentCandidates("").catch((error) => {
      showMessage("error", `读取本周学生候选失败：${error.message || error}`);
    });
  });

  dom.downloadAllButton?.addEventListener("click", () => {
    downloadAllImages();
  });

  dom.preview?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-download-schedule-index]");
    if (!button) return;

    const index = Number(button.dataset.downloadScheduleIndex);
    const schedule = state.schedules[index];
    if (schedule) {
      downloadScheduleImage(schedule);
    }
  });
}

function setDefaultWeek() {
  if (state.initialWeekStart) {
    dom.weekStartInput.value = state.initialWeekStart;
    return;
  }
  dom.weekStartInput.value = defaultWeekStart();
}

function defaultWeekStart() {
  const today = startOfLocalDay(new Date());
  const nextMonday = getMonday(today);
  if (nextMonday <= today) {
    nextMonday.setDate(nextMonday.getDate() + 7);
  }
  return toDateInputValue(nextMonday);
}

function setDefaultFilters() {
  dom.weekStartInput.value = defaultWeekStart();
  dom.includeInactiveCheckbox.checked = false;
  dom.studentSelect.value = "";
}

function readInitialQuery() {
  const params = new URLSearchParams(window.location.search);
  const weekStart = String(params.get("week_start") || "");
  if (/^\d{4}-\d{2}-\d{2}$/.test(weekStart) && toDateInputValue(getMonday(parseDateInput(weekStart))) === weekStart) {
    state.initialWeekStart = weekStart;
  }
  state.initialStudentId = String(params.get("student_id") || "");
  state.initialIncludeInactive = readStudentCandidateQuery().includeInactive;
  dom.includeInactiveCheckbox.checked = state.initialIncludeInactive;
}

async function loadLookups() {
  setLoading(true);
  try {
    const [teachers, subjects] = await Promise.all([
      fetchLessonTeachers(),
      fetchLessonSubjects(),
    ]);

    state.teachers = teachers || [];
    state.subjects = subjects || [];
  } finally {
    setLoading(false);
  }
}

function handleCandidateScopeChange() {
  handleDraftFilterChange();
  refreshStudentCandidates(dom.studentSelect.value).catch((error) => {
    showMessage("error", `读取本周学生候选失败：${error.message || error}`);
  });
}

function handleDraftFilterChange() {
  clearQueryResults();
  syncDraftUrl();
  showMessage("info", PENDING_MESSAGE);
}

async function refreshStudentCandidates(selectedStudentId = "") {
  const requestId = ++state.candidateRequestSequence;
  const weekStart = parseDateInput(dom.weekStartInput.value);
  if (!weekStart) {
    return false;
  }
  const normalizedWeekStart = getMonday(weekStart);
  const weekEnd = addDays(normalizedWeekStart, 6);
  const candidates = await fetchStudentRangeCandidates({
    startDate: toDateInputValue(normalizedWeekStart),
    endDate: toDateInputValue(weekEnd),
    includeInactive: Boolean(dom.includeInactiveCheckbox.checked),
    selectedStudentId: selectedStudentId || null,
  });
  if (requestId !== state.candidateRequestSequence) return false;
  state.studentCandidates = candidates;
  renderStudentRangeCandidateOptions(dom.studentSelect, candidates, {
    selectedStudentId,
  });
  syncDraftUrl();
  return true;
}

async function loadSchedules() {
  const weekStart = parseDateInput(dom.weekStartInput.value);
  if (!weekStart) {
    showMessage("warning", "请选择周一日期。");
    return;
  }

  const normalizedWeekStart = getMonday(weekStart);
  if (toDateInputValue(normalizedWeekStart) !== dom.weekStartInput.value) {
    dom.weekStartInput.value = toDateInputValue(normalizedWeekStart);
  }

  const weekEnd = addDays(normalizedWeekStart, 6);
  const selectedStudentId = dom.studentSelect.value || "";
  const includeInactive = Boolean(dom.includeInactiveCheckbox.checked);
  const requestId = ++state.mainRequestSequence;
  setLoading(true);
  hideMessage();

  try {
    const candidateRequestIsCurrent = await refreshStudentCandidates(selectedStudentId);
    if (!candidateRequestIsCurrent || requestId !== state.mainRequestSequence) return;
    const months = monthsBetween(normalizedWeekStart, weekEnd);
    const monthRows = await Promise.all(months.map((month) => fetchLessonRecords(month)));
    if (requestId !== state.mainRequestSequence) return;
    const rows = monthRows.flat();
    state.students = await fetchLessonStudentsByIds(rows.map((row) => row.student_id));
    if (requestId !== state.mainRequestSequence) return;
    const schedules = buildSchedules(rows, normalizedWeekStart, weekEnd, selectedStudentId);
    state.schedules = schedules;
    state.appliedFilters = {
      weekStart: toDateInputValue(normalizedWeekStart),
      studentId: selectedStudentId,
      includeInactive,
    };
    renderSchedules();
    syncUrl(normalizedWeekStart, selectedStudentId, includeInactive);

    if (schedules.length) {
      showMessage("success", `已生成 ${schedules.length} 张周课表图片预览。`);
    } else {
      showMessage("info", "该周没有可生成图片的预定课时。");
    }
  } catch (error) {
    if (requestId !== state.mainRequestSequence) return;
    state.schedules = [];
    state.appliedFilters = null;
    renderSchedules();
    showMessage("error", `读取周课表失败：${error.message || error}`);
  } finally {
    if (requestId === state.mainRequestSequence) setLoading(false);
  }
}

function syncUrl(weekStart, studentId, includeInactive) {
  const params = writeStudentCandidateQuery(new URLSearchParams(), {
    studentId,
    includeInactive,
  });
  params.set("week_start", toDateInputValue(weekStart));
  window.history?.replaceState?.(null, "", `${window.location.pathname}?${params.toString()}`);
}

function syncDraftUrl() {
  const weekStart = parseDateInput(dom.weekStartInput.value);
  if (!weekStart) return;
  syncUrl(getMonday(weekStart), dom.studentSelect.value || "", Boolean(dom.includeInactiveCheckbox.checked));
}

function clearQueryResults() {
  state.mainRequestSequence += 1;
  state.candidateRequestSequence += 1;
  state.appliedFilters = null;
  state.students = [];
  state.schedules = [];
  renderSchedules();
  setLoading(false);
}

function buildSchedules(rows, weekStart, weekEnd, selectedStudentId) {
  const startValue = toDateInputValue(weekStart);
  const endValue = toDateInputValue(weekEnd);
  const scheduledRows = rows
    .filter((row) => row.lesson_type === "planned")
    .filter((row) => row.status === "planned")
    .filter((row) => !row.voided_at)
    .filter((row) => row.lesson_date >= startValue && row.lesson_date <= endValue)
    .filter((row) => !selectedStudentId || row.student_id === selectedStudentId)
    .sort(compareLessonRows);

  const rowsByStudentId = new Map();
  scheduledRows.forEach((row) => {
    const key = row.student_id || "unknown";
    if (!rowsByStudentId.has(key)) {
      rowsByStudentId.set(key, []);
    }
    rowsByStudentId.get(key).push(row);
  });

  return Array.from(rowsByStudentId.entries())
    .map(([studentId, lessons]) => {
      const student = state.students.find((row) => row.id === studentId) || { id: studentId, name: "未设置学生" };
      return {
        student,
        lessons,
        weekStart,
        weekEnd,
        title: "青空塾 本周课程表",
      };
    })
    .sort((left, right) => studentName(left.student).localeCompare(studentName(right.student), "zh-Hans-CN"));
}

function renderSchedules() {
  const count = state.schedules.length;
  dom.countText.textContent = `${count} 张`;
  dom.downloadAllButton.disabled = count === 0;
  dom.preview.innerHTML = "";
  dom.emptyState.classList.toggle("is-hidden", count > 0);

  state.schedules.forEach((schedule, index) => {
    const panel = document.createElement("article");
    panel.className = "weekly-schedule-card";

    const header = document.createElement("div");
    header.className = "weekly-schedule-card-header";
    header.innerHTML = `
      <div>
        <h3>${escapeHtml(studentName(schedule.student))}</h3>
        <p>${escapeHtml(formatDateRange(schedule.weekStart, schedule.weekEnd))}</p>
      </div>
      <button class="button" type="button" data-download-schedule-index="${index}">下载 PNG</button>
    `;

    const canvas = document.createElement("canvas");
    canvas.className = "weekly-schedule-canvas";
    drawScheduleCanvas(canvas, schedule);

    panel.append(header, canvas);
    const editList = document.createElement("div");
    editList.className = "weekly-schedule-edit-list";
    editList.innerHTML = `
      <p class="section-note">调整日期或时间后，返回此页重新生成图片。</p>
      ${schedule.lessons.map((lesson) => `
        <a class="button table-action-button" href="${escapeAttribute(buildLessonEditUrl(lesson.id, schedule))}">
          ${escapeHtml(buildLessonEditLabel(lesson))}
        </a>
      `).join("")}
    `;
    panel.append(editList);
    dom.preview.append(panel);
  });
}

function buildLessonEditUrl(lessonId, schedule) {
  const params = new URLSearchParams({
    id: lessonId,
    edit: "1",
    return_to: "weekly_schedule",
    week_start: toDateInputValue(schedule.weekStart),
    student_id: schedule.student.id || "",
  });
  return `./lesson-detail.html?${params.toString()}`;
}

function buildLessonEditLabel(lesson) {
  const timeText = formatTimeRange(lesson);
  const subjectText = subjectNameById(lesson.subject_id);
  const teacherText = teacherNameById(lesson.teacher_id) || "未设置老师";
  return `编辑 ${formatDateOnly(lesson.lesson_date)} · ${timeText} · ${subjectText} · ${teacherText}`;
}

function downloadAllImages() {
  state.schedules.forEach((schedule, index) => {
    window.setTimeout(() => downloadScheduleImage(schedule), index * 120);
  });
}

function downloadScheduleImage(schedule) {
  const canvas = document.createElement("canvas");
  drawScheduleCanvas(canvas, schedule);
  const link = document.createElement("a");
  link.href = canvas.toDataURL("image/png");
  link.download = buildImageFilename(schedule);
  link.click();
}

function drawScheduleCanvas(canvas, schedule) {
  const groupedDays = groupLessonsByDate(schedule.lessons);
  const dayBlocks = groupedDays.map((day) => ({
    ...day,
    height: 104 + day.lessons.length * 102,
  }));
  const contentHeight = dayBlocks.reduce((sum, day) => sum + day.height + 22, 0);
  const canvasHeight = Math.max(760, 268 + contentHeight + 120);
  canvas.width = IMAGE_WIDTH;
  canvas.height = canvasHeight;

  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#f5f7fa";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  drawHeader(ctx, schedule);

  let y = 248;
  dayBlocks.forEach((day) => {
    drawDayBlock(ctx, day, y);
    y += day.height + 22;
  });

  drawFooter(ctx, y + 24);
}

function drawHeader(ctx, schedule) {
  const x = IMAGE_PADDING;
  const width = IMAGE_WIDTH - IMAGE_PADDING * 2;
  drawRoundedRect(ctx, x, 48, width, 154, 34, "#0f766e");

  ctx.fillStyle = "#ecfeff";
  ctx.font = "700 34px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(schedule.title, x + 38, 104);

  ctx.fillStyle = "#ffffff";
  ctx.font = "800 52px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(studentName(schedule.student), x + 38, 162);

  ctx.fillStyle = "#d9f99d";
  ctx.font = "700 28px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(formatDateRange(schedule.weekStart, schedule.weekEnd), x + width - 360, 162);
}

function drawDayBlock(ctx, day, y) {
  const x = IMAGE_PADDING;
  const width = IMAGE_WIDTH - IMAGE_PADDING * 2;
  drawRoundedRect(ctx, x, y, width, day.height, CARD_RADIUS, "#ffffff");

  ctx.fillStyle = "#134e4a";
  ctx.font = "900 31px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(`${formatMonthDay(day.date)} 周${WEEKDAY_LABELS[day.date.getDay()]}`, x + 34, y + 56);

  ctx.fillStyle = "#64748b";
  ctx.font = "700 24px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(`${day.lessons.length} 节课`, x + width - 122, y + 56);

  let rowY = y + 94;
  day.lessons.forEach((lesson) => {
    drawLessonRow(ctx, lesson, x + 30, rowY, width - 60);
    rowY += 102;
  });
}

function drawLessonRow(ctx, lesson, x, y, width) {
  drawRoundedRect(ctx, x, y, width, 82, 18, "#f8fafc");

  ctx.fillStyle = "#0f172a";
  ctx.font = "900 24px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(`东京 ${formatTimeRange(lesson)}`, x + 22, y + 33);

  const beijingTime = formatBeijingTimeRange(lesson);
  if (beijingTime) {
    ctx.fillStyle = "#0f766e";
    ctx.font = "800 21px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
    ctx.fillText(`北京 ${beijingTime}`, x + 22, y + 64);
  }

  ctx.fillStyle = "#111827";
  ctx.font = "900 30px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(truncateText(ctx, subjectNameById(lesson.subject_id), 210), x + 270, y + 50);

  ctx.fillStyle = "#475569";
  ctx.font = "700 24px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  const meta = [
    teacherNameById(lesson.teacher_id),
    formatDuration(lesson.duration_hours),
    formatLessonVenue(lesson.lesson_delivery_mode, lesson.lesson_venue),
    safeText(lesson.lesson_content || lesson.note),
  ].filter(Boolean).join(" / ");
  ctx.fillText(truncateText(ctx, meta, width - 520), x + 510, y + 48);
}

function drawFooter(ctx, y) {
  ctx.fillStyle = "#64748b";
  ctx.font = "700 24px system-ui, -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText("如需调整课程时间，请提前联系老师。", IMAGE_PADDING + 8, y);
}

function groupLessonsByDate(lessons) {
  const map = new Map();
  lessons.forEach((lesson) => {
    if (!map.has(lesson.lesson_date)) {
      map.set(lesson.lesson_date, []);
    }
    map.get(lesson.lesson_date).push(lesson);
  });

  return Array.from(map.entries()).map(([dateValue, rows]) => ({
    date: parseDateInput(dateValue),
    lessons: rows.sort(compareLessonRows),
  }));
}

function compareLessonRows(left, right) {
  return String(left.lesson_date || "").localeCompare(String(right.lesson_date || ""))
    || String(left.start_time || "").localeCompare(String(right.start_time || ""))
    || String(left.end_time || "").localeCompare(String(right.end_time || ""))
    || studentNameById(left.student_id).localeCompare(studentNameById(right.student_id), "zh-Hans-CN")
    || subjectNameById(left.subject_id).localeCompare(subjectNameById(right.subject_id), "zh-Hans-CN");
}

function monthsBetween(startDate, endDate) {
  const months = [];
  const cursor = new Date(startDate.getFullYear(), startDate.getMonth(), 1);
  const last = new Date(endDate.getFullYear(), endDate.getMonth(), 1);
  while (cursor <= last) {
    months.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`);
    cursor.setMonth(cursor.getMonth() + 1);
  }
  return months;
}

function getMonday(date) {
  const result = startOfLocalDay(date);
  const day = result.getDay();
  const offset = day === 0 ? -6 : 1 - day;
  result.setDate(result.getDate() + offset);
  return result;
}

function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function startOfLocalDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function parseDateInput(value) {
  const [year, month, day] = String(value || "").split("-").map(Number);
  if (!year || !month || !day) return null;
  return new Date(year, month - 1, day);
}

function toDateInputValue(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function formatDateRange(start, end) {
  return `${formatFullDate(start)} - ${formatFullDate(end)}`;
}

function formatDateOnly(value) {
  const date = parseDateInput(value);
  return date ? formatFullDate(date) : "日期未定";
}

function formatFullDate(date) {
  return `${date.getFullYear()}.${date.getMonth() + 1}.${date.getDate()}`;
}

function formatMonthDay(date) {
  return `${date.getMonth() + 1}.${date.getDate()}`;
}

function formatTimeRange(lesson) {
  const start = formatTime(lesson.start_time);
  const end = formatTime(lesson.end_time);
  if (start && end) return `${start}-${end}`;
  return start || end || "时间未定";
}

function formatBeijingTimeRange(lesson) {
  if (!safeText(lesson.start_time) && !safeText(lesson.end_time)) {
    return "";
  }
  const start = formatTime(lesson.start_time, -1);
  const end = formatTime(lesson.end_time, -1);
  if (start && end) return `${start}-${end}`;
  return start || end;
}

function formatTime(value, offsetHours = 0) {
  const text = safeText(value);
  if (!text) return "";

  const [hourText, minuteText] = text.slice(0, 5).split(":");
  const hour = Number(hourText);
  const minute = Number(minuteText);
  if (
    !Number.isInteger(hour)
    || !Number.isInteger(minute)
    || hour < 0
    || hour > 23
    || minute < 0
    || minute > 59
  ) {
    return text.slice(0, 5);
  }

  const totalMinutes = (hour * 60 + minute + offsetHours * 60 + 24 * 60) % (24 * 60);
  const shiftedHour = Math.floor(totalMinutes / 60);
  const shiftedMinute = totalMinutes % 60;
  return `${String(shiftedHour).padStart(2, "0")}:${String(shiftedMinute).padStart(2, "0")}`;
}

function formatDuration(value) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) return "";
  const text = Number.isInteger(number) ? String(number) : number.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  return `${text}H`;
}

function formatLessonVenue(mode, venue) {
  const value = safeText(venue);
  if (!mode && !value) return "";
  const label = mode === "onsite" ? "线下" : mode === "online" ? "线上" : "场地";
  return value ? `${label} ${value}` : label;
}

function buildImageFilename(schedule) {
  const name = studentName(schedule.student).replace(/[\\/:*?"<>|]/g, "_");
  return `青空塾_${name}_周课表_${toDateInputValue(schedule.weekStart)}_${toDateInputValue(schedule.weekEnd)}.png`;
}

function drawRoundedRect(ctx, x, y, width, height, radius, fillStyle) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
  ctx.fillStyle = fillStyle;
  ctx.fill();
}

function truncateText(ctx, text, maxWidth) {
  const value = safeText(text);
  if (!value || ctx.measureText(value).width <= maxWidth) return value;
  let result = value;
  while (result.length > 1 && ctx.measureText(`${result}...`).width > maxWidth) {
    result = result.slice(0, -1);
  }
  return `${result}...`;
}

function studentNameById(id) {
  return studentName(state.students.find((student) => student.id === id));
}

function teacherNameById(id) {
  const teacher = state.teachers.find((row) => row.id === id);
  return safeText(teacher?.display_name || teacher?.name);
}

function subjectNameById(id) {
  const subject = state.subjects.find((row) => row.id === id);
  return safeText(subject?.name) || "未设置科目";
}

function studentName(student) {
  return safeText(student?.display_name || student?.name) || "未设置学生";
}

function setLoading(isLoading) {
  dom.loadButton.disabled = isLoading;
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function showMessage(type, message) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = message;
}

function hideMessage() {
  dom.messageArea.className = "message is-hidden";
  dom.messageArea.textContent = "";
}

function safeText(value) {
  return String(value ?? "").trim();
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
