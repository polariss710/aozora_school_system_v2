import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { buildWageDutyReport } from "../js/utils/wage-duty-report-export.js";

const highLock = {
  settlement_month: "2026-07",
  teacher_name: "高若天",
  pay_hours: 16,
  lesson_wage_jpy: 64000,
  fee_jpy: 0,
  total_jpy: 64000,
};
const highDetails = [
  ["68f7cc0f-231b-4fa1-985a-5ecfac59b4e8", "2026-07-05", "16:00", "18:00", "makeup_completed", "陈加恩"],
  ["9fe69b4b-c5e9-4392-b926-f47ab59c58f7", "2026-07-05", "18:00", "20:00", "makeup_completed", "陈红卓"],
  ["bd2a4520-a348-47cd-846f-83166304dd5d", "2026-07-06", "16:00", "18:00", "completed", "陈加恩"],
  ["44ea863f-2f4c-40e5-881a-70e3b7e5b27e", "2026-07-12", "13:00", "15:00", "completed", "陈红卓"],
  ["3d9481aa-67e0-4707-bc01-14748f2dcdbd", "2026-07-19", "15:00", "17:00", "completed", "陈红卓"],
  ["292dcccf-2611-4472-8083-e84efaec0480", "2026-07-19", "17:00", "19:00", "completed", "陈加恩"],
  ["15c029c4-a02f-4b19-ac3b-781e43d82f8b", "2026-07-27", "15:00", "17:00", "completed", "陈红卓"],
  ["f5dca0c1-a553-46dd-99b0-59d6b6753009", "2026-07-27", "19:00", "21:00", "completed", "陈加恩"],
].map(([lessonRecordId, lessonDate, startTime, endTime, status, studentName]) => ({
  lesson_record_id: lessonRecordId,
  lesson_date: lessonDate,
  start_time: startTime,
  end_time: endTime,
  status,
  student_name: studentName,
  subject_name: "EJU文综",
  lesson_content: "EJU文综",
  pay_hours: 2,
  lesson_wage_jpy: 8000,
  transport_fee_jpy: 0,
  classroom_fee_jpy: 0,
  is_no_wage: false,
}));

const highReport = buildWageDutyReport(highLock, highDetails);
assert.equal(highReport.rows.length, 46);
assert.deepEqual(
  highReport.rows.slice(4, 12).map((row) => [row[0], row[4], row[5], row[6]]),
  [
    ["2026/07/05（日）", "16:00", "18:00", 2],
    ["2026/07/05（日）", "18:00", "20:00", 2],
    ["2026/07/06（月）", "16:00", "18:00", 2],
    ["2026/07/12（日）", "13:00", "15:00", 2],
    ["2026/07/19（日）", "15:00", "17:00", 2],
    ["2026/07/19（日）", "17:00", "19:00", 2],
    ["2026/07/27（月）", "15:00", "17:00", 2],
    ["2026/07/27（月）", "19:00", "21:00", 2],
  ]
);
assert.deepEqual(highReport.rows[35].slice(6, 9), [
  { f: "SUM(G5:G35)" },
  { f: "SUM(H5:H35)" },
  { f: "SUM(I5:I35)" },
]);
assert.equal(
  highReport.rows[36][0],
  "合计：结算课时 16 / 课时工资 JPY 64,000 / 费用 JPY 0 / 合计 JPY 64,000"
);

const noWageReport = buildWageDutyReport({
  settlement_month: "2026-07",
  teacher_name: "吴峰",
  pay_hours: 0,
  lesson_wage_jpy: 0,
  fee_jpy: 0,
  total_jpy: 0,
}, [{
  lesson_record_id: "145a8219-0fcf-4e0b-8230-c6a092668836",
  lesson_date: "2026-07-31",
  start_time: "13:00",
  end_time: "13:30",
  status: "makeup_completed",
  student_name: "彭宇晗",
  subject_name: "EJU日语",
  lesson_content: "EJU日语",
  pay_hours: 0,
  lesson_wage_jpy: 0,
  transport_fee_jpy: 0,
  classroom_fee_jpy: 0,
  is_no_wage: true,
}]);
assert.equal(noWageReport.rows[4][0], "2026/07/31（金）");
assert.equal(noWageReport.rows[4][6], 0);
assert.equal(noWageReport.rows[36][0], "合计：结算课时 0 / 课时工资 JPY 0 / 费用 JPY 0 / 合计 JPY 0");

const otherTeacherReport = buildWageDutyReport({
  settlement_month: "2026-07",
  teacher_name: "王亚楠",
  pay_hours: 14,
  lesson_wage_jpy: 77000,
  fee_jpy: 0,
  total_jpy: 77000,
}, []);
assert.equal(
  otherTeacherReport.rows[36][0],
  "合计：结算课时 14 / 课时工资 JPY 77,000 / 费用 JPY 0 / 合计 JPY 77,000"
);

const exportSource = readFileSync("js/utils/wage-duty-report-export.js", "utf8");
assert.match(exportSource, /dutyDateText\(detail\.lesson_date\)/);
assert.match(exportSource, /safeText\(a\.lesson_date\)\.localeCompare\(safeText\(b\.lesson_date\)\)/);
assert.doesNotMatch(exportSource, /系统快照合计|内部范围\$\{/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

console.log("WAGE_DUTY_REPORT_EXPORT_TEST_PASS");
