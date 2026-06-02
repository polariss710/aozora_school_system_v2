import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchPaymentDetailPage } from "../api/payment-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const PAYMENT_REQUEST_STATUS_LABELS = {
  pending: "待支付",
  paid: "已支付",
  reversed: "已撤销",
  void: "已作废",
  cancelled: "已取消",
};

const SOURCE_TYPE_LABELS = {
  teacher_wage: "老师工资",
};

const PAYEE_TYPE_LABELS = {
  teacher: "老师",
};

const WAGE_STATUS_LABELS = {
  locked: "已锁定",
  void: "已作废",
};

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const EXPENSE_CATEGORY_LABELS = {
  teacher_wage: "老师工资",
};

const REIMBURSEMENT_STATUS_LABELS = {
  not_required: "无需报销",
  paid: "已报销",
  pending: "待报销",
};

const TRANSACTION_TYPE_LABELS = {
  expense_adjust: "支出调整",
  payment_reversal: "支付撤销",
};

const dom = {};
let detailData = null;

export function initPaymentDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const paymentRequestId = readPaymentRequestId();
  if (!paymentRequestId) {
    showMessage("error", "缺少老师工资支付请求 ID，请从老师工资支付一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadPaymentDetail(paymentRequestId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#paymentDetailMessageArea");
  dom.loadingState = document.querySelector("#paymentDetailLoadingState");
  dom.content = document.querySelector("#paymentDetailContent");
  dom.titleText = document.querySelector("#paymentDetailTitleText");
  dom.basicInfo = document.querySelector("#paymentDetailBasicInfo");
  dom.amountInfo = document.querySelector("#paymentDetailAmountInfo");
  dom.timelineInfo = document.querySelector("#paymentDetailTimelineInfo");
  dom.systemInfo = document.querySelector("#paymentDetailSystemInfo");
  dom.noteBlock = document.querySelector("#paymentDetailNoteBlock");
  dom.wageLock = document.querySelector("#paymentDetailWageLock");
  dom.expense = document.querySelector("#paymentDetailExpense");
  dom.accountInfo = document.querySelector("#paymentDetailAccountInfo");
  dom.paidTransaction = document.querySelector("#paymentDetailPaidTransaction");
  dom.reversalTransaction = document.querySelector("#paymentDetailReversalTransaction");
  dom.chainSummary = document.querySelector("#paymentDetailChainSummary");
  dom.chainCount = document.querySelector("#paymentDetailChainCount");
  dom.chainRows = document.querySelector("#paymentDetailChainRows");
  dom.chainEmpty = document.querySelector("#paymentDetailChainEmpty");
}

function readPaymentRequestId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadPaymentDetail(paymentRequestId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载老师工资支付详情...");

  try {
    detailData = await fetchPaymentDetailPage(paymentRequestId);
    renderPaymentDetail(detailData);
    setContentVisible(true);
    showMessage("success", "老师工资支付详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取老师工资支付详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderPaymentDetail(data) {
  const { paymentRequest } = data;
  dom.titleText.textContent = `${formatMonth(paymentRequest.request_month)} / ${displayValue(paymentRequest.payee_name)} / ${formatCurrency(paymentRequest.amount, paymentRequest.currency)}`;

  dom.basicInfo.innerHTML = renderDefinitionList([
    ["请求 ID", shortId(paymentRequest.id)],
    ["来源类型", sourceTypeLabel(paymentRequest.source_type)],
    ["来源 ID", shortId(paymentRequest.source_id)],
    ["请求月份", formatMonth(paymentRequest.request_month)],
    ["收款方类型", payeeTypeLabel(paymentRequest.payee_type)],
    ["收款方", displayValue(paymentRequest.payee_name)],
    ["业务归属", displayValue(paymentRequest.business_name || paymentRequest.business_entity_id)],
    ["状态", paymentRequestStatusLabel(paymentRequest.status)],
    ["到期日", formatDateOnly(paymentRequest.due_date)],
  ]);

  dom.amountInfo.innerHTML = renderDefinitionList([
    ["币种", displayValue(paymentRequest.currency)],
    ["原币金额", formatCurrency(paymentRequest.amount, paymentRequest.currency)],
    ["JPY 金额", formatCurrency(paymentRequest.amount_jpy, "JPY")],
    ["CNY 金额", formatCurrency(paymentRequest.amount_cny, "CNY")],
    ["账户", accountNameById(paymentRequest.account_id)],
  ]);

  dom.timelineInfo.innerHTML = renderDefinitionList([
    ["当前状态", paymentRequestStatusLabel(paymentRequest.status)],
    ["创建时间", formatDate(paymentRequest.created_at)],
    ["支付时间", formatDate(paymentRequest.paid_at)],
    ["撤销时间", formatDate(paymentRequest.reversed_at)],
    ["重新生成时间", formatDate(paymentRequest.reissued_at)],
    ["撤销原因", displayValue(paymentRequest.reversal_reason)],
    ["reissue 原因", displayValue(paymentRequest.reissue_reason)],
  ]);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["id", shortId(paymentRequest.id)],
    ["source_type", displayValue(paymentRequest.source_type)],
    ["source_id", shortId(paymentRequest.source_id)],
    ["payee_id", shortId(paymentRequest.payee_id)],
    ["business_entity_id", shortId(paymentRequest.business_entity_id)],
    ["paid_expense_id", shortId(paymentRequest.paid_expense_id)],
    ["paid_account_transaction_id", shortId(paymentRequest.paid_account_transaction_id)],
    ["reversal_transaction_id", shortId(paymentRequest.reversal_transaction_id)],
    ["updated_at", formatDate(paymentRequest.updated_at)],
  ]);

  dom.noteBlock.textContent = displayValue(paymentRequest.note);
  renderWageLock(data.wageLock, paymentRequest);
  renderExpense(data.expense, paymentRequest);
  renderAccount(paymentRequest.account_id);
  renderTransaction(dom.paidTransaction, findTransactionById(paymentRequest.paid_account_transaction_id), "无原扣款流水。");
  renderTransaction(dom.reversalTransaction, findTransactionById(paymentRequest.reversal_transaction_id), "无撤销冲销流水。");
  renderReissueChain(paymentRequest, data.sourceRequests);
}

