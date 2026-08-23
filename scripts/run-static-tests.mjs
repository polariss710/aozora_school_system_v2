#!/usr/bin/env node
// 统一静态测试 runner。
//
// 目的：把「环境缺失」和「断言不成立」分开。此前 scripts/*.mjs 全量直跑时，
// 需要数据库或浏览器的测试在没有相应环境的机器上必然抛错，导致长期有 20 余个
// 红项，静态检查这道闸门实际失效——真正的回归会淹没在噪音里。
//
// 本 runner 不修改、不删除、不放松任何既有测试。它只是把结果分成三类，并且
// 只在「失败」非零时退出非零。跳过项会被逐条列出，不是静默忽略。
// 在具备数据库与浏览器的环境（例如 Codex 的执行环境）中，跳过数应为 0。
//
// 用法：
//   node scripts/run-static-tests.mjs            # 摘要
//   node scripts/run-static-tests.mjs --verbose  # 附失败详情
//   node scripts/run-static-tests.mjs --list-skipped

import { readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const SCRIPTS = path.join(ROOT, "scripts");
const SELF = path.basename(import.meta.filename);

const verbose = process.argv.includes("--verbose");
const listSkipped = process.argv.includes("--list-skipped") || verbose;

// 环境缺失的判定特征。命中即归为「跳过」而非「失败」。
// 刻意写得窄：只认明确的环境缺失信号，不认任何 AssertionError。
const ENV_SKIP_PATTERNS = [
  { re: /SCHOOL_SUPABASE_DB_URL_REQUIRED|CASH_SUPABASE_DB_URL_REQUIRED|SUPABASE_DB_URL[A-Z_]*REQUIRED/, need: "数据库连接" },
  { re: /ECONNREFUSED|ENOTFOUND|EAI_AGAIN/, need: "数据库连接" },
  { re: /\bpg_ctl\b|\binitdb\b|could not connect to server|role .* does not exist/i, need: "本地 PostgreSQL" },
  { re: /Cannot find package 'playwright'|Cannot find package 'puppeteer'|browserType\.launch|Executable doesn't exist/i, need: "浏览器运行时" },
  { re: /CHROME[A-Z_]*REQUIRED|BROWSER[A-Z_]*REQUIRED/, need: "浏览器运行时" },
  // 例如 PHASE2C_D1_NODE_MODULES_REQUIRED：测试要求 PHASE2C_*_NODE_MODULES
  // 环境变量指向一个已安装依赖的 node_modules 根目录。
  { re: /[A-Z0-9_]*NODE_MODULES_REQUIRED/, need: "DOM 依赖（PHASE2C_*_NODE_MODULES 环境变量）" },
];

function classify(stderr) {
  // AssertionError 一律算真失败，即使同时出现环境字样，避免掩盖回归。
  if (/AssertionError/.test(stderr)) return null;
  for (const { re, need } of ENV_SKIP_PATTERNS) {
    if (re.test(stderr)) return need;
  }
  return null;
}

// scripts/ 下的 .mjs 全部是测试，除了本 runner 与下列共用模块。
// 共用模块只有导出、没有副作用，直接执行会「通过」，那是假绿。
const NOT_TESTS = new Set([SELF, "static-test-helpers.mjs"]);

// 主干基线只包含 git 跟踪的测试。
//
// scripts/ 下存在有意不提交的本地原型 artifact（如 Phase 2C-B 的
// school-lesson-clearance-phase2c-b-*.mjs）。那个阶段的交付契约就是「只做
// standalone 本地原型，不碰生产入口、版本或缓存链」，D1 生产集成报告还专门
// 记录了这些受保护文件「未修改、移动、执行、暂存或提交」。
// 用 readdirSync 无差别执行会把它们卷进主干基线：既违反了「未执行」的保护
// 承诺，又让一个本地原型的失败伪装成主干红项。
//
// 因此以 git ls-files 为准。未跟踪的 .mjs 会被列出但不执行、不计入结果。
function trackedTests() {
  const out = execFileSync("git", ["ls-files", "--", "scripts/*.mjs"], {
    cwd: ROOT,
    encoding: "utf8",
  });
  return new Set(
    out.split("\n").filter(Boolean).map((p) => path.basename(p))
  );
}

let tracked;
try {
  tracked = trackedTests();
} catch (error) {
  console.error("无法调用 git ls-files，拒绝退回到无差别执行：", error.message);
  console.error("主干基线必须只包含 git 跟踪的测试，否则会执行受保护的本地原型。");
  process.exit(2);
}

const allFiles = readdirSync(SCRIPTS)
  .filter((f) => f.endsWith(".mjs") && !NOT_TESTS.has(f))
  .sort();
const files = allFiles.filter((f) => tracked.has(f));
const untracked = allFiles.filter((f) => !tracked.has(f));

const passed = [];
const skipped = [];
const failed = [];

for (const file of files) {
  try {
    execFileSync(process.execPath, [path.join(SCRIPTS, file)], {
      cwd: ROOT,
      stdio: ["ignore", "ignore", "pipe"],
      timeout: 120000,
    });
    passed.push(file);
  } catch (error) {
    const stderr = String(error.stderr || error.message || "");
    const need = classify(stderr);
    if (need) skipped.push({ file, need });
    else failed.push({ file, stderr });
  }
}

console.log(`通过 ${passed.length}  跳过 ${skipped.length}  失败 ${failed.length}  (共 ${files.length})`);

if (untracked.length) {
  console.log(`\n未执行（git 未跟踪，视为本地原型 artifact，不计入基线）：`);
  for (const f of untracked) console.log(`  ${f}`);
}

if (skipped.length && listSkipped) {
  console.log("\n跳过（环境缺失，非测试问题）：");
  const byNeed = new Map();
  for (const { file, need } of skipped) {
    if (!byNeed.has(need)) byNeed.set(need, []);
    byNeed.get(need).push(file);
  }
  for (const [need, list] of byNeed) {
    console.log(`  需要${need}：`);
    for (const f of list) console.log(`    ${f}`);
  }
} else if (skipped.length) {
  const needs = [...new Set(skipped.map((s) => s.need))].join("、");
  console.log(`（跳过项需要：${needs}。加 --list-skipped 查看清单）`);
}

if (failed.length) {
  console.log("\n失败：");
  for (const { file, stderr } of failed) {
    const line = stderr.split("\n").find((l) => /AssertionError|Error:/.test(l)) || "";
    console.log(`  ${file}`);
    if (line) console.log(`    ${line.trim().slice(0, 140)}`);
    if (verbose) {
      console.log(stderr.split("\n").slice(0, 20).map((l) => `      ${l}`).join("\n"));
    }
  }
}

process.exit(failed.length ? 1 : 0);
