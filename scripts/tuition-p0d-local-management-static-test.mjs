import fs from "node:fs";

const tool = fs.readFileSync(new URL("./manage-atomic-tuition.zsh", import.meta.url), "utf8");
const api = fs.readFileSync(new URL("../js/api/income-detail-api.js", import.meta.url), "utf8");
const page = fs.readFileSync(new URL("../js/pages/income-detail-page.js", import.meta.url), "utf8");
const edge = fs.readFileSync(new URL("../supabase/functions/void-atomic-tuition-generation/index.ts", import.meta.url), "utf8");

const assertions = [
  [!tool.includes("eval "), "tool must not use eval"],
  [!/(CASH_SUPABASE_DB_URL|load_cash_db|home_(cny|jpy)_transactions)/.test(tool), "tool must not connect Cash DB"],
  [!/(insert into|update public|delete from|truncate|drop table)/i.test(tool), "tool must not directly DML business tables"],
  [tool.includes("local_trusted_business_owner_v1"), "fixed operator authority missing"],
  [tool.includes("DRY-RUN") && tool.includes("--execute"), "dry-run/execute contract missing"],
  [tool.includes("VOID ATOMIC TUITION") && tool.includes("REISSUE ATOMIC TUITION"), "exact confirmations missing"],
  [tool.includes("school_reissue_atomic_student_tuition_generation_local"), "formal Reissue RPC missing"],
  [!api.includes("school_get_atomic_tuition_void_preflight"), "V2 API still calls protected Void preflight"],
  [!page.includes("voidAtomicTuitionGeneration"), "V2 page still exposes Atomic Void invocation"],
  [page.includes("Atomic学费账单的作废与重新生成需要通过本机受信管理工具执行。"), "V2 notice missing"],
  [edge.includes("preflight_only") && edge.includes("school_void_atomic_student_tuition_generation_local"), "Edge local preflight/authority bridge missing"],
];
for (const [ok, message] of assertions) {
  if (!ok) throw new Error(message);
}
console.log(`P0-D local management static checks passed (${assertions.length}/${assertions.length}).`);