function renderWageLock(wageLock, paymentRequest) {
  if (!wageLock) {
    dom.wageLock.innerHTML = paymentRequest.source_type === "teacher_wage"
      ? '<div class="state-text">未找到关联工资锁定记录。</div>'
      : '<div class="state-text">当前请求不是老师工资来源。</div>';
    return;
  }

  dom.wageLock.innerHTML = `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(wageLock.id))}</strong>
        <span class="status-badge ${escapeAttribute(statusClass(wageLock.status))}">${escapeHtml(wageStatusLabel(wageLock.status))}</span>
      </div>
      <p><a class="table-action-button" href="./wage-detail.html?id=${encodeURIComponent(wageLock.id)}">查看老师工资结算详情</a></p>
      ${renderDefinitionList([
        ["结算月份", formatMonth(wageLock.settlement_month)],
        ["老师", displayValue(wageLock.teacher_name)],
        ["业务归属", displayValue(wageLock.business_name)],
        ["结算类型", settlementTypeLabel(wageLock.settlement_type)],
        ["课时数", displayValue(wageLock.lesson_count)],
        ["支付小时", displayValue(wageLock.pay_hours)],
        ["合计 JPY", formatCurrency(wageLock.total_jpy, "JPY")],
        ["合计 CNY", formatCurrency(wageLock.total_cny, "CNY")],
        ["锁定时间", formatDate(wageLock.locked_at)],
        ["作废时间", formatDate(wageLock.voided_at)],
      ])}
    </article>
  `;
}

function renderExpense(expense, paymentRequest) {
  if (!paymentRequest.paid_expense_id) {
    dom.expense.innerHTML = '<div class="state-text">无关联支出记录。</div>';
    return;
  }

  if (!expense) {
    dom.expense.innerHTML = '<div class="state-text">未找到关联支出记录。</div>';
    return;
  }

  dom.expense.innerHTML = `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(expense.id))}</strong>
        <span class="status-badge ${escapeAttribute(statusClass(expense.status))}">${escapeHtml(displayValue(expense.status))}</span>
      </div>
      ${paymentRequest.status === "reversed" || paymentRequest.status === "void" ? '<p class="section-note">本支付请求已撤销或作废；关联支出仍保留为审计记录，不代表当前有效支付。</p>' : ""}
      <p><a class="table-action-button" href="./expense-detail.html?id=${encodeURIComponent(expense.id)}">查看支出详情</a></p>
      ${renderDefinitionList([
        ["支出日期", formatDateOnly(expense.expense_date)],
        ["目标月份", formatMonth(expense.year_month)],
        ["支出分类", expenseCategoryLabel(expense.expense_category)],
        ["描述", displayValue(expense.description)],
        ["金额", formatCurrency(expense.amount, expense.currency)],
        ["JPY 金额", formatCurrency(expense.amount_jpy, "JPY")],
        ["CNY 金额", formatCurrency(expense.amount_cny, "CNY")],
        ["支出状态", displayValue(expense.status)],
        ["报销状态", reimbursementStatusLabel(expense.reimbursement_status)],
        ["创建时间", formatDate(expense.created_at)],
      ])}
    </article>
  `;
}

