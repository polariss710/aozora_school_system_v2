import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js";
import {
  createAccountAdjustment,
  createAccountTransfer,
  fetchAccountTransactions,
  fetchAccountTransactionTypes,
  fetchAccounts,
  fetchBusinessEntitiesForAccounts,
} from "../api/account-api.js";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const DEFAULT_FILTERS = {
  accountId: "",
  businessEntityId: "",
  currency: "",
  transactionType: "",
};

const COMMON_TRANSACTION_TYPES = [
  "account_adjustment",
  "account_adjustment_reversal",
  "transfer_out",
  "transfer_in",
  "transfer_reverse_in",
  "transfer_reverse_out",
  "expense_adjust",
  "payment_reversal",
  "income",
  "expense",
  "transfer",
  "adjustment",
];

const TRANSACTION_TYPE_LABELS = {
  account_adjustment: "账户调整",
  account_adjustment_reversal: "账户调整撤销",
  transfer_out: "转账转出",
  transfer_in: "转账转入",
  transfer_reverse_in: "转账撤销入金",
  transfer_reverse_out: "转账撤销出金",
  expense_adjust: "支出调整 / 支付扣款",
  payment_reversal: "支付撤销",
  income: "收入",
  expense: "支出",
  transfer: "调拨",
  adjustment: "调整",
};

const ACCOUNT_TYPE_LABELS = {
  cash: "现金",
  bank: "银行",
  wallet: "钱包",
  receivable: "应收",
  payable: "应付",
};

const dom = {};
let accounts = [];
let businessEntities = [];
let transactions = [];
let isAdjustmentSubmitting = false;
let isTransferSubmitting = false;

export function initAccountPage() {
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
    renderAccounts([]);
    renderTransactions([]);
    return;
  }

  loadAccountData();
}

function cacheDom() {
  dom.messageArea = document.querySelector("#accountMessageArea");
  dom.filterForm = document.querySelector("#accountFilterForm");
  dom.yearFilter = document.querySelector("#accountYearFilter");
  dom.monthFilter = document.querySelector("#accountMonthFilter");
  dom.accountSelect = document.querySelector("#accountSelect");
  dom.businessEntitySelect = document.querySelector("#accountBusinessEntitySelect");
  dom.currencySelect = document.querySelector("#accountCurrencySelect");
  dom.transactionTypeSelect = document.querySelector("#transactionTypeSelect");
  dom.resetButton = document.querySelector("#accountResetButton");
  dom.accountGrid = document.querySelector("#accountGrid");
  dom.accountLoadingState = document.querySelector("#accountLoadingState");
  dom.accountEmptyState = document.querySelector("#accountEmptyState");
  dom.transactionTableBody = document.querySelector("#accountTransactionTableBody");
  dom.transactionLoadingState = document.querySelector("#accountTransactionLoadingState");
  dom.transactionEmptyState = document.querySelector("#accountTransactionEmptyState");
  dom.transactionCount = document.querySelector("#accountTransactionCount");
  dom.openAccountTransferButton = document.querySelector("#openAccountTransferButton");
  dom.accountTransferDialog = document.querySelector("#accountTransferDialog");
  dom.accountTransferError = document.querySelector("#accountTransferError");
  dom.accountTransferDateInput = document.querySelector("#accountTransferDateInput");
  dom.accountTransferBusinessEntitySelect = document.querySelector("#accountTransferBusinessEntitySelect");
  dom.accountTransferFromAccountSelect = document.querySelector("#accountTransferFromAccountSelect");
  dom.accountTransferToAccountSelect = document.querySelector("#accountTransferToAccountSelect");
  dom.accountTransferAmountInput = document.querySelector("#accountTransferAmountInput");
  dom.accountTransferPreview = document.querySelector("#accountTransferPreview");
  dom.accountTransferReasonInput = document.querySelector("#accountTransferReasonInput");
  dom.accountTransferNoteInput = document.querySelector("#accountTransferNoteInput");
  dom.accountTransferCancelButton = document.querySelector("#accountTransferCancelButton");
  dom.accountTransferSubmitButton = document.querySelector("#accountTransferSubmitButton");
  dom.openAccountAdjustmentButton = document.querySelector("#openAccountAdjustmentButton");
  dom.accountAdjustmentDialog = document.querySelector("#accountAdjustmentDialog");
  dom.accountAdjustmentError = document.querySelector("#accountAdjustmentError");
  dom.accountAdjustmentDateInput = document.querySelector("#accountAdjustmentDateInput");
  dom.accountAdjustmentBusinessEntitySelect = document.querySelector("#accountAdjustmentBusinessEntitySelect");
  dom.accountAdjustmentAccountSelect = document.querySelector("#accountAdjustmentAccountSelect");
  dom.accountAdjustmentAmountInput = document.querySelector("#accountAdjustmentAmountInput");
  dom.accountAdjustmentPreview = document.querySelector("#accountAdjustmentPreview");
  dom.accountAdjustmentReasonInput = document.querySelector("#accountAdjustmentReasonInput");
  dom.accountAdjustmentNoteInput = document.querySelector("#accountAdjustmentNoteInput");
  dom.accountAdjustmentCancelButton = document.querySelector("#accountAdjustmentCancelButton");
  dom.accountAdjustmentSubmitButton = document.querySelector("#accountAdjustmentSubmitButton");
}

