import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import {
  createReimbursementRecord,
  fetchReimbursementCandidateExpenses,
  fetchReimbursementItemCounts,
  fetchReimbursementLookups,
  fetchReimbursementRecords,
  fetchReimbursementTransactionCounts,
} from "../api/reimbursement-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  fromAccountId: "",
  toAccountId: "",
  currency: "",
  status: "",
  hasItems: "",
  hasTransactions: "",
  keyword: "",
};

const REIMBURSEMENT_STATUS_LABELS = {
  paid: "已支付",
  pending: "待报销",
  reimbursed: "已报销",
  not_required: "无需报销",
};

const EXPENSE_CATEGORY_LABELS = {
  advertising: "广告宣传",
  classroom: "教室费用",
  other: "其他",
  software: "软件 / 系统",
  tax_accounting: "税务会计",
  teacher_wage: "老师工资",
};

const CREATE_REIMBURSEMENT_FIELD_IDS = [
  "reimbursementDate",
  "expenses",
  "fromAccount",
  "toAccount",
];

const dom = {};
let businessEntities = [];
let accounts = [];
let reimbursementRecords = [];
let reimbursementCandidateExpenses = [];
let itemCounts = new Map();
let transactionCounts = new Map();
let loadedMonth = "";
let isCreateSubmitting = false;
let candidateExpenses = [];
let selectedExpenseIds = new Set();

export function initReimbursementPage() {
  cacheDom();
  populateYearSelect(dom.yearFilter, PAYMENT_MONTH_FILTER_YEAR_RANGE);
  populateMonthSelect(dom.monthFilter);
  setDefaultFilters();
  bindEvents();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    renderCandidateExpenses([]);
    renderReimbursements([]);
    return;
  }

  loadInitialData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#reimbursementMessageArea");
  dom.filterForm = document.querySelector("#reimbursementFilterForm");
  dom.yearFilter = document.querySelector("#reimbursementYearFilter");
  dom.monthFilter = document.querySelector("#reimbursementMonthFilter");
  dom.fromAccountSelect = document.querySelector("#reimbursementFromAccountSelect");
  dom.toAccountSelect = document.querySelector("#reimbursementToAccountSelect");
  dom.currencySelect = document.querySelector("#reimbursementCurrencySelect");
  dom.statusSelect = document.querySelector("#reimbursementStatusSelect");
  dom.hasItemsSelect = document.querySelector("#reimbursementHasItemsSelect");
  dom.hasTransactionsSelect = document.querySelector("#reimbursementHasTransactionsSelect");
  dom.keywordInput = document.querySelector("#reimbursementKeywordInput");
  dom.resetButton = document.querySelector("#reimbursementResetButton");
  dom.tableBody = document.querySelector("#reimbursementTableBody");
  dom.loadingState = document.querySelector("#reimbursementLoadingState");
  dom.emptyState = document.querySelector("#reimbursementEmptyState");
  dom.reimbursementCount = document.querySelector("#reimbursementCount");
  dom.candidateListTableBody = document.querySelector("#reimbursementCandidateListTableBody");
  dom.candidateListLoadingState = document.querySelector("#reimbursementCandidateListLoadingState");
  dom.candidateListEmptyState = document.querySelector("#reimbursementCandidateListEmptyState");
  dom.candidateListCount = document.querySelector("#reimbursementCandidateListCount");
  dom.openCreateReimbursementButton = document.querySelector("#openCreateReimbursementButton");
  dom.createReimbursementDialog = document.querySelector("#createReimbursementDialog");
  dom.createReimbursementError = document.querySelector("#createReimbursementError");
  dom.createReimbursementDateInput = document.querySelector("#createReimbursementDateInput");
  dom.createReimbursementMonthInput = document.querySelector("#createReimbursementMonthInput");
  dom.createReimbursementFromAccountSelect = document.querySelector("#createReimbursementFromAccountSelect");
  dom.createReimbursementToAccountSelect = document.querySelector("#createReimbursementToAccountSelect");
  dom.createReimbursementSelectedCount = document.querySelector("#createReimbursementSelectedCount");
  dom.createReimbursementTotalAmount = document.querySelector("#createReimbursementTotalAmount");
  dom.createReimbursementCurrency = document.querySelector("#createReimbursementCurrency");
  dom.createReimbursementCandidateCount = document.querySelector("#createReimbursementCandidateCount");
  dom.createReimbursementCandidateLoading = document.querySelector("#createReimbursementCandidateLoading");
  dom.createReimbursementCandidateEmpty = document.querySelector("#createReimbursementCandidateEmpty");
  dom.createReimbursementCandidateRows = document.querySelector("#createReimbursementCandidateRows");
  dom.createReimbursementNoteInput = document.querySelector("#createReimbursementNoteInput");
  dom.createReimbursementSubmitButton = document.querySelector("#createReimbursementSubmitButton");
  dom.createReimbursementCancelButton = document.querySelector("#createReimbursementCancelButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    applyQuery();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    applyQuery();
  });

  dom.openCreateReimbursementButton.addEventListener("click", openCreateReimbursementDialog);
  dom.createReimbursementCancelButton.addEventListener("click", closeCreateReimbursementDialog);
  dom.createReimbursementSubmitButton.addEventListener("click", submitCreateReimbursement);
  dom.createReimbursementCandidateRows.addEventListener("change", handleCandidateSelectionChange);

  for (const [input, fieldId] of [
    [dom.createReimbursementDateInput, "reimbursementDate"],
    [dom.createReimbursementFromAccountSelect, "fromAccount"],
    [dom.createReimbursementToAccountSelect, "toAccount"],
  ]) {
    input.addEventListener("input", () => {
      clearCreateFieldInvalid(fieldId);
      hideCreateErrorIfClean();
    });
    input.addEventListener("change", () => {
      clearCreateFieldInvalid(fieldId);
      hideCreateErrorIfClean();
    });
  }
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.fromAccountSelect.value = DEFAULT_FILTERS.fromAccountId;
  dom.toAccountSelect.value = DEFAULT_FILTERS.toAccountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.statusSelect.value = DEFAULT_FILTERS.status;
  dom.hasItemsSelect.value = DEFAULT_FILTERS.hasItems;
  dom.hasTransactionsSelect.value = DEFAULT_FILTERS.hasTransactions;
  dom.keywordInput.value = DEFAULT_FILTERS.keyword;
}

