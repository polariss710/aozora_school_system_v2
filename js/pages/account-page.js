import { PAYMENT_MONTH_FILTER_YEAR_RANGE } from "../config.js";
import { hasSupabaseConfig } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import {
  createAccountAdjustment,
  createAccountProfile,
  createAccountTransfer,
  fetchAccountTransactions,
  fetchAccounts,
  fetchBusinessEntitiesForAccounts,
  updateAccountProfile,
} from "../api/account-api.js?v=be-ui-20260806-1";
import {
  currentYearMonth,
  getYearMonthSelectValue,
  populateMonthSelect,
  populateYearSelect,
  setYearMonthSelectValue,
} from "../utils/month-filter.js";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";
import {
  requirePrimarySchoolBusinessEntityId,
} from "../utils/business-entity-policy.js?v=be-ui-20260806-1";

const DEFAULT_FILTERS = {
  appType: "school",
  accountId: "",
  currency: "",
};

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
  other: "其他",
  cny_yuebao: "余额宝",
  cny_yulibao: "余利宝",
  jpy_mufg_card: "日元三菱卡",
  jpy_rakuten_card: "日元乐天卡",
  jpy_cash: "日元现金",
};

const ACCOUNT_APP_TYPE_LABELS = {
  school: "学校业务",
  store: "店铺业务",
  family: "家庭账本",
};

const ACCOUNT_APP_TYPE_OPTIONS = ["school", "store", "family"];
const ACCOUNT_CREATABLE_APP_TYPE_OPTIONS = ["school", "family"];
const EDITABLE_ACCOUNT_TYPE_OPTIONS_BY_CURRENCY = {
  CNY: ["cny_yuebao", "cny_yulibao"],
  JPY: ["jpy_mufg_card", "jpy_rakuten_card", "jpy_cash"],
};
const EDITABLE_ACCOUNT_CURRENCY_OPTIONS = ["CNY", "JPY"];
const ACCOUNT_CREATE_FIELD_IDS = [
  "appType",
  "name",
  "currency",
  "accountType",
  "initialBalance",
  "companyAccount",
  "active",
];
const ACCOUNT_PROFILE_FIELD_IDS = [
  "appType",
  "name",
  "currency",
  "accountType",
  "companyAccount",
  "active",
];

