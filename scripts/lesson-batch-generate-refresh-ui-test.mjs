import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const submitStart = source.indexOf("async function handleLessonBatchGenerateSubmit()");
const submitEnd = source.indexOf("\nfunction buildLessonBatchGenerateResultSummary", submitStart);
assert.ok(submitStart >= 0 && submitEnd > submitStart);
const submit = source.slice(submitStart, submitEnd);

assert.match(submit, /const filtersBeforeSubmit = readFilters\(\)/);
assert.match(submit, /const monthBeforeSubmit = filtersBeforeSubmit\?\.month \|\| loadedMonth/);
assert.match(submit, /closeLessonBatchGenerateDialog\(true\)/);
assert.match(submit, /await refreshLessonMonthPreservingFilters\(monthBeforeSubmit, filtersBeforeSubmit\)/);
assert.doesNotMatch(submit, /await loadLessonMonth\(/);
assert.doesNotMatch(submit, /applyCurrentFilters\(\)/);
assert.equal((submit.match(/generatePlannedLessonRecordsBatch\(/g) || []).length, 1);
assert.ok(
  submit.indexOf("generatePlannedLessonRecordsBatch(")
    < submit.indexOf("closeLessonBatchGenerateDialog(true)")
);
assert.match(submit, /预定课时已生成，但列表刷新失败，请手动刷新页面。/);

const refreshStart = source.indexOf("async function refreshLessonMonthPreservingFilters(");
const refreshEnd = source.indexOf("\nfunction setCreateCrossMonthMakeupActualSubmitting", refreshStart);
assert.ok(refreshStart >= 0 && refreshEnd > refreshStart);
const refresh = source.slice(refreshStart, refreshEnd);
assert.match(refresh, /beginLessonRecordsRequest\(\)/);
assert.match(refresh, /loadLessonMonth\(month, nextFilters, requestToken\)/);
assert.match(refresh, /restoreFilterSelections\(nextFilters\)/);
assert.match(refresh, /syncLessonQueryUrl\(nextFilters\)/);
assert.match(refresh, /renderLessonRecords\(filterLessonRecords\(lessonRecords, nextFilters\)\)/);
assert.match(refresh, /refreshLessonManagementStats\(nextFilters, \{ propagateError: true \}\)/);

console.log("lesson batch generate unified refresh contract: PASS");
