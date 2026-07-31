import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  createLatestRequestGate,
  normalizeStudentSettlementWeekStart,
} from "../js/utils/lesson-settlement-filter.js";

const lessonPage = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonApi = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const editDialog = readFileSync(new URL("../js/components/lesson-edit-dialog.js", import.meta.url), "utf8");

// A cross-month natural week belongs to its Monday's settlement month only.
assert.equal(normalizeStudentSettlementWeekStart("2026-07", "2026-07-27"), "2026-07-27");
assert.equal(normalizeStudentSettlementWeekStart("2026-08", "2026-07-27"), "");

// The saved-record refresh uses the pre-save filter snapshot, never the edited
// record date/month, and starts a newest-request gate before reloading records.
const editRefreshFunction = lessonPage.match(
  /async function refreshAfterEditLesson[\s\S]*?\n}\n\nfunction renderValueOptions/
)?.[0] || "";
const sharedRefreshFunction = lessonPage.match(
  /async function refreshLessonMonthPreservingFilters[\s\S]*?\n}\n\nfunction setCreateCrossMonthMakeupActualSubmitting/
)?.[0] || "";
assert.match(editRefreshFunction, /refreshLessonMonthPreservingFilters\(previousFilters\?\.month, previousFilters\)/);
assert.match(sharedRefreshFunction, /previousFilters \? \{ \.\.\.previousFilters } : readFilters\(\)/);
assert.match(sharedRefreshFunction, /beginLessonRecordsRequest\(\)/);
assert.match(sharedRefreshFunction, /loadLessonMonth\(month, nextFilters, requestToken\)/);
assert.match(sharedRefreshFunction, /restoreFilterSelections\(nextFilters\)/);
assert.match(sharedRefreshFunction, /syncLessonQueryUrl\(nextFilters\)/);
assert.match(sharedRefreshFunction, /renderLessonRecords\(filterLessonRecords\(lessonRecords, nextFilters\)\)/);
assert.match(sharedRefreshFunction, /await refreshLessonManagementStats\(nextFilters, \{ propagateError: true }\)/);
assert.doesNotMatch(sharedRefreshFunction, /updatedLesson\.(?:year_month|lesson_date)/);
assert.doesNotMatch(sharedRefreshFunction, /setYearMonthSelectValue/);

// All filters and the current view are captured before the write request.
assert.match(lessonPage, /getRefreshContext:\s*\(\) => readFilters\(\)/);
assert.match(editDialog, /const refreshContext = getRefreshContext\?\.\(\) \|\| null/);
assert.match(editDialog, /await onSaved\(updatedLesson, refreshContext\)/);
assert.match(editDialog, /课时已保存，但列表刷新失败/);
assert.match(editDialog, /请重新查询/);

// Legacy NULL aircon evidence remains NULL: the page does not invent zero and
// the API selects the legacy preserving overload by omitting the rate argument.
assert.match(editDialog, /lesson\.aircon_unit_price_jpy_snapshot !== null/);
assert.match(editDialog, /nullableIntegerFromInput\(dom\.airconRateInput\.value\)/);
assert.match(editDialog, /preservesLegacyNullAirconRate/);
assert.match(
  lessonApi,
  /payload\.lessonType === "planned" && Number\.isInteger\(payload\.airconRateJpyPerHour\)/
);

// API preserves the raw diagnostic error; the UI layer owns safe Chinese mapping.
assert.doesNotMatch(lessonApi, /normalizeLessonMutationError/);

// Page/API boundaries remain intact.
assert.doesNotMatch(lessonPage, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /supabase\.(?:from|rpc)\s*\(/);
assert.doesNotMatch(editDialog, /\.rpc\s*\(/);
assert.match(lessonApi, /school_update_lesson_record_guarded_with_venue/);

// A stale refresh response cannot overwrite a newer query.
const gate = createLatestRequestGate();
const saveRefresh = gate.begin();
const newerQuery = gate.begin();
assert.equal(gate.isCurrent(saveRefresh), false);
assert.equal(gate.isCurrent(newerQuery), true);

console.log("R2-F-E lesson operations UI/API fixtures: PASS");
