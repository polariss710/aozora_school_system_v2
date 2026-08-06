import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const htmlFiles = fs.readdirSync(root).filter((name) => name.endsWith(".html"));
const pageFiles = fs.readdirSync(path.join(root, "js/pages"))
  .filter((name) => name.endsWith(".js"));
const apiFiles = fs.readdirSync(path.join(root, "js/api"))
  .filter((name) => name.endsWith(".js"));
const browserFiles = [
  ...htmlFiles,
  ...pageFiles.map((name) => `js/pages/${name}`),
  ...fs.readdirSync(path.join(root, "js/components")).filter((name) => name.endsWith(".js")).map((name) => `js/components/${name}`),
  ...fs.readdirSync(path.join(root, "js/utils")).filter((name) => name.endsWith(".js")).map((name) => `js/utils/${name}`),
];

for (const file of browserFiles) {
  const source = read(file);
  assert(!/(业务归属|个人名义)/.test(source), `user-visible retired scope wording remains: ${file}`);
  assert(!/business-entity\.html/.test(source), `retired management navigation remains: ${file}`);
}

for (const file of htmlFiles) {
  const source = read(file);
  assert(!/(BusinessEntitySelect|businessEntitySelect|BusinessEntityFilter|businessEntityFilter)/.test(source),
    `retired entity control remains in HTML: ${file}`);
}

for (const file of pageFiles) {
  const source = read(`js/pages/${file}`);
  assert(!source.includes(".rpc("), `page module calls RPC directly: ${file}`);
  assert(!/import\s*\{[^}]*\bsupabase\b[^}]*\}\s*from\s*["']\.\.\/supabase-client\.js["']/.test(source),
    `page module imports the Supabase data client directly: ${file}`);
}

const authGuard = read("js/auth-guard.js");
for (const key of ["business_entity_id", "businessEntityId", "business_entity", "businessEntity"]) {
  assert(authGuard.includes(`"${key}"`), `legacy URL key is not cleared: ${key}`);
}
assert(authGuard.includes("window.history.replaceState"), "legacy URL cleanup must use replaceState");

const policy = read("js/utils/business-entity-policy.js");
assert(policy.includes("matches.length !== 1"), "new-record scope resolver must fail closed unless Aozora is unique");
assert(policy.includes('PRIMARY_SCHOOL_BUSINESS_ENTITY_CODE = "aosora"'),
  "new-record scope resolver must use the DB-authoritative Aozora code");

const editContracts = [
  ["js/pages/student-page.js", "defaultBusinessEntityId: editingStudent.business_entity_id"],
  ["js/pages/teacher-page.js", "defaultBusinessEntityId: editingTeacher.default_business_entity_id"],
  ["js/pages/wage-rule-page.js", "businessEntityId: editingWageRule.business_entity_id"],
  ["js/components/lesson-edit-dialog.js", "businessEntityId: currentLesson.business_entity_id"],
  ["js/pages/income-detail-page.js", "const businessEntityId = income.business_entity_id"],
  ["js/pages/expense-detail-page.js", "const businessEntityId = expense.business_entity_id"],
];
for (const [file, contract] of editContracts) {
  assert(read(file).includes(contract), `historical edit scope preservation missing: ${file}`);
}

const businessApi = read("js/api/business-entity-api.js");
assert(!/school_(?:create|update)_business_entity_profile/.test(businessApi),
  "Profile writer consumer remains in business-entity API");
for (const file of apiFiles) {
  if (file === "business-entity-api.js") continue;
  assert(!/school_(?:create|update)_business_entity_profile/.test(read(`js/api/${file}`)),
    `Profile writer consumer remains: ${file}`);
}

const profitApi = read("js/api/profit-summary-api.js");
const profitPage = read("js/pages/profit-summary-page.js");
assert(profitApi.includes('supabase.rpc("school_get_profit_summary_schoolwide_v1"'),
  "profit summary must use the DB-authoritative school-wide reader through the API layer");
assert(!/\.from\(/.test(profitApi), "profit summary API must not rebuild authority from raw tables");
assert(!/(reduce\s*\(|sumAmount\s*\(|incomeAmount\s*-\s*expenseAmount)/.test(profitPage),
  "profit summary page must not recompute financial facts");

const coreSql = read("sql/current/school_business_entity_ui_closure_core_20260806.sql");
assert(coreSql.includes("security definer") && coreSql.includes("set search_path = pg_catalog, public"),
  "school-wide profit reader must be a fixed-search-path security definer");
assert(coreSql.includes("membership.role in ('admin','operator','read_only')"),
  "school-wide reader must enforce active application membership");
assert(!/\b(insert\s+into|update|delete\s+from|truncate\s+table)\s+public\./i.test(coreSql),
  "BE-UI SQL must not contain business DML");
assert(!/business_entity_id\s*=|p_business_entity_id/i.test(coreSql),
  "school-wide reader must not filter by one historical business scope");

console.log("BE_UI_STATIC_TEST_PASS");