function bindEvents() {
  dom.filterForm.addEventListener("submit", (event) => {
    event.preventDefault();
    loadAccountData();
  });

  dom.resetButton.addEventListener("click", () => {
    setDefaultFilters();
    loadAccountData();
  });

  dom.openAccountTransferButton.addEventListener("click", openAccountTransferDialog);
  dom.accountTransferCancelButton.addEventListener("click", closeAccountTransferDialog);
  dom.accountTransferSubmitButton.addEventListener("click", submitAccountTransfer);
  dom.accountTransferBusinessEntitySelect.addEventListener("change", () => {
    clearTransferFieldInvalid("businessEntity");
    renderTransferAccountOptions();
    updateTransferPreview();
    hideTransferErrorIfClean();
  });
  dom.accountTransferFromAccountSelect.addEventListener("change", () => {
    clearTransferFieldInvalid("fromAccount");
    renderTransferToAccountOptions();
    updateTransferPreview();
    hideTransferErrorIfClean();
  });
  dom.accountTransferToAccountSelect.addEventListener("change", () => {
    clearTransferFieldInvalid("toAccount");
    updateTransferPreview();
    hideTransferErrorIfClean();
  });
  dom.accountTransferAmountInput.addEventListener("input", () => {
    clearTransferFieldInvalid("amount");
    updateTransferPreview();
    hideTransferErrorIfClean();
  });
  dom.accountTransferDateInput.addEventListener("input", () => {
    clearTransferFieldInvalid("transferDate");
    hideTransferErrorIfClean();
  });
  dom.accountTransferReasonInput.addEventListener("input", () => {
    clearTransferFieldInvalid("reason");
    hideTransferErrorIfClean();
  });

  dom.openAccountAdjustmentButton.addEventListener("click", openAccountAdjustmentDialog);
  dom.accountAdjustmentCancelButton.addEventListener("click", closeAccountAdjustmentDialog);
  dom.accountAdjustmentSubmitButton.addEventListener("click", submitAccountAdjustment);
  dom.accountAdjustmentBusinessEntitySelect.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("businessEntity");
    renderAdjustmentAccountOptions();
    updateAdjustmentPreview();
    hideAdjustmentErrorIfClean();
  });
  dom.accountAdjustmentAccountSelect.addEventListener("change", () => {
    clearAdjustmentFieldInvalid("account");
    updateAdjustmentPreview();
    hideAdjustmentErrorIfClean();
  });
  dom.accountAdjustmentAmountInput.addEventListener("input", () => {
    clearAdjustmentFieldInvalid("amount");
    updateAdjustmentPreview();
    hideAdjustmentErrorIfClean();
  });
  dom.accountAdjustmentDateInput.addEventListener("input", () => {
    clearAdjustmentFieldInvalid("adjustmentDate");
    hideAdjustmentErrorIfClean();
  });
  dom.accountAdjustmentReasonInput.addEventListener("input", () => {
    clearAdjustmentFieldInvalid("reason");
    hideAdjustmentErrorIfClean();
  });
}

function setDefaultFilters() {
  setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, currentYearMonth());
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.businessEntitySelect.value = DEFAULT_FILTERS.businessEntityId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
  dom.transactionTypeSelect.value = DEFAULT_FILTERS.transactionType;
}

