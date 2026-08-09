import assert from "node:assert/strict";
import test from "node:test";

import {
  ONLINE_ADJUSTMENT_MODES,
  ONLINE_SOURCE_TREATMENT_MODES,
  buildOnlineDraftSaveInput,
  canUseOnlineDraftSave,
  canonicalDecimal,
  classifySaveRecovery,
  createSingleFlight,
  onlineStatusDisplay,
  statusConfirmsDraftSave,
} from "../js/pages/settlement-online-state.js";

const UUID = "123e4567-e89b-42d3-a456-426614174000";
const UUID_2 = "223e4567-e89b-42d3-a456-426614174000";
const HASH = "a".repeat(64);
const HASH_2 = "b".repeat(64);

function status(overrides = {}) {
  return {
    effective_state: { effective_status: "incomplete" },
    physical_settlement: { settlement_id: null, settlement_status: null },
    source_treatment_draft: { draft_id: null, updated_at: null },
    adjustment_draft: { draft_id: null, updated_at: null },
    immutable_blocker: null,
    can_save: true,
    save_blocker_code: null,
    save_blocker_message: null,
    can_lock: false,
    requires_repreview: true,
    ...overrides,
  };
}

function preview() {
  return {
    preview_manifest_sha256: HASH,
    preview_expected_facts: {
      lesson_variance_manifest_sha256: HASH_2,
      system_difference_cny: "123.4500",
    },
    preview: {
      lesson_variance_source_count: 2,
      unused_planned_credit_jpy: "20000.00",
      overage_charge_jpy: "0",
      net_lesson_variance_jpy: "-20000.00",
      net_lesson_variance_cny: "-1000.1250",
      projected_adjustment_amount_cny: "-123.4500",
      projected_final_carryover_cny: "0.00",
    },
  };
}

function input(overrides = {}) {
  return {
    sourceTreatmentMode: ONLINE_SOURCE_TREATMENT_MODES.SEPARATE,
    settlementExchangeRate: null,
    settlementExchangeRateSource: null,
    settlementExchangeRateEffectiveDate: null,
    adjustmentMode: ONLINE_ADJUSTMENT_MODES.CLEAR_BALANCE,
    explicitUserAmountCny: null,
    reason: "负责人确认清零",
    note: "",
    ...overrides,
  };
}

function savedStatus(overrides = {}) {
  return status({
    requires_repreview: false,
    preview_manifest_sha256: HASH,
    lesson_manifest_sha256: HASH_2,
    source_treatment_draft: {
      draft_id: UUID,
      status: "active",
      updated_at: "2026-08-10T01:02:03Z",
      source_treatment_mode: ONLINE_SOURCE_TREATMENT_MODES.SEPARATE,
      settlement_exchange_rate: null,
      settlement_exchange_rate_source: null,
      settlement_exchange_rate_effective_date: null,
      source_manifest_sha256: HASH_2,
      source_count: 2,
    },
    adjustment_draft: {
      draft_id: UUID_2,
      status: "active",
      updated_at: "2026-08-10T01:02:04Z",
      adjustment_mode: ONLINE_ADJUSTMENT_MODES.CLEAR_BALANCE,
      adjustment_amount_cny: "-123.45",
      reason: "负责人确认清零",
      note: "",
    },
    ...overrides,
  });
}

test("only active admin plus DB can_save sees save", () => {
  assert.equal(canUseOnlineDraftSave("admin", status()), true);
  for (const role of ["operator", "read_only", "inactive", "", null]) {
    assert.equal(canUseOnlineDraftSave(role, status()), false);
  }
  assert.equal(canUseOnlineDraftSave("admin", status({ can_save: false })), false);
  assert.equal(canUseOnlineDraftSave("admin", status({
    save_blocker_code: "SETTLEMENT_SOURCE_FACTS_EMPTY",
  })), false);
  assert.equal(canUseOnlineDraftSave("admin", status({
    immutable_blocker: { code: "SETTLEMENT_WAGE_BLOCKED" },
  })), false);
});

