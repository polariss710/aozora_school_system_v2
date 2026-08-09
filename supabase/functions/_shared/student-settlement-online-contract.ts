export const SETTLEMENT_ONLINE_MAX_BODY_BYTES = 64 * 1024;

export const SETTLEMENT_ONLINE_ALLOWED_ORIGINS = Object.freeze([
  "https://polariss710.github.io",
  "http://localhost:8000",
  "http://127.0.0.1:8000",
  "http://localhost:8001",
  "http://127.0.0.1:8001",
]);

const ALLOWED_ORIGIN_SET = new Set(SETTLEMENT_ONLINE_ALLOWED_ORIGINS);
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MONTH_PATTERN = /^[0-9]{4}-(0[1-9]|1[0-2])$/;
const DATE_PATTERN = /^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])$/;
const TIMESTAMP_PATTERN =
  /^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1])T([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,6})?(?:Z|[+-](?:[0-1][0-9]|2[0-3]):[0-5][0-9])$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;
const DECIMAL_PATTERN = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/;
const POSITIVE_DECIMAL_PATTERN = /^(?:0\.(?:0*[1-9][0-9]*)|[1-9][0-9]*(?:\.[0-9]+)?)$/;
const STABLE_CODE_PATTERN = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}\b/;

const SOURCE_TREATMENT_MODES = new Set([
  "separate_makeup_and_overage_v1",
  "net_lesson_variance_to_financial_credit_v1",
]);
const ADJUSTMENT_MODES = new Set([
  "carry_final_balance",
  "clear_balance",
  "manual_adjustment",
]);

const SAVE_FIELDS = new Set([
  "student_id",
  "settlement_month",
  "source_treatment_mode",
  "settlement_exchange_rate",
  "settlement_exchange_rate_source",
  "settlement_exchange_rate_effective_date",
  "adjustment_mode",
  "manual_adjustment_amount_cny",
  "reason",
  "note",
  "expected_preview_manifest_sha256",
  "expected_lesson_variance_manifest_sha256",
  "expected_source_count",
  "expected_unused_planned_credit_jpy",
  "expected_overage_charge_jpy",
  "expected_net_lesson_variance_jpy",
  "expected_net_lesson_variance_cny",
  "expected_system_difference_cny",
  "expected_final_carryover_cny",
  "expected_source_treatment_draft_id",
  "expected_source_treatment_draft_updated_at",
  "expected_adjustment_draft_id",
  "expected_adjustment_draft_updated_at",
  "client_correlation_id",
]);

const LOCK_FIELDS = new Set([
  "student_id",
  "settlement_month",
  "expected_source_treatment_draft_id",
  "expected_source_treatment_draft_updated_at",
  "expected_adjustment_draft_id",
  "expected_adjustment_draft_updated_at",
  "expected_preview_manifest_sha256",
  "expected_lesson_variance_manifest_sha256",
  "expected_source_count",
  "expected_unused_planned_credit_jpy",
  "expected_overage_charge_jpy",
  "expected_net_lesson_variance_jpy",
  "expected_net_lesson_variance_cny",
  "expected_system_difference_cny",
  "expected_final_carryover_cny",
  "note",
  "confirm_lock",
  "client_correlation_id",
]);

const REQUIRED_SAVE_FIELDS = [...SAVE_FIELDS].filter((field) => (
  field !== "client_correlation_id"
));
const REQUIRED_LOCK_FIELDS = [...LOCK_FIELDS].filter((field) => (
  field !== "client_correlation_id"
));

export type JsonRecord = Record<string, unknown>;
export type SettlementOnlineAction = "save" | "lock";

export type SaveSettlementRequest = {
  student_id: string;
  settlement_month: string;
  source_treatment_mode: string;
  settlement_exchange_rate: string | null;
  settlement_exchange_rate_source: string | null;
  settlement_exchange_rate_effective_date: string | null;
  adjustment_mode: string;
  manual_adjustment_amount_cny: string | null;
  reason: string;
  note: string | null;
  expected_preview_manifest_sha256: string;
  expected_lesson_variance_manifest_sha256: string;
  expected_source_count: number;
  expected_unused_planned_credit_jpy: string;
  expected_overage_charge_jpy: string;
  expected_net_lesson_variance_jpy: string;
  expected_net_lesson_variance_cny: string;
  expected_system_difference_cny: string;
  expected_final_carryover_cny: string;
  expected_source_treatment_draft_id: string | null;
  expected_source_treatment_draft_updated_at: string | null;
  expected_adjustment_draft_id: string | null;
  expected_adjustment_draft_updated_at: string | null;
  client_correlation_id: string | null;
};

