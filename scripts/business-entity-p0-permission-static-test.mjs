import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const occurrences = (source, token) => source.split(token).length - 1;

const createSql = read("sql/current/school_create_business_entity_profile_rpc.sql");
const updateSql = read("sql/current/school_update_business_entity_profile_rpc.sql");
const coreSql = read("sql/current/school_business_entity_p0_permission_closure_core_20260806.sql");
const deploySql = read("sql/current/school_business_entity_p0_permission_closure_deploy_20260806.sql");
const postdeploySql = read("sql/current/school_business_entity_p0_permission_closure_postdeploy_20260806.sql");
const rollbackSql = read("sql/tests/school_business_entity_p0_permission_closure_rollback_test_20260806.sql");
const apiSource = read("js/api/business-entity-api.js");

assert(occurrences(createSql, "perform public.school_require_current_app_admin();") === 2,
  "every create overload must call the active-admin helper");
assert(occurrences(updateSql, "perform public.school_require_current_app_admin();") === 2,
  "every update overload must call the active-admin helper");
assert(!/set search_path\s*=\s*public\b/i.test(`${createSql}\n${updateSql}`),
  "profile writers must not retain public-only search_path");
assert(occurrences(`${createSql}\n${updateSql}`, "set search_path = pg_catalog, public") === 4,
  "all four overloads must use the fixed safe search_path");
assert(createSql.includes("pg_catalog.gen_random_uuid()"),
  "generated business codes must resolve gen_random_uuid through pg_catalog");

assert(coreSql.includes("drop policy if exists school_allow_all_business_entities"),
  "core must remove the public allow-all policy");
assert(coreSql.includes("create policy school_business_entities_active_membership_select"),
  "core must create the active-membership SELECT policy");
assert(coreSql.includes("for select\n  to authenticated"),
  "business-entity RLS policy must be authenticated SELECT-only");
assert(coreSql.includes("membership.role in ('admin','operator','read_only')"),
  "SELECT policy must preserve all three active application roles");
assert(!/create policy school_allow_all_business_entities/i.test(coreSql),
  "the allow-all policy must never be recreated");
assert(coreSql.includes("revoke all privileges on table public.school_business_entities"),
  "core must revoke all direct table privileges first");
assert(coreSql.includes("grant select on table public.school_business_entities to authenticated"),
  "only authenticated SELECT may be restored");
assert(!/grant\s+(all|insert|update|delete|truncate|references|trigger)[\s\S]*school_business_entities[\s\S]*to\s+(anon|authenticated|service_role)/i.test(coreSql),
  "core must not restore direct table mutation privileges");
assert(!/grant execute[\s\S]*school_(create|update)_business_entity_profile[\s\S]*to\s+(anon|service_role)/i.test(coreSql),
  "anon and service-role must not receive Profile RPC execute");

assert(!/\b(insert\s+into|update|delete\s+from|truncate\s+table)\s+public\.school_business_entities\b/i.test(`${coreSql}\n${deploySql}`),
  "deployment SQL must not write business-entity rows");
assert(!/school_(create|update)_business_entity_profile\s*\(/i.test(
  postdeploySql.replace(/'public\.school_(create|update)_business_entity_profile[^']*'/g, "")
), "postdeploy must not invoke Profile writers");

assert(apiSource.includes('.from("school_business_entities")') && apiSource.includes('.select(BUSINESS_ENTITY_COLUMNS)'),
  "API must retain the authorized read path");
assert(apiSource.includes('supabase.rpc("school_create_business_entity_profile"'),
  "create must remain behind the API-layer RPC");
assert(apiSource.includes('supabase.rpc("school_update_business_entity_profile"'),
  "update must remain behind the API-layer RPC");

const pageFiles = fs.readdirSync(path.join(root, "js/pages"))
  .filter((name) => name.endsWith(".js"));
for (const file of pageFiles) {
  const source = read(`js/pages/${file}`);
  assert(!source.includes(".rpc("), `page module calls RPC directly: ${file}`);
  assert(!/\.from\([^)]*school_business_entities/.test(source),
    `page module accesses business-entity table directly: ${file}`);
  assert(!/import\s*\{[^}]*\bsupabase\b[^}]*\}\s*from\s*["']\.\.\/supabase-client\.js["']/.test(source),
    `page module imports the Supabase data client directly: ${file}`);
}

const browserFiles = [
  ...fs.readdirSync(path.join(root, "js"), { recursive: true })
    .filter((name) => typeof name === "string" && name.endsWith(".js"))
    .map((name) => `js/${name}`),
  ...fs.readdirSync(root).filter((name) => name.endsWith(".html")),
];
for (const file of browserFiles) {
  const source = read(file);
  assert(!/service[_-]?role/i.test(source), `browser source contains service-role material: ${file}`);
}

assert(rollbackSql.includes("BE_P0_PERMISSION_CLOSURE_LOCAL_ROLLBACK_TEST_PASS"),
  "rollback fixture must expose a stable PASS marker");
assert(rollbackSql.trimEnd().endsWith("rollback;"),
  "local permission fixture must end in ROLLBACK");

console.log("BE_P0_PERMISSION_STATIC_TEST_PASS");
