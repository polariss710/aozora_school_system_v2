import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  handleSettlementOnlineRequest,
  mapSettlementOnlineError,
  parseLockSettlementRequest,
  parseSaveSettlementRequest,
  sanitizeOnlineResult,
} from "../supabase/functions/_shared/student-settlement-online-contract.ts";

const ROOT = process.cwd();
const UUID = "123e4567-e89b-42d3-a456-426614174000";
const UUID_2 = "223e4567-e89b-42d3-a456-426614174000";
const HASH = "a".repeat(64);
const HASH_2 = "b".repeat(64);

function validSave(overrides = {}) {
  return {
    student_id: UUID,
    settlement_month: "2026-07",
    source_treatment_mode: "separate_makeup_and_overage_v1",
    settlement_exchange_rate: null,
    settlement_exchange_rate_source: null,
    settlement_exchange_rate_effective_date: null,
    adjustment_mode: "carry_final_balance",
    manual_adjustment_amount_cny: null,
    reason: "负责人确认保留待补义务",
    note: null,
    expected_preview_manifest_sha256: HASH,
    expected_lesson_variance_manifest_sha256: HASH_2,
    expected_source_count: 2,
    expected_unused_planned_credit_jpy: "20000.00",
    expected_overage_charge_jpy: "0",
    expected_net_lesson_variance_jpy: "-20000.00",
    expected_net_lesson_variance_cny: "-1000.1250",
    expected_system_difference_cny: "0.00",
    expected_final_carryover_cny: "0.00",
    expected_source_treatment_draft_id: null,
    expected_source_treatment_draft_updated_at: null,
    expected_adjustment_draft_id: null,
    expected_adjustment_draft_updated_at: null,
    ...overrides,
  };
}

function validLock(overrides = {}) {
  return {
    student_id: UUID,
    settlement_month: "2026-07",
    expected_source_treatment_draft_id: UUID,
    expected_source_treatment_draft_updated_at: "2026-08-09T12:34:56.123456+09:00",
    expected_adjustment_draft_id: UUID_2,
    expected_adjustment_draft_updated_at: "2026-08-09T12:34:57Z",
    expected_preview_manifest_sha256: HASH,
    expected_lesson_variance_manifest_sha256: HASH_2,
    expected_source_count: 2,
    expected_unused_planned_credit_jpy: "20000.00",
    expected_overage_charge_jpy: "0",
    expected_net_lesson_variance_jpy: "-20000.00",
    expected_net_lesson_variance_cny: "-1000.1250",
    expected_system_difference_cny: "0.00",
    expected_final_carryover_cny: "0.00",
    note: null,
    confirm_lock: true,
    ...overrides,
  };
}

test("strict parsers preserve authoritative decimal strings", () => {
  const save = parseSaveSettlementRequest(validSave());
  const lock = parseLockSettlementRequest(validLock());
  assert.equal(save.expected_net_lesson_variance_cny, "-1000.1250");
  assert.equal(lock.expected_final_carryover_cny, "0.00");
  assert.equal(lock.confirm_lock, true);
});

test("save accepts the explicit financial-net source mode only with rate facts", () => {
  const parsed = parseSaveSettlementRequest(validSave({
    source_treatment_mode: "net_lesson_variance_to_financial_credit_v1",
    settlement_exchange_rate: "20.1250",
    settlement_exchange_rate_source: "DB approved source",
    settlement_exchange_rate_effective_date: "2026-07-31",
    adjustment_mode: "manual_adjustment",
    manual_adjustment_amount_cny: "-10.50",
  }));
  assert.equal(parsed.settlement_exchange_rate, "20.1250");
  assert.equal(parsed.manual_adjustment_amount_cny, "-10.50");
});

test("unknown authority and cross-operation fields are rejected", () => {
  for (const field of [
    "actor_user_id", "role", "business_entity_id", "operator_authority",
    "service_role", "confirmation_text",
  ]) {
    assert.throws(() => parseSaveSettlementRequest(validSave({ [field]: "forbidden" })),
      /未声明字段/);
  }
  assert.throws(() => parseSaveSettlementRequest(validSave({ confirm_lock: true })),
    /未声明字段/);
  assert.throws(() => parseLockSettlementRequest(validLock({ reason: "cross operation" })),
    /未声明字段/);
});

test("invalid month, timestamp, decimal number and confirmation are rejected", () => {
  assert.throws(() => parseSaveSettlementRequest(validSave({ settlement_month: "2026-13" })));
  assert.throws(() => parseSaveSettlementRequest(validSave({ expected_system_difference_cny: 0 })));
  assert.throws(() => parseLockSettlementRequest(validLock({
    expected_adjustment_draft_updated_at: "2026-08-09 12:00:00",
  })));
  assert.throws(() => parseLockSettlementRequest(validLock({ confirm_lock: false })));
});

