import {
  fetchLessonRecords,
  fetchLessonStudentsByIds,
  fetchLessonSubjects,
  fetchLessonTeachers,
} from "../api/lesson-api.js?v=phase-b4-remaining-20260807-1";
import { detectRegusOfficeConflictIds } from "../utils/classroom-capacity.js";

const WEEKDAY_LABELS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const RESET_MESSAGE = "已重置筛选条件；点击“查询”后刷新结果。";
const PENDING_MESSAGE = "筛选条件已变更；点击“查询”后刷新结果。";
const state = {
  students: [], teachers: [], subjects: [], rows: [], visibleRows: [], conflictIds: new Set(),
  appliedFilters: null, requestSequence: 0,
};
const dom = {};

export function initClassroomSchedulePage() {
  cacheDom();
  bindEvents();
  setWeek(new Date());
  loadLookupsAndSchedule();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#classroomScheduleMessageArea");
  dom.form = document.querySelector("#classroomScheduleForm");
  dom.weekStart = document.querySelector("#classroomScheduleWeekStart");
  dom.venueSelect = document.querySelector("#classroomScheduleVenueSelect");
  dom.previousButton = document.querySelector("#classroomSchedulePreviousButton");
  dom.currentButton = document.querySelector("#classroomScheduleCurrentButton");
  dom.nextButton = document.querySelector("#classroomScheduleNextButton");
  dom.loadButton = document.querySelector("#classroomScheduleLoadButton");
  dom.resetButton = document.querySelector("#classroomScheduleResetButton");
  dom.lessonCount = document.querySelector("#classroomScheduleLessonCount");
  dom.venueCount = document.querySelector("#classroomScheduleVenueCount");
  dom.conflictCount = document.querySelector("#classroomScheduleConflictCount");
  dom.rangeTitle = document.querySelector("#classroomScheduleRangeTitle");
  dom.conflictSummary = document.querySelector("#classroomScheduleConflictSummary");
  dom.loadingState = document.querySelector("#classroomScheduleLoadingState");
  dom.emptyState = document.querySelector("#classroomScheduleEmptyState");
  dom.board = document.querySelector("#classroomScheduleBoard");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => { event.preventDefault(); loadSchedule(); });
  dom.weekStart?.addEventListener("change", handleDraftFilterChange);
  dom.venueSelect?.addEventListener("change", handleDraftFilterChange);
  dom.previousButton?.addEventListener("click", () => shiftWeek(-7));
  dom.currentButton?.addEventListener("click", () => { setWeek(new Date()); handleDraftFilterChange(); });
  dom.nextButton?.addEventListener("click", () => shiftWeek(7));
  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    clearQueryResults();
    showMessage("info", RESET_MESSAGE);
  });
  dom.board?.addEventListener("click", (event) => {
    const card = event.target.closest("[data-lesson-id]");
    if (card) window.location.href = `./lesson-detail.html?id=${encodeURIComponent(card.dataset.lessonId)}`;
  });
}

async function loadLookupsAndSchedule() {
  const initializationGeneration = state.requestSequence;
  setLoading(true);
  try {
    [state.teachers, state.subjects] = await Promise.all([
      fetchLessonTeachers(), fetchLessonSubjects(),
    ]);
    if (initializationGeneration !== state.requestSequence) return;
    await loadSchedule();
  } catch (error) {
    if (initializationGeneration !== state.requestSequence) return;
    showMessage("error", `读取教室排班失败：${error.message || error}`);
  } finally {
    if (initializationGeneration === state.requestSequence) setLoading(false);
  }
}