export type LockSettlementRequest = {
  student_id: string;
  settlement_month: string;
  expected_source_treatment_draft_id: string;
  expected_source_treatment_draft_updated_at: string;
  expected_adjustment_draft_id: string;
  expected_adjustment_draft_updated_at: string;
  expected_preview_manifest_sha256: string;
  expected_lesson_variance_manifest_sha256: string;
  expected_source_count: number;
  expected_unused_planned_credit_jpy: string;
  expected_overage_charge_jpy: string;
  expected_net_lesson_variance_jpy: string;
  expected_net_lesson_variance_cny: string;
  expected_system_difference_cny: string;
  expected_final_carryover_cny: string;
  note: string | null;
  confirm_lock: true;
  client_correlation_id: string | null;
};

export class SettlementOnlinePublicError extends Error {
  code: string;
  status: number;
  action: string;

  constructor(code: string, message: string, status: number, action = "stop") {
    super(message);
    this.name = "SettlementOnlinePublicError";
    this.code = code;
    this.status = status;
    this.action = action;
  }
}

export function resolveAllowedOrigin(origin: string | null): string | null {
  if (!origin) return null;
  if (!ALLOWED_ORIGIN_SET.has(origin)) {
    throw new SettlementOnlinePublicError(
      "SETTLEMENT_EDGE_ORIGIN_FORBIDDEN",
      "请求来源不在允许范围内。",
      403,
    );
  }
  return origin;
}

export function buildCorsHeaders(
  allowedOrigin: string | null,
  requestId: string,
): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
    "x-request-id": requestId,
  };
  if (allowedOrigin) {
    headers["Access-Control-Allow-Origin"] = allowedOrigin;
  }
  return headers;
}

