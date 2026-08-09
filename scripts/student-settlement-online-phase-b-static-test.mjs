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
  assert.doesNotMatch(settlementPage, /lockStudentSettlementOnline|lock-student-settlement/);
  assert.doesNotMatch(pageSource, /lock-student-settlement/);
  assert.doesNotMatch(pageSource, /SCHOOL_SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY/);
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
