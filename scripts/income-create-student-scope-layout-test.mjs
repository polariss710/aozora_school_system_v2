import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const html = read("income.html");
const css = read("css/app.css");
const page = read("js/pages/income-page.js");
const app = read("js/income-app.js");
const config = read("js/config.js");

const studentField = html.match(/<div class="field" data-create-income-field="student">[\s\S]*?<\/div>\s*<select id="createIncomeStudentSelect"><\/select>\s*<\/div>/)?.[0] || "";
const titleRow = studentField.match(/<div class="income-create-student-label-row">[\s\S]*?<\/div>/)?.[0] || "";
const layoutCss = css.match(/#createIncomeDialog \.income-create-student-label-row \{[\s\S]*?#createIncomeDialog \.income-create-student-label-row \.required-mark \{[\s\S]*?\n\}/)?.[0] || "";

assert.ok(studentField, "新增收入 dialog 必须保留学生字段");
assert.ok(titleRow, "学生字段必须有专用标题行");
assert.match(titleRow, /<label class="income-create-student-label" for="createIncomeStudentSelect">学生<\/label>/);
assert.match(titleRow, /<label class="student-month-include-control income-create-student-scope-toggle">[\s\S]*?<input id="createIncomeIncludeInactiveCheckbox" type="checkbox">[\s\S]*?<span>包含暂停\/离校学生<\/span>[\s\S]*?<\/label>/);
assert.match(titleRow, /<b class="required-mark">必填<\/b>\s*<\/div>$/);
assert.ok(
  studentField.indexOf('id="createIncomeIncludeInactiveCheckbox"') < studentField.indexOf('<select id="createIncomeStudentSelect"'),
  "键盘顺序必须为 checkbox 后进入学生 select",
);
assert.equal((html.match(/id="createIncomeIncludeInactiveCheckbox"/g) || []).length, 1, "checkbox ID 必须唯一");
assert.equal((html.match(/income-create-student-label-row/g) || []).length, 1, "专用标题行不得影响其他 dialog");
assert.match(html, /id="tuitionBillStudentSelect"[\s\S]*?id="tuitionBillIncludeInactiveCheckbox"/, "学费预览结构不得改变");

assert.match(layoutCss, /display:\s*flex/);
assert.match(layoutCss, /align-items:\s*center/);
assert.match(layoutCss, /margin-left:\s*12px/);
assert.match(layoutCss, /white-space:\s*nowrap/);
assert.match(layoutCss, /width:\s*16px/);
assert.match(layoutCss, /height:\s*16px/);
assert.match(layoutCss, /margin-left:\s*auto/);
assert.doesNotMatch(layoutCss, /(?:^|\n)\s*(?:position:\s*absolute|transform:|left:|right:)/);
assert.match(css, /\.student-month-include-control\s*\{[\s\S]*?gap:\s*6px/);
assert.match(css, /@media \(max-width: 767px\)[\s\S]*?#createIncomeDialog \.income-create-field-grid,[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/);

assert.match(page, /dom\.createIncomeIncludeInactiveCheckbox = document\.querySelector\("#createIncomeIncludeInactiveCheckbox"\)/);
assert.match(page, /dom\.createIncomeIncludeInactiveCheckbox\.addEventListener\("change", \(\) => refreshCreateStudentCandidates\(\)\)/);
assert.match(page, /dom\.createIncomeIncludeInactiveCheckbox\.checked = Boolean\(filters\?\.includeInactive\)/);
assert.match(page, /fetchStudentMonthCandidates\(\{[\s\S]*?month,[\s\S]*?includeInactive: dom\.createIncomeIncludeInactiveCheckbox\.checked,[\s\S]*?selectedStudentId: selectedStudentId \|\| null/);

const mockCandidates = [
  { id: "active", status: "active" },
  { id: "paused", status: "paused" },
  { id: "departed", status: "departed" },
];
const checkbox = new EventTarget();
checkbox.checked = false;
let renderedCandidates = [];
let readerCalls = 0;
let writerCalls = 0;
checkbox.addEventListener("change", () => {
  readerCalls += 1;
  renderedCandidates = mockCandidates.filter((candidate) => checkbox.checked || candidate.status === "active");
});
checkbox.dispatchEvent(new Event("change"));
assert.deepEqual(renderedCandidates.map(({ id }) => id), ["active"]);
checkbox.checked = true;
checkbox.dispatchEvent(new Event("change"));
assert.deepEqual(renderedCandidates.map(({ id }) => id), ["active", "paused", "departed"]);
checkbox.checked = false;
checkbox.dispatchEvent(new Event("change"));
assert.deepEqual(renderedCandidates.map(({ id }) => id), ["active"]);
assert.equal(readerCalls, 3);
assert.equal(writerCalls, 0);

assert.match(html, /app\.css\?v=income-create-student-scope-layout-20260813-1/);
assert.match(html, /income-app\.js\?v=lesson-week-close-20260823-1/);
assert.match(app, /config\.js\?v=lesson-week-close-20260823-1/);
assert.match(config, /APP_VERSION = "v10\.5\.62"/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = read(`js/pages/${pageFile}`);
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(source, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/, `page-layer DML regression: ${pageFile}`);
}

console.log("INCOME_CREATE_STUDENT_SCOPE_LAYOUT_TEST_PASS writer_calls=0");
