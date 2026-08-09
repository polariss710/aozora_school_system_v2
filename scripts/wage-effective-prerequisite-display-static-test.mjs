import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const api = readFileSync("js/api/wage-api.js", "utf8");
const page = readFileSync("js/pages/wage-page.js", "utf8");
const html = readFileSync("wage.html", "utf8");
const css = readFileSync("css/app.css", "utf8");
const reader = readFileSync("sql/current/school_wage_candidate_effective_display_reader_20260809.sql", "utf8");
const rehearsal = readFileSync("sql/current/school_wage_candidate_effective_display_reader_rollback_20260809.sql", "utf8");
const postdeploy = readFileSync("sql/current/school_wage_candidate_effective_display_reader_postdeploy_20260809.sql", "utf8");

assert.match(api, /supabase\.rpc\("school_get_teacher_monthly_wage_generation_preflight"/);
assert.match(api, /candidate_prerequisites/);
assert.match(api, /WAGE_PREFLIGHT_CANDIDATE_COVERAGE_MISMATCH/);
assert.doesNotMatch(api, /school_student_monthly_settlements/);
assert.doesNotMatch(api, /studentSettlementStatus|studentSettlementMatchedBusiness/);

assert.match(page, /工资前置满足 \/ 阻断/);
assert.match(page, /no_wage 无需月结/);
assert.match(page, /no_wage_not_required/);
assert.match(page, /historically_consumed_immutable/);
assert.match(page, /historical_zero_carry_complete/);
assert.doesNotMatch(page, /学生结算完成 \/ 未完成/);
assert.doesNotMatch(page, /studentSettlementStatus|studentSettlementMatchedBusiness/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.match(html, /<th>工资前置<\/th>/);
assert.match(html, /wage-duty-report-summary-20260809-1/);
assert.match(html, /wage-effective-prerequisite-stable-loading-20260809-1/);
assert.match(css, /\.wage-list-panel #wageLoadingState\.is-hidden\s*\{[\s\S]*display:\s*block !important;[\s\S]*visibility:\s*hidden/);

assert.match(reader, /candidate_prerequisites/);
assert.match(reader, /select \* from public\.school_get_teacher_monthly_wage_generation_candidate_facts/);
assert.match(reader, /'prerequisite_satisfied', blocker_code is null/);
assert.match(reader, /'prerequisite_status'/);
assert.match(reader, /security definer[\s\S]*set search_path = pg_catalog, public/i);
assert.match(reader, /grant execute[\s\S]*to authenticated/i);
assert.doesNotMatch(reader, /\b(?:insert|update|delete|merge|truncate|drop)\b/i);

assert.match(rehearsal, /begin;[\s\S]*\\ir school_wage_candidate_effective_display_reader_20260809\.sql[\s\S]*rollback;/i);
assert.match(rehearsal, /set local role anon/);
assert.match(rehearsal, /NO_MEMBERSHIP_UNEXPECTED_ACCESS/);
assert.match(postdeploy, /active_wage_lock_count/);
assert.match(postdeploy, /conditional_amount_jpy/);
assert.match(postdeploy, /begin transaction isolation level repeatable read read only/);

console.log("WAGE_EFFECTIVE_PREREQUISITE_DISPLAY_STATIC_TEST_PASS");
