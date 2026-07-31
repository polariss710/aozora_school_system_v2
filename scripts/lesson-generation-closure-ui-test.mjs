import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { lessonUserErrorMessage } from "../js/utils/lesson-error-message.js";

const lessonPage = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonApi = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const editDialog = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");
const voidDialog = readFileSync(new URL("../js/components/lesson-void-dialog.js", import.meta.url), "utf8");
const deleteDialog = readFileSync(new URL("../js/components/lesson-delete-dialog.js", import.meta.url), "utf8");

function functionSource(name, nextName) {
  const pattern = new RegExp(`(?:async )?function ${name}\\([\\s\\S]*?\\n}\\n\\n(?:async )?function ${nextName}`);
  return lessonPage.match(pattern)?.[0] || "";
}

// Technical identifiers are retained only in diagnostic errors, never user text.
assert.equal(
  lessonUserErrorMessage(new Error("FUTURE_ACTUAL_COMPLETION_FORBIDDEN")),
  "实际完成日期不能晚于东京当前业务日期。"
);
assert.equal(
  lessonUserErrorMessage(new Error("R2_E_E_BILLED_PLANNED_STATUS_TRANSITION_FORBIDDEN")),
  "已收费课时不允许执行该状态变更。"
);
assert.equal(
  lessonUserErrorMessage(new Error("保存失败（FUTURE_ACTUAL_COMPLETION_FORBIDDEN）")),
  "实际完成日期不能晚于东京当前业务日期。"
);
assert.equal(
  lessonUserErrorMessage(new Error("TypeError: Failed to fetch")),
  "网络连接异常，请检查网络后重试。"
);
assert.equal(
  lessonUserErrorMessage(new Error("R9_UNKNOWN_DATABASE_FAILURE"), "安全中文提示。"),
  "安全中文提示。"
);
assert.equal(lessonUserErrorMessage(new Error("学生月度结算已锁定，不能修改。")), "学生月度结算已锁定，不能修改。");

// Ordinary and partial actual share one handler; makeup and cross-month makeup
// have their own writers. Every successful write closes then refreshes the exact
// pre-submit filter snapshot. A write failure returns before close/refresh.
const actualSubmit = functionSource("handleCreateActualLessonSubmit", "readCreateActualLessonPayload");
assert.match(actualSubmit, /payload\.partial[\s\S]*createPartialCompletedActualFromPlanned[\s\S]*createActualLessonFromPlanned/);
assert.match(actualSubmit, /const filtersBeforeSubmit = readFilters\(\)/);
assert.match(actualSubmit, /catch \(error\)[\s\S]*showCreateActualLessonError[\s\S]*return;/);
assert.match(actualSubmit, /closeCreateActualLessonDialog\(true\)[\s\S]*refreshAfterCreateActualLesson\(createdLesson, filtersBeforeSubmit\)/);
assert.match(actualSubmit, /实际课时已生成，但列表刷新失败，请重新查询。/);

const makeupSubmit = functionSource("handleCreateMakeupActualLessonSubmit", "readCreateMakeupActualLessonPayload");
assert.match(makeupSubmit, /const filtersBeforeSubmit = readFilters\(\)/);
assert.match(makeupSubmit, /catch \(error\)[\s\S]*showCreateMakeupActualLessonError[\s\S]*return;/);
assert.match(makeupSubmit, /closeCreateMakeupActualLessonDialog\(true\)[\s\S]*refreshAfterCreateMakeupActualLesson\(createdLesson, filtersBeforeSubmit\)/);
assert.match(makeupSubmit, /实际课时已生成，但列表刷新失败，请重新查询。/);

const crossMonthSubmit = functionSource("handleCreateCrossMonthMakeupActualSubmit", "readCreateCrossMonthMakeupActualPayload");
assert.match(crossMonthSubmit, /const filtersBeforeSubmit = readFilters\(\)/);
assert.match(crossMonthSubmit, /catch \(error\)[\s\S]*showCreateCrossMonthMakeupActualError[\s\S]*return;/);
assert.match(crossMonthSubmit, /closeCreateCrossMonthMakeupActualDialog\(true\)[\s\S]*refreshAfterCreateCrossMonthMakeupActual\(createdLesson, filtersBeforeSubmit\)/);

const sharedRefresh = functionSource("refreshLessonMonthPreservingFilters", "setCreateCrossMonthMakeupActualSubmitting");
assert.match(sharedRefresh, /const requestToken = beginLessonRecordsRequest\(\)/);
assert.match(sharedRefresh, /loadLessonMonth\(month, nextFilters, requestToken\)/);
assert.match(sharedRefresh, /restoreFilterSelections\(nextFilters\)/);
assert.match(sharedRefresh, /syncLessonQueryUrl\(nextFilters\)/);
assert.match(sharedRefresh, /filterLessonRecords\(lessonRecords, nextFilters\)/);
assert.match(sharedRefresh, /refreshLessonManagementStats\(nextFilters, \{ propagateError: true }\)/);
assert.doesNotMatch(sharedRefresh, /createdLesson|lesson_date|year_month/);

// Changing any filter invalidates list/statistics, starts a newer request gate,
// and does not query until the explicit form submit calls applyQuery.
const invalidation = functionSource("invalidateLessonResultsForFilterChange", "loadLessonMonth");
const invalidationBody = invalidation.replace(/async function loadLessonMonth[\s\S]*/, "");
assert.match(invalidation, /beginLessonRecordsRequest\(\)/);
assert.match(invalidation, /renderLessonRecords\(\[\], \{ emptyMessage:/);
assert.match(invalidation, /筛选条件已变化，请点击“查询”显示结果。/);
assert.doesNotMatch(invalidationBody, /fetchLesson|loadLessonMonth|applyQuery/);
for (const filterName of [
  "weekFilter", "studentSelect", "teacherSelect", "subjectSelect",
  "businessEntitySelect", "lessonTypeSelect", "statusSelect", "billableSelect",
]) {
  assert.match(lessonPage, new RegExp(`dom\\.${filterName}`));
}
assert.match(lessonPage, /dom\.keywordInput\?\.addEventListener\("input", \(\) => invalidateLessonResultsForFilterChange\(\)\)/);
assert.match(lessonPage, /dom\.filterForm\.addEventListener\("submit"[\s\S]*applyQuery\(\)/);

// No page/component write bypass. API is the only RPC boundary.
for (const source of [lessonPage, editDialog, voidDialog, deleteDialog]) {
  assert.doesNotMatch(source, /\.rpc\s*\(/);
  assert.doesNotMatch(source, /supabase\.(?:from|rpc)\s*\(/);
}
assert.match(lessonApi, /school_create_actual_lesson_from_planned/);
assert.match(lessonApi, /school_create_partial_completed_actual_from_planned/);
assert.match(lessonApi, /school_create_lesson_credit_makeup_actual/);

console.log("R2-F-E1 lesson generation refresh/error/filter fixtures: PASS");
