import { hasSupabaseConfig } from "../supabase-client.js";
import {
  fetchReimbursementDetailPage,
  reverseReimbursementRecord,
} from "../api/reimbursement-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const REIMBURSEMENT_STATUS_LABELS = {
  paid: "已报销",
  reversed: "已撤销",
};

const EXPENSE_STATUS_LABELS = {
  paid: "已支付",
};

const EXPENSE_CATEGORY_LABELS = {
  advertising: "广告宣传",
  classroom: "教室费用",
  other: "其他",
  software: "软件服务",
  tax_accounting: "税务会计",
  teacher_wage: "老师工资",
};

const REIMBURSEMENT_STATUS = {
  not_required: "无需报销",
  paid: "已报销",
  pending: "待报销",
};

const TRANSACTION_TYPE_LABELS = {
  reimbursement_out: "报销出金",
  reimbursement_in: "报销入金",
  reimbursement_reverse_in: "报销撤销入金",
  reimbursement_reverse_out: "报销撤销出金",
};

const REVERSE_REIMBURSEMENT_FIELD_IDS = [
  "reversalDate",
  "confirmCheck",
];

const dom = {};
let detailData = null;
let isReverseSubmitting = false;

export function initReimbursementDetailPage() {
  cacheDom();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const reimbursementId = readReimbursementId();
  if (!reimbursementId) {
    showMessage("error", "缺少报销记录 ID，请从报销管理一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadReimbursementDetail(reimbursementId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#reimbursementDetailMessageArea");
  dom.actionStatus = document.querySelector("#reimbursementDetailActionStatus");
  dom.openReverseReimbursementButton = document.querySelector("#openReverseReimbursementButton");
  dom.loadingState = document.querySelector("#reimbursementDetailLoadingState");
  dom.content = document.querySelector("#reimbursementDetailContent");
  dom.titleText = document.querySelector("#reimbursementDetailTitleText");
  dom.basicInfo = document.querySelector("#reimbursementDetailBasicInfo");
  dom.accountInfo = document.querySelector("#reimbursementDetailAccountInfo");
  dom.summaryInfo = document.querySelector("#reimbursementDetailSummaryInfo");
  dom.reversalCard = document.querySelector("#reimbursementDetailReversalCard");
  dom.reversalInfo = document.querySelector("#reimbursementDetailReversalInfo");
  dom.systemInfo = document.querySelector("#reimbursementDetailSystemInfo");
  dom.noteBlock = document.querySelector("#reimbursementDetailNoteBlock");
  dom.transactions = document.querySelector("#reimbursementDetailTransactions");
  dom.expenseCount = document.querySelector("#reimbursementDetailExpenseCount");
  dom.expenseEmpty = document.querySelector("#reimbursementDetailExpenseEmpty");
  dom.expenseRows = document.querySelector("#reimbursementDetailExpenseRows");
  dom.reverseDialog = document.querySelector("#reverseReimbursementDialog");
  dom.reverseSummary = document.querySelector("#reverseReimbursementSummary");
  dom.reverseError = document.querySelector("#reverseReimbursementError");
  dom.reverseDateInput = document.querySelector("#reverseReimbursementDateInput");
  dom.reverseReasonInput = document.querySelector("#reverseReimbursementReasonInput");
  dom.reverseConfirmCheck = document.querySelector("#reverseReimbursementConfirmCheck");
  dom.reverseSubmitButton = document.querySelector("#reverseReimbursementSubmitButton");
  dom.reverseCancelButton = document.querySelector("#reverseReimbursementCancelButton");
}

function bindEvents() {
  dom.openReverseReimbursementButton.addEventListener("click", openReverseDialog);
  dom.reverseCancelButton.addEventListener("click", closeReverseDialog);
  dom.reverseSubmitButton.addEventListener("click", submitReverseReimbursement);
  dom.reverseDateInput.addEventListener("input", () => {
    setReverseFieldInvalid("reversalDate", false);
    hideReverseErrorIfClean();
  });
  dom.reverseDateInput.addEventListener("change", () => {
    setReverseFieldInvalid("reversalDate", false);
    hideReverseErrorIfClean();
  });
  dom.reverseConfirmCheck.addEventListener("change", () => {
    setReverseFieldInvalid("confirmCheck", false);
    hideReverseErrorIfClean();
  });
}

function readReimbursementId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadReimbursementDetail(reimbursementId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载报销记录详情...");

  try {
    detailData = await fetchReimbursementDetailPage(reimbursementId);
    renderReimbursementDetail(detailData);
    setContentVisible(true);
    showMessage("success", "报销记录详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取报销记录详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderReimbursementDetail(data) {
  const { reimbursement, items, transactions } = data;
  const itemTotal = sumBy(items, "amount");
  const transactionTotal = sumBy(transactions, "amount");
  const outTotal = sumBy(
    transactions.filter((transaction) => transaction.transaction_type === "reimbursement_out"),
    "amount"
  );
  const inTotal = sumBy(
    transactions.filter((transaction) => transaction.transaction_type === "reimbursement_in"),
    "amount"
  );
  const itemDifference = itemTotal - Number(reimbursement.amount || 0);

  renderActionArea(reimbursement);
  dom.titleText.textContent = `${formatDateOnly(reimbursement.reimbursement_date)} / ${formatCurrency(reimbursement.amount, reimbursement.currency)}`;
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["报销日期", formatDateOnly(reimbursement.reimbursement_date)],
    ["目标月份", formatMonth(reimbursement.year_month)],
    ["状态", reimbursementStatusLabel(reimbursement.status)],
    ["业务归属", businessNameById(reimbursement.business_entity_id)],
    ["金额", formatCurrency(reimbursement.amount, reimbursement.currency)],
    ["币种", displayValue(reimbursement.currency)],
    ["创建时间", formatDate(reimbursement.created_at)],
    ["更新时间", formatDate(reimbursement.updated_at)],
  ]);

  dom.accountInfo.innerHTML = renderDefinitionList([
    ["出金账户", accountNameById(reimbursement.from_account_id)],
    ["出金账户编码", accountCodeById(reimbursement.from_account_id)],
    ["出金币种", accountCurrencyById(reimbursement.from_account_id)],
    ["入金账户", accountNameById(reimbursement.to_account_id)],
    ["入金账户编码", accountCodeById(reimbursement.to_account_id)],
    ["入金币种", accountCurrencyById(reimbursement.to_account_id)],
  ]);

  dom.summaryInfo.innerHTML = `
    ${renderDefinitionList([
      ["关联支出条数", displayCount(items.length)],
      ["item 金额合计", formatCurrency(itemTotal, reimbursement.currency)],
      ["报销主表金额", formatCurrency(reimbursement.amount, reimbursement.currency)],
      ["item 与主表差异", formatCurrency(itemDifference, reimbursement.currency)],
      ["账户流水条数", displayCount(transactions.length)],
      ["账户流水金额合计", formatCurrency(transactionTotal, reimbursement.currency)],
      ["reimbursement_out 合计", formatCurrency(outTotal, reimbursement.currency)],
      ["reimbursement_in 合计", formatCurrency(inTotal, reimbursement.currency)],
    ])}
    ${Math.abs(itemDifference) > 0.0001 ? '<p class="section-note">item 合计与主表金额存在差异；本页仅提示差异，不自动修正任何金额。</p>' : ""}
  `;

  renderReversalInfo(reimbursement);
  dom.systemInfo.innerHTML = renderDefinitionList([
    ["reimbursement id", shortId(reimbursement.id)],
    ["app_type", displayValue(reimbursement.app_type)],
    ["created_at", formatDate(reimbursement.created_at)],
    ["updated_at", formatDate(reimbursement.updated_at)],
  ]);

  dom.noteBlock.textContent = displayValue(reimbursement.note);
  renderTransactions(transactions);
  renderExpenseItems(items, data.expenses, reimbursement.currency);
}

function renderActionArea(reimbursement) {
  const status = reimbursement?.status || "";
  dom.actionStatus.className = `status-badge ${reimbursementStatusClass(status)}`;
  dom.actionStatus.textContent = reimbursementStatusLabel(status);
  dom.openReverseReimbursementButton.classList.toggle("is-hidden", status !== "paid");
  dom.openReverseReimbursementButton.disabled = status !== "paid";
}

function renderReversalInfo(reimbursement) {
  const isReversed = reimbursement.status === "reversed";
  dom.reversalCard.classList.toggle("is-hidden", !isReversed);

  if (!isReversed) {
    dom.reversalInfo.innerHTML = "";
    return;
  }

  const fromTransactionId = reimbursement.reversal_from_account_transaction_id;
  const toTransactionId = reimbursement.reversal_to_account_transaction_id;
  dom.reversalInfo.innerHTML = `
    ${renderDefinitionList([
      ["撤销时间", formatDate(reimbursement.reversed_at)],
      ["撤销理由", displayValue(reimbursement.reversal_reason)],
      ["反向入金流水", shortId(fromTransactionId)],
      ["反向出金流水", shortId(toTransactionId)],
    ])}
    <div class="reimbursement-reversal-links">
      ${fromTransactionId ? `<a class="table-action-button" href="./account-transaction-detail.html?id=${encodeURIComponent(fromTransactionId)}">反向入金流水详情</a>` : ""}
      ${toTransactionId ? `<a class="table-action-button" href="./account-transaction-detail.html?id=${encodeURIComponent(toTransactionId)}">反向出金流水详情</a>` : ""}
    </div>
  `;
}

function renderTransactions(transactions) {
  if (!transactions.length) {
    dom.transactions.innerHTML = '<div class="state-text">无关联账户流水。</div>';
    return;
  }

  dom.transactions.innerHTML = transactions.map((transaction) => `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(transactionTypeLabel(transaction.transaction_type))}</strong>
        <span class="status-badge ${Number(transaction.amount) < 0 ? "status-cancelled" : "status-active"}">${escapeHtml(formatCurrency(transaction.amount, transaction.currency))}</span>
      </div>
      ${renderDefinitionList([
        ["交易日期", formatDateOnly(transaction.transaction_date)],
        ["账户", accountNameById(transaction.account_id)],
        ["币种", displayValue(transaction.currency)],
        ["余额", formatCurrency(transaction.balance_after, transaction.currency)],
        ["related_table", displayValue(transaction.related_table)],
        ["related_id", shortId(transaction.related_id)],
        ["描述", displayValue(transaction.description)],
        ["备注", displayValue(transaction.note)],
        ["创建时间", formatDate(transaction.created_at)],
      ])}
      <p><a class="table-action-button" href="./account-transaction-detail.html?id=${encodeURIComponent(transaction.id)}">流水详情</a></p>
    </article>
  `).join("");
}

function renderExpenseItems(items, expenses, reimbursementCurrency) {
  dom.expenseCount.textContent = `${items.length} 条`;
  dom.expenseEmpty.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.expenseRows.innerHTML = "";
    return;
  }

  dom.expenseRows.innerHTML = items.map((item) => {
    const expense = expenses.find((row) => row.id === item.expense_id);
    return `
      <tr>
        <td class="reimbursement-nowrap">${escapeHtml(formatDateOnly(expense?.expense_date))}</td>
        <td class="reimbursement-nowrap">${escapeHtml(formatMonth(expense?.year_month))}</td>
        <td class="reimbursement-nowrap">${escapeHtml(expenseCategoryLabel(expense?.expense_category))}</td>
        <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(expense?.description))}</span></td>
        <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(item.amount, reimbursementCurrency || expense?.currency))}</td>
        <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(expense?.amount, expense?.currency))}</td>
        <td class="reimbursement-nowrap">${escapeHtml(displayValue(expense?.currency))}</td>
        <td><span class="status-badge ${escapeAttribute(statusClass(expense?.status))}">${escapeHtml(expenseStatusLabel(expense?.status))}</span></td>
        <td class="reimbursement-nowrap">${escapeHtml(displayValue(expense?.receipt_status))}</td>
        <td class="reimbursement-nowrap">${escapeHtml(expenseReimbursementStatusLabel(expense?.reimbursement_status, expense?.expense_category))}</td>
        <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(item.note || expense?.note))}</span></td>
        <td class="reimbursement-nowrap">${expense?.id ? `<a class="table-action-button" href="./expense-detail.html?id=${encodeURIComponent(expense.id)}">详情</a>` : "-"}</td>
      </tr>
    `;
  }).join("");
}