test("handler enforces origin, method, JSON, auth, admin, then wrapper", async () => {
  const calls = [];
  const dependencies = {
    createRequestId: () => UUID,
    nowMs: () => 100,
    authenticateUser: async () => {
      calls.push("auth");
      return { userId: UUID, privateContext: {} };
    },
    requireActiveAdmin: async () => calls.push("admin"),
    invokeOnlineRpc: async () => {
      calls.push("rpc");
      return {
        ok: true,
        student_id: UUID,
        year_month: "2026-07",
        actor_user_id: UUID_2,
        operator_authority: "must-not-leak",
        canonical_confirmation: "must-not-leak",
      };
    },
    log: () => {},
  };
  const config = {
    edgeName: "save-student-settlement-draft",
    action: "save",
    parseBody: parseSaveSettlementRequest,
    dependencies,
  };

  const forbiddenOrigin = await handleSettlementOnlineRequest(new Request("https://edge.test", {
    method: "POST",
    headers: { origin: "https://evil.example", "content-type": "application/json" },
    body: JSON.stringify(validSave()),
  }), config);
  assert.equal(forbiddenOrigin.status, 403);
  assert.equal(forbiddenOrigin.headers.get("access-control-allow-origin"), null);
  assert.deepEqual(calls, []);

  const response = await handleSettlementOnlineRequest(new Request("https://edge.test", {
    method: "POST",
    headers: {
      origin: "https://polariss710.github.io",
      authorization: "Bearer valid-user-jwt",
      "content-type": "application/json",
    },
    body: JSON.stringify(validSave()),
  }), config);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("access-control-allow-origin"),
    "https://polariss710.github.io");
  assert.deepEqual(calls, ["auth", "admin", "rpc"]);
  const body = await response.json();
  assert.equal(body.request_id, UUID);
  assert.equal(body.result.actor_user_id, undefined);
  assert.equal(body.result.operator_authority, undefined);
  assert.equal(body.result.canonical_confirmation, undefined);
});

test("every JSON failure includes a server request id", async () => {
  const response = await handleSettlementOnlineRequest(new Request("https://edge.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(validSave()),
  }), {
    edgeName: "save-student-settlement-draft",
    action: "save",
    parseBody: parseSaveSettlementRequest,
    dependencies: {
      createRequestId: () => UUID,
      nowMs: () => 1,
      authenticateUser: async () => { throw new Error("must not be reached"); },
      requireActiveAdmin: async () => {},
      invokeOnlineRpc: async () => ({}),
      log: () => {},
    },
  });
  assert.equal(response.status, 401);
  assert.equal((await response.json()).request_id, UUID);
});

test("stable database errors and response allowlist stay intact", () => {
  const mapped = mapSettlementOnlineError({
    code: "P0001",
    message: "SETTLEMENT_PREVIEW_MANIFEST_STALE",
  });
  assert.equal(mapped.status, 409);
  assert.equal(mapped.action, "repreview");
  for (const code of [
    "SETTLEMENT_MONTH_NOT_CLOSED",
    "SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED",
  ]) {
    const monthBlocked = mapSettlementOnlineError({ code: "P0001", message: code });
    assert.equal(monthBlocked.status, 409);
    assert.equal(monthBlocked.action, "stop");
    assert.doesNotMatch(monthBlocked.message, /SQL|function|schema|service.role/i);
  }
  const result = sanitizeOnlineResult("lock", {
    settlement_id: UUID,
    actor_user_id: UUID_2,
    operator_authority: "hidden",
    canonical_confirmation: "hidden",
  });
  assert.deepEqual(result, { settlement_id: UUID });
});

