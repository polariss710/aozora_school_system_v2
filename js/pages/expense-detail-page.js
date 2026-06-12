import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createExpenseAttachmentMetadata,
  fetchExpenseDetailPage,
  reverseExpenseRecord,
  updateExpenseRecord,
} from "../api/expense-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const EXPENSE_STATUS_LABELS = {
  paid: "已支付",
  reversed: "已撤销",
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
  alipay: "支付宝",
  bank: "银行",
  bank_transfer: "银行转账",
  card: "信用卡",
  cash: "现金支付",
  wechat: "微信",
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
  expense_reversal: "支出撤销",
};

const SOURCE_TYPE_LABELS = {
  invoice: "发票",
  manual: "手工记录",
  manual_metadata: "手工摘要",
  other: "其他",
  receipt: "收据",
  statement: "对账单",
  teacher_wage: "老师工资",
};

const dom = {};
let detailData = null;
let isReverseSubmitting = false;
let isAttachmentSubmitting = false;
let isEditSubmitting = false;
const REVERSE_EXPENSE_FIELD_IDS = ["reversalDate", "reason", "confirmCheck"];
const ATTACHMENT_FIELD_IDS = ["fileName", "fileType", "fileSize", "sourceType", "note"];
const ATTACHMENT_SOURCE_TYPE_OPTIONS = ["manual_metadata", "receipt", "invoice", "statement", "other"];
const EDITABLE_EXPENSE_CATEGORIES = ["classroom", "other", "tax_accounting", "advertising", "software"];
const EDIT_PAYMENT_METHOD_OPTIONS = ["cash", "bank_transfer", "card", "alipay"];
const EDIT_RECEIPT_STATUS_OPTIONS = ["有", "无需收据", "待确认"];
const EDIT_REIMBURSEMENT_STATUS_OPTIONS = ["not_required", "pending"];
const EDIT_EXPENSE_FIELD_IDS = [
  "expenseDate",
  "businessEntity",
  "account",
  "expenseCategory",
  "amount",
  "description",
  "paymentMethod",
  "receiptStatus",
  "reimbursementStatus",
  "taxCategory",
  "exchangeRate",
  "note",
];

