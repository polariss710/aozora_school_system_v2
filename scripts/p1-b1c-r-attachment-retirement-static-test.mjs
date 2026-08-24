import assert from "node:assert/strict";
import { assertAppVersionAtLeast } from "./static-test-helpers.mjs";
import { readFileSync } from "node:fs";

const html = readFileSync("expense-detail.html", "utf8");
const page = readFileSync("js/pages/expense-detail-page.js", "utf8");
const api = readFileSync("js/api/expense-detail-api.js", "utf8");
const config = readFileSync("js/config.js", "utf8");
const migration = readFileSync(
  "sql/current/school_p1_b1c_r_attachment_write_retirement_20260810.sql",
  "utf8"
);

for (const retiredRuntimeToken of [
  "openExpenseAttachmentDialogButton",
  "expenseAttachmentDialog",
  "createExpenseAttachmentMetadata",
  "school_create_expense_attachment_metadata",
  "submitAttachmentMetadata",
  "canCreateAttachmentMetadata",
]) {
  assert(!html.includes(retiredRuntimeToken), `HTML still exposes ${retiredRuntimeToken}`);
  assert(!page.includes(retiredRuntimeToken), `page still exposes ${retiredRuntimeToken}`);
  assert(!api.includes(retiredRuntimeToken), `API still exposes ${retiredRuntimeToken}`);
}

assert(html.includes("附件新增功能已退役"), "detail must state the retirement rule");
assert(page.includes("以下仅保留 ${attachments.length} 个历史摘要"), "history summary must remain");
assert(page.includes("renderAttachments(data.attachments)"), "history reader rendering must remain");
assert(api.includes('.from("school_expense_attachments")'), "history metadata reader must remain");
assert(api.includes("fetchExpenseAttachments(expense.id)"), "detail load must retain history lookup");

for (const forbiddenStorageRuntime of [
  ".upload(",
  ".download(",
  "createSignedUrl",
  ".move(",
  ".copy(",
]) {
  assert(!html.includes(forbiddenStorageRuntime));
  assert(!page.includes(forbiddenStorageRuntime));
  assert(!api.includes(forbiddenStorageRuntime));
}

assertAppVersionAtLeast(config, "v10.5.33");
// Historical cache-key snapshots are intentionally not asserted; see the week-close handoff section 8.6.

assert(migration.includes("begin;"));
assert(migration.includes("commit;"));
assert(migration.includes("P1_B1C_R_STORAGE_OBJECT_SNAPSHOT_DRIFT"));
assert(migration.includes("P1_B1C_R_ORPHAN_CLASSIFICATION_DRIFT"));
assert(migration.includes("P1_B1C_R_METADATA_SNAPSHOT_DRIFT"));
assert(migration.includes("school_expense_files_write_retired_guard"));
assert(migration.includes("current_user in ('anon','authenticated','service_role')"));
assert(migration.includes("v_request_role in ('anon','authenticated','service_role')"));
assert(migration.includes("drop policy school_allow_all_storage_expense_files_insert"));
assert(migration.includes("drop policy school_allow_all_storage_expense_files_update"));
assert(migration.includes("drop policy school_allow_all_storage_expense_files_delete"));
assert(migration.includes("drop policy school_allow_all_expense_attachments"));
assert(migration.includes("from public,anon,authenticated,service_role"));

for (const forbiddenDataMutation of [
  /insert\s+into\s+storage\.objects/i,
  /update\s+storage\.objects/i,
  /delete\s+from\s+storage\.objects/i,
  /insert\s+into\s+public\.school_expense_attachments/i,
  /update\s+public\.school_expense_attachments/i,
  /delete\s+from\s+public\.school_expense_attachments/i,
]) {
  assert(!forbiddenDataMutation.test(migration), `migration contains data mutation ${forbiddenDataMutation}`);
}

console.log("P1_B1C_R_ATTACHMENT_RETIREMENT_STATIC_PASS");
