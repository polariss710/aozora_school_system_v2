const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH64_RE = /^[0-9a-f]{64}$/;
const HASH32_RE = /^[0-9a-f]{32}$/;

/**
 * @typedef {Object} CorrectionTarget
 * @property {string} operation_id
 * @property {string} original_home_request_id
 * @property {string} original_home_transaction_id
 * @property {string} school_expense_id
 * @property {string} school_attempt_id
 */

/** @typedef {Record<string, unknown> & {ok: boolean, code?: string, message?: string}} RpcResult */
/**
 * @typedef {RpcResult & {
 *   school_expense_id: string, school_attempt_id: string,
 *   original_home_request_id: string, original_home_transaction_id: string,
 *   school_event_id: string, school_idempotency_key: string,
 *   school_fingerprint: string, amount: number, currency: string,
 *   charge_date: string, actor_id: string,
 *   expense_snapshot: Record<string, unknown>, attempt_snapshot: Record<string, unknown>
 * }} SchoolSource
 */
/**
 * @typedef {RpcResult & {
 *   status: "prepared"|"completed", operation_id: string, correction_id: string,
 *   original_home_request_id: string, original_home_transaction_id: string,
 *   school_expense_id: string, school_attempt_id: string,
 *   balance_effect_id: string, replacement_request_id: string,
 *   replacement_fixed_item_id: string, replacement_projection_id: string,
 *   amount: number, currency: string, original_effective_date: string,
 *   accounting_scope: string, external_event_id: string,
 *   original_idempotency_key: string, school_fingerprint: string,
 *   home_payload_hash: string, replacement_fingerprint: string,
 *   actor_id: string
 * }} HomeCorrectionResult
 */
/**
 * @typedef {RpcResult & {
 *   school_evidence_id: string, operation_id: string, home_correction_id: string,
 *   school_expense_id: string, school_attempt_id: string, actor_id: string,
 *   school_finalized_at: string, school_evidence_fingerprint: string
 * }} SchoolEvidence
 */

/** @typedef {{p_school_expense_id:string,p_school_attempt_id:string,p_actor_id:string}} SchoolSourceArgs */
/** @typedef {{p_operation_id:string}} OperationArgs */
/** @typedef {{p_operation_id:string,p_original_home_request_id:string,p_original_home_transaction_id:string,p_school_expense_id:string,p_school_attempt_id:string,p_school_fingerprint:string,p_actor_id:string}} HomePrepareArgs */
/** @typedef {{p_operation_id:string,p_home_correction_id:string,p_original_home_request_id:string,p_original_home_transaction_id:string,p_home_balance_effect_id:string,p_replacement_request_id:string,p_replacement_fixed_item_id:string,p_replacement_projection_id:string,p_school_expense_id:string,p_school_attempt_id:string,p_amount:number,p_currency:string,p_charge_date:string,p_accounting_scope:string,p_external_event_id:string,p_original_idempotency_key:string,p_school_fingerprint:string,p_home_payload_hash:string,p_replacement_fingerprint:string,p_actor_id:string,p_home_prepared_snapshot:HomeCorrectionResult}} SchoolFinalizeArgs */
/** @typedef {{p_correction_id:string,p_operation_id:string,p_school_evidence_id:string,p_school_evidence_fingerprint:string,p_school_finalized_at:string,p_actor_id:string,p_school_evidence_snapshot:SchoolEvidence}} HomeCompleteArgs */
/**
 * @typedef {
 *   {name:"school_get_expense_cash_correction_source_v1",args:SchoolSourceArgs} |
 *   {name:"home_get_external_transaction_correction_p",args:OperationArgs} |
 *   {name:"home_prepare_external_transaction_correction_p",args:HomePrepareArgs} |
 *   {name:"school_get_expense_cash_correction_p",args:OperationArgs} |
 *   {name:"school_finalize_expense_cash_correction_p",args:SchoolFinalizeArgs} |
 *   {name:"home_complete_external_transaction_correction_p",args:HomeCompleteArgs}
 * } CorrectionRpcCall
 */

