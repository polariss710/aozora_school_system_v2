import assert from "node:assert/strict";
import fs from "node:fs";

const schema = fs.readFileSync("sql/current/school_historical_zero_carry_completion_schema_20260809.sql", "utf8");
const rpcs = fs.readFileSync("sql/current/school_historical_zero_carry_completion_rpcs_20260809.sql", "utf8");
const tool = fs.readFileSync("scripts/manage-historical-zero-carry-evidence.zsh", "utf8");

assert.match(schema, /create table if not exists public\.school_student_monthly_settlement_historical_completion_evidence/i);
assert.match(schema, /unique \(student_id, settlement_month, business_entity_id\)/i);
assert.match(schema, /check \(final_carry_cny = 0\)/i);
assert.match(schema, /revoke all privileges[\s\S]*from public, anon, authenticated, service_role/i);
assert.doesNotMatch(schema, /create\s+(or\s+replace\s+)?function/i);
assert.doesNotMatch(schema, /\b(insert|update|delete)\s+(into|public\.)/i);

assert.match(rpcs, /school_create_student_monthly_settlement_historical_completion_evidence_core/i);
assert.match(rpcs, /school_local_create_student_monthly_settlement_historical_completion_evidence/i);
assert.match(rpcs, /school_resolve_student_monthly_settlement_effective_state/i);
assert.match(rpcs, /school_get_teacher_monthly_wage_generation_preflight/i);
assert.match(rpcs, /historical_zero_carry_complete/i);
assert.match(rpcs, /historically_consumed_immutable/i);
assert.match(rpcs, /ordinary_locked/i);
assert.match(rpcs, /WAGE_EFFECTIVE_SETTLEMENT_MISSING/i);
assert.match(rpcs, /WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH/i);
assert.match(rpcs, /WAGE_RULE_MISSING/i);
assert.match(rpcs, /WAGE_RULE_DUPLICATE/i);
assert.match(rpcs, /WAGE_LESSON_FACT_INCOMPLETE/i);
assert.match(rpcs, /settlement_type = 'no_wage'[\s\S]*then true/i);
assert.match(rpcs, /set search_path = pg_catalog, public/gi);
assert.doesNotMatch(rpcs, /\bexecute\s+format\s*\(/i);

assert.match(rpcs, /revoke all on function public\.school_create_student_monthly_settlement_historical_completion_evidence_core[\s\S]*from public, anon, authenticated, service_role/i);
assert.match(rpcs, /grant execute on function public\.school_local_create_student_monthly_settlement_historical_completion_evidence[^;]*\bto service_role\s*;/i);
assert.doesNotMatch(rpcs, /grant execute on function public\.school_local_create_student_monthly_settlement_historical_completion_evidence[^;]*\bto authenticated\b[^;]*;/i);
assert.match(tool, /set local request\.jwt\.claims='\{"role":"service_role"\}'/);
assert.match(tool, /CASH_SUPABASE_DB_URL/);
assert.match(tool, /SCHOOL_SUPABASE_DB_URL/);
assert.doesNotMatch(tool, /SUPABASE_SERVICE_ROLE_KEY|sb_secret_|service_role_key/i);

const browserFiles = [
  ...fs.readdirSync("js").filter((name) => name.endsWith(".js")).map((name) => `js/${name}`),
  ...fs.readdirSync(".").filter((name) => name.endsWith(".html")),
];
for (const file of browserFiles) {
  const source = fs.readFileSync(file, "utf8");
  assert.doesNotMatch(source, /school_(?:local_)?create_student_monthly_settlement_historical_completion_evidence/i, `browser evidence writer reference: ${file}`);
  assert.doesNotMatch(source, /SERVICE_ROLE|service[_-]?role/i, `browser service-role marker: ${file}`);
}

for (const file of fs.readdirSync("js/pages").filter((name) => name.endsWith(".js"))) {
  const source = fs.readFileSync(`js/pages/${file}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page direct RPC: ${file}`);
  assert.doesNotMatch(source, /\.(?:insert|update|upsert)\s*\(/, `page direct DML: ${file}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)(?:\s*\.\w+\s*\([^;]*?\))*\s*\.delete\s*\(/,
    `page direct delete: ${file}`
  );
}

console.log("Historical zero-carry / wage effective static checks passed.");
