import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  canShowPlannedCancellationAction,
  isActiveLessonCancellationActor,
} from "../js/utils/lesson-cancellation-capability.js";

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
// Historical cache-key literals are intentionally not asserted; canonical module identity remains covered (handoff section 8.6).

function read(relativePath) {
  return readFileSync(join(projectRoot, relativePath), "utf8");
}

function authApiImports(relativePath) {
  const source = read(relativePath);
  return [...source.matchAll(/from\s+["']([^"']*auth-api\.js\?[^"']+)["']/g)]
    .map((match) => match[1]);
}

const productionJsFiles = readdirSync(join(projectRoot, "js"), { recursive: true })
  .filter((file) => file.endsWith(".js"))
  .map((file) => `js/${file}`);
const resolvedAuthModuleUrls = [];
for (const relativePath of productionJsFiles) {
  for (const specifier of authApiImports(relativePath)) {
    resolvedAuthModuleUrls.push(
      new URL(specifier, pathToFileURL(join(projectRoot, relativePath))).href
    );
  }
}
assert.ok(resolvedAuthModuleUrls.length >= 4, "expected all production auth-api consumers");
assert.equal(
  new Set(resolvedAuthModuleUrls).size,
  1,
  "production auth-api consumers must resolve to one ES Module URL identity"
);

const guardAuthSpecifier = authApiImports("js/auth-guard.js")[0];
const lessonAuthSpecifier = authApiImports("js/pages/lesson-page.js")[0];
assert.ok(guardAuthSpecifier && lessonAuthSpecifier);
assert.equal(
  new URL(guardAuthSpecifier, pathToFileURL(join(projectRoot, "js/auth-guard.js"))).href,
  new URL(lessonAuthSpecifier, pathToFileURL(join(projectRoot, "js/pages/lesson-page.js"))).href
);

async function verifySharedContext(label) {
  const fixtureRoot = mkdtempSync(join(tmpdir(), `aozora-auth-context-${label}-`));
  try {
    mkdirSync(join(fixtureRoot, "js/api"), { recursive: true });
    mkdirSync(join(fixtureRoot, "js/pages"), { recursive: true });
    writeFileSync(join(fixtureRoot, "js/api/auth-api.js"), read("js/api/auth-api.js"));
    writeFileSync(join(fixtureRoot, "js/supabase-client.js"), `
      export const hasSupabaseConfig = () => true;
      const session = { access_token: "synthetic-session" };
      const user = { id: "synthetic-user" };
      const membership = { user_id: user.id, is_active: true, role: "admin" };
      export const supabase = {
        auth: {
          getSession: async () => ({ data: { session }, error: null }),
          getUser: async () => ({ data: { user }, error: null }),
          signInWithPassword: async () => ({ error: null }),
          signOut: async () => ({ error: null }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
        },
        rpc: async (name) => {
          if (name !== "school_get_current_app_membership") throw new Error(name);
          return { data: membership, error: null };
        },
      };
    `);
    writeFileSync(join(fixtureRoot, "js/auth-guard-bridge.js"), `
      import { verifyCurrentAuthContext } from ${JSON.stringify(guardAuthSpecifier)};
      export const verifyFromGuard = verifyCurrentAuthContext;
    `);
    writeFileSync(join(fixtureRoot, "js/pages/lesson-page-bridge.js"), `
      import { getCurrentAuthContext } from ${JSON.stringify(lessonAuthSpecifier)};
      export const readFromLessonPage = getCurrentAuthContext;
    `);

    const guardBridgeUrl = pathToFileURL(join(fixtureRoot, "js/auth-guard-bridge.js")).href;
    const pageBridgeUrl = pathToFileURL(join(fixtureRoot, "js/pages/lesson-page-bridge.js")).href;
    const guardBridge = await import(guardBridgeUrl);
    const pageBridge = await import(pageBridgeUrl);
    const verified = await guardBridge.verifyFromGuard();
    assert.equal(verified.membership.role, "admin");
    assert.strictEqual(
      pageBridge.readFromLessonPage().membership,
      verified.membership,
      `${label}: guard writer and lesson reader must share one auth context instance`
    );
    const warmPageBridge = await import(pageBridgeUrl);
    assert.strictEqual(
      warmPageBridge.readFromLessonPage(),
      pageBridge.readFromLessonPage(),
      `${label}: warm imports must retain one context object`
    );
  } finally {
    rmSync(fixtureRoot, { recursive: true, force: true });
  }
}

await verifySharedContext("cold");
await verifySharedContext("reload");

const authContext = (role, isActive = true) => ({
  membership: { role, is_active: isActive },
});
const planned = {
  id: "planned-1",
  lesson_type: "planned",
  status: "planned",
  voided_at: null,
};
const canShow = (overrides = {}) => canShowPlannedCancellationAction({
  authContext: authContext("admin"),
  planned,
  hasLinkedActual: false,
  ...overrides,
});

assert.equal(isActiveLessonCancellationActor(authContext("admin")), true);
assert.equal(isActiveLessonCancellationActor(authContext("operator")), true);
assert.equal(isActiveLessonCancellationActor(authContext("read_only")), false);
assert.equal(isActiveLessonCancellationActor(authContext("admin", false)), false);
assert.equal(isActiveLessonCancellationActor({ membership: null }), false);
assert.equal(isActiveLessonCancellationActor(null), false);

assert.equal(canShow(), true);
assert.equal(canShow({ authContext: authContext("operator") }), true);
assert.equal(canShow({ authContext: authContext("read_only") }), false);
assert.equal(canShow({ authContext: authContext("admin", false) }), false);
assert.equal(canShow({ authContext: { membership: null } }), false);
assert.equal(canShow({ authContext: null }), false);
assert.equal(canShow({ hasLinkedActual: true }), false);
assert.equal(canShow({ planned: { ...planned, status: "pending_makeup" } }), false);
assert.equal(canShow({ planned: { ...planned, status: "makeup_completed" } }), false);
assert.equal(canShow({ planned: { ...planned, voided_at: "2026-08-12T00:00:00Z" } }), false);
assert.equal(canShow({ planned: { ...planned, lesson_type: "actual" } }), false);

for (const tuitionHistory of [
  {},
  { tuition_revision_count: 1, active_tuition_revision_count: 1 },
  { tuition_revision_count: 1, voided_tuition_revision_count: 1 },
]) {
  assert.equal(canShow({ planned: { ...planned, ...tuitionHistory } }), true);
}

const lessonPage = read("js/pages/lesson-page.js");
const lessonDetailPage = read("js/pages/lesson-detail-page.js");
const renderMissing = lessonPage.match(
  /function renderMissingActualCard\([\s\S]*?\n}\n\nfunction canMarkCancelledActualFromPlanned/
)?.[0] || "";
assert.match(renderMissing, /data-generate-actual-id/);
assert.match(renderMissing, /data-generate-cancelled-actual-id/);
assert.match(renderMissing, />取消并转待补课<\/button>/);
assert.equal((renderMissing.match(/data-generate-cancelled-actual-id/g) || []).length, 1);
assert.doesNotMatch(lessonDetailPage, /generate-cancelled-actual|取消并转待补课/);
assert.match(lessonPage, /if \(hasTuitionRevisionHistory\(record\)\) \{\s*return "";/);
assert.doesNotMatch(lessonPage, /\.rpc\s*\(|supabase\.(?:from|rpc)\s*\(/);

console.log("School V2 cancellation auth-context, role, state, tuition and view matrices: PASS");