const CLIENT_ERRORS = Object.freeze({
  CORRECTION_P_INVALID_JSON: ["请求JSON无效。", 400],
  CORRECTION_P_INVALID_TARGET: ["Correction-P目标标识无效。", 400],
  SCHOOL_AUTH_REQUIRED: ["需要登录后才能执行。", 401],
  SCHOOL_AUTH_INVALID: ["登录状态无效。", 401],
  P0G1_ACTIVE_ADMIN_REQUIRED: ["仅active admin可执行。", 403],
  METHOD_NOT_ALLOWED: ["仅支持POST请求。", 405],
  HOME_CORRECTION_ROUTE_POLICY_NOT_CONFIGURED: ["Correction-P固定路线尚未配置。", 409],
  HOME_CORRECTION_ROUTE_POLICY_CONFLICT: ["Correction-P固定路线配置冲突。", 409],
  HOME_CORRECTION_OPERATION_PAYLOAD_CONFLICT: ["operation已存在但业务身份不一致。", 409],
  HOME_CORRECTION_BUSINESS_OPERATION_CONFLICT: ["该业务已由另一operation处理。", 409],
  HOME_CORRECTION_DUPLICATE_IDENTITY: ["该业务身份已被Correction-P占用。", 409],
  HOME_CORRECTION_ORIGINAL_REQUEST_MISMATCH: ["Home原请求状态不再匹配。", 409],
  HOME_CORRECTION_ORIGINAL_TRANSACTION_MISMATCH: ["Home原交易状态不再匹配。", 409],
  SCHOOL_CORRECTION_P_SOURCE_MISMATCH: ["School原始事实不再匹配。", 409],
  SCHOOL_CORRECTION_P_TERMINAL_CONFLICT: ["School evidence已存在且内容冲突。", 409],
  HOME_CORRECTION_COMPLETE_TERMINAL_CONFLICT: ["Home completed evidence冲突。", 409],
  CORRECTION_P_HOME_PREPARE_RECOVERABLE: ["Home prepare结果暂不可确认，请使用相同operation重试。", 503],
  CORRECTION_P_SCHOOL_FINALIZE_RECOVERABLE: ["School finalize结果暂不可确认，请使用相同operation重试。", 503],
  CORRECTION_P_HOME_COMPLETE_RECOVERABLE: ["Home complete结果暂不可确认，请使用相同operation重试。", 503],
  CORRECTION_P_INTERNAL_ERROR: ["Correction-P暂时无法完成，请使用相同operation重试。", 500],
});

const RPC_ARG_KEYS = Object.freeze({
  school_get_expense_cash_correction_source_v1: [
    "p_school_expense_id", "p_school_attempt_id", "p_actor_id",
  ],
  home_get_external_transaction_correction_p: ["p_operation_id"],
  home_prepare_external_transaction_correction_p: [
    "p_operation_id", "p_original_home_request_id", "p_original_home_transaction_id",
    "p_school_expense_id", "p_school_attempt_id", "p_school_fingerprint", "p_actor_id",
  ],
  school_get_expense_cash_correction_p: ["p_operation_id"],
  school_finalize_expense_cash_correction_p: [
    "p_operation_id", "p_home_correction_id", "p_original_home_request_id",
    "p_original_home_transaction_id", "p_home_balance_effect_id",
    "p_replacement_request_id", "p_replacement_fixed_item_id",
    "p_replacement_projection_id", "p_school_expense_id", "p_school_attempt_id",
    "p_amount", "p_currency", "p_charge_date", "p_accounting_scope",
    "p_external_event_id", "p_original_idempotency_key", "p_school_fingerprint",
    "p_home_payload_hash", "p_replacement_fingerprint", "p_actor_id",
    "p_home_prepared_snapshot",
  ],
  home_complete_external_transaction_correction_p: [
    "p_correction_id", "p_operation_id", "p_school_evidence_id",
    "p_school_evidence_fingerprint", "p_school_finalized_at", "p_actor_id",
    "p_school_evidence_snapshot",
  ],
});