function openReverseDialog() {
  if (isReverseSubmitting) {
    return;
  }

  if (!detailData?.reimbursement) {
    showMessage("error", "撤销对象不存在，请刷新后重试。");
    return;
  }

  if (detailData.reimbursement.status !== "paid") {
    showMessage("error", "只有已支付的报销记录可以撤销。");
    return;
  }

  clearReverseErrors();
  dom.reverseSummary.innerHTML = renderReverseSummary(detailData.reimbursement);
  dom.reverseDateInput.value = currentDate();
  dom.reverseReasonInput.value = "";
  dom.reverseConfirmCheck.checked = false;
  setReverseSubmitting(false);
  dom.reverseDialog.classList.remove("is-hidden");
  dom.reverseDialog.setAttribute("aria-hidden", "false");
}

function closeReverseDialog() {
  if (isReverseSubmitting) {
    return;
  }

  dom.reverseDialog.classList.add("is-hidden");
  dom.reverseDialog.setAttribute("aria-hidden", "true");
}

async function submitReverseReimbursement() {
  if (isReverseSubmitting) {
    return;
  }

  clearReverseErrors();
  const payload = readReversePayload();
  if (!payload) {
    return;
  }

  setReverseSubmitting(true);

  try {
    await reverseReimbursementRecord(payload);
    setReverseSubmitting(false);
    closeReverseDialog();
    await loadReimbursementDetail(payload.reimbursementId);
    showMessage("success", "报销已撤销。");
  } catch (error) {
    console.error(error);
    showReverseError(`撤销报销失败：${error.message || error}`, reverseFieldIdsForError(error.message || ""));
  } finally {
    setReverseSubmitting(false);
  }
}

