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

export function inspectSchoolExpenseCashFingerprint(cashRequest) {
  if (!cashRequest || typeof cashRequest !== "object") {
    throw new Error("Cash request evidence is required");
  }
  const snapshot = cashRequest.payload_snapshot;
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("Cash request payload_snapshot is required");
  }

  if (!Object.prototype.hasOwnProperty.call(
    snapshot,
    "school_attempt_payload_fingerprint",
  )) {
    return { state: "missing" };
  }

  return {
    state: "present",
    fingerprint: requiredFingerprint(snapshot.school_attempt_payload_fingerprint),
  };
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

export function buildCashFixedCreateRpcPayload(prepared) {
  if (!prepared || typeof prepared !== "object") {
    throw new Error("School fixed prepare V2 returned no canonical payload");
  }
  if (!prepared.cash_payload_snapshot || typeof prepared.cash_payload_snapshot !== "object") {
    throw new Error("School fixed prepare V2 returned no cash_payload_snapshot");
  }
  const fingerprint = requiredFingerprint(prepared.request_payload_fingerprint);
  if (prepared.payment_route !== "fixed_credit_card") {
    throw new Error("School fixed prepare V2 returned the wrong payment_route");
  }
  if (prepared.cash_payload_snapshot.school_attempt_payload_fingerprint !== fingerprint) {
    throw new Error("School fixed prepare V2 payload fingerprint mismatch");
  }

  return {
    p_user_id: requiredUuid(prepared.cash_user_id, "cash_user_id"),
    p_external_source: "aozora_school",
    p_external_event_id: requiredUuid(prepared.request_event_id, "request_event_id"),
    p_external_reference_type: "school_expense_records",
    p_external_reference_id: requiredUuid(prepared.expense_id, "expense_id"),
    p_request_type: "expense_paid",
    p_transaction_type: "expense",
    p_card_instrument_id: requiredUuid(prepared.card_instrument_id, "card_instrument_id"),
    p_charge_date: requiredDate(prepared.charge_date, "charge_date"),
    p_suggested_fixed_month: requiredDate(
      prepared.suggested_fixed_month,
      "suggested_fixed_month",
    ),
    p_target_fixed_month: requiredDate(prepared.target_fixed_month, "target_fixed_month"),
    p_funding_date: requiredDate(prepared.funding_date, "funding_date"),
    p_amount: requiredAmount(prepared.settlement_amount, "settlement_amount"),
    p_currency: requiredText(prepared.settlement_currency, "settlement_currency").toUpperCase(),
    p_idempotency_key: requiredText(prepared.idempotency_key, "idempotency_key"),
    p_description: requiredText(prepared.cash_description, "cash_description"),
    p_note: typeof prepared.cash_payload_snapshot.note === "string"
      ? prepared.cash_payload_snapshot.note
      : "",
    p_payload_snapshot: prepared.cash_payload_snapshot,
  };
}

export function buildSchoolExpenseCashEvidence(cashRequest, options = {}) {
  if (!cashRequest || typeof cashRequest !== "object") {
    throw new Error("Cash request evidence is required");
  }
  const snapshot = cashRequest.payload_snapshot;
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("Cash request payload_snapshot is required");
  }
  if (
    cashRequest.payment_route !== undefined &&
    cashRequest.payment_route !== null &&
    cashRequest.payment_route !== "immediate_account"
  ) {
    throw new Error("Immediate School Cash evidence has the wrong payment_route");
  }

  const fingerprintState = inspectSchoolExpenseCashFingerprint(cashRequest);
  const hasHistoricalFingerprint = Object.prototype.hasOwnProperty.call(
    options,
    "resolvedHistoricalFingerprint",
  );
  let fingerprint;
  if (fingerprintState.state === "present") {
    if (hasHistoricalFingerprint) {
      throw new Error("Native School Cash V2 fingerprint cannot be overridden");
    }
    fingerprint = fingerprintState.fingerprint;
  } else {
    if (!hasHistoricalFingerprint) {
      throw new Error("SCHOOL_EXPENSE_CASH_NATIVE_FINGERPRINT_MISSING");
    }
    fingerprint = requiredFingerprint(options.resolvedHistoricalFingerprint);
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
    p_request_payload_fingerprint: fingerprint,
  };
}

