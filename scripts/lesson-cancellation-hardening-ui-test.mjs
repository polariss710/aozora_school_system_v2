import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const lessonPage = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");
const lessonDetailPage = readFileSync(new URL("../js/pages/lesson-detail-page.js", import.meta.url), "utf8");
const lessonApi = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const lessonHtml = readFileSync(new URL("../lesson.html", import.meta.url), "utf8");
const lessonApp = readFileSync(new URL("../js/lesson-app.js", import.meta.url), "utf8");
const config = readFileSync(new URL("../js/config.js", import.meta.url), "utf8");
const appCss = readFileSync(new URL("../css/app.css", import.meta.url), "utf8");
const writerSql = readFileSync(
  new URL("../sql/current/school_create_cancelled_actual_lesson_from_planned_rpc.sql", import.meta.url),
  "utf8"
);
const cancelDialogHtml = lessonHtml.slice(
  lessonHtml.indexOf('id="createCancelledActualLessonDialog"'),
  lessonHtml.indexOf('id="createMakeupActualLessonDialog"')
);

function functionSource(name, nextName) {
  const pattern = new RegExp(`(?:async )?function ${name}\\([\\s\\S]*?\\n}\\n\\n(?:async )?function ${nextName}`);
  return lessonPage.match(pattern)?.[0] || "";
}

const openDialog = functionSource(
  "openCreateCancelledActualLessonDialog",
  "closeCreateCancelledActualLessonDialog"
);
const closeDialog = functionSource(
  "closeCreateCancelledActualLessonDialog",
  "resetCreateCancelledActualLessonForm"
);
const renderMissing = functionSource("renderMissingActualCard", "canMarkCancelledActualFromPlanned");
const canMark = functionSource("canMarkCancelledActualFromPlanned", "canGenerateActualFromPlanned");

// The visible action and the open handler now agree on the canonical source.
assert.match(openDialog, /plannedLesson\.status !== "planned"/);
assert.doesNotMatch(openDialog, /plannedLesson\.status !== "pending_makeup"/);
assert.match(openDialog, /currentUserCanMarkLessonCancelled\(\)/);
assert.match(openDialog, /linkedActualForPlannedLesson\(plannedLesson\.id\)/);
assert.match(canMark, /membership\?\.is_active === true|currentUserCanMarkLessonCancelled/);
assert.match(canMark, /planned\.status === "planned"/);
assert.match(canMark, /!linkedActualForPlannedLesson\(planned\.id\)/);

// Ordinary actual remains present; cancellation is role-gated and pending
// makeup renders only the existing makeup-completion action.
assert.match(renderMissing, /data-generate-actual-id/);
assert.match(renderMissing, /canMarkCancelledActualFromPlanned\(planned\)/);
assert.match(renderMissing, /data-generate-cancelled-actual-id/);
assert.match(renderMissing, /planned\.status === "pending_makeup"[\s\S]*data-generate-makeup-actual-id/);

// Opening and closing are UI-only. Writes remain in the explicit submit path.
assert.doesNotMatch(openDialog, /createCancelledActualLessonFromPlanned/);
assert.doesNotMatch(closeDialog, /createCancelledActualLessonFromPlanned/);
assert.match(lessonPage, /await createCancelledActualLessonFromPlanned\(payload\)/);

// Pre-open failures are placed next to the clicked action; submit failures are
// mapped and shown in the dialog rather than only logged or sent off-screen.
assert.match(lessonPage, /dataset\.cancelledActualActionError = "true"/);
assert.match(lessonPage, /errorElement\.scrollIntoView\(\{ block: "nearest" \}\)/);
assert.match(lessonPage, /showCreateCancelledActualLessonError\(message/);
for (const code of [
  "LESSON_CANCELLATION_ROLE_REQUIRED",
  "LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS",
  "LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED",
  "LESSON_CANCELLATION_TEACHER_WAGE_LOCKED",
  "LESSON_FINANCIAL_FACT_IMMUTABLE",
  "SETTLEMENT_UNUSED_CREDIT_SOURCE_ALREADY_CLAIMED",
]) {
  assert.match(lessonPage, new RegExp(code));
}

const errorIndex = cancelDialogHtml.indexOf('id="createCancelledActualLessonError"');
const summaryIndex = cancelDialogHtml.indexOf('id="createCancelledActualLessonSummary"');
assert.ok(errorIndex > 0 && summaryIndex > errorIndex);
assert.match(cancelDialogHtml, /标记取消并转待补课/);
assert.match(cancelDialogHtml, /来源预定课时转为“待补课”/);
assert.match(cancelDialogHtml, /进入待补课余额/);
assert.match(cancelDialogHtml, /不计入老师实际上课工资/);
assert.doesNotMatch(cancelDialogHtml, /不修改原 planned/);
assert.match(cancelDialogHtml, /createCancelledActualLessonStartTimeInput" type="time" step="900"/);
assert.match(cancelDialogHtml, /createCancelledActualLessonEndTimeInput" type="time" step="900"/);
assert.match(cancelDialogHtml, /createCancelledActualLessonDurationInput[^>]*readonly aria-readonly="true"/);

// Page/API and business-calculation boundaries remain closed.
assert.doesNotMatch(lessonPage, /\.rpc\s*\(/);
assert.doesNotMatch(lessonPage, /supabase\.(?:from|rpc)\s*\(/);
assert.match(lessonApi, /supabase\.rpc\("school_create_cancelled_actual_lesson_from_planned"/);
assert.match(lessonApi, /durationHours: Number\.isFinite/);
assert.match(lessonApi, /options\.status === "voided"[\s\S]*\.not\("voided_at", "is", null\)/);
assert.match(lessonApi, /else \{[\s\S]*query = query\.is\("voided_at", null\)/);
assert.doesNotMatch(lessonApi, /options\.status === "voided"[\s\S]{0,160}\.eq\("lesson_type", "planned"\)/);
assert.match(lessonPage, /function isVoidedLesson\(record\)[\s\S]*Boolean\(record && record\.voided_at\)/);
assert.match(lessonPage, /statusFilter === "voided"[\s\S]*return isVoidedLesson\(record\)/);
assert.doesNotMatch(lessonPage, /function isVoidedPlanned/);
assert.match(lessonDetailPage, /function isVoidedLesson\(lesson\)[\s\S]*Boolean\(lesson && lesson\.voided_at\)/);
assert.doesNotMatch(lessonDetailPage, /function isVoidedPlanned/);
assert.match(writerSql, /extract\(epoch from \(v_end_value - v_start_value\)\)::numeric \/ 3600/);
assert.match(writerSql, /p_duration_hours is distinct from v_duration_hours/);
assert.match(writerSql, /actual_minutes, teacher_settlement_month/);

assert.match(config, /APP_VERSION = "v10\.5\.\d+"/);
assert.match(lessonHtml, /<body class="lesson-page">/);
assert.match(lessonHtml, /app\.css\?v=phase-b4-lesson-candidates-20260806/);
assert.match(lessonHtml, /lesson-app\.js\?v=be-ui-20260806-1/);
assert.match(lessonApp, /lesson-page\.js\?v=be-ui-20260806-1/);
assert.match(appCss, /\.lesson-page \.dialog-backdrop\s*\{\s*z-index:\s*1700;/);

console.log("School V2 cancellation hardening UI/API/static contract: PASS");