export function parseSaveSettlementRequest(value: unknown): SaveSettlementRequest {
  const body = requireRecord(value);
  requireExactFields(body, SAVE_FIELDS, REQUIRED_SAVE_FIELDS);

  const sourceTreatmentMode = requireEnum(
    body.source_treatment_mode,
    "source_treatment_mode",
    SOURCE_TREATMENT_MODES,
  );
  const adjustmentMode = requireEnum(
    body.adjustment_mode,
    "adjustment_mode",
    ADJUSTMENT_MODES,
  );
  const rate = optionalDecimalString(body.settlement_exchange_rate,
    "settlement_exchange_rate", true);
  const rateSource = optionalText(body.settlement_exchange_rate_source,
    "settlement_exchange_rate_source", 240);
  const rateDate = optionalDate(body.settlement_exchange_rate_effective_date,
    "settlement_exchange_rate_effective_date");
  const manualAmount = optionalDecimalString(body.manual_adjustment_amount_cny,
    "manual_adjustment_amount_cny", false);

  if (sourceTreatmentMode === "separate_makeup_and_overage_v1") {
    if (rate !== null || rateSource !== null || rateDate !== null) {
      throw badRequest(
        "SETTLEMENT_EDGE_SOURCE_INPUT_FORBIDDEN",
        "当前课时差额处理方式不接受汇率输入。",
      );
    }
  } else if (rate === null || rateSource === null || rateDate === null) {
    throw badRequest(
      "SETTLEMENT_EDGE_SOURCE_INPUT_REQUIRED",
      "财务净额模式必须提供汇率、来源和生效日。",
    );
  }

  if (adjustmentMode === "manual_adjustment") {
    if (manualAmount === null) {
      throw badRequest(
        "SETTLEMENT_EDGE_MANUAL_AMOUNT_REQUIRED",
        "手动调整必须提供明确金额。",
      );
    }
  } else if (manualAmount !== null) {
    throw badRequest(
      "SETTLEMENT_EDGE_MANUAL_AMOUNT_FORBIDDEN",
      "当前调整方式的金额由数据库权威计算。",
    );
  }

  return {
    student_id: requireUuid(body.student_id, "student_id"),
    settlement_month: requireMonth(body.settlement_month),
    source_treatment_mode: sourceTreatmentMode,
    settlement_exchange_rate: rate,
    settlement_exchange_rate_source: rateSource,
    settlement_exchange_rate_effective_date: rateDate,
    adjustment_mode: adjustmentMode,
    manual_adjustment_amount_cny: manualAmount,
    reason: requireText(body.reason, "reason", 2000),
    note: optionalText(body.note, "note", 4000),
    expected_preview_manifest_sha256: requireSha256(
      body.expected_preview_manifest_sha256,
      "expected_preview_manifest_sha256",
    ),
    expected_lesson_variance_manifest_sha256: requireSha256(
      body.expected_lesson_variance_manifest_sha256,
      "expected_lesson_variance_manifest_sha256",
    ),
    expected_source_count: requireNonnegativeInteger(
      body.expected_source_count,
      "expected_source_count",
    ),
    expected_unused_planned_credit_jpy: requireDecimalString(
      body.expected_unused_planned_credit_jpy,
      "expected_unused_planned_credit_jpy",
    ),
    expected_overage_charge_jpy: requireDecimalString(
      body.expected_overage_charge_jpy,
      "expected_overage_charge_jpy",
    ),
    expected_net_lesson_variance_jpy: requireDecimalString(
      body.expected_net_lesson_variance_jpy,
      "expected_net_lesson_variance_jpy",
    ),
    expected_net_lesson_variance_cny: requireDecimalString(
      body.expected_net_lesson_variance_cny,
      "expected_net_lesson_variance_cny",
    ),
    expected_system_difference_cny: requireDecimalString(
      body.expected_system_difference_cny,
      "expected_system_difference_cny",
    ),
    expected_final_carryover_cny: requireDecimalString(
      body.expected_final_carryover_cny,
      "expected_final_carryover_cny",
    ),
    expected_source_treatment_draft_id: optionalUuid(
      body.expected_source_treatment_draft_id,
      "expected_source_treatment_draft_id",
    ),
    expected_source_treatment_draft_updated_at: optionalTimestamp(
      body.expected_source_treatment_draft_updated_at,
      "expected_source_treatment_draft_updated_at",
    ),
    expected_adjustment_draft_id: optionalUuid(
      body.expected_adjustment_draft_id,
      "expected_adjustment_draft_id",
    ),
    expected_adjustment_draft_updated_at: optionalTimestamp(
      body.expected_adjustment_draft_updated_at,
      "expected_adjustment_draft_updated_at",
    ),
    client_correlation_id: optionalUuid(
      body.client_correlation_id,
      "client_correlation_id",
    ),
  };
}

export function parseLockSettlementRequest(value: unknown): LockSettlementRequest {
  const body = requireRecord(value);
  requireExactFields(body, LOCK_FIELDS, REQUIRED_LOCK_FIELDS);
  if (body.confirm_lock !== true) {
    throw badRequest(
      "SETTLEMENT_EDGE_LOCK_CONFIRMATION_REQUIRED",
      "正式锁定前必须明确确认。",
    );
  }

  return {
    student_id: requireUuid(body.student_id, "student_id"),
    settlement_month: requireMonth(body.settlement_month),
    expected_source_treatment_draft_id: requireUuid(
      body.expected_source_treatment_draft_id,
      "expected_source_treatment_draft_id",
    ),
    expected_source_treatment_draft_updated_at: requireTimestamp(
      body.expected_source_treatment_draft_updated_at,
      "expected_source_treatment_draft_updated_at",
    ),
    expected_adjustment_draft_id: requireUuid(
      body.expected_adjustment_draft_id,
      "expected_adjustment_draft_id",
    ),
    expected_adjustment_draft_updated_at: requireTimestamp(
      body.expected_adjustment_draft_updated_at,
      "expected_adjustment_draft_updated_at",
    ),
    expected_preview_manifest_sha256: requireSha256(
      body.expected_preview_manifest_sha256,
      "expected_preview_manifest_sha256",
    ),
    expected_lesson_variance_manifest_sha256: requireSha256(
      body.expected_lesson_variance_manifest_sha256,
      "expected_lesson_variance_manifest_sha256",
    ),
    expected_source_count: requireNonnegativeInteger(
      body.expected_source_count,
      "expected_source_count",
    ),
    expected_unused_planned_credit_jpy: requireDecimalString(
      body.expected_unused_planned_credit_jpy,
      "expected_unused_planned_credit_jpy",
    ),
    expected_overage_charge_jpy: requireDecimalString(
      body.expected_overage_charge_jpy,
      "expected_overage_charge_jpy",
    ),
    expected_net_lesson_variance_jpy: requireDecimalString(
      body.expected_net_lesson_variance_jpy,
      "expected_net_lesson_variance_jpy",
    ),
    expected_net_lesson_variance_cny: requireDecimalString(
      body.expected_net_lesson_variance_cny,
      "expected_net_lesson_variance_cny",
    ),
    expected_system_difference_cny: requireDecimalString(
      body.expected_system_difference_cny,
      "expected_system_difference_cny",
    ),
    expected_final_carryover_cny: requireDecimalString(
      body.expected_final_carryover_cny,
      "expected_final_carryover_cny",
    ),
    note: optionalText(body.note, "note", 4000),
    confirm_lock: true,
    client_correlation_id: optionalUuid(
      body.client_correlation_id,
      "client_correlation_id",
    ),
  };
}

