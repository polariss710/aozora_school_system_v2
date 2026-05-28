const STATUS_LABELS = {
  pending: "待支付",
  paid: "已支付",
  cancelled: "已取消",
  reversed: "已撤销",
  void: "已作废",
};

const SOURCE_TYPE_LABELS = {
  teacher_wage: "老师工资",
};

export function formatCurrency(amount, currency) {
  if (amount === null || amount === undefined || amount === "") {
    return "-";
  }

  const numberValue = Number(amount);
  if (!Number.isFinite(numberValue)) {
    return safeText(amount);
  }

  const code = currency || "JPY";
  try {
    return new Intl.NumberFormat("zh-CN", {
      style: "currency",
      currency: code,
      currencyDisplay: "code",
      maximumFractionDigits: code === "JPY" ? 0 : 2,
    }).format(numberValue);
  } catch {
    return `${numberValue.toLocaleString("zh-CN")} ${safeText(code)}`;
  }
}

export function formatDate(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return safeText(value);
  }

  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function formatMonth(value) {
  if (!value) {
    return "-";
  }

  const text = String(value);
  const match = text.match(/^(\d{4})-(\d{2})/);
  if (match) {
    return `${match[1]}-${match[2]}`;
  }

  return safeText(value);
}

export function statusLabel(status) {
  return STATUS_LABELS[status] || safeText(status) || "-";
}

export function sourceTypeLabel(sourceType) {
  return SOURCE_TYPE_LABELS[sourceType] || safeText(sourceType) || "-";
}

export function safeText(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }

  return String(value);
}
