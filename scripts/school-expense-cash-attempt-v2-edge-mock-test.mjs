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

assert.deepEqual(shared.inspectSchoolExpenseCashFingerprint(cashRequest), {
  state: "present",
  fingerprint: prepared.request_payload_fingerprint,
});
assert.deepEqual(
  shared.inspectSchoolExpenseCashFingerprint({ ...cashRequest, payload_snapshot: {} }),
  { state: "missing" },
);
assert.throws(
  () => shared.buildSchoolExpenseCashEvidence({ ...cashRequest, payload_snapshot: {} }),
  /SCHOOL_EXPENSE_CASH_NATIVE_FINGERPRINT_MISSING/,
);
for (const invalidFingerprint of ["", "a".repeat(63), "g".repeat(64), null]) {
  assert.throws(
    () => shared.buildSchoolExpenseCashEvidence({
      ...cashRequest,
      payload_snapshot: {
        school_attempt_payload_fingerprint: invalidFingerprint,
      },
    }),
    /request_payload_fingerprint/,
  );
}
const historicalEvidence = shared.buildSchoolExpenseCashEvidence(
  { ...cashRequest, payload_snapshot: {} },
  { resolvedHistoricalFingerprint: "d".repeat(64) },
);
assert.equal(historicalEvidence.p_request_payload_fingerprint, "d".repeat(64));
assert.throws(
  () => shared.buildSchoolExpenseCashEvidence(cashRequest, {
    resolvedHistoricalFingerprint: "d".repeat(64),
  }),
  /cannot be overridden/,
);