export function buildSchoolExpenseFixedCashEvidence(cashRequest) {
  if (!cashRequest || typeof cashRequest !== "object") {
    throw new Error("Cash fixed request evidence is required");
  }
  const snapshot = cashRequest.payload_snapshot;
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("Cash fixed request payload_snapshot is required");
  }
  if (cashRequest.payment_route !== "fixed_credit_card") {
    throw new Error("Cash fixed request evidence has the wrong payment_route");
  }
  if (cashRequest.account_id !== null || cashRequest.funding_account_id !== null) {
    throw new Error("Cash fixed request must not contain an account or funding account");
  }

  const fundingDate = requiredDate(snapshot.funding_date, "funding_date");
  if (snapshot.card_instrument_id !== cashRequest.card_instrument_id) {
    throw new Error("Cash fixed request card snapshot mismatch");
  }
  if (snapshot.charge_date !== cashRequest.charge_date) {
    throw new Error("Cash fixed request charge-date snapshot mismatch");
  }
  if (snapshot.suggested_fixed_month !== cashRequest.suggested_fixed_month) {
    throw new Error("Cash fixed request suggested-month snapshot mismatch");
  }
  if (snapshot.target_fixed_month !== cashRequest.target_fixed_month) {
    throw new Error("Cash fixed request target-month snapshot mismatch");
  }

  return {
    p_expense_record_id: requiredUuid(cashRequest.external_reference_id, "external_reference_id"),
    p_cash_request_id: requiredUuid(cashRequest.id, "cash_request_id"),
    p_cash_request_status: requiredText(cashRequest.status, "cash_request_status"),
    p_payment_route: "fixed_credit_card",
    p_external_source: requiredText(cashRequest.external_source, "external_source"),
    p_request_event_id: requiredUuid(cashRequest.external_event_id, "external_event_id"),
    p_idempotency_key: requiredText(cashRequest.idempotency_key, "idempotency_key"),
    p_external_reference_type: requiredText(
      cashRequest.external_reference_type,
      "external_reference_type",
    ),
    p_external_reference_id: requiredUuid(
      cashRequest.external_reference_id,
      "external_reference_id",
    ),
    p_request_type: requiredText(cashRequest.request_type, "request_type"),
    p_transaction_type: requiredText(cashRequest.transaction_type, "transaction_type"),
    p_settlement_amount: requiredAmount(cashRequest.amount, "amount"),
    p_settlement_currency: requiredText(cashRequest.currency, "currency").toUpperCase(),
    p_card_instrument_id: requiredUuid(cashRequest.card_instrument_id, "card_instrument_id"),
    p_charge_date: requiredDate(cashRequest.charge_date, "charge_date"),
    p_suggested_fixed_month: requiredDate(
      cashRequest.suggested_fixed_month,
      "suggested_fixed_month",
    ),
    p_target_fixed_month: requiredDate(cashRequest.target_fixed_month, "target_fixed_month"),
    p_funding_date: fundingDate,
    p_account_id: null,
    p_funding_account_id: null,
    p_request_payload_fingerprint: requiredFingerprint(
      snapshot.school_attempt_payload_fingerprint,
    ),
    p_cash_transaction_id: cashRequest.created_transaction_id ?? null,
    p_fixed_projection_id: cashRequest.fixed_projection_id ?? null,
  };
}

