import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchTuitionReceiptSource } from "../api/tuition-receipt-api.js";
import { formatCurrency, safeText } from "../utils/format.js";

const LOGO_SRC = "./assets/logo3.png";

const dom = {};
let receiptData = null;

export function initTuitionReceiptPage() {
  cacheDom();
  bindEvents();

  const incomeRecordId = readIncomeRecordId();
  if (!incomeRecordId) {
    blockReceiptPage("请从已 Cash 确认的学费收入记录进入領収書生成页面。");
    return;
  }

  if (!hasSupabaseConfig()) {
    blockReceiptPage("请先配置 Supabase。当前页面无法读取收入记录。");
    return;
  }

  loadReceiptSource(incomeRecordId);
}

function cacheDom() {
  dom.form = document.querySelector("#tuitionReceiptForm");
  dom.messageArea = document.querySelector("#tuitionReceiptMessageArea");
  dom.editorPanel = document.querySelector("#tuitionReceiptEditorPanel");
  dom.previewPanel = document.querySelector("#tuitionReceiptPreviewPanel");
  dom.studentNameInput = document.querySelector("#receiptStudentName");
  dom.amountInput = document.querySelector("#receiptAmountJpy");
  dom.itemInput = document.querySelector("#receiptItemName");
  dom.issueDateInput = document.querySelector("#receiptIssueDate");
  dom.receiptNumberInput = document.querySelector("#receiptNumber");
  dom.paymentMethodInput = document.querySelector("#receiptPaymentMethod");
  dom.issuerNameInput = document.querySelector("#receiptIssuerName");
  dom.issuerInfoInput = document.querySelector("#receiptIssuerInfo");
  dom.noteInput = document.querySelector("#receiptNote");
  dom.preview = document.querySelector("#tuitionReceiptPreview");
  dom.printButton = document.querySelector("#printTuitionReceiptButton");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => {
    event.preventDefault();
    renderReceipt({ showSuccess: true });
  });

  dom.printButton?.addEventListener("click", () => {
    if (!validateReceipt()) {
      return;
    }
    hideMessage();
    window.print();
  });
}

async function loadReceiptSource(incomeRecordId) {
  showMessage("info", "正在读取已 Cash 确认的学费收入记录...");
  setReceiptControlsDisabled(true);

  try {
    const source = await fetchTuitionReceiptSource(incomeRecordId);
    receiptData = buildReceiptDataFromSource(source);
    populateReceiptFields(receiptData);
    renderReceipt();
    showMessage("success", "已从 Cash 确认收入记录生成領収書预览。");
  } catch (error) {
    receiptData = null;
    blockReceiptPage(`无法生成領収書：${error.message || error}`);
  } finally {
    setReceiptControlsDisabled(false);
  }
}

function buildReceiptDataFromSource(source) {
  const { income, student, cashIncomeLinkageEvent: event } = source;

  if (!income || income.app_type !== "school") {
    throw new Error("收入记录不存在或不属于 School 业务。");
  }
  if (income.income_category !== "tuition" && income.source_type !== "student_tuition_bill") {
    throw new Error("只有学费收入可以生成学费領収書。");
  }
  if (income.status !== "received") {
    throw new Error("只有已收款收入可以生成領収書。");
  }
  if (income.cancelled_at || income.reversed_at) {
    throw new Error("已作废或已撤销收入不能生成領収書。");
  }
  if (!income.student_id || !student) {
    throw new Error("收入记录缺少学生信息，不能生成学费領収書。");
  }
  if (!event || event.sync_status !== "synced") {
    throw new Error("只有已通过 Cash 确认并同步的收入记录可以生成領収書。");
  }
  if (event.payment_amount === null || event.payment_amount === undefined || !event.payment_currency) {
    throw new Error("Cash 确认记录缺少实际到账金额或币种。");
  }

  const receiptDate = dateOnly(income.income_date) || dateOnly(event.synced_at) || getTodayDateValue();
  const amount = Number(event.payment_amount);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error("Cash 确认金额无效。");
  }

  return {
    incomeRecordId: income.id,
    studentName: safeText(student.display_name || student.name),
    amount,
    currency: event.payment_currency,
    itemName: buildItemName(income),
    issueDate: receiptDate,
    receiptNumber: buildReceiptNumber(receiptDate, income.id),
    paymentMethod: buildPaymentMethod(event),
    issuerName: "青空進学塾",
    issuerInfo: "",
    note: buildReceiptNote(income),
  };
}

function populateReceiptFields(data) {
  dom.studentNameInput.value = data.studentName;
  dom.amountInput.value = formatReceiptAmount(data.amount, data.currency);
  dom.itemInput.value = data.itemName;
  dom.issueDateInput.value = data.issueDate;
  dom.receiptNumberInput.value = data.receiptNumber;
  dom.paymentMethodInput.value = data.paymentMethod;
  dom.issuerNameInput.value = data.issuerName;
  dom.issuerInfoInput.value = data.issuerInfo;
  dom.noteInput.value = data.note;

  [
    dom.studentNameInput,
    dom.amountInput,
    dom.itemInput,
    dom.issueDateInput,
    dom.receiptNumberInput,
    dom.paymentMethodInput,
    dom.issuerNameInput,
    dom.issuerInfoInput,
    dom.noteInput,
  ].forEach((input) => {
    if (input) input.readOnly = true;
  });
}

function renderReceipt(options = {}) {
  if (!receiptData) {
    dom.preview.innerHTML = "";
    return;
  }

  dom.preview.innerHTML = buildReceiptHtml(receiptData);

  if (options.showSuccess) {
    showMessage("success", "領収書预览已根据收入记录刷新。");
  }
}

