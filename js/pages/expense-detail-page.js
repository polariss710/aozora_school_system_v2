import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchExpenseDetailPage } from "../api/expense-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

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

const PAYMENT_METHOD_LABELS = {
  bank: "银行",
  bank_transfer: "银行转账",
  card: "银行卡",
};

const REIMBURSEMENT_STATUS_LABELS = {
  not_required: "无需报销",
  paid: "已报销",
  pending: "待报销",
};

const PAYMENT_REQUEST_STATUS_LABELS = {
  paid: "已支付",
  reversed: "已撤销",
  void: "已作废",
  pending: "待支付",
  cancelled: "已取消",
};

const TRANSACTION_TYPE_LABELS = {
  expense_adjust: "支出调整",
  payment_reversal: "支付撤销",
  reimbursement_out: "报销转出",
  reimbursement_in: "报销转入",
  income_adjust: "收入调整",
};

const SOURCE_TYPE_LABELS = {
  teacher_wage: "老师工资",
};

const dom = {};
let detailData = null;

export function initExpenseDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const expenseId = readExpenseId();
  if (!expenseId) {
    showMessage("error", "缺少支出记录 ID，请从支出记录一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadExpenseDetail(expenseId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#expenseDetailMessageArea");
  dom.loadingState = document.querySelector("#expenseDetailLoadingState");
  dom.content = document.querySelector("#expenseDetailContent");
  dom.titleText = document.querySelector("#expenseDetailTitleText");
  dom.basicInfo = document.querySelector("#expenseDetailBasicInfo");
  dom.amountInfo = document.querySelector("#expenseDetailAmountInfo");
  dom.relatedInfo = document.querySelector("#expenseDetailRelatedInfo");
  dom.receiptInfo = document.querySelector("#expenseDetailReceiptInfo");
  dom.noteBlock = document.querySelector("#expenseDetailNoteBlock");
  dom.paymentRequests = document.querySelector("#expenseDetailPaymentRequests");
  dom.directTransactions = document.querySelector("#expenseDetailDirectTransactions");
  dom.paymentTransactions = document.querySelector("#expenseDetailPaymentTransactions");
  dom.reimbursements = document.querySelector("#expenseDetailReimbursements");
  dom.attachments = document.querySelector("#expenseDetailAttachments");
}

function readExpenseId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadExpenseDetail(expenseId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载支出记录详情...");

  try {
    detailData = await fetchExpenseDetailPage(expenseId);
    renderExpenseDetail(detailData);
    setContentVisible(true);
    showMessage("success", "支出记录详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取支出记录详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderExpenseDetail(data) {
  const { expense } = data;
  dom.titleText.textContent = `${expenseCategoryLabel(expense.expense_category)} / ${displayValue(expense.description)}`;
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["支出日期", formatDateOnly(expense.expense_date)],
    ["目标月份", formatMonth(expense.year_month)],
    ["支出分类", expenseCategoryLabel(expense.expense_category)],
    ["描述", displayValue(expense.description)],
    ["状态", expenseStatusLabel(expense.status)],
    ["业务归属", businessNameById(expense.business_entity_id)],
    ["创建时间", formatDate(expense.created_at)],
    ["更新时间", formatDate(expense.updated_at)],
  ]);

  dom.amountInfo.innerHTML = renderDefinitionList([
    ["币种", displayValue(expense.currency)],
    ["原币金额", formatCurrency(expense.amount, expense.currency)],
    ["JPY 金额", formatCurrency(expense.amount_jpy, "JPY")],
    ["CNY 金额", formatCurrency(expense.amount_cny, "CNY")],
    ["汇率", displayValue(expense.exchange_rate)],
    ["支付方式", paymentMethodLabel(expense.payment_method)],
    ["经营支出", booleanLabel(expense.is_business_expense)],
    ["税务分类", displayValue(expense.tax_category)],
  ]);

  dom.relatedInfo.innerHTML = renderDefinitionList([
    ["账户", accountNameById(expense.account_id)],
    ["老师", teacherNameById(expense.teacher_id)],
    ["学生", studentNameById(expense.student_id)],
    ["salary_payment_id", shortId(expense.salary_payment_id)],
    ["支出 ID", shortId(expense.id)],
    ["app_type", displayValue(expense.app_type)],
  ]);

  dom.receiptInfo.innerHTML = renderDefinitionList([
    ["收据状态", displayValue(expense.receipt_status)],
    ["报销状态", reimbursementStatusLabel(expense.reimbursement_status)],
    ["报销备注", displayValue(expense.reimbursement_note)],
  ]);

  dom.noteBlock.textContent = displayValue(expense.note);
  renderPaymentRequests(data.paymentRequests);
  renderTransactions(dom.directTransactions, data.directTransactions, "无直接关联本支出的账户流水。");
  renderTransactions(dom.paymentTransactions, data.paymentTransactions, "无来源支付请求账户流水。");
  renderReimbursements(data.reimbursementItems, data.reimbursements);
  renderAttachments(data.attachments);
}

