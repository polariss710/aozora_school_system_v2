import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const AUTH_ASSET_VERSION = "p0-g1-a-20260804-1";
const rootHtmlFiles = readdirSync(".")
  .filter((file) => file.endsWith(".html") && file !== "login.html")
  .sort();

assert.equal(rootHtmlFiles.length, 31, "all 31 V2 business HTML entries must be guarded");

for (const htmlFile of rootHtmlFiles) {
  const html = readFileSync(htmlFile, "utf8");
  assert.match(html, /<html lang="zh-CN" class="auth-pending">/, `${htmlFile} must fail closed`);
  assert.match(
    html,
    /css\/app\.css\?v=[^"?]+/,
    `${htmlFile} must load versioned no-flash CSS`
  );

  const moduleMatch = html.match(/<script type="module" src="\.\/(js\/[^"?]+\.js)\?v=([^"?]+)"><\/script>/);
  assert.ok(moduleMatch, `${htmlFile} must have a versioned entry module`);
  assert.ok(moduleMatch[2].length >= 8, `${htmlFile} entry module cache must be versioned`);

  const entry = readFileSync(moduleMatch[1], "utf8");
  assert.ok(
    entry.indexOf("import { requireGlobalSession }") >= 0 &&
      entry.indexOf("import { requireGlobalSession }") < entry.indexOf("const globalSessionPromise"),
    `${moduleMatch[1]} must import the guard before executing it`
  );
  assert.equal((entry.match(/requireGlobalSession\(\)/g) || []).length, 1);
  assert.equal((entry.match(/await globalSessionPromise/g) || []).length, 1);
  if (htmlFile === "business-entity.html") {
    assert.ok(
      entry.indexOf("await globalSessionPromise") < entry.indexOf("window.location.replace"),
      "retired entry must verify authority before redirecting"
    );
    continue;
  }
  const initName = entry.match(/import\s*\{\s*(init[A-Z][A-Za-z0-9_]*)\s*\}/)?.[1];
  assert.ok(initName, `${moduleMatch[1]} must import its page initializer`);
  const initIndex = entry.indexOf(`${initName}(`, entry.indexOf("await globalSessionPromise"));
  assert.ok(initIndex >= 0, `${moduleMatch[1]} must contain its page initializer`);
  assert.ok(
    entry.indexOf("await globalSessionPromise") < initIndex,
    `${moduleMatch[1]} must await authority before page initialization`
  );
}

const loginHtml = readFileSync("login.html", "utf8");
assert.doesNotMatch(loginHtml, /auth-pending/);
assert.match(loginHtml, /type="email"/);
assert.match(loginHtml, /type="password"/);
assert.doesNotMatch(loginHtml, /sign\s*up|signup|注册/i);
assert.match(loginHtml, /js\/login-app\.js\?v=[^"?]+/);

const authApi = readFileSync("js/api/auth-api.js", "utf8");
assert.match(authApi, /supabase\.auth\.getUser\(\)/);
assert.match(authApi, /school_get_current_app_membership/);
assert.match(authApi, /membership\.user_id !== user\.id/);
assert.match(authApi, /membership\.is_active !== true/);
assert.match(authApi, /VALID_ROLES\.has\(membership\.role\)/);
assert.match(authApi, /signInWithPassword/);
assert.doesNotMatch(authApi, /service_role|service-role/i);
assert.doesNotMatch(authApi, /user\.email\s*===|membership.*email|email.*membership/i);

const guard = readFileSync("js/auth-guard.js", "utf8");
assert.match(guard, /verifyCurrentAuthContext\(\)/);
assert.match(guard, /event === "SIGNED_OUT"/);
assert.match(guard, /"TOKEN_REFRESHED", "USER_UPDATED"/);
assert.match(guard, /window\.location\.replace/);
assert.match(guard, /new Promise\(\(\) => \{\}\)/);
assert.match(guard, /document\.documentElement\.classList\.remove\("auth-pending"\)/);

const loginApp = readFileSync("js/login-app.js", "utf8");
assert.match(loginApp, /raw\.startsWith\("\/\/"\)/);
assert.match(loginApp, /candidate\.origin !== window\.location\.origin/);
assert.match(loginApp, /candidate\.pathname\.startsWith\(basePath\)/);
assert.match(loginApp, /candidate\.pathname === loginUrl\.pathname/);
assert.match(loginApp, /passwordInput\.value = ""/);
assert.doesNotMatch(loginApp, /access_token|refresh_token/i);

const legacyAuth = readFileSync("js/auth.js", "utf8");
assert.match(legacyAuth, /\.\/api\/auth-api\.js/);
assert.doesNotMatch(legacyAuth, /supabase-client|supabase\.auth/);

const client = readFileSync("js/supabase-client.js", "utf8");
assert.match(client, /autoRefreshToken: true/);
assert.match(client, /persistSession: true/);
assert.match(client, /detectSessionInUrl: false/);
assert.doesNotMatch(client, /keyPrefix|slice\(0, 5\)/);

assert.match(
  authApi,
  /supabase-client\.js\?v=p1-b2b-auth-storage-20260810-1/,
  "auth-api must import the single versioned canonical Supabase client"
);
for (const file of readdirSync("js", { recursive: true }).filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/${file}`, "utf8");
  assert.doesNotMatch(
    source,
    /supabase-client\.js(?!\?v=p1-b2b-auth-storage-20260810-1)/,
    `js/${file} must use the single versioned canonical Supabase client URL`
  );
}

const css = readFileSync("css/app.css", "utf8");
assert.match(css, /html\.auth-pending body\s*\{\s*visibility: hidden;/);
assert.match(css, /html\.auth-authorized body\s*\{\s*visibility: visible;/);

console.log("P0_G1_A_AUTH_GUARD_STATIC_TEST_PASS");
