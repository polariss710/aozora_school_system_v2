import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import {
  LEGACY_AUTH_STORAGE_KEY,
  removeLegacyAuthStorage,
  V2_AUTH_STORAGE_KEY,
} from "../js/auth-storage-isolation.js";

class SyntheticStorage {
  constructor(entries = []) {
    this.values = new Map(entries);
  }
  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }
  removeItem(key) {
    this.values.delete(key);
  }
}

assert.notEqual(V2_AUTH_STORAGE_KEY, LEGACY_AUTH_STORAGE_KEY);
assert.equal(V2_AUTH_STORAGE_KEY, "aozora-school-v2-auth-v1");

const flowId = "0123456789abcdef0123456789abcdef";
const unrelated = [
  ["theme", "dark"],
  ["language", "zh-CN"],
  ["other-app-auth", "synthetic-other-session"],
  ["unrelated-cache-marker", "keep"],
];
const storage = new SyntheticStorage([
  ...unrelated,
  [LEGACY_AUTH_STORAGE_KEY, "synthetic-old-session"],
  [`${LEGACY_AUTH_STORAGE_KEY}-user`, "synthetic-old-user"],
  [`${LEGACY_AUTH_STORAGE_KEY}-code-verifier`, "synthetic-old-verifier"],
  [`${LEGACY_AUTH_STORAGE_KEY}-flows-code-verifier`, JSON.stringify([flowId])],
  [`${LEGACY_AUTH_STORAGE_KEY}-flow-${flowId}-code-verifier`, "synthetic-flow-verifier"],
  [V2_AUTH_STORAGE_KEY, "synthetic-new-session"],
]);

assert.deepEqual(removeLegacyAuthStorage(storage), { removedKeyCount: 5 });
for (const [key, value] of [...unrelated, [V2_AUTH_STORAGE_KEY, "synthetic-new-session"]]) {
  assert.equal(storage.getItem(key), value, `${key} must remain unchanged`);
}
for (const key of [
  LEGACY_AUTH_STORAGE_KEY,
  `${LEGACY_AUTH_STORAGE_KEY}-user`,
  `${LEGACY_AUTH_STORAGE_KEY}-code-verifier`,
  `${LEGACY_AUTH_STORAGE_KEY}-flows-code-verifier`,
  `${LEGACY_AUTH_STORAGE_KEY}-flow-${flowId}-code-verifier`,
]) {
  assert.equal(storage.getItem(key), null, `${key} must be removed`);
}

assert.throws(
  () => removeLegacyAuthStorage(new SyntheticStorage([
    [`${LEGACY_AUTH_STORAGE_KEY}-flows-code-verifier`, "not-json"],
  ])),
  /legacy_auth_flow_index_invalid/
);

const client = readFileSync("js/supabase-client.js", "utf8");
assert.match(client, /storageKey:\s*V2_AUTH_STORAGE_KEY/);
assert.match(client, /removeLegacyAuthStorage\(window\.localStorage\)/);
assert.doesNotMatch(client, /setSession|localStorage\.clear|sessionStorage\.clear/);

const authSource = [
  client,
  readFileSync("js/api/auth-api.js", "utf8"),
  readFileSync("js/auth-guard.js", "utf8"),
  readFileSync("js/login-app.js", "utf8"),
].join("\n");
assert.doesNotMatch(authSource, /console\.(log|debug|info|warn|error)\([^\n]*(session|token)/i);

const businessEntries = readdirSync(".").filter(
  (file) => file.endsWith(".html") && file !== "login.html"
);
assert.equal(businessEntries.length, 31);
for (const htmlFile of businessEntries) {
  const html = readFileSync(htmlFile, "utf8");
  const modulePath = html.match(/<script type="module" src="\.\/(js\/[^"?]+\.js)(?:\?[^"\s]+)?"><\/script>/)?.[1];
  assert.ok(modulePath, `${htmlFile}: missing module entry`);
  const moduleSource = readFileSync(modulePath, "utf8");
  assert.match(moduleSource, /auth-guard\.js\?v=p1-b2b-auth-storage-20260810-1/);
}

console.log("P1_B2B_AUTH_STORAGE_STATIC_TEST_PASS");
