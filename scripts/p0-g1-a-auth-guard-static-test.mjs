import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";

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
  "wage.html", "wage-detail.html", "expense.html", "expense-detail.html",
  "income.html", "income-detail.html", "settlement.html", "settlement-detail.html",
];

// 已定要开放但库内前置未完成的页面写在这里，钉死它们不在白名单里，
// 避免被顺手加回来。前置做完时，把对应行移进 FINANCE_PAGES。
// 2026-09-11：结算两页的前置（库 + Edge）已全部完成，故本表暂空。
const PENDING_PAGES = {};

const operatorPages = allowlistFor("operator");
const readOnlyPages = allowlistFor("read_only");

assert.deepEqual([...operatorPages].sort(), [...TEACHING_PAGES, ...FINANCE_PAGES].sort());
// read_only 是给「只看课务」的账号预留的，不该跟着拿到账目页面。
assert.deepEqual([...readOnlyPages].sort(), [...TEACHING_PAGES].sort());
assert.doesNotMatch(guard, /ROLE_PAGE_ALLOWLIST\.read_only\s*=\s*ROLE_PAGE_ALLOWLIST\.operator/);

for (const [page, why] of Object.entries(PENDING_PAGES)) {
  assert.equal(operatorPages.has(page), false, `${page} 尚不能开放：${why}`);
}

// 外部授课是塾长个人的收入，永久排除；工资规则改的是单价，不是记账。
for (const page of ["part-time-work.html", "part-time-work-annual.html",
                    "wage-rule.html", "wage-rule-detail.html",
                    "reimbursement.html", "profit-summary.html"]) {
  assert.equal(operatorPages.has(page), false, `operator 不应含 ${page}`);
  assert.equal(readOnlyPages.has(page), false, `read_only 不应含 ${page}`);
}

// ---------------------------------------------------------------------------
// 缓存链：模块改了却不升键，等于这次改动没有发布
// ---------------------------------------------------------------------------
//
// 2026-09-10 的 b973808 就是这样：白名单改了，加载链接一个没动。浏览器会继续
// 用缓存里的旧模块，页面开放与 read_only 拆分全部不生效，而一切看起来都
// 「已发布」。这一类原先完全没有覆盖。
//
// 只升 auth-guard.js 的键【也不够】：浏览器命中的是 HTML 里那个入口模块 URL，
// 入口模块的缓存副本没换，就根本读不到 auth-guard 的新地址。整条
// HTML → 入口模块 → auth-guard → auth-api 都要纳入（Codex 2026-09-11 P1）。
//
// 判断「该不该升键」要拿改动去比【线上正在跑的那一版】，不是比 HEAD——
// 漏升键的改动一旦提交，比 HEAD 就永远相等，门槛自动失效（同上 P2）。
// 基线文件由 scripts/refresh-auth-guard-chain-baseline.mjs 在发布后刷新。
const baseline = JSON.parse(readFileSync("scripts/auth-guard-chain-baseline.json", "utf8"));

// 当前每个模块实际被哪些键加载
const currentKeys = new Map();
const noteKey = (modulePath, key) => {
  if (!currentKeys.has(modulePath)) currentKeys.set(modulePath, new Set());
  currentKeys.get(modulePath).add(key);
};

for (const htmlFile of rootHtmlFiles) {
  const html = readFileSync(htmlFile, "utf8");
  for (const [, modPath, key] of html.matchAll(
    /<script type="module" src="\.\/(js\/[A-Za-z0-9_-]+\.js)\?v=([^"]+)">/g
  )) {
    noteKey(modPath, key);
    for (const [, , guardKey] of readFileSync(modPath, "utf8")
      .matchAll(/\.\/(auth-guard\.js)\?v=([^"']+)/g)) {
      noteKey("js/auth-guard.js", guardKey);
    }
  }
}
for (const [, , apiKey] of guard.matchAll(/\.\/(api\/auth-api\.js)\?v=([^"']+)/g)) {
  noteKey("js/api/auth-api.js", apiKey);
}

assert.ok(currentKeys.size > 0, "没扫到任何模块加载链接");

for (const [modulePath, keys] of currentKeys) {
  // 其一：同一个模块在全仓库只能有一个键。只升了一部分文件时，新旧键会并存。
  assert.equal(
    keys.size, 1,
    `${modulePath} 的缓存键不一致，说明只升了一部分加载点：${[...keys].join(" / ")}`
  );

  // 其二：内容相对发布基线有改动时，键必须一起变。这条才抓得住「整个忘了升」。
  const recorded = baseline.modules[modulePath];
  if (!recorded) continue;  // 基线之后新增的模块，下次刷新基线时纳入
  const digest = createHash("sha256").update(readFileSync(modulePath)).digest("hex");
  if (digest === recorded.sha256) continue;
  for (const key of recorded.loadedWith) {
    assert.equal(
      keys.has(key), false,
      `${modulePath} 相对发布基线 ${baseline.ref} 已改动，但缓存键仍是 ${key}——` +
      "浏览器会继续用缓存里的旧模块，这次改动不会生效"
    );
  }
}

console.log("P0_G1_A_AUTH_GUARD_STATIC_TEST_PASS");