export type SettlementOnlineAuthContext = {
  userId: string;
  privateContext: unknown;
};

export type SettlementOnlineDependencies<TInput> = {
  createRequestId: () => string;
  nowMs: () => number;
  authenticateUser: (authorization: string) => Promise<SettlementOnlineAuthContext>;
  requireActiveAdmin: (context: SettlementOnlineAuthContext) => Promise<void>;
  invokeOnlineRpc: (actorUserId: string, input: TInput) => Promise<unknown>;
  log: (event: JsonRecord) => void;
};

export type SettlementOnlineHandlerConfig<TInput> = {
  edgeName: string;
  action: SettlementOnlineAction;
  parseBody: (value: unknown) => TInput;
  dependencies: SettlementOnlineDependencies<TInput>;
};

export async function handleSettlementOnlineRequest<TInput>(
  request: Request,
  config: SettlementOnlineHandlerConfig<TInput>,
): Promise<Response> {
  const requestId = config.dependencies.createRequestId();
  const startedAt = config.dependencies.nowMs();
  let allowedOrigin: string | null = null;
  let settlementMonth = "";

  const finish = (
    body: JsonRecord | null,
    status: number,
    code: string,
    action = "stop",
    extraHeaders: Record<string, string> = {},
  ): Response => {
    const durationMs = Math.max(0, config.dependencies.nowMs() - startedAt);
    config.dependencies.log({
      request_id: requestId,
      edge: config.edgeName,
      operation: config.action,
      settlement_month: settlementMonth,
      status,
      code,
      duration_ms: durationMs,
    });
    const headers = {
      ...buildCorsHeaders(allowedOrigin, requestId),
      ...extraHeaders,
    };
    if (body === null) {
      return new Response(null, { status, headers });
    }
    return new Response(JSON.stringify({
      ...body,
      request_id: requestId,
      ...(body.ok === false ? { action } : {}),
    }), {
      status,
      headers: {
        ...headers,
        "content-type": "application/json; charset=utf-8",
      },
    });
  };

  try {
    allowedOrigin = resolveAllowedOrigin(request.headers.get("origin"));

    if (request.method === "OPTIONS") {
      return finish(null, 204, "OPTIONS_OK");
    }
    if (request.method !== "POST") {
      return finish(
        { ok: false, code: "SETTLEMENT_EDGE_METHOD_NOT_ALLOWED", message: "仅支持POST请求。" },
        405,
        "SETTLEMENT_EDGE_METHOD_NOT_ALLOWED",
        "stop",
        { Allow: "POST, OPTIONS" },
      );
    }

    assertContentLength(request.headers.get("content-length"));
    const contentType = request.headers.get("content-type") || "";
    if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
      throw new SettlementOnlinePublicError(
        "SETTLEMENT_EDGE_JSON_CONTENT_TYPE_REQUIRED",
        "请求必须使用application/json。",
        415,
      );
    }

    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > SETTLEMENT_ONLINE_MAX_BODY_BYTES) {
      throw new SettlementOnlinePublicError(
        "SETTLEMENT_EDGE_BODY_TOO_LARGE",
        "请求内容过大。",
        413,
      );
    }

    let parsedBody: unknown;
    try {
      parsedBody = JSON.parse(rawBody);
    } catch (_error) {
      throw badRequest("SETTLEMENT_EDGE_JSON_INVALID", "请求JSON格式无效。");
    }
    const input = config.parseBody(parsedBody);
    if (isRecord(input) && typeof input.settlement_month === "string") {
      settlementMonth = input.settlement_month;
    }

    const authorization = requireBearerAuthorization(
      request.headers.get("authorization") || "",
    );
    const authContext = await config.dependencies.authenticateUser(authorization);
    await config.dependencies.requireActiveAdmin(authContext);
    const rpcResult = await config.dependencies.invokeOnlineRpc(authContext.userId, input);
    const safeResult = sanitizeOnlineResult(config.action, rpcResult);

    return finish(
      { ok: true, operation: config.action, result: safeResult },
      200,
      "OK",
    );
  } catch (error) {
    const mapped = mapSettlementOnlineError(error);
    return finish(
      { ok: false, code: mapped.code, message: mapped.message },
      mapped.status,
      mapped.code,
      mapped.action,
    );
  }
}