const cnyNativeRequest = {
  ...cashRequest,
  currency: "CNY",
  amount: "456.78",
};
assert.equal(
  shared.buildSchoolExpenseCashEvidence(cnyNativeRequest).p_payment_currency,
  "CNY",
);
const ordinaryImmediateRequest = {
  ...cashRequest,
  payload_snapshot: {
    school_attempt_payload_fingerprint: "e".repeat(64),
  },
};
assert.equal(
  shared.buildSchoolExpenseCashEvidence(ordinaryImmediateRequest)
    .p_request_payload_fingerprint,
  "e".repeat(64),
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

const fixedPrepared = {
  cash_user_id: prepared.cash_user_id,
  request_event_id: "c3300000-0000-4000-8000-000000000401",
  expense_id: "c3300000-0000-4000-8000-000000000101",
  attempt_no: 1,
  idempotency_key:
    "aozora_school:school_expense_records:c3300000-0000-4000-8000-000000000101:expense_paid:attempt:1",
  payment_route: "fixed_credit_card",
  card_instrument_id: "c3300000-0000-4000-8000-000000000301",
  charge_date: "2099-01-11",
  suggested_fixed_month: "2099-02-01",
  target_fixed_month: "2099-02-01",
  funding_date: "2099-02-25",
  settlement_amount: "5678",
  settlement_currency: "JPY",
  request_payload_fingerprint: "c".repeat(64),
  cash_description: "教室费用 / codex-test / 2099-01 / 5678 JPY / 信用卡固定支出",
  cash_payload_snapshot: {
    external_source: "aozora_school",
    external_reference_type: "school_expense_records",
    external_reference_id: "c3300000-0000-4000-8000-000000000101",
    request_type: "expense_paid",
    transaction_type: "expense",
    payment_route: "fixed_credit_card",
    card_instrument_id: "c3300000-0000-4000-8000-000000000301",
    charge_date: "2099-01-11",
    suggested_fixed_month: "2099-02-01",
    target_fixed_month: "2099-02-01",
    funding_date: "2099-02-25",
    school_attempt_payload_fingerprint: "c".repeat(64),
    note: "codex-test phase3c3b",
  },
};
const fixedCreate = shared.buildCashFixedCreateRpcPayload(fixedPrepared);
assert.equal(fixedCreate.p_card_instrument_id, fixedPrepared.card_instrument_id);
assert.equal(fixedCreate.p_funding_date, fixedPrepared.funding_date);
assert.equal(fixedCreate.p_amount, fixedPrepared.settlement_amount);
assert.equal("p_account_id" in fixedCreate, false);
assert.equal("p_funding_account_id" in fixedCreate, false);

const fixedCashRequest = {
  id: "c3300000-0000-4000-8000-000000000501",
  external_source: "aozora_school",
  external_event_id: fixedPrepared.request_event_id,
  external_reference_type: "school_expense_records",
  external_reference_id: fixedPrepared.expense_id,
  request_type: "expense_paid",
  transaction_type: "expense",
  amount: fixedPrepared.settlement_amount,
  currency: fixedPrepared.settlement_currency,
  account_id: null,
  funding_account_id: null,
  transacted_at: fixedPrepared.charge_date,
  status: "pending",
  idempotency_key: fixedPrepared.idempotency_key,
  payment_route: "fixed_credit_card",
  card_instrument_id: fixedPrepared.card_instrument_id,
  charge_date: fixedPrepared.charge_date,
  suggested_fixed_month: fixedPrepared.suggested_fixed_month,
  target_fixed_month: fixedPrepared.target_fixed_month,
  created_transaction_id: null,
  fixed_projection_id: null,
  payload_snapshot: fixedPrepared.cash_payload_snapshot,
};
const fixedEvidence = shared.buildSchoolExpenseFixedCashEvidence(fixedCashRequest);
assert.equal(fixedEvidence.p_payment_route, "fixed_credit_card");
assert.equal(fixedEvidence.p_account_id, null);
assert.equal(fixedEvidence.p_funding_account_id, null);
assert.equal(fixedEvidence.p_funding_date, fixedPrepared.funding_date);
assert.equal(fixedEvidence.p_cash_transaction_id, null);
assert.equal(fixedEvidence.p_fixed_projection_id, null);
assert.throws(
  () => shared.buildSchoolExpenseFixedCashEvidence({
    ...fixedCashRequest,
    account_id: prepared.cash_account_id,
  }),
  /must not contain an account/,
);
assert.throws(
  () => shared.buildSchoolExpenseFixedCashEvidence({
    ...fixedCashRequest,
    charge_date: "2099-01-12",
  }),
  /charge-date snapshot mismatch/,
);

const approvedFixedRequest = {
  ...fixedCashRequest,
  status: "approved",
  fixed_projection_id: "c3300000-0000-4000-8000-000000000601",
};
const fixedApprovalEvidence = {
  request_id: approvedFixedRequest.id,
  request_status: "approved",
  payment_route: "fixed_credit_card",
  external_event_id: approvedFixedRequest.external_event_id,
  external_reference_id: approvedFixedRequest.external_reference_id,
  idempotency_key: approvedFixedRequest.idempotency_key,
  card_instrument_id: approvedFixedRequest.card_instrument_id,
  charge_date: approvedFixedRequest.charge_date,
  suggested_fixed_month: approvedFixedRequest.suggested_fixed_month,
  target_fixed_month: approvedFixedRequest.target_fixed_month,
  original_amount: approvedFixedRequest.amount,
  original_currency: "JPY",
  created_transaction_id: null,
  fixed_projection_id: approvedFixedRequest.fixed_projection_id,
  projection_status: "projected",
  projection_version: 1,
  funding_status: "unfunded",
  funding_payment_channel_id: "c3300000-0000-4000-8000-000000000701",
  funding_transaction_id: null,
  fixed_item_id: "c3300000-0000-4000-8000-000000000801",
  fixed_item_template_id: null,
  fixed_item_scope: "school",
  fixed_item_currency: "JPY",
  fixed_item_direction: "expense",
  fixed_item_amount: approvedFixedRequest.amount,
  fixed_item_month_key: "2099-02",
  fixed_item_due_date: "2099-02-25",
  fixed_item_payment_group: "邮局卡",
  fixed_item_status: "unpaid",
  fixed_item_account_id: null,
  fixed_item_linked_jpy_transaction_id: null,
  fixed_item_linked_cny_transaction_id: null,
  approved_by: "c3300000-0000-4000-8000-000000000901",
  approved_at: "2099-01-12T00:00:00+00:00",
};
const approvedFixedEvidence = shared.buildSchoolExpenseFixedApprovedEvidence(
  approvedFixedRequest,
  fixedApprovalEvidence,
);
assert.equal(approvedFixedEvidence.p_fixed_projection_id, approvedFixedRequest.fixed_projection_id);
assert.equal(approvedFixedEvidence.p_fixed_item_id, fixedApprovalEvidence.fixed_item_id);
assert.equal(approvedFixedEvidence.p_fixed_item_scope, "school");
assert.equal(approvedFixedEvidence.p_cash_transaction_id, null);
assert.equal(approvedFixedEvidence.p_projection_funding_transaction_id, null);
assert.throws(
  () => shared.buildSchoolExpenseFixedApprovedEvidence(
    approvedFixedRequest,
    { ...fixedApprovalEvidence, fixed_projection_id: "c3300000-0000-4000-8000-000000000999" },
  ),
  /fixed_projection_id/,
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

// Fixed-branch orchestration fault matrix. Database mocks retain identity so a
// failure after prepare or Cash create is recoverable without a second row.
function runFixedSaga(state, faults = {}) {
  state.calls.push("home_schedule");
  if (faults.cardRouteDisabled) return { ok: false, stage: "schedule" };
  state.calls.push("school_prepare");
  if (faults.schoolPrepare) return { ok: false, stage: "prepare" };
  state.prepared ??= fixedPrepared;
  state.calls.push("home_writer");
  if (faults.homeWriter) return { ok: false, stage: "home", prepared: true };
  state.request ??= fixedCashRequest;
  state.calls.push("school_submitted");
  if (faults.schoolSubmitted) return { ok: false, stage: "submitted" };
  state.submitted = true;
  return { ok: true, requestId: state.request.id };
}

let fixedState = { calls: [] };
assert.equal(runFixedSaga(fixedState, { cardRouteDisabled: true }).stage, "schedule");
assert.deepEqual(fixedState.calls, ["home_schedule"]);
fixedState = { calls: [] };
assert.equal(runFixedSaga(fixedState, { schoolPrepare: true }).stage, "prepare");
assert.deepEqual(fixedState.calls, ["home_schedule", "school_prepare"]);
fixedState = { calls: [] };
assert.equal(runFixedSaga(fixedState, { homeWriter: true }).prepared, true);
assert.equal(fixedState.prepared.request_event_id, fixedPrepared.request_event_id);
fixedState = { calls: [] };
assert.equal(runFixedSaga(fixedState, { schoolSubmitted: true }).stage, "submitted");
const firstFixedRequestId = fixedState.request.id;
fixedState.calls = [];
assert.equal(runFixedSaga(fixedState).ok, true);
assert.equal(fixedState.request.id, firstFixedRequestId);
assert.equal(fixedState.prepared.request_event_id, fixedPrepared.request_event_id);

assert.match(requestSource, /school_request_cash_expense_payment_confirmation_v2/);
assert.match(requestSource, /school_mark_cash_expense_request_submitted_v2/);
assert.match(requestSource, /buildCashCreateRpcPayload\(schoolRequest\)/);
assert.match(requestSource, /home_external_transaction_requests/);
assert.doesNotMatch(requestSource, /requestedPaymentDate\s*\?\?/);
assert.match(syncSource, /school_mark_cash_expense_confirmed_v2/);
assert.match(syncSource, /school_mark_cash_expense_rejected_v2/);
assert.match(requestSource, /home_get_school_fixed_card_schedule/);
assert.match(requestSource, /school_request_cash_fixed_expense_payment_confirmation_v2/);
assert.match(requestSource, /home_create_external_fixed_transaction_request/);
assert.match(requestSource, /school_mark_cash_fixed_expense_request_submitted_v2/);
assert.ok(
  requestSource.indexOf("home_get_school_fixed_card_schedule") <
    requestSource.indexOf("school_request_cash_fixed_expense_payment_confirmation_v2"),
  "home schedule must be read before School fixed prepare",
);
assert.match(syncSource, /school_mark_cash_fixed_expense_rejected_v2/);
assert.match(syncSource, /home_get_external_fixed_approval_evidence/);
assert.match(syncSource, /school_mark_cash_fixed_expense_approved_v2/);
assert.match(syncSource, /HOME_FIXED_APPROVAL_EVIDENCE_INCOMPLETE/);
const fixedApprovedBranch =
  syncSource.match(/if \(action === "approved" && isFixedExpense\)[\s\S]*?\n    \}\n\n    if \(action === "approved"\)/)?.[0] ?? "";
assert.doesNotMatch(fixedApprovedBranch, /school_mark_cash_expense_confirmed_v2/);
assert.doesNotMatch(fixedApprovedBranch, /created_transaction_id\s*\?\?/);
for (const field of ["account_id", "transacted_at", "idempotency_key", "payload_snapshot"]) {
  assert.match(syncSource, new RegExp(`"${field}"`));
}
assert.match(syncSource, /p_recovery_source:\s*"sync-cash-request-result-v2"/);
assert.match(syncSource, /school_resolve_historical_expense_cash_attempt_fingerprint_v1/);
assert.match(syncSource, /inspectSchoolExpenseCashFingerprint/);
assert.match(syncSource, /HOME_TRANSACTION_MISSING/);
assert.match(syncSource, /HOME_TRANSACTION_AMBIGUOUS/);
assert.match(syncSource, /\.or\(filters\)/);
assert.doesNotMatch(syncSource, /\.limit\(1\)/);
assert.doesNotMatch(syncSource, /home_approve_external_transaction_request/);
assert.doesNotMatch(syncSource, /home_reject_external_transaction_request/);
assert.doesNotMatch(syncSource, /home_create_external_transaction_request/);
assert.doesNotMatch(syncSource, /home_create_(?:jpy|cny)_transaction/);
assert.doesNotMatch(syncSource, /crypto\.subtle|createHash|sha256|sha-256/i);

const resolverCallCount = (syncSource.match(
  /school_resolve_historical_expense_cash_attempt_fingerprint_v1/g,
) || []).length;
assert.equal(resolverCallCount, 1, "historical resolver is called only by the immediate helper");
const immediateHelper = syncSource.match(
  /async function buildImmediateExpenseCallbackEvidence[\s\S]*?\n}\n\nDeno\.serve/,
)?.[0] ?? "";
assert.match(immediateHelper, /inspectSchoolExpenseCashFingerprint/);
assert.match(immediateHelper, /school_resolve_historical_expense_cash_attempt_fingerprint_v1/);
assert.doesNotMatch(immediateHelper, /fixed_credit_card|school_mark_cash_income/);

