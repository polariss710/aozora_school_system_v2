import {
  fetchLessonRecords,
  fetchLessonStudents,
  fetchLessonSubjects,
  fetchLessonTeachers,
} from "../api/lesson-api.js";
import { detectRegusOfficeConflictIds } from "../utils/classroom-capacity.js";

const WEEKDAY_LABELS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const state = { students: [], teachers: [], subjects: [], rows: [], visibleRows: [], conflictIds: new Set() };
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
  dom.venueSelect?.addEventListener("change", applyVenueFilter);
  dom.previousButton?.addEventListener("click", () => shiftWeek(-7));
  dom.currentButton?.addEventListener("click", () => { setWeek(new Date()); loadSchedule(); });
  dom.nextButton?.addEventListener("click", () => shiftWeek(7));
  dom.board?.addEventListener("click", (event) => {
    const card = event.target.closest("[data-lesson-id]");
    if (card) window.location.href = `./lesson-detail.html?id=${encodeURIComponent(card.dataset.lessonId)}`;
  });
}

async function loadLookupsAndSchedule() {
  setLoading(true);
  try {
    [state.students, state.teachers, state.subjects] = await Promise.all([
      fetchLessonStudents(), fetchLessonTeachers(), fetchLessonSubjects(),
    ]);
    await loadSchedule();
  } catch (error) {
    showMessage("error", `读取教室排班失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function loadSchedule() {
  const weekStart = getMonday(parseDate(dom.weekStart.value) || new Date());
  dom.weekStart.value = dateValue(weekStart);
  const weekEnd = addDays(weekStart, 6);
  setLoading(true);
  hideMessage();
  try {
    const rows = (await Promise.all(monthsBetween(weekStart, weekEnd).map(fetchLessonRecords))).flat();
    state.rows = buildEffectiveOnsiteRows(rows, weekStart, weekEnd);
    renderVenueOptions();
    applyVenueFilter();
    showMessage("info", state.rows.length ? "排班已刷新；Regus办公室同一时段出现多组课程时会标红，公共区不限制组数。" : "该周暂无已设置教室的线下课。");
  } catch (error) {
    state.rows = [];
    applyVenueFilter();
    showMessage("error", `读取教室排班失败：${error.message || error}`);
  } finally {
    setLoading(false);
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

function applyVenueFilter() {
  const venue = dom.venueSelect.value;
  state.visibleRows = state.rows.filter((row) => !venue || normalizeVenue(row.lesson_venue) === venue);
  state.conflictIds = detectRegusOfficeConflictIds(state.rows);
  renderBoard();
}

function renderVenueOptions() {
  const selected = dom.venueSelect.value;
  const venues = Array.from(new Map(state.rows.map((row) => [normalizeVenue(row.lesson_venue), safeText(row.lesson_venue)])).entries());
  dom.venueSelect.innerHTML = ['<option value="">全部教室</option>', ...venues.map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)].join("");
  if (venues.some(([value]) => value === selected)) dom.venueSelect.value = selected;
}

function renderBoard() {
  const weekStart = getMonday(parseDate(dom.weekStart.value) || new Date());
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

function shiftWeek(days) { setWeek(addDays(parseDate(dom.weekStart.value) || new Date(), days)); loadSchedule(); }
function setWeek(date) { dom.weekStart.value = dateValue(getMonday(date)); }
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
