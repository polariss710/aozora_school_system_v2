import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const schema = read("sql/current/school_phase2c_c_lesson_clearance_schema_migration_20260817.sql");
const backend = read("sql/current/school_phase2c_c_lesson_clearance_backend_migration_20260817.sql");
const rollback = read("sql/current/school_phase2c_c_lesson_clearance_exact_rollback_20260817.sql");
const contract = read("sql/tests/school_phase2c_c_lesson_clearance_contract_local_20260817.sql");
const extended = read("sql/tests/school_phase2c_c_lesson_clearance_extended_contract_local_20260817.sql");
const roles = read("sql/tests/school_phase2c_c_lesson_clearance_role_matrix_local_20260817.sql");
const packageTest = read("sql/tests/school_phase2c_c_p002_regression_local_20260817.sql");
const concurrency = read("scripts/school-phase2c-c-lesson-clearance-concurrency-local-test-20260817.zsh");
const lessonApi = read("js/api/lesson-api.js");
const lessonPage = read("js/pages/lesson-page.js");

for (const table of ["school_lesson_clearances", "school_lesson_clearance_details"]) {
  assert.match(schema, new RegExp(`create table public\\.${table}\\b`, "i"));
  assert.match(schema, new RegExp(`alter table public\\.${table} enable row level security`, "i"));
  assert.match(schema, new RegExp(`revoke all on public\\.${table} from public,anon,authenticated,service_role`, "i"));
  assert.match(rollback, new RegExp(`drop table public\\.${table}`, "i"));
}
assert.doesNotMatch(schema, /create table public\.school_student_package_credit_lots/i);
assert.doesNotMatch(backend, /create table public\.school_student_package_credit_lots/i);
assert.doesNotMatch(rollback, /drop table public\.school_student_package_credit_lots/i);
assert.match(schema, /clearance_type text not null check \(clearance_type in \([\s\S]*'overtime_offset'[\s\S]*'administrative_writeoff'[\s\S]*'legacy_consolidated_fulfillment'[\s\S]*'reversal'/);
assert.match(schema, /selection_mode text not null default 'manual'/);
assert.match(schema, /forward_adjustment_direction text not null default 'none'/);
assert.match(schema, /school_lesson_clearances_idempotency_uniq/);
assert.match(schema, /school_lesson_clearances_reversal_once_uidx/);

for (const fn of [
  "school_list_lesson_clearance_pending_balances",
  "school_list_lesson_clearance_available_overages",
  "school_suggest_lesson_clearance_targets",
  "school_preview_lesson_clearance",
  "school_list_lesson_clearance_history",
  "school_list_lesson_clearance_forward_manifest",
  "school_list_cross_month_makeup_projection",
  "school_create_lesson_clearance",
  "school_reverse_lesson_clearance",
]) assert.match(backend, new RegExp(`create function public\\.${fn}\\b`, "i"));

assert.match(backend, /school_create_lesson_clearance_core\([\s\S]*p_pending_source_planned_id uuid[\s\S]*p_overtime_source_actual_id uuid/);
assert.match(backend, /order by lock_target\.year_month/);
assert.match(backend, /order by lock_target\.lesson_id/);
assert.match(backend, /LESSON_CLEARANCE_PRICE_POLICY_REQUIRED/);
assert.match(backend, /LESSON_CLEARANCE_FIFO_DEVIATION_REASON_REQUIRED/);
assert.match(backend, /LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED/);
assert.match(backend, /LESSON_CLEARANCE_PACKAGE_SOURCE_FORBIDDEN/);
assert.match(backend, /LESSON_CLEARANCE_APPEND_ONLY/);
assert.match(backend, /school_variance_claim_clearance_mutex/);
assert.match(backend, /school_lesson_clearance_detail_validate/);
assert.match(backend, /v_operation_month,case when v_forward then v_operation_month else null end,v_forward/);
assert.match(backend, /pending_unit_price_minutes_v1/);
assert.match(backend, /projection\.id,[\s\S]*projection\.planned_lesson_id/);
assert.match(backend, /actual_row\.status='makeup_completed'/);
assert.doesNotMatch(backend, /insert into public\.school_lesson_records/i);
assert.doesNotMatch(backend, /update public\.school_(lesson_records|student_monthly_settlements|student_tuition_bills|income_records)/i);

for (const role of ["public", "anon", "authenticated", "service_role"]) {
  assert.match(backend, new RegExp(`revoke all on public\\.school_lesson_clearances from public,anon,authenticated,service_role`, "i"));
  assert.ok(role);
}
for (const writer of ["school_create_lesson_clearance", "school_reverse_lesson_clearance"]) {
  assert.match(backend, new RegExp(`revoke all on function public\\.${writer}\\([\\s\\S]*from public,anon,authenticated,service_role`, "i"));
  assert.match(backend, new RegExp(`grant execute on function public\\.${writer}\\([\\s\\S]*to authenticated`, "i"));
}
assert.doesNotMatch(backend, /grant execute on function public\.school_(create|reverse)_lesson_clearance[\s\S]{0,300}to service_role/i);

for (const restored of [
  "school_get_lesson_credit_raw_remaining_hours",
  "school_get_lesson_credit_remaining_hours",
  "school_list_student_lesson_credit_balances",
  "school_list_open_lesson_credit_sources",
  "school_tuition_p0f_source_lines",
]) assert.match(rollback, new RegExp(`create or replace function public\\.${restored}\\b`, "i"));
assert.match(rollback, /LESSON_CLEARANCE_ROLLBACK_BUSINESS_FACTS_EXIST/);
assert.match(rollback, /remaining_minutes=1200/);
assert.doesNotMatch(rollback, /drop function public\.school_is_active_package_credit_origin/);
assert.doesNotMatch(rollback, /drop function public\.school_list_student_package_credit_lots/);

for (const label of [
  "caller explicitly selected FIFO first target",
  "non-FIFO target persists deviation reason",
  "suggestion reader writes zero rows",
  "cross-teacher clearance succeeds",
  "cross-subject clearance succeeds",
  "cross-student clearance rejected",
  "cross-entity clearance rejected",
  "same-price partial clearance preserves both residual balances",
  "different-price clearance rejected stably",
  "active claim blocks subsequent clearance",
  "existing clearance blocks subsequent active claim",
  "ordinary makeup actual minutes reduce balance before ledger allocation",
]) assert.ok(contract.includes(label), `missing contract test: ${label}`);
for (const label of [
  "Preview returns DB-authoritative same-price minutes and two-sided JPY evidence",
  "Locked same-price offset forwards to operation month",
  "Future settlement forward manifest contains the locked clearance evidence",
  "Reversal appends a later operation-month forward fact",
  "Cross-month makeup projects one actual UUID",
  "Clearance facts never masquerade as makeup actuals",
  "P002 cannot become a clearance source",
]) assert.ok(extended.includes(label), `missing extended test: ${label}`);
for (const text of [
  "LESSON_CLEARANCE_ROLE_REQUIRED",
  "LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED",
  "LESSON_CLEARANCE_MEMBERSHIP_REQUIRED",
  "LESSON_CLEARANCE_AUTH_REQUIRED",
  "active read_only membership may execute clearance readers",
  "anon writer execute revoked",
  "service_role writer execute revoked",
]) assert.ok(roles.includes(text), `missing role assertion: ${text}`);
assert.match(packageTest, /1200[\s\S]*consumed_minutes[\s\S]*P002/);
assert.match(concurrency, /session_a/);
assert.match(concurrency, /session_b/);
assert.doesNotMatch(lessonPage, /school_(create|reverse)_lesson_clearance|school_preview_lesson_clearance/);
assert.doesNotMatch(lessonApi, /school_(create|reverse)_lesson_clearance|school_preview_lesson_clearance/);
assert.doesNotMatch(lessonPage, /\.rpc\s*\(/);

console.log("School lesson clearance Phase 2C-C static contract: PASS");
