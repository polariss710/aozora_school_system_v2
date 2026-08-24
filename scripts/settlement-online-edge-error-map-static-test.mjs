import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// 学生月度结算在线 Edge 的 DB 错误映射完整性。
//
// 背景：2026-08-25 发现 supabase/functions/_shared/student-settlement-online-contract.ts
// 的 DB_ERROR_MAP 与 DB 的错误面从未系统性对齐——在线契约面 39 个 code 中，
// 5 个运行时 code 未被映射，会在 mapDbError 中退化成
// SETTLEMENT_EDGE_INTERNAL_ERROR，把明确的业务 blocker 变成不透明的内部错误。
// 其中 SETTLEMENT_REPREVIEW_REQUIRED 是正式锁定的专属 blocker，
// SETTLEMENT_SOURCE_FACTS_EMPTY 是 can_save 判定链上最常见的一条。
//
// 本测试的作用：下一个新增的 DB code 必须做出显式决定——要么映射，要么写进
// 下方的部署期白名单——否则本测试红。缺口不再靠人记得。
//
// 范围说明：只覆盖「在线 Edge 路径可达」的契约面，即下列 4 个归档 SQL。
// sql/current 全量有 149 个 SETTLEMENT_*/S1_C_* code，其余绝大多数是部署期、
// 回滚测试或本机受信工具专用，永远到不了浏览器，纳入只会产生噪音。
// 若将来在线写入路径扩展到别的 SQL，必须同步扩充 CONTRACT_SQL_FILES——
// 这一点无法由本测试自动发现，是已知的范围边界。

const CONTRACT_SQL_FILES = [
  "sql/current/school_student_settlement_online_admin_contract_20260809.sql",
  "sql/current/school_student_settlement_tokyo_month_close_guard_20260810.sql",
  "sql/current/school_student_settlement_lesson_week_close_guard_20260823.sql",
  "sql/current/school_student_settlement_online_can_save_qualification_20260810.sql",
];

const CONTRACT_TS = "supabase/functions/_shared/student-settlement-online-contract.ts";

// 部署期 / 迁移期断言：由 SQL 文件自身的 preflight、patch 形状校验或迁移守卫
// 抛出，只会在执行 SQL 文件时出现，不经由 Edge 返回浏览器。逐条点名，不用
// 正则前缀排除——正则会把将来某个真正的运行时 code 一起吞掉。
const DEPLOY_TIME_ONLY = new Set([
  // 2026-08-10 月封口 guard 的字符串补丁形状校验，共 7 处注入点
  "SETTLEMENT_MONTH_CLOSE_ADJUSTMENT_CORE_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_ELIGIBILITY_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_LOCAL_LOCK_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_LOCAL_SAVE_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_LOCK_CORE_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_SOURCE_CORE_PATCH_SHAPE_MISMATCH",
  "SETTLEMENT_MONTH_CLOSE_STATUS_PATCH_SHAPE_MISMATCH",
  // 部署前对象 / ACL 检查
  "SETTLEMENT_ONLINE_PREFLIGHT_OBJECTS_MISSING",
  "SETTLEMENT_ONLINE_PREFLIGHT_CORE_ACL_DRIFT",
  "SETTLEMENT_ONLINE_PREFLIGHT_TABLE_DML_EXPOSED",
  "SETTLEMENT_ONLINE_CAN_SAVE_R1_DEPENDENCY_MISSING",
  "SETTLEMENT_ONLINE_SAVE_ACL_INVALID",
  // 迁移保留标记
  "SETTLEMENT_TOKYO_MONTH_CLOSE_MIGRATION_HELD_FOR_ROLLBACK_TESTS",
]);

const contractTs = readFileSync(CONTRACT_TS, "utf8");