const SOURCE_RESULT_KEYS = Object.freeze([
  "ok", "school_expense_id", "school_attempt_id", "original_home_request_id",
  "original_home_transaction_id", "school_event_id", "school_idempotency_key",
  "school_fingerprint", "amount", "currency", "charge_date", "actor_id",
  "expense_snapshot", "attempt_snapshot",
]);
const HOME_RESULT_KEYS = Object.freeze([
  "ok", "correction_id", "correction_type", "reason_code", "status", "version",
  "business_idempotency_key", "operation_id", "original_home_request_id",
  "original_home_transaction_id", "school_expense_id", "school_attempt_id",
  "balance_effect_id", "replacement_request_id", "replacement_fixed_item_id",
  "replacement_projection_id", "school_evidence_id", "amount", "currency",
  "account_id", "original_effective_date", "accounting_scope", "external_event_id",
  "external_reference_type", "external_reference_id", "original_idempotency_key",
  "school_fingerprint", "home_payload_hash", "replacement_fingerprint",
  "school_evidence_fingerprint", "school_evidence_snapshot", "actor_source",
  "actor_id", "prepared_at", "completed_at", "retry_count", "last_retried_at",
  "created_at", "effect", "replacement", "idempotent", "inserted", "message",
]);
const SCHOOL_RESULT_KEYS = Object.freeze([
  "ok", "school_evidence_id", "operation_id", "correction_type", "reason_code",
  "school_expense_id", "school_attempt_id", "home_correction_id",
  "original_home_request_id", "original_home_transaction_id", "home_balance_effect_id",
  "replacement_request_id", "replacement_fixed_item_id", "replacement_projection_id",
  "amount", "currency", "charge_date", "accounting_scope", "external_event_id",
  "original_idempotency_key", "school_fingerprint", "home_payload_hash",
  "replacement_fingerprint", "actor_id", "school_finalized_at",
  "school_evidence_fingerprint", "idempotent", "message",
]);
const FAILURE_RESULT_KEYS = Object.freeze(["ok", "code", "message"]);

export class CorrectionPError extends Error {
  /** @param {string} code @param {string} [internalCategory] */
  constructor(code, internalCategory = "APPLICATION") {
    super(code);
    this.name = "CorrectionPError";
    this.code = Object.hasOwn(CLIENT_ERRORS, code) ? code : "CORRECTION_P_INTERNAL_ERROR";
    this.internalCategory = internalCategory;
  }
}

/** @param {unknown} error */
export function correctionPClientError(error) {
  const code = error instanceof CorrectionPError
    ? error.code
    : "CORRECTION_P_INTERNAL_ERROR";
  const [message, status] = CLIENT_ERRORS[code] || CLIENT_ERRORS.CORRECTION_P_INTERNAL_ERROR;
  return { status, body: { ok: false, code, message } };
}

export function rpcTransportError() {
  return new CorrectionPError("CORRECTION_P_INTERNAL_ERROR", "RPC_TRANSPORT");
}

/** @param {string} code @param {string} [category] @returns {never} */
function typed(code, category = "CONTRACT") {
  throw new CorrectionPError(code, category);
}

/** @param {unknown} value @returns {value is Record<string, unknown>} */
function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** @param {Record<string, unknown>} value @param {readonly string[]} expected */
function requireExactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_ARGS_CONTRACT");
  }
}

/** @param {Record<string, unknown>} value @param {readonly string[]} allowed @returns {RpcResult} */
function copyAllowedResult(value, allowed) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) typed("CORRECTION_P_INTERNAL_ERROR", "RPC_RESULT_EXTRA_FIELD");
  }
  /** @type {Record<string, unknown>} */
  const copy = {};
  for (const key of allowed) {
    if (Object.hasOwn(value, key)) copy[key] = value[key];
  }
  return /** @type {RpcResult} */ (copy);
}

/** @param {unknown} home @returns {asserts home is HomeCorrectionResult} */
function assertHomeResultShape(home) {
  if (!isRecord(home) || home.ok !== true || !["prepared", "completed"].includes(String(home.status)) ||
      !UUID_RE.test(String(home.operation_id || "")) || !UUID_RE.test(String(home.correction_id || "")) ||
      !UUID_RE.test(String(home.original_home_request_id || "")) ||
      !UUID_RE.test(String(home.original_home_transaction_id || "")) ||
      !UUID_RE.test(String(home.school_expense_id || "")) ||
      !UUID_RE.test(String(home.school_attempt_id || "")) ||
      !UUID_RE.test(String(home.balance_effect_id || "")) ||
      !UUID_RE.test(String(home.replacement_request_id || "")) ||
      !UUID_RE.test(String(home.replacement_fixed_item_id || "")) ||
      !UUID_RE.test(String(home.replacement_projection_id || "")) ||
      typeof home.amount !== "number" || !Number.isFinite(home.amount) || home.amount <= 0 ||
      typeof home.currency !== "string" || typeof home.original_effective_date !== "string" ||
      typeof home.accounting_scope !== "string" || !UUID_RE.test(String(home.external_event_id || "")) ||
      typeof home.original_idempotency_key !== "string" ||
      !HASH64_RE.test(String(home.school_fingerprint || "")) ||
      !HASH32_RE.test(String(home.home_payload_hash || "")) ||
      !HASH64_RE.test(String(home.replacement_fingerprint || "")) ||
      !UUID_RE.test(String(home.actor_id || ""))) {
    typed("CORRECTION_P_INTERNAL_ERROR", "HOME_PREPARED_CONTRACT");
  }
}