export function initExpenseDetailPage() {
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
  dom.actionStatus = document.querySelector("#expenseDetailActionStatus");
  dom.openEditExpenseButton = document.querySelector("#openEditExpenseButton");
  dom.openReverseExpenseButton = document.querySelector("#openReverseExpenseButton");
  dom.loadingState = document.querySelector("#expenseDetailLoadingState");
  dom.content = document.querySelector("#expenseDetailContent");
  dom.titleText = document.querySelector("#expenseDetailTitleText");
  dom.basicInfo = document.querySelector("#expenseDetailBasicInfo");
  dom.amountInfo = document.querySelector("#expenseDetailAmountInfo");
  dom.relatedInfo = document.querySelector("#expenseDetailRelatedInfo");
  dom.receiptInfo = document.querySelector("#expenseDetailReceiptInfo");
  dom.reversalCard = document.querySelector("#expenseDetailReversalCard");
  dom.reversalInfo = document.querySelector("#expenseDetailReversalInfo");
  dom.noteBlock = document.querySelector("#expenseDetailNoteBlock");
  dom.reimbursements = document.querySelector("#expenseDetailReimbursements");
  dom.openAttachmentDialogButton = document.querySelector("#openExpenseAttachmentDialogButton");
  dom.attachments = document.querySelector("#expenseDetailAttachments");
  dom.editDialog = document.querySelector("#editExpenseDialog");
  dom.editError = document.querySelector("#editExpenseError");
  dom.editDateInput = document.querySelector("#editExpenseDateInput");
  dom.editBusinessEntitySelect = document.querySelector("#editExpenseBusinessEntitySelect");
  dom.editAccountSelect = document.querySelector("#editExpenseAccountSelect");
  dom.editCategorySelect = document.querySelector("#editExpenseCategorySelect");
  dom.editAmountInput = document.querySelector("#editExpenseAmountInput");
  dom.editDescriptionInput = document.querySelector("#editExpenseDescriptionInput");
  dom.editPaymentMethodSelect = document.querySelector("#editExpensePaymentMethodSelect");
  dom.editReceiptStatusSelect = document.querySelector("#editExpenseReceiptStatusSelect");
  dom.editReimbursementStatusSelect = document.querySelector("#editExpenseReimbursementStatusSelect");
  dom.editTaxCategoryInput = document.querySelector("#editExpenseTaxCategoryInput");
  dom.editExchangeRateInput = document.querySelector("#editExpenseExchangeRateInput");
  dom.editNoteInput = document.querySelector("#editExpenseNoteInput");
  dom.editSubmitButton = document.querySelector("#editExpenseSubmitButton");
  dom.editCancelButton = document.querySelector("#editExpenseCancelButton");
  dom.attachmentDialog = document.querySelector("#expenseAttachmentDialog");
  dom.attachmentSummary = document.querySelector("#expenseAttachmentSummary");
  dom.attachmentError = document.querySelector("#expenseAttachmentError");
  dom.attachmentFileNameInput = document.querySelector("#expenseAttachmentFileNameInput");
  dom.attachmentFileTypeInput = document.querySelector("#expenseAttachmentFileTypeInput");
  dom.attachmentFileSizeInput = document.querySelector("#expenseAttachmentFileSizeInput");
  dom.attachmentSourceTypeSelect = document.querySelector("#expenseAttachmentSourceTypeSelect");
  dom.attachmentNoteInput = document.querySelector("#expenseAttachmentNoteInput");
  dom.attachmentSubmitButton = document.querySelector("#expenseAttachmentSubmitButton");
  dom.attachmentCancelButton = document.querySelector("#expenseAttachmentCancelButton");
  dom.reverseDialog = document.querySelector("#reverseExpenseDialog");
  dom.reverseSummary = document.querySelector("#reverseExpenseSummary");
  dom.reverseError = document.querySelector("#reverseExpenseError");
  dom.reverseDateInput = document.querySelector("#reverseExpenseDateInput");
  dom.reverseReasonInput = document.querySelector("#reverseExpenseReasonInput");
  dom.reverseConfirmCheck = document.querySelector("#reverseExpenseConfirmCheck");
  dom.reverseSubmitButton = document.querySelector("#reverseExpenseSubmitButton");
  dom.reverseCancelButton = document.querySelector("#reverseExpenseCancelButton");
}

