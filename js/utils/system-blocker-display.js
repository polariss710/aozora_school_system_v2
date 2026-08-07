function nonNegativeInteger(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : 0;
}

function countSummary(counts = {}) {
  const parts = [];
  const activeWageLockCount = nonNegativeInteger(counts.activeWageLockCount);
  const wageDetailCount = nonNegativeInteger(counts.wageDetailCount);
  const paymentRequestCount = nonNegativeInteger(counts.paymentRequestCount);
  const expenseCount = nonNegativeInteger(counts.expenseCount);
  const accountTransactionCount = nonNegativeInteger(counts.accountTransactionCount);

  if (activeWageLockCount) parts.push(`${activeWageLockCount}个工资快照`);
  if (wageDetailCount) parts.push(`${wageDetailCount}条工资明细`);
  if (paymentRequestCount) parts.push(`${paymentRequestCount}个支付请求`);
  if (expenseCount) parts.push(`${expenseCount}条支出`);
  if (accountTransactionCount) parts.push(`${accountTransactionCount}条账户流水`);

  return parts.length ? `，涉及${parts.join("、")}` : "";
}

export function formatTeacherWageBlockerDisplayReason({
  blockerLevel = "",
  counts = null,
  hasBlocker = false,
} = {}) {
  const level = String(blockerLevel || "").trim();
  if (!hasBlocker && !level) return "";

  const summary = countSummary(counts || {});
  if (level === "payment_completed") {
    return `老师工资已支付${summary}；当前月结操作受已完成工资链路保护。`;
  }
  if (level === "payment_requested") {
    return `老师工资支付请求已生成${summary}；当前月结操作受工资链路保护。`;
  }
  if (level === "wage_snapshot") {
    return `老师工资已生成或锁定${summary}；当前月结操作受工资快照保护。如需变更，请先按受控流程处理未支付工资快照。`;
  }
  return "老师工资已生成或锁定；当前月结操作受工资链路保护。";
}
