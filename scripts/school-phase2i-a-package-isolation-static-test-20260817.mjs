import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const migration = read("sql/current/school_phase2i_a_p002_package_isolation_migration_20260817.sql");
const rollback = read("sql/current/school_phase2i_a_p002_package_isolation_exact_rollback_20260817.sql");
const contract = read("sql/tests/school_phase2i_a_p002_package_isolation_contract_local_20260817.sql");

for (const value of [
  "8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9",
  "686cbf3a566160bf0de0e30abbdaafa5",
  "a7b163a0-201e-4867-9b94-372343356a80",
  "2cf7b72f-6e3c-4d09-80f7-7c58593cd466",
  "07a02092-9503-47d1-9000-106f7e3de7e5",
  "96000000-0000-4000-8000-202608031004",
  "91756564-c48d-4a1d-b6bc-88a041660e46",
  "9de972ff-8e66-470a-8b05-e430ef51562f",
]) assert.match(migration, new RegExp(value));

assert.match(migration, /create table public\.school_student_package_credit_lots/);
assert.match(migration, /initial_minutes=1200 and consumed_minutes=0/);
assert.match(migration, /remaining_minutes integer generated always/);
assert.match(migration, /LESSON_PACKAGE_SOURCE_NOT_MAKEUP_CREDIT/);
assert.match(migration, /school_assert_active_lesson_writer\(\)/);
assert.match(migration, /revoke all on public\.school_student_package_credit_lots\s+from public,anon,authenticated,service_role/);
assert.match(migration, /grant execute on function public\.school_list_student_package_credit_lots\(uuid\)\s+to authenticated/);
assert.doesNotMatch(migration, /create\s+(?:or replace\s+)?function\s+public\.[^(]*(?:consume|reserve|clearance)/i);
assert.doesNotMatch(migration, /create table public\.school_lesson_clearance/i);
assert.doesNotMatch(migration, /\b(update|delete)\s+public\.school_lesson_records\b/i);
assert.doesNotMatch(migration, /\binsert\s+into\s+public\.school_lesson_records\b/i);
assert.equal((migration.match(/insert into public\.school_student_package_credit_lots/g) || []).length, 1);

assert.match(rollback, /delete from public\.school_student_package_credit_lots/);
assert.match(rollback, /drop table public\.school_student_package_credit_lots/);
assert.match(rollback, /rename to school_create_lesson_credit_makeup_actual/);
for (const md5 of [
  "f5da14743858f89d37f17ba2646ab092",
  "2111a62f998abeeb6933b47fc5c512aa",
  "81823a464f235e72a439867a2c4d395a",
  "3b45f8f09d4d63a952ca5ec42f7214d7",
  "4859d04189893b1dfdecc6a3d66df192",
  "3434e8ece09ec210511aec8b8eb1960f",
]) assert.match(rollback, new RegExp(md5));

for (let index = 1; index <= 23; index += 1) {
  assert.match(contract, new RegExp(`${String(index).padStart(2, "0")} `));
}
console.log("SCHOOL_PHASE2I_A_PACKAGE_ISOLATION_STATIC_PASS");