export function mapSettlementOnlineError(error: unknown): SettlementOnlinePublicError {
  if (error instanceof SettlementOnlinePublicError) return error;

  const record = isRecord(error) ? error : {};
  const stableCode = extractStableCode([
    record.message,
    record.details,
    record.hint,
    error,
  ]);
  const transportCode = typeof record.code === "string" ? record.code : "";

  const known = DB_ERROR_MAP[stableCode];
  if (known) {
    return new SettlementOnlinePublicError(
      stableCode,
      known.message,
      known.status,
      known.action,
    );
  }
  if (transportCode === "55P03") {
    return new SettlementOnlinePublicError(
      "SETTLEMENT_SCOPE_BUSY",
      "同一结算范围正在处理中，请稍后刷新状态。",
      423,
      "retry_later",
    );
  }

  return new SettlementOnlinePublicError(
    "SETTLEMENT_EDGE_INTERNAL_ERROR",
    "操作未完成，请稍后刷新状态。",
    500,
    "refresh_status",
  );
}

export function sanitizeOnlineResult(
  action: SettlementOnlineAction,
  value: unknown,
): JsonRecord {
  const normalized = Array.isArray(value) ? value[0] : value;
  if (!isRecord(normalized)) {
    throw new Error("ONLINE_WRAPPER_RESULT_INVALID");
  }
  const saveFields = [
    "ok", "idempotent", "operation", "request_correlation_id",
    "student_id", "year_month", "business_entity_id",
    "source_treatment_draft_id", "source_treatment_draft_updated_at",
    "adjustment_draft_id", "adjustment_draft_updated_at",
    "preview_manifest_sha256", "lesson_variance_manifest_sha256",
    "authoritative_preview", "effective_status",
  ];
  const lockFields = [
    "ok", "idempotent", "operation", "request_correlation_id",
    "settlement_id", "student_id", "year_month", "business_entity_id",
    "settlement_status", "locked_at", "system_difference_cny",
    "adjustment_amount_cny", "final_carryover_cny",
    "lesson_variance_source_count", "lesson_variance_manifest_sha256",
    "preview_manifest_sha256", "source_treatment_draft_id",
    "source_treatment_draft_updated_at", "adjustment_draft_id",
    "adjustment_draft_updated_at", "effective_status",
  ];
  const safe: JsonRecord = {};
  for (const field of action === "save" ? saveFields : lockFields) {
    if (Object.prototype.hasOwnProperty.call(normalized, field)) {
      safe[field] = normalized[field];
    }
  }
  return safe;
}