function readReversePayload() {
  const reimbursement = detailData?.reimbursement;
  if (!reimbursement?.id) {
    showReverseError("撤销对象不存在，请关闭后重试。");
    return null;
  }

  if (reimbursement.status !== "paid") {
    showReverseError("只有已支付的报销记录可以撤销。");
    return null;
  }

  const reversalDate = dom.reverseDateInput.value;
  if (!reversalDate) {
    showReverseError("请选择撤销日期。", ["reversalDate"]);
    return null;
  }

  if (!dom.reverseConfirmCheck.checked) {
    showReverseError("请勾选确认撤销说明。", ["confirmCheck"]);
    return null;
  }

  return {
    reimbursementId: reimbursement.id,
    reversalDate,
    reason: dom.reverseReasonInput.value.trim(),
  };
}

function renderReverseSummary(reimbursement) {
  return renderDefinitionList([
    ["报销日期", formatDateOnly(reimbursement.reimbursement_date)],
    ["状态", reimbursementStatusLabel(reimbursement.status)],
    ["金额", formatCurrency(reimbursement.amount, reimbursement.currency)],
    ["出金账户", accountNameById(reimbursement.from_account_id)],
    ["入金账户", accountNameById(reimbursement.to_account_id)],
    ["关联支出条数", displayCount(detailData?.items?.length || 0)],
  ]);
}