function mockHistoricalSync(state, request, transactionRows) {
  const fingerprintState = shared.inspectSchoolExpenseCashFingerprint(request);
  if (fingerprintState.state === "present") {
    state.nativeCallbacks += 1;
    return { mode: "native", fingerprint: fingerprintState.fingerprint };
  }
  if (
    request.external_reference_type !== "school_expense_records" ||
    request.request_type !== "expense_paid" ||
    request.transaction_type !== "expense" ||
    request.payment_route !== "immediate_account"
  ) {
    throw new Error("HISTORICAL_FALLBACK_FORBIDDEN");
  }
  if (request.status === "approved" && transactionRows.length === 0) {
    throw new Error("HOME_TRANSACTION_MISSING");
  }
  if (transactionRows.length > 1) {
    throw new Error("HOME_TRANSACTION_AMBIGUOUS");
  }
  if (request.status === "rejected" && transactionRows.length !== 0) {
    throw new Error("HOME_TRANSACTION_EVIDENCE_CONFLICT");
  }

  const attempt = state.attempt;
  const eligible =
    (attempt.status === "submitted" && attempt.version === 1) ||
    (["approved_immediate", "rejected"].includes(attempt.status) &&
      [1, 2].includes(attempt.version));
  if (!eligible || attempt.callbackRecoveredFromPrepared) {
    throw new Error("HISTORICAL_FALLBACK_NOT_ELIGIBLE");
  }
  if (
    (request.status === "approved" && attempt.status === "rejected") ||
    (request.status === "rejected" && attempt.status === "approved_immediate")
  ) {
    throw new Error("TERMINAL_CONFLICT");
  }

  state.resolverCalls += 1;
  const resolvedFingerprint = attempt.fingerprint;
  const callbackEvidence = shared.buildSchoolExpenseCashEvidence(request, {
    resolvedHistoricalFingerprint: resolvedFingerprint,
  });
  state.callbackCalls += 1;
  if (attempt.status === "submitted") {
    attempt.status = request.status === "approved" ? "approved_immediate" : "rejected";
    attempt.version += 1;
    return { mode: "historical", idempotent: false, callbackEvidence };
  }
  return { mode: "historical", idempotent: true, callbackEvidence };
}