async function loadSchedule() {
  const weekStart = getMonday(parseDate(dom.weekStart.value) || new Date());
  dom.weekStart.value = dateValue(weekStart);
  const weekEnd = addDays(weekStart, 6);
  const filters = { weekStart: dateValue(weekStart), venue: dom.venueSelect.value || "" };
  const requestId = ++state.requestSequence;
  setLoading(true);
  hideMessage();
  try {
    const rows = (await Promise.all(monthsBetween(weekStart, weekEnd).map(fetchLessonRecords))).flat();
    if (requestId !== state.requestSequence) return;
    state.rows = buildEffectiveOnsiteRows(rows, weekStart, weekEnd);
    state.students = await fetchLessonStudentsByIds(state.rows.map((row) => row.student_id));
    if (requestId !== state.requestSequence) return;
    filters.venue = renderVenueOptions(filters.venue);
    state.appliedFilters = filters;
    applyVenueFilter(state.appliedFilters);
    showMessage("info", state.rows.length ? "排班已刷新；Regus办公室同一时段出现多组课程时会标红，公共区不限制组数。" : "该周暂无已设置教室的线下课。");
  } catch (error) {
    if (requestId !== state.requestSequence) return;
    state.appliedFilters = null;
    state.rows = [];
    state.students = [];
    resetRenderedSchedule();
    showMessage("error", `读取教室排班失败：${error.message || error}`);
  } finally {
    if (requestId === state.requestSequence) setLoading(false);
  }
}

function buildEffectiveOnsiteRows(rows, weekStart, weekEnd) {
  const start = dateValue(weekStart);
  const end = dateValue(weekEnd);
  const linkedPlannedIds = new Set(rows.filter((row) => row.lesson_type === "actual" && row.planned_lesson_id).map((row) => row.planned_lesson_id));
  return rows.filter((row) => {
    if (row.lesson_date < start || row.lesson_date > end || row.lesson_delivery_mode !== "onsite" || !safeText(row.lesson_venue)) return false;
    if (row.lesson_type === "planned") return !row.voided_at && ["planned", "pending_makeup"].includes(row.status) && !linkedPlannedIds.has(row.id);
    return row.lesson_type === "actual" && ["completed", "makeup_completed"].includes(row.status);
  }).sort(compareRows);
}

function applyVenueFilter(filters = state.appliedFilters) {
  if (!filters) return;
  const venue = filters.venue;
  state.visibleRows = state.rows.filter((row) => !venue || normalizeVenue(row.lesson_venue) === venue);
  state.conflictIds = detectRegusOfficeConflictIds(state.rows);
  renderBoard();
}

function renderVenueOptions(selected = dom.venueSelect.value) {
  const venues = Array.from(new Map(state.rows.map((row) => [normalizeVenue(row.lesson_venue), safeText(row.lesson_venue)])).entries());
  dom.venueSelect.innerHTML = ['<option value="">全部教室</option>', ...venues.map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)].join("");
  if (venues.some(([value]) => value === selected)) dom.venueSelect.value = selected;
  return dom.venueSelect.value || "";
}

function renderBoard() {
  const weekStart = parseDate(state.appliedFilters?.weekStart) || getMonday(new Date());
  const days = Array.from({ length: 7 }, (_, index) => addDays(weekStart, index));
  dom.rangeTitle.textContent = `${fullDate(days[0])} - ${fullDate(days[6])}`;
  dom.lessonCount.textContent = String(state.visibleRows.length);
  dom.venueCount.textContent = String(new Set(state.visibleRows.map((row) => normalizeVenue(row.lesson_venue))).size);
  const visibleConflictCount = state.visibleRows.filter((row) => state.conflictIds.has(row.id)).length;
  dom.conflictCount.textContent = String(visibleConflictCount);
  dom.conflictSummary.textContent = visibleConflictCount ? `发现 ${visibleConflictCount} 节办公室时间冲突课程。` : "办公室同一时段最多 1 组，暂无冲突。";
  dom.emptyState.classList.toggle("is-hidden", state.visibleRows.length > 0);
  dom.board.innerHTML = days.map((day) => renderDay(day, state.visibleRows.filter((row) => row.lesson_date === dateValue(day)))).join("");
}

function renderDay(day, rows) {
  return `<section class="classroom-schedule-day"><header><strong>${escapeHtml(WEEKDAY_LABELS[day.getDay()])}</strong><span>${escapeHtml(`${day.getMonth() + 1}/${day.getDate()}`)}</span></header><div class="classroom-schedule-day-lessons">${rows.length ? rows.map(renderLessonCard).join("") : '<p class="classroom-schedule-day-empty">无课程</p>'}</div></section>`;
}

