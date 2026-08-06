import fs from "node:fs";

const read = (path) => fs.readFileSync(path, "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const page = read("js/pages/lesson-page.js");
const lessonApi = read("js/api/lesson-api.js");
const statusApi = read("js/api/student-status-api.js");
const wageApi = read("js/api/wage-api.js");
const detailApi = read("js/api/lesson-detail-api.js");
const editDialog = read("js/components/lesson-edit-dialog.js");
const html = read("lesson.html");
const config = read("js/config.js");
const sql = read("sql/current/school_student_status_phase_b4_lesson_candidate_core_20260806.sql");

assert(!/\.rpc\s*\(/.test(page), "lesson page must not call rpc directly");
assert(!/\.(insert|update|delete|upsert)\s*\(/.test(page), "lesson page must not perform table DML");
assert(!/student\?\.status|student\.status|school_students[^\n]*status/.test(page + editDialog + lessonApi), "lesson candidate code must not use legacy student status");
assert(html.includes("lessonIncludeInactiveCheckbox") && html.includes("包含暂停/离校学生"), "top include-inactive control missing");
assert(html.includes("lessonPdfExportIncludeInactiveCheckbox"), "PDF include-inactive control missing");
assert(page.includes('params.get("include_inactive") === "1"') && page.includes('params.set("include_inactive", "1")'), "lesson URL include_inactive round-trip missing");
assert(page.includes("fetchStudentMonthCandidates") && page.includes("studentMonthCandidateLabel"), "top authoritative month candidates missing");
assert(page.includes("fetchPlannedLessonStudentCandidates") && page.includes("refreshCreatePlannedStudentCandidates"), "single planned authoritative candidate refresh missing");
assert(page.includes("preflightPlannedLessonBatchStudentCandidates") && page.includes("target_occurrences"), "batch DB preflight occurrence use missing");
assert(!page.includes("const dates = listDateInputValues(draft.startDate, draft.endDate)"), "batch preview must not expand occurrence dates in frontend");
assert(editDialog.includes("authoritative_student_month") && editDialog.includes("is_eligible"), "planned edit authority-month candidate contract missing");
assert(editDialog.includes("既有 actual 的学生事实不可在此修改"), "actual student preservation contract missing");
assert(detailApi.includes('.eq("id", studentId)') && !detailApi.includes('select("id,student_code,name,display_name,status")'), "record-ID student lookup must be minimal and status-independent");
assert(statusApi.includes("school_list_student_month_candidates_v1"), "shared student month API missing");
assert(wageApi.includes("fetchStudentMonthCandidates") && !wageApi.includes('supabase.rpc("school_list_student_month_candidates_v1"'), "wage must delegate to shared month-candidate API");
assert(sql.includes("school_expand_planned_lesson_batch_occurrences_v1") && sql.includes("school_preflight_planned_lesson_batch_student_candidates_v1"), "B4 lesson SQL helpers missing");
assert(sql.includes("cross join lateral public.school_expand_planned_lesson_batch_occurrences_v1"), "formal batch writer must use shared occurrence helper");
assert(sql.includes("school_resolve_planned_billing_attribution") && sql.includes("school_resolve_student_status_at_month_core_v1"), "DB authority resolver chain missing");
assert(config.includes('APP_VERSION = "v10.5.14"'), "APP_VERSION must be v10.5.14");

console.log("STUDENT_STATUS_PHASE_B4_LESSON_CANDIDATE_STATIC_TEST_PASS");
