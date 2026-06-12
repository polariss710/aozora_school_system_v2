import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchIncomeDetailPage, reverseIncomeRecord, updateIncomeRecord } from "../api/income-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const INCOME_STATUS_LABELS = {
  received: "已收款",
  reversed: "已撤销",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
  material_fee: "教材费",
  registration_fee: "报名费",
  other_fee: "其他费用",
};

const EDITABLE_INCOME_CATEGORIES = ["tuition", "material_fee", "registration_fee", "other_fee"];

const PAYMENT_METHOD_LABELS = {
  alipay: "支付宝",
  bank_transfer: "银行转账",
  cash: "现金",
  card: "银行卡",
  wechat: "微信",
};

const SETTLEMENT_STATUS_LABELS = {
  locked: "已锁定",
  draft: "草稿",
};

const TRANSACTION_TYPE_LABELS = {
  income_adjust: "收入调整",
  income_reversal: "收入撤销",
};

const dom = {};
let detailData = null;
let isReverseSubmitting = false;
let isEditSubmitting = false;
const REVERSE_INCOME_FIELD_IDS = ["reversalDate", "reason", "confirmCheck"];
const EDIT_INCOME_FIELD_IDS = [
  "incomeDate",
  "settlementMonth",
  "businessEntity",
  "student",
  "account",
  "incomeCategory",
  "amount",
  "paymentMethod",
  "exchangeRate",
];