const dom = {};
let accounts = [];
let businessEntities = [];
let transactions = [];
let editingAccount = null;
let isAccountCreateSubmitting = false;
let isAccountProfileSubmitting = false;
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
  dom.appTypeSelect = document.querySelector("#accountAppTypeSelect");
  dom.accountSelect = document.querySelector("#accountSelect");
  dom.currencySelect = document.querySelector("#accountCurrencySelect");
  dom.resetButton = document.querySelector("#accountResetButton");
  dom.accountGrid = document.querySelector("#accountGrid");
  dom.accountCount = document.querySelector("#accountCount");
  dom.accountLoadingState = document.querySelector("#accountLoadingState");
  dom.accountEmptyState = document.querySelector("#accountEmptyState");
  dom.transactionTableBody = document.querySelector("#accountTransactionTableBody");
  dom.transactionLoadingState = document.querySelector("#accountTransactionLoadingState");
  dom.transactionEmptyState = document.querySelector("#accountTransactionEmptyState");
  dom.transactionCount = document.querySelector("#accountTransactionCount");
  dom.openAccountCreateButton = document.querySelector("#openAccountCreateButton");
  dom.accountCreateDialog = document.querySelector("#accountCreateDialog");
  dom.accountCreateError = document.querySelector("#accountCreateError");
  dom.accountCreateAppTypeSelect = document.querySelector("#accountCreateAppTypeSelect");
  dom.accountCreateNameInput = document.querySelector("#accountCreateNameInput");
  dom.accountCreateTypeSelect = document.querySelector("#accountCreateTypeSelect");
  dom.accountCreateCurrencySelect = document.querySelector("#accountCreateCurrencySelect");
  dom.accountCreateInitialBalanceInput = document.querySelector("#accountCreateInitialBalanceInput");
  dom.accountCreateCompanySelect = document.querySelector("#accountCreateCompanySelect");
  dom.accountCreateActiveSelect = document.querySelector("#accountCreateActiveSelect");
  dom.accountCreateNoteInput = document.querySelector("#accountCreateNoteInput");
  dom.accountCreateCancelButton = document.querySelector("#accountCreateCancelButton");
  dom.accountCreateSubmitButton = document.querySelector("#accountCreateSubmitButton");
  dom.accountProfileDialog = document.querySelector("#accountProfileDialog");
  dom.accountProfileError = document.querySelector("#accountProfileError");
  dom.accountProfileAppTypeSelect = document.querySelector("#accountProfileAppTypeSelect");
  dom.accountProfileNameInput = document.querySelector("#accountProfileNameInput");
  dom.accountProfileCurrencySelect = document.querySelector("#accountProfileCurrencySelect");
  dom.accountProfileTypeSelect = document.querySelector("#accountProfileTypeSelect");
  dom.accountProfileCompanySelect = document.querySelector("#accountProfileCompanySelect");
  dom.accountProfileActiveSelect = document.querySelector("#accountProfileActiveSelect");
  dom.accountProfileNoteInput = document.querySelector("#accountProfileNoteInput");
  dom.accountProfileCancelButton = document.querySelector("#accountProfileCancelButton");
  dom.accountProfileSubmitButton = document.querySelector("#accountProfileSubmitButton");
  dom.openAccountTransferButton = document.querySelector("#openAccountTransferButton");
  dom.accountTransferDialog = document.querySelector("#accountTransferDialog");
  dom.accountTransferError = document.querySelector("#accountTransferError");
  dom.accountTransferDateInput = document.querySelector("#accountTransferDateInput");
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
  dom.appTypeSelect.addEventListener("change", () => {
    dom.accountSelect.value = "";
    loadAccountData();
  });

  dom.openAccountCreateButton.addEventListener("click", openAccountCreateDialog);
  dom.accountCreateCancelButton.addEventListener("click", closeAccountCreateDialog);
  dom.accountCreateSubmitButton.addEventListener("click", submitAccountCreate);
  dom.accountCreateAppTypeSelect.addEventListener("change", () => {
    clearAccountCreateFieldInvalid("appType");
    updateAccountCreateScopeControls();
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateNameInput.addEventListener("input", () => {
    clearAccountCreateFieldInvalid("name");
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateCurrencySelect.addEventListener("change", () => {
    clearAccountCreateFieldInvalid("currency");
    renderAccountCreateTypeOptions(dom.accountCreateCurrencySelect.value, dom.accountCreateTypeSelect.value);
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateTypeSelect.addEventListener("change", () => {
    clearAccountCreateFieldInvalid("accountType");
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateInitialBalanceInput.addEventListener("input", () => {
    clearAccountCreateFieldInvalid("initialBalance");
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateCompanySelect.addEventListener("change", () => {
    clearAccountCreateFieldInvalid("companyAccount");
    hideAccountCreateErrorIfClean();
  });
  dom.accountCreateActiveSelect.addEventListener("change", () => {
    clearAccountCreateFieldInvalid("active");
    hideAccountCreateErrorIfClean();
  });

  dom.accountGrid.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-account-id]");
    if (!button) {
      return;
    }

    openAccountProfileDialog(button.dataset.editAccountId);
  });

  dom.accountProfileCancelButton.addEventListener("click", closeAccountProfileDialog);
  dom.accountProfileSubmitButton.addEventListener("click", submitAccountProfile);
  dom.accountProfileNameInput.addEventListener("input", () => {
    clearAccountProfileFieldInvalid("name");
    hideAccountProfileErrorIfClean();
  });
  dom.accountProfileCurrencySelect.addEventListener("change", () => {
    clearAccountProfileFieldInvalid("currency");
    renderAccountProfileTypeOptions(
      dom.accountProfileCurrencySelect.value,
      dom.accountProfileTypeSelect.value,
      editingAccount
    );
    hideAccountProfileErrorIfClean();
  });
  dom.accountProfileTypeSelect.addEventListener("change", () => {
    clearAccountProfileFieldInvalid("accountType");
    hideAccountProfileErrorIfClean();
  });
  dom.accountProfileCompanySelect.addEventListener("change", () => {
    clearAccountProfileFieldInvalid("companyAccount");
    hideAccountProfileErrorIfClean();
  });
  dom.accountProfileActiveSelect.addEventListener("change", () => {
    clearAccountProfileFieldInvalid("active");
    hideAccountProfileErrorIfClean();
  });

  dom.openAccountTransferButton.addEventListener("click", openAccountTransferDialog);
  dom.accountTransferCancelButton.addEventListener("click", closeAccountTransferDialog);
  dom.accountTransferSubmitButton.addEventListener("click", submitAccountTransfer);
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
  dom.appTypeSelect.value = DEFAULT_FILTERS.appType;
  dom.accountSelect.value = DEFAULT_FILTERS.accountId;
  dom.currencySelect.value = DEFAULT_FILTERS.currency;
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

  try {
    const [accountRows, businessEntityRows, transactionRows] = await Promise.all([
      fetchAccounts(),
      fetchBusinessEntitiesForAccounts(),
      fetchAccountTransactions(filters),
    ]);

    accounts = accountRows;
    businessEntities = businessEntityRows;
    requirePrimarySchoolBusinessEntityId(businessEntities);
    transactions = transactionRows;

    renderAccountOptions(filterAccountsForOptionSelect(accounts, filters));
    restoreFilterSelections(filters);
    renderAccounts(filterAccountsForDisplay(accounts, filters));
    renderTransactions(transactions);
    showMessage("success", "账户管理数据已加载。");
  } catch (error) {
    accounts = [];
    businessEntities = [];
    transactions = [];
    renderAccountOptions([]);
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
    appType: dom.appTypeSelect.value || "",
    accountId: dom.accountSelect.value,
    currency: dom.currencySelect.value,
  };
}

function restoreFilterSelections(filters) {
  dom.appTypeSelect.value = filters.appType;
  dom.accountSelect.value = filters.accountId;
  dom.currencySelect.value = filters.currency;
}

function renderAccountOptions(items) {
  const options = ['<option value="">全部</option>'];

  for (const account of items) {
    const label = [
      account.name,
      account.currency,
      accountAppTypeLabel(account.app_type),
    ].filter(Boolean).join(" / ");

    options.push(
      `<option value="${escapeAttribute(account.id)}">${escapeHtml(label)}</option>`
    );
  }

  dom.accountSelect.innerHTML = options.join("");
}

function filterAccountsForOptionSelect(items, filters) {
  return items.filter((account) => {
    if (filters.appType && account.app_type !== filters.appType) {
      return false;
    }

    return true;
  });
}

function filterAccountsForDisplay(items, filters) {
  return items.filter((account) => {
    if (filters.appType && account.app_type !== filters.appType) {
      return false;
    }

    if (filters.accountId && account.id !== filters.accountId) {
      return false;
    }

    if (filters.currency && account.currency !== filters.currency) {
      return false;
    }

    return true;
  });
}

function renderAccounts(items) {
  if (dom.accountCount) {
    dom.accountCount.textContent = `共 ${items.length} 条`;
  }

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
        <span class="status-badge ${account.is_active ? "status-active" : "status-inactive"}">
          ${account.is_active ? "启用" : "停用"}
        </span>
      </div>
      <div class="table-actions">
        ${isEditableAccountAppType(account.app_type)
          ? `<button class="button" type="button" data-edit-account-id="${escapeAttribute(account.id)}">编辑基础信息</button>`
          : '<button class="button" type="button" disabled>暂不开放编辑</button>'}
      </div>
      <div class="account-balance">${escapeHtml(formatCurrency(account.current_balance, account.currency))}</div>
      <dl class="account-meta">
        <div>
          <dt>用途</dt>
          <dd>${escapeHtml(accountAppTypeLabel(account.app_type))}</dd>
        </div>
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
          <dd>${escapeHtml(accountCompanyLabel(account))}</dd>
        </div>
        <div>
          <dt>备注</dt>
          <dd>${escapeHtml(account.note || "-")}</dd>
        </div>
      </dl>
    </article>
  `).join("");
}

function openAccountCreateDialog() {
  if (!hasSupabaseConfig()) {
    showMessage("error", "请先在 js/config.js 填写 Supabase URL 和 anon key。");
    return;
  }

  clearAccountCreateErrors();
  setAccountCreateSubmitting(false);
  renderAccountCreateAppTypeOptions(
    ACCOUNT_CREATABLE_APP_TYPE_OPTIONS.includes(dom.appTypeSelect.value)
      ? dom.appTypeSelect.value
      : "school"
  );
  dom.accountCreateNameInput.value = "";
  renderAccountCreateCurrencyOptions("CNY");
  renderAccountCreateTypeOptions("CNY");
  dom.accountCreateInitialBalanceInput.value = "0";
  dom.accountCreateCompanySelect.value = "false";
  dom.accountCreateActiveSelect.value = "true";
  dom.accountCreateNoteInput.value = "";
  updateAccountCreateScopeControls();
  dom.accountCreateDialog.classList.remove("is-hidden");
  dom.accountCreateDialog.setAttribute("aria-hidden", "false");
  dom.accountCreateNameInput.focus();
}

function closeAccountCreateDialog({ force = false } = {}) {
  if (isAccountCreateSubmitting && !force) {
    return;
  }

  dom.accountCreateDialog.classList.add("is-hidden");
  dom.accountCreateDialog.setAttribute("aria-hidden", "true");
}

async function submitAccountCreate() {
  if (isAccountCreateSubmitting) {
    return;
  }

  clearAccountCreateErrors();

  const initialBalanceText = dom.accountCreateInitialBalanceInput.value.trim();
  const initialBalance = initialBalanceText === "" ? 0 : Number(initialBalanceText);
  const appType = dom.accountCreateAppTypeSelect.value;
  const payload = {
    appType,
    name: dom.accountCreateNameInput.value.trim(),
    accountType: dom.accountCreateTypeSelect.value,
    currency: dom.accountCreateCurrencySelect.value,
    businessEntityId: appType === "family" ? null : requirePrimarySchoolBusinessEntityId(businessEntities),
    initialBalance,
    isCompanyAccount: appType === "family" ? false : dom.accountCreateCompanySelect.value === "true",
    isActive: dom.accountCreateActiveSelect.value === "true",
    note: dom.accountCreateNoteInput.value.trim(),
  };

  if (!ACCOUNT_CREATABLE_APP_TYPE_OPTIONS.includes(payload.appType)) {
    showAccountCreateError("请选择有效账户用途。", ["appType"]);
    return;
  }

  if (!payload.name) {
    showAccountCreateError("请输入账户名称。", ["name"]);
    return;
  }

  if (!EDITABLE_ACCOUNT_CURRENCY_OPTIONS.includes(payload.currency)) {
    showAccountCreateError("请选择有效账户币种。", ["currency"]);
    return;
  }

  if (!isEditableAccountTypeForCurrency(payload.accountType, payload.currency)) {
    showAccountCreateError("请选择与币种匹配的账户类型。", ["accountType"]);
    return;
  }

  if (!Number.isFinite(payload.initialBalance)) {
    showAccountCreateError("请输入有效初始余额。", ["initialBalance"]);
    return;
  }

  if (payload.appType === "school" && !["true", "false"].includes(dom.accountCreateCompanySelect.value)) {
    showAccountCreateError("请选择公司账户标记。", ["companyAccount"]);
    return;
  }

  if (!["true", "false"].includes(dom.accountCreateActiveSelect.value)) {
    showAccountCreateError("请选择启用状态。", ["active"]);
    return;
  }

  setAccountCreateSubmitting(true);

  try {
    const result = await createAccountProfile(payload);
    closeAccountCreateDialog({ force: true });
    await refreshAfterAccountCreate(result);
    showMessage("success", "账户已新增。当前余额只在账户卡片展示，后续余额修正请使用账户调整流程。");
  } catch (error) {
    showAccountCreateError(`账户新增失败：${error.message || error}`, accountCreateFieldIdsForError(error.message || ""));
  } finally {
    setAccountCreateSubmitting(false);
  }
}

async function refreshAfterAccountCreate(result) {
  if (result?.app_type) {
    dom.appTypeSelect.value = result.app_type;
    dom.accountSelect.value = "";
  }
  await reloadAccountDataPreservingViewport();
}

function renderAccountCreateTypeOptions(currency, selectedType = "") {
  const options = editableAccountTypesForCurrency(currency);
  const nextType = options.includes(selectedType) ? selectedType : options[0];
  dom.accountCreateTypeSelect.innerHTML = options
    .map((type) => `<option value="${escapeAttribute(type)}">${escapeHtml(accountTypeLabel(type))}</option>`)
    .join("");
  dom.accountCreateTypeSelect.value = nextType || "";
}

function renderAccountCreateAppTypeOptions(selectedAppType) {
  dom.accountCreateAppTypeSelect.innerHTML = ACCOUNT_CREATABLE_APP_TYPE_OPTIONS
    .map((appType) => `<option value="${escapeAttribute(appType)}">${escapeHtml(accountAppTypeLabel(appType))}</option>`)
    .join("");
  dom.accountCreateAppTypeSelect.value = ACCOUNT_CREATABLE_APP_TYPE_OPTIONS.includes(selectedAppType)
    ? selectedAppType
    : "school";
}

function renderAccountCreateCurrencyOptions(selectedCurrency) {
  dom.accountCreateCurrencySelect.innerHTML = EDITABLE_ACCOUNT_CURRENCY_OPTIONS
    .map((currency) => `<option value="${escapeAttribute(currency)}">${escapeHtml(currency)}</option>`)
    .join("");
  dom.accountCreateCurrencySelect.value = EDITABLE_ACCOUNT_CURRENCY_OPTIONS.includes(selectedCurrency)
    ? selectedCurrency
    : "CNY";
}

function updateAccountCreateScopeControls() {
  const isFamily = dom.accountCreateAppTypeSelect.value === "family";
  dom.accountCreateCompanySelect.disabled = isFamily;
  if (isFamily) {
    dom.accountCreateCompanySelect.value = "false";
    clearAccountCreateFieldInvalid("companyAccount");
  }
}

function setAccountCreateSubmitting(isSubmitting) {
  isAccountCreateSubmitting = isSubmitting;
  dom.accountCreateSubmitButton.disabled = isSubmitting;
  dom.accountCreateCancelButton.disabled = isSubmitting;
  dom.accountCreateSubmitButton.textContent = isSubmitting ? "新增中..." : "新增";
}

function clearAccountCreateErrors() {
  dom.accountCreateError.textContent = "";
  dom.accountCreateError.classList.add("is-hidden");
  for (const fieldId of ACCOUNT_CREATE_FIELD_IDS) {
    clearAccountCreateFieldInvalid(fieldId);
  }
}

function showAccountCreateError(message, fieldIds = []) {
  dom.accountCreateError.textContent = message;
  dom.accountCreateError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setAccountCreateFieldInvalid(fieldId, true);
  }
  dom.accountCreateDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function accountCreateFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("名称")) fields.push("name");
  if (text.includes("用途")) fields.push("appType");
  if (text.includes("类型")) fields.push("accountType");
  if (text.includes("币种")) fields.push("currency");
  if (text.includes("初始余额") || text.includes("余额")) fields.push("initialBalance");
  if (text.includes("公司账户")) fields.push("companyAccount");
  if (text.includes("启用状态")) fields.push("active");
  return fields;
}

function setAccountCreateFieldInvalid(fieldId, invalid) {
  const field = dom.accountCreateDialog.querySelector(`[data-account-create-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearAccountCreateFieldInvalid(fieldId) {
  setAccountCreateFieldInvalid(fieldId, false);
}

function hideAccountCreateErrorIfClean() {
  const hasInvalidField = Boolean(dom.accountCreateDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.accountCreateError.textContent = "";
    dom.accountCreateError.classList.add("is-hidden");
  }
}

function openAccountProfileDialog(accountId) {
  const account = accounts.find((item) => item.id === accountId);
  if (!account) {
    showMessage("error", "没有找到要编辑的账户。");
    return;
  }

  editingAccount = account;
  renderAccountProfileAppTypeOptions(account.app_type);
  dom.accountProfileNameInput.value = account.name || "";
  renderAccountProfileCurrencyOptions(account.currency);
  renderAccountProfileTypeOptions(account.currency, account.account_type, account);
  dom.accountProfileCompanySelect.value = account.is_company_account ? "true" : "false";
  dom.accountProfileActiveSelect.value = account.is_active ? "true" : "false";
  dom.accountProfileNoteInput.value = account.note || "";
  updateAccountProfileScopeControls(account);
  clearAccountProfileErrors();
  setAccountProfileSubmitting(false);
  dom.accountProfileDialog.classList.remove("is-hidden");
  dom.accountProfileDialog.setAttribute("aria-hidden", "false");
  dom.accountProfileNameInput.focus();
}

function closeAccountProfileDialog({ force = false } = {}) {
  if (isAccountProfileSubmitting && !force) {
    return;
  }

  editingAccount = null;
  dom.accountProfileDialog.classList.add("is-hidden");
  dom.accountProfileDialog.setAttribute("aria-hidden", "true");
}

async function submitAccountProfile() {
  if (isAccountProfileSubmitting) {
    return;
  }

  clearAccountProfileErrors();

  if (!editingAccount) {
    showAccountProfileError("没有找到要编辑的账户。");
    return;
  }

  const payload = {
    accountId: editingAccount.id,
    appType: editingAccount.app_type || "school",
    name: dom.accountProfileNameInput.value.trim(),
    currency: dom.accountProfileCurrencySelect.value,
    accountType: dom.accountProfileTypeSelect.value,
    businessEntityId: editingAccount.app_type === "family" ? null : editingAccount.business_entity_id,
    isCompanyAccount: editingAccount.app_type === "family" ? false : dom.accountProfileCompanySelect.value === "true",
    isActive: dom.accountProfileActiveSelect.value === "true",
    note: dom.accountProfileNoteInput.value.trim(),
  };

  if (!payload.name) {
    showAccountProfileError("请输入账户名称。", ["name"]);
    return;
  }

  if (!EDITABLE_ACCOUNT_CURRENCY_OPTIONS.includes(payload.currency)) {
    showAccountProfileError("请选择有效账户币种。", ["currency"]);
    return;
  }

  if (!isAllowedAccountTypeForProfile(payload.accountType, payload.currency, editingAccount)) {
    showAccountProfileError("请选择与币种匹配的账户类型。", ["accountType"]);
    return;
  }

  if (payload.appType === "school" && !["true", "false"].includes(dom.accountProfileCompanySelect.value)) {
    showAccountProfileError("请选择公司账户标记。", ["companyAccount"]);
    return;
  }

  if (!["true", "false"].includes(dom.accountProfileActiveSelect.value)) {
    showAccountProfileError("请选择启用状态。", ["active"]);
    return;
  }

  setAccountProfileSubmitting(true);

  try {
    await updateAccountProfile(payload);
    closeAccountProfileDialog({ force: true });
    await reloadAccountDataPreservingViewport();
    showMessage("success", "账户基础信息已更新。余额修正请继续使用账户调整流程。");
  } catch (error) {
    showAccountProfileError(`账户基础信息更新失败：${error.message || error}`, accountProfileFieldIdsForError(error.message || ""));
  } finally {
    setAccountProfileSubmitting(false);
  }
}

function renderAccountProfileCurrencyOptions(selectedCurrency) {
  dom.accountProfileCurrencySelect.innerHTML = EDITABLE_ACCOUNT_CURRENCY_OPTIONS
    .map((currency) => `<option value="${escapeAttribute(currency)}">${escapeHtml(currency)}</option>`)
    .join("");
  dom.accountProfileCurrencySelect.value = EDITABLE_ACCOUNT_CURRENCY_OPTIONS.includes(selectedCurrency)
    ? selectedCurrency
    : "JPY";
}

function renderAccountProfileAppTypeOptions(selectedAppType) {
  const appType = ACCOUNT_APP_TYPE_OPTIONS.includes(selectedAppType) ? selectedAppType : "school";
  dom.accountProfileAppTypeSelect.innerHTML = ACCOUNT_APP_TYPE_OPTIONS
    .map((value) => `<option value="${escapeAttribute(value)}">${escapeHtml(accountAppTypeLabel(value))}</option>`)
    .join("");
  dom.accountProfileAppTypeSelect.value = appType;
}

function renderAccountProfileTypeOptions(currency, selectedType = "", account = null) {
  const options = editableAccountTypesForCurrency(currency);
  const shouldPreserveLegacyType = account
    && account.currency === currency
    && account.account_type === selectedType
    && !options.includes(selectedType);
  const finalOptions = shouldPreserveLegacyType ? [selectedType, ...options] : options;
  const nextType = finalOptions.includes(selectedType) ? selectedType : finalOptions[0];
  dom.accountProfileTypeSelect.innerHTML = finalOptions
    .map((type) => `<option value="${escapeAttribute(type)}">${escapeHtml(accountTypeLabel(type))}</option>`)
    .join("");
  dom.accountProfileTypeSelect.value = nextType || "";
}

function updateAccountProfileScopeControls(account) {
  const isFamily = account?.app_type === "family";
  dom.accountProfileCompanySelect.disabled = isFamily;
  if (isFamily) {
    dom.accountProfileCompanySelect.value = "false";
  }
}

function setAccountProfileSubmitting(isSubmitting) {
  isAccountProfileSubmitting = isSubmitting;
  dom.accountProfileSubmitButton.disabled = isSubmitting;
  dom.accountProfileCancelButton.disabled = isSubmitting;
  dom.accountProfileSubmitButton.textContent = isSubmitting ? "保存中..." : "保存";
}

function clearAccountProfileErrors() {
  dom.accountProfileError.textContent = "";
  dom.accountProfileError.classList.add("is-hidden");
  for (const fieldId of ACCOUNT_PROFILE_FIELD_IDS) {
    clearAccountProfileFieldInvalid(fieldId);
  }
}

function showAccountProfileError(message, fieldIds = []) {
  dom.accountProfileError.textContent = message;
  dom.accountProfileError.classList.remove("is-hidden");
  for (const fieldId of fieldIds) {
    setAccountProfileFieldInvalid(fieldId, true);
  }
  dom.accountProfileDialog.querySelector(".dialog-panel")?.scrollTo({ top: 0, behavior: "smooth" });
}

function accountProfileFieldIdsForError(message) {
  const text = safeText(message);
  const fields = [];
  if (text.includes("名称")) fields.push("name");
  if (text.includes("用途")) fields.push("appType");
  if (text.includes("类型")) fields.push("accountType");
  if (text.includes("币种")) fields.push("currency");
  if (text.includes("公司账户")) fields.push("companyAccount");
  if (text.includes("启用状态")) fields.push("active");
  return fields;
}

function setAccountProfileFieldInvalid(fieldId, invalid) {
  const field = dom.accountProfileDialog.querySelector(`[data-account-profile-field="${fieldId}"]`);
  if (field) {
    field.classList.toggle("is-invalid", invalid);
  }
}

function clearAccountProfileFieldInvalid(fieldId) {
  setAccountProfileFieldInvalid(fieldId, false);
}

function hideAccountProfileErrorIfClean() {
  const hasInvalidField = Boolean(dom.accountProfileDialog.querySelector(".field.is-invalid"));
  if (!hasInvalidField) {
    dom.accountProfileError.textContent = "";
    dom.accountProfileError.classList.add("is-hidden");
  }
}

async function reloadAccountDataPreservingViewport() {
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  await loadAccountData();
  window.scrollTo(scrollX, scrollY);
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
    const amountClass = Number(item.amount) >= 0 ? "amount-positive" : "amount-negative";
    const relatedText = [item.related_table, item.related_id].filter(Boolean).join(" / ") || "-";
    const description = item.description || item.note || "-";

    return `
      <tr>
        <td><a class="table-action-button" href="./account-transaction-detail.html?id=${encodeURIComponent(item.id)}">详情</a></td>
        <td>${escapeHtml(formatDate(item.transaction_date))}</td>
        <td>${escapeHtml(account?.name || item.account_id || "-")}</td>
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
  const defaultFromAccountId = filters?.accountId || "";

  dom.accountTransferDateInput.value = currentDate();
  dom.accountTransferAmountInput.value = "";
  dom.accountTransferReasonInput.value = "";
  dom.accountTransferNoteInput.value = "";

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

  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);

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
    showTransferError("转账账户必须属于同一内部范围。", ["fromAccount", "toAccount"]);
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

  dom.accountSelect.value = "";

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
  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);
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
  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);
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
  for (const fieldId of ["transferDate", "fromAccount", "toAccount", "amount", "reason"]) {
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
  const defaultAccountId = filters?.accountId || "";

  dom.accountAdjustmentDateInput.value = currentDate();
  dom.accountAdjustmentAmountInput.value = "";
  dom.accountAdjustmentReasonInput.value = "";
  dom.accountAdjustmentNoteInput.value = "";

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

  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);

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
    showAdjustmentError("调整账户与内部范围不一致。", ["account"]);
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
  const businessEntityId = requirePrimarySchoolBusinessEntityId(businessEntities);
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
  for (const fieldId of ["adjustmentDate", "account", "amount", "reason"]) {
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

function transactionTypeLabel(type) {
  return TRANSACTION_TYPE_LABELS[type] || safeText(type) || "-";
}

function editableAccountTypesForCurrency(currency) {
  return EDITABLE_ACCOUNT_TYPE_OPTIONS_BY_CURRENCY[currency] || [];
}

function isEditableAccountTypeForCurrency(accountType, currency) {
  return editableAccountTypesForCurrency(currency).includes(accountType);
}

function isAllowedAccountTypeForProfile(accountType, currency, account) {
  if (isEditableAccountTypeForCurrency(accountType, currency)) {
    return true;
  }

  return Boolean(
    account
      && account.currency === currency
      && account.account_type === accountType
  );
}

function accountTypeLabel(type) {
  return ACCOUNT_TYPE_LABELS[type] || safeText(type) || "-";
}

function accountAppTypeLabel(appType) {
  return ACCOUNT_APP_TYPE_LABELS[appType] || safeText(appType) || "-";
}

function isEditableAccountAppType(appType) {
  return appType === "school" || appType === "family";
}

function accountCompanyLabel(account) {
  if (account?.app_type === "family") {
    return "家庭账户";
  }

  return account?.is_company_account ? "是" : "否";
}

function displayValue(value) {
  return safeText(value) || "-";
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