const DB_ERROR_MAP: Record<string, { status: number; message: string; action: string }> = {
  SETTLEMENT_ADMIN_REQUIRED: { status: 403, message: "当前账号没有执行该操作的管理员权限。", action: "stop" },
  SETTLEMENT_TRUSTED_EDGE_ROLE_REQUIRED: { status: 403, message: "受信服务权限验证失败。", action: "stop" },
  SETTLEMENT_INPUT_INVALID: { status: 422, message: "结算请求参数无效。", action: "repreview" },
  SETTLEMENT_SCOPE_NOT_UNIQUE: { status: 409, message: "结算范围无法唯一确认。", action: "stop" },
  SETTLEMENT_NOT_INCOMPLETE: { status: 409, message: "该结算范围当前不能进入普通在线结算。", action: "refresh_status" },
  SETTLEMENT_ORDINARY_ALREADY_LOCKED: { status: 409, message: "该学生月份已经正式锁定。", action: "refresh_status" },
  SETTLEMENT_HISTORICALLY_CONSUMED: { status: 409, message: "该学生月份已被历史学费事实消费，只能只读查看。", action: "stop" },
  SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE: { status: 409, message: "该学生月份已有历史零结转完成证据，只能只读查看。", action: "stop" },
  SETTLEMENT_SUCCESSOR_REVISION_BLOCKED: { status: 409, message: "该月份已被后继学费版本冻结。", action: "stop" },
  SETTLEMENT_IMMUTABLE_CONSUMPTION_BLOCKED: { status: 409, message: "该月份已被不可变财务事实消费。", action: "stop" },
  SETTLEMENT_WAGE_BLOCKED: { status: 409, message: "该月份已进入老师工资不可变链。", action: "stop" },
  SETTLEMENT_MONTH_NOT_CLOSED: { status: 409, message: "当前月份尚未结束，仅可预览，不能保存或锁定。", action: "stop" },
  SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED: { status: 409, message: "未来月份仅可预览，不能保存或锁定。", action: "stop" },
  SETTLEMENT_MONTH_INVALID: { status: 422, message: "结算月份格式无效。", action: "repreview" },
  SETTLEMENT_PREVIEW_MANIFEST_STALE: { status: 409, message: "结算预览已变化，请重新预览。", action: "repreview" },
  SETTLEMENT_LESSON_MANIFEST_STALE: { status: 409, message: "课时事实已变化，请重新预览。", action: "repreview" },
  SETTLEMENT_EXPECTED_FACTS_MISMATCH: { status: 409, message: "结算权威金额已变化，请重新预览。", action: "repreview" },
  SETTLEMENT_SOURCE_DRAFT_STALE: { status: 409, message: "课时差额草稿版本已变化，请刷新状态。", action: "refresh_status" },
  SETTLEMENT_ADJUSTMENT_DRAFT_STALE: { status: 409, message: "差额调整草稿版本已变化，请刷新状态。", action: "refresh_status" },
  SETTLEMENT_SCOPE_BUSY: { status: 423, message: "同一结算范围正在处理中，请稍后刷新状态。", action: "retry_later" },
  SETTLEMENT_LOCK_CONFLICT: { status: 409, message: "现有正式结算与本次请求不一致。", action: "refresh_status" },
};

function requireRecord(value: unknown): JsonRecord {
  if (!isRecord(value)) {
    throw badRequest("SETTLEMENT_EDGE_BODY_INVALID", "请求body必须为JSON对象。");
  }
  return value;
}

function requireExactFields(
  body: JsonRecord,
  allowed: Set<string>,
  required: string[],
): void {
  const unknown = Object.keys(body).filter((field) => !allowed.has(field));
  if (unknown.length) {
    throw badRequest(
      "SETTLEMENT_EDGE_UNKNOWN_FIELD",
      `请求包含未声明字段：${unknown.sort().join(", ")}`,
    );
  }
  const missing = required.filter((field) => !Object.prototype.hasOwnProperty.call(body, field));
  if (missing.length) {
    throw badRequest(
      "SETTLEMENT_EDGE_REQUIRED_FIELD_MISSING",
      `请求缺少字段：${missing.sort().join(", ")}`,
    );
  }
}

function requireBearerAuthorization(value: string): string {
  if (!/^Bearer\s+\S+$/i.test(value) || value.length > 16384) {
    throw new SettlementOnlinePublicError(
      "SETTLEMENT_EDGE_AUTH_REQUIRED",
      "登录状态无效或已过期，请重新登录。",
      401,
      "reauthenticate",
    );
  }
  return value;
}

