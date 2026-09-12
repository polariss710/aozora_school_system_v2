import assert from "node:assert/strict";
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

// 2026-09-13 移除两条原型期【冻结】断言：
//   · APP_VERSION 必须保持 v10.5.47
//   · lesson/settlement 生产入口文件不得有未提交 diff
// 二者都假定 phase2c-b 原型开发期间生产不动。该冻结期早已结束（生产已到
// v10.5.65），这两条从 v10.5.48 起就一直失败，只会持续报红、淹没真实失败。
//
// ⚠️ 保留本文件而非整个删除：上面对 local/phase2c-b/ 的 7 条边界检查仍然有效，
//    其中「不得直接 .rpc()」「不得表 DML」「不得出现 DB URL」对应 AGENTS.md
//    的硬规则，那个原型目录至今仍在仓库里。

console.log(`Phase 2C-B static boundary: PASS (${localFiles.length} isolated prototype files)`);
