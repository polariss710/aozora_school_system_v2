import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

// Historical cache-key literals are intentionally not asserted; see the week-close handoff section 8.6.
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
  /supabase-client\.js/,
  "auth-api must import the canonical Supabase client resource"
);
// The former exact-key cross-file assertion was removed under handoff section 8.6.

const css = readFileSync("css/app.css", "utf8");
assert.match(css, /html\.auth-pending body\s*\{\s*visibility: hidden;/);
assert.match(css, /html\.auth-authorized body\s*\{\s*visibility: visible;/);

// 角色页面白名单是 fail-closed 的安全边界，悄悄变宽不会有人发现。按【集合】比对，
// 不是 assert.match —— 正则只能证明某一行在，证明不了没有多出别的行。
function allowlistFor(role) {
  const block = new RegExp(`${role}:\\s*new Set\\(\\[([\\s\\S]*?)\\]\\)`).exec(guard);
  assert.ok(block, `找不到 ${role} 的白名单`);
  return new Set([...block[1].matchAll(/"([^"]+\.html)"/g)].map((m) => m[1]));
}

const TEACHING_PAGES = [
  "student.html", "lesson.html", "lesson-detail.html", "teacher.html",
  "quote-plan.html", "contract-generator.html", "weekly-lesson-dashboard.html",
  "weekly-schedule-image.html", "classroom-schedule.html",
];
// 2026-09-10：教务老师兼任财务，账目页面开放；写操作的分层在数据库，不在这里。
const FINANCE_PAGES = [
  "wage.html", "wage-detail.html",
  "income.html", "income-detail.html", "expense.html", "expense-detail.html",
];
// 月度结算的草稿保存仍是 active-admin 专用（Edge 的
// school_save_student_monthly_settlement_draft_online_admin）。在那批改完之前
// 放开页面，只会得到「进得去但存不了」。钉死它不在白名单里，避免被顺手加回来。
const SETTLEMENT_PAGES_PENDING = ["settlement.html", "settlement-detail.html"];

const operatorPages = allowlistFor("operator");
const readOnlyPages = allowlistFor("read_only");

assert.deepEqual([...operatorPages].sort(), [...TEACHING_PAGES, ...FINANCE_PAGES].sort());
// read_only 是给「只看课务」的账号预留的，不该跟着拿到账目页面。
assert.deepEqual([...readOnlyPages].sort(), [...TEACHING_PAGES].sort());
assert.doesNotMatch(guard, /ROLE_PAGE_ALLOWLIST\.read_only\s*=\s*ROLE_PAGE_ALLOWLIST\.operator/);

for (const page of SETTLEMENT_PAGES_PENDING) {
  assert.equal(operatorPages.has(page), false,
    `${page} 的草稿保存 Edge 仍是 admin 专用，此时放开只会「进得去但存不了」`);
}

// 外部授课是塾长个人的收入，永久排除；工资规则改的是单价，不是记账。
for (const page of ["part-time-work.html", "part-time-work-annual.html",
                    "wage-rule.html", "wage-rule-detail.html",
                    "reimbursement.html", "profit-summary.html"]) {
  assert.equal(operatorPages.has(page), false, `operator 不应含 ${page}`);
  assert.equal(readOnlyPages.has(page), false, `read_only 不应含 ${page}`);
}

// ---------------------------------------------------------------------------
// 缓存键：auth-guard.js 改了却不升键，等于这次改动没有发布
// ---------------------------------------------------------------------------
//
// 2026-09-10 的 b973808 就是这样：白名单改了，93 个加载链接一个没动。
// 浏览器会继续用缓存里的旧模块，页面开放与 read_only 拆分全部不生效，
// 而一切看起来都「已发布」。这一类静态测试原先完全没有覆盖。
//
// 具体键值不钉（见文件开头的约定），钉的是两条不变量。
function gitLines(args) {
  return execFileSync("git", args, { encoding: "utf8" });
}

const loaders = gitLines(["grep", "-h", "-o", "auth-guard\\.js?v=[^\"']*", "--", ".", ":!local"])
  .split("\n")
  .filter(Boolean);
assert.ok(loaders.length > 0, "找不到任何 auth-guard.js 的加载链接");

// 其一：全仓库只能有一个键。漏改一部分文件时，新旧键会并存。
const keys = new Set(loaders);
assert.equal(
  keys.size, 1,
  `auth-guard.js 的缓存键不一致，说明只升了一部分文件：${[...keys].join(" / ")}`
);

// 其二：auth-guard.js 相对 HEAD 有改动时，键必须一起变。
// 这条才抓得住「整个忘了升」。不在 git 仓库或文件尚未入库时跳过。
let headGuard = null;
try {
  headGuard = gitLines(["show", "HEAD:js/auth-guard.js"]);
} catch {
  headGuard = null;
}
if (headGuard !== null && headGuard !== guard) {
  const headKeys = new Set(
    gitLines(["grep", "-h", "-o", "auth-guard\\.js?v=[^\"']*", "HEAD", "--", ".", ":!local"])
      .split("\n")
      .filter(Boolean)
      .map((line) => line.replace(/^HEAD:/, ""))
  );
  for (const key of headKeys) {
    assert.equal(
      keys.has(key), false,
      `js/auth-guard.js 相对 HEAD 已改动，但缓存键仍是 ${key}——` +
      "浏览器会继续用缓存里的旧模块，这次改动不会生效"
    );
  }
}

console.log("P0_G1_A_AUTH_GUARD_STATIC_TEST_PASS");