function renderPaymentRequests(requests) {
  if (!requests.length) {
    dom.paymentRequests.innerHTML = '<div class="state-text">无关联来源支付请求。</div>';
    return;
  }

  dom.paymentRequests.innerHTML = requests.map((request) => `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(request.id))}</strong>
        <span class="status-badge ${escapeAttribute(paymentRequestStatusClass(request.status))}">${escapeHtml(paymentRequestStatusLabel(request.status))}</span>
      </div>
      ${request.status === "reversed" || request.status === "void" ? '<p class="section-note">该来源支付请求已撤销或作废；关联支出仍保留为审计记录，不代表有效经营支出。</p>' : ""}
      ${renderDefinitionList([
        ["来源类型", sourceTypeLabel(request.source_type)],
        ["source_id", shortId(request.source_id)],
        ["请求月份", formatMonth(request.request_month)],
        ["收款方", displayValue(request.payee_name)],
        ["金额", formatCurrency(request.amount, request.currency)],
        ["paid_at", formatDate(request.paid_at)],
        ["reversed_at", formatDate(request.reversed_at)],
        ["撤销原因", displayValue(request.reversal_reason)],
        ["原扣款流水", shortId(request.paid_account_transaction_id)],
        ["反向流水", shortId(request.reversal_transaction_id)],
        ["reissued_from", shortId(request.reissued_from_payment_request_id)],
        ["replacement", shortId(request.replacement_payment_request_id)],
        ["reissue_reason", displayValue(request.reissue_reason)],
        ["reissued_at", formatDate(request.reissued_at)],
      ])}
    </article>
  `).join("");
}

function renderTransactions(container, transactions, emptyText) {
  if (!transactions.length) {
    container.innerHTML = `<div class="state-text">${escapeHtml(emptyText)}</div>`;
    return;
  }

  container.innerHTML = transactions.map((transaction) => `
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
    </article>
  `).join("");
}

function renderReimbursements(items, reimbursements) {
  if (!items.length) {
    dom.reimbursements.innerHTML = '<div class="state-text">无关联报销记录。</div>';
    return;
  }

  dom.reimbursements.innerHTML = items.map((item) => {
    const reimbursement = reimbursements.find((row) => row.id === item.reimbursement_id);
    return `
      <article class="detail-list-card">
        <div class="detail-list-card-header">
          <strong>${escapeHtml(shortId(item.reimbursement_id))}</strong>
          <span class="status-badge ${escapeAttribute(statusClass(reimbursement?.status))}">${escapeHtml(displayValue(reimbursement?.status))}</span>
        </div>
        ${renderDefinitionList([
          ["报销明细金额", formatCurrency(item.amount, reimbursement?.currency)],
          ["明细备注", displayValue(item.note)],
          ["报销日期", formatDateOnly(reimbursement?.reimbursement_date)],
          ["报销月份", formatMonth(reimbursement?.year_month)],
          ["报销总额", formatCurrency(reimbursement?.amount, reimbursement?.currency)],
          ["币种", displayValue(reimbursement?.currency)],
          ["转出账户", accountNameById(reimbursement?.from_account_id)],
          ["转入账户", accountNameById(reimbursement?.to_account_id)],
          ["报销备注", displayValue(reimbursement?.note)],
          ["创建时间", formatDate(reimbursement?.created_at)],
        ])}
      </article>
    `;
  }).join("");
}

function renderAttachments(attachments) {
  if (!attachments.length) {
    dom.attachments.innerHTML = '<div class="state-text">无附件记录。</div>';
    return;
  }

  dom.attachments.innerHTML = `
    <p class="section-note">附件 ${attachments.length} 个。第一版仅显示文件摘要，不提供下载、预览、上传、删除或 OCR。</p>
    ${attachments.map((attachment) => `
      <article class="detail-list-card">
        <div class="detail-list-card-header">
          <strong>${escapeHtml(displayValue(attachment.file_name))}</strong>
          <span class="status-badge status-neutral">${escapeHtml(displayFileSize(attachment.file_size))}</span>
        </div>
        ${renderDefinitionList([
          ["文件类型", displayValue(attachment.file_type)],
          ["来源类型", displayValue(attachment.source_type)],
          ["备注", displayValue(attachment.note)],
          ["创建时间", formatDate(attachment.created_at)],
        ])}
      </article>
    `).join("")}
  `;
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
  return entity ? safeText(entity.name) || "未设置" : id ? "未知" : "未设置";
}

function accountNameById(id) {
  const account = detailData?.lookups.accounts.find((item) => item.id === id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function teacherNameById(id) {
  const teacher = detailData?.lookups.teachers.find((item) => item.id === id);
  if (!teacher) {
    return id ? "未知" : "未设置";
  }

  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function studentNameById(id) {
  const student = detailData?.lookups.students.find((item) => item.id === id);
  if (!student) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(student.display_name || student.name) || "未设置";
  const code = safeText(student.student_code);
  return code ? `${name} / ${code}` : name;
}

function expenseCategoryLabel(value) {
  return EXPENSE_CATEGORY_LABELS[value] || displayValue(value);
}

function paymentMethodLabel(value) {
  return PAYMENT_METHOD_LABELS[value] || displayValue(value);
}

function expenseStatusLabel(value) {
  return EXPENSE_STATUS_LABELS[value] || displayValue(value);
}

function reimbursementStatusLabel(value) {
  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function paymentRequestStatusLabel(value) {
  return PAYMENT_REQUEST_STATUS_LABELS[value] || displayValue(value);
}

function sourceTypeLabel(value) {
  return SOURCE_TYPE_LABELS[value] || displayValue(value);
}

function transactionTypeLabel(value) {
  return TRANSACTION_TYPE_LABELS[value] || displayValue(value);
}

function statusClass(value) {
  if (value === "paid") {
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

function paymentRequestStatusClass(value) {
  return statusClass(value);
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

function displayFileSize(value) {
  const size = Number(value);
  if (!Number.isFinite(size)) {
    return "-";
  }

  if (size >= 1024 * 1024) {
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  }

  if (size >= 1024) {
    return `${(size / 1024).toFixed(1)} KB`;
  }

  return `${size} B`;
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
