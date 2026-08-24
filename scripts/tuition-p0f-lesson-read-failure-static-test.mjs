import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const api = read("js/api/lesson-api.js");
const detailApi = read("js/api/lesson-detail-api.js");
const page = read("js/pages/lesson-page.js");
const detailPage = read("js/pages/lesson-detail-page.js");
const historyStateModule = await import("../js/utils/lesson-tuition-history-state.js");
const app = read("js/lesson-app.js");
const html = read("lesson.html");
const acl = read("sql/current/school_tuition_p0f_lesson_history_reader_anon_acl_fix_20260803.sql");
const postdeploy = read("sql/current/school_tuition_p0f_school_postdeploy_20260803.sql");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(
  acl.includes("grant execute on function public.school_get_planned_lesson_tuition_history_state(uuid[])")
    && acl.includes("to anon,authenticated,service_role"),
  "anon must receive execute only on the stable lesson history reader"
);
assert(!/\b(insert|update|delete|truncate|alter table|create table)\b/i.test(acl), "ACL fix must not contain business DML or table DDL");
assert(acl.includes("p.provolatile <> 's'") && acl.includes("not p.prosecdef"), "ACL fix must verify stable/security-definer contract");
assert(acl.includes("search_path=pg_catalog, public"), "ACL fix must verify fixed search_path");
assert(postdeploy.includes("school_void_planned_lesson_after_tuition_void") && postdeploy.includes("school_set_student_settlement_source_treatment_draft"), "postdeploy must retain anon writer/helper denial checks");

assert(api.includes('supabase.rpc(\n    "school_get_planned_lesson_tuition_history_state"'), "API layer must call the history reader");
assert(api.includes("mergeLessonTuitionHistoryStates(records, [], true)"), "list API must fail closed when the auxiliary reader fails");
assert(detailApi.includes("mergeLessonTuitionHistoryState(lesson, [], true)"), "detail API must fail closed when the auxiliary reader fails");
assert(page.includes("课时历史状态暂时无法读取，相关修改操作已隐藏。"), "page must show the required degraded-read warning");
assert((page.match(/tuition_history_state_available === false/g) || []).length >= 4, "page must hide edit/delete/void and show warning when history state is unavailable");
assert(detailPage.includes("tuition_history_state_available === false"), "detail page must hide mutation actions when history state is unavailable");
assert(page.includes('console.error("Lesson management initial load failed", error)'), "main reader failures must remain visible and must not be swallowed");
assert(!page.includes(".rpc("), "page module must not call RPC directly");
assert(!/\.(insert|update|delete|upsert)\s*\(/.test(page), "page module must not perform direct row writes");

// Historical cache-key literals are intentionally not asserted; resource references remain covered (handoff section 8.6).
assert(html.includes("lesson-app.js"), "lesson HTML must load the lesson app resource");
assert(app.includes("config.js") && app.includes("lesson-page.js"), "app must retain config and page resource imports");
assert(page.includes("lesson-api.js"), "page must retain the lesson API resource import");

const sampleRecords = [
  { id: "planned-1", lesson_type: "planned" },
  { id: "actual-1", lesson_type: "actual" },
];
const degraded = historyStateModule.mergeLessonTuitionHistoryStates(sampleRecords, [], true);
assert(degraded.length === 2, "auxiliary reader failure must preserve the main reader rows");
assert(degraded.every((row) => row.tuition_history_state_available === false), "auxiliary reader failure must hide actions for every row");
assert(degraded.every((row) => row.tuition_revision_count === null), "auxiliary reader failure must not invent revision counts");

const incomplete = historyStateModule.mergeLessonTuitionHistoryStates(sampleRecords, []);
assert(incomplete.every((row) => row.tuition_history_state_available === false), "incomplete auxiliary results must fail closed");

const normal = historyStateModule.mergeLessonTuitionHistoryStates(sampleRecords, [{
  lesson_id: "planned-1",
  tuition_revision_count: 1,
  voided_tuition_revision_count: 1,
  active_tuition_revision_count: 0,
}]);
assert(normal[0].tuition_history_state_available === true, "complete reader results must be usable");
assert(normal[0].tuition_revision_count === 1 && normal[0].active_tuition_revision_count === 0, "DB counts must map without frontend derivation");

console.log("P0F_LESSON_READ_FAILURE_STATIC_TEST_PASSED");
