import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const localFiles = [
  "local/phase2c-b/index.html",
  "local/phase2c-b/phase2c-b.css",
  "local/phase2c-b/phase2c-b-api-contract.mjs",
  "local/phase2c-b/phase2c-b-mock-adapter.mjs",
  "local/phase2c-b/phase2c-b-state.mjs",
  "local/phase2c-b/phase2c-b-page.mjs",
];
const source = localFiles.map((file) => readFileSync(resolve(root, file), "utf8")).join("\n");

assert.doesNotMatch(source, /\.rpc\s*\(/, "local page/API must not call RPC directly");
assert.doesNotMatch(source, /\.(insert|update|delete|upsert)\s*\(/, "local page/API must not perform table DML");
assert.doesNotMatch(source, /SCHOOL_SUPABASE_DB_URL|CASH_SUPABASE_DB_URL|SUPABASE_DB_URL/, "no DB URL reference allowed");
assert.match(source, /productionMounted:\s*false/, "API draft must declare no production mount");
assert.match(source, /LESSON_CLEARANCE_PRICE_POLICY_REQUIRED/, "same-price stable error code is required");
assert.match(source, /package_credit/, "package isolation must be explicit");
assert.match(source, /idempotency/, "idempotency manifest must be present");

const version = readFileSync(resolve(root, "js/config.js"), "utf8");
assert.match(version, /APP_VERSION\s*=\s*"v10\.5\.47"/, "production version must remain v10.5.47");

const productionDiff = execFileSync(
  "git",
  ["diff", "--", "lesson.html", "lesson-detail.html", "settlement.html", "js/config.js", "js/pages/lesson-page.js", "js/api/lesson-api.js", "css/app.css"],
  { cwd: root, encoding: "utf8" },
);
assert.equal(productionDiff, "", "production lesson/settlement entrypoints must remain unchanged");

console.log(`Phase 2C-B static boundary: PASS (${localFiles.length} isolated prototype files)`);
