import fs from "node:fs";
import assert from "node:assert/strict";

const migration = fs.readFileSync("sql/current/school_tuition_p0e_forward_adjustment_20260803.sql", "utf8");
const schema = fs.readFileSync("sql/current/school_tuition_p0e_forward_adjustment_schema_20260803.sql", "utf8");
const tool = fs.readFileSync("scripts/manage-atomic-tuition.zsh", "utf8");
const api = fs.readFileSync("js/api/settlement-api.js", "utf8");
const detailApi = fs.readFileSync("js/api/settlement-detail-api.js", "utf8");
const page = fs.readFileSync("js/pages/settlement-page.js", "utf8");
const detailPage = fs.readFileSync("js/pages/settlement-detail-page.js", "utf8");
const html = fs.readFileSync("settlement.html", "utf8");
const detailHtml = fs.readFileSync("settlement-detail.html", "utf8");

assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(detailPage, /\.rpc\s*\(/);
assert.doesNotMatch(page, /Math\.round|system_difference_cny\s*[+*-]/);
assert.doesNotMatch(detailPage, /Math\.round|system_difference_cny\s*[+*-]/);
assert.match(api, /school_get_student_monthly_settlement_effective_states/);
assert.match(detailApi, /school_get_student_monthly_settlement_effective_states/);
assert.match(api, /row\.settlement_status !== "unlocked" \|\| row\.editable === false/);
assert.match(page, /historically_consumed_immutable/);
assert.match(detailPage, /historically_consumed_immutable/);
assert.match(page, /canUseOnlineDraftSave\(membershipRole, row\.online_status\)/);
assert.match(page, /canUseOnlineDraftPreview\(membershipRole, row\.online_status\)/);
assert.match(page, /canUseOnlineDraftSave\(membershipRole, currentOnlineStatus\)/);
assert.match(detailPage, /settlement\.editable === false/);
const hideAdjustmentErrorIfCleanBlock = page.match(
  /function hideAdjustmentErrorIfClean\(\) \{[\s\S]*?\n\}/
)?.[0] || "";
assert.match(hideAdjustmentErrorIfCleanBlock, /if \(!dom\.adjustmentDialog\?\.querySelector\("\.field\.is-invalid"\)\) \{/);
assert.match(hideAdjustmentErrorIfCleanBlock, /dom\.adjustmentError\.classList\.add\("is-hidden"\)/);
const adjustmentModeChangeBlock = page.match(
  /dom\.adjustmentSourceInput\?\.addEventListener\("change", \(\) => \{[\s\S]*?\n  \}\);/
)?.[0] || "";
assert.match(adjustmentModeChangeBlock, /applyAdjustmentMode\(\)[\s\S]*invalidateAdjustmentPreview\(\)/);
assert.doesNotMatch(api, /school_set_student_monthly_settlement_draft_adjustment/);
// Historical cache-key literals are intentionally not asserted; resource references remain covered (handoff section 8.6).
assert.match(html, /settlement-app\.js/);
assert.match(detailHtml, /settlement-detail-app\.js/);

assert.match(schema, /school_student_tuition_generation_revision_adjustments/);
assert.match(schema, /adjustment_type='neutralize_historical_carryover_v1'/);
assert.match(migration, /v_adjustment:=case when v_type is null then 0 else -round\(v_previous_bill\.previous_carryover_cny,2\) end/);
assert.match(migration, /v_final:=round\(v_exchange\+v_previous_bill\.previous_carryover_cny\+v_adjustment,2\)/);
assert.match(migration, /school_validate_tuition_generation_revision_adjustment_for_bill/);
assert.match(migration, /TUITION_P0E_FORWARD_ADJUSTMENT_REQUIRED/);
assert.match(migration, /historically_consumed_immutable/);

for (const flag of [
  "--forward-adjustment-mode",
  "--expected-source-settlement-id",
  "--expected-source-revision-id",
  "--expected-historical-carryover-cny",
  "--expected-forward-adjustment-cny",
  "--adjustment-line-manifest",
  "--reason",
]) {
  assert.ok(tool.includes(flag), `management tool missing ${flag}`);
}
assert.match(tool, /school_get_atomic_tuition_reissue_preview_p0e/);
assert.match(tool, /school_build_student_tuition_generation_snapshot/);
assert.match(tool, /if \[\[ -z "\$DB_ADJUSTMENT_TYPE" \]\]/);
assert.match(tool, /school_reissue_atomic_student_tuition_generation_p0e_local/);
assert.doesNotMatch(tool, /CASH_SUPABASE_DB_URL|load_cash_db/);
assert.doesNotMatch(tool, /insert into|update public|delete from|truncate|drop table/i);

console.log("P0-E DB authority, tool and settlement effective-state static checks passed");
