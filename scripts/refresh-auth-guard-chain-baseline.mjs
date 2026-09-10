// 刷新会话守卫加载链的【发布基线】。
//
// 为什么需要基线：缓存键的作用是让浏览器丢掉旧文件。判断「该不该升键」必须
// 拿改动去比【线上正在跑的那一版】，不是比 HEAD——一旦漏升键的改动提交了，
// 比 HEAD 就永远相等，门槛自动失效（Codex 2026-09-11 P2）。
//
// 基线取自最后推送的提交（默认 origin/main），因为 GitHub Pages 发的就是它。
//
// 用法（发布之后、把新版推上去之后再跑）：
//   node scripts/refresh-auth-guard-chain-baseline.mjs [ref]
//   git add scripts/auth-guard-chain-baseline.json
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";

const ref = process.argv[2] || "origin/main";
const BASELINE = "scripts/auth-guard-chain-baseline.json";

const git = (args) => execFileSync("git", args, { encoding: "utf8" });
const show = (path) => {
  try {
    return git(["show", `${ref}:${path}`]);
  } catch {
    return null;
  }
};
const sha = (text) => createHash("sha256").update(text).digest("hex");

const ENTRY_RE = /<script type="module" src="\.\/(js\/[A-Za-z0-9_-]+\.js)\?v=([^"]+)">/g;
const GUARD_RE = /\.\/(auth-guard\.js)\?v=([^"']+)/g;
const API_RE = /\.\/(api\/auth-api\.js)\?v=([^"']+)/g;

const modules = {};
const record = (path, key) => {
  const content = show(path);
  if (content === null) return;
  modules[path] ??= { sha256: sha(content), loadedWith: [] };
  if (key && !modules[path].loadedWith.includes(key)) modules[path].loadedWith.push(key);
};

const pages = git(["ls-tree", "-r", "--name-only", ref])
  .split("\n")
  .filter((p) => /^[^/]+\.html$/.test(p) && p !== "login.html");

for (const page of pages) {
  const html = show(page);
  if (html === null) continue;
  for (const [, modPath, key] of html.matchAll(ENTRY_RE)) {
    record(modPath, key);
    // 入口模块 → auth-guard.js
    const entry = show(modPath);
    if (entry === null) continue;
    for (const [, , guardKey] of entry.matchAll(GUARD_RE)) record("js/auth-guard.js", guardKey);
  }
}

// auth-guard.js → api/auth-api.js
const guard = show("js/auth-guard.js");
if (guard !== null) {
  for (const [, , apiKey] of guard.matchAll(API_RE)) record("js/api/auth-api.js", apiKey);
}

const out = {
  note: "会话守卫加载链的发布基线。由 scripts/refresh-auth-guard-chain-baseline.mjs 生成，请勿手改。",
  ref: git(["rev-parse", "--short", ref]).trim(),
  modules: Object.fromEntries(Object.entries(modules).sort(([a], [b]) => a.localeCompare(b))),
};
writeFileSync(BASELINE, `${JSON.stringify(out, null, 2)}\n`);
console.log(`基线已写入 ${BASELINE}：ref=${out.ref}，${Object.keys(modules).length} 个模块`);
