import assert from "node:assert/strict";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const helperSql = join(
  root,
  "sql/current/school_expense_cash_attempt_v2_fingerprint_helper_20260819.sql",
);
const resolverSql = join(
  root,
  "sql/current/school_expense_cash_historical_fingerprint_resolver_v1_20260820.sql",
);
const tempRoot = mkdtempSync(join(tmpdir(), "school-cash-p0-resolver-"));
const dataDir = join(tempRoot, "data");
const socketDir = join(tempRoot, "socket");
const port = String(56000 + (process.pid % 800));
let serverStarted = false;

function run(file, args, options = {}) {
  return execFileSync(file, args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });
}

function psql(sql) {
  return run("psql", [
    "-X",
    "-v",
    "ON_ERROR_STOP=1",
    "-h",
    socketDir,
    "-p",
    port,
    "-d",
    "postgres",
    "-At",
    "-F",
    "|",
    "-c",
    sql,
  ]).trim();
}

function psqlFile(file) {
  return run("psql", [
    "-X",
    "-v",
    "ON_ERROR_STOP=1",
    "-h",
    socketDir,
    "-p",
    port,
    "-d",
    "postgres",
    "-f",
    file,
  ]);
}

function uuid(n) {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

const uuidFields = new Set([
  "p_expense_record_id",
  "p_cash_request_id",
  "p_home_request_user_id",
  "p_request_event_id",
  "p_external_reference_id",
  "p_cash_account_id",
  "p_cash_transaction_id",
  "p_home_transaction_id",
  "p_home_transaction_user_id",
  "p_home_transaction_account_id",
  "p_home_transaction_event_id",
  "p_home_transaction_reference_id",
]);
const dateFields = new Set(["p_charge_date", "p_home_transaction_date"]);

function literal(field, value) {
  if (value === null) return "null";
  if (uuidFields.has(field)) return `'${value}'::uuid`;
  if (dateFields.has(field)) return `'${value}'::date`;
  if (typeof value === "number") return String(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  return `'${String(value).replaceAll("'", "''")}'`;
}

function resolverCall(args, role = null) {
  const namedArgs = Object.entries(args)
    .map(([field, value]) => `${field} => ${literal(field, value)}`)
    .join(",\n");
  const query = `select * from public.school_resolve_historical_expense_cash_attempt_fingerprint_v1(\n${namedArgs}\n);`;
  return psql(role ? `set role ${role}; ${query}` : query);
}

function expectFailure(label, args, expectedCode) {
  let failure = null;
  try {
    resolverCall(args);
  } catch (error) {
    failure = `${error.stderr ?? ""}\n${error.stdout ?? ""}\n${error.message ?? ""}`;
  }
  assert.ok(failure, `${label} must fail`);
  assert.match(failure, new RegExp(expectedCode), label);
}

function createFixture(index, shape, options = {}) {
  const expenseId = uuid(index * 10 + 1);
  const attemptId = uuid(index * 10 + 2);
  const requestId = uuid(index * 10 + 3);
  const eventId = uuid(index * 10 + 4);
  const accountId = uuid(index * 10 + 5);
  const userId = uuid(index * 10 + 6);
  const transactionId = uuid(index * 10 + 7);
  const paymentCurrency = options.paymentCurrency ?? "CNY";
  const paymentAmount = options.paymentAmount ?? (paymentCurrency === "JPY" ? 31500 : 1330);
  const originalCurrency = "JPY";
  const originalAmount = 31500;
  const idempotency = `aozora_school:school_expense_records:${expenseId}:expense_paid:attempt:1`;
  const chargeDate = "2026-08-20";
  const terminalApproved = shape.includes("approved");
  const terminalRejected = shape.includes("rejected");
  const submitted = shape.includes("submitted") || terminalApproved || terminalRejected;
  const version = Number(shape.match(/v(\d)$/)?.[1] ?? 1);
  const callbackRecovered = shape === "native_recovered_approved_v3";
  const attemptStatus = terminalApproved
    ? "approved_immediate"
    : terminalRejected
    ? "rejected"
    : shape.startsWith("prepared")
    ? "prepared"
    : "submitted";
  const expenseStatus = terminalApproved ? "paid" : "pending";
  const mirrorStatus = terminalApproved
    ? "approved"
    : terminalRejected
    ? "rejected"
    : shape.startsWith("prepared")
    ? "pending_cash_request"
    : "pending";
  const storedRequestId = shape.startsWith("prepared") ? null : requestId;
  const storedTransactionId = terminalApproved ? transactionId : null;
  const syncedAt = terminalApproved || terminalRejected
    ? "2026-08-20T01:02:03+00"
    : null;

  psql(`
    insert into public.school_expense_records(
      id, app_type, status, cash_request_id, cash_request_status,
      cash_transaction_id, cash_synced_at, cash_request_event_id,
      cash_request_attempt_no, cash_payment_amount, cash_payment_currency
    ) values (
      '${expenseId}', 'school', '${expenseStatus}',
      ${storedRequestId ? `'${storedRequestId}'` : "null"}, '${mirrorStatus}',
      ${storedTransactionId ? `'${storedTransactionId}'` : "null"},
      ${syncedAt ? `'${syncedAt}'::timestamptz` : "null"},
      '${eventId}', 1, ${paymentAmount}, '${paymentCurrency}'
    );
    insert into public.school_expense_cash_attempts(
      id, expense_id, attempt_no, request_type, payment_route,
      request_event_id, idempotency_key, original_amount, original_currency,
      payment_amount, payment_currency, cash_funding_account_id, charge_date,
      cash_request_id, submitted_at, attempt_status, version,
      cash_transaction_id, approved_at, rejected_at,
      callback_recovered_from_prepared, callback_recovered_at,
      callback_recovery_source, request_payload_fingerprint
    ) values (
      '${attemptId}', '${expenseId}', 1, 'expense_paid', 'immediate_account',
      '${eventId}', '${idempotency}', ${originalAmount}, '${originalCurrency}',
      ${paymentAmount}, '${paymentCurrency}', '${accountId}', '${chargeDate}',
      ${storedRequestId ? `'${storedRequestId}'` : "null"},
      ${submitted ? "'2026-08-18T00:00:00+00'::timestamptz" : "null"},
      '${attemptStatus}', ${version},
      ${storedTransactionId ? `'${storedTransactionId}'` : "null"},
      ${terminalApproved ? "'2026-08-20T01:02:03+00'::timestamptz" : "null"},
      ${terminalRejected ? "'2026-08-20T01:02:03+00'::timestamptz" : "null"},
      ${callbackRecovered},
      ${callbackRecovered ? "'2026-08-20T01:02:03+00'::timestamptz" : "null"},
      ${callbackRecovered ? "'sync-cash-request-result-v2'" : "null"},
      public.school_expense_cash_attempt_payload_fingerprint_v2(
        '${expenseId}', 1, 'expense_paid', 'immediate_account', '${eventId}',
        '${idempotency}', ${originalAmount}, '${originalCurrency}',
        ${paymentAmount}, '${paymentCurrency}', '${accountId}', '${chargeDate}'
      )
    );
  `);

  const approved = options.homeStatus
    ? options.homeStatus === "approved"
    : !terminalRejected;
  const homeStatus = options.homeStatus ?? (terminalRejected ? "rejected" : "approved");
  const transaction = homeStatus === "approved";
  const args = {
    p_expense_record_id: expenseId,
    p_cash_request_id: requestId,
    p_home_request_user_id: userId,
    p_home_request_status: homeStatus,
    p_home_approved_at: homeStatus === "approved" ? "2026-08-20T01:02:03+00" : null,
    p_home_rejected_at: homeStatus === "rejected" ? "2026-08-20T01:02:03+00" : null,
    p_external_source: "aozora_school",
    p_request_event_id: eventId,
    p_idempotency_key: idempotency,
    p_external_reference_type: "school_expense_records",
    p_external_reference_id: expenseId,
    p_request_type: "expense_paid",
    p_transaction_type: "expense",
    p_payment_route: "immediate_account",
    p_attempt_no: 1,
    p_original_amount: originalAmount,
    p_original_currency: originalCurrency,
    p_payment_amount: paymentAmount,
    p_payment_currency: paymentCurrency,
    p_cash_account_id: accountId,
    p_charge_date: chargeDate,
    p_cash_transaction_id: transaction ? transactionId : null,
    p_home_transaction_id: transaction ? transactionId : null,
    p_home_transaction_user_id: transaction ? userId : null,
    p_home_transaction_type: transaction ? "expense" : null,
    p_home_transaction_amount: transaction ? paymentAmount : null,
    p_home_transaction_currency: transaction ? paymentCurrency : null,
    p_home_transaction_account_id: transaction ? accountId : null,
    p_home_transaction_date: transaction ? chargeDate : null,
    p_home_transaction_scope: transaction ? "school" : null,
    p_home_transaction_external_source: transaction ? "aozora_school" : null,
    p_home_transaction_event_id: transaction ? eventId : null,
    p_home_transaction_event_type: transaction ? "expense_paid" : null,
    p_home_transaction_reference_type: transaction ? "school_expense_records" : null,
    p_home_transaction_reference_id: transaction ? expenseId : null,
    p_home_transaction_idempotency_key: transaction ? idempotency : null,
    p_home_transaction_created_by_external: transaction ? true : null,
  };
  return {
    args,
    expenseId,
    attemptId,
    requestId,
    eventId,
    accountId,
    transactionId,
    approved,
  };
}

try {
  mkdirSync(socketDir);
  run("initdb", ["-D", dataDir, "-A", "trust", "--no-locale", "-E", "UTF8"]);
  run("pg_ctl", [
    "-D",
    dataDir,
    "-l",
    join(tempRoot, "postgres.log"),
    "-o",
    `-F -k ${socketDir} -p ${port}`,
    "-w",
    "start",
  ]);
  serverStarted = true;

  psql(`
    create role postgres superuser;
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema extensions;
    create extension pgcrypto with schema extensions;
  `);
  psqlFile(helperSql);
  psql(`
    create table public.school_expense_records (
      id uuid primary key,
      app_type text not null,
      status text not null,
      cash_request_id uuid,
      cash_request_status text,
      cash_transaction_id uuid,
      cash_synced_at timestamptz,
      cash_request_event_id uuid,
      cash_request_attempt_no integer,
      cash_payment_amount numeric,
      cash_payment_currency text
    );
    create table public.school_expense_cash_attempts (
      id uuid primary key,
      expense_id uuid not null,
      attempt_no integer not null,
      request_type text not null,
      payment_route text not null,
      request_event_id uuid not null,
      idempotency_key text not null,
      original_amount numeric not null,
      original_currency text not null,
      payment_amount numeric not null,
      payment_currency text not null,
      cash_funding_account_id uuid not null,
      charge_date date not null,
      cash_request_id uuid,
      submitted_at timestamptz,
      attempt_status text not null,
      version integer not null,
      cash_transaction_id uuid,
      approved_at timestamptz,
      rejected_at timestamptz,
      callback_recovered_from_prepared boolean not null default false,
      callback_recovered_at timestamptz,
      callback_recovery_source text,
      request_payload_fingerprint text
    );
  `);
  psqlFile(resolverSql);

  const submittedCny = createFixture(10, "submitted_v1");
  assert.match(resolverCall(submittedCny.args), /phase3c2r_submitted_v1/);
  const submittedJpy = createFixture(20, "submitted_v1", {
    paymentCurrency: "JPY",
    paymentAmount: 31500,
  });
  assert.match(resolverCall(submittedJpy.args), /phase3c2r_submitted_v1/);

  const rejectedSubmitted = createFixture(30, "submitted_v1", {
    homeStatus: "rejected",
  });
  assert.match(resolverCall(rejectedSubmitted.args), /phase3c2r_submitted_v1/);

  const approvedV1 = createFixture(40, "approved_v1");
  assert.match(resolverCall(approvedV1.args), /phase3c2r_backfilled_approved_v1/);
  const rejectedV1 = createFixture(50, "rejected_v1");
  assert.match(resolverCall(rejectedV1.args), /phase3c2r_backfilled_rejected_v1/);
  const approvedV2 = createFixture(60, "approved_v2");
  assert.match(resolverCall(approvedV2.args), /phase3c2r_compat_recovered_approved_v2/);
  const rejectedV2 = createFixture(70, "rejected_v2");
  assert.match(resolverCall(rejectedV2.args), /phase3c2r_compat_recovered_rejected_v2/);

  expectFailure(
    "approved terminal conflicting action",
    {
      ...approvedV1.args,
      p_home_request_status: "rejected",
      p_home_approved_at: null,
      p_home_rejected_at: "2026-08-20T01:02:03+00",
      ...Object.fromEntries(
      Object.keys(approvedV1.args)
        .filter((key) => key.startsWith("p_home_transaction_") || key === "p_cash_transaction_id")
        .map((key) => [key, null]),
      ),
    },
    "TERMINAL_CONFLICT",
  );
  expectFailure(
    "rejected terminal conflicting action",
    {
      ...rejectedV1.args,
      p_home_request_status: "approved",
      p_home_approved_at: "2026-08-20T01:02:03+00",
      p_home_rejected_at: null,
      p_cash_transaction_id: uuid(9991),
      p_home_transaction_id: uuid(9991),
      p_home_transaction_user_id: rejectedV1.args.p_home_request_user_id,
      p_home_transaction_type: "expense",
      p_home_transaction_amount: rejectedV1.args.p_payment_amount,
      p_home_transaction_currency: rejectedV1.args.p_payment_currency,
      p_home_transaction_account_id: rejectedV1.args.p_cash_account_id,
      p_home_transaction_date: rejectedV1.args.p_charge_date,
      p_home_transaction_scope: "school",
      p_home_transaction_external_source: "aozora_school",
      p_home_transaction_event_id: rejectedV1.args.p_request_event_id,
      p_home_transaction_event_type: "expense_paid",
      p_home_transaction_reference_type: "school_expense_records",
      p_home_transaction_reference_id: rejectedV1.args.p_expense_record_id,
      p_home_transaction_idempotency_key: rejectedV1.args.p_idempotency_key,
      p_home_transaction_created_by_external: true,
    },
    "TERMINAL_CONFLICT",
  );

  const nativeSubmittedV2 = createFixture(80, "submitted_v2");
  expectFailure(
    "native submitted v2",
    nativeSubmittedV2.args,
    "HISTORICAL_FALLBACK_NOT_ELIGIBLE",
  );
  const nativeApprovedV3 = createFixture(90, "approved_v3");
  expectFailure(
    "native approved v3",
    nativeApprovedV3.args,
    "HISTORICAL_FALLBACK_NOT_ELIGIBLE",
  );
  const nativeRecoveredV3 = createFixture(100, "native_recovered_approved_v3");
  expectFailure(
    "native recovered terminal",
    nativeRecoveredV3.args,
    "HISTORICAL_FALLBACK_NOT_ELIGIBLE",
  );

  const negativeCases = [
    ["expense ID", "p_expense_record_id", uuid(9001), "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["attempt no", "p_attempt_no", 2, "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["event", "p_request_event_id", uuid(9002), "SCHOOL_EXPENSE_CASH_ATTEMPT_NOT_FOUND"],
    ["request ID", "p_cash_request_id", uuid(9003), "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["idempotency", "p_idempotency_key", "wrong-idempotency", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["route", "p_payment_route", "fixed_credit_card", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["request type", "p_request_type", "income_received", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["transaction type", "p_transaction_type", "income", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["external source", "p_external_source", "wrong_source", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["approved timestamp", "p_home_approved_at", null, "ACTION_STATUS_CONFLICT"],
    ["original amount", "p_original_amount", 31501, "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["original currency", "p_original_currency", "CNY", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["settlement amount", "p_payment_amount", 1331, "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["settlement currency", "p_payment_currency", "JPY", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["account", "p_cash_account_id", uuid(9004), "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["charge date", "p_charge_date", "2026-08-21", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["reference table", "p_external_reference_type", "wrong_table", "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["reference ID", "p_external_reference_id", uuid(9005), "HOME_REQUEST_EVIDENCE_CONFLICT"],
    ["transaction ID", "p_home_transaction_id", uuid(9006), "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction amount", "p_home_transaction_amount", 1331, "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction currency", "p_home_transaction_currency", "JPY", "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction account", "p_home_transaction_account_id", uuid(9007), "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction date", "p_home_transaction_date", "2026-08-21", "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction scope", "p_home_transaction_scope", "household", "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction event", "p_home_transaction_event_id", uuid(9008), "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction event type", "p_home_transaction_event_type", "wrong_event", "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction idempotency", "p_home_transaction_idempotency_key", "wrong-idem", "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction reference", "p_home_transaction_reference_id", uuid(9009), "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction user", "p_home_transaction_user_id", uuid(9010), "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
    ["transaction external flag", "p_home_transaction_created_by_external", false, "HOME_TRANSACTION_EVIDENCE_CONFLICT"],
  ];
  for (const [label, field, value, code] of negativeCases) {
    expectFailure(label, { ...submittedCny.args, [field]: value }, code);
  }

  psql(`update public.school_expense_cash_attempts set version = 2 where id='${submittedCny.attemptId}'`);
  expectFailure("status/version", submittedCny.args, "HISTORICAL_FALLBACK_NOT_ELIGIBLE");
  psql(`update public.school_expense_cash_attempts set version = 1 where id='${submittedCny.attemptId}'`);

  psql(`update public.school_expense_cash_attempts set request_payload_fingerprint = repeat('0',64) where id='${submittedCny.attemptId}'`);
  expectFailure("recomputed fingerprint", submittedCny.args, "FINGERPRINT_RECOMPUTE_CONFLICT");

  const ambiguous = createFixture(110, "submitted_v1");
  psql(`
    insert into public.school_expense_cash_attempts
    select '${uuid(1199)}'::uuid, expense_id, attempt_no, request_type, payment_route,
      request_event_id, idempotency_key, original_amount, original_currency,
      payment_amount, payment_currency, cash_funding_account_id, charge_date,
      cash_request_id, submitted_at, attempt_status, version, cash_transaction_id,
      approved_at, rejected_at, callback_recovered_from_prepared,
      callback_recovered_at, callback_recovery_source, request_payload_fingerprint
    from public.school_expense_cash_attempts where id='${ambiguous.attemptId}'
  `);
  expectFailure(
    "attempt identity ambiguity",
    ambiguous.args,
    "SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_AMBIGUOUS",
  );

  const acl = psql(`
    select proname, pg_get_userbyid(proowner), prosecdef, provolatile,
           coalesce(array_to_string(proconfig, ','), ''),
           has_function_privilege('service_role', oid, 'execute'),
           has_function_privilege('anon', oid, 'execute'),
           has_function_privilege('authenticated', oid, 'execute'),
           has_function_privilege('public', oid, 'execute')
    from pg_proc
    where proname in (
      'school_resolve_historical_expense_cash_attempt_fp_v1_core',
      'school_resolve_historical_expense_cash_attempt_fingerprint_v1'
    )
    order by proname;
  `).split("\n");
  assert.equal(acl.length, 2);
  for (const row of acl) {
    const [name, owner, definer, volatility, config, service, anon, authenticated, publicRole] = row.split("|");
    assert.equal(owner, "postgres", name);
    assert.equal(definer, "t", name);
    assert.equal(volatility, "s", name);
    assert.match(config, /search_path=pg_catalog, public/);
    assert.equal(anon, "f", name);
    assert.equal(authenticated, "f", name);
    assert.equal(publicRole, "f", name);
    assert.equal(service, name.endsWith("_core") ? "f" : "t", name);
  }

  assert.match(resolverCall(approvedV1.args, "service_role"), /phase3c2r_backfilled_approved_v1/);
  let coreDenied = null;
  try {
    psql(`set role service_role; select * from public.school_resolve_historical_expense_cash_attempt_fp_v1_core(
      ${Object.entries(approvedV1.args).map(([field, value]) => `${field} => ${literal(field, value)}`).join(",")}
    );`);
  } catch (error) {
    coreDenied = `${error.stderr ?? ""}`;
  }
  assert.match(coreDenied ?? "", /permission denied for function/);

  const resolverSource = readFileSync(resolverSql, "utf8");
  assert.doesNotMatch(resolverSource, /\b(insert|update|delete|merge|truncate)\b/i);
  assert.doesNotMatch(resolverSource, /teacher_wage|payee|description|created_at\s*[<>=]/i);
  assert.doesNotMatch(resolverSource, /aec4eb6d|aa0f9e43/i);

  console.log("P0_HISTORICAL_RESOLVER_LOCAL_POSTGRES_TEST_PASS");
} finally {
  if (serverStarted) {
    try {
      run("pg_ctl", ["-D", dataDir, "-m", "fast", "-w", "stop"]);
    } catch {
      // The temporary cluster is removed below even if stop reports a stale PID.
    }
  }
  rmSync(tempRoot, { recursive: true, force: true });
}