/** @param {unknown} evidence @returns {asserts evidence is SchoolEvidence} */
function assertSchoolEvidenceShape(evidence) {
  if (!isRecord(evidence) || evidence.ok !== true ||
      !UUID_RE.test(String(evidence.school_evidence_id || "")) ||
      !UUID_RE.test(String(evidence.operation_id || "")) ||
      !UUID_RE.test(String(evidence.home_correction_id || "")) ||
      !UUID_RE.test(String(evidence.school_expense_id || "")) ||
      !UUID_RE.test(String(evidence.school_attempt_id || "")) ||
      !UUID_RE.test(String(evidence.actor_id || "")) ||
      typeof evidence.school_finalized_at !== "string" ||
      !HASH64_RE.test(String(evidence.school_evidence_fingerprint || ""))) {
    typed("CORRECTION_P_INTERNAL_ERROR", "SCHOOL_EVIDENCE_CONTRACT");
  }
}

/** @param {CorrectionRpcCall} call @param {unknown} raw @returns {RpcResult} */
function validateCorrectionRpcResult(call, raw) {
  if (!isRecord(raw) || typeof raw.ok !== "boolean") {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_MALFORMED_RESULT");
  }
  if (!raw.ok) {
    if (typeof raw.code !== "string" || typeof raw.message !== "string") {
      typed("CORRECTION_P_INTERNAL_ERROR", "RPC_MALFORMED_RESULT");
    }
    return copyAllowedResult(raw, FAILURE_RESULT_KEYS);
  }
  if (call.name === "school_get_expense_cash_correction_source_v1") {
    const result = copyAllowedResult(raw, SOURCE_RESULT_KEYS);
    if (result.school_expense_id !== call.args.p_school_expense_id ||
        result.school_attempt_id !== call.args.p_school_attempt_id ||
        result.actor_id !== call.args.p_actor_id ||
        typeof result.amount !== "number" || !Number.isFinite(result.amount) ||
        typeof result.currency !== "string" || typeof result.charge_date !== "string" ||
        typeof result.school_idempotency_key !== "string" ||
        !UUID_RE.test(String(result.original_home_request_id || "")) ||
        !UUID_RE.test(String(result.original_home_transaction_id || "")) ||
        !UUID_RE.test(String(result.school_event_id || "")) ||
        !HASH64_RE.test(String(result.school_fingerprint || "")) ||
        !isRecord(result.expense_snapshot) || !isRecord(result.attempt_snapshot)) {
      typed("CORRECTION_P_INTERNAL_ERROR", "SCHOOL_SOURCE_CONTRACT");
    }
    return result;
  }
  if (call.name === "home_get_external_transaction_correction_p" ||
      call.name === "home_prepare_external_transaction_correction_p" ||
      call.name === "home_complete_external_transaction_correction_p") {
    const result = copyAllowedResult(raw, HOME_RESULT_KEYS);
    assertHomeResultShape(result);
    if (result.operation_id !== call.args.p_operation_id) {
      typed("CORRECTION_P_INTERNAL_ERROR", "RPC_OPERATION_IDENTITY");
    }
    return result;
  }
  const result = copyAllowedResult(raw, SCHOOL_RESULT_KEYS);
  assertSchoolEvidenceShape(result);
  if (result.operation_id !== call.args.p_operation_id) {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_OPERATION_IDENTITY");
  }
  return result;
}