function assertContentLength(value: string | null): void {
  if (!value) return;
  if (!/^[0-9]+$/.test(value)) {
    throw badRequest("SETTLEMENT_EDGE_CONTENT_LENGTH_INVALID", "Content-Length无效。");
  }
  if (Number(value) > SETTLEMENT_ONLINE_MAX_BODY_BYTES) {
    throw new SettlementOnlinePublicError(
      "SETTLEMENT_EDGE_BODY_TOO_LARGE",
      "请求内容过大。",
      413,
    );
  }
}

function requireUuid(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value : "";
  if (!UUID_PATTERN.test(text)) {
    throw fieldError(fieldName, "必须为UUID");
  }
  return text.toLowerCase();
}

function optionalUuid(value: unknown, fieldName: string): string | null {
  if (value === null || value === undefined) return null;
  return requireUuid(value, fieldName);
}

function requireMonth(value: unknown): string {
  const text = typeof value === "string" ? value : "";
  if (!MONTH_PATTERN.test(text)) {
    throw fieldError("settlement_month", "必须为YYYY-MM");
  }
  return text;
}

function requireDate(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value : "";
  if (!DATE_PATTERN.test(text) || !isExactDate(text)) {
    throw fieldError(fieldName, "必须为有效的YYYY-MM-DD");
  }
  return text;
}

function optionalDate(value: unknown, fieldName: string): string | null {
  if (value === null || value === undefined) return null;
  return requireDate(value, fieldName);
}

function requireTimestamp(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value : "";
  if (!TIMESTAMP_PATTERN.test(text) || Number.isNaN(Date.parse(text))) {
    throw fieldError(fieldName, "必须为带时区的ISO时间戳");
  }
  return text;
}

function optionalTimestamp(value: unknown, fieldName: string): string | null {
  if (value === null || value === undefined) return null;
  return requireTimestamp(value, fieldName);
}

function requireSha256(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value : "";
  if (!SHA256_PATTERN.test(text)) {
    throw fieldError(fieldName, "必须为SHA-256十六进制字符串");
  }
  return text.toLowerCase();
}

function requireDecimalString(value: unknown, fieldName: string): string {
  const text = typeof value === "string" ? value : "";
  if (text.length > 80 || !DECIMAL_PATTERN.test(text)) {
    throw fieldError(fieldName, "必须为十进制定点字符串");
  }
  return text;
}

function optionalDecimalString(
  value: unknown,
  fieldName: string,
  positive: boolean,
): string | null {
  if (value === null || value === undefined) return null;
  const text = requireDecimalString(value, fieldName);
  if (positive && !POSITIVE_DECIMAL_PATTERN.test(text)) {
    throw fieldError(fieldName, "必须为正十进制定点字符串");
  }
  return text;
}

function requireNonnegativeInteger(value: unknown, fieldName: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw fieldError(fieldName, "必须为非负整数");
  }
  return value;
}

function requireEnum(value: unknown, fieldName: string, allowed: Set<string>): string {
  if (typeof value !== "string" || !allowed.has(value)) {
    throw fieldError(fieldName, "值不受支持");
  }
  return value;
}

function requireText(value: unknown, fieldName: string, maxLength: number): string {
  if (typeof value !== "string") throw fieldError(fieldName, "必须为文本");
  const text = value.trim();
  if (!text || text.length > maxLength) {
    throw fieldError(fieldName, `必须为1-${maxLength}字符`);
  }
  return text;
}

function optionalText(value: unknown, fieldName: string, maxLength: number): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") throw fieldError(fieldName, "必须为文本或null");
  const text = value.trim();
  if (!text) return null;
  if (text.length > maxLength) throw fieldError(fieldName, `不能超过${maxLength}字符`);
  return text;
}

function isExactDate(text: string): boolean {
  const [year, month, day] = text.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function fieldError(fieldName: string, rule: string): SettlementOnlinePublicError {
  return badRequest(
    "SETTLEMENT_EDGE_FIELD_INVALID",
    `${fieldName}${rule}。`,
  );
}

function badRequest(code: string, message: string): SettlementOnlinePublicError {
  return new SettlementOnlinePublicError(code, message, 400, "repreview");
}

function isRecord(value: unknown): value is JsonRecord {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function extractStableCode(values: unknown[]): string {
  for (const value of values) {
    if (typeof value !== "string") continue;
    const match = value.match(STABLE_CODE_PATTERN);
    if (match) return match[0];
  }
  return "";
}