test("effective and blocker states remain distinct and readable", () => {
  assert.equal(onlineStatusDisplay(status()).key, "incomplete");
  assert.equal(onlineStatusDisplay(savedStatus()).key, "draft_saved");
  assert.equal(onlineStatusDisplay(null, new Error("offline")).key, "unknown");
  for (const effective of [
    "ordinary_locked",
    "historically_consumed_immutable",
    "historical_zero_carry_complete",
  ]) {
    assert.equal(onlineStatusDisplay(status({
      effective_state: { effective_status: effective },
      can_save: false,
    })).key, effective);
  }
  for (const code of [
    "SETTLEMENT_SUCCESSOR_REVISION_BLOCKED",
    "SETTLEMENT_WAGE_BLOCKED",
    "SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED",
    "SETTLEMENT_SOURCE_FACTS_EMPTY",
  ]) {
    assert.equal(onlineStatusDisplay(status({
      can_save: false,
      save_blocker_code: code,
      save_blocker_message: "DB安全提示",
    })).key, code);
  }
});

test("save request uses only explicit choices, status versions and authoritative preview strings", () => {
  const request = buildOnlineDraftSaveInput({
    row: { student_id: UUID, year_month: "2026-07", business_entity_id: "must-not-pass" },
    status: status(),
    previewResult: preview(),
    input: input(),
  });
  assert.equal(request.expectedNetLessonVarianceCny, "-1000.1250");
  assert.equal(request.expectedSystemDifferenceCny, "123.4500");
  assert.equal(request.expectedFinalCarryoverCny, "0.00");
  assert.equal(request.manualAdjustmentAmountCny, null);
  for (const forbidden of [
    "actor", "role", "membership", "businessEntityId", "authority",
    "serviceRole", "canonicalConfirmation", "confirmLock",
  ]) assert.equal(Object.hasOwn(request, forbidden), false);
});

test("carry and clear do not require manual amount; manual requires decimal amount and reason", () => {
  for (const adjustmentMode of [
    ONLINE_ADJUSTMENT_MODES.CARRY_FINAL_BALANCE,
    ONLINE_ADJUSTMENT_MODES.CLEAR_BALANCE,
  ]) {
    const request = buildOnlineDraftSaveInput({
      row: { student_id: UUID, year_month: "2026-07" },
      status: status(),
      previewResult: preview(),
      input: input({ adjustmentMode }),
    });
    assert.equal(request.manualAdjustmentAmountCny, null);
  }
  assert.throws(() => buildOnlineDraftSaveInput({
    row: { student_id: UUID, year_month: "2026-07" },
    status: status(), previewResult: preview(),
    input: input({ adjustmentMode: ONLINE_ADJUSTMENT_MODES.MANUAL_ADJUSTMENT, reason: "" }),
  }));
  const manual = buildOnlineDraftSaveInput({
    row: { student_id: UUID, year_month: "2026-07" },
    status: status(), previewResult: preview(),
    input: input({
      adjustmentMode: ONLINE_ADJUSTMENT_MODES.MANUAL_ADJUSTMENT,
      explicitUserAmountCny: "-10.5000",
      reason: "人工调整确认",
    }),
  });
  assert.equal(manual.manualAdjustmentAmountCny, "-10.5000");
});

test("financial net mode preserves the explicit rate string without calculating money", () => {
  const request = buildOnlineDraftSaveInput({
    row: { student_id: UUID, year_month: "2026-07" },
    status: status(), previewResult: preview(),
    input: input({
      sourceTreatmentMode: ONLINE_SOURCE_TREATMENT_MODES.NET_FINANCIAL,
      settlementExchangeRate: "20.125000",
      settlementExchangeRateSource: "业务负责人输入",
      settlementExchangeRateEffectiveDate: "2026-07-31",
    }),
  });
  assert.equal(request.settlementExchangeRate, "20.125000");
  assert.equal(canonicalDecimal("-001.2300".replace("001", "1")), "-1.23");
});

test("status-first recovery distinguishes confirmed, unchanged and other-session conflict", () => {
  assert.equal(statusConfirmsDraftSave(savedStatus(), preview(), input()), true);
  const before = status();
  assert.equal(classifySaveRecovery(before, savedStatus(), preview(), input()), "confirmed");
  assert.equal(classifySaveRecovery(before, status(), preview(), input()), "unchanged");
  assert.equal(classifySaveRecovery(before, status({
    source_treatment_draft: { draft_id: UUID, updated_at: "2026-08-10T02:00:00Z" },
  }), preview(), input()), "conflict");
});

test("single flight rejects a double click without a second task", async () => {
  const gate = createSingleFlight();
  let calls = 0;
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const first = gate.run(async () => { calls += 1; await pending; return "done"; });
  const second = await gate.run(async () => { calls += 1; });
  assert.deepEqual(second, { skipped: true });
  release();
  assert.equal((await first).value, "done");
  assert.equal(calls, 1);
});
