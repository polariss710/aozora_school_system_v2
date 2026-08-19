const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const FINGERPRINT_PATTERN = /^[0-9a-f]{64}$/;

function requiredText(value, field) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`School Cash V2 evidence is missing ${field}`);
  }
  return value.trim();
}

function requiredUuid(value, field) {
  const text = requiredText(value, field);
  if (!UUID_PATTERN.test(text)) {
    throw new Error(`School Cash V2 evidence has invalid ${field}`);
  }
  return text;
}

function requiredDate(value, field) {
  const text = requiredText(value, field);
  if (!DATE_PATTERN.test(text)) {
    throw new Error(`School Cash V2 evidence has invalid ${field}`);
  }
  return text;
}

function requiredAmount(value, field) {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error(`School Cash V2 evidence has invalid ${field}`);
  }
  return value;
}

function requiredFingerprint(value) {
  const text = requiredText(value, "request_payload_fingerprint");
  if (!FINGERPRINT_PATTERN.test(text)) {
    throw new Error("School Cash V2 evidence has invalid request_payload_fingerprint");
  }
  return text;
}

export function buildCashCreateRpcPayload(prepared) {
  if (!prepared || typeof prepared !== "object") {
    throw new Error("School prepare V2 returned no canonical payload");
  }
  if (!prepared.cash_payload_snapshot || typeof prepared.cash_payload_snapshot !== "object") {
    throw new Error("School prepare V2 returned no cash_payload_snapshot");
  }
  const fingerprint = requiredFingerprint(prepared.request_payload_fingerprint);
  if (prepared.cash_payload_snapshot.school_attempt_payload_fingerprint !== fingerprint) {
    throw new Error("School prepare V2 payload fingerprint mismatch");
  }

  return {
    p_user_id: requiredUuid(prepared.cash_user_id, "cash_user_id"),
    p_account_id: requiredUuid(prepared.cash_account_id, "cash_account_id"),
    p_external_source: "aozora_school",
    p_external_event_id: requiredUuid(prepared.request_event_id, "request_event_id"),
    p_external_reference_type: "school_expense_records",
    p_external_reference_id: requiredUuid(prepared.expense_id, "expense_id"),
    p_request_type: "expense_paid",
    p_transaction_type: "expense",
    p_transacted_at: requiredDate(prepared.actual_payment_date, "actual_payment_date"),
    p_amount: requiredAmount(prepared.payment_amount, "payment_amount"),
    p_idempotency_key: requiredText(prepared.idempotency_key, "idempotency_key"),
    p_description: requiredText(prepared.cash_description, "cash_description"),
    p_note: typeof prepared.cash_payload_snapshot.note === "string"
      ? prepared.cash_payload_snapshot.note
      : "",
    p_payload_snapshot: prepared.cash_payload_snapshot,
    p_currency: requiredText(prepared.payment_currency, "payment_currency").toUpperCase(),
  };
}

export function buildSchoolExpenseCashEvidence(cashRequest) {
  if (!cashRequest || typeof cashRequest !== "object") {
    throw new Error("Cash request evidence is required");
  }
  const snapshot = cashRequest.payload_snapshot;
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("Cash request payload_snapshot is required");
  }

  return {
    p_expense_record_id: requiredUuid(cashRequest.external_reference_id, "external_reference_id"),
    p_cash_request_id: requiredUuid(cashRequest.id, "cash_request_id"),
    p_cash_request_status: requiredText(cashRequest.status, "cash_request_status"),
    p_external_source: requiredText(cashRequest.external_source, "external_source"),
    p_request_event_id: requiredUuid(cashRequest.external_event_id, "external_event_id"),
    p_idempotency_key: requiredText(cashRequest.idempotency_key, "idempotency_key"),
    p_external_reference_type: requiredText(cashRequest.external_reference_type, "external_reference_type"),
    p_external_reference_id: requiredUuid(cashRequest.external_reference_id, "external_reference_id"),
    p_request_type: requiredText(cashRequest.request_type, "request_type"),
    p_transaction_type: requiredText(cashRequest.transaction_type, "transaction_type"),
    p_payment_amount: requiredAmount(cashRequest.amount, "amount"),
    p_payment_currency: requiredText(cashRequest.currency, "currency").toUpperCase(),
    p_cash_account_id: requiredUuid(cashRequest.account_id, "account_id"),
    p_charge_date: requiredDate(cashRequest.transacted_at, "transacted_at"),
    p_request_payload_fingerprint: requiredFingerprint(
      snapshot.school_attempt_payload_fingerprint,
    ),
  };
}
