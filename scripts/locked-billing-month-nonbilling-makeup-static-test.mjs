import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_correction_20260816.sql", import.meta.url),
  "utf8",
);
const rollback = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_correction_exact_rollback_20260816.sql", import.meta.url),
  "utf8",
);
const originals = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_predeployment_definitions_20260816.sql", import.meta.url),
  "utf8",
);
const rehearsal = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_rehearsal_20260816.sql", import.meta.url),
  "utf8",
);
const execution = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_execute_correction_20260816.sql", import.meta.url),
  "utf8",
);
const postcorrection = readFileSync(
  new URL("../sql/current/school_locked_billing_month_nonbilling_makeup_sun_chenfeng_postcorrection_readonly_20260816.sql", import.meta.url),
  "utf8",
);
const api = readFileSync(new URL("../js/api/lesson-api.js", import.meta.url), "utf8");
const page = readFileSync(new URL("../js/pages/lesson-page.js", import.meta.url), "utf8");

assert.doesNotMatch(migration, /\b(create|alter|drop)\s+table\b/i);
assert.doesNotMatch(migration, /\b(insert|update|delete)\s+public\.school_(student_monthly_settlements|student_tuition_bills|income_records)\b/i);
assert.match(migration, /LESSON_MAKEUP_DATE_BEFORE_SOURCE/);
assert.match(migration, /v_is_locked_nonbilling_makeup/);
assert.match(migration, /new\.status='makeup_completed'/);
assert.match(migration, /new\.is_billable is false/);
assert.match(migration, /new\.lesson_fee=0/);
assert.match(originals, /LESSON_MAKEUP_TEACHER_WAGE_LOCKED/);
assert.match(migration, /R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED/);

for (const id of [
  "8b737b58-cd14-42c5-afd2-34730dcef963",
  "c8e6cf21-850c-4700-af9e-7ebf3c2a577d",
  "6722e5a8-d7a1-453a-93a8-9cbaab227378",
  "5e0a23ff-0e1e-48c6-9866-5fc335b3e42d",
  "2a9f1c25-a060-461e-ae10-b02295dec381",
  "468ab75b-312e-4ba0-8d8d-8ae2f6ace00e",
]) assert.match(migration, new RegExp(id, "i"));

assert.match(migration, /school_require_current_app_admin\(\)/);
assert.match(migration, /p_expected_planned_updated_at/);
assert.match(migration, /p_expected_actual_updated_at/);
assert.match(migration, /CORRECT_SUN_CHENFENG_20260811_MAKEUP/);
assert.match(migration, /set voided_at=transaction_timestamp\(\),void_reason=v_reason/);
assert.match(migration, /school_create_cancelled_actual_lesson_from_planned\(/);
assert.match(migration, /school_create_lesson_credit_makeup_actual\(/);
assert.match(migration, /'2026-08-11'/);
assert.match(migration, /'简谐\+万有引力'/);
assert.match(migration, /v_candidate_count<>5 or v_candidate_wage<>40000 or v_new_wage<>8000/);
assert.match(migration, /revoke all on function public\.school_correct_sun_chenfeng_20260811_makeup_v1\([\s\S]*?from public,anon,authenticated,service_role/);
assert.doesNotMatch(migration, /grant execute on function public\.school_correct_sun_chenfeng_20260811_makeup_v1/);
assert.doesNotMatch(rehearsal, /set local role authenticated;[\s\S]*school_correct_sun_chenfeng_20260811_makeup_v1/i);
assert.match(execution, /v_acl<>'postgres=X\/postgres'/);
assert.match(execution, /drop function public\.school_correct_sun_chenfeng_20260811_makeup_v1/);
assert.match(execution, /SUN_CHENFENG_EXACT_CORRECTION_COMMITTED_AND_ENTRYPOINT_REMOVED/);
assert.doesNotMatch(execution, /set local role (authenticated|service_role)/i);
assert.match(postcorrection, /e69d9745-884a-401f-a4dc-d6672ea2a602/);
assert.match(postcorrection, /ff517a87-39fd-4282-89a9-e4fef28b728c/);
assert.match(postcorrection, /school_correct_sun_chenfeng_20260811_makeup_v1[\s\S]*is not null/);
assert.match(postcorrection, /SUN_CHENFENG_POSTCORRECTION_READONLY_PASS/);
assert.match(migration, /revoke all on function public\.school_enforce_r1d_e_b2_actual_attribution/);

assert.equal((originals.match(/^CREATE OR REPLACE FUNCTION/gm) || []).length, 3);
for (const hash of [
  "e6de3be6719e88c7da9b451e40f3b7c7",
  "73ac1abeebb6ce82870f9e0f8240629b",
  "60e380b560b0682dd78aa97139382d65",
]) {
  assert.match(originals, new RegExp(hash));
  assert.match(rollback, new RegExp(hash));
}
assert.match(rollback, /\\ir school_locked_billing_month_nonbilling_makeup_predeployment_definitions_20260816\.sql/);
assert.match(rollback, /SUN_CHENFENG_EXACT_ROLLBACK_UNSAFE_AFTER_DATA_CORRECTION/);

assert.match(api, /supabase\.rpc\("school_create_lesson_credit_makeup_actual"/);
assert.match(api, /supabase\.rpc\("school_create_cancelled_actual_lesson_from_planned"/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(`${api}\n${page}`, /school_correct_sun_chenfeng_20260811_makeup_v1/);

console.log("LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_STATIC_PASS");