// ---------------------------------------------------------------------------
// 提取 DB_ERROR_MAP 的键
// ---------------------------------------------------------------------------
const mapBlock = /const DB_ERROR_MAP[^=]*=\s*\{([\s\S]*?)\n\};/.exec(contractTs);
assert(mapBlock, "未能在 contract.ts 中定位 DB_ERROR_MAP");
const mapped = new Set(
  [...mapBlock[1].matchAll(/^\s{2}([A-Z][A-Z0-9_]+):/gm)].map((m) => m[1])
);
assert(mapped.size > 0, "DB_ERROR_MAP 解析结果为空，正则可能已失效");

// ---------------------------------------------------------------------------
// 提取契约面 SQL 会抛出的 code
// ---------------------------------------------------------------------------
const dbCodes = new Set();
for (const file of CONTRACT_SQL_FILES) {
  const sql = readFileSync(file, "utf8");
  for (const m of sql.matchAll(/'(SETTLEMENT_[A-Z0-9_]+)'/g)) dbCodes.add(m[1]);
}
assert(dbCodes.size > 0, "契约面 SQL 未解析出任何 code，文件路径可能已变");

// ---------------------------------------------------------------------------
// 断言 1：每个契约面 code 要么被映射，要么被显式声明为部署期专用
// ---------------------------------------------------------------------------
const unhandled = [...dbCodes]
  .filter((c) => !mapped.has(c) && !DEPLOY_TIME_ONLY.has(c))
  .sort();
assert.deepEqual(
  unhandled,
  [],
  `以下 DB code 既未映射也未声明为部署期专用，会退化成 `
    + `SETTLEMENT_EDGE_INTERNAL_ERROR：\n  ${unhandled.join("\n  ")}\n`
    + `请在 DB_ERROR_MAP 中映射，或在本测试的 DEPLOY_TIME_ONLY 中点名并说明理由。`
);

// ---------------------------------------------------------------------------
// 断言 2：白名单不得包含实际已映射的 code（两处重复会让意图不清）
// ---------------------------------------------------------------------------
const bothPlaces = [...DEPLOY_TIME_ONLY].filter((c) => mapped.has(c)).sort();
assert.deepEqual(bothPlaces, [], `既在 DB_ERROR_MAP 又在 DEPLOY_TIME_ONLY：${bothPlaces}`);

// ---------------------------------------------------------------------------
// 断言 3：白名单不得包含契约面根本不存在的 code（防止清单僵化）
// ---------------------------------------------------------------------------
const stale = [...DEPLOY_TIME_ONLY].filter((c) => !dbCodes.has(c)).sort();
assert.deepEqual(
  stale,
  [],
  `DEPLOY_TIME_ONLY 中的以下 code 已不存在于契约面 SQL，应删除：${stale}`
);

// ---------------------------------------------------------------------------
// 断言 4：正式锁定路径的关键 blocker 必须有明确 action，不得是 stop
// SETTLEMENT_REPREVIEW_REQUIRED 表示「先 save 再 lock」，用户有明确下一步，
// 给 stop 会让人以为无解。
// ---------------------------------------------------------------------------
const repreviewEntry = /SETTLEMENT_REPREVIEW_REQUIRED:\s*\{[^}]*action:\s*"([a-z_]+)"/
  .exec(contractTs);
assert(repreviewEntry, "SETTLEMENT_REPREVIEW_REQUIRED 未映射");
assert.equal(
  repreviewEntry[1],
  "repreview",
  "SETTLEMENT_REPREVIEW_REQUIRED 的 action 必须是 repreview：用户需先完成一次 save"
);

// ---------------------------------------------------------------------------
// 断言 5：未映射 code 仍必须走 internal error 兜底，不得直接抛裸 DB 消息
// ---------------------------------------------------------------------------
assert.match(
  contractTs,
  /SETTLEMENT_EDGE_INTERNAL_ERROR/,
  "缺少 internal error 兜底"
);

console.log(
  `edge error map: 契约面 ${dbCodes.size} 个 code，已映射 ${
    [...dbCodes].filter((c) => mapped.has(c)).length
  } 个，部署期专用 ${
    [...dbCodes].filter((c) => DEPLOY_TIME_ONLY.has(c)).length
  } 个，未处理 0 个`
);