export function buildSchoolExpenseFixedApprovedEvidence(cashRequest, approvalEvidence) {
  const base = buildSchoolExpenseFixedCashEvidence(cashRequest);
  if (!approvalEvidence || typeof approvalEvidence !== "object") {
    throw new Error("Cash fixed approval evidence is required");
  }

  const exact = (field, requestValue, evidenceValue) => {
    if (requestValue !== evidenceValue) {
      throw new Error(`Cash fixed approval evidence mismatch: ${field}`);
    }
    return evidenceValue;
  };
  const requiredNullableUuid = (value, field) => {
    if (value === null) return null;
    return requiredUuid(value, field);
  };
  const requiredInteger = (value, field) => {
    const parsed = typeof value === "number" ? value : Number(value);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`Cash fixed approval evidence has invalid ${field}`);
    }
    return parsed;
  };

  exact("request_id", cashRequest.id, approvalEvidence.request_id);
  exact("request_status", cashRequest.status, approvalEvidence.request_status);
  exact("payment_route", cashRequest.payment_route, approvalEvidence.payment_route);
  exact("external_event_id", cashRequest.external_event_id, approvalEvidence.external_event_id);
  exact("external_reference_id", cashRequest.external_reference_id, approvalEvidence.external_reference_id);
  exact("idempotency_key", cashRequest.idempotency_key, approvalEvidence.idempotency_key);
  exact("card_instrument_id", cashRequest.card_instrument_id, approvalEvidence.card_instrument_id);
  exact("charge_date", cashRequest.charge_date, approvalEvidence.charge_date);
  exact("suggested_fixed_month", cashRequest.suggested_fixed_month, approvalEvidence.suggested_fixed_month);
  exact("target_fixed_month", cashRequest.target_fixed_month, approvalEvidence.target_fixed_month);
  exact("created_transaction_id", cashRequest.created_transaction_id, approvalEvidence.created_transaction_id);
  exact("fixed_projection_id", cashRequest.fixed_projection_id, approvalEvidence.fixed_projection_id);

  return {
    ...base,
    p_original_amount: requiredAmount(approvalEvidence.original_amount, "original_amount"),
    p_original_currency: requiredText(approvalEvidence.original_currency, "original_currency").toUpperCase(),
    p_cash_transaction_id: requiredNullableUuid(
      approvalEvidence.created_transaction_id,
      "created_transaction_id",
    ),
    p_fixed_projection_id: requiredUuid(
      approvalEvidence.fixed_projection_id,
      "fixed_projection_id",
    ),
    p_projection_status: requiredText(
      approvalEvidence.projection_status,
      "projection_status",
    ),
    p_projection_version: requiredInteger(
      approvalEvidence.projection_version,
      "projection_version",
    ),
    p_projection_funding_status: requiredText(
      approvalEvidence.funding_status,
      "funding_status",
    ),
    p_projection_funding_channel_id: requiredUuid(
      approvalEvidence.funding_payment_channel_id,
      "funding_payment_channel_id",
    ),
    p_projection_funding_transaction_id: requiredNullableUuid(
      approvalEvidence.funding_transaction_id,
      "funding_transaction_id",
    ),
    p_fixed_item_id: requiredUuid(approvalEvidence.fixed_item_id, "fixed_item_id"),
    p_fixed_item_template_id: requiredNullableUuid(
      approvalEvidence.fixed_item_template_id,
      "fixed_item_template_id",
    ),
    p_fixed_item_scope: requiredText(approvalEvidence.fixed_item_scope, "fixed_item_scope"),
    p_fixed_item_currency: requiredText(
      approvalEvidence.fixed_item_currency,
      "fixed_item_currency",
    ).toUpperCase(),
    p_fixed_item_direction: requiredText(
      approvalEvidence.fixed_item_direction,
      "fixed_item_direction",
    ),
    p_fixed_item_amount: requiredAmount(approvalEvidence.fixed_item_amount, "fixed_item_amount"),
    p_fixed_item_month_key: requiredText(
      approvalEvidence.fixed_item_month_key,
      "fixed_item_month_key",
    ),
    p_fixed_item_due_date: requiredDate(
      approvalEvidence.fixed_item_due_date,
      "fixed_item_due_date",
    ),
    p_fixed_item_payment_group: requiredText(
      approvalEvidence.fixed_item_payment_group,
      "fixed_item_payment_group",
    ),
    p_fixed_item_status: requiredText(
      approvalEvidence.fixed_item_status,
      "fixed_item_status",
    ),
    p_fixed_item_account_id: requiredNullableUuid(
      approvalEvidence.fixed_item_account_id,
      "fixed_item_account_id",
    ),
    p_fixed_item_linked_jpy_transaction_id: requiredNullableUuid(
      approvalEvidence.fixed_item_linked_jpy_transaction_id,
      "fixed_item_linked_jpy_transaction_id",
    ),
    p_fixed_item_linked_cny_transaction_id: requiredNullableUuid(
      approvalEvidence.fixed_item_linked_cny_transaction_id,
      "fixed_item_linked_cny_transaction_id",
    ),
    p_approved_actor: requiredUuid(approvalEvidence.approved_by, "approved_by"),
    p_approved_at: requiredText(approvalEvidence.approved_at, "approved_at"),
  };
}
