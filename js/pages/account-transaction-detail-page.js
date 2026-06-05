import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchAccountTransactionDetailPage,
  reverseAccountAdjustment,
} from "../api/account-transaction-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const TRANSACTION_TYPE_LABELS = {
  account_adjustment: "账户调整",
  account_adjustment_reversal: "账户调整撤销",
  transfer_out: "转账转出",
  transfer_in: "转账转入",
  income_adjust: "收入调整",
  expense_adjust: "支出调整 / 支付扣款",
  payment_reversal: "支付撤销",
  reimbursement_out: "报销转出",
  reimbursement_in: "报销转入",
};

const ACCOUNT_TYPE_LABELS = {
  cash: "现金",
  bank: "银行",
  wallet: "钱包",
  receivable: "应收",
  payable: "应付",
  other: "其他",
};

const RELATED_TABLE_LABELS = {
  school_income_records: "收入记录",
  school_expense_records: "支出记录",
  school_payment_requests: "老师工资支付请求",
  school_reimbursements: "报销记录",
  school_account_adjustments: "账户调整",
  school_account_transfers: "账户转账/调拨",
  school_accounts: "账户调整 / 初始账户来源",
};

const SOURCE_LINKS = {
  school_income_records: "income-detail.html",
  school_expense_records: "expense-detail.html",
  school_payment_requests: "payment-detail.html",
  school_reimbursements: "reimbursement-detail.html",
};

const dom = {};
let detailData = null;
let isReverseAccountAdjustmentSubmitting = false;

export function initAccountTransactionDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const transactionId = readTransactionId();
  if (!transactionId) {
    showMessage("error", "缺少账户流水 ID，请从账户管理一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadTransactionDetail(transactionId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#accountTransactionDetailMessageArea");
  dom.loadingState = document.querySelector("#accountTransactionDetailLoadingState");
  dom.content = document.querySelector("#accountTransactionDetailContent");
  dom.titleText = document.querySelector("#accountTransactionDetailTitleText");
  dom.basicInfo = document.querySelector("#accountTransactionDetailBasicInfo");
  dom.amountInfo = document.querySelector("#accountTransactionDetailAmountInfo");
  dom.accountInfo = document.querySelector("#accountTransactionDetailAccountInfo");
  dom.systemInfo = document.querySelector("#accountTransactionDetailSystemInfo");
  dom.noteBlock = document.querySelector("#accountTransactionDetailNoteBlock");
  dom.source = document.querySelector("#accountTransactionDetailSource");
  dom.openReverseAccountAdjustmentButton = document.querySelector("#openReverseAccountAdjustmentButton");
  dom.reverseAccountAdjustmentDialog = document.querySelector("#reverseAccountAdjustmentDialog");
  dom.reverseAccountAdjustmentSummary = document.querySelector("#reverseAccountAdjustmentSummary");
  dom.reverseAccountAdjustmentError = document.querySelector("#reverseAccountAdjustmentError");
  dom.reverseAccountAdjustmentDateInput = document.querySelector("#reverseAccountAdjustmentDateInput");
  dom.reverseAccountAdjustmentReasonInput = document.querySelector("#reverseAccountAdjustmentReasonInput");
  dom.reverseAccountAdjustmentConfirmCheck = document.querySelector("#reverseAccountAdjustmentConfirmCheck");
  dom.reverseAccountAdjustmentCancelButton = document.querySelector("#reverseAccountAdjustmentCancelButton");
  dom.reverseAccountAdjustmentSubmitButton = document.querySelector("#reverseAccountAdjustmentSubmitButton");
  bindEvents();
}

function bindEvents() {
  dom.openReverseAccountAdjustmentButton.addEventListener("click", openReverseAccountAdjustmentDialog);
  dom.reverseAccountAdjustmentCancelButton.addEventListener("click", closeReverseAccountAdjustmentDialog);
  dom.reverseAccountAdjustmentSubmitButton.addEventListener("click", submitReverseAccountAdjustment);
  dom.reverseAccountAdjustmentDateInput.addEventListener("input", () => {
    clearReverseAccountAdjustmentFieldInvalid("reversalDate");
    hideReverseAccountAdjustmentErrorIfClean();
  });
  dom.reverseAccountAdjustmentReasonInput.addEventListener("input", () => {
    clearReverseAccountAdjustmentFieldInvalid("reason");
    hideReverseAccountAdjustmentErrorIfClean();
  });
  dom.reverseAccountAdjustmentConfirmCheck.addEventListener("change", () => {
    clearReverseAccountAdjustmentFieldInvalid("confirmCheck");
    hideReverseAccountAdjustmentErrorIfClean();
  });
}