function bindEvents() {
  dom.openEditExpenseButton.addEventListener("click", openEditDialog);
  dom.openReverseExpenseButton.addEventListener("click", openReverseDialog);
  dom.openAttachmentDialogButton.addEventListener("click", openAttachmentDialog);
  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditExpense);
  dom.editBusinessEntitySelect.addEventListener("change", () => {
    renderEditAccountOptions();
    updateEditReimbursementDefault();
    setEditFieldInvalid("businessEntity", false);
    hideEditErrorIfClean();
  });
  dom.editAccountSelect.addEventListener("change", () => {
    updateEditReimbursementDefault();
    setEditFieldInvalid("account", false);
    hideEditErrorIfClean();
  });
  for (const [input, fieldId] of [
    [dom.editDateInput, "expenseDate"],
    [dom.editBusinessEntitySelect, "businessEntity"],
    [dom.editAccountSelect, "account"],
    [dom.editCategorySelect, "expenseCategory"],
    [dom.editAmountInput, "amount"],
    [dom.editDescriptionInput, "description"],
    [dom.editPaymentMethodSelect, "paymentMethod"],
    [dom.editReceiptStatusSelect, "receiptStatus"],
    [dom.editReimbursementStatusSelect, "reimbursementStatus"],
    [dom.editTaxCategoryInput, "taxCategory"],
    [dom.editExchangeRateInput, "exchangeRate"],
    [dom.editNoteInput, "note"],
  ]) {
    input.addEventListener("input", () => {
      setEditFieldInvalid(fieldId, false);
      hideEditErrorIfClean();
    });
    input.addEventListener("change", () => {
      setEditFieldInvalid(fieldId, false);
      hideEditErrorIfClean();
    });
  }
  dom.attachmentCancelButton.addEventListener("click", closeAttachmentDialog);
  dom.attachmentSubmitButton.addEventListener("click", submitAttachmentMetadata);
  for (const [input, fieldId] of [
    [dom.attachmentFileNameInput, "fileName"],
    [dom.attachmentFileTypeInput, "fileType"],
    [dom.attachmentFileSizeInput, "fileSize"],
    [dom.attachmentSourceTypeSelect, "sourceType"],
    [dom.attachmentNoteInput, "note"],
  ]) {
    input.addEventListener("input", () => {
      setAttachmentFieldInvalid(fieldId, false);
      hideAttachmentErrorIfClean();
    });
    input.addEventListener("change", () => {
      setAttachmentFieldInvalid(fieldId, false);
      hideAttachmentErrorIfClean();
    });
  }
  dom.reverseCancelButton.addEventListener("click", closeReverseDialog);
  dom.reverseSubmitButton.addEventListener("click", submitReverseExpense);
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
  renderActionArea(data);
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
    ["税务分类", displayValue(expense.tax_category)],
  ]);

  dom.relatedInfo.innerHTML = renderDefinitionList([
    ["账户", accountNameById(expense.account_id)],
    ["支出 ID", shortId(expense.id)],
    ["app_type", displayValue(expense.app_type)],
  ]);

  dom.receiptInfo.innerHTML = renderDefinitionList([
    ["收据状态", displayValue(expense.receipt_status)],
    ["报销状态", reimbursementStatusLabel(expense.reimbursement_status, expense.expense_category)],
    ["报销备注", displayValue(expense.reimbursement_note)],
  ]);

  renderReversalInfo(expense);
  dom.noteBlock.textContent = displayValue(expense.note);
  renderReimbursements(data.reimbursementItems, data.reimbursements);
  renderAttachments(data.attachments);
}

function renderActionArea(data) {
  const { expense } = data;
  const status = expense?.status || "";
  const canEdit = canEditExpense(data);
  const canReverse = canReverseExpense(data);
  const canCreateAttachment = canCreateAttachmentMetadata(data);
  dom.actionStatus.className = `status-badge ${statusClass(status)}`;
  dom.actionStatus.textContent = expenseStatusLabel(status);
  dom.openEditExpenseButton.classList.toggle("is-hidden", !canEdit);
  dom.openEditExpenseButton.disabled = !canEdit;
  dom.openReverseExpenseButton.classList.toggle("is-hidden", !canReverse);
  dom.openReverseExpenseButton.disabled = !canReverse;
  dom.openAttachmentDialogButton.classList.toggle("is-hidden", !canCreateAttachment);
  dom.openAttachmentDialogButton.disabled = !canCreateAttachment;
}

function canEditExpense(data) {
  const expense = data?.expense;
  if (!expense) {
    return false;
  }

  return expense.status === "paid"
    && expense.app_type === "school"
    && expense.expense_category !== "teacher_wage"
    && !expense.salary_payment_id
    && !expense.reversed_at
    && !expense.reversal_account_transaction_id
    && expense.reimbursement_status !== "paid"
    && !(data.paymentRequests || []).length
    && !(data.reimbursementItems || []).length
    && !(data.reimbursements || []).some((row) => row.status === "paid");
}

function canReverseExpense(data) {
  const expense = data?.expense;
  if (!expense) {
    return false;
  }

  const hasPaidReimbursement = (data.reimbursements || []).some((row) => row.status === "paid");
  return expense.status === "paid"
    && expense.expense_category !== "teacher_wage"
    && !expense.reversed_at
    && !expense.reversal_account_transaction_id
    && expense.reimbursement_status !== "paid"
    && !hasPaidReimbursement;
}

function canCreateAttachmentMetadata(data) {
  const expense = data?.expense;
  return Boolean(expense?.id)
    && expense.app_type === "school"
    && expense.expense_category !== "teacher_wage";
}