async function loadAccountData() {
  if (!hasSupabaseConfig()) {
    return;
  }

  const filters = readFilters();
  if (!filters) {
    return;
  }

  setLoading(true);
  showMessage("info", "正在加载账户管理数据...");

  let transactionTypeWarning = "";

  try {
    const [accountRows, businessEntityRows, transactionTypeRows, transactionRows] = await Promise.all([
      fetchAccounts(),
      fetchBusinessEntitiesForAccounts(),
      fetchAccountTransactionTypes().catch((error) => {
        transactionTypeWarning = `流水类型读取失败，已保留固定选项：${error.message || error}`;
        return [];
      }),
      fetchAccountTransactions(filters),
    ]);

    accounts = accountRows;
    businessEntities = businessEntityRows;
    transactions = transactionRows;

    renderAccountOptions(accounts);
    renderBusinessEntityOptions(businessEntities);
    renderTransactionTypeOptions(mergeTransactionTypes(transactionTypeRows));
    restoreFilterSelections(filters);
    renderAccounts(filterAccountsForDisplay(accounts, filters));
    renderTransactions(transactions);
    showMessage(
      transactionTypeWarning ? "warning" : "success",
      transactionTypeWarning || "账户管理数据已加载。"
    );
  } catch (error) {
    accounts = [];
    businessEntities = [];
    transactions = [];
    renderAccountOptions([]);
    renderBusinessEntityOptions([]);
    renderTransactionTypeOptions(COMMON_TRANSACTION_TYPES);
    renderAccounts([]);
    renderTransactions([]);
    showMessage("error", `读取账户管理数据失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function readFilters() {
  const selectedMonth = getYearMonthSelectValue(dom.yearFilter, dom.monthFilter);
  if (!selectedMonth) {
    showMessage("error", "请选择正确的年月。");
    return null;
  }

  return {
    month: selectedMonth,
    accountId: dom.accountSelect.value,
    businessEntityId: dom.businessEntitySelect.value,
    currency: dom.currencySelect.value,
    transactionType: dom.transactionTypeSelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.accountSelect.value = filters.accountId;
  dom.businessEntitySelect.value = filters.businessEntityId;
  dom.currencySelect.value = filters.currency;
  dom.transactionTypeSelect.value = filters.transactionType;
}

function renderAccountOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const account of items) {
    const label = [
      account.name,
      account.currency,
      formatCurrency(account.current_balance, account.currency),
    ].filter(Boolean).join(" / ");

    options.push(
      `<option value="${escapeAttribute(account.id)}">${escapeHtml(label)}</option>`
    );
  }

  dom.accountSelect.innerHTML = options.join("");
}

function renderBusinessEntityOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const entity of items) {
    const name = entity.name || entity.id;
    options.push(
      `<option value="${escapeAttribute(entity.id)}">${escapeHtml(name)}</option>`
    );
  }

  dom.businessEntitySelect.innerHTML = options.join("");
}

function renderTransactionTypeOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const type of items) {
    options.push(
      `<option value="${escapeAttribute(type)}">${escapeHtml(transactionTypeLabel(type))}</option>`
    );
  }

  dom.transactionTypeSelect.innerHTML = options.join("");
}

function mergeTransactionTypes(actualTypes) {
  const normalizedActualTypes = (actualTypes || [])
    .map((type) => String(type || "").trim())
    .filter(Boolean);
  const commonSet = new Set(COMMON_TRANSACTION_TYPES);
  const extraTypes = Array.from(new Set(normalizedActualTypes))
    .filter((type) => !commonSet.has(type))
    .sort((a, b) => transactionTypeLabel(a).localeCompare(transactionTypeLabel(b), "zh-CN"));

  return [...COMMON_TRANSACTION_TYPES, ...extraTypes];
}

function filterAccountsForDisplay(items, filters) {
  return items.filter((account) => {
    if (filters.accountId && account.id !== filters.accountId) {
      return false;
    }

    if (filters.businessEntityId && account.business_entity_id !== filters.businessEntityId) {
      return false;
    }

    if (filters.currency && account.currency !== filters.currency) {
      return false;
    }

    return true;
  });
}

function renderAccounts(items) {
  dom.accountEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.accountGrid.innerHTML = "";
    return;
  }

  dom.accountGrid.innerHTML = items.map((account) => `
    <article class="account-card">
      <div class="account-card-header">
        <div>
          <div class="account-name">${escapeHtml(account.name)}</div>
          <div class="account-code">${escapeHtml(account.account_code || "-")}</div>
        </div>
        <span class="status-badge ${account.is_active ? "status-paid" : "status-cancelled"}">
          ${account.is_active ? "启用" : "停用"}
        </span>
      </div>
      <div class="account-balance">${escapeHtml(formatCurrency(account.current_balance, account.currency))}</div>
      <dl class="account-meta">
        <div>
          <dt>币种</dt>
          <dd>${escapeHtml(account.currency || "-")}</dd>
        </div>
        <div>
          <dt>类型</dt>
          <dd>${escapeHtml(accountTypeLabel(account.account_type))}</dd>
        </div>
        <div>
          <dt>公司账户</dt>
          <dd>${account.is_company_account ? "是" : "否"}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd>${escapeHtml(account.note || "-")}</dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function renderTransactions(items) {
  dom.transactionCount.textContent = `${items.length} 条`;
  dom.transactionEmptyState.classList.toggle("is-hidden", items.length > 0);

  if (!items.length) {
    dom.transactionTableBody.innerHTML = "";
    return;
  }

  dom.transactionTableBody.innerHTML = items.map((item) => {
    const account = findAccount(item.account_id);
    const businessEntity = findBusinessEntity(item.business_entity_id);
    const amountClass = Number(item.amount) >= 0 ? "amount-positive" : "amount-negative";
    const relatedText = [item.related_table, item.related_id].filter(Boolean).join(" / ") || "-";
    const description = item.description || item.note || "-";

    return `
      <tr>
        <td><a class="table-action-button" href="./account-transaction-detail.html?id=${encodeURIComponent(item.id)}">详情</a></td>
        <td>${escapeHtml(formatDate(item.transaction_date))}</td>
        <td>${escapeHtml(account?.name || item.account_id || "-")}</td>
        <td>${escapeHtml(businessEntity?.name || item.business_entity_id || "-")}</td>
        <td>${escapeHtml(transactionTypeLabel(item.transaction_type))}</td>
        <td>${escapeHtml(item.currency || "-")}</td>
        <td class="number-cell ${amountClass}">${escapeHtml(formatCurrency(item.amount, item.currency))}</td>
        <td class="number-cell">${escapeHtml(formatCurrency(item.balance_after, item.currency))}</td>
        <td class="description-cell">${escapeHtml(description)}</td>
        <td>${escapeHtml(relatedText)}</td>
        <td>${escapeHtml(formatDate(item.created_at))}</td>
      </tr>
    `;
  }).join("");
}

function openAccountTransferDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearTransferErrors();
  setTransferSubmitting(false);

  const filters = readFilters();
  const activeBusinessEntities = businessEntities.filter((entity) => entity.is_active !== false);
  const defaultBusinessEntityId = filters?.businessEntityId || "";
  const defaultFromAccountId = filters?.accountId || "";

  dom.accountTransferDateInput.value = currentDate();
  dom.accountTransferAmountInput.value = "";
  dom.accountTransferReasonInput.value = "";
  dom.accountTransferNoteInput.value = "";

  renderTransferBusinessEntityOptions(activeBusinessEntities);
  dom.accountTransferBusinessEntitySelect.value = activeBusinessEntities.some((entity) => entity.id === defaultBusinessEntityId)
    ? defaultBusinessEntityId
    : "";

  renderTransferAccountOptions();
  dom.accountTransferFromAccountSelect.value = filteredTransferFromAccounts().some((account) => account.id === defaultFromAccountId)
    ? defaultFromAccountId
    : "";
  renderTransferToAccountOptions();
  updateTransferPreview();

  dom.accountTransferDialog.classList.remove("is-hidden");
  dom.accountTransferDialog.setAttribute("aria-hidden", "false");
  dom.accountTransferDateInput.focus();
}

function closeAccountTransferDialog() {
  if (isTransferSubmitting) {
    return;
  }

  dom.accountTransferDialog.classList.add("is-hidden");
  dom.accountTransferDialog.setAttribute("aria-hidden", "true");
}

async function submitAccountTransfer() {
  if (isTransferSubmitting) {
    return;
  }

  clearTransferErrors();

  const payload = readAccountTransferPayload();
  if (!payload) {
    return;
  }

  setTransferSubmitting(true);

  try {
    const result = await createAccountTransfer(payload);
    setTransferSubmitting(false);
    closeAccountTransferDialog();
    await refreshAfterAccountTransfer(result);
    showAccountTransferSuccess(result);
  } catch (error) {
    console.error(error);
    showTransferError(`账户转账失败：${error.message || error}`, transferFieldIdsForError(error.message || ""));
  } finally {
    setTransferSubmitting(false);
  }
}

function readAccountTransferPayload() {
  const transferDate = dom.accountTransferDateInput.value;
  if (!transferDate) {
    showTransferError("请选择转账日期。", ["transferDate"]);
    return null;
  }

  const businessEntityId = dom.accountTransferBusinessEntitySelect.value;
  if (!businessEntityId) {
    showTransferError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

  const fromAccountId = dom.accountTransferFromAccountSelect.value;
  if (!fromAccountId) {
    showTransferError("请选择转出账户。", ["fromAccount"]);
    return null;
  }

  const toAccountId = dom.accountTransferToAccountSelect.value;
  if (!toAccountId) {
    showTransferError("请选择转入账户。", ["toAccount"]);
    return null;
  }

  if (fromAccountId === toAccountId) {
    showTransferError("转出账户和转入账户不能相同。", ["fromAccount", "toAccount"]);
    return null;
  }

  const fromAccount = accounts.find((item) => item.id === fromAccountId);
  const toAccount = accounts.find((item) => item.id === toAccountId);
  if (!isUsableTransferAccount(fromAccount)) {
    showTransferError("转出账户不存在或不可用。", ["fromAccount"]);
    return null;
  }

  if (!isUsableTransferAccount(toAccount)) {
    showTransferError("转入账户不存在或不可用。", ["toAccount"]);
    return null;
  }

  if (fromAccount.business_entity_id !== businessEntityId || toAccount.business_entity_id !== businessEntityId) {
    showTransferError("转账账户必须属于同一业务归属。", ["fromAccount", "toAccount"]);
    return null;
  }

  if (fromAccount.currency !== toAccount.currency) {
    showTransferError("转出账户和转入账户币种必须一致。", ["toAccount"]);
    return null;
  }

  const amount = Number(dom.accountTransferAmountInput.value);
  if (!Number.isFinite(amount) || amount <= 0) {
    showTransferError("转账金额必须大于 0。", ["amount"]);
    return null;
  }

  const reason = dom.accountTransferReasonInput.value.trim();
  if (!reason) {
    showTransferError("转账原因不能为空。", ["reason"]);
    return null;
  }

  return {
    transferDate,
    businessEntityId,
    fromAccountId,
    toAccountId,
    amount,
    reason,
    note: dom.accountTransferNoteInput.value.trim(),
  };
}

async function refreshAfterAccountTransfer(result) {
  if (result?.year_month) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, result.year_month);
  }

  if (result?.business_entity_id) {
    dom.businessEntitySelect.value = result.business_entity_id;
  }

  dom.accountSelect.value = "";
  dom.transactionTypeSelect.value = "";

  await loadAccountData();
}

function showAccountTransferSuccess(result) {
  const amountText = formatCurrency(result?.amount, result?.currency);
  const fromBalanceText = formatCurrency(result?.from_account_new_balance, result?.currency);
  const toBalanceText = formatCurrency(result?.to_account_new_balance, result?.currency);
  const links = [
    result?.from_account_transaction_id
      ? `<a href="./account-transaction-detail.html?id=${encodeURIComponent(result.from_account_transaction_id)}">查看转出流水</a>`
      : "",
    result?.to_account_transaction_id
      ? `<a href="./account-transaction-detail.html?id=${encodeURIComponent(result.to_account_transaction_id)}">查看转入流水</a>`
      : "",
  ].filter(Boolean).join(" / ");

  dom.messageArea.className = "message message-success";
  dom.messageArea.innerHTML = `账户转账已保存：${escapeHtml(amountText)}，转出后 ${escapeHtml(fromBalanceText)}，转入后 ${escapeHtml(toBalanceText)}。${links}`;
}

function renderTransferBusinessEntityOptions(items) {
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of items) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`);
  }
  dom.accountTransferBusinessEntitySelect.innerHTML = options.join("");
}

function renderTransferAccountOptions() {
  const selectedFromValue = dom.accountTransferFromAccountSelect.value;
  const options = ['<option value="">请选择转出账户</option>'];
  for (const account of filteredTransferFromAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(transferAccountLabel(account))}</option>`);
  }
  dom.accountTransferFromAccountSelect.innerHTML = options.join("");
  if (filteredTransferFromAccounts().some((account) => account.id === selectedFromValue)) {
    dom.accountTransferFromAccountSelect.value = selectedFromValue;
  }
  renderTransferToAccountOptions();
}