const historicalApprovedRequest = {
  ...cashRequest,
  status: "approved",
  payment_route: "immediate_account",
  currency: "CNY",
  payload_snapshot: {
    attempt_no: 1,
    original_amount: 31500,
    original_currency: "JPY",
  },
};
const approvedSyncState = {
  attempt: {
    status: "submitted",
    version: 1,
    fingerprint: "f".repeat(64),
    callbackRecoveredFromPrepared: false,
  },
  resolverCalls: 0,
  callbackCalls: 0,
  nativeCallbacks: 0,
  homeWriterCalls: 0,
  homeTransactionCount: 1,
};
const uniqueTransaction = [{ id: "c3200000-0000-4000-8000-000000000601" }];
const firstHistoricalApproved = mockHistoricalSync(
  approvedSyncState,
  historicalApprovedRequest,
  uniqueTransaction,
);
assert.equal(firstHistoricalApproved.idempotent, false);
assert.equal(approvedSyncState.attempt.status, "approved_immediate");
assert.equal(approvedSyncState.attempt.version, 2);
const replayHistoricalApproved = mockHistoricalSync(
  approvedSyncState,
  historicalApprovedRequest,
  uniqueTransaction,
);
assert.equal(replayHistoricalApproved.idempotent, true);
assert.equal(approvedSyncState.attempt.version, 2);
assert.equal(approvedSyncState.homeTransactionCount, 1);
assert.equal(approvedSyncState.homeWriterCalls, 0);