/**
 * Centralized vendor boundary. Supabase's schema-less generic cannot express
 * this fixed cross-project RPC set, so the method is invoked from `unknown`
 * and every call/result is runtime allowlisted before it reaches the saga.
 * @param {unknown} client
 * @param {CorrectionRpcCall} call
 * @returns {Promise<RpcResult>}
 */
export async function callCorrectionRpc(client, call) {
  if (!isRecord(call) || typeof call.name !== "string" ||
      !Object.hasOwn(RPC_ARG_KEYS, call.name) || !isRecord(call.args)) {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_NAME_CONTRACT");
  }
  const expected = RPC_ARG_KEYS[/** @type {keyof typeof RPC_ARG_KEYS} */ (call.name)];
  requireExactKeys(call.args, expected);
  if (!isRecord(client) || typeof client.rpc !== "function") {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_CLIENT_CONTRACT");
  }
  /** @type {unknown} */
  let envelope;
  try {
    envelope = await Reflect.apply(client.rpc, client, [call.name, call.args]);
  } catch (_error) {
    throw rpcTransportError();
  }
  if (!isRecord(envelope) || !Object.hasOwn(envelope, "data") || !Object.hasOwn(envelope, "error")) {
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_ENVELOPE_CONTRACT");
  }
  if (envelope.error) throw rpcTransportError();
  return validateCorrectionRpcResult(call, envelope.data);
}

/** @param {unknown} body @returns {CorrectionTarget} */
export function requireCorrectionTarget(body) {
  if (!isRecord(body)) typed("CORRECTION_P_INVALID_TARGET", "BODY_IDENTITY");
  const fields = [
    "operation_id",
    "original_home_request_id",
    "original_home_transaction_id",
    "school_expense_id",
    "school_attempt_id",
  ];
  /** @type {Record<string, string>} */
  const values = {};
  for (const field of fields) {
    const value = typeof body[field] === "string" ? body[field].trim() : "";
    if (!UUID_RE.test(value)) typed("CORRECTION_P_INVALID_TARGET", "BODY_IDENTITY");
    values[field] = value;
  }
  const allowed = new Set(fields);
  for (const field of Object.keys(body || {})) {
    if (!allowed.has(field)) typed("CORRECTION_P_INVALID_TARGET", "BODY_OVERRIDE");
  }
  return {
    operation_id: values.operation_id,
    original_home_request_id: values.original_home_request_id,
    original_home_transaction_id: values.original_home_transaction_id,
    school_expense_id: values.school_expense_id,
    school_attempt_id: values.school_attempt_id,
  };
}

/** @param {unknown} source @param {CorrectionTarget} target @returns {asserts source is SchoolSource} */
export function assertSourceMatchesTarget(source, target) {
  if (!isRecord(source) || source.ok !== true || source.school_expense_id !== target.school_expense_id ||
      source.school_attempt_id !== target.school_attempt_id ||
      source.original_home_request_id !== target.original_home_request_id ||
      source.original_home_transaction_id !== target.original_home_transaction_id ||
      !HASH64_RE.test(source.school_fingerprint || "")) {
    typed("CORRECTION_P_INTERNAL_ERROR", "SCHOOL_SOURCE_CONTRACT");
  }
}

/** @param {SchoolSource} source @param {CorrectionTarget} target @param {string} actorId @returns {HomePrepareArgs} */
export function buildHomePrepareArgs(source, target, actorId) {
  return {
    p_operation_id: target.operation_id,
    p_original_home_request_id: target.original_home_request_id,
    p_original_home_transaction_id: target.original_home_transaction_id,
    p_school_expense_id: target.school_expense_id,
    p_school_attempt_id: target.school_attempt_id,
    p_school_fingerprint: source.school_fingerprint,
    p_actor_id: actorId,
  };
}

/** @param {unknown} home @param {CorrectionTarget} target @returns {asserts home is HomeCorrectionResult} */
export function assertHomePrepared(home, target) {
  assertHomeResultShape(home);
  if (
      home.operation_id !== target.operation_id ||
      home.original_home_request_id !== target.original_home_request_id ||
      home.original_home_transaction_id !== target.original_home_transaction_id ||
      home.school_expense_id !== target.school_expense_id ||
      home.school_attempt_id !== target.school_attempt_id ||
      !home.balance_effect_id || !home.replacement_request_id ||
      !home.replacement_fixed_item_id || !home.replacement_projection_id ||
      !HASH64_RE.test(home.school_fingerprint || "") ||
      !HASH32_RE.test(home.home_payload_hash || "") ||
      !HASH64_RE.test(home.replacement_fingerprint || "")) {
    typed("CORRECTION_P_INTERNAL_ERROR", "HOME_PREPARED_CONTRACT");
  }
}