function readTransactionId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadTransactionDetail(transactionId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载账户流水详情...");

  try {
    detailData = await fetchAccountTransactionDetailPage(transactionId);
    renderTransactionDetail(detailData);
    setContentVisible(true);
    showMessage("success", "账户流水详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取账户流水详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderTransactionDetail(data) {
  const { transaction } = data;
  dom.titleText.textContent = `${formatDateOnly(transaction.transaction_date)} / ${transactionTypeLabel(transaction.transaction_type)} / ${formatCurrency(transaction.amount, transaction.currency)}`;

  dom.basicInfo.innerHTML = renderDefinitionList([
    ["流水 ID", shortId(transaction.id)],
    ["交易日期", formatDateOnly(transaction.transaction_date)],
    ["目标月份", formatMonth(transaction.year_month)],
    ["流水类型", transactionTypeLabel(transaction.transaction_type)],
    ["关联来源", relatedTableLabel(transaction.related_table)],
    ["related_id", shortId(transaction.related_id)],
    ["业务归属", businessNameById(transaction.business_entity_id)],
    ["创建时间", formatDate(transaction.created_at)],
    ["更新时间", formatDate(transaction.updated_at)],
  ]);

  dom.amountInfo.innerHTML = `
    ${renderDefinitionList([
      ["币种", displayValue(transaction.currency)],
      ["金额", formatCurrency(transaction.amount, transaction.currency)],
      ["金额方向", amountDirectionLabel(transaction.amount)],
      ["流水后余额", formatCurrency(transaction.balance_after, transaction.currency)],
      ["流水类型说明", transactionTypeLabel(transaction.transaction_type)],
    ])}
    <p class="section-note">这里只做流水方向说明，不做经营统计或余额重算。</p>
  `;

  renderAccountInfo(transaction);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["id", shortId(transaction.id)],
    ["account_id", shortId(transaction.account_id)],
    ["business_entity_id", shortId(transaction.business_entity_id)],
    ["related_table", displayValue(transaction.related_table)],
    ["related_id", shortId(transaction.related_id)],
    ["app_type", displayValue(transaction.app_type)],
    ["created_at", formatDate(transaction.created_at)],
    ["updated_at", formatDate(transaction.updated_at)],
  ]);

  dom.noteBlock.textContent = noteText(transaction);
  renderSource(data.source, transaction);
  renderReverseAccountAdjustmentAction(data);
}

function renderAccountInfo(transaction) {
  const account = accountById(transaction.account_id);
  if (!account) {
    dom.accountInfo.innerHTML = renderDefinitionList([
      ["账户", transaction.account_id ? "未知" : "未设置"],
      ["流水后余额", formatCurrency(transaction.balance_after, transaction.currency)],
    ]);
    return;
  }

  dom.accountInfo.innerHTML = `
    ${renderDefinitionList([
      ["账户名称", displayValue(account.name)],
      ["账户编码", displayValue(account.account_code)],
      ["账户类型", accountTypeLabel(account.account_type)],
      ["账户币种", displayValue(account.currency)],
      ["业务归属", businessNameById(account.business_entity_id)],
      ["公司账户", booleanLabel(account.is_company_account)],
      ["启用状态", booleanLabel(account.is_active)],
      ["流水后余额", formatCurrency(transaction.balance_after, transaction.currency)],
      ["当前账户余额", formatCurrency(account.current_balance, account.currency)],
    ])}
    <p class="section-note">current_balance 为当前账户余额，不代表该流水发生时余额；该流水记录后的余额请以 balance_after 为准。</p>
  `;
}

function renderReverseAccountAdjustmentAction(data) {
  const canReverse = canReverseAccountAdjustment(data);
  dom.openReverseAccountAdjustmentButton.classList.toggle("is-hidden", !canReverse);
}

function canReverseAccountAdjustment(data) {
  const transaction = data?.transaction;
  const adjustment = data?.source?.row;
  return Boolean(
    transaction?.transaction_type === "account_adjustment" &&
    transaction?.related_table === "school_account_adjustments" &&
    adjustment?.status === "posted" &&
    !adjustment?.reversed_at &&
    !adjustment?.reversal_account_transaction_id
  );
}