function renderReversalInfo(expense) {
  const isReversed = expense.status === "reversed"
    || Boolean(expense.reversed_at)
    || Boolean(expense.reversal_account_transaction_id);
  dom.reversalCard.classList.toggle("is-hidden", !isReversed);

  if (!isReversed) {
    dom.reversalInfo.innerHTML = "";
    return;
  }

  dom.reversalInfo.innerHTML = renderDefinitionList([
    ["撤销时间", formatDate(expense.reversed_at)],
    ["撤销原因", displayValue(expense.reversal_reason)],
    ["反向流水", shortId(expense.reversal_account_transaction_id)],
  ]);
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
        ${reimbursement?.id ? `<p><a class="table-action-button" href="./reimbursement-detail.html?id=${encodeURIComponent(reimbursement.id)}">查看报销详情</a></p>` : ""}
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

function openEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  if (!detailData?.expense) {
    showMessage("error", "编辑对象不存在，请刷新后重试。");
    return;
  }

  if (!canEditExpense(detailData)) {
    showMessage("error", editNotAllowedMessage(detailData));
    return;
  }

  clearEditErrors();
  populateEditDialog(detailData.expense);
  setEditSubmitting(false);
  dom.editDialog.classList.remove("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "false");
}

function closeEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  dom.editDialog.classList.add("is-hidden");
  dom.editDialog.setAttribute("aria-hidden", "true");
}

function populateEditDialog(expense) {
  dom.editDateInput.value = expense.expense_date || "";
  dom.editAmountInput.value = expense.amount ?? "";
  dom.editDescriptionInput.value = expense.description || "";
  dom.editPaymentMethodSelect.value = EDIT_PAYMENT_METHOD_OPTIONS.includes(expense.payment_method)
    ? expense.payment_method
    : "";
  dom.editReceiptStatusSelect.value = EDIT_RECEIPT_STATUS_OPTIONS.includes(expense.receipt_status)
    ? expense.receipt_status
    : "待确认";
  dom.editReimbursementStatusSelect.value = EDIT_REIMBURSEMENT_STATUS_OPTIONS.includes(expense.reimbursement_status)
    ? expense.reimbursement_status
    : "pending";
  dom.editTaxCategoryInput.value = expense.tax_category || "";
  dom.editExchangeRateInput.value = expense.exchange_rate ?? "";
  dom.editNoteInput.value = expense.note || "";

  renderEditCategoryOptions();
  dom.editCategorySelect.value = EDITABLE_EXPENSE_CATEGORIES.includes(expense.expense_category)
    ? expense.expense_category
    : "";

  renderEditBusinessEntityOptions();
  dom.editBusinessEntitySelect.value = expense.business_entity_id || "";
  renderEditAccountOptions();
  dom.editAccountSelect.value = filteredEditAccounts().some((account) => account.id === expense.account_id)
    ? expense.account_id
    : "";
}

async function submitEditExpense() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();
  const payload = readEditExpensePayload();
  if (!payload) {
    return;
  }

  setEditSubmitting(true);

  try {
    await updateExpenseRecord(payload);
    setEditSubmitting(false);
    closeEditDialog();
    await loadExpenseDetail(payload.expenseId);
    showMessage("success", "支出记录已更新。");
  } catch (error) {
    console.error(error);
    showEditError(`编辑支出失败：${error.message || error}`, editFieldIdsForError(error.message || ""));
  } finally {
    setEditSubmitting(false);
  }
}