/** @param {HomeCorrectionResult} home @param {string} actorId @returns {SchoolFinalizeArgs} */
export function buildSchoolFinalizeArgs(home, actorId) {
  return {
    p_operation_id: home.operation_id,
    p_home_correction_id: home.correction_id,
    p_original_home_request_id: home.original_home_request_id,
    p_original_home_transaction_id: home.original_home_transaction_id,
    p_home_balance_effect_id: home.balance_effect_id,
    p_replacement_request_id: home.replacement_request_id,
    p_replacement_fixed_item_id: home.replacement_fixed_item_id,
    p_replacement_projection_id: home.replacement_projection_id,
    p_school_expense_id: home.school_expense_id,
    p_school_attempt_id: home.school_attempt_id,
    p_amount: home.amount,
    p_currency: home.currency,
    p_charge_date: home.original_effective_date,
    p_accounting_scope: home.accounting_scope,
    p_external_event_id: home.external_event_id,
    p_original_idempotency_key: home.original_idempotency_key,
    p_school_fingerprint: home.school_fingerprint,
    p_home_payload_hash: home.home_payload_hash,
    p_replacement_fingerprint: home.replacement_fingerprint,
    p_actor_id: actorId,
    p_home_prepared_snapshot: home,
  };
}

/** @param {unknown} evidence @param {HomeCorrectionResult} home @param {string} actorId @returns {asserts evidence is SchoolEvidence} */
export function assertSchoolEvidence(evidence, home, actorId) {
  assertSchoolEvidenceShape(evidence);
  if (evidence.operation_id !== home.operation_id ||
      evidence.home_correction_id !== home.correction_id ||
      evidence.school_expense_id !== home.school_expense_id ||
      evidence.school_attempt_id !== home.school_attempt_id ||
      evidence.actor_id !== actorId ||
      !HASH64_RE.test(evidence.school_evidence_fingerprint || "") ||
      !evidence.school_evidence_id || !evidence.school_finalized_at) {
    typed("CORRECTION_P_INTERNAL_ERROR", "SCHOOL_EVIDENCE_CONTRACT");
  }
}

/** @param {HomeCorrectionResult} home @param {SchoolEvidence} evidence @param {string} actorId @returns {HomeCompleteArgs} */
export function buildHomeCompleteArgs(home, evidence, actorId) {
  return {
    p_correction_id: home.correction_id,
    p_operation_id: home.operation_id,
    p_school_evidence_id: evidence.school_evidence_id,
    p_school_evidence_fingerprint: evidence.school_evidence_fingerprint,
    p_school_finalized_at: evidence.school_finalized_at,
    p_actor_id: actorId,
    p_school_evidence_snapshot: evidence,
  };
}

/**
 * @template {RpcResult} T
 * @param {() => Promise<T>} writeCall
 * @param {() => Promise<T>} readCall
 * @param {string} [recoveryCode]
 * @returns {Promise<T>}
 */
export async function recoverWriterWithStatus(
  writeCall,
  readCall,
  recoveryCode = "CORRECTION_P_INTERNAL_ERROR",
) {
  let writerFailure;
  try {
    const written = await writeCall();
    if (written?.ok) return written;
    if (Object.hasOwn(CLIENT_ERRORS, written?.code)) typed(written.code, "RPC_TYPED_RESULT");
    typed("CORRECTION_P_INTERNAL_ERROR", "RPC_MALFORMED_RESULT");
  } catch (error) {
    writerFailure=error;
    try {
      const recovered = await readCall();
      if (recovered?.ok) return recovered;
    } catch (_readError) {
      // The caller receives only the stable recovery category below.
    }
    if (writerFailure instanceof CorrectionPError &&
        writerFailure.internalCategory === "RPC_TYPED_RESULT") {
      throw writerFailure;
    }
    typed(recoveryCode, "SAGA_STATUS_UNCONFIRMED");
  }
}
