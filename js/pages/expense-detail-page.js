import {
  initSchoolAuth,
  isActiveAdmin,
  isLoggedIn,
  requireActiveAdminForCashConfirmation,
} from "../auth.js";
import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import {
  fetchExpenseDetailPage,
  fetchFixedCardSchedulePreview,
  fetchSchoolFixedRouteCardsViaFunction,
  requestCashExpenseConfirmation,
  reverseExpenseRecord,
  updateExpenseRecord,
  voidUnsubmittedTeacherWageExpenseRecord,
} from "../api/expense-detail-api.js?v=fixed-card-preview-dedup-20260902-1";
import { fetchSchoolEligibleCashAccountsViaFunction } from "../api/payment-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";
import {
  currentJapanDate,
  monthFromUrl,
  updateMonthScopedNavigation,
} from "../utils/month-filter.js";

const EXPENSE_STATUS_LABELS = {
  paid: "已支付",
  pending: "待支付",
  reversed: "已撤销",
  cancelled: "已取消",
  void: "已作废",
  voided: "已作废",
};

const EXPENSE_CATEGORY_LABELS = {
  advertising: "广告宣传",
  classroom: "教室费用",
  other: "其他",
  software: "软件服务",
  tax_accounting: "税务会计",
  teacher_wage: "老师工资",
};

// 允许走固定信用卡路线的支出分类。业务约定：只有教室租金这类大额、需要「刷卡进
// 账单、次月还款」的支出才走信用卡；其余小额支出直接用公司卡走即时账户路线。
//
// 与 School 侧 prepare RPC 的判定必须保持一致，此处仅用于界面显隐。
const FIXED_CARD_ALLOWED_CATEGORY = "classroom";

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
  manual_school: "手工登记（School 直接支付）",
  manual_cash: "手工登记（Cash 审批）",
  manual_metadata: "手工摘要",
  other: "其他",
  receipt: "收据",
  statement: "对账单",
  teacher_wage: "老师工资",
};