function readEditExpensePayload() {
  const expense = detailData?.expense;
  if (!expense?.id) {
    showEditError("编辑对象不存在，请关闭后重试。");
    return null;
  }

  if (!canEditExpense(detailData)) {
    showEditError(editNotAllowedMessage(detailData));
    return null;
  }

  const expenseDate = dom.editDateInput.value;
  if (!expenseDate) {
    showEditError("请选择支出日期。", ["expenseDate"]);
    return null;
  }

  const businessEntityId = dom.editBusinessEntitySelect.value;
  if (!businessEntityId) {
    showEditError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

  const accountId = dom.editAccountSelect.value;
  if (!accountId) {
    showEditError("请选择付款账户。", ["account"]);
    return null;
  }

  const account = detailData.lookups.accounts.find((item) => item.id === accountId);
  if (!account || account.is_active !== true || account.app_type !== "school") {
    showEditError("付款账户无效或已停用。", ["account"]);
    return null;
  }

  if (account.business_entity_id !== businessEntityId) {
    showEditError("付款账户与业务归属不一致。", ["account"]);
    return null;
  }

  if (!account.currency) {
    showEditError("付款账户缺少币种。", ["account"]);
    return null;
  }

  const expenseCategory = dom.editCategorySelect.value;
  if (!EDITABLE_EXPENSE_CATEGORIES.includes(expenseCategory)) {
    showEditError("请选择支出分类。", ["expenseCategory"]);
    return null;
  }

  const amount = Number(dom.editAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showEditError("支出金额必须大于 0。", ["amount"]);
    return null;
  }

  const description = dom.editDescriptionInput.value.trim();
  if (!description) {
    showEditError("支出内容不能为空。", ["description"]);
    return null;
  }

  const paymentMethod = dom.editPaymentMethodSelect.value;
  if (!EDIT_PAYMENT_METHOD_OPTIONS.includes(paymentMethod)) {
    showEditError("请选择支付方式。", ["paymentMethod"]);
    return null;
  }

  const receiptStatus = dom.editReceiptStatusSelect.value;
  if (!EDIT_RECEIPT_STATUS_OPTIONS.includes(receiptStatus)) {
    showEditError("收据状态无效。", ["receiptStatus"]);
    return null;
  }

  const reimbursementStatus = dom.editReimbursementStatusSelect.value;
  if (!EDIT_REIMBURSEMENT_STATUS_OPTIONS.includes(reimbursementStatus)) {
    showEditError("报销状态无效。", ["reimbursementStatus"]);
    return null;
  }

  const exchangeRateText = dom.editExchangeRateInput.value.trim();
  const parsedExchangeRate = exchangeRateText ? Number(exchangeRateText) : null;
  if (exchangeRateText && (!Number.isFinite(parsedExchangeRate) || parsedExchangeRate < 0)) {
    showEditError("汇率必须为空、0 或大于 0。", ["exchangeRate"]);
    return null;
  }
  const exchangeRate = parsedExchangeRate && parsedExchangeRate > 0 ? parsedExchangeRate : null;

  return {
    expenseId: expense.id,
    expenseDate,
    businessEntityId,
    accountId,
    expenseCategory,
    amount,
    description,
    currency: account.currency,
    exchangeRate,
    paymentMethod,
    taxCategory: dom.editTaxCategoryInput.value.trim(),
    receiptStatus,
    reimbursementStatus,
    note: dom.editNoteInput.value.trim(),
  };
}

function renderEditCategoryOptions() {
  const options = ['<option value="">请选择支出分类</option>'];
  for (const category of EDITABLE_EXPENSE_CATEGORIES) {
    options.push(`<option value="${escapeAttribute(category)}">${escapeHtml(expenseCategoryLabel(category))}</option>`);
  }
  dom.editCategorySelect.innerHTML = options.join("");
}

function renderEditBusinessEntityOptions() {
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of detailData.lookups.businessEntities.filter((item) => item.is_active !== false)) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(businessNameById(entity.id))}</option>`);
  }
  dom.editBusinessEntitySelect.innerHTML = options.join("");
}

function renderEditAccountOptions() {
  const selectedValue = dom.editAccountSelect.value;
  const options = ['<option value="">请选择付款账户</option>'];
  for (const account of filteredEditAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(editAccountLabel(account))}</option>`);
  }
  dom.editAccountSelect.innerHTML = options.join("");
  if (filteredEditAccounts().some((account) => account.id === selectedValue)) {
    dom.editAccountSelect.value = selectedValue;
  }
}