function openReverseAccountAdjustmentDialog() {
  if (!canReverseAccountAdjustment(detailData)) {
    showMessage("error", "当前账户流水不允许撤销账户调整。");
    return;
  }

  const adjustment = detailData.source.row;
  dom.reverseAccountAdjustmentSummary.innerHTML = renderDefinitionList([
    ["调整 ID", shortId(adjustment.id)],
    ["调整日期", formatDateOnly(adjustment.adjustment_date)],
    ["账户", accountNameById(adjustment.account_id)],
    ["业务归属", businessNameById(adjustment.business_entity_id)],
    ["调整金额", formatCurrency(adjustment.amount, adjustment.currency)],
    ["撤销后影响", formatCurrency(Number(adjustment.amount || 0) * -1, adjustment.currency)],
  ]);
  dom.reverseAccountAdjustmentDateInput.value = currentLocalDate();
  dom.reverseAccountAdjustmentReasonInput.value = "";
  dom.reverseAccountAdjustmentConfirmCheck.checked = false;
  clearReverseAccountAdjustmentErrors();
  setReverseAccountAdjustmentSubmitting(false);
  dom.reverseAccountAdjustmentDialog.classList.remove("is-hidden");
  dom.reverseAccountAdjustmentDialog.setAttribute("aria-hidden", "false");
  dom.reverseAccountAdjustmentDateInput.focus();
}

function closeReverseAccountAdjustmentDialog({ force = false } = {}) {
  if (isReverseAccountAdjustmentSubmitting && !force) {
    return;
  }

  dom.reverseAccountAdjustmentDialog.classList.add("is-hidden");
  dom.reverseAccountAdjustmentDialog.setAttribute("aria-hidden", "true");
}

async function submitReverseAccountAdjustment() {
  if (isReverseAccountAdjustmentSubmitting) {
    return;
  }

  clearReverseAccountAdjustmentErrors();

  if (!canReverseAccountAdjustment(detailData)) {
    showReverseAccountAdjustmentError("当前账户调整状态不允许撤销。", ["confirmCheck"]);
    return;
  }

  const adjustment = detailData.source.row;
  const reversalDate = dom.reverseAccountAdjustmentDateInput.value;
  const reason = dom.reverseAccountAdjustmentReasonInput.value.trim();

  if (!reversalDate) {
    showReverseAccountAdjustmentError("请选择撤销日期。", ["reversalDate"]);
    return;
  }

  if (!reason) {
    showReverseAccountAdjustmentError("请输入撤销原因。", ["reason"]);
    return;
  }

  if (!dom.reverseAccountAdjustmentConfirmCheck.checked) {
    showReverseAccountAdjustmentError("请确认撤销该账户调整。", ["confirmCheck"]);
    return;
  }

  setReverseAccountAdjustmentSubmitting(true);

  try {
    const result = await reverseAccountAdjustment({
      adjustmentId: adjustment.id,
      reversalDate,
      reason,
    });

    closeReverseAccountAdjustmentDialog({ force: true });
    await loadTransactionDetail(detailData.transaction.id);
    const reversalTransactionId = result.reversal_account_transaction_id || result.reversal_transaction_id;
    showMessage(
      "success",
      `账户调整已撤销。撤销流水：${shortId(reversalTransactionId)}。`
    );
  } catch (error) {
    showReverseAccountAdjustmentError(error.message || String(error), reverseAccountAdjustmentFieldIdsForError(error));
  } finally {
    setReverseAccountAdjustmentSubmitting(false);
  }
}

function showReverseAccountAdjustmentError(message, fieldIds = []) {
  dom.reverseAccountAdjustmentError.textContent = message;
  dom.reverseAccountAdjustmentError.classList.remove("is-hidden");
  fieldIds.forEach(setReverseAccountAdjustmentFieldInvalid);
}

function clearReverseAccountAdjustmentErrors() {
  dom.reverseAccountAdjustmentError.textContent = "";
  dom.reverseAccountAdjustmentError.classList.add("is-hidden");
  ["reversalDate", "reason", "confirmCheck"].forEach(clearReverseAccountAdjustmentFieldInvalid);
}

function hideReverseAccountAdjustmentErrorIfClean() {
  const hasInvalidField = document.querySelector("[data-reverse-account-adjustment-field].is-invalid");
  if (!hasInvalidField) {
    dom.reverseAccountAdjustmentError.textContent = "";
    dom.reverseAccountAdjustmentError.classList.add("is-hidden");
  }
}

function setReverseAccountAdjustmentFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-reverse-account-adjustment-field="${fieldId}"]`);
  field?.classList.add("is-invalid");
}

function clearReverseAccountAdjustmentFieldInvalid(fieldId) {
  const field = document.querySelector(`[data-reverse-account-adjustment-field="${fieldId}"]`);
  field?.classList.remove("is-invalid");
}

function setReverseAccountAdjustmentSubmitting(isSubmitting) {
  isReverseAccountAdjustmentSubmitting = isSubmitting;
  dom.reverseAccountAdjustmentSubmitButton.disabled = isSubmitting;
  dom.reverseAccountAdjustmentCancelButton.disabled = isSubmitting;
  dom.reverseAccountAdjustmentSubmitButton.textContent = isSubmitting ? "撤销中..." : "确认撤销";
}

function reverseAccountAdjustmentFieldIdsForError(error) {
  const message = error?.message || String(error || "");
  if (message.includes("date") || message.includes("日期")) return ["reversalDate"];
  if (message.includes("reason") || message.includes("原因")) return ["reason"];
  return [];
}

function renderSource(source, transaction) {
  if (!transaction.related_table || !transaction.related_id) {
    dom.source.innerHTML = '<div class="state-text">无关联来源对象。</div>';
    return;
  }

  if (source?.error === "unsupported") {
    dom.source.innerHTML = `<div class="state-text">暂不支持展示来源表：${escapeHtml(transaction.related_table)}。</div>`;
    return;
  }

  if (source?.error) {
    dom.source.innerHTML = `<div class="state-text">来源记录读取失败：${escapeHtml(source.error)}</div>`;
    return;
  }

  if (!source?.row) {
    dom.source.innerHTML = '<div class="state-text">来源记录未找到。可能是历史数据、已清理数据或当前只读权限不可见。</div>';
    return;
  }

  const link = sourceLink(transaction.related_table, transaction.related_id);
  dom.source.innerHTML = `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(relatedTableLabel(transaction.related_table))}</strong>
        <span class="status-badge status-neutral">${escapeHtml(shortId(transaction.related_id))}</span>
      </div>
      ${link ? `<p><a class="table-action-button" href="${escapeAttribute(link)}">查看来源详情</a></p>` : ""}
      ${renderDefinitionList(sourceDefinitionItems(transaction.related_table, source.row))}
    </article>
  `;
}

function sourceDefinitionItems(table, row) {
  if (table === "school_income_records") {
    return [
      ["收入日期", formatDateOnly(row.income_date)],
      ["目标月份", formatMonth(row.year_month)],
      ["结算月份", formatMonth(row.settlement_month)],
      ["收入分类", displayValue(row.income_category)],
      ["描述", displayValue(row.description)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["JPY 金额", formatCurrency(row.amount_jpy, "JPY")],
      ["CNY 金额", formatCurrency(row.amount_cny, "CNY")],
      ["状态", displayValue(row.status)],
      ["账户", accountNameById(row.account_id)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  if (table === "school_expense_records") {
    return [
      ["支出日期", formatDateOnly(row.expense_date)],
      ["目标月份", formatMonth(row.year_month)],
      ["支出分类", displayValue(row.expense_category)],
      ["描述", displayValue(row.description)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["JPY 金额", formatCurrency(row.amount_jpy, "JPY")],
      ["CNY 金额", formatCurrency(row.amount_cny, "CNY")],
      ["状态", displayValue(row.status)],
      ["报销状态", displayValue(row.reimbursement_status)],
      ["账户", accountNameById(row.account_id)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  if (table === "school_payment_requests") {
    return [
      ["请求月份", formatMonth(row.request_month)],
      ["来源类型", displayValue(row.source_type)],
      ["收款方", displayValue(row.payee_name)],
      ["业务归属", displayValue(row.business_name)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["JPY 金额", formatCurrency(row.amount_jpy, "JPY")],
      ["CNY 金额", formatCurrency(row.amount_cny, "CNY")],
      ["状态", displayValue(row.status)],
      ["支付时间", formatDate(row.paid_at)],
      ["撤销时间", formatDate(row.reversed_at)],
      ["重新生成时间", formatDate(row.reissued_at)],
      ["paid_expense_id", shortId(row.paid_expense_id)],
    ];
  }

  if (table === "school_reimbursements") {
    return [
      ["报销日期", formatDateOnly(row.reimbursement_date)],
      ["目标月份", formatMonth(row.year_month)],
      ["业务归属", businessNameById(row.business_entity_id)],
      ["转出账户", accountNameById(row.from_account_id)],
      ["转入账户", accountNameById(row.to_account_id)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["状态", displayValue(row.status)],
      ["备注", displayValue(row.note)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  if (table === "school_account_adjustments") {
    return [
      ["调整日期", formatDateOnly(row.adjustment_date)],
      ["目标月份", formatMonth(row.year_month)],
      ["业务归属", businessNameById(row.business_entity_id)],
      ["账户", accountNameById(row.account_id)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["调整前余额", formatCurrency(row.balance_before, row.currency)],
      ["调整后余额", formatCurrency(row.balance_after, row.currency)],
      ["原因", displayValue(row.reason)],
      ["备注", displayValue(row.note)],
      ["状态", displayValue(row.status)],
      ["账户流水", shortId(row.account_transaction_id)],
      ["撤销时间", formatDate(row.reversed_at)],
      ["撤销原因", displayValue(row.reversal_reason)],
      ["撤销流水", shortId(row.reversal_account_transaction_id)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  if (table === "school_account_transfers") {
    return [
      ["转账日期", formatDateOnly(row.transfer_date)],
      ["目标月份", formatMonth(row.year_month)],
      ["业务归属", businessNameById(row.business_entity_id)],
      ["转出账户", accountNameById(row.from_account_id)],
      ["转入账户", accountNameById(row.to_account_id)],
      ["金额", formatCurrency(row.amount, row.currency)],
      ["转出前余额", formatCurrency(row.from_balance_before, row.currency)],
      ["转出后余额", formatCurrency(row.from_balance_after, row.currency)],
      ["转入前余额", formatCurrency(row.to_balance_before, row.currency)],
      ["转入后余额", formatCurrency(row.to_balance_after, row.currency)],
      ["原因", displayValue(row.reason)],
      ["备注", displayValue(row.note)],
      ["状态", displayValue(row.status)],
      ["转出流水", shortId(row.from_account_transaction_id)],
      ["转入流水", shortId(row.to_account_transaction_id)],
      ["撤销时间", formatDate(row.reversed_at)],
      ["撤销原因", displayValue(row.reversal_reason)],
      ["撤销转出流水", shortId(row.reversal_from_account_transaction_id)],
      ["撤销转入流水", shortId(row.reversal_to_account_transaction_id)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  if (table === "school_accounts") {
    return [
      ["账户名称", displayValue(row.name)],
      ["账户编码", displayValue(row.account_code)],
      ["账户类型", accountTypeLabel(row.account_type)],
      ["币种", displayValue(row.currency)],
      ["业务归属", businessNameById(row.business_entity_id)],
      ["当前余额", formatCurrency(row.current_balance, row.currency)],
      ["启用状态", booleanLabel(row.is_active)],
      ["创建时间", formatDate(row.created_at)],
    ];
  }

  return [["来源 ID", shortId(row.id)]];
}

function renderDefinitionList(items) {
  return `
    <dl class="detail-definition-list">
      ${items.map(([label, value]) => `
        <div>
          <dt>${escapeHtml(label)}</dt>
          <dd>${escapeHtml(displayValue(value))}</dd>
        </div>
      `).join("")}
    </dl>
  `;
}

function accountById(id) {
  return detailData?.lookups.accounts.find((item) => item.id === id) || null;
}

function businessById(id) {
  return detailData?.lookups.businessEntities.find((item) => item.id === id) || null;
}

function accountNameById(id) {
  const account = accountById(id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function businessNameById(id) {
  const entity = businessById(id);
  if (!entity) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(entity.name) || "未设置";
  const code = safeText(entity.code);
  return code ? `${name} / ${code}` : name;
}

function transactionTypeLabel(type) {
  return TRANSACTION_TYPE_LABELS[type] || displayValue(type);
}

function accountTypeLabel(type) {
  return ACCOUNT_TYPE_LABELS[type] || displayValue(type);
}

function relatedTableLabel(table) {
  return RELATED_TABLE_LABELS[table] || displayValue(table);
}

function amountDirectionLabel(amount) {
  const value = Number(amount);
  if (value > 0) return "入金 / 增加";
  if (value < 0) return "出金 / 减少";
  return "无变化";
}

function sourceLink(table, id) {
  const page = SOURCE_LINKS[table];
  return page && id ? `./${page}?id=${encodeURIComponent(id)}` : "";
}

function noteText(transaction) {
  const rows = [
    ["说明", transaction.description],
    ["备注", transaction.note],
  ];

  return rows
    .map(([label, value]) => `${label}：${displayValue(value)}`)
    .join("\n");
}

function booleanLabel(value) {
  if (value === true) return "是";
  if (value === false) return "否";
  return "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function currentLocalDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function displayValue(value) {
  return safeText(value) || "-";
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
}

function setContentVisible(isVisible) {
  dom.content.classList.toggle("is-hidden", !isVisible);
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
}

function escapeHtml(value) {
  return safeText(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value);
}