test("static permission, deployment-unit and browser boundaries", async () => {
  const [save, lock, runtime, contract, config, api] = await Promise.all([
    read("supabase/functions/save-student-settlement-draft/index.ts"),
    read("supabase/functions/lock-student-settlement/index.ts"),
    read("supabase/functions/_shared/student-settlement-online-runtime.ts"),
    read("supabase/functions/_shared/student-settlement-online-contract.ts"),
    read("supabase/config.toml"),
    read("js/api/student-settlement-online-api.js"),
  ]);
  assert.match(save, /school_save_student_monthly_settlement_draft_online_admin/);
  assert.doesNotMatch(save, /school_lock_student_monthly_settlement_online_admin/);
  assert.match(lock, /school_lock_student_monthly_settlement_online_admin/);
  assert.doesNotMatch(lock, /school_save_student_monthly_settlement_draft_online_admin/);
  assert.doesNotMatch(save + lock + runtime, /school_(?:unlock|relock)_student_monthly_settlement/);
  assert.doesNotMatch(save + lock, /functions\.invoke|fetch\s*\(/);
  assert.equal((runtime.match(/SCHOOL_SERVICE_ROLE_KEY/g) || []).length, 1);
  assert.doesNotMatch(contract + api, /SCHOOL_SERVICE_ROLE_KEY/);
  assert.match(config, /\[functions\.save-student-settlement-draft\]\s*\nverify_jwt = false/);
  assert.match(config, /\[functions\.lock-student-settlement\]\s*\nverify_jwt = false/);
  assert.match(api, /school_get_student_monthly_settlement_online_status/);
  assert.match(api, /SETTLEMENT_EDGE_RESULT_UNCERTAIN/);
  assert.doesNotMatch(api, /service[_-]?role/i);

  const jsFiles = await walk(path.join(ROOT, "js"));
  const pageFiles = jsFiles.filter((file) => !file.includes(`${path.sep}api${path.sep}`));
  const pageSource = (await Promise.all(pageFiles.map((file) => readFile(file, "utf8")))).join("\n");
  const settlementPage = await read("js/pages/settlement-page.js");
  assert.match(settlementPage, /getStudentSettlementOnlineStatus/);
  assert.match(settlementPage, /saveStudentSettlementDraftOnline/);
  assert.match(settlementPage, /lockStudentSettlementOnline\(lockInput\)/);
  // 锁定 Edge 只能有 settlement-page.js 一个调用点，防止入口扩散。
  // settlement-online-state.js 的 JSDoc 会提及该 API 名，因此对它只放开
  // 文字引用，仍禁止实际调用表达式——整体排除会让它日后真的调用 Edge 也不报错。
  const otherPages = pageFiles
    .filter((file) => path.basename(file) !== "settlement-page.js");
  const otherPageSource = (await Promise.all(
    otherPages.map((file) => readFile(file, "utf8")),
  )).join("\n");
  assert.doesNotMatch(otherPageSource, /lockStudentSettlementOnline\s*\(/);
  assert.doesNotMatch(otherPageSource, /lock-student-settlement/);
  // state 模块与 page 必须使用同一缓存键，否则浏览器可能加载到旧 state 模块，
  // 出现「新导出缺失」或「跑的是旧逻辑」。
  const stateKey = /settlement-online-state\.js\?v=([A-Za-z0-9._-]+)/.exec(settlementPage);
  assert(stateKey, "settlement-page.js 未带缓存键加载 state 模块");
  assert.match(
    await readFile(path.join(ROOT, "settlement.html"), "utf8"),
    new RegExp(`settlement-app\\.js\\?v=${stateKey[1].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`),
    "state 模块的缓存键与页面入口不一致",
  );
  assert.doesNotMatch(pageSource, /SCHOOL_SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY/);

  // --- P0 金额边界的来源约束（A'）---------------------------------------
  //
  // 这条边界现在靠「登记入口不可达 + 读取入口只收 scope」保证。以下三组断言
  // 各自钉住其中一环；任何一环松掉，约束就退回一道可绕过的检查。
  const settlementApi = await read("js/api/settlement-api.js");
  const stateSource = await read("js/pages/settlement-online-state.js");

  // 一、登记入口必须模块私有。曾经它是页面层的公开导出，于是「先污染对象、
  // 再调它登记」即可把 DOM 值送进 payload——那正是 P1-1 的原问题。
  assert.doesNotMatch(settlementApi, /export[^\n]*brandAuthoritative/);
  assert.doesNotMatch(stateSource, /export[^\n]*freezeAuthoritativeSnapshot/);
  assert.doesNotMatch(pageSource, /function\s+freezeAuthoritativeSnapshot/);

  // 二、对外的两个权威读取入口，参数表只能是 scope。多一个参数就多一条
  // 调用方能操纵的通道，来源约束即不成立。
  assert.match(
    settlementApi,
    /export async function fetchAuthoritativeLockStatus\(studentId, yearMonth\)/,
  );
  assert.match(
    settlementApi,
    /export async function fetchAuthoritativeLockFacts\(studentId, yearMonth\)/,
  );
  // 锁定预览不得再经 fetchStudentSettlementAdjustmentDialogPreview——
  // 它的 payload 有 explicitUserAmountCny 直通 p_explicit_user_amount_cny。
  // 与上面 otherPages 的处理一致：放开注释里的文字引用，禁止调用与定义表达式。
  assert.doesNotMatch(settlementPage, /fetchLockPreviewFromDrafts\s*\(/);
  assert.doesNotMatch(settlementPage, /function\s+fetchLockPreviewFromDrafts/);

  // 三、WeakSet 在 settlement-api.js 的模块作用域内，凡导入该模块处必须使用
  // 同一查询串。不同查询串产生不同模块实例、各持互不相通的 WeakSet，会让所有
  // 权威快照在另一实例中判为 false。这是功能性不变式，不只是缓存卫生。
  const apiCacheKeys = new Set();
  for (const file of jsFiles) {
    const source = await readFile(file, "utf8");
    for (const hit of source.matchAll(/settlement-api\.js\?v=([A-Za-z0-9._-]+)/g)) {
      apiCacheKeys.add(hit[1]);
    }
  }
  assert.equal(
    apiCacheKeys.size, 1,
    `settlement-api.js 的导入查询串必须唯一，实际有 ${apiCacheKeys.size} 个：${[...apiCacheKeys].join(", ")}`,
  );
});

async function read(relativePath) {
  return readFile(path.join(ROOT, relativePath), "utf8");
}

async function walk(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const resolved = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await walk(resolved));
    else if (entry.isFile() && entry.name.endsWith(".js")) files.push(resolved);
  }
  return files;
}