function filteredEditAccounts() {
  const businessEntityId = dom.editBusinessEntitySelect.value;
  return detailData.lookups.accounts.filter((account) => {
    if (account.is_active !== true || account.app_type !== "school") {
      return false;
    }
    if (businessEntityId && account.business_entity_id !== businessEntityId) {
      return false;
    }
    return true;
  });
}

function editAccountLabel(account) {
  const accountKind = account.is_company_account ? "公司账户" : "个人垫付账户";
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
    accountKind,
  ].filter(Boolean).join(" / ");
}

function updateEditReimbursementDefault() {
  const account = detailData.lookups.accounts.find((item) => item.id === dom.editAccountSelect.value);
  if (account && !detailData.expense?.reimbursement_status) {
    dom.editReimbursementStatusSelect.value = account.is_company_account ? "not_required" : "pending";
  }
}

function openAttachmentDialog() {
  if (isAttachmentSubmitting) {
    return;
  }

  if (!canCreateAttachmentMetadata(detailData)) {
    showMessage("error", attachmentNotAllowedMessage(detailData));
    return;
  }

  clearAttachmentErrors();
  dom.attachmentSummary.innerHTML = renderAttachmentSummary(detailData.expense);
  dom.attachmentFileNameInput.value = "";
  dom.attachmentFileTypeInput.value = "";
  dom.attachmentFileSizeInput.value = "";
  dom.attachmentSourceTypeSelect.value = "manual_metadata";
  dom.attachmentNoteInput.value = "";
  setAttachmentSubmitting(false);
  dom.attachmentDialog.classList.remove("is-hidden");
  dom.attachmentDialog.setAttribute("aria-hidden", "false");
}

function closeAttachmentDialog() {
  if (isAttachmentSubmitting) {
    return;
  }

  dom.attachmentDialog.classList.add("is-hidden");
  dom.attachmentDialog.setAttribute("aria-hidden", "true");
}

async function submitAttachmentMetadata() {
  if (isAttachmentSubmitting) {
    return;
  }

  clearAttachmentErrors();
  const payload = readAttachmentPayload();
  if (!payload) {
    return;
  }

  setAttachmentSubmitting(true);

  try {
    const result = await createExpenseAttachmentMetadata(payload);
    setAttachmentSubmitting(false);
    closeAttachmentDialog();
    await loadExpenseDetail(payload.expenseId);
    showMessage("success", `附件摘要已保存：${shortId(result.attachment_id)}。`);
  } catch (error) {
    console.error(error);
    showAttachmentError(`保存附件摘要失败：${error.message || error}`, attachmentFieldIdsForError(error.message || ""));
  } finally {
    setAttachmentSubmitting(false);
  }
}

function readAttachmentPayload() {
  const expense = detailData?.expense;
  if (!expense?.id) {
    showAttachmentError("支出记录不存在，请关闭后重试。");
    return null;
  }

  if (!canCreateAttachmentMetadata(detailData)) {
    showAttachmentError(attachmentNotAllowedMessage(detailData));
    return null;
  }

  const fileName = dom.attachmentFileNameInput.value.trim();
  if (!fileName) {
    showAttachmentError("附件文件名不能为空。", ["fileName"]);
    return null;
  }

  if (fileName.length > 255) {
    showAttachmentError("附件文件名过长。", ["fileName"]);
    return null;
  }

  const fileSizeText = dom.attachmentFileSizeInput.value.trim();
  const fileSize = fileSizeText ? Number(fileSizeText) : null;
  if (fileSizeText && (!Number.isSafeInteger(fileSize) || fileSize < 0)) {
    showAttachmentError("附件大小必须是 0 或正整数。", ["fileSize"]);
    return null;
  }

  const sourceType = dom.attachmentSourceTypeSelect.value;
  if (!ATTACHMENT_SOURCE_TYPE_OPTIONS.includes(sourceType)) {
    showAttachmentError("附件来源类型无效。", ["sourceType"]);
    return null;
  }

  return {
    expenseId: expense.id,
    fileName,
    fileType: dom.attachmentFileTypeInput.value.trim(),
    fileSize,
    sourceType,
    note: dom.attachmentNoteInput.value.trim(),
  };
}