function buildReceiptHtml(data) {
  const amountText = formatReceiptAmount(data.amount, data.currency);
  const issueDateText = formatJapaneseDate(data.issueDate);
  const issuerInfoHtml = data.issuerInfo
    ? `<p>${escapeHtml(data.issuerInfo)}</p>`
    : `<p class="tuition-receipt-muted">Cash 確認済み収入記録に基づき発行</p>`;
  const noteHtml = data.note
    ? `<div class="tuition-receipt-note">${escapeHtml(data.note).replace(/\n/g, "<br>")}</div>`
    : "";

  return `
    <article class="tuition-receipt-document" aria-label="学费領収書">
      <header class="tuition-receipt-document-header">
        <h2>領収書</h2>
        <img src="${LOGO_SRC}" alt="青空進学塾">
      </header>

      <section class="tuition-receipt-top">
        <div class="tuition-receipt-recipient">
          <p class="tuition-receipt-student">${escapeHtml(data.studentName)} 様</p>
          <p>下記の通り領収いたしました。</p>
          <div class="tuition-receipt-amount-box">
            <span>領収金額</span>
            <strong>${escapeHtml(amountText)}</strong>
          </div>
          <p class="tuition-receipt-tax-note">上記金額は Cash 確認済みの収入記録に基づきます。</p>
        </div>

        <div class="tuition-receipt-issuer">
          <dl>
            <div>
              <dt>発行日</dt>
              <dd>${escapeHtml(issueDateText)}</dd>
            </div>
            <div>
              <dt>領収書番号</dt>
              <dd>${escapeHtml(data.receiptNumber)}</dd>
            </div>
          </dl>
          <h3>${escapeHtml(data.issuerName)}</h3>
          ${issuerInfoHtml}
        </div>
      </section>

      <table class="tuition-receipt-detail-table">
        <thead>
          <tr>
            <th>項目</th>
            <th>金額</th>
            <th>支払方法</th>
            <th>備考</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>${escapeHtml(data.itemName)}</td>
            <td>${escapeHtml(amountText)}</td>
            <td>${escapeHtml(data.paymentMethod)}</td>
            <td>${data.note ? escapeHtml(data.note) : "-"}</td>
          </tr>
        </tbody>
      </table>

      <section class="tuition-receipt-summary">
        <div>
          <span>但し書き</span>
          <strong>${escapeHtml(data.itemName)}</strong>
        </div>
        <div>
          <span>合計金額</span>
          <strong>${escapeHtml(amountText)}</strong>
        </div>
      </section>

      <footer class="tuition-receipt-footer">
        <p>上記正に領収いたしました。</p>
        ${noteHtml}
      </footer>
    </article>
  `;
}

function validateReceipt() {
  if (!receiptData) {
    showMessage("warning", "没有可打印的領収書。请从已 Cash 确认的学费收入记录进入。");
    return false;
  }
  return true;
}

function blockReceiptPage(message) {
  showMessage("warning", message);
  dom.editorPanel?.classList.add("is-hidden");
  dom.previewPanel?.classList.add("is-hidden");
}

function setReceiptControlsDisabled(disabled) {
  if (dom.printButton) {
    dom.printButton.disabled = disabled || !receiptData;
  }
}

function readIncomeRecordId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("income_record_id") || params.get("id") || "";
}

function buildItemName(income) {
  const snapshot = income.source_snapshot && typeof income.source_snapshot === "object"
    ? income.source_snapshot
    : {};
  const month = safeText(snapshot.billing_month || income.settlement_month || income.year_month);
  const monthMatch = month.match(/^(\d{4})-(\d{2})/);
  const monthLabel = monthMatch
    ? `${monthMatch[1]}年${monthMatch[2]}月分`
    : "";
  return `${monthLabel ? `${monthLabel} ` : ""}授業料として`;
}

function buildPaymentMethod(event) {
  const accountName = safeText(event.cash_account_name_snapshot);
  return accountName ? `${accountName} / Cash確認` : "Cash確認";
}

function buildReceiptNote(income) {
  const sourceLabel = safeText(income.source_label || income.description);
  return sourceLabel ? sourceLabel : `收入记录 ${shortId(income.id)}`;
}

function formatReceiptAmount(amount, currency) {
  return formatCurrency(amount, currency);
}

function buildReceiptNumber(dateValue, incomeRecordId) {
  const compactDate = String(dateValue || getTodayDateValue()).replace(/-/g, "");
  return `R-${compactDate}-${shortId(incomeRecordId)}`;
}

function formatJapaneseDate(dateValue) {
  const date = parseDateValue(dateValue);
  if (!date) return "-";
  const weekdays = ["日", "月", "火", "水", "木", "金", "土"];
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 (${weekdays[date.getDay()]})`;
}

function dateOnly(value) {
  const text = safeText(value);
  return /^\d{4}-\d{2}-\d{2}/.test(text) ? text.slice(0, 10) : "";
}

function getTodayDateValue() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

function parseDateValue(dateValue) {
  if (!dateValue) return null;
  const [year, month, day] = dateValue.split("-").map((part) => Number(part));
  if (!year || !month || !day) return null;
  return new Date(year, month - 1, day);
}

function shortId(value) {
  return value ? String(value).slice(0, 8) : "-";
}

function showMessage(type, text) {
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = text;
}

function hideMessage() {
  dom.messageArea.className = "message is-hidden";
  dom.messageArea.textContent = "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
