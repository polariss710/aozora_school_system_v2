const LOGO_SRC = "./assets/logo3.png";

const dom = {};

export function initTuitionReceiptPage() {
  cacheDom();
  setDefaultValues();
  bindEvents();
  renderReceipt();
}

function cacheDom() {
  dom.form = document.querySelector("#tuitionReceiptForm");
  dom.messageArea = document.querySelector("#tuitionReceiptMessageArea");
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
  dom.resetButton = document.querySelector("#resetTuitionReceiptButton");
}

function setDefaultValues() {
  const today = getTodayDateValue();
  dom.issueDateInput.value = today;
  dom.receiptNumberInput.value = buildReceiptNumber(today);
  dom.itemInput.value = buildDefaultItem(today);
  dom.paymentMethodInput.value = "銀行振込";
  dom.issuerNameInput.value = dom.issuerNameInput.value || "青空進学塾";
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => {
    event.preventDefault();
    renderReceipt({ showSuccess: true });
  });

  dom.form?.addEventListener("input", () => renderReceipt());
  dom.form?.addEventListener("change", (event) => {
    if (event.target === dom.issueDateInput && !dom.receiptNumberInput.value.trim()) {
      dom.receiptNumberInput.value = buildReceiptNumber(dom.issueDateInput.value);
    }
    renderReceipt();
  });

  dom.printButton?.addEventListener("click", () => {
    if (!validateReceipt()) {
      return;
    }
    hideMessage();
    window.print();
  });

  dom.resetButton?.addEventListener("click", () => {
    clearInputs();
    setDefaultValues();
    renderReceipt({ message: "已恢复默认領収書模板。" });
  });
}

function clearInputs() {
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
    if (input) input.value = "";
  });
}

function renderReceipt(options = {}) {
  const data = readReceiptData();
  dom.preview.innerHTML = buildReceiptHtml(data);

  if (options.showSuccess) {
    if (validateReceipt()) {
      showMessage("success", "領収書预览已更新。");
    }
    return;
  }

  if (options.message) {
    showMessage("success", options.message);
  }
}

function readReceiptData() {
  const amount = parseExplicitJpyAmount(dom.amountInput.value);
  return {
    studentName: dom.studentNameInput.value.trim(),
    amount,
    itemName: dom.itemInput.value.trim(),
    issueDate: dom.issueDateInput.value,
    receiptNumber: dom.receiptNumberInput.value.trim(),
    paymentMethod: dom.paymentMethodInput.value.trim(),
    issuerName: dom.issuerNameInput.value.trim() || "青空進学塾",
    issuerInfo: dom.issuerInfoInput.value.trim(),
    note: dom.noteInput.value.trim(),
  };
}

function buildReceiptHtml(data) {
  const amountText = data.amount === null ? "¥ -" : formatJpy(data.amount);
  const studentText = data.studentName || "学生名未入力";
  const itemText = data.itemName || "授業料として";
  const issueDateText = formatJapaneseDate(data.issueDate);
  const receiptNumberText = data.receiptNumber || "-";
  const paymentMethodText = data.paymentMethod || "-";
  const issuerInfoHtml = data.issuerInfo
    ? `<p>${escapeHtml(data.issuerInfo)}</p>`
    : `<p class="tuition-receipt-muted">発行者情報未入力</p>`;
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
          <p class="tuition-receipt-student">${escapeHtml(studentText)} 様</p>
          <p>下記の通り領収いたしました。</p>
          <div class="tuition-receipt-amount-box">
            <span>領収金額</span>
            <strong>${escapeHtml(amountText)}</strong>
          </div>
          <p class="tuition-receipt-tax-note">上記金額は手動入力値です。</p>
        </div>

        <div class="tuition-receipt-issuer">
          <dl>
            <div>
              <dt>発行日</dt>
              <dd>${escapeHtml(issueDateText)}</dd>
            </div>
            <div>
              <dt>領収書番号</dt>
              <dd>${escapeHtml(receiptNumberText)}</dd>
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
            <td>${escapeHtml(itemText)}</td>
            <td>${escapeHtml(amountText)}</td>
            <td>${escapeHtml(paymentMethodText)}</td>
            <td>${data.note ? escapeHtml(data.note) : "-"}</td>
          </tr>
        </tbody>
      </table>

      <section class="tuition-receipt-summary">
        <div>
          <span>但し書き</span>
          <strong>${escapeHtml(itemText)}</strong>
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
  const data = readReceiptData();
  if (!data.studentName) {
    showMessage("warning", "请输入学生名称 / 宛名。");
    dom.studentNameInput.focus();
    return false;
  }
  if (data.amount === null) {
    showMessage("warning", "请输入有效的 JPY 金额。");
    dom.amountInput.focus();
    return false;
  }
  if (!data.itemName) {
    showMessage("warning", "请输入项目 / 但し書き。");
    dom.itemInput.focus();
    return false;
  }
  return true;
}

function parseExplicitJpyAmount(value) {
  const normalized = String(value || "").trim();
  if (!normalized) return null;
  const amount = Number(normalized);
  if (!Number.isFinite(amount) || amount < 0) return null;
  return Math.round(amount);
}

function formatJpy(amount) {
  return `¥ ${amount.toLocaleString("ja-JP")}`;
}

function buildDefaultItem(dateValue) {
  const date = parseDateValue(dateValue);
  if (!date) return "授業料として";
  return `${date.getFullYear()}年${String(date.getMonth() + 1).padStart(2, "0")}月分 授業料として`;
}

function buildReceiptNumber(dateValue) {
  const compactDate = String(dateValue || getTodayDateValue()).replace(/-/g, "");
  const now = new Date();
  const time = [now.getHours(), now.getMinutes(), now.getSeconds()]
    .map((part) => String(part).padStart(2, "0"))
    .join("");
  return `R-${compactDate}-${time}`;
}

function formatJapaneseDate(dateValue) {
  const date = parseDateValue(dateValue);
  if (!date) return "-";
  const weekdays = ["日", "月", "火", "水", "木", "金", "土"];
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 (${weekdays[date.getDay()]})`;
}

function parseDateValue(dateValue) {
  if (!dateValue) return null;
  const [year, month, day] = dateValue.split("-").map((part) => Number(part));
  if (!year || !month || !day) return null;
  return new Date(year, month - 1, day);
}

function getTodayDateValue() {
  const today = new Date();
  const year = today.getFullYear();
  const month = String(today.getMonth() + 1).padStart(2, "0");
  const day = String(today.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
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
    .replace(/'/g, "&#39;");
}
