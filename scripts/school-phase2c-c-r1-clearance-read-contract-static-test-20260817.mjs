import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const migration = readFileSync(resolve(root,
  "sql/current/school_phase2c_c_r1_clearance_read_contract_migration_20260817.sql"), "utf8");
const rollback = readFileSync(resolve(root,
  "sql/current/school_phase2c_c_r1_clearance_read_contract_exact_rollback_20260817.sql"), "utf8");
const rehearsal = readFileSync(resolve(root,
  "sql/current/school_phase2c_c_r1_clearance_read_contract_production_rehearsal_20260817.sql"), "utf8");
const acceptance = readFileSync(resolve(root,
  "sql/current/school_phase2c_c_r1_clearance_read_contract_production_readonly_acceptance_20260817.sql"), "utf8");
const mapping = JSON.parse(readFileSync(resolve(root,
  "docs/school-v2-phase2c-c-r1-clearance-read-contract-field-map-20260817.json"), "utf8"));

for (const name of [
  "school_preview_lesson_clearance_v2",
  "school_preview_lesson_clearance_reversal_v1",
  "school_list_lesson_clearance_history_v2",
]) {
  assert.match(migration, new RegExp(`create function public\\.${name}\\(`));
  assert.match(rollback, new RegExp(`drop function if exists public\\.${name}\\(`));
}
for (const field of [
  "request_identity","preview_manifest_sha256","pending_source","overtime_source",
  "same_teacher","cross_teacher","same_subject","cross_subject",
  "recommended_pending_planned_id","is_recommended_target","deviation_reason_code",
  "source_locked","forward_destination_month","can_execute_for_current_actor",
  "reversal_manifest_sha256","can_reverse","evidence_status",
]) assert.ok(migration.includes(`'${field}'`), `missing DB field ${field}`);

assert.match(migration, /public\.school_preview_lesson_clearance\(/,
  "V2 Preview must reuse the deployed authoritative Preview");
assert.match(migration, /school_get_lesson_clearance_(pending|overtime)_remaining_minutes/,
  "reversal Preview must reuse authoritative balance helpers");
assert.doesNotMatch(migration, /\b(insert|update|delete|truncate)\s+(into|public\.|from)/i,
  "read migration must not contain business DML");
assert.doesNotMatch(migration, /create\s+table|alter\s+table/i,
  "R1 must not change tables");
assert.doesNotMatch(migration, /create\s+or\s+replace\s+function\s+public\.school_(create|reverse)_lesson_clearance/i,
  "writer definitions must remain untouched");
assert.match(migration, /grant execute[\s\S]+to authenticated/i);
assert.match(migration, /revoke all[\s\S]+from public,anon,authenticated,service_role/i);
for (const sql of [rehearsal, acceptance]) {
  assert.doesNotMatch(sql, /select\s+(?:\*\s+from\s+)?public\.school_(?:create|reverse)_lesson_clearance\s*\(/i,
    "production validation must not call a clearance writer");
}
assert.match(rehearsal, /rollback to savepoint phase2ccr1_fixture/i);
assert.match(rehearsal, /PHASE2C_C_R1_PRODUCTION_REHEARSAL_PASS/);
assert.match(acceptance, /begin transaction read only/i);
assert.match(acceptance, /reader_zero_write_assertion/);

assert.equal(mapping.contractVersion, "phase2c_c_r1_20260817");
assert.ok(mapping.preview.length >= 20);
assert.ok(mapping.history.length >= 15);
assert.ok(mapping.reversalPreview.length >= 12);
assert.ok(mapping.preview.every((row) => row.authority === "db"));
assert.ok(mapping.history.some((row) => row.evidenceStatus === "unavailable"));

console.log("Phase 2C-C-R1 clearance read contract static test: PASS");
