import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sharedPath = "supabase/functions/_shared/expense-cash-attempt-v2.js";
const requestPath = "supabase/functions/request-cash-expense-confirmation/index.ts";
const syncPath = "supabase/functions/sync-cash-request-result/index.ts";
const sharedSource = await readFile(sharedPath, "utf8");
const requestSource = await readFile(requestPath, "utf8");
const syncSource = await readFile(syncPath, "utf8");
const shared = await import(`data:text/javascript;base64,${Buffer.from(sharedSource).toString("base64")}`);

const prepared = {
  cash_user_id: "c3200000-0000-4000-8000-000000000201",
  cash_account_id: "c3200000-0000-4000-8000-000000000301",
  request_event_id: "c3200000-0000-4000-8000-000000000401",
  expense_id: "c3200000-0000-4000-8000-000000000101",
  actual_payment_date: "2099-01-25",
  payment_amount: "1234",
  payment_currency: "JPY",
  idempotency_key: "aozora_school:school_expense_records:c3200000-0000-4000-8000-000000000101:expense_paid:attempt:1",
  request_payload_fingerprint: "a".repeat(64),
  cash_description: "其他 / codex-test / 2099-01 / 1234 JPY",
  cash_payload_snapshot: {
    actual_payment_amount: 1234,
    actual_payment_currency: "JPY",
    actual_payment_date: "2099-01-25",
    school_attempt_payload_fingerprint: "a".repeat(64),
    note: "codex-test",
  },
};

const cashCreate = shared.buildCashCreateRpcPayload(prepared);
assert.equal(cashCreate.p_amount, prepared.payment_amount);
assert.equal(cashCreate.p_currency, prepared.payment_currency);
assert.equal(cashCreate.p_account_id, prepared.cash_account_id);
assert.equal(cashCreate.p_transacted_at, prepared.actual_payment_date);
assert.equal(cashCreate.p_payload_snapshot, prepared.cash_payload_snapshot);

const cashRequest = {
  id: "c3200000-0000-4000-8000-000000000501",
  external_source: "aozora_school",
  external_event_id: prepared.request_event_id,
  external_reference_type: "school_expense_records",
  external_reference_id: prepared.expense_id,
  request_type: "expense_paid",
  transaction_type: "expense",
  amount: prepared.payment_amount,
  currency: prepared.payment_currency,
  account_id: prepared.cash_account_id,
  transacted_at: prepared.actual_payment_date,
  status: "pending",
  idempotency_key: prepared.idempotency_key,
  payload_snapshot: prepared.cash_payload_snapshot,
};
const evidence = shared.buildSchoolExpenseCashEvidence(cashRequest);
assert.deepEqual(evidence, {
  p_expense_record_id: prepared.expense_id,
  p_cash_request_id: cashRequest.id,
  p_cash_request_status: "pending",
  p_external_source: "aozora_school",
  p_request_event_id: prepared.request_event_id,
  p_idempotency_key: prepared.idempotency_key,
  p_external_reference_type: "school_expense_records",
  p_external_reference_id: prepared.expense_id,
  p_request_type: "expense_paid",
  p_transaction_type: "expense",
  p_payment_amount: prepared.payment_amount,
  p_payment_currency: "JPY",
  p_cash_account_id: prepared.cash_account_id,
  p_charge_date: prepared.actual_payment_date,
  p_request_payload_fingerprint: prepared.request_payload_fingerprint,
});

assert.throws(
  () => shared.buildSchoolExpenseCashEvidence({ ...cashRequest, payload_snapshot: {} }),
  /request_payload_fingerprint/,
);
assert.throws(
  () => shared.buildCashCreateRpcPayload({
    ...prepared,
    cash_payload_snapshot: {
      ...prepared.cash_payload_snapshot,
      school_attempt_payload_fingerprint: "b".repeat(64),
    },
  }),
  /fingerprint mismatch/,
);

// Mock the main recovery: the same DB identity reaches the same Cash idempotency
// key, a failed School submitted writeback is retried, and no second identity exists.
const attempts = new Map();
const cashRequests = new Map();
function mockPrepare(row) {
  const existing = attempts.get(row.idempotency_key);
  if (existing) return existing;
  attempts.set(row.idempotency_key, row);
  return row;
}
function mockCashCreate(payload) {
  const existing = cashRequests.get(payload.p_idempotency_key);
  if (existing) return { ...existing, inserted: false };
  const created = { request_id: cashRequest.id, status: "pending", inserted: true };
  cashRequests.set(payload.p_idempotency_key, created);
  return created;
}
const firstPrepared = mockPrepare(prepared);
const firstCash = mockCashCreate(shared.buildCashCreateRpcPayload(firstPrepared));
assert.equal(firstCash.inserted, true);
const retriedPrepared = mockPrepare({ ...prepared });
const retriedCash = mockCashCreate(shared.buildCashCreateRpcPayload(retriedPrepared));
assert.equal(retriedCash.inserted, false);
assert.equal(attempts.size, 1);
assert.equal(cashRequests.size, 1);

assert.match(requestSource, /school_request_cash_expense_payment_confirmation_v2/);
assert.match(requestSource, /school_mark_cash_expense_request_submitted_v2/);
assert.match(requestSource, /buildCashCreateRpcPayload\(schoolRequest\)/);
assert.match(requestSource, /home_external_transaction_requests/);
assert.doesNotMatch(requestSource, /requestedPaymentDate\s*\?\?/);
assert.match(syncSource, /school_mark_cash_expense_confirmed_v2/);
assert.match(syncSource, /school_mark_cash_expense_rejected_v2/);
for (const field of ["account_id", "transacted_at", "idempotency_key", "payload_snapshot"]) {
  assert.match(syncSource, new RegExp(`"${field}"`));
}
assert.match(syncSource, /p_recovery_source:\s*"sync-cash-request-result-v2"/);

console.log("PHASE3C2R_EDGE_MOCK_TEST_PASS");