export function initIncomeDetailPage() {
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

  const incomeId = readIncomeId();
  if (!incomeId) {
    showMessage("error", "缺少收入记录 ID，请从收入记录一览进入详情页。");
    setContentVisible(false);
    return;
  }

  loadIncomeDetail(incomeId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#incomeDetailMessageArea");
  dom.actionStatus = document.querySelector("#incomeDetailActionStatus");
  dom.openEditIncomeButton = document.querySelector("#openEditIncomeButton");
  dom.openReverseIncomeButton = document.querySelector("#openReverseIncomeButton");
  dom.loadingState = document.querySelector("#incomeDetailLoadingState");
  dom.content = document.querySelector("#incomeDetailContent");
  dom.titleText = document.querySelector("#incomeDetailTitleText");
  dom.basicInfo = document.querySelector("#incomeDetailBasicInfo");
  dom.amountInfo = document.querySelector("#incomeDetailAmountInfo");
  dom.relatedInfo = document.querySelector("#incomeDetailRelatedInfo");
  dom.systemInfo = document.querySelector("#incomeDetailSystemInfo");
  dom.reversalCard = document.querySelector("#incomeDetailReversalCard");
  dom.reversalInfo = document.querySelector("#incomeDetailReversalInfo");
  dom.noteBlock = document.querySelector("#incomeDetailNoteBlock");
  dom.transactionCount = document.querySelector("#incomeDetailTransactionCount");
  dom.transactionEmpty = document.querySelector("#incomeDetailTransactionEmpty");
  dom.transactionRows = document.querySelector("#incomeDetailTransactionRows");
  dom.reverseDialog = document.querySelector("#reverseIncomeDialog");
  dom.reverseSummary = document.querySelector("#reverseIncomeSummary");
  dom.reverseError = document.querySelector("#reverseIncomeError");
  dom.reverseDateInput = document.querySelector("#reverseIncomeDateInput");
  dom.reverseReasonInput = document.querySelector("#reverseIncomeReasonInput");
  dom.reverseConfirmCheck = document.querySelector("#reverseIncomeConfirmCheck");
  dom.reverseSubmitButton = document.querySelector("#reverseIncomeSubmitButton");
  dom.reverseCancelButton = document.querySelector("#reverseIncomeCancelButton");
  dom.editDialog = document.querySelector("#editIncomeDialog");
  dom.editError = document.querySelector("#editIncomeError");
  dom.editIncomeDateInput = document.querySelector("#editIncomeDateInput");
  dom.editSettlementMonthInput = document.querySelector("#editSettlementMonthInput");
  dom.editBusinessEntitySelect = document.querySelector("#editIncomeBusinessEntitySelect");
  dom.editStudentSelect = document.querySelector("#editIncomeStudentSelect");
  dom.editAccountSelect = document.querySelector("#editIncomeAccountSelect");
  dom.editCategorySelect = document.querySelector("#editIncomeCategorySelect");
  dom.editAmountInput = document.querySelector("#editIncomeAmountInput");
  dom.editPaymentMethodSelect = document.querySelector("#editIncomePaymentMethodSelect");
  dom.editDescriptionInput = document.querySelector("#editIncomeDescriptionInput");
  dom.editExchangeRateInput = document.querySelector("#editIncomeExchangeRateInput");
  dom.editTaxableSelect = document.querySelector("#editIncomeTaxableSelect");
  dom.editTaxCategoryInput = document.querySelector("#editIncomeTaxCategoryInput");
  dom.editReceiptStatusInput = document.querySelector("#editIncomeReceiptStatusInput");
  dom.editNoteInput = document.querySelector("#editIncomeNoteInput");
  dom.editSubmitButton = document.querySelector("#editIncomeSubmitButton");
  dom.editCancelButton = document.querySelector("#editIncomeCancelButton");
}

function bindEvents() {
  dom.openEditIncomeButton.addEventListener("click", openEditDialog);
  dom.openReverseIncomeButton.addEventListener("click", openReverseDialog);
  dom.editCancelButton.addEventListener("click", closeEditDialog);
  dom.editSubmitButton.addEventListener("click", submitEditIncome);
  dom.editBusinessEntitySelect.addEventListener("change", () => {
    renderEditStudentOptions();
    renderEditAccountOptions();
    setEditFieldInvalid("businessEntity", false);
    hideEditErrorIfClean();
  });
  dom.editStudentSelect.addEventListener("change", () => {
    setEditFieldInvalid("student", false);
    hideEditErrorIfClean();
  });
  dom.editAccountSelect.addEventListener("change", () => {
    setEditFieldInvalid("account", false);
    hideEditErrorIfClean();
  });
  dom.editCategorySelect.addEventListener("change", () => {
    setEditFieldInvalid("incomeCategory", false);
    hideEditErrorIfClean();
  });
  for (const [input, fieldId] of [
    [dom.editIncomeDateInput, "incomeDate"],
    [dom.editSettlementMonthInput, "settlementMonth"],
    [dom.editAmountInput, "amount"],
    [dom.editPaymentMethodSelect, "paymentMethod"],
    [dom.editExchangeRateInput, "exchangeRate"],
  ]) {
    input.addEventListener("input", () => {
      setEditFieldInvalid(fieldId, false);
      hideEditErrorIfClean();
    });
  }
  dom.reverseCancelButton.addEventListener("click", closeReverseDialog);
  dom.reverseSubmitButton.addEventListener("click", submitReverseIncome);
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

function readIncomeId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadIncomeDetail(incomeId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载收入记录详情...");

  try {
    detailData = await fetchIncomeDetailPage(incomeId);
    renderIncomeDetail(detailData);
    setContentVisible(true);
    showMessage("success", "收入记录详情已加载。");
  } catch (error) {
    detailData = null;
    setContentVisible(false);
    showMessage("error", `读取收入记录详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderIncomeDetail(data) {
  const { income } = data;
  renderActionArea(data);
  dom.titleText.textContent = `${formatDateOnly(income.income_date)} / ${incomeCategoryLabel(income.income_category)} / ${formatCurrency(income.amount, income.currency)}`;

  dom.basicInfo.innerHTML = renderDefinitionList([
    ["收入 ID", shortId(income.id)],
    ["收入日期", formatDateOnly(income.income_date)],
    ["目标月份", formatMonth(income.year_month)],
    ["结算月份", formatMonth(income.settlement_month)],
    ["收入分类", incomeCategoryLabel(income.income_category)],
    ["描述", displayValue(income.description)],
    ["状态", incomeStatusLabel(income.status)],
    ["业务归属", businessNameById(income.business_entity_id)],
    ["创建时间", formatDate(income.created_at)],
    ["更新时间", formatDate(income.updated_at)],
  ]);

  dom.amountInfo.innerHTML = renderDefinitionList([
    ["币种", displayValue(income.currency)],
    ["原币金额", formatCurrency(income.amount, income.currency)],
    ["JPY 金额", formatCurrency(income.amount_jpy, "JPY")],
    ["CNY 金额", formatCurrency(income.amount_cny, "CNY")],
    ["汇率", displayValue(income.exchange_rate)],
    ["付款币种", displayValue(income.payment_currency)],
    ["支付方式", paymentMethodLabel(income.payment_method)],
    ["应税收入", booleanLabel(income.is_taxable_income)],
    ["税务分类", displayValue(income.tax_category)],
    ["收据状态", displayValue(income.receipt_status)],
    ["进入学生结算", booleanLabel(income.include_in_student_settlement)],
  ]);

  dom.relatedInfo.innerHTML = renderDefinitionList([
    ["学生", studentNameById(income.student_id)],
    ["学生编号", studentFieldById(income.student_id, "student_code")],
    ["课程方向", studentFieldById(income.student_id, "course_track")],
    ["目标类型", studentFieldById(income.student_id, "target_type")],
    ["学生默认币种", studentFieldById(income.student_id, "default_currency")],
    ["账户", accountNameById(income.account_id)],
    ["账户编码", accountFieldById(income.account_id, "account_code")],
    ["账户类型", accountFieldById(income.account_id, "account_type")],
  ]);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["id", shortId(income.id)],
    ["student_id", shortId(income.student_id)],
    ["student_payment_id", shortId(income.student_payment_id)],
    ["account_id", shortId(income.account_id)],
    ["business_entity_id", shortId(income.business_entity_id)],
    ["app_type", displayValue(income.app_type)],
    ["created_at", formatDate(income.created_at)],
    ["updated_at", formatDate(income.updated_at)],
  ]);

  renderReversalInfo(income);
  dom.noteBlock.textContent = displayValue(income.note);
  renderTransactions(data.transactions);
}

function renderActionArea(data) {
  const { income } = data;
  const status = income?.status || "";
  const canReverse = canReverseIncome(data);
  const canEdit = canEditIncome(data);
  dom.actionStatus.className = `status-badge ${statusClass(status)}`;
  dom.actionStatus.textContent = incomeStatusLabel(status);
  dom.openEditIncomeButton.classList.toggle("is-hidden", !canEdit);
  dom.openEditIncomeButton.disabled = !canEdit;
  dom.openReverseIncomeButton.classList.toggle("is-hidden", !canReverse);
  dom.openReverseIncomeButton.disabled = !canReverse;
}

function canEditIncome(data) {
  const income = data?.income;
  if (!income) {
    return false;
  }

  const hasLockedSettlement = (data.settlements || []).some((settlement) => settlement.settlement_status === "locked");
  return income.status === "received"
    && !income.reversed_at
    && !income.reversal_account_transaction_id
    && !income.student_payment_id
    && !hasLockedSettlement;
}

function canReverseIncome(data) {
  const income = data?.income;
  if (!income) {
    return false;
  }

  const hasLockedSettlement = (data.settlements || []).some((settlement) => settlement.settlement_status === "locked");
  return income.status === "received"
    && !income.reversed_at
    && !income.reversal_account_transaction_id
    && !income.student_payment_id
    && !hasLockedSettlement;
}

function renderReversalInfo(income) {
  const isReversed = income.status === "reversed"
    || Boolean(income.reversed_at)
    || Boolean(income.reversal_account_transaction_id);
  dom.reversalCard.classList.toggle("is-hidden", !isReversed);

  if (!isReversed) {
    dom.reversalInfo.innerHTML = "";
    return;
  }

  dom.reversalInfo.innerHTML = renderDefinitionList([
    ["撤销时间", formatDate(income.reversed_at)],
    ["撤销原因", displayValue(income.reversal_reason)],
    ["反向流水", shortId(income.reversal_account_transaction_id)],
  ]);
}

function openEditDialog() {
  if (isEditSubmitting) {
    return;
  }

  if (!detailData?.income) {
    showMessage("error", "编辑对象不存在，请刷新后重试。");
    return;
  }

  if (!canEditIncome(detailData)) {
    showMessage("error", editNotAllowedMessage(detailData));
    return;
  }

  clearEditErrors();
  populateEditDialog(detailData.income);
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

function populateEditDialog(income) {
  dom.editIncomeDateInput.value = income.income_date || "";
  dom.editSettlementMonthInput.value = income.settlement_month || income.year_month || "";
  dom.editAmountInput.value = income.amount ?? "";
  dom.editPaymentMethodSelect.value = income.payment_method || "";
  dom.editCategorySelect.value = EDITABLE_INCOME_CATEGORIES.includes(income.income_category)
    ? income.income_category
    : "tuition";
  dom.editDescriptionInput.value = income.description || "";
  dom.editExchangeRateInput.value = income.exchange_rate ?? "";
  dom.editTaxableSelect.value = income.is_taxable_income ? "true" : "false";
  dom.editTaxCategoryInput.value = income.tax_category || "";
  dom.editReceiptStatusInput.value = income.receipt_status || "";
  dom.editNoteInput.value = income.note || "";

  renderEditBusinessEntityOptions();
  dom.editBusinessEntitySelect.value = income.business_entity_id || "";
  renderEditStudentOptions();
  dom.editStudentSelect.value = filteredEditStudents().some((student) => student.id === income.student_id)
    ? income.student_id
    : "";
  renderEditAccountOptions();
  dom.editAccountSelect.value = filteredEditAccounts().some((account) => account.id === income.account_id)
    ? income.account_id
    : "";
}

async function submitEditIncome() {
  if (isEditSubmitting) {
    return;
  }

  clearEditErrors();
  const payload = readEditIncomePayload();
  if (!payload) {
    return;
  }

  setEditSubmitting(true);

  try {
    await updateIncomeRecord(payload);
    setEditSubmitting(false);
    closeEditDialog();
    await loadIncomeDetail(payload.incomeId);
    showMessage("success", "收入记录已更新。");
  } catch (error) {
    console.error(error);
    showEditError(`编辑收入失败：${error.message || error}`, editFieldIdsForError(error.message || ""));
  } finally {
    setEditSubmitting(false);
  }
}

function readEditIncomePayload() {
  const income = detailData?.income;
  if (!income?.id) {
    showEditError("编辑对象不存在，请关闭后重试。");
    return null;
  }

  if (!canEditIncome(detailData)) {
    showEditError(editNotAllowedMessage(detailData));
    return null;
  }

  const incomeDate = dom.editIncomeDateInput.value;
  if (!incomeDate) {
    showEditError("请选择实际收款日期。", ["incomeDate"]);
    return null;
  }

  const settlementMonth = dom.editSettlementMonthInput.value;
  if (!settlementMonth || !/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(settlementMonth)) {
    showEditError("结算月份格式无效。", ["settlementMonth"]);
    return null;
  }

  const businessEntityId = dom.editBusinessEntitySelect.value;
  if (!businessEntityId) {
    showEditError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

  const studentId = dom.editStudentSelect.value;
  if (!studentId) {
    showEditError("请选择学生。", ["student"]);
    return null;
  }

  const accountId = dom.editAccountSelect.value;
  if (!accountId) {
    showEditError("请选择入账账户。", ["account"]);
    return null;
  }

  const account = detailData.lookups.accounts.find((item) => item.id === accountId);
  if (!account || account.is_active !== true || account.app_type !== "school") {
    showEditError("入账账户无效或已停用。", ["account"]);
    return null;
  }

  if (account.business_entity_id !== businessEntityId) {
    showEditError("入账账户与业务归属不一致。", ["account"]);
    return null;
  }

  if (!account.currency) {
    showEditError("入账账户缺少币种。", ["account"]);
    return null;
  }

  const incomeCategory = dom.editCategorySelect.value;
  if (!EDITABLE_INCOME_CATEGORIES.includes(incomeCategory)) {
    showEditError("请选择收入分类。", ["incomeCategory"]);
    return null;
  }

  const amount = Number(dom.editAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showEditError("收入金额必须大于 0。", ["amount"]);
    return null;
  }

  const paymentMethod = dom.editPaymentMethodSelect.value;
  if (!paymentMethod) {
    showEditError("请选择收款方式。", ["paymentMethod"]);
    return null;
  }

  const exchangeRateText = dom.editExchangeRateInput.value.trim();
  const exchangeRate = exchangeRateText ? Number(exchangeRateText) : null;
  if (exchangeRateText && (!Number.isFinite(exchangeRate) || exchangeRate <= 0)) {
    showEditError("汇率必须大于 0。", ["exchangeRate"]);
    return null;
  }

  return {
    incomeId: income.id,
    incomeDate,
    settlementMonth,
    businessEntityId,
    studentId,
    accountId,
    incomeCategory,
    amount,
    currency: account.currency,
    paymentCurrency: account.currency,
    exchangeRate,
    paymentMethod,
    description: dom.editDescriptionInput.value.trim(),
    isTaxableIncome: dom.editTaxableSelect.value === "true",
    taxCategory: dom.editTaxCategoryInput.value.trim(),
    receiptStatus: dom.editReceiptStatusInput.value.trim(),
    note: dom.editNoteInput.value.trim(),
  };
}

function renderEditBusinessEntityOptions() {
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of detailData.lookups.businessEntities.filter((item) => item.is_active !== false)) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(businessName(entity))}</option>`);
  }
  dom.editBusinessEntitySelect.innerHTML = options.join("");
}

function renderEditStudentOptions() {
  const selectedValue = dom.editStudentSelect.value;
  const options = ['<option value="">请选择学生</option>'];
  for (const student of filteredEditStudents()) {
    options.push(`<option value="${escapeAttribute(student.id)}">${escapeHtml(studentName(student))}</option>`);
  }
  dom.editStudentSelect.innerHTML = options.join("");
  if (filteredEditStudents().some((student) => student.id === selectedValue)) {
    dom.editStudentSelect.value = selectedValue;
  }
}

function renderEditAccountOptions() {
  const selectedValue = dom.editAccountSelect.value;
  const options = ['<option value="">请选择入账账户</option>'];
  for (const account of filteredEditAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(editAccountLabel(account))}</option>`);
  }
  dom.editAccountSelect.innerHTML = options.join("");
  if (filteredEditAccounts().some((account) => account.id === selectedValue)) {
    dom.editAccountSelect.value = selectedValue;
  }
}

function filteredEditStudents() {
  const businessEntityId = dom.editBusinessEntitySelect.value;
  return detailData.lookups.students.filter((student) => {
    if (businessEntityId && student.business_entity_id !== businessEntityId) {
      return false;
    }
    return student.status !== "inactive" && student.status !== "disabled" && student.status !== "archived";
  });
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
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
  ].filter(Boolean).join(" / ");
}

function renderTransactions(transactions) {
  dom.transactionCount.textContent = `${transactions.length} 条`;
  dom.transactionEmpty.classList.toggle("is-hidden", transactions.length > 0);

  if (!transactions.length) {
    dom.transactionRows.innerHTML = "";
    return;
  }

  dom.transactionRows.innerHTML = transactions.map((transaction) => `
    <tr>
      <td class="income-nowrap">${escapeHtml(formatDateOnly(transaction.transaction_date))}</td>
      <td>${escapeHtml(transactionTypeLabel(transaction.transaction_type))}</td>
      <td>${escapeHtml(accountNameById(transaction.account_id))}</td>
      <td class="income-nowrap">${escapeHtml(displayValue(transaction.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(transaction.amount, transaction.currency))}</td>
      <td class="number-cell income-nowrap">${escapeHtml(formatCurrency(transaction.balance_after, transaction.currency))}</td>
      <td>${escapeHtml(displayValue(transaction.related_table))}</td>
      <td>${escapeHtml(shortId(transaction.related_id))}</td>
      <td class="income-note-cell">${escapeHtml(displayValue(transaction.description))}</td>
      <td class="income-note-cell">${escapeHtml(displayValue(transaction.note))}</td>
      <td class="income-nowrap">${escapeHtml(formatDate(transaction.created_at))}</td>
    </tr>
  `).join("");
}

function openReverseDialog() {
  if (isReverseSubmitting) {
    return;
  }

  if (!detailData?.income) {
    showMessage("error", "撤销对象不存在，请刷新后重试。");
    return;
  }

  if (!canReverseIncome(detailData)) {
    showMessage("error", reverseNotAllowedMessage(detailData));
    return;
  }

  clearReverseErrors();
  dom.reverseSummary.innerHTML = renderReverseSummary(detailData.income);
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

async function submitReverseIncome() {
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
    await reverseIncomeRecord(payload);
    setReverseSubmitting(false);
    closeReverseDialog();
    await loadIncomeDetail(payload.incomeId);
    showMessage("success", "收入已撤销。");
  } catch (error) {
    console.error(error);
    showReverseError(`撤销收入失败：${error.message || error}`, reverseFieldIdsForError(error.message || ""));
  } finally {
    setReverseSubmitting(false);
  }
}

function readReversePayload() {
  const income = detailData?.income;
  if (!income?.id) {
    showReverseError("撤销对象不存在，请关闭后重试。");
    return null;
  }

  if (!canReverseIncome(detailData)) {
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
    incomeId: income.id,
    reversalDate,
    reason: dom.reverseReasonInput.value.trim(),
  };
}

function renderReverseSummary(income) {
  return renderDefinitionList([
    ["收入日期", formatDateOnly(income.income_date)],
    ["结算月份", formatMonth(income.settlement_month)],
    ["分类", incomeCategoryLabel(income.income_category)],
    ["描述", displayValue(income.description)],
    ["金额", formatCurrency(income.amount, income.currency)],
    ["账户", accountNameById(income.account_id)],
  ]);
}

function reverseNotAllowedMessage(data) {
  const income = data?.income;
  if (!income) return "撤销对象不存在，请刷新后重试。";
  if (income.status === "reversed" || income.reversed_at || income.reversal_account_transaction_id) {
    return "该收入已撤销，不能重复撤销。";
  }
  if (income.status !== "received") return "只能撤销已收款收入。";
  if (income.student_payment_id) return "关联学生收款链路的收入暂不支持通过普通收入撤销处理。";
  if ((data.settlements || []).some((settlement) => settlement.settlement_status === "locked")) {
    return "目标学生月度结算已锁定，不能撤销收入。";
  }
  return "当前收入不能撤销。";
}

function editNotAllowedMessage(data) {
  const income = data?.income;
  if (!income) return "编辑对象不存在，请刷新后重试。";
  if (income.status === "reversed" || income.reversed_at || income.reversal_account_transaction_id) {
    return "该收入已撤销，不能编辑。";
  }
  if (income.status !== "received") return "只能编辑已收款收入。";
  if (income.student_payment_id) return "关联学生收款链路的收入暂不支持普通编辑。";
  if ((data.settlements || []).some((settlement) => settlement.settlement_status === "locked")) {
    return "目标学生月度结算已锁定，不能编辑收入。";
  }
  return "当前收入不能编辑。";
}

function setEditSubmitting(isSubmitting) {
  isEditSubmitting = isSubmitting;
  dom.editSubmitButton.disabled = isSubmitting;
  dom.editCancelButton.disabled = isSubmitting;
  dom.editSubmitButton.textContent = isSubmitting ? "保存中..." : "保存收入";
}

function clearEditErrors() {
  dom.editError.textContent = "";
  dom.editError.classList.add("is-hidden");
  for (const fieldId of EDIT_INCOME_FIELD_IDS) {
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
  if (text.includes("收款日期")) fields.push("incomeDate");
  if (text.includes("结算月份") || text.includes("已锁定")) fields.push("settlementMonth");
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("学生")) fields.push("student");
  if (text.includes("账户") || text.includes("币种")) fields.push("account");
  if (text.includes("分类")) fields.push("incomeCategory");
  if (text.includes("汇率")) fields.push("exchangeRate");
  return fields;
}

function setEditFieldInvalid(fieldId, invalid) {
  const field = dom.editDialog.querySelector(`[data-edit-income-field="${fieldId}"]`);
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
  for (const fieldId of REVERSE_INCOME_FIELD_IDS) {
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
  const field = dom.reverseDialog.querySelector(`[data-reverse-income-field="${fieldId}"]`);
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

function studentById(id) {
  return detailData?.lookups.students.find((item) => item.id === id) || null;
}

function businessById(id) {
  return detailData?.lookups.businessEntities.find((item) => item.id === id) || null;
}

function accountById(id) {
  return detailData?.lookups.accounts.find((item) => item.id === id) || null;
}

function studentNameById(id) {
  const student = studentById(id);
  if (!student) {
    return id ? "未知" : "未设置";
  }

  return safeText(student.display_name || student.name) || "未设置";
}

function studentFieldById(id, key) {
  const student = studentById(id);
  return student ? displayValue(student[key]) : id ? "未知" : "未设置";
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

function accountNameById(id) {
  const account = accountById(id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function studentName(student) {
  return safeText(student.display_name || student.name) || "未设置";
}

function businessName(entity) {
  const name = safeText(entity.name) || "未设置";
  const code = safeText(entity.code);
  return code ? `${name} / ${code}` : name;
}

function accountFieldById(id, key) {
  const account = accountById(id);
  return account ? displayValue(account[key]) : id ? "未知" : "未设置";
}

function incomeStatusLabel(value) {
  return INCOME_STATUS_LABELS[value] || displayValue(value);
}

function incomeCategoryLabel(value) {
  return INCOME_CATEGORY_LABELS[value] || displayValue(value);
}

function paymentMethodLabel(value) {
  return PAYMENT_METHOD_LABELS[value] || displayValue(value);
}

function settlementStatusLabel(value) {
  return SETTLEMENT_STATUS_LABELS[value] || displayValue(value);
}

function transactionTypeLabel(value) {
  return TRANSACTION_TYPE_LABELS[value] || displayValue(value);
}

function statusClass(value) {
  if (value === "received" || value === "locked") {
    return "status-paid";
  }

  if (value === "reversed") {
    return "status-cancelled";
  }

  if (value === "draft") {
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

function currentDate() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
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