function renderLessonCard(row) {
  const conflict = state.conflictIds.has(row.id);
  return `<button class="classroom-schedule-lesson${conflict ? " is-conflict" : ""}" type="button" data-lesson-id="${escapeHtml(row.id)}"><span class="classroom-schedule-lesson-time">${escapeHtml(timeRange(row))}</span><strong>${escapeHtml(safeText(row.lesson_venue))}</strong><span>${escapeHtml(subjectName(row.subject_id))} / ${escapeHtml(studentName(row.student_id))}</span><span>${escapeHtml(teacherName(row.teacher_id))}</span>${conflict ? '<em>办公室重叠</em>' : ""}</button>`;
}

function shiftWeek(days) { setWeek(addDays(parseDate(dom.weekStart.value) || new Date(), days)); handleDraftFilterChange(); }
function setWeek(date) { dom.weekStart.value = dateValue(getMonday(date)); }
function setDefaultFilters() { setWeek(new Date()); dom.venueSelect.innerHTML = '<option value="">全部教室</option>'; dom.venueSelect.value = ""; }
function handleDraftFilterChange() { clearQueryResults(); showMessage("info", PENDING_MESSAGE); }
function clearQueryResults() {
  state.requestSequence += 1;
  state.appliedFilters = null;
  state.students = [];
  state.rows = [];
  resetRenderedSchedule();
  setLoading(false);
}
function resetRenderedSchedule() {
  state.visibleRows = [];
  state.conflictIds = new Set();
  dom.lessonCount.textContent = "0";
  dom.venueCount.textContent = "0";
  dom.conflictCount.textContent = "0";
  dom.rangeTitle.textContent = "本周排班";
  dom.conflictSummary.textContent = "办公室同一时段最多 1 组。";
  dom.emptyState.classList.remove("is-hidden");
  dom.board.innerHTML = "";
}
function setLoading(value) { if (dom.loadButton) dom.loadButton.disabled = value; dom.loadingState?.classList.toggle("is-hidden", !value); }
function showMessage(type, message) { dom.messageArea.className = `message message-${type}`; dom.messageArea.textContent = message; }
function hideMessage() { dom.messageArea.className = "message is-hidden"; dom.messageArea.textContent = ""; }
function studentName(id) { const row = state.students.find((item) => item.id === id); return safeText(row?.display_name || row?.name) || "未设置学生"; }
function teacherName(id) { const row = state.teachers.find((item) => item.id === id); return safeText(row?.display_name || row?.name) || "未设置老师"; }
function subjectName(id) { return safeText(state.subjects.find((item) => item.id === id)?.name) || "未设置科目"; }
function compareRows(a, b) { return String(a.lesson_date).localeCompare(String(b.lesson_date)) || String(a.start_time || "").localeCompare(String(b.start_time || "")) || String(a.lesson_venue).localeCompare(String(b.lesson_venue), "zh-Hans-CN"); }
function timeRange(row) { const start = safeText(row.start_time).slice(0, 5); const end = safeText(row.end_time).slice(0, 5); return start && end ? `${start}-${end}` : start || end || "时间未定"; }
function normalizeVenue(value) { return safeText(value).toLocaleLowerCase("zh-CN"); }
function getMonday(date) { const result = new Date(date.getFullYear(), date.getMonth(), date.getDate()); const day = result.getDay(); result.setDate(result.getDate() + (day === 0 ? -6 : 1 - day)); return result; }
function addDays(date, days) { const result = new Date(date); result.setDate(result.getDate() + days); return result; }
function parseDate(value) { const [y, m, d] = safeText(value).split("-").map(Number); return y && m && d ? new Date(y, m - 1, d) : null; }
function dateValue(date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function fullDate(date) { return `${date.getFullYear()}.${date.getMonth() + 1}.${date.getDate()}`; }
function monthsBetween(start, end) { const values = []; const cursor = new Date(start.getFullYear(), start.getMonth(), 1); const last = new Date(end.getFullYear(), end.getMonth(), 1); while (cursor <= last) { values.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`); cursor.setMonth(cursor.getMonth() + 1); } return values; }
function safeText(value) { return String(value ?? "").trim(); }
function escapeHtml(value) { return safeText(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;"); }
