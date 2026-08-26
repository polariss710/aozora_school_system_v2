// Phase D 锁定测试的共用装置：加载真实 API 层，并从中取回已登记的权威快照。
//
// 为什么测试必须走 API 层：2026-08-26 起，权威快照的登记入口收进了
// js/api/settlement-api.js 的模块作用域，不再对外导出。常规执行环境下没有导出
// 路径能自行登记一个对象，因此 buildOnlineDraftLockInput 认可的快照只能来自
// API 层的真实读取。
//
// 定位（2026-08-27 确认）：这是**防误用**，不是安全边界。后者在 DB——lock RPC
// 用库内草稿行重算 preview 并比对全部 expected_*，写入前不一致即拒绝。前端拦不住
// 蓄意伪造（supabase 客户端公开导出，可直接 invoke），也不需要拦。
//
// 代价是原本零依赖的页面层单元测试现在要拖上 supabase 客户端。这是登记入口收进
// 模块作用域的内在成本，不是可以绕开的配置问题。

// 装远程导入钩子与 window 桩。必须在加载任何 js/ 模块之前。
import "./browser-module-bootstrap.mjs";

import { readFileSync } from "node:fs";

// 必须用与 state 层完全相同的查询串导入 settlement-api.js。
//
// 权威快照的 WeakSet 在该模块作用域内，不同查询串会产生不同模块实例、各持一个
// 互不相通的 WeakSet：测试从无查询串的实例取快照、state 层拿带查询串的实例去
// 判，正常路径的 builder 会直接抛「must be a frozen authoritative snapshot」。
// 这个坑在改造当天真实踩到过。
//
// 键从源码里读，测试因而自动跟随生产的缓存键。该一致性另有静态断言看住
// （student-settlement-online-phase-b-static-test）。
const stateSource = readFileSync(
  new URL("../../js/pages/settlement-online-state.js", import.meta.url), "utf8",
);
export const apiCacheKey =
  /settlement-api\.js\?v=([A-Za-z0-9._-]+)/.exec(stateSource)?.[1];
if (!apiCacheKey) {
  throw new Error("未能从 settlement-online-state.js 读出 settlement-api.js 的缓存键");
}

export const stub = await import("./supabase-capture-stub.mjs");
export const settlementApi = await import(
  `../../js/api/settlement-api.js?v=${apiCacheKey}`
);

export const STATUS_RPC = "school_get_student_monthly_settlement_online_status";
export const PREVIEW_RPC = "school_preview_student_settlement_adjustment_dialog";

// API 层用 requireUuid 校验，fixture 必须是真实 UUID 形态。页面层测试曾用
// "S1"、"SD1" 之类的假 id，那是走不到 API 层才成立的。
export const STUDENT_ID = "11111111-1111-4111-8111-111111111111";
export const BUSINESS_ENTITY_ID = "55555555-5555-4555-8555-555555555555";
export const SOURCE_DRAFT_ID = "22222222-2222-4222-8222-222222222222";
export const ADJUSTMENT_DRAFT_ID = "33333333-3333-4333-8333-333333333333";
export const CORRELATION_ID = "44444444-4444-4444-8444-444444444444";
export const SHA_A = "a".repeat(64);
export const SHA_B = "b".repeat(64);
export const YEAR_MONTH = "2026-08";
export const AUTHORITATIVE_CARRY = "40000.00";

// DB 返回的 status 行。两份草稿上带着锁定预览所需的全部取参——API 层正是从
// 这里取，页面递不进任何值。
export function statusRow(overrides = {}) {
  return {
    contract_version: "student_settlement_online_status_v1",
    student_id: STUDENT_ID,
    year_month: YEAR_MONTH,
    business_entity_id: BUSINESS_ENTITY_ID,
    can_lock: true,
    requires_repreview: false,
    lock_blocker_code: null,
    save_blocker_code: null,
    immutable_blocker: null,
    preview_manifest_sha256: SHA_A,
    lesson_manifest_sha256: SHA_B,
    physical_settlement: { settlement_id: null },
    effective_state: { effective_status: "incomplete" },
    source_treatment_draft: {
      draft_id: SOURCE_DRAFT_ID,
      status: "active",
      updated_at: "2026-09-07T01:00:00Z",
      source_manifest_sha256: SHA_B,
      source_count: 3,
      source_treatment_mode: "separate_makeup_and_overage_v1",
      settlement_exchange_rate: null,
      settlement_exchange_rate_source: null,
      settlement_exchange_rate_effective_date: null,
    },
    adjustment_draft: {
      draft_id: ADJUSTMENT_DRAFT_ID,
      status: "active",
      updated_at: "2026-09-07T01:00:00Z",
      adjustment_mode: "carry_final_balance",
      adjustment_amount_cny: null,
    },
    ...overrides,
  };
}

export function previewRow(carryover = AUTHORITATIVE_CARRY) {
  return {
    preview_manifest_sha256: SHA_A,
    preview: {
      lesson_variance_source_count: 3,
      unused_planned_credit_jpy: "0",
      overage_charge_jpy: "0",
      net_lesson_variance_jpy: "0",
      net_lesson_variance_cny: "0",
      projected_final_carryover_cny: carryover,
    },
    preview_expected_facts: {
      lesson_variance_manifest_sha256: SHA_B,
      system_difference_cny: "0",
    },
  };
}

// 预置两个 RPC 的返回值，再走真实 API 层取回已登记的权威快照。
export async function authoritativeFacts({ status, preview } = {}) {
  const statusData = status ?? statusRow();
  stub.resetCapture();
  stub.setRpcResponse(STATUS_RPC, statusData);
  stub.setRpcResponse(PREVIEW_RPC, preview ?? previewRow());
  return settlementApi.fetchAuthoritativeLockFacts(
    statusData.student_id, statusData.year_month,
  );
}

// 递归查找结构各层级是否出现某个字符串（键名与值都查）
export function containsDeep(value, needle) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.includes(needle);
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).includes(needle);
  }
  if (Array.isArray(value)) return value.some((item) => containsDeep(item, needle));
  if (typeof value === "object") {
    return Object.entries(value).some(
      ([key, item]) => key.includes(needle) || containsDeep(item, needle),
    );
  }
  return false;
}