async function loadInitialData() {
  setLoading(true);
  showMessage("info", "正在加载报销管理数据...");

  try {
    const lookups = await fetchReimbursementLookups();
    businessEntities = lookups.businessEntities;
    accounts = lookups.accounts;
    renderMasterOptions();
    await loadReimbursementMonth(currentYearMonth());
    applyCurrentFilters();
    showMessage("success", "报销管理数据已加载。");
  } catch (error) {
    businessEntities = [];
    accounts = [];
    reimbursementRecords = [];
    reimbursementCandidateExpenses = [];
    itemCounts = new Map();
    transactionCounts = new Map();
    loadedMonth = "";
    renderMasterOptions();
    renderDataOptions([], []);
    renderCandidateExpenses([]);
    renderReimbursements([]);
    showMessage("error", `读取报销管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

async function applyQuery() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  if (filters.month !== loadedMonth) {
    setLoading(true);
    showMessage("info", "正在加载报销记录...");

    try {
      await loadReimbursementMonth(filters.month);
      restoreFilterSelections(filters);
      applyCurrentFilters();
      showMessage("success", "报销管理数据已加载。");
    } catch (error) {
      reimbursementRecords = [];
      reimbursementCandidateExpenses = [];
      itemCounts = new Map();
      transactionCounts = new Map();
      loadedMonth = "";
      renderDataOptions([], []);
      renderCandidateExpenses([]);
      renderReimbursements([]);
      showMessage("error", `读取报销管理数据失败：${error.message || error}`);
    } finally {
      setLoading(false);
    }
    return;
  }

  applyCurrentFilters();
}

async function loadReimbursementMonth(month) {
  const [records, candidates] = await Promise.all([
    fetchReimbursementRecords(month),
    fetchReimbursementCandidateExpenses({ month }),
  ]);
  reimbursementRecords = records;
  reimbursementCandidateExpenses = candidates;
  const ids = reimbursementRecords.map((row) => row.id).filter(Boolean);
  const [itemRows, transactionRows] = await Promise.all([
    fetchReimbursementItemCounts(ids),
    fetchReimbursementTransactionCounts(ids),
  ]);

  itemCounts = countByKey(itemRows, "reimbursement_id");
  transactionCounts = countByKey(transactionRows, "related_id");
  loadedMonth = month;
  renderDataOptions(reimbursementRecords, reimbursementCandidateExpenses);
}

function applyCurrentFilters() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  restoreFilterSelections(filters);
  renderCandidateExpenses(filterCandidateExpenses(reimbursementCandidateExpenses, filters));
  renderReimbursements(filterReimbursements(reimbursementRecords, filters));
}

function readFilters() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month,
    fromAccountId: dom.fromAccountSelect.value,
    toAccountId: dom.toAccountSelect.value,
    currency: dom.currencySelect.value,
    status: dom.statusSelect.value,
    hasItems: dom.hasItemsSelect.value,
    hasTransactions: dom.hasTransactionsSelect.value,
    keyword: dom.keywordInput.value.trim(),
  };
}

function restoreFilterSelections(filters) {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, filters.month);
  dom.fromAccountSelect.value = filters.fromAccountId;
  dom.toAccountSelect.value = filters.toAccountId;
  dom.currencySelect.value = filters.currency;
  dom.statusSelect.value = filters.status;
  dom.hasItemsSelect.value = filters.hasItems;
  dom.hasTransactionsSelect.value = filters.hasTransactions;
  dom.keywordInput.value = filters.keyword;
}

function renderMasterOptions() {
  renderEntityOptions(dom.fromAccountSelect, accounts, accountName);
  renderEntityOptions(dom.toAccountSelect, accounts, accountName);
}

function renderDataOptions(reimbursementRows, candidateRows) {
  renderValueOptions(
    dom.currencySelect,
    distinctValues([...reimbursementRows, ...candidateRows], "currency"),
    displayValue
  );
  renderValueOptions(
    dom.statusSelect,
    uniqueValues([
      ...distinctValues(reimbursementRows, "status"),
      ...distinctValues(candidateRows, "reimbursement_status"),
    ]),
    reimbursementStatusLabel
  );
}

function renderEntityOptions(selectEl, rows, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const row of rows) {
    options.push(
      `<option value="${escapeAttribute(row.id)}">${escapeHtml(labelGetter(row))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderValueOptions(selectEl, values, labelGetter) {
  const options = ['<option value="">全部</option>'];

  for (const value of values) {
    options.push(
      `<option value="${escapeAttribute(value)}">${escapeHtml(labelGetter(value))}</option>`
    );
  }

  selectEl.innerHTML = options.join("");
}

function renderReimbursements(rows) {
  dom.reimbursementCount.textContent = `${rows.length} 条`;
  dom.emptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.tableBody.innerHTML = "";
    return;
  }

  dom.tableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="reimbursement-nowrap"><a class="button table-action-button" href="./reimbursement-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDateOnly(row.reimbursement_date))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(formatMonth(row.year_month))}</td>
      <td>${escapeHtml(accountNameById(row.from_account_id))}</td>
      <td>${escapeHtml(accountNameById(row.to_account_id))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.status))}">${escapeHtml(reimbursementStatusLabel(row.status))}</span></td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(displayCount(itemCount(row.id)))}</td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(displayCount(transactionCount(row.id)))}</td>
      <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDate(row.created_at))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDate(row.updated_at))}</td>
    </tr>
  `).join("");
}

function renderCandidateExpenses(rows) {
  dom.candidateListCount.textContent = `${rows.length} 条`;
  dom.candidateListEmptyState.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.candidateListTableBody.innerHTML = "";
    return;
  }

  dom.candidateListTableBody.innerHTML = rows.map((row) => `
    <tr>
      <td class="reimbursement-nowrap"><a class="button table-action-button" href="./expense-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDateOnly(row.expense_date))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(expenseCategoryLabel(row.expense_category))}</td>
      <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.description))}</span></td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td>${escapeHtml(accountNameById(row.account_id))}</td>
      <td><span class="status-badge ${escapeAttribute(statusClass(row.reimbursement_status))}">${escapeHtml(reimbursementStatusLabel(row.reimbursement_status))}</span></td>
      <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.note))}</span></td>
    </tr>
  `).join("");
}

async function openCreateReimbursementDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  resetCreateReimbursementForm();
  dom.createReimbursementDialog.classList.remove("is-hidden");
  dom.createReimbursementDialog.setAttribute("aria-hidden", "false");
  await loadCreateReimbursementCandidates();
}

function closeCreateReimbursementDialog() {
  if (isCreateSubmitting) {
    return;
  }

  dom.createReimbursementDialog.classList.add("is-hidden");
  dom.createReimbursementDialog.setAttribute("aria-hidden", "true");
}

function resetCreateReimbursementForm() {
  clearCreateErrors();
  candidateExpenses = [];
  selectedExpenseIds = new Set();
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter) || currentYearMonth();
  dom.createReimbursementDateInput.value = defaultReimbursementDateForMonth(month);
  dom.createReimbursementMonthInput.value = month;
  dom.createReimbursementFromAccountSelect.innerHTML = '<option value="">请先选择支出</option>';
  dom.createReimbursementToAccountSelect.innerHTML = '<option value="">请先选择支出</option>';
  dom.createReimbursementNoteInput.value = "";
  renderCreateCandidateRows([]);
  updateCreateSummary();
  setCreateSubmitting(false);
}

async function loadCreateReimbursementCandidates() {
  const month = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!month) {
    showCreateError("请选择正确的年月。", ["expenses"]);
    return;
  }

  dom.createReimbursementMonthInput.value = month;
  setCreateCandidateLoading(true);

  try {
    candidateExpenses = await fetchReimbursementCandidateExpenses({
      month,
      currency: dom.currencySelect.value,
    });
    selectedExpenseIds = new Set();
    renderCreateCandidateRows(candidateExpenses);
    updateCreateSummary();
  } catch (error) {
    candidateExpenses = [];
    selectedExpenseIds = new Set();
    renderCreateCandidateRows([]);
    updateCreateSummary();
    showCreateError(`读取待报销支出失败：${error.message || error}`, ["expenses"]);
  } finally {
    setCreateCandidateLoading(false);
  }
}

function renderCreateCandidateRows(rows) {
  dom.createReimbursementCandidateCount.textContent = `${rows.length} 条`;
  dom.createReimbursementCandidateEmpty.classList.toggle("is-hidden", rows.length > 0);

  if (!rows.length) {
    dom.createReimbursementCandidateRows.innerHTML = "";
    return;
  }

  dom.createReimbursementCandidateRows.innerHTML = rows.map((row) => `
    <tr>
      <td class="reimbursement-nowrap">
        <input type="checkbox" data-reimbursement-expense-id="${escapeAttribute(row.id)}" aria-label="选择支出 ${escapeAttribute(row.description || row.id)}">
      </td>
      <td class="reimbursement-nowrap">${escapeHtml(formatDateOnly(row.expense_date))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(expenseCategoryLabel(row.expense_category))}</td>
      <td class="reimbursement-note-cell"><span class="table-cell-summary">${escapeHtml(displayValue(row.description))}</span></td>
      <td>${escapeHtml(accountNameById(row.account_id))}</td>
      <td class="number-cell reimbursement-nowrap">${escapeHtml(formatCurrency(row.amount, row.currency))}</td>
      <td class="reimbursement-nowrap">${escapeHtml(displayValue(row.currency))}</td>
      <td class="reimbursement-nowrap"><a class="button table-action-button" href="./expense-detail.html?id=${encodeURIComponent(row.id)}">详情</a></td>
    </tr>
  `).join("");
}

function handleCandidateSelectionChange(event) {
  const checkbox = event.target.closest("[data-reimbursement-expense-id]");
  if (!checkbox) {
    return;
  }

  const expenseId = checkbox.dataset.reimbursementExpenseId;
  if (checkbox.checked) {
    selectedExpenseIds.add(expenseId);
  } else {
    selectedExpenseIds = new Set(Array.from(selectedExpenseIds).filter((id) => id !== expenseId));
  }

  clearCreateFieldInvalid("expenses");
  hideCreateErrorIfClean();
  updateCreateSummary();
}

async function submitCreateReimbursement() {
  if (isCreateSubmitting) {
    return;
  }

  clearCreateErrors();
  const payload = readCreateReimbursementPayload();
  if (!payload) {
    return;
  }

  setCreateSubmitting(true);

  try {
    const result = await createReimbursementRecord(payload);
    setCreateSubmitting(false);
    closeCreateReimbursementDialog();
    await refreshCurrentReimbursementList();
    showReimbursementCreateSuccess(result);
  } catch (error) {
    console.error(error);
    showCreateError(`确认报销失败：${error.message || error}`, createFieldIdsForError(error.message || ""));
  } finally {
    setCreateSubmitting(false);
  }
}

function readCreateReimbursementPayload() {
  const reimbursementDate = dom.createReimbursementDateInput.value;
  if (!reimbursementDate) {
    showCreateError("请选择报销日期。", ["reimbursementDate"]);
    return null;
  }

  const candidateMonth = dom.createReimbursementMonthInput.value;
  if (candidateMonth && reimbursementDate.slice(0, 7) !== candidateMonth) {
    showCreateError("报销日期需要与候选支出月份一致。", ["reimbursementDate"]);
    return null;
  }

  const selectedExpenses = createSelectedExpenses();
  if (!selectedExpenses.length) {
    showCreateError("请选择要报销的支出。", ["expenses"]);
    return null;
  }

  const summary = createSelectionSummary(selectedExpenses);
  if (summary.hasMixedBusinessEntity) {
    showCreateError("已选支出内部范围不一致。", ["expenses"]);
    return null;
  }

  if (summary.hasMixedCurrency) {
    showCreateError("已选支出币种不一致。", ["expenses"]);
    return null;
  }

  if (!summary.businessEntityId || !summary.currency) {
    showCreateError("已选支出缺少内部范围或币种。", ["expenses"]);
    return null;
  }

  if (!Number.isFinite(summary.totalAmount) || summary.totalAmount <= 0) {
    showCreateError("报销金额必须大于 0。", ["expenses"]);
    return null;
  }

  const fromAccountId = dom.createReimbursementFromAccountSelect.value;
  const toAccountId = dom.createReimbursementToAccountSelect.value;
  if (!fromAccountId || !toAccountId) {
    showCreateError("请选择出金账户和入金账户。", ["fromAccount", "toAccount"]);
    return null;
  }

  if (fromAccountId === toAccountId) {
    showCreateError("出金账户和入金账户不能相同。", ["fromAccount", "toAccount"]);
    return null;
  }

  const fromAccount = accounts.find((item) => item.id === fromAccountId);
  const toAccount = accounts.find((item) => item.id === toAccountId);
  if (!isValidReimbursementAccount(fromAccount, summary) || !isValidReimbursementAccount(toAccount, summary)) {
    showCreateError("账户币种与支出币种不一致。", ["fromAccount", "toAccount"]);
    return null;
  }

  return {
    reimbursementDate,
    businessEntityId: summary.businessEntityId,
    fromAccountId,
    toAccountId,
    expenseIds: selectedExpenses.map((row) => row.id),
    note: dom.createReimbursementNoteInput.value.trim(),
  };
}

async function refreshCurrentReimbursementList() {
  const filters = readFilters();
  if (!filters) {
    return;
  }

  await loadReimbursementMonth(filters.month);
  restoreFilterSelections(filters);
  applyCurrentFilters();
}

function showReimbursementCreateSuccess(result) {
  const reimbursementId = result?.reimbursement_id;
  dom.messageArea.className = "message message-success";
  if (reimbursementId) {
    dom.messageArea.innerHTML = `报销已确认。<a href="${escapeAttribute(reimbursementDetailUrl(reimbursementId))}">查看详情</a>`;
  } else {
    dom.messageArea.textContent = "报销已确认。";
  }
}

function updateCreateSummary() {
  const selectedExpenses = createSelectedExpenses();
  const summary = createSelectionSummary(selectedExpenses);
  dom.createReimbursementSelectedCount.textContent = `${selectedExpenses.length} 条`;
  dom.createReimbursementTotalAmount.textContent = selectedExpenses.length
    ? formatCurrency(summary.totalAmount, summary.currency)
    : "-";
  dom.createReimbursementCurrency.textContent = summary.hasMixedCurrency
    ? "币种不一致"
    : displayValue(summary.currency);
  renderCreateAccountOptions(summary);
}

function createSelectedExpenses() {
  return candidateExpenses.filter((row) => selectedExpenseIds.has(row.id));
}

function createSelectionSummary(rows) {
  const businessEntityIds = distinctRawValues(rows, "business_entity_id");
  const currencies = distinctRawValues(rows, "currency");
  return {
    businessEntityId: businessEntityIds.length === 1 ? businessEntityIds[0] : "",
    currency: currencies.length === 1 ? currencies[0] : "",
    totalAmount: rows.reduce((sum, row) => sum + Number(row.amount || 0), 0),
    hasMixedBusinessEntity: businessEntityIds.length > 1,
    hasMixedCurrency: currencies.length > 1,
  };
}

function distinctRawValues(rows, key) {
  return Array.from(new Set(rows.map((row) => row[key]).filter(Boolean)));
}

function renderCreateAccountOptions(summary = createSelectionSummary(createSelectedExpenses())) {
  const fromSelected = dom.createReimbursementFromAccountSelect.value;
  const toSelected = dom.createReimbursementToAccountSelect.value;
  const filteredAccounts = filteredReimbursementAccounts(summary);
  const options = [
    `<option value="">${summary.businessEntityId && summary.currency ? "请选择账户" : "请先选择支出"}</option>`,
    ...filteredAccounts.map((account) => `<option value="${escapeAttribute(account.id)}">${escapeHtml(createAccountLabel(account))}</option>`),
  ];

  dom.createReimbursementFromAccountSelect.innerHTML = options.join("");
  dom.createReimbursementToAccountSelect.innerHTML = options.join("");
  dom.createReimbursementFromAccountSelect.disabled = !filteredAccounts.length;
  dom.createReimbursementToAccountSelect.disabled = !filteredAccounts.length;

  if (filteredAccounts.some((account) => account.id === fromSelected)) {
    dom.createReimbursementFromAccountSelect.value = fromSelected;
  }

  if (filteredAccounts.some((account) => account.id === toSelected)) {
    dom.createReimbursementToAccountSelect.value = toSelected;
  }
}

function filteredReimbursementAccounts(summary) {
  if (!summary.businessEntityId || !summary.currency || summary.hasMixedBusinessEntity || summary.hasMixedCurrency) {
    return [];
  }

  return accounts.filter((account) => isValidReimbursementAccount(account, summary));
}

function isValidReimbursementAccount(account, summary) {
  return Boolean(
    account &&
    account.app_type === "school" &&
    account.is_active === true &&
    account.business_entity_id === summary.businessEntityId &&
    account.currency === summary.currency
  );
}

function createAccountLabel(account) {
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
  ].filter(Boolean).join(" / ");
}

function setCreateCandidateLoading(isLoading) {
  dom.createReimbursementCandidateLoading.classList.toggle("is-hidden", !isLoading);
}

function setCreateSubmitting(isSubmitting) {
  isCreateSubmitting = isSubmitting;
  dom.createReimbursementSubmitButton.disabled = isSubmitting;
  dom.createReimbursementCancelButton.disabled = isSubmitting;
  dom.createReimbursementSubmitButton.textContent = isSubmitting ? "保存中..." : "确认报销";
}

function clearCreateErrors() {
  dom.createReimbursementError.textContent = "";
  dom.createReimbursementError.classList.add("is-hidden");
  for (const fieldId of CREATE_REIMBURSEMENT_FIELD_IDS) {
    clearCreateFieldInvalid(fieldId);
  }
}

function showCreateError(message, fieldIds = []) {
  dom.createReimbursementError.textContent = message;
  dom.createReimbursementError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setCreateFieldInvalid(fieldId, true);
  }
  dom.createReimbursementDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function createFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("支出") || text.includes("报销金额")) fields.push("expenses");
  if (text.includes("账户") || text.includes("币种")) fields.push("fromAccount", "toAccount");
  if (text.includes("报销日期")) fields.push("reimbursementDate");
  return Array.from(new Set(fields));
}

function setCreateFieldInvalid(fieldId, invalid) {
  const field = dom.createReimbursementDialog.querySelector(`[data-create-reimbursement-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearCreateFieldInvalid(fieldId) {
  setCreateFieldInvalid(fieldId, false);
}

function hideCreateErrorIfClean() {
  const hasInvalidField = Boolean(dom.createReimbursementDialog.querySelector(".field.is-invalid, .is-invalid[data-create-reimbursement-field]"));
  if (!hasInvalidField) {
    dom.createReimbursementError.textContent = "";
    dom.createReimbursementError.classList.add("is-hidden");
  }
}

function reimbursementDetailUrl(id) {
  return `./reimbursement-detail.html?id=${encodeURIComponent(id)}`;
}

function filterReimbursements(rows, filters) {
  return rows.filter((row) => {

    if (filters.fromAccountId && row.from_account_id !== filters.fromAccountId) {
      return false;
    }

    if (filters.toAccountId && row.to_account_id !== filters.toAccountId) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    if (filters.status && row.status !== filters.status) {
      return false;
    }

    if (!matchesCountFilter(itemCount(row.id), filters.hasItems)) {
      return false;
    }

    if (!matchesCountFilter(transactionCount(row.id), filters.hasTransactions)) {
      return false;
    }

    return matchesKeyword(row, filters.keyword);
  });
}

function filterCandidateExpenses(rows, filters) {
  return rows.filter((row) => {

    const accountFilters = [filters.fromAccountId, filters.toAccountId].filter(Boolean);
    if (accountFilters.length && !accountFilters.includes(row.account_id)) {
      return false;
    }

    if (filters.currency && row.currency !== filters.currency) {
      return false;
    }

    if (filters.status && row.reimbursement_status !== filters.status) {
      return false;
    }

    return matchesCandidateKeyword(row, filters.keyword);
  });
}

function matchesKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    accountNameById(row.from_account_id),
    accountNameById(row.to_account_id),
    row.currency,
    reimbursementStatusLabel(row.status),
    row.status,
    row.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function matchesCandidateKeyword(row, keyword) {
  if (!keyword) {
    return true;
  }

  const normalizedKeyword = keyword.toLowerCase();
  return [
    accountNameById(row.account_id),
    expenseCategoryLabel(row.expense_category),
    reimbursementStatusLabel(row.reimbursement_status),
    row.reimbursement_status,
    row.description,
    row.currency,
    row.note,
  ]
    .map((value) => safeText(value).toLowerCase())
    .some((value) => value.includes(normalizedKeyword));
}

function matchesCountFilter(count, filterValue) {
  if (!filterValue) {
    return true;
  }

  if (filterValue === "yes") {
    return count > 0;
  }

  if (filterValue === "no") {
    return count === 0;
  }

  return true;
}

function countByKey(rows, key) {
  const result = new Map();

  for (const row of rows) {
    const value = row[key];
    if (!value) {
      continue;
    }

    result.set(value, (result.get(value) || 0) + 1);
  }

  return result;
}

function itemCount(id) {
  return itemCounts.get(id) || 0;
}

function transactionCount(id) {
  return transactionCounts.get(id) || 0;
}

function distinctValues(rows, key) {
  return Array.from(
    new Set(
      rows
        .map((row) => safeText(row[key]).trim())
        .filter(Boolean)
    )
  ).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function uniqueValues(values) {
  return Array.from(new Set(values.filter(Boolean))).sort((left, right) => left.localeCompare(right, "zh-CN"));
}

function accountNameById(id) {
  const account = accounts.find((item) => item.id === id);
  if (!account) {
    return id ? "未知" : "未设置";
  }

  return accountName(account);
}

function accountName(account) {
  const name = safeText(account.name) || "未设置";
  const currency = safeText(account.currency);
  return currency ? `${name} / ${currency}` : name;
}

function reimbursementStatusLabel(value) {
  return REIMBURSEMENT_STATUS_LABELS[value] || displayValue(value);
}

function expenseCategoryLabel(value) {
  return EXPENSE_CATEGORY_LABELS[value] || displayValue(value);
}

function statusClass(status) {
  if (status === "paid") {
    return "status-paid";
  }

  return "status-neutral";
}

function formatDateOnly(value) {
  return safeText(value) || "-";
}

function todayDateString() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function defaultReimbursementDateForMonth(month) {
  const today = todayDateString();
  return month === today.slice(0, 7) ? today : `${month}-01`;
}

function displayCount(value) {
  return Number(value || 0).toLocaleString("zh-CN");
}

function displayValue(value) {
  return safeText(value) || "-";
}

function setLoading(isLoading) {
  dom.loadingState.classList.toggle("is-hidden", !isLoading);
  dom.candidateListLoadingState.classList.toggle("is-hidden", !isLoading);
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
