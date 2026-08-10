import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  isLessonTimeValue,
  validateLessonTimeGrid,
} from "../js/utils/lesson-time-grid.js";
import { lessonUserErrorMessage } from "../js/utils/lesson-error-message.js";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), "utf8");

const validRanges = [
  ["14:00", "16:00"],
  ["14:15", "16:15"],
  ["14:30", "16:30"],
  ["14:45", "16:45"],
];
for (const [startTime, endTime] of validRanges) {
  assert.equal(validateLessonTimeGrid(startTime, endTime).status, "valid");
}

const invalidRanges = [
  ["14:40", "16:40"],
  ["14:45", "16:40"],
  ["14:40", "16:45"],
];
for (const [startTime, endTime] of invalidRanges) {
  const result = validateLessonTimeGrid(startTime, endTime);
  assert.equal(result.status, "error");
  assert.equal(result.code, "LESSON_TIME_GRID_INVALID");
  assert.match(result.message, /00、15、30、45/);
  assert.doesNotMatch(result.message, /请稍后重试/);
}

assert.equal(isLessonTimeValue("14:40"), true);
assert.equal(isLessonTimeValue("24:00"), false);
assert.equal(validateLessonTimeGrid("", "").status, "incomplete");
assert.equal(validateLessonTimeGrid("14:45", "").status, "incomplete");
const reversedRange = validateLessonTimeGrid("14:45", "14:30");
assert.equal(reversedRange.status, "error");
assert.equal(reversedRange.code, "LESSON_TIME_RANGE_INVALID");
assert.match(reversedRange.message, /结束时间必须晚于开始时间/);

let mockWriterCalls = 0;
async function guardedMockSubmit(startTime, endTime) {
  const result = validateLessonTimeGrid(startTime, endTime);
  if (result.status !== "valid") return result;
  mockWriterCalls += 1;
  return { status: "submitted" };
}

const originalStart = "14:40";
const originalEnd = "16:40";
const blocked = await guardedMockSubmit(originalStart, originalEnd);
assert.equal(blocked.code, "LESSON_TIME_GRID_INVALID");
assert.equal(mockWriterCalls, 0);
assert.equal(originalStart, "14:40");
assert.equal(originalEnd, "16:40");

await guardedMockSubmit("14:45", "16:45");
assert.equal(mockWriterCalls, 1);

const mappedFromMessage = lessonUserErrorMessage({
  message: "LESSON_TIME_GRID_INVALID",
  code: "22023",
});
assert.match(mappedFromMessage, /15分钟刻度规则/);
assert.match(mappedFromMessage, /重复提交不会解决/);
assert.doesNotMatch(mappedFromMessage, /请稍后重试|school_lesson_writer_p0_validate_row|school_lesson_records/);

const mappedFromDetails = lessonUserErrorMessage({
  message: "database rejected request",
  details: "LESSON_TIME_GRID_INVALID at internal validation",
  code: "22023",
});
assert.equal(mappedFromDetails, mappedFromMessage);

const other22023Fallback = "其他参数不符合要求。";
assert.equal(
  lessonUserErrorMessage({ message: "other business validation", code: "22023" }, other22023Fallback),
  other22023Fallback
);
assert.equal(lessonUserErrorMessage(new Error("保留现有中文业务提示。")), "保留现有中文业务提示。");

const lessonHtml = read("lesson.html");
const lessonDetailHtml = read("lesson-detail.html");
const lessonPage = read("js/pages/lesson-page.js");
const lessonEditDialog = read("js/components/lesson-edit-dialog.js");
const gridModule = read("js/utils/lesson-time-grid.js");
const partTimeHtml = read("part-time-work.html");

const mainHtmlTimeInputs = [...`${lessonHtml}\n${lessonDetailHtml}`.matchAll(/<input\b[^>]*\btype="time"[^>]*>/g)].map((match) => match[0]);
assert.equal(mainHtmlTimeInputs.length, 14);
for (const input of mainHtmlTimeInputs) {
  assert.match(input, /\bstep="900"/);
}
assert.equal((lessonPage.match(/<input type="time" step="900"/g) || []).length, 2);
assert.equal((`${lessonHtml}\n${lessonDetailHtml}`.match(/lesson-time-grid-hint/g) || []).length, 7);
assert.match(lessonPage, /lesson-time-grid-hint/);
assert.match(lessonPage, /else if \(timeCheck\.status === "error"\)/);
assert.match(lessonPage, /validateLessonTimeGrid\(startText, endText\)/);
assert.match(lessonEditDialog, /validateLessonTimeGrid\(startText, endText\)/);
assert.doesNotMatch(gridModule, /Math\.(?:round|floor|ceil|trunc)/);
assert.doesNotMatch(partTimeHtml, /lesson-time-grid-hint|step="900"/);

console.log("lesson time grid frontend tests passed");
