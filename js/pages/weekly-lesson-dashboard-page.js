import { fetchLessonStudents, fetchWeeklyLessonOperations } from "../api/lesson-api.js";
import { safeText } from "../utils/format.js";

const dom = {};
let students = [];

export function initWeeklyLessonDashboardPage() {
  cacheDom();
  bindEvents();
  setWeekFromQueryOrToday();
  fetchLessonStudents()
    .then((rows) => { students = rows || []; return loadDashboard(); })
    .catch((error) => showMessage("error", `读取本周课时失败：${error.message || error}`));
}

function cacheDom() {
  dom.message = document.querySelector("#weeklyLessonDashboardMessage");
  dom.form = document.querySelector("#weeklyLessonDashboardForm");
  dom.weekStart = document.querySelector("#weeklyLessonDashboardWeekStart");
  dom.previous = document.querySelector("#weeklyLessonDashboardPrevious");
  dom.next = document.querySelector("#weeklyLessonDashboardNext");
  dom.rows = document.querySelector("#weeklyLessonDashboardRows");
  dom.empty = document.querySelector("#weeklyLessonDashboardEmpty");
  dom.loading = document.querySelector("#weeklyLessonDashboardLoading");
  dom.plannedHours = document.querySelector("#weeklyLessonDashboardPlannedHours");
  dom.unregisteredCount = document.querySelector("#weeklyLessonDashboardUnregisteredCount");
  dom.creditHours = document.querySelector("#weeklyLessonDashboardCreditHours");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => { event.preventDefault(); loadDashboard(); });
  dom.previous?.addEventListener("click", () => shiftWeek(-7));
  dom.next?.addEventListener("click", () => shiftWeek(7));
}

function setWeekFromQueryOrToday() {
  const initial = new URLSearchParams(window.location.search).get("week_start");
  const date = /^\d{4}-\d{2}-\d{2}$/.test(initial || "") ? new Date(`${initial}T00:00:00`) : new Date();
  dom.weekStart.value = dateValue(monday(date));
}

function shiftWeek(days) { const date = new Date(`${dom.weekStart.value}T00:00:00`); date.setDate(date.getDate() + days); dom.weekStart.value = dateValue(monday(date)); loadDashboard(); }

async function loadDashboard() {
  const weekStart = dateValue(monday(new Date(`${dom.weekStart.value}T00:00:00`)));
  if (!weekStart) return;
  dom.weekStart.value = weekStart;
  setLoading(true); hideMessage();
  try {
    const rows = await fetchWeeklyLessonOperations(weekStart);
    renderRows(rows);
    syncUrl(weekStart);
  } catch (error) { renderRows([]); showMessage("error", `读取本周课时失败：${error.message || error}`); }
  finally { setLoading(false); }
}

function renderRows(rows) {
  const values = rows || [];
  const totals = values.reduce((sum, row) => ({
    planned: sum.planned + number(row.weekly_planned_hours),
    unregistered: sum.unregistered + number(row.overdue_unregistered_count) + number(row.upcoming_unregistered_count),
    credit: sum.credit + number(row.open_credit_hours),
  }), { planned: 0, unregistered: 0, credit: 0 });
  dom.plannedHours.textContent = displayHours(totals.planned);
  dom.unregisteredCount.textContent = String(totals.unregistered);
  dom.creditHours.textContent = displayHours(totals.credit);
  dom.empty.classList.toggle("is-hidden", values.length > 0);
  dom.rows.innerHTML = values.map((row) => {
    const student = students.find((item) => item.id === row.student_id);
    const name = safeText(student?.display_name || student?.name) || "未设置学生";
    const unregistered = number(row.overdue_unregistered_count) + number(row.upcoming_unregistered_count);
    const params = new URLSearchParams({ year: dom.weekStart.value.slice(0, 4), month: dom.weekStart.value.slice(5, 7), week_start: dom.weekStart.value, student_id: row.student_id || "" });
    return `<tr><td>${escapeHtml(name)}</td><td>${number(row.weekly_planned_count)} 节 / ${displayHours(row.weekly_planned_hours)}</td><td>${number(row.weekly_registered_count)} 节</td><td>${displayHours(row.weekly_completed_hours)}</td><td>${unregistered}</td><td>${number(row.weekly_cancelled_count)}</td><td>${number(row.open_credit_source_count)}</td><td>${displayHours(row.open_credit_hours)}</td><td>${escapeHtml(row.oldest_credit_date || "-")}</td><td><a class="button table-action-button" href="./lesson.html?${params.toString()}">查看课时</a></td></tr>`;
  }).join("");
}

function number(value) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function displayHours(value) { return `${number(value).toLocaleString("zh-CN", { maximumFractionDigits: 2 })} 小时`; }
function monday(date) { if (Number.isNaN(date?.getTime())) return new Date(); const result = new Date(date); result.setHours(0, 0, 0, 0); result.setDate(result.getDate() - ((result.getDay() + 6) % 7)); return result; }
function dateValue(date) { if (!date || Number.isNaN(date.getTime())) return ""; return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function syncUrl(weekStart) { const params = new URLSearchParams({ week_start: weekStart }); window.history?.replaceState?.(null, "", `${window.location.pathname}?${params.toString()}`); }
function setLoading(value) { dom.loading.classList.toggle("is-hidden", !value); }
function showMessage(type, text) { dom.message.className = `message message-${type}`; dom.message.textContent = text; }
function hideMessage() { dom.message.className = "message is-hidden"; dom.message.textContent = ""; }
function escapeHtml(value) { return safeText(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#39;"); }
