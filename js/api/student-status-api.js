import { supabase } from "../supabase-client.js";

export async function fetchStudentMonthCandidates({
  month,
  includeInactive = false,
  selectedStudentId = null,
}) {
  const normalizedMonth = String(month || "").trim();
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(normalizedMonth)) {
    throw new Error("请选择正确的学生状态月份。");
  }

  const { data, error } = await supabase.rpc("school_list_student_month_candidates_v1", {
    p_target_month: `${normalizedMonth}-01`,
    p_include_inactive: Boolean(includeInactive),
    p_selected_student_id: selectedStudentId || null,
  });

  if (error) {
    throw error;
  }
  return (data || []).map(normalizeStudentMonthCandidate);
}

export async function fetchCurrentStudentMonthCandidates({
  includeInactive = false,
  selectedStudentId = null,
} = {}) {
  const { data, error } = await supabase.rpc("school_list_current_student_month_candidates_v1", {
    p_include_inactive: Boolean(includeInactive),
    p_selected_student_id: selectedStudentId || null,
  });

  if (error) {
    throw error;
  }
  return (data || []).map(normalizeStudentMonthCandidate);
}

export async function fetchStudentRangeCandidates({
  startDate,
  endDate,
  includeInactive = false,
  selectedStudentId = null,
}) {
  const normalizedStartDate = normalizeDateInput(startDate);
  const normalizedEndDate = normalizeDateInput(endDate);
  if (!normalizedStartDate || !normalizedEndDate || normalizedStartDate > normalizedEndDate) {
    throw new Error("请选择正确的学生状态日期范围。");
  }

  const { data, error } = await supabase.rpc("school_list_student_range_candidates_v1", {
    p_start_date: normalizedStartDate,
    p_end_date: normalizedEndDate,
    p_include_inactive: Boolean(includeInactive),
    p_selected_student_id: selectedStudentId || null,
  });

  if (error) {
    throw error;
  }
  return (data || []).map(normalizeStudentRangeCandidate);
}

export function normalizeStudentMonthCandidate(row = {}) {
  return {
    ...row,
    student_id: row.student_id || row.id || "",
    resolved_status: String(row.resolved_status || ""),
  };
}

export function normalizeStudentRangeCandidate(row = {}) {
  return {
    ...row,
    student_id: row.student_id || row.id || "",
    resolved_status: String(row.status_at_end || row.resolved_status || ""),
    is_active_in_range: Boolean(row.is_active_in_range),
  };
}

export function studentMonthCandidateLabel(row = {}) {
  const name = String(row.display_name || row.name || "").trim() || "未设置";
  const code = String(row.student_code || "").trim();
  const base = code ? `${name}（${code}）` : name;
  if (row.resolved_status === "paused") return `${base}｜本月暂停`;
  if (row.resolved_status === "left") return `${base}｜本月已离校`;
  return base;
}

export function studentRangeCandidateLabel(row = {}) {
  const normalized = normalizeStudentRangeCandidate(row);
  const name = String(normalized.display_name || normalized.name || "").trim() || "未设置";
  const code = String(normalized.student_code || "").trim();
  const base = code ? `${name}（${code}）` : name;
  if (normalized.is_active_in_range) return base;
  if (normalized.resolved_status === "paused") return `${base}｜本月暂停`;
  if (normalized.resolved_status === "left") return `${base}｜本月已离校`;
  return base;
}

export function renderStudentMonthCandidateOptions(
  selectElement,
  rows,
  { placeholder = "全部学生", selectedStudentId = "" } = {}
) {
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`];
  for (const rawRow of rows || []) {
    const row = normalizeStudentMonthCandidate(rawRow);
    options.push(
      `<option value="${escapeAttribute(row.student_id)}">${escapeHtml(studentMonthCandidateLabel(row))}</option>`
    );
  }
  selectElement.innerHTML = options.join("");
  selectElement.value = selectedStudentId || "";
}

export function renderStudentRangeCandidateOptions(
  selectElement,
  rows,
  { placeholder = "全部有课学生", selectedStudentId = "" } = {}
) {
  const options = [`<option value="">${escapeHtml(placeholder)}</option>`];
  for (const rawRow of rows || []) {
    const row = normalizeStudentRangeCandidate(rawRow);
    options.push(
      `<option value="${escapeAttribute(row.student_id)}">${escapeHtml(studentRangeCandidateLabel(row))}</option>`
    );
  }
  selectElement.innerHTML = options.join("");
  selectElement.value = selectedStudentId || "";
}

export function readStudentCandidateQuery(search = window.location.search) {
  const params = new URLSearchParams(search);
  return {
    studentId: String(params.get("student_id") || "").trim(),
    includeInactive: params.get("include_inactive") === "1",
  };
}

export function writeStudentCandidateQuery(params, { studentId = "", includeInactive = false } = {}) {
  if (studentId) params.set("student_id", studentId);
  else params.delete("student_id");
  if (includeInactive) params.set("include_inactive", "1");
  else params.delete("include_inactive");
  return params;
}

function normalizeDateInput(value) {
  const text = String(value || "").trim();
  return /^\d{4}-(0[1-9]|1[0-2])-([0-2]\d|3[01])$/.test(text) ? text : "";
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