function renderAttachmentSummary(expense) {
  return renderDefinitionList([
    ["支出日期", formatDateOnly(expense.expense_date)],
    ["分类", expenseCategoryLabel(expense.expense_category)],
    ["描述", displayValue(expense.description)],
    ["金额", formatCurrency(expense.amount, expense.currency)],
    ["支出状态", expenseStatusLabel(expense.status)],
  ]);
}

function attachmentNotAllowedMessage(data) {
  const expense = data?.expense;
  if (!expense) return "支出记录不存在，请刷新后重试。";
  if (expense.expense_category === "teacher_wage") return "老师工资支出不支持普通支出附件摘要。";
  return "当前支出不能新增附件摘要。";
}

function setAttachmentSubmitting(isSubmitting) {
  isAttachmentSubmitting = isSubmitting;
  dom.attachmentSubmitButton.disabled = isSubmitting;
  dom.attachmentCancelButton.disabled = isSubmitting;
  dom.attachmentSubmitButton.textContent = isSubmitting ? "保存中..." : "保存附件摘要";
}

function clearAttachmentErrors() {
  dom.attachmentError.textContent = "";
  dom.attachmentError.classList.add("is-hidden");
  for (const fieldId of ATTACHMENT_FIELD_IDS) {
    setAttachmentFieldInvalid(fieldId, false);
  }
}

function showAttachmentError(message, fieldIds = []) {
  dom.attachmentError.textContent = message;
  dom.attachmentError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setAttachmentFieldInvalid(fieldId, true);
  }
  dom.attachmentDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function attachmentFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("文件名")) fields.push("fileName");
  if (text.includes("大小")) fields.push("fileSize");
  if (text.includes("来源类型")) fields.push("sourceType");
  return fields;
}

