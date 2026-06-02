import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchIncomeDetailPage } from "../api/income-detail-api.js";
import { formatCurrency, formatDate, formatMonth, safeText } from "../utils/format.js";

const INCOME_STATUS_LABELS = {
  received: "已收款",
};

const INCOME_CATEGORY_LABELS = {
  tuition: "学费",
};

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
};

const dom = {};
let detailData = null;

export function initIncomeDetailPage() {
  cacheDom();

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
  dom.loadingState = document.querySelector("#incomeDetailLoadingState");
  dom.content = document.querySelector("#incomeDetailContent");
  dom.titleText = document.querySelector("#incomeDetailTitleText");
  dom.basicInfo = document.querySelector("#incomeDetailBasicInfo");
  dom.amountInfo = document.querySelector("#incomeDetailAmountInfo");
  dom.relatedInfo = document.querySelector("#incomeDetailRelatedInfo");
  dom.systemInfo = document.querySelector("#incomeDetailSystemInfo");
  dom.noteBlock = document.querySelector("#incomeDetailNoteBlock");
  dom.settlements = document.querySelector("#incomeDetailSettlements");
  dom.transactionCount = document.querySelector("#incomeDetailTransactionCount");
  dom.transactionEmpty = document.querySelector("#incomeDetailTransactionEmpty");
  dom.transactionRows = document.querySelector("#incomeDetailTransactionRows");
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

  dom.noteBlock.textContent = displayValue(income.note);
  renderSettlements(data.settlements);
  renderTransactions(data.transactions);
}

function renderSettlements(settlements) {
  if (!settlements.length) {
    dom.settlements.innerHTML = '<div class="state-text">无关联学生月度结算快照。</div>';
    return;
  }

  dom.settlements.innerHTML = settlements.map((settlement) => `
    <article class="detail-list-card">
      <div class="detail-list-card-header">
        <strong>${escapeHtml(shortId(settlement.id))}</strong>
        <span class="status-badge ${escapeAttribute(statusClass(settlement.settlement_status))}">${escapeHtml(settlementStatusLabel(settlement.settlement_status))}</span>
      </div>
      <p><a class="table-action-button" href="./settlement-detail.html?id=${encodeURIComponent(settlement.id)}">查看学生月度结算详情</a></p>
      ${renderDefinitionList([
        ["结算月份", formatMonth(settlement.year_month)],
        ["预设汇率", displayValue(settlement.preset_exchange_rate)],
        ["计划课时费 JPY", formatCurrency(settlement.planned_lesson_fee_jpy, "JPY")],
        ["计划课时费 CNY", formatCurrency(settlement.planned_lesson_fee_cny, "CNY")],
        ["实际课时费 JPY", formatCurrency(settlement.actual_lesson_fee_jpy, "JPY")],
        ["实际课时费 CNY", formatCurrency(settlement.actual_lesson_fee_cny, "CNY")],
        ["已收 JPY", formatCurrency(settlement.received_jpy, "JPY")],
        ["已收 CNY", formatCurrency(settlement.received_cny, "CNY")],
        ["已收折算 CNY", formatCurrency(settlement.received_equivalent_cny, "CNY")],
        ["结转 CNY", formatCurrency(settlement.carryover_amount_cny, "CNY")],
        ["锁定时间", formatDate(settlement.locked_at)],
        ["创建时间", formatDate(settlement.created_at)],
      ])}
    </article>
  `).join("");
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