const historicalRejectedRequest = {
  ...historicalApprovedRequest,
  status: "rejected",
  created_transaction_id: null,
};
const rejectedSyncState = {
  attempt: {
    status: "submitted",
    version: 1,
    fingerprint: "1".repeat(64),
    callbackRecoveredFromPrepared: false,
  },
  resolverCalls: 0,
  callbackCalls: 0,
  nativeCallbacks: 0,
  homeWriterCalls: 0,
  homeTransactionCount: 0,
};
assert.equal(
  mockHistoricalSync(rejectedSyncState, historicalRejectedRequest, []).idempotent,
  false,
);
assert.equal(rejectedSyncState.attempt.status, "rejected");
assert.equal(rejectedSyncState.attempt.version, 2);
assert.equal(
  mockHistoricalSync(rejectedSyncState, historicalRejectedRequest, []).idempotent,
  true,
);
assert.equal(rejectedSyncState.attempt.version, 2);

assert.throws(
  () => mockHistoricalSync(
    { ...approvedSyncState, attempt: { ...approvedSyncState.attempt } },
    historicalApprovedRequest,
    [],
  ),
  /HOME_TRANSACTION_MISSING/,
);
assert.throws(
  () => mockHistoricalSync(
    { ...approvedSyncState, attempt: { ...approvedSyncState.attempt } },
    historicalApprovedRequest,
    [uniqueTransaction[0], { id: "duplicate" }],
  ),
  /HOME_TRANSACTION_AMBIGUOUS/,
);
assert.throws(
  () => mockHistoricalSync(
    { ...rejectedSyncState, attempt: { ...rejectedSyncState.attempt } },
    historicalRejectedRequest,
    uniqueTransaction,
  ),
  /HOME_TRANSACTION_EVIDENCE_CONFLICT/,
);

for (const request of [
  { ...historicalApprovedRequest, payment_route: "fixed_credit_card" },
  {
    ...historicalApprovedRequest,
    external_reference_type: "school_income_records",
    request_type: "income_received",
    transaction_type: "income",
  },
]) {
  assert.throws(
    () => mockHistoricalSync(
      { ...approvedSyncState, attempt: { ...approvedSyncState.attempt } },
      request,
      uniqueTransaction,
    ),
    /HISTORICAL_FALLBACK_FORBIDDEN/,
  );
}

const nativeState = {
  attempt: { status: "submitted", version: 2 },
  resolverCalls: 0,
  callbackCalls: 0,
  nativeCallbacks: 0,
};
assert.equal(mockHistoricalSync(nativeState, cnyNativeRequest, []).mode, "native");
assert.equal(nativeState.resolverCalls, 0);
assert.equal(nativeState.nativeCallbacks, 1);

console.log("P0_HISTORICAL_RESOLVER_EDGE_MOCK_TEST_PASS");
