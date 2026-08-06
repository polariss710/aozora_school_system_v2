import { supabase } from "../supabase-client.js";

export async function fetchProfitSummaryPageData(filters) {
  const month = String(filters?.month || "").trim();
  const { data, error } = await supabase.rpc("school_get_profit_summary_schoolwide_v1", {
    p_start_month: month,
    p_end_month: month,
  });

  if (error) {
    throw error;
  }

  return normalizeProfitSummary(data);
}

function normalizeProfitSummary(data) {
  const result = data && typeof data === "object" ? data : {};
  return {
    startMonth: String(result.start_month || ""),
    endMonth: String(result.end_month || ""),
    summaryRows: Array.isArray(result.summary_rows) ? result.summary_rows : [],
    auditRows: Array.isArray(result.audit_rows) ? result.audit_rows : [],
    incomeRecords: Array.isArray(result.income_records) ? result.income_records : [],
    expenseRecords: Array.isArray(result.expense_records) ? result.expense_records : [],
  };
}