function setAttachmentFieldInvalid(fieldId, invalid) {
  const field = dom.attachmentDialog.querySelector(`[data-expense-attachment-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideAttachmentErrorIfClean() {
  const hasInvalidField = Boolean(dom.attachmentDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.attachmentError.textContent = "";
    dom.attachmentError.classList.add("is-hidden");
  }
}

function openReverseDialog() {
  if (isReverseSubmitting) {
    return;
  }

  if (!detailData?.expense) {
    showMessage("error", "撤销对象不存在，请刷新后重试。");
    return;
  }

  if (!canReverseExpense(detailData)) {
    showMessage("error", reverseNotAllowedMessage(detailData));
    return;
  }

  clearReverseErrors();
  dom.reverseSummary.innerHTML = renderReverseSummary(detailData.expense);
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

async function submitReverseExpense() {
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
    await reverseExpenseRecord(payload);
    setReverseSubmitting(false);
    closeReverseDialog();
    await loadExpenseDetail(payload.expenseId);
    showMessage("success", "支出已撤销。");
  } catch (error) {
    console.error(error);
    showReverseError(`撤销支出失败：${error.message || error}`, reverseFieldIdsForError(error.message || ""));
  } finally {
    setReverseSubmitting(false);
  }
}

function readReversePayload() {
  const expense = detailData?.expense;
  if (!expense?.id) {
    showReverseError("撤销对象不存在，请关闭后重试。");
    return null;
  }

  if (!canReverseExpense(detailData)) {
    showReverseError(reverseNotAllowedMessage(detailData));
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
    expenseId: expense.id,
    reversalDate,
    reason: dom.reverseReasonInput.value.trim(),
  };
}

function renderReverseSummary(expense) {
  return renderDefinitionList([
    ["支出日期", formatDateOnly(expense.expense_date)],
    ["分类", expenseCategoryLabel(expense.expense_category)],
    ["描述", displayValue(expense.description)],
    ["金额", formatCurrency(expense.amount, expense.currency)],
    ["账户", accountNameById(expense.account_id)],
    ["报销状态", reimbursementStatusLabel(expense.reimbursement_status, expense.expense_category)],
  ]);
}

function reverseNotAllowedMessage(data) {
  const expense = data?.expense;
  if (!expense) return "撤销对象不存在，请刷新后重试。";
  if (expense.status === "reversed" || expense.reversed_at || expense.reversal_account_transaction_id) {
    return "该支出已撤销，不能重复撤销。";
  }
  if (expense.status !== "paid") return "只能撤销已支付支出。";
  if (expense.expense_category === "teacher_wage") return "老师工资支出不能通过普通支出撤销处理。";
  if (expense.reimbursement_status === "paid" || (data.reimbursements || []).some((row) => row.status === "paid")) {
    return "该支出已被报销确认，请先撤销报销记录。";
  }
  return "当前支出不能撤销。";
}

function editNotAllowedMessage(data) {
  const expense = data?.expense;
  if (!expense) return "编辑对象不存在，请刷新后重试。";
  if (expense.status === "reversed" || expense.reversed_at || expense.reversal_account_transaction_id) {
    return "该支出已撤销，不能编辑。";
  }
  if (expense.status !== "paid") return "只能编辑已支付支出。";
  if (expense.expense_category === "teacher_wage" || expense.salary_payment_id) {
    return "老师工资或工资支付来源支出不能通过普通支出编辑。";
  }
  if ((data.paymentRequests || []).length) {
    return "来源支付请求生成的支出不能通过普通支出编辑。";
  }
  if (expense.reimbursement_status === "paid" || (data.reimbursements || []).some((row) => row.status === "paid")) {
    return "该支出已被报销确认，不能编辑。";
  }
  if ((data.reimbursementItems || []).length) {
    return "该支出已进入报销链路，不能编辑。";
  }
  return "当前支出不能编辑。";
}

function setEditSubmitting(isSubmitting) {
  isEditSubmitting = isSubmitting;
  dom.editSubmitButton.disabled = isSubmitting;
  dom.editCancelButton.disabled = isSubmitting;
  dom.editSubmitButton.textContent = isSubmitting ? "保存中..." : "保存支出";
}

function clearEditErrors() {
  dom.editError.textContent = "";
  dom.editError.classList.add("is-hidden");
  for (const fieldId of EDIT_EXPENSE_FIELD_IDS) {
    setEditFieldInvalid(fieldId, false);
  }
}

function showEditError(message, fieldIds = []) {
  dom.editError.textContent = message;
  dom.editError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setEditFieldInvalid(fieldId, true);
  }
  dom.editDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function editFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("金额")) fields.push("amount");
  if (text.includes("支出日期")) fields.push("expenseDate");
  if (text.includes("支出分类") || text.includes("老师工资支出")) fields.push("expenseCategory");
  if (text.includes("支出内容")) fields.push("description");
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("付款账户") || text.includes("币种") || text.includes("更换付款账户")) fields.push("account");
  if (text.includes("汇率")) fields.push("exchangeRate");
  if (text.includes("支付方式")) fields.push("paymentMethod");
  if (text.includes("报销状态") || text.includes("已报销") || text.includes("报销链路")) fields.push("reimbursementStatus");
  if (text.includes("收据状态")) fields.push("receiptStatus");
  return fields;
}

function setEditFieldInvalid(fieldId, invalid) {
  const field = dom.editDialog.querySelector(`[data-edit-expense-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideEditErrorIfClean() {
  const hasInvalidField = Boolean(dom.editDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.editError.textContent = "";
    dom.editError.classList.add("is-hidden");
  }
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
  for (const fieldId of REVERSE_EXPENSE_FIELD_IDS) {
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
  const field = dom.reverseDialog.querySelector(`[data-reverse-expense-field="${fieldId}"]`);
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

function reimbursementStatusLabel(value, expenseCategory = "") {
  if (expenseCategory === "teacher_wage") {
    if (value === "pending") {
      return "工资垫付待清算";
    }
    if (value === "not_required") {
      return "无需清算（公司账户支付）";
    }
  }

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

function currentDate() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
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
