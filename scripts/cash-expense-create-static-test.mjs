import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const api = readFileSync("js/api/expense-api.js", "utf8");
const page = readFileSync("js/pages/expense-page.js", "utf8");
const html = readFileSync("expense.html", "utf8");
const config = readFileSync("js/config.js", "utf8");
const schema = readFileSync(
  "sql/current/school_pending_cash_expense_identity_schema_20260804.sql",
  "utf8",
);
const pendingWriter = readFileSync(
  "sql/current/school_create_pending_cash_expense_record_v1_rpc.sql",
  "utf8",
);
const paidWriter = readFileSync(
  "sql/current/school_create_expense_record_rpc.sql",
  "utf8",
);
const prepareWriter = readFileSync(
  "sql/current/school_expense_cash_request_backend_amount_rpc.sql",
  "utf8",
);

assert.match(api, /school_create_pending_cash_expense_record_v1/);
assert.match(api, /p_client_request_id: clientRequestId/);
assert.match(api, /p_reimbursement_status: payload\.reimbursementStatus/);
assert.match(api, /cash_creation_event_id/);
assert.match(api, /created_by_user_id/);

assert.match(page, /crypto\.randomUUID\(\)/);
assert.match(page, /createPendingCashExpenseRecord\(payload\)/);
assert.match(page, /openBatchCashExpenseDialog\(\[pendingExpense\], \{ origin: "new-cash-expense" \}\)/);
assert.match(page, /支出已保存为待提交，可稍后从支出列表提交 Cash/);
assert.match(page, /支出已保存为待支付记录，但尚未成功提交至 Cash/);
assert.match(page, /requireActiveAdminForCashConfirmation/);
assert.match(page, /\["manual_cash", "teacher_wage"\]\.includes\(row\.source_type\)/);
assert.doesNotMatch(page, /\bsupabase\s*\./);
assert.doesNotMatch(page, /\.rpc\s*\(/);

const createPayloadReader = page.match(
  /function readCreateExpensePayload\(\)[\s\S]*?\n\}\n\nfunction createExpenseHandlingMode/u,
)?.[0] ?? "";
assert.match(createPayloadReader, /currency = dom\.createExpenseCurrencySelect\.value/);
assert.match(createPayloadReader, /amount = Number\(dom\.createExpenseAmountInput\.value\)/);
assert.doesNotMatch(createPayloadReader, /amount_(?:jpy|cny)|year_month|Math\.(?:round|ceil|floor)/i);

assert.match(html, /value="school" checked/);
assert.match(html, /value="cash"/);
assert.match(html, /data-create-expense-school-only/);
assert.match(html, /data-create-expense-cash-only hidden/);
assert.match(html, /从 School 账户直接支出/);
assert.match(html, /提交至 Cash 审批/);
assert.match(config, /APP_VERSION = "v10\.5\.4"/);

assert.match(schema, /add column if not exists cash_creation_event_id uuid/);
assert.match(schema, /add column if not exists created_by_user_id uuid/);
assert.match(schema, /create unique index if not exists school_expense_records_cash_creation_event_uniq/);
assert.doesNotMatch(schema, /\b(?:update|delete|truncate|drop table|drop column)\b/i);

assert.match(pendingWriter, /school_require_current_app_admin\(\)/);
assert.match(pendingWriter, /pg_advisory_xact_lock/);
assert.match(pendingWriter, /P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT/);
assert.match(pendingWriter, /'pending'/);
assert.match(pendingWriter, /'manual_cash'/);
assert.match(pendingWriter, /null,null,null,null,[\s\S]*0,null,null/);
assert.match(paidWriter, /'manual_school'/);
assert.match(paidWriter, /created_by_user_id/);
assert.match(prepareWriter, /P0_EXPENSE_CASH_REQUEST_SOURCE_NOT_ALLOWED/);

for (const pageFile of readdirSync("js/pages").filter((file) => file.endsWith(".js"))) {
  const source = readFileSync(`js/pages/${pageFile}`, "utf8");
  assert.doesNotMatch(source, /\.rpc\s*\(/, `page-layer RPC regression: ${pageFile}`);
  assert.doesNotMatch(
    source,
    /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/,
    `page-layer table DML regression: ${pageFile}`,
  );
}

console.log("CASH_EXPENSE_CREATE_STATIC_TEST_PASS");