const dom = {};
let detailData = null;
let isReverseSubmitting = false;
let isEditSubmitting = false;
let isCashRequestSubmitting = false;
let cashEligibleAccounts = [];
let hasLoadedCashEligibleAccounts = false;
let cashFixedRouteCards = [];
let hasLoadedCashFixedRouteCards = false;
let cashFixedSchedulePreview = null;
let cashFixedSchedulePreviewSeq = 0;
let cashFixedSchedulePreviewKey = "";
const REVERSE_EXPENSE_FIELD_IDS = ["reversalDate", "reason", "confirmCheck"];
const EDITABLE_EXPENSE_CATEGORIES = ["classroom", "other", "tax_accounting", "advertising", "software"];
const EDIT_PAYMENT_METHOD_OPTIONS = ["cash", "bank_transfer", "card", "alipay"];
const EDIT_RECEIPT_STATUS_OPTIONS = ["有", "无需收据", "待确认"];
const EDIT_REIMBURSEMENT_STATUS_OPTIONS = ["not_required", "pending"];
const EDIT_EXPENSE_FIELD_IDS = [
  "expenseDate",
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

export async function initExpenseDetailPage() {
  cacheDom();
  await initSchoolAuth();
  bindEvents();
  configureMonthScopedLinks();

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
  dom.openCashExpenseRequestButton = document.querySelector("#openCashExpenseRequestButton");
  dom.voidTeacherWageExpenseButton = document.querySelector("#voidTeacherWageExpenseButton");
  dom.returnLink = document.querySelector('.reimbursement-detail-actions a[href="./expense.html"]');
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
  dom.systemInfo = document.querySelector("#expenseDetailSystemInfo");
  dom.reimbursements = document.querySelector("#expenseDetailReimbursements");
  dom.attachments = document.querySelector("#expenseDetailAttachments");
  dom.editDialog = document.querySelector("#editExpenseDialog");
  dom.editError = document.querySelector("#editExpenseError");
  dom.editDateInput = document.querySelector("#editExpenseDateInput");
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
  dom.reverseDialog = document.querySelector("#reverseExpenseDialog");
  dom.reverseSummary = document.querySelector("#reverseExpenseSummary");
  dom.reverseError = document.querySelector("#reverseExpenseError");
  dom.reverseDateInput = document.querySelector("#reverseExpenseDateInput");
  dom.reverseReasonInput = document.querySelector("#reverseExpenseReasonInput");
  dom.reverseConfirmCheck = document.querySelector("#reverseExpenseConfirmCheck");
  dom.reverseSubmitButton = document.querySelector("#reverseExpenseSubmitButton");
  dom.reverseCancelButton = document.querySelector("#reverseExpenseCancelButton");
  dom.cashExpenseRequestDialog = document.querySelector("#cashExpenseRequestDialog");
  dom.cashExpenseRequestError = document.querySelector("#cashExpenseRequestError");
  dom.cashExpenseRequestSummary = document.querySelector("#cashExpenseRequestSummary");
  dom.cashExpenseActualAmountInput = document.querySelector("#cashExpenseActualAmountInput");
  dom.cashExpenseActualDateInput = document.querySelector("#cashExpenseActualDateInput");
  dom.cashExpenseActualCurrencySelect = document.querySelector("#cashExpenseActualCurrencySelect");
  dom.cashExpenseAccountSelect = document.querySelector("#cashExpenseAccountSelect");
  dom.cashExpensePaymentRouteSelect = document.querySelector("#cashExpensePaymentRouteSelect");
  dom.cashExpensePaymentRouteField = document.querySelector('[data-cash-expense-field="paymentRoute"]');
  dom.cashExpenseCardSelect = document.querySelector("#cashExpenseCardSelect");
  dom.cashExpenseActualDateLabel = document.querySelector("#cashExpenseActualDateLabel");
  dom.cashExpenseNoteInput = document.querySelector("#cashExpenseNoteInput");
  dom.cashExpenseRequestPreview = document.querySelector("#cashExpenseRequestPreview");
  dom.cashExpenseRequestSubmitButton = document.querySelector("#cashExpenseRequestSubmitButton");
  dom.cashExpenseRequestCancelButton = document.querySelector("#cashExpenseRequestCancelButton");
}

function bindEvents() {
  dom.openEditExpenseButton.addEventListener("click", openEditDialog);
  dom.openCashExpenseRequestButton.addEventListener("click", openCashExpenseRequestDialog);
  dom.voidTeacherWageExpenseButton.addEventListener("click", voidUnsubmittedTeacherWageExpenseFromDetail);
  dom.openReverseExpenseButton.addEventListener("click", openReverseDialog);
  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditExpense);
  dom.editAccountSelect.addEventListener("change", () => {
    updateEditReimbursementDefault();
    setEditFieldInvalid("account", false);
    hideEditErrorIfClean();
  });
  for (const [input, fieldId] of [
    [dom.editDateInput, "expenseDate"],
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
  dom.cashExpenseRequestCancelButton.addEventListener("click", closeCashExpenseRequestDialog);
  dom.cashExpenseRequestSubmitButton.addEventListener("click", submitCashExpenseRequest);
  for (const [input, fieldId] of [
    [dom.cashExpensePaymentRouteSelect, "paymentRoute"],
    [dom.cashExpenseActualAmountInput, "actualAmount"],
    [dom.cashExpenseActualDateInput, "actualDate"],
    [dom.cashExpenseActualCurrencySelect, "actualCurrency"],
    [dom.cashExpenseAccountSelect, "cashAccount"],
    [dom.cashExpenseCardSelect, "cardInstrument"],
    [dom.cashExpenseNoteInput, "note"],
  ]) {
    const onChange = async () => {
      setCashExpenseFieldInvalid(fieldId, false);
      hideCashExpenseRequestErrorIfClean();
      if (input === dom.cashExpenseActualCurrencySelect) {
        renderCashExpenseAccountOptions();
      }
      // 卡列表在切到固定信用卡时才拉取，不放在打开对话框的主路径上。
      //
      // 默认路线是即时账户，固定卡目前又只有教室租金一个场景；若在打开时就 await
      // 卡列表，一次 Cash 侧超时会把即时路线一起卡住，读取失败还会在与卡无关的
      // 界面上弹出「信用卡读取失败」。
      if (input === dom.cashExpensePaymentRouteSelect) {
        updateCashExpenseRouteMode();
        if (currentCashExpenseRoute() === "fixed_credit_card") {
          await ensureCashFixedRouteCards();
          renderCashExpenseCardOptions();
        }
      }
      updateCashExpenseRequestPreview();
      // 目标固定月只取决于卡与刷卡日，其余字段变化不必重新拉取。
      if (
        input === dom.cashExpensePaymentRouteSelect
        || input === dom.cashExpenseCardSelect
        || input === dom.cashExpenseActualDateInput
      ) {
        await refreshCashFixedSchedulePreview();
      }
    };
    input.addEventListener("input", onChange);
    input.addEventListener("change", onChange);
  }
}

function configureMonthScopedLinks() {
  const month = monthFromUrl();
  if (!month) {
    return;
  }

  const params = new URLSearchParams(window.location.search);
  params.delete("id");
  if (dom.returnLink) {
    dom.returnLink.href = `./expense.html?${params.toString()}`;
  }
  updateMonthScopedNavigation(month);
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
  dom.titleText.textContent = `${expenseObjectName(expense)} / ${expenseCategoryLabel(expense.expense_category)}`;
  renderAmountSummary(expense);
  dom.basicInfo.innerHTML = renderDefinitionList([
    ["支出对象 / 来源", expenseObjectName(expense)],
    ["分类", expenseCategoryLabel(expense.expense_category)],
    ["记账月份", formatMonth(expense.year_month)],
    ["实际支付日", actualPaymentDateLabel(expense)],
    ["支出内容", displayValue(expense.description)],
    ["状态", expenseStatusLabel(expense.status)],
  ]);

  dom.relatedInfo.innerHTML = renderNonEmptyDefinitionList([
    ["老师", teacherNameForDisplay(expense.teacher_id)],
    ["支付对象", safeText(expense.payee_name_snapshot)],
    ["账户", accountNameForDisplay(expense.account_id)],
    ["业务来源", businessSourceLabel(expense)],
  ], "无关联对象。");

  dom.receiptInfo.innerHTML = renderDefinitionList([
    ["附件", attachmentSummaryLabel(data.attachments)],
    ["收据状态", displayValue(expense.receipt_status)],
    ["报销状态", reimbursementStatusLabel(expense.reimbursement_status, expense.expense_category)],
    ["报销备注", displayValue(expense.reimbursement_note)],
  ]);

  renderReversalInfo(expense);
  renderNoteBlock(expense.note);
  renderSystemInfo(data);
  renderReimbursements(data.reimbursementItems, data.reimbursements);
  renderAttachments(data.attachments);
}

function renderAmountSummary(expense) {
  const cashStatus = expense.cash_transaction_id && !expense.cash_request_status
    ? "synced"
    : expense.cash_request_status;
  dom.amountInfo.innerHTML = `
    <div class="expense-detail-main-amount">${escapeHtml(formatCurrency(expense.amount, expense.currency))}</div>
    <div class="expense-detail-main-meta">
      <span>${escapeHtml(displayValue(expense.currency))}</span>
      <span class="status-badge ${escapeAttribute(cashRequestStatusClass(cashStatus))}">${escapeHtml(cashRequestStatusLabel(cashStatus))}</span>
    </div>
    ${renderDefinitionList([
      ["JPY 金额", formatCurrency(expense.amount_jpy, "JPY")],
      ["CNY 金额", formatCurrency(expense.amount_cny, "CNY")],
      ["Cash 支付金额", formatCashPaymentAmount(expense)],
      ["Cash 同步时间", formatDate(expense.cash_synced_at)],
    ])}
  `;
}

function renderNoteBlock(note) {
  const text = safeText(note);
  const businessNote = isSystemMigrationNote(text) ? "" : text;
  if (!businessNote) {
    dom.noteBlock.innerHTML = '<span class="expense-note-empty">无业务备注</span>';
    return;
  }

  const needsCollapse = businessNote.length > 120 || businessNote.includes("\n");
  if (!needsCollapse) {
    dom.noteBlock.textContent = businessNote;
    return;
  }

  dom.noteBlock.innerHTML = `
    <div class="expense-note-preview">${escapeHtml(notePreview(businessNote))}</div>
    <details class="expense-note-disclosure">
      <summary>
        <span class="summary-closed">展开完整备注</span>
        <span class="summary-open">收起完整备注</span>
      </summary>
      <div class="expense-note-full-text">${escapeHtml(businessNote)}</div>
    </details>
  `;
}

function renderSystemInfo(data) {
  const { expense } = data;
  dom.systemInfo.innerHTML = `
    <article class="detail-list-card">
      <h3>记录与来源</h3>
      ${renderDefinitionList([
        ["支出 ID", shortId(expense.id)],
        ["app_type", displayValue(expense.app_type)],
        ["source_type", sourceTypeLabel(expense.source_type)],
        ["source_id", shortId(expense.source_id)],
        ["cash_creation_event_id", shortId(expense.cash_creation_event_id)],
        ["created_by_user_id", shortId(expense.created_by_user_id)],
        ["salary_payment_id", shortId(expense.salary_payment_id)],
        ["teacher_id", shortId(expense.teacher_id)],
        ["student_id", shortId(expense.student_id)],
        ["account_id", shortId(expense.account_id)],
        ["payment_method", paymentMethodLabel(expense.payment_method)],
        ["payee_name_snapshot", displayValue(expense.payee_name_snapshot)],
        ["is_business_expense", booleanLabel(expense.is_business_expense)],
        ["税务分类", displayValue(expense.tax_category)],
        ["汇率", displayValue(expense.exchange_rate)],
        ["created_at", formatDate(expense.created_at)],
        ["updated_at", formatDate(expense.updated_at)],
      ])}
    </article>
    <article class="detail-list-card">
      <h3>Cash 链路</h3>
      ${renderDefinitionList([
        ["cash_request_id", shortId(expense.cash_request_id)],
        ["cash_request_event_id", shortId(expense.cash_request_event_id)],
        ["cash_request_attempt_no", displayValue(expense.cash_request_attempt_no)],
        ["cash_request_status", cashRequestStatusLabel(expense.cash_request_status)],
        ["cash_transaction_id", shortId(expense.cash_transaction_id)],
        ["cash_requested_at", formatDate(expense.cash_requested_at)],
        ["cash_synced_at", formatDate(expense.cash_synced_at)],
        ["cash_payment_amount", formatCashPaymentAmount(expense)],
        ["cash_error_message", displayValue(expense.cash_error_message)],
      ])}
      ${renderSystemTextBlock("Cash 原始备注", expense.cash_payment_note)}
    </article>
    <article class="detail-list-card">
      <h3>备注原文</h3>
      ${isSystemMigrationNote(expense.note) ? renderSystemTextBlock("迁移说明", expense.note) : renderSystemTextBlock("支出备注", expense.note)}
      ${renderSystemTextBlock("报销备注", expense.reimbursement_note)}
    </article>
  `;
}

function renderActionArea(data) {
  const { expense } = data;
  const status = expense?.status || "";
  const canEdit = canEditExpense(data);
  const canRequestCash = canRequestCashExpense(data);
  const canVoidTeacherWageExpense = canVoidUnsubmittedTeacherWageExpense(data);
  const canReverse = canReverseExpense(data);
  dom.actionStatus.className = `status-badge ${statusClass(status)}`;
  dom.actionStatus.textContent = expenseStatusLabel(status);
  dom.openEditExpenseButton.classList.toggle("is-hidden", !canEdit);
  dom.openEditExpenseButton.disabled = !canEdit;
  dom.openCashExpenseRequestButton.classList.toggle("is-hidden", !canRequestCash);
  dom.openCashExpenseRequestButton.disabled = !canRequestCash;
  dom.voidTeacherWageExpenseButton.classList.toggle("is-hidden", !canVoidTeacherWageExpense);
  dom.voidTeacherWageExpenseButton.disabled = !canVoidTeacherWageExpense;
  dom.openReverseExpenseButton.classList.toggle("is-hidden", !canReverse);
  dom.openReverseExpenseButton.disabled = !canReverse;
}

function canEditExpense(data) {
  const expense = data?.expense;
  if (!expense) {
    return false;
  }
  if (cashExpenseProtectionMessage(data)) {
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
  if (cashExpenseProtectionMessage(data)) {
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

function canRequestCashExpense(data) {
  const expense = data?.expense;
  if (!isActiveAdmin()) return false;
  if (!expense?.id) return false;
  if (expense.app_type !== "school") return false;
  if (!["manual_cash", "teacher_wage"].includes(expense.source_type)) return false;
  if (expense.status !== "pending") return false;
  if (expense.reversed_at || expense.reversal_account_transaction_id) return false;
  if (expense.cash_transaction_id) return false;
  return !["pending", "approved", "synced"].includes(expense.cash_request_status || "");
}

function canVoidUnsubmittedTeacherWageExpense(data) {
  const expense = data?.expense;
  const hasNoCashRequest = !expense?.cash_request_status && !expense?.cash_request_id;
  const hasRejectedCashRequest = expense?.cash_request_status === "rejected";
  return Boolean(expense?.id)
    && expense.app_type === "school"
    && expense.source_type === "teacher_wage"
    && expense.status === "pending"
    && !expense.cancelled_at
    && (hasNoCashRequest || hasRejectedCashRequest)
    && !expense.cash_transaction_id;
}

function voidTeacherWageExpenseNotAllowedMessage(data) {
  const expense = data?.expense;
  if (!expense) return "支出记录不存在，请刷新后重试。";
  if (expense.app_type !== "school") return "只能作废 School 支出记录。";
  if (expense.source_type !== "teacher_wage") return "本流程只允许作废老师工资支出记录。";
  if (expense.status === "cancelled" || expense.cancelled_at) return "该老师工资支出记录已作废。";
  if (expense.status !== "pending") return "只有待支付且未生成 Cash 流水的老师工资支出记录可以作废。";
  if (expense.cash_transaction_id) return "该支出记录已有 Cash transaction，不能作废。";
  if (expense.cash_request_status === "rejected") return "";
  if (expense.cash_request_status || expense.cash_request_id) return "该支出记录已有未终止 Cash 请求，不能在 School 侧直接作废。";
  return "该支出记录当前状态不能作废。";
}

function cashRequestNotAllowedMessage(data) {
  const expense = data?.expense;
  if (!expense) return "支出记录不存在，请刷新后重试。";
  if (!isActiveAdmin()) return "仅已启用的管理员账号可以提交 Cash。";
  if (expense.app_type !== "school") return "只能提交 School 支出记录。";
  if (!["manual_cash", "teacher_wage"].includes(expense.source_type)) return "该支出来源不允许提交 Cash。";
  if (expense.status !== "pending") return "只有待支付支出记录可以提交 Cash 支付确认。";
  if (expense.reversed_at || expense.reversal_account_transaction_id) return "已撤销支出不能提交 Cash 支付确认。";
  if (expense.cash_transaction_id) return "该支出记录已经有 Cash transaction。";
  if (expense.cash_request_status === "pending") return "该支出记录已有待确认 Cash request。";
  if (expense.cash_request_status === "approved" || expense.cash_request_status === "synced") return "该支出记录已同步到 Cash。";
  return "";
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
    <p class="section-note">附件新增功能已退役；以下仅保留 ${attachments.length} 个历史摘要，不提供上传、下载、预览、替换、删除或 OCR。</p>
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

  const businessEntityId = expense.business_entity_id;

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
    showEditError("付款账户与内部范围不一致。", ["account"]);
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
    expectedUpdatedAt: expense.updated_at,
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
  const businessEntityId = detailData.expense.business_entity_id;
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

async function openCashExpenseRequestDialog() {
  if (isCashRequestSubmitting) {
    return;
  }

  if (!canRequestCashExpense(detailData)) {
    showMessage("error", cashRequestNotAllowedMessage(detailData));
    return;
  }

  if (
    !requireActiveAdminForCashConfirmation((_type, message) => {
      showMessage("error", message);
    })
  ) {
    return;
  }

  clearCashExpenseRequestErrors();
  await ensureCashEligibleAccounts();
  const expense = detailData.expense;
  dom.cashExpenseRequestSummary.innerHTML = renderCashExpenseRequestSummary(expense);
  dom.cashExpenseActualAmountInput.value = expense.amount ?? "";
  dom.cashExpenseActualDateInput.value = currentJapanDate();
  dom.cashExpenseActualCurrencySelect.value = expense.currency || "JPY";
  dom.cashExpenseNoteInput.value = [
    expenseCategoryLabel(expense.expense_category),
    expense.payee_name_snapshot,
    expense.year_month,
    expense.description,
  ].filter(Boolean).join(" / ");
  // 每次打开都回到即时账户路线。固定信用卡是少数场景（目前只有教室租金），
  // 让它保持上次的选择容易导致下一笔支出被误提交成固定项，而固定项的撤销
  // 要经过 Cash 侧一整套删除保护，代价远高于多点一次下拉。
  // 固定信用卡路线只对教室费用开放。业务约定：只有教室租金这类大额、需要「预扣
  // 到账单、次月还款」的支出才走信用卡；其余小额支出直接用公司卡走即时路线。
  //
  // 这里只是界面镜像。权威判定在 School 侧的 prepare RPC——UI 挡不住直接调 Edge
  // 的调用方，而一旦把老师工资之类提成固定项，那笔钱会挂到信用卡账单上，与实际
  // 支付方式对不上，且撤销要经过 Cash 侧整套删除保护。
  const allowsFixedCardRoute = expense.expense_category === FIXED_CARD_ALLOWED_CATEGORY;
  dom.cashExpensePaymentRouteField.hidden = !allowsFixedCardRoute;
  dom.cashExpensePaymentRouteSelect.value = "immediate_account";
  // 丢弃上一次打开时留下的预览，并让在途请求的结果失效——否则切换支出记录后，
  // 前一条记录的固定月可能因响应晚到而显示在这一条上。
  cashFixedSchedulePreviewSeq += 1;
  cashFixedSchedulePreviewKey = "";
  cashFixedSchedulePreview = null;
  renderCashExpenseAccountOptions();
  updateCashExpenseRouteMode();
  updateCashExpenseRequestPreview();
  setCashRequestSubmitting(false);
  dom.cashExpenseRequestDialog.classList.remove("is-hidden");
  dom.cashExpenseRequestDialog.setAttribute("aria-hidden", "false");
}

function closeCashExpenseRequestDialog() {
  if (isCashRequestSubmitting) {
    return;
  }

  dom.cashExpenseRequestDialog.classList.add("is-hidden");
  dom.cashExpenseRequestDialog.setAttribute("aria-hidden", "true");
}

async function voidUnsubmittedTeacherWageExpenseFromDetail() {
  if (!canVoidUnsubmittedTeacherWageExpense(detailData)) {
    showMessage("error", voidTeacherWageExpenseNotAllowedMessage(detailData));
    return;
  }

  if (!isLoggedIn()) {
    showMessage("error", "请先重新登录后再作废支出记录。");
    return;
  }

  const expense = detailData.expense;
  const reason = window.prompt(
    "作废老师工资支出记录\n\n此操作只适用于尚未提交 Cash 的老师工资支出记录。作废后可从老师工资快照重新生成支出记录。已提交 Cash 或已支付的支出记录不能作废。\n\n作废理由（可选）：",
    ""
  );
  if (reason === null) {
    return;
  }

  if (!window.confirm("确认作废这条未提交 Cash 的老师工资支出记录？原记录会保留为已取消，不会删除数据。")) {
    return;
  }

  try {
    const result = await voidUnsubmittedTeacherWageExpenseRecord({
      expenseId: expense.id,
      reason: reason.trim(),
    });
    await loadExpenseDetail(expense.id);
    showMessage("success", `老师工资支出记录已作废：${shortId(result.expense_id)}。可回到老师工资详情重新生成。`);
  } catch (error) {
    showMessage("error", `作废老师工资支出记录失败：${error.message || error}`);
  }
}

async function ensureCashEligibleAccounts() {
  if (hasLoadedCashEligibleAccounts) {
    return;
  }

  try {
    cashEligibleAccounts = await fetchSchoolEligibleCashAccountsViaFunction();
    hasLoadedCashEligibleAccounts = true;
  } catch (error) {
    cashEligibleAccounts = [];
    hasLoadedCashEligibleAccounts = false;
    showCashExpenseRequestError(`Cash 支付账户读取失败：${error.message || error}`, ["cashAccount"]);
  }
}

function renderCashExpenseAccountOptions() {
  const currency = dom.cashExpenseActualCurrencySelect.value || "JPY";
  const selectedValue = dom.cashExpenseAccountSelect.value;
  const accounts = cashEligibleAccounts.filter((account) => account.currency === currency);
  const options = ['<option value="">请选择 Cash 支付账户</option>'];
  for (const account of accounts) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(cashAccountLabel(account))}</option>`);
  }
  dom.cashExpenseAccountSelect.innerHTML = options.join("");

  if (accounts.some((account) => account.id === selectedValue)) {
    dom.cashExpenseAccountSelect.value = selectedValue;
  } else if (accounts.length === 1) {
    dom.cashExpenseAccountSelect.value = accounts[0].id;
  }
}

function currentCashExpenseRoute() {
  return dom.cashExpensePaymentRouteSelect?.value === "fixed_credit_card"
    ? "fixed_credit_card"
    : "immediate_account";
}

async function ensureCashFixedRouteCards() {
  if (hasLoadedCashFixedRouteCards) {
    return;
  }

  try {
    cashFixedRouteCards = await fetchSchoolFixedRouteCardsViaFunction();
    hasLoadedCashFixedRouteCards = true;
  } catch (error) {
    cashFixedRouteCards = [];
    hasLoadedCashFixedRouteCards = false;
    showCashExpenseRequestError(`Cash 信用卡读取失败：${error.message || error}`, ["cardInstrument"]);
  }
}

// 一张卡不可选可能有三种原因，逐一给出而不是笼统禁用：
//
//   cash_route_enabled=false  Cash 侧路线 Gate 未开（当前西武卡即是）
//   币种与支出记录不符        卡的结算币种决定了这笔支出的币种，无法换算
//   币种尚未支持              CNY 卡的提交路径没打通——prepare RPC 接不了金额，
//                             而人民币账单需要填实际金额
//
// 不可选的卡仍然列出并标注原因，不从列表里去掉。Gate 未开时若直接过滤，列表会
// 是空的，无从区分「没有卡」与「卡还没启用」。
function cashCardUnavailableReason(card, expenseCurrency) {
  if (!card.cash_route_enabled) {
    return "Cash 侧未启用";
  }
  if (card.settlement_currency !== expenseCurrency) {
    return `币种不符（${card.settlement_currency}）`;
  }
  if (card.settlement_currency !== "JPY") {
    return "该币种的提交路径尚未启用";
  }
  return null;
}

function cashCardLabel(card, expenseCurrency) {
  const base = `${card.name || "未命名卡"}（${card.settlement_currency}）`;
  const reason = cashCardUnavailableReason(card, expenseCurrency);
  return reason ? `${base} · ${reason}` : base;
}

function renderCashExpenseCardOptions() {
  const expenseCurrency = detailData?.expense?.currency || "JPY";
  const selectedValue = dom.cashExpenseCardSelect.value;
  const options = ['<option value="">请选择信用卡</option>'];
  let onlyAvailableId = "";
  let availableCount = 0;

  for (const card of cashFixedRouteCards) {
    const unavailable = cashCardUnavailableReason(card, expenseCurrency) !== null;
    if (!unavailable) {
      onlyAvailableId = card.card_instrument_id;
      availableCount += 1;
    }
    options.push(
      `<option value="${escapeAttribute(card.card_instrument_id)}"${unavailable ? " disabled" : ""}>`
      + `${escapeHtml(cashCardLabel(card, expenseCurrency))}</option>`,
    );
  }

  dom.cashExpenseCardSelect.innerHTML = options.join("");

  if (cashFixedRouteCards.some((card) => card.card_instrument_id === selectedValue)) {
    dom.cashExpenseCardSelect.value = selectedValue;
  } else if (availableCount === 1) {
    dom.cashExpenseCardSelect.value = onlyAvailableId;
  }
}

// 两条路线的字段集不同。固定信用卡不经过 Cash 账户，金额取自支出记录本身、币种
// 由卡决定，因此金额/币种/账户三个字段整体隐藏。
//
// 日期字段两条路线共用，但语义不同：即时路线是 Cash 流水日，固定路线是刷卡日
// ——Cash 侧据此按卡的 cutoff/funding 推导账单月与扣款日。label 随路线切换。
function updateCashExpenseRouteMode() {
  const route = currentCashExpenseRoute();
  for (const field of dom.cashExpenseRequestDialog.querySelectorAll("[data-cash-expense-route]")) {
    field.hidden = field.dataset.cashExpenseRoute !== route;
  }
  dom.cashExpenseActualDateLabel.textContent = route === "fixed_credit_card"
    ? "刷卡日"
    : "实际支付日（Cash流水日）";
}

// 拉取目标固定月预览。卡或刷卡日变化时调用。
//
// 用递增序号做竞态保护：日期输入可能连续触发多次请求，而响应返回顺序不保证，
// 旧请求后到会把预览覆盖成过期结果。只有最后一次发出的请求允许写入状态。
async function refreshCashFixedSchedulePreview() {
  const cardId = dom.cashExpenseCardSelect.value;
  const chargeDate = dom.cashExpenseActualDateInput.value;
  const card = cashFixedRouteCards.find((item) => item.card_instrument_id === cardId);

  // 卡不可用时不发请求：Cash 侧会照常算出月份，但那个月份没有意义——这张卡本来
  // 就提交不了，显示一个「将生成 2026-10」只会误导。
  const expenseCurrency = detailData?.expense?.currency || "JPY";
  if (
    currentCashExpenseRoute() !== "fixed_credit_card"
    || !card
    || cashCardUnavailableReason(card, expenseCurrency) !== null
    || !/^\d{4}-\d{2}-\d{2}$/.test(chargeDate || "")
  ) {
    cashFixedSchedulePreviewSeq += 1;
    cashFixedSchedulePreviewKey = "";
    cashFixedSchedulePreview = null;
    updateCashExpenseRequestPreview();
    return;
  }

  // 按参数去重。input 与 change 绑的是同一个回调，选卡或填完日期都会各触发一次，
  // 递增序号能保证结果正确，却消除不了重复的网络调用。
  const requestKey = `${cardId}|${chargeDate}`;
  if (requestKey === cashFixedSchedulePreviewKey) {
    return;
  }
  cashFixedSchedulePreviewKey = requestKey;

  const seq = ++cashFixedSchedulePreviewSeq;
  try {
    const result = await fetchFixedCardSchedulePreview({
      cardInstrumentId: cardId,
      chargeDate,
    });
    if (seq !== cashFixedSchedulePreviewSeq) {
      return;
    }
    cashFixedSchedulePreview = result;
  } catch (_error) {
    if (seq !== cashFixedSchedulePreviewSeq) {
      return;
    }
    // 预览失败不打断填写，也不弹错误横幅——它只是辅助信息，真正的判定在提交时。
    // 清掉 key，使同一组参数在下次事件时能够重试，不会被去重挡住。
    cashFixedSchedulePreviewKey = "";
    cashFixedSchedulePreview = null;
  }
  updateCashExpenseRequestPreview();
}

function updateCashExpenseRequestPreview() {
  if (currentCashExpenseRoute() === "fixed_credit_card") {
    const expense = detailData?.expense;
    const chargeDate = dom.cashExpenseActualDateInput.value;
    const card = cashFixedRouteCards.find(
      (item) => item.card_instrument_id === dom.cashExpenseCardSelect.value,
    );
    const fixedAmountText = expense?.amount != null
      ? formatCurrency(Number(expense.amount), expense.currency || "JPY")
      : "-";
    // 目标固定月来自 Cash 侧，不在前端计算。cashFixedSchedulePreview 为空时（尚未
    // 拉取、卡不可用、或拉取失败）只回显输入，不显示一个猜出来的月份。
    const scheduleText = cashFixedSchedulePreview
      ? ` → ${String(cashFixedSchedulePreview.target_fixed_month).slice(0, 7)} 固定项，`
        + `${cashFixedSchedulePreview.funding_date} 扣款`
      : "";
    dom.cashExpenseRequestPreview.textContent =
      `Cash 请求预览：刷卡 ${chargeDate || "-"} / ${fixedAmountText} / ${card?.name || "-"}${scheduleText}`;
    return;
  }

  const amount = Number(dom.cashExpenseActualAmountInput.value);
  const currency = dom.cashExpenseActualCurrencySelect.value || "JPY";
  const paymentDate = dom.cashExpenseActualDateInput.value;
  const account = cashEligibleAccounts.find((item) => item.id === dom.cashExpenseAccountSelect.value);
  const amountText = Number.isFinite(amount) && amount > 0 ? formatCurrency(amount, currency) : "-";
  const accountText = account ? cashAccountLabel(account) : "-";
  dom.cashExpenseRequestPreview.textContent = `Cash 请求预览：${paymentDate || "-"} / ${amountText} / ${accountText}`;
}

async function submitCashExpenseRequest() {
  if (isCashRequestSubmitting) {
    return;
  }

  clearCashExpenseRequestErrors();
  const payload = readCashExpenseRequestPayload();
  if (!payload) {
    return;
  }

  setCashRequestSubmitting(true);

  try {
    const result = await requestCashExpenseConfirmation(payload);
    setCashRequestSubmitting(false);
    closeCashExpenseRequestDialog();
    await loadExpenseDetail(payload.expenseId);
    showMessage("success", `Cash 支出确认请求已提交：${shortId(result.cash_request_id)}。`);
  } catch (error) {
    console.error(error);
    showCashExpenseRequestError(`提交 Cash 支出确认失败：${error.message || error}`, cashExpenseFieldIdsForError(error.message || ""));
  } finally {
    setCashRequestSubmitting(false);
  }
}

function readCashExpenseRequestPayload() {
  const expense = detailData?.expense;
  if (!expense?.id) {
    showCashExpenseRequestError("支出记录不存在，请关闭后重试。");
    return null;
  }

  if (!canRequestCashExpense(detailData)) {
    showCashExpenseRequestError(cashRequestNotAllowedMessage(detailData));
    return null;
  }

  if (currentCashExpenseRoute() === "fixed_credit_card") {
    const chargeDate = dom.cashExpenseActualDateInput.value;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(chargeDate || "")) {
      showCashExpenseRequestError("请选择刷卡日。", ["actualDate"]);
      return null;
    }

    const cardId = dom.cashExpenseCardSelect.value;
    const card = cashFixedRouteCards.find((item) => item.card_instrument_id === cardId);
    if (!card) {
      showCashExpenseRequestError("请选择信用卡。", ["cardInstrument"]);
      return null;
    }

    // 再查一次可用性。不可用的卡在下拉里是 disabled 的，正常点不中，但 value 能被
    // 直接改。真正的拒绝在 Cash 侧（HOME_FIXED_CARD_ROUTE_DISABLED 等），这里只是
    // 让原因就地显示，省掉一趟往返。
    const unavailableReason = cashCardUnavailableReason(card, expense.currency || "JPY");
    if (unavailableReason) {
      showCashExpenseRequestError(`该信用卡当前不可用：${unavailableReason}。`, ["cardInstrument"]);
      return null;
    }

    return {
      expenseId: expense.id,
      paymentRoute: "fixed_credit_card",
      cardInstrumentId: cardId,
      chargeDate,
      note: buildCashFixedExpenseRequestNote(expense, chargeDate, card),
    };
  }

  const amount = Number(dom.cashExpenseActualAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showCashExpenseRequestError("实际支付金额必须大于 0。", ["actualAmount"]);
    return null;
  }

  const actualPaymentDate = dom.cashExpenseActualDateInput.value;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(actualPaymentDate || "")) {
    showCashExpenseRequestError("请选择实际支付日。", ["actualDate"]);
    return null;
  }

  const currency = dom.cashExpenseActualCurrencySelect.value;
  if (!["JPY", "CNY"].includes(currency)) {
    showCashExpenseRequestError("请选择实际支付币种。", ["actualCurrency"]);
    return null;
  }

  const accountId = dom.cashExpenseAccountSelect.value;
  const account = cashEligibleAccounts.find((item) => item.id === accountId);
  if (!account) {
    showCashExpenseRequestError("请选择 Cash 支付账户。", ["cashAccount"]);
    return null;
  }

  if (account.currency !== currency) {
    showCashExpenseRequestError("Cash 支付账户币种必须与实际支付币种一致。", ["cashAccount", "actualCurrency"]);
    return null;
  }

  return {
    expenseId: expense.id,
    cashAccountId: accountId,
    actualPaymentAmount: amount,
    actualPaymentCurrency: currency,
    actualPaymentDate,
    note: buildCashExpenseRequestNote(expense, amount, currency, actualPaymentDate),
  };
}

function renderCashExpenseRequestSummary(expense) {
  return renderDefinitionList([
    ["支出日期", formatDateOnly(expense.expense_date)],
    ["目标月份", formatMonth(expense.year_month)],
    ["分类", expenseCategoryLabel(expense.expense_category)],
    ["支付对象", displayValue(expense.payee_name_snapshot)],
    ["原始金额", formatCurrency(expense.amount, expense.currency)],
    ["状态", expenseStatusLabel(expense.status)],
  ]);
}

function buildCashExpenseRequestNote(expense, amount, currency, paymentDate) {
  const base = dom.cashExpenseNoteInput.value.trim();
  const requiredText = `${displayValue(expense.payee_name_snapshot || expense.description)}，实际支付日${paymentDate}，实际支付${formatCurrency(amount, currency)}`;
  if (!base) {
    return requiredText;
  }
  return base.includes("实际支付日") ? base : `${base}；${requiredText}`;
}

// 固定信用卡路线的备注。与即时路线的区别在于「刷卡日」而非「实际支付日」——
// 这两个日期在信用卡场景下相差一个多月，混用会让 Cash 侧的记录难以对账。
// 金额取自支出记录，因为这条路线没有用户输入的金额。
function buildCashFixedExpenseRequestNote(expense, chargeDate, card) {
  const base = dom.cashExpenseNoteInput.value.trim();
  const amountText = expense.amount != null
    ? formatCurrency(Number(expense.amount), expense.currency || "JPY")
    : "-";
  const requiredText = `${displayValue(expense.payee_name_snapshot || expense.description)}，`
    + `${card.name || "信用卡"}刷卡日${chargeDate}，${amountText}`;
  if (!base) {
    return requiredText;
  }
  return base.includes("刷卡日") ? base : `${base}；${requiredText}`;
}

function setCashRequestSubmitting(isSubmitting) {
  isCashRequestSubmitting = isSubmitting;
  dom.cashExpenseRequestSubmitButton.disabled = isSubmitting;
  dom.cashExpenseRequestCancelButton.disabled = isSubmitting;
  dom.cashExpenseRequestSubmitButton.textContent = isSubmitting ? "提交中..." : "提交 Cash 支付确认";
}

function clearCashExpenseRequestErrors() {
  dom.cashExpenseRequestError.textContent = "";
  dom.cashExpenseRequestError.classList.add("is-hidden");
  [
    "paymentRoute",
    "actualAmount",
    "actualDate",
    "actualCurrency",
    "cashAccount",
    "cardInstrument",
    "note",
  ].forEach((fieldId) => {
    setCashExpenseFieldInvalid(fieldId, false);
  });
}

function showCashExpenseRequestError(message, fieldIds = []) {
  dom.cashExpenseRequestError.textContent = message;
  dom.cashExpenseRequestError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCashExpenseFieldInvalid(fieldId, true);
  }
  dom.cashExpenseRequestDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function cashExpenseFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("金额")) fields.push("actualAmount");
  if (text.includes("币种")) fields.push("actualCurrency");
  if (text.includes("账户")) fields.push("cashAccount");
  return fields;
}

function setCashExpenseFieldInvalid(fieldId, invalid) {
  const field = dom.cashExpenseRequestDialog.querySelector(`[data-cash-expense-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function hideCashExpenseRequestErrorIfClean() {
  const hasInvalidField = Boolean(dom.cashExpenseRequestDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.cashExpenseRequestError.textContent = "";
    dom.cashExpenseRequestError.classList.add("is-hidden");
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
  const cashProtectionMessage = cashExpenseProtectionMessage(data);
  if (cashProtectionMessage) return cashProtectionMessage;
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

function cashExpenseProtectionMessage(data) {
  const expense = data?.expense;
  if (!expense) return "";
  if (expense.cash_transaction_id || ["approved", "synced"].includes(expense.cash_request_status || "")) {
    return "已同步到 Cash，不能直接编辑或删除。请通过冲正/调整流程处理。";
  }
  if (["pending", "pending_cash_request"].includes(expense.cash_request_status || "")) {
    return "该支出已有待确认 Cash 请求，不能直接编辑核心字段或撤销。";
  }
  return "";
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

function renderNonEmptyDefinitionList(items, emptyText = "无记录。") {
  const visibleItems = items.filter(([, value]) => hasDisplayValue(value));
  if (!visibleItems.length) {
    return `<div class="state-text">${escapeHtml(emptyText)}</div>`;
  }

  return renderDefinitionList(visibleItems);
}

function renderSystemTextBlock(label, value) {
  const text = safeText(value);
  if (!text) {
    return "";
  }

  return `
    <div class="expense-system-text-block">
      <strong>${escapeHtml(label)}</strong>
      <pre>${escapeHtml(text)}</pre>
    </div>
  `;
}

function hasDisplayValue(value) {
  const text = safeText(value);
  return Boolean(text) && !["-", "未设置", "未知", "undefined", "null"].includes(text);
}

function expenseObjectName(expense) {
  const payeeName = safeText(expense?.payee_name_snapshot);
  if (payeeName) {
    return payeeName;
  }

  if (expense?.teacher_id) {
    return teacherNameById(expense.teacher_id);
  }

  if (expense?.student_id) {
    return studentNameById(expense.student_id);
  }

  return displayValue(expense?.description);
}

function teacherNameForDisplay(id) {
  return id ? teacherNameById(id) : "";
}

function accountNameForDisplay(id) {
  return id ? accountNameById(id) : "";
}

function businessSourceLabel(expense) {
  if (!expense?.source_type) {
    return "";
  }

  if (expense.source_type === "teacher_wage") {
    return "老师工资";
  }

  if (expense.source_type === "manual" && !expense.source_id) {
    return "手工记录";
  }

  if (expense.source_type === "manual_school") {
    return "School 直接支付";
  }

  if (expense.source_type === "manual_cash") {
    return "Cash 审批支付";
  }

  return sourceTypeLabel(expense.source_type);
}

function actualPaymentDateLabel(expense) {
  if (safeText(expense?.expense_date)) {
    return formatDateOnly(expense.expense_date);
  }

  if (expense?.status === "pending" && !expense?.cash_transaction_id) {
    return "未提交 Cash";
  }

  return "未设置";
}

function attachmentSummaryLabel(attachments) {
  const count = Array.isArray(attachments) ? attachments.length : 0;
  return count > 0 ? `${count} 个附件摘要` : "无附件";
}

function formatCashPaymentAmount(expense) {
  if (expense?.cash_payment_amount === null || expense?.cash_payment_amount === undefined || expense?.cash_payment_amount === "") {
    return "-";
  }

  return formatCurrency(expense.cash_payment_amount, expense.cash_payment_currency || expense.currency);
}

function notePreview(text) {
  const normalized = safeText(text).replace(/\s+/g, " ").trim();
  return normalized.length > 120 ? `${normalized.slice(0, 120)}...` : normalized;
}

function isSystemMigrationNote(value) {
  const text = safeText(value);
  return /migrated_to_|canonical_flow|payment_request_id=|migration/i.test(text);
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

function cashRequestStatusLabel(value) {
  const labels = {
    pending_cash_request: "Cash待提交",
    pending: "Cash待确认",
    approved: "Cash已确认",
    synced: "已同步到 Cash",
    rejected: "Cash已拒绝",
  };
  return labels[value] || (safeText(value) ? displayValue(value) : "未提交 Cash");
}

function cashRequestStatusClass(value) {
  if (value === "approved" || value === "synced") {
    return "status-paid";
  }

  if (value === "pending" || value === "pending_cash_request") {
    return "status-pending";
  }

  if (value === "rejected") {
    return "status-cancelled";
  }

  return "status-neutral";
}

function cashAccountLabel(account) {
  return [
    account.name || account.id,
    account.currency || "-",
    account.account_type || "",
  ].filter(Boolean).join(" / ");
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
