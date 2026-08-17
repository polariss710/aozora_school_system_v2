import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repo = resolve(import.meta.dirname, "..");
const migration = readFileSync(resolve(repo, "sql/current/school_phase2c_c_r2_clearance_candidate_readers_migration_20260817.sql"), "utf8");
const rollback = readFileSync(resolve(repo, "sql/current/school_phase2c_c_r2_clearance_candidate_readers_exact_rollback_20260817.sql"), "utf8");
const closure = JSON.parse(readFileSync(resolve(repo, "docs/school-v2-phase2c-c-r2-clearance-reader-field-closure-20260817.json"), "utf8"));

const signatures = [
  "school_list_lesson_clearance_pending_balances_v2",
  "school_list_lesson_clearance_available_overages_v2",
  "school_list_student_package_credit_lots_v2",
  "school_list_cross_month_makeup_projection_v2",
  "school_get_lesson_clearance_dashboard_summary_v1",
];
for (const name of signatures) {
  assert.match(migration, new RegExp(`create function public\\.${name}\\(`));
  assert.match(migration, new RegExp(`alter function public\\.${name}\\([\\s\\S]*?owner to postgres`));
  assert.match(migration, new RegExp(`grant execute on function public\\.${name}\\(`));
  assert.match(rollback, new RegExp(`drop function if exists public\\.${name}\\(`));
}

assert.equal(closure.rules.page_master_joins_required, false);
assert.equal(closure.rules.page_balance_derivation_allowed, false);
assert.deepEqual(closure.missing_fields, []);
for (const reader of Object.values(closure.readers)) {
  for (const field of [...(reader.response_fields || []), ...(reader.item_fields || []), ...(reader.summary_fields || []), ...(reader.fields || [])]) {
    assert.match(migration, new RegExp(`['\"]${field}['\"]`), `${reader.rpc} missing ${field}`);
  }
}

assert.doesNotMatch(migration, /create\s+table|alter\s+table|insert\s+into|update\s+public\.|delete\s+from|truncate/i);
assert.doesNotMatch(migration, /create\s+(or\s+replace\s+)?function\s+public\.school_(create|reverse)_lesson_clearance/i);
assert.match(migration, /security definer/g);
assert.match(migration, /set search_path=pg_catalog,public/g);
assert.match(migration, /from public,anon,authenticated,service_role/g);
assert.match(migration, /to authenticated/g);
assert.match(migration, /PHASE2C_C_R2_WRITER_CHANGED/);
assert.match(rollback, /PHASE2C_C_R2_EXACT_ROLLBACK_DEPENDENCY_DRIFT/);

console.log("SCHOOL_PHASE2C_C_R2_CLEARANCE_CANDIDATE_READERS_STATIC_PASS");