function setReverseSubmitting(isSubmitting) {
  isReverseSubmitting = isSubmitting;
  dom.reverseSubmitButton.disabled = isSubmitting;
  dom.reverseCancelButton.disabled = isSubmitting;
  dom.reverseSubmitButton.textContent = isSubmitting ? "撤销中..." : "确认撤销";
}

function clearReverseErrors() {
  dom.reverseError.textContent = "";
  dom.reverseError.classList.add("is-hidden");
  for (const fieldId of REVERSE_REIMBURSEMENT_FIELD_IDS) {
    setReverseFieldInvalid(fieldId, false);
  }
}

function showReverseError(message, fieldIds = []) {
  dom.reverseError.textContent = message;
  dom.reverseError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setReverseFieldInvalid(fieldId, true);
  }
  dom.reverseDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function reverseFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("撤销日期")) fields.push("reversalDate");
  return fields;
}

function setReverseFieldInvalid(fieldId, invalid) {
  const field = dom.reverseDialog.querySelector(`[data-reverse-reimbursement-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideReverseErrorIfClean() {
  const hasInvalidField = Boolean(dom.reverseDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.reverseError.textContent = "";
    dom.reverseError.classList.add("is-hidden");
  }
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

function businessNameById(id) {
  const entity = detailData?.lookups.businessEntities.find((item) => item.id === id);
  if (!entity) {
    return id ? "未知" : "未设置";
  }

  const code = safeText(entity.code);
  const name = safeText(entity.name) || "未设置";
  return code ? `${name} / ${code}` : name;
}

function accountById(id) {
  return detailData?.lookups.accounts.find((item) => item.id === id);
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

function accountCodeById(id) {
  return displayValue(accountById(id)?.account_code);
}

function accountCurrencyById(id) {
  return displayValue(accountById(id)?.currency);
}

function reimbursementStatusLabel(value) {
  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function reimbursementStatusClass(value) {
  if (value === "paid") {
    return "status-paid";
  }

  if (value === "reversed") {
    return "status-reversed";
  }

  return "status-neutral";
}

function expenseStatusLabel(value) {
  return EXPENSE_STATUS_LABELS[value] || displayValue(value);
}

function expenseCategoryLabel(value) {
  return EXPENSE_CATEGORY_LABELS[value] || displayValue(value);
}

function expenseReimbursementStatusLabel(value, expenseCategory = "") {
  if (expenseCategory === "teacher_wage") {
    if (value === "pending") {
      return "工资垫付待清算";
    }
    if (value === "not_required") {
      return "无需清算（公司账户支付）";
    }
  }

  return REIMBURSEMENT_STATUS[value] || displayValue(value);
}

function transactionTypeLabel(value) {
  return TRANSACTION_TYPE_LABELS[value] || displayValue(value);
}

function statusClass(value) {
  if (value === "paid") {
    return "status-paid";
  }

  if (value === "pending") {
    return "status-pending";
  }

  return "status-neutral";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
}

function sumBy(rows, key) {
  return rows.reduce((total, row) => total + Number(row[key] || 0), 0);
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function displayCount(value) {
  return Number(value || 0).toLocaleString("zh-CN");
}

function displayValue(value) {
  return safeText(value) || "-";
}

function currentDate() {
  return new Date().toISOString().slice(0, 10);
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
