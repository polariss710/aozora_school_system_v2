import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repo = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(repo, path), "utf8");
const migration = read("sql/current/school_phase2c_d2_a2_pending_operational_date_reader_v3_migration_20260818.sql");
const rollback = read("sql/current/school_phase2c_d2_a2_pending_operational_date_reader_v3_exact_rollback_20260818.sql");
const api = read("js/api/lesson-clearance-api.js");

assert.match(migration, /school_list_lesson_clearance_pending_balances_v3\(uuid,boolean\)/);
assert.match(migration, /school_list_lesson_clearance_pending_balances_v2/);
for (const field of [
  "operational_display_date",
  "operational_display_date_basis",
  "origin_partial_actual_id",
  "origin_partial_actual_date",
  "origin_evidence_status",
  "operational_display_explanation",
]) assert.match(migration, new RegExp(field));
assert.match(migration, /actual_row\.status='completed'/);
assert.match(migration, /actual_row\.voided_at is null/);
assert.match(migration, /actual_row\.planned_lesson_id=planned\.id/);
assert.match(migration, /extract\(isodow from planned\.lesson_date\)/);
assert.match(migration, /security definer/i);
assert.match(migration, /set search_path=pg_catalog,public/);
assert.match(migration, /revoke all[\s\S]*public,anon,authenticated,service_role/);
assert.match(migration, /grant execute[\s\S]*to authenticated/);
assert.match(rollback, /drop function if exists[\s\S]*school_list_lesson_clearance_pending_balances_v3/);
assert.match(rollback, /school_list_lesson_clearance_pending_balances_v2/);
assert.match(api, /school_list_lesson_clearance_pending_balances_v[23]/);

console.log("SCHOOL_PHASE2C_D2_A2_PENDING_OPERATIONAL_DATE_STATIC_PASS");