function renderAccount(accountId) {
  const account = accountById(accountId);
  if (!account) {
    dom.accountInfo.innerHTML = renderDefinitionList([
      ["账户", accountId ? "未知" : "未设置"],
    ]);
    return;
  }

  dom.accountInfo.innerHTML = renderDefinitionList([
    ["账户名称", displayValue(account.name)],
    ["账户编码", displayValue(account.account_code)],
    ["账户类型", displayValue(account.account_type)],
    ["币种", displayValue(account.currency)],
    ["公司账户", booleanLabel(account.is_company_account)],
    ["启用状态", booleanLabel(account.is_active)],
    ["business_entity_id", shortId(account.business_entity_id)],
  ]);
}

function renderTransaction(container, transaction, emptyText) {
  if (!transaction) {
    container.innerHTML = `<div class="state-text">${escapeHtml(emptyText)}</div>`;
    return;
  }

  container.innerHTML = `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(transactionTypeLabel(transaction.transaction_type))}</strong>
        <span class="status-badge ${Number(transaction.amount) < 0 ? "status-cancelled" : "status-active"}">${escapeHtml(formatCurrency(transaction.amount, transaction.currency))}</span>
      </div>
      ${renderDefinitionList([
        ["交易日期", formatDateOnly(transaction.transaction_date)],
        ["目标月份", formatMonth(transaction.year_month)],
        ["账户", accountNameById(transaction.account_id)],
        ["币种", displayValue(transaction.currency)],
        ["余额", formatCurrency(transaction.balance_after, transaction.currency)],
        ["related_table", displayValue(transaction.related_table)],
        ["related_id", shortId(transaction.related_id)],
        ["描述", displayValue(transaction.description)],
        ["备注", displayValue(transaction.note)],
        ["创建时间", formatDate(transaction.created_at)],
      ])}
    </article>
  `;
}

function renderReissueChain(paymentRequest, sourceRequests) {
  dom.chainSummary.innerHTML = renderDefinitionList([
    ["reissued_from", shortId(paymentRequest.reissued_from_payment_request_id)],
    ["replacement", shortId(paymentRequest.replacement_payment_request_id)],
    ["reissue_reason", displayValue(paymentRequest.reissue_reason)],
    ["reissued_at", formatDate(paymentRequest.reissued_at)],
  ]);

  const rows = sourceRequests || [];
  dom.chainCount.textContent = `${rows.length} 条`;
  dom.chainEmpty.classList.toggle("is-hidden", rows.length > 1);

  dom.chainRows.innerHTML = rows.map((row) => `
    <tr>
      <td><a class="table-action-button" href="./payment-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
      <td>${escapeHtml(shortId(row.id))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(paymentRequestStatusLabel(row.status))}</span></td>
      <td>${escapeHtml(formatMonth(row.request_month))}</td>
      <td class="number-cell">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td>${escapeHtml(formatDate(row.paid_at))}</td>
      <td>${escapeHtml(formatDate(row.reversed_at))}</td>
      <td>${escapeHtml(shortId(row.reissued_from_payment_request_id))}</td>
      <td>${escapeHtml(shortId(row.replacement_payment_request_id))}</td>
      <td>${escapeHtml(shortId(row.paid_expense_id))}</td>
      <td>${row.id === paymentRequest.id ? '<span class="status-badge status-neutral">当前</span>' : ""}</td>
    </tr>
  `).join("");
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

function findTransactionById(id) {
  return detailData?.transactions.find((item) => item.id === id) || null;
}

function accountById(id) {
  return detailData?.accounts.find((item) => item.id === id) || null;
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

function sourceTypeLabel(value) {
  return SOURCE_TYPE_LABELS[value] || displayValue(value);
}

function payeeTypeLabel(value) {
  return PAYEE_TYPE_LABELS[value] || displayValue(value);
}

function paymentRequestStatusLabel(value) {
  return PAYMENT_REQUEST_STATUS_LABELS[value] || displayValue(value);
}

function wageStatusLabel(value) {
  return WAGE_STATUS_LABELS[value] || displayValue(value);
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function expenseCategoryLabel(value) {
  return EXPENSE_CATEGORY_LABELS[value] || displayValue(value);
}

function reimbursementStatusLabel(value) {
  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function transactionTypeLabel(value) {
  return TRANSACTION_TYPE_LABELS[value] || displayValue(value);
}

function statusClass(value) {
  if (value === "paid" || value === "locked") {
    return "status-paid";
  }

  if (value === "reversed" || value === "void" || value === "cancelled") {
    return "status-cancelled";
  }

  if (value === "pending") {
    return "status-pending";
  }

  return "status-neutral";
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