function renderTransferToAccountOptions() {
  const selectedToValue = dom.accountTransferToAccountSelect.value;
  const options = ['<option value="">请选择转入账户</option>'];
  for (const account of filteredTransferToAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(transferAccountLabel(account))}</option>`);
  }
  dom.accountTransferToAccountSelect.innerHTML = options.join("");
  if (filteredTransferToAccounts().some((account) => account.id === selectedToValue)) {
    dom.accountTransferToAccountSelect.value = selectedToValue;
  }
}

function filteredTransferFromAccounts() {
  const businessEntityId = dom.accountTransferBusinessEntitySelect.value;
  return accounts.filter((account) => {
    if (!isUsableTransferAccount(account)) {
      return false;
    }

    if (businessEntityId && account.business_entity_id !== businessEntityId) {
      return false;
    }

    return true;
  });
}

function filteredTransferToAccounts() {
  const businessEntityId = dom.accountTransferBusinessEntitySelect.value;
  const fromAccount = accounts.find((item) => item.id === dom.accountTransferFromAccountSelect.value);
  return accounts.filter((account) => {
    if (!isUsableTransferAccount(account)) {
      return false;
    }

    if (businessEntityId && account.business_entity_id !== businessEntityId) {
      return false;
    }

    if (fromAccount) {
      if (account.id === fromAccount.id) {
        return false;
      }

      if (account.currency !== fromAccount.currency) {
        return false;
      }
    }

    return true;
  });
}

function isUsableTransferAccount(account) {
  return Boolean(account && account.is_active === true && account.app_type === "school");
}

function transferAccountLabel(account) {
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
  ].filter(Boolean).join(" / ");
}

function updateTransferPreview() {
  const fromAccount = accounts.find((item) => item.id === dom.accountTransferFromAccountSelect.value);
  const toAccount = accounts.find((item) => item.id === dom.accountTransferToAccountSelect.value);
  const amount = Number(dom.accountTransferAmountInput.value);
  if (!fromAccount || !toAccount || !Number.isFinite(amount) || amount <= 0) {
    dom.accountTransferPreview.classList.add("is-hidden");
    dom.accountTransferPreview.innerHTML = "";
    return;
  }

  const fromCurrentBalance = Number(fromAccount.current_balance || 0);
  const toCurrentBalance = Number(toAccount.current_balance || 0);
  const fromNextBalance = fromCurrentBalance - amount;
  const toNextBalance = toCurrentBalance + amount;
  dom.accountTransferPreview.classList.remove("is-hidden");
  dom.accountTransferPreview.innerHTML = `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">币种</span>
      <span>${escapeHtml(fromAccount.currency || "-")}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">转出后</span>
      <span>${escapeHtml(formatCurrency(fromNextBalance, fromAccount.currency))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">转入后</span>
      <span>${escapeHtml(formatCurrency(toNextBalance, toAccount.currency))}</span>
    </div>
  `;
}

function setTransferSubmitting(isSubmitting) {
  isTransferSubmitting = isSubmitting;
  dom.accountTransferSubmitButton.disabled = isSubmitting;
  dom.accountTransferCancelButton.disabled = isSubmitting;
  dom.accountTransferSubmitButton.textContent = isSubmitting ? "保存中..." : "保存转账";
}

function clearTransferErrors() {
  dom.accountTransferError.textContent = "";
  dom.accountTransferError.classList.add("is-hidden");
  for (const fieldId of ["transferDate", "businessEntity", "fromAccount", "toAccount", "amount", "reason"]) {
    clearTransferFieldInvalid(fieldId);
  }
}

function showTransferError(message, fieldIds = []) {
  dom.accountTransferError.textContent = message;
  dom.accountTransferError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setTransferFieldInvalid(fieldId, true);
  }
  dom.accountTransferDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function transferFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期")) fields.push("transferDate");
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("转出")) fields.push("fromAccount");
  if (text.includes("转入")) fields.push("toAccount");
  if (text.includes("账户") || text.includes("币种")) fields.push("fromAccount", "toAccount");
  if (text.includes("金额")) fields.push("amount");
  if (text.includes("原因")) fields.push("reason");
  return Array.from(new Set(fields));
}

function setTransferFieldInvalid(fieldId, invalid) {
  const field = dom.accountTransferDialog.querySelector(`[data-account-transfer-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearTransferFieldInvalid(fieldId) {
  setTransferFieldInvalid(fieldId, false);
}

function hideTransferErrorIfClean() {
  const hasInvalidField = Boolean(dom.accountTransferDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.accountTransferError.textContent = "";
    dom.accountTransferError.classList.add("is-hidden");
  }
}

function openAccountAdjustmentDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearAdjustmentErrors();
  setAdjustmentSubmitting(false);

  const filters = readFilters();
  const activeBusinessEntities = businessEntities.filter((entity) => entity.is_active !== false);
  const defaultBusinessEntityId = filters?.businessEntityId || "";
  const defaultAccountId = filters?.accountId || "";

  dom.accountAdjustmentDateInput.value = currentDate();
  dom.accountAdjustmentAmountInput.value = "";
  dom.accountAdjustmentReasonInput.value = "";
  dom.accountAdjustmentNoteInput.value = "";

  renderAdjustmentBusinessEntityOptions(activeBusinessEntities);
  dom.accountAdjustmentBusinessEntitySelect.value = activeBusinessEntities.some((entity) => entity.id === defaultBusinessEntityId)
    ? defaultBusinessEntityId
    : "";

  renderAdjustmentAccountOptions();
  dom.accountAdjustmentAccountSelect.value = filteredAdjustmentAccounts().some((account) => account.id === defaultAccountId)
    ? defaultAccountId
    : "";
  updateAdjustmentPreview();

  dom.accountAdjustmentDialog.classList.remove("is-hidden");
  dom.accountAdjustmentDialog.setAttribute("aria-hidden", "false");
}

function closeAccountAdjustmentDialog() {
  if (isAdjustmentSubmitting) {
    return;
  }

  dom.accountAdjustmentDialog.classList.add("is-hidden");
  dom.accountAdjustmentDialog.setAttribute("aria-hidden", "true");
}

async function submitAccountAdjustment() {
  if (isAdjustmentSubmitting) {
    return;
  }

  clearAdjustmentErrors();

  const payload = readAccountAdjustmentPayload();
  if (!payload) {
    return;
  }

  setAdjustmentSubmitting(true);

  try {
    const result = await createAccountAdjustment(payload);
    setAdjustmentSubmitting(false);
    closeAccountAdjustmentDialog();
    await refreshAfterAccountAdjustment(result);
    showAccountAdjustmentSuccess(result);
  } catch (error) {
    console.error(error);
    showAdjustmentError(`账户调整失败：${error.message || error}`, adjustmentFieldIdsForError(error.message || ""));
  } finally {
    setAdjustmentSubmitting(false);
  }
}

function readAccountAdjustmentPayload() {
  const adjustmentDate = dom.accountAdjustmentDateInput.value;
  if (!adjustmentDate) {
    showAdjustmentError("请选择调整日期。", ["adjustmentDate"]);
    return null;
  }

  const businessEntityId = dom.accountAdjustmentBusinessEntitySelect.value;
  if (!businessEntityId) {
    showAdjustmentError("请选择业务归属。", ["businessEntity"]);
    return null;
  }

  const accountId = dom.accountAdjustmentAccountSelect.value;
  if (!accountId) {
    showAdjustmentError("请选择调整账户。", ["account"]);
    return null;
  }

  const account = accounts.find((item) => item.id === accountId);
  if (!account || account.is_active !== true || account.app_type !== "school") {
    showAdjustmentError("调整账户不存在或不可用。", ["account"]);
    return null;
  }

  if (account.business_entity_id !== businessEntityId) {
    showAdjustmentError("调整账户与业务归属不一致。", ["account"]);
    return null;
  }

  const amount = Number(dom.accountAdjustmentAmountInput.value);
  if (!Number.isFinite(amount) || amount === 0) {
    showAdjustmentError("调整金额不能为 0。", ["amount"]);
    return null;
  }

  const reason = dom.accountAdjustmentReasonInput.value.trim();
  if (!reason) {
    showAdjustmentError("调整原因不能为空。", ["reason"]);
    return null;
  }

  return {
    adjustmentDate,
    businessEntityId,
    accountId,
    amount,
    reason,
    note: dom.accountAdjustmentNoteInput.value.trim(),
  };
}

async function refreshAfterAccountAdjustment(result) {
  if (result?.year_month) {
    setYearMonthSelectValue(dom.yearFilter, dom.monthFilter, result.year_month);
  }

  if (result?.business_entity_id) {
    dom.businessEntitySelect.value = result.business_entity_id;
  }

  if (result?.account_id) {
    dom.accountSelect.value = result.account_id;
  }

  await loadAccountData();
}

function showAccountAdjustmentSuccess(result) {
  const amountText = formatCurrency(result?.amount, result?.currency);
  const balanceText = formatCurrency(result?.new_balance, result?.currency);
  dom.messageArea.className = "message message-success";
  if (result?.account_transaction_id) {
    dom.messageArea.innerHTML = `账户调整已保存：${escapeHtml(amountText)}，调整后余额 ${escapeHtml(balanceText)}。<a href="./account-transaction-detail.html?id=${encodeURIComponent(result.account_transaction_id)}">查看流水</a>`;
  } else {
    dom.messageArea.textContent = `账户调整已保存：${amountText}，调整后余额 ${balanceText}。`;
  }
}

function renderAdjustmentBusinessEntityOptions(items) {
  const options = ['<option value="">请选择业务归属</option>'];
  for (const entity of items) {
    options.push(`<option value="${escapeAttribute(entity.id)}">${escapeHtml(entity.name || entity.id)}</option>`);
  }
  dom.accountAdjustmentBusinessEntitySelect.innerHTML = options.join("");
}

function renderAdjustmentAccountOptions() {
  const selectedValue = dom.accountAdjustmentAccountSelect.value;
  const options = ['<option value="">请选择账户</option>'];
  for (const account of filteredAdjustmentAccounts()) {
    options.push(`<option value="${escapeAttribute(account.id)}">${escapeHtml(adjustmentAccountLabel(account))}</option>`);
  }
  dom.accountAdjustmentAccountSelect.innerHTML = options.join("");
  if (filteredAdjustmentAccounts().some((account) => account.id === selectedValue)) {
    dom.accountAdjustmentAccountSelect.value = selectedValue;
  }
}

function filteredAdjustmentAccounts() {
  const businessEntityId = dom.accountAdjustmentBusinessEntitySelect.value;
  return accounts.filter((account) => {
    if (account.is_active !== true || account.app_type !== "school") {
      return false;
    }

    if (businessEntityId && account.business_entity_id !== businessEntityId) {
      return false;
    }

    return true;
  });
}

function adjustmentAccountLabel(account) {
  return [
    account.name || account.account_code || account.id,
    account.currency || "-",
    formatCurrency(account.current_balance, account.currency),
  ].filter(Boolean).join(" / ");
}

function updateAdjustmentPreview() {
  const account = accounts.find((item) => item.id === dom.accountAdjustmentAccountSelect.value);
  const amount = Number(dom.accountAdjustmentAmountInput.value);
  if (!account || !Number.isFinite(amount) || amount === 0) {
    dom.accountAdjustmentPreview.classList.add("is-hidden");
    dom.accountAdjustmentPreview.innerHTML = "";
    return;
  }

  const currentBalance = Number(account.current_balance || 0);
  const nextBalance = currentBalance + amount;
  const direction = amount > 0 ? "增加" : "减少";
  dom.accountAdjustmentPreview.classList.remove("is-hidden");
  dom.accountAdjustmentPreview.innerHTML = `
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">方向</span>
      <span>${escapeHtml(direction)}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">调整前</span>
      <span>${escapeHtml(formatCurrency(currentBalance, account.currency))}</span>
    </div>
    <div class="dialog-summary-row">
      <span class="dialog-summary-label">调整后</span>
      <span>${escapeHtml(formatCurrency(nextBalance, account.currency))}</span>
    </div>
  `;
}

function setAdjustmentSubmitting(isSubmitting) {
  isAdjustmentSubmitting = isSubmitting;
  dom.accountAdjustmentSubmitButton.disabled = isSubmitting;
  dom.accountAdjustmentCancelButton.disabled = isSubmitting;
  dom.accountAdjustmentSubmitButton.textContent = isSubmitting ? "保存中..." : "保存调整";
}

function clearAdjustmentErrors() {
  dom.accountAdjustmentError.textContent = "";
  dom.accountAdjustmentError.classList.add("is-hidden");
  for (const fieldId of ["adjustmentDate", "businessEntity", "account", "amount", "reason"]) {
    clearAdjustmentFieldInvalid(fieldId);
  }
}

function showAdjustmentError(message, fieldIds = []) {
  dom.accountAdjustmentError.textContent = message;
  dom.accountAdjustmentError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setAdjustmentFieldInvalid(fieldId, true);
  }
  dom.accountAdjustmentDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function adjustmentFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("日期")) fields.push("adjustmentDate");
  if (text.includes("业务归属")) fields.push("businessEntity");
  if (text.includes("账户") || text.includes("币种")) fields.push("account");
  if (text.includes("金额")) fields.push("amount");
  if (text.includes("原因")) fields.push("reason");
  return fields;
}

function setAdjustmentFieldInvalid(fieldId, invalid) {
  const field = dom.accountAdjustmentDialog.querySelector(`[data-account-adjustment-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearAdjustmentFieldInvalid(fieldId) {
  setAdjustmentFieldInvalid(fieldId, false);
}

function hideAdjustmentErrorIfClean() {
  const hasInvalidField = Boolean(dom.accountAdjustmentDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.accountAdjustmentError.textContent = "";
    dom.accountAdjustmentError.classList.add("is-hidden");
  }
}

function currentDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function findAccount(accountId) {
  return accounts.find((account) => account.id === accountId);
}

function findBusinessEntity(entityId) {
  return businessEntities.find((entity) => entity.id === entityId);
}

function transactionTypeLabel(type) {
  return TRANSACTION_TYPE_LABELS[type] || safeText(type) || "-";
}

function accountTypeLabel(type) {
  return ACCOUNT_TYPE_LABELS[type] || safeText(type) || "-";
}

function setLoading(isLoading) {
  dom.accountLoadingState.classList.toggle("is-hidden", !isLoading);
  dom.transactionLoadingState.classList.toggle("is-hidden", !isLoading);
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
