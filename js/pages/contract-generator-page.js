const PAYMENT_METHODS = {
  monthly: {
    label: "按月支付",
    text: "一か月単位で先払い、つまり毎月の月末までに、翌月の費用を払うこと。",
  },
  bimonthly: {
    label: "每2个月支付",
    text: "二か月単位で先払い、つまり支払対象期間の前月末までに、翌二か月分の費用を払うこと。",
  },
  half: {
    label: "半额支付",
    text: "契約開始時に契約期間総額の半額を支払い、残額は両者合意の期限までに支払うこと。",
  },
  full: {
    label: "全额支付",
    text: "契約開始時に契約期間総額を一括で支払うこと。",
  },
};

const CIRCLED_NUMBERS = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"];

const COURSE_TRACK_SUBJECTS = {
  science: ["日語", "数学", "物理", "化学"],
  humanities: ["日語", "数学", "文综"],
};

const dom = {};
const state = {
  startRows: [],
};

export function initContractGeneratorPage() {
  cacheDom();
  bindEvents();
  resetDraft({ silent: true });
}

function cacheDom() {
  dom.form = document.querySelector("#contractGeneratorForm");
  dom.messageArea = document.querySelector("#contractGeneratorMessageArea");
  dom.studentNameInput = document.querySelector("#contractStudentName");
  dom.periodStartInput = document.querySelector("#contractPeriodStart");
  dom.periodEndInput = document.querySelector("#contractPeriodEnd");
  dom.tuitionInput = document.querySelector("#contractTuition");
  dom.classroomFeeModeSelect = document.querySelector("#contractClassroomFeeMode");
  dom.classroomFeeInput = document.querySelector("#contractClassroomFee");
  dom.paymentMethodSelect = document.querySelector("#contractPaymentMethod");
  dom.courseTrackSelect = document.querySelector("#contractCourseTrack");
  dom.startRows = document.querySelector("#contractStartRows");
  dom.addStartRowButton = document.querySelector("#addContractStartRowButton");
  dom.resetButton = document.querySelector("#resetContractGeneratorButton");
  dom.printButton = document.querySelector("#printContractButton");
  dom.preview = document.querySelector("#contractPreview");
}

function bindEvents() {
  dom.form?.addEventListener("submit", (event) => {
    event.preventDefault();
    renderContract({ showSuccess: true });
  });

  dom.form?.addEventListener("input", () => renderContract());
  dom.form?.addEventListener("change", (event) => {
    if (event.target === dom.courseTrackSelect) {
      applyCourseTrackPreset();
    }
    syncClassroomFeeInput();
    renderContract();
  });
  dom.startRows?.addEventListener("input", handleStartRowInput);
  dom.startRows?.addEventListener("click", handleStartRowClick);

  dom.addStartRowButton?.addEventListener("click", () => {
    state.startRows.push(createBlankStartRow());
    renderStartRows();
    renderContract();
  });

  dom.resetButton?.addEventListener("click", () => resetDraft());
  dom.printButton?.addEventListener("click", printContract);
}

function resetDraft(options = {}) {
  const draft = createDefaultDraft();
  dom.studentNameInput.value = draft.studentName;
  dom.periodStartInput.value = draft.periodStart;
  dom.periodEndInput.value = draft.periodEnd;
  dom.tuitionInput.value = draft.tuition;
  dom.classroomFeeModeSelect.value = draft.classroomFeeMode;
  dom.classroomFeeInput.value = draft.classroomFee;
  dom.paymentMethodSelect.value = draft.paymentMethod;
  dom.courseTrackSelect.value = draft.courseTrack;
  state.startRows = draft.startRows.map(normalizeStartRow);
  renderStartRows();
  syncClassroomFeeInput();
  renderContract(options.silent ? {} : { message: "已恢复默认合同模板。" });
}

function createDefaultDraft() {
  const today = getTodayDateValue();
  return {
    studentName: "",
    periodStart: today,
    periodEnd: getDefaultEndDateValue(),
    tuition: "一万円/時間（￥10000/H）",
    classroomFeeMode: "none",
    classroomFee: "二千円/時間（￥2000/H）",
    paymentMethod: "monthly",
    courseTrack: "science",
    startRows: createStartRowsForTrack("science", today),
  };
}

function createBlankStartRow() {
  return {
    subject: "",
    startDate: dom.periodStartInput?.value || getTodayDateValue(),
  };
}

function normalizeStartRow(row) {
  return {
    subject: String(row?.subject || ""),
    startDate: String(row?.startDate || ""),
  };
}

function renderStartRows() {
  if (!dom.startRows) return;

  dom.startRows.innerHTML = state.startRows.map((row, index) => `
    <div class="contract-start-row" data-contract-start-index="${index}">
      <label class="field">
        <span>科目 / 课程</span>
        <input type="text" value="${escapeHtml(row.subject)}" data-contract-start-field="subject" placeholder="例：文科数学、英語">
      </label>
      <label class="field">
        <span>开始日</span>
        <input type="date" value="${escapeHtml(row.startDate)}" data-contract-start-field="startDate">
      </label>
      <button class="button contract-start-remove-button" type="button" data-contract-start-action="remove" ${state.startRows.length <= 1 ? "disabled" : ""}>删除</button>
    </div>
  `).join("");
}

function handleStartRowInput(event) {
  const input = event.target.closest("[data-contract-start-field]");
  if (!input) return;

  const row = input.closest("[data-contract-start-index]");
  const index = Number(row?.dataset.contractStartIndex);
  const field = input.dataset.contractStartField;
  if (!Number.isInteger(index) || !state.startRows[index]) return;

  state.startRows[index][field] = input.value;
  renderContract();
}

function handleStartRowClick(event) {
  const button = event.target.closest("[data-contract-start-action='remove']");
  if (!button) return;

  const row = button.closest("[data-contract-start-index]");
  const index = Number(row?.dataset.contractStartIndex);
  if (!Number.isInteger(index) || state.startRows.length <= 1) return;

  state.startRows.splice(index, 1);
  renderStartRows();
  renderContract();
}

function getDraftFromForm() {
  return {
    studentName: dom.studentNameInput?.value.trim() || "",
    periodStart: dom.periodStartInput?.value || "",
    periodEnd: dom.periodEndInput?.value || "",
    tuition: dom.tuitionInput?.value.trim() || "",
    classroomFeeMode: dom.classroomFeeModeSelect?.value || "none",
    classroomFee: dom.classroomFeeInput?.value.trim() || "",
    paymentMethod: dom.paymentMethodSelect?.value || "monthly",
    courseTrack: dom.courseTrackSelect?.value || "science",
    startRows: state.startRows.map(normalizeStartRow),
  };
}

function renderContract(options = {}) {
  const draft = getDraftFromForm();
  renderPreview(draft);

  if (options.message) {
    showMessage(options.message, "success");
  } else if (options.showSuccess) {
    showMessage("合同预览已更新。", "success");
  } else {
    hideMessage();
  }
}

function renderPreview(draft) {
  if (!dom.preview) return;

  const contractee = draft.studentName || "　　　　　　　　　";
  const period = `${formatJapaneseDate(draft.periodStart)}～${formatJapaneseDate(draft.periodEnd)}`;
  const tuition = draft.tuition || "　　　　　　　　　　　　　　";
  const classroomFeeLine = buildClassroomFeeLine(draft);
  const payment = PAYMENT_METHODS[draft.paymentMethod] || PAYMENT_METHODS.monthly;

  dom.preview.innerHTML = `
    <article class="contract-document">
      <header class="contract-document-header">
        <p>青空進学塾</p>
        <h2>学習指導契約書</h2>
      </header>

      <section class="contract-clause">
        <h3>契約約款</h3>
        <p>（契約の成立）</p>
        <p>第１条　契約者　<span class="contract-fill">${escapeHtml(contractee)}</span>　(以下甲という）は、契約書の内容及び以下の条項を承諾のうえ､本日､<span class="contract-underline">青空進学塾</span>　（以下乙という）に対して入塾及び契約の申込を行い、乙がこれを承諾した場合において、特定商取引に関する法律（以下「法」と記す。）に基づく契約が成立します。</p>
      </section>

      <section class="contract-clause">
        <p>（役務の提供及び対価の支払）</p>
        <p>第２条　乙は、甲に対し、乙の定める学習指導カリキュラムの中から甲が選択した左記契約書記載の内容の役務を提供します。</p>
        <p>２　甲は、授業料、その他左記契約書に記載された金額、方法により納入期限までに支払うこととします。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導の形態）</p>
        <p>第３条　契約書記載の指導形態については、以下の通りとします。</p>
        <p>　・個人指導とは、一人の講師が一人の生徒に対し、所定の指導時間を通して、マンツ－マンで指導を行うものとします。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導の開始日）</p>
        <p>第４条　本契約において、学習指導の開始日とは、以下の通りとします。</p>
        <div class="contract-dynamic-lines">
          ${renderStartDateLines(draft.startRows)}
        </div>
        <p>所定の教室において学習指導がなされている限り、現実の受講の有無を問わないものとします。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導の実施場所）</p>
        <p>第５条　乙は、左記契約書記載の場所において学習指導を行います。</p>
        <p>但し、やむをえない事情がある場合には、両者合意の上、他の場所に移動することがあります。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導期間と契約期間）</p>
        <p>第６条　学習指導の期間は、以下の通りとします。</p>
        <p class="contract-fill-line">${escapeHtml(period)}</p>
        <p>なお、更新時には、更新料等は請求しないものとします。</p>
        <p>また、契約内容・期間に変更が生じた場合には、両者合意の確認のため、新たな契約書を作成し、本契約はその時点で、破棄されるものとします。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導の費用と払い方）</p>
        <p>第７条　学習指導の費用は、以下の通りとします。</p>
        <p class="contract-fill-line">・授業料：日本円　${escapeHtml(tuition)}</p>
        ${classroomFeeLine}
        <p class="contract-fill-line">・払い方：${escapeHtml(payment.text)}</p>
        <p>　※日本円、中国元のどちらの払うこと。</p>
        <p>・費用の計算：すべてのコース終了後は、総授業時間数に応じて料金を返金または補填することになる。</p>
      </section>

      <section class="contract-clause">
        <p>（学習指導のスケジュール）</p>
        <p>第8条　学習指導のスケジュールは別紙_スケジュールを参照する。</p>
      </section>

      <section class="contract-clause">
        <p>（関連商品）</p>
        <p>第9条　学習指導に付随して必要となる関連商品（教材等書籍、カセット・テープ・ＣＤ等、ファクシミリ機器、テレビ電話）の販売を行う場合は、その関連商品ごとの価格・数量を明らかにするものとします。教室の料金も発生する可能性がある。</p>
      </section>

      <section class="contract-clause">
        <p>（中途解約）</p>
        <p>第10条  乙は、契約に定める期間以内、お客さん側の事情による中途解約の場合支払ったお金は一切返金しません。</p>
      </section>

      <section class="contract-clause">
        <p>（個人情報保護）</p>
        <p>第11条　本契約に際し乙が収集した個人情報に関しては、原則として以下の目的のみに利用します。</p>
        <p>甲に対するサービスの案内、情報提供を行うため</p>
        <p>甲より照会を受けた内容に回答するため</p>
        <p>･････････</p>
        <p>･････････</p>
        <p>２　本契約に際し乙が収集した個人情報に関しては、第三者への提供は行いません。</p>
      </section>

      <section class="contract-clause">
        <p>（紛争の解決）</p>
        <p>第12条　本約款に定める事項及び契約内容について疑義が生じた場合、その他本約款に関して争いが生じた場合は、両者協議の上、解決するものとします。</p>
        <p>２　本契約及び約款に定めのない事項については、民法及び特定商取引に関する法律その他の関連諸法によるものとします。</p>
      </section>

      <section class="contract-signature">
        <p>以上合意を証するため本契約書を2通作成し、甲乙の量当事者記名（又は署名）捺印の上、各自1つを保有する。</p>
        <p class="contract-date-line">契約日　　　　　　　　　　　　　　　　　　　　　年　　　月　　　日</p>
        <div class="contract-party-grid">
          <div>
            <p>甲</p>
            <p>名称：<span></span></p>
            <p>住所：<span></span></p>
          </div>
          <div>
            <p>乙</p>
            <p>名称：<span></span></p>
            <p>住所：<span></span></p>
          </div>
        </div>
      </section>
    </article>
  `;
}

function syncClassroomFeeInput() {
  if (!dom.classroomFeeInput || !dom.classroomFeeModeSelect) return;
  const isEnabled = dom.classroomFeeModeSelect.value === "enabled";
  dom.classroomFeeInput.disabled = !isEnabled;
  dom.classroomFeeInput.placeholder = isEnabled ? "例：二千円/時間（￥2000/H）" : "教室料なし";
}

function buildClassroomFeeLine(draft) {
  if (draft.classroomFeeMode !== "enabled") {
    return "";
  }

  const classroomFee = draft.classroomFee || "　　　　　　　　　　　　　　";
  return `<p class="contract-fill-line">・教室料：日本円　${escapeHtml(classroomFee)}</p>`;
}

function applyCourseTrackPreset() {
  const track = dom.courseTrackSelect?.value || "science";
  const startDate = dom.periodStartInput?.value || getTodayDateValue();
  state.startRows = createStartRowsForTrack(track, startDate);
  renderStartRows();
}

function createStartRowsForTrack(track, startDate) {
  const subjects = COURSE_TRACK_SUBJECTS[track] || COURSE_TRACK_SUBJECTS.science;
  return subjects.map((subject) => ({ subject, startDate }));
}

function renderStartDateLines(rows) {
  const normalizedRows = rows.length ? rows : [createBlankStartRow()];
  return normalizedRows.map((row, index) => {
    const marker = CIRCLED_NUMBERS[index] || `${index + 1}.`;
    const subject = row.subject.trim() || "　　　　　　　　　";
    return `<p class="contract-fill-line">・${marker}${escapeHtml(subject)}は${escapeHtml(formatJapaneseDate(row.startDate))}から</p>`;
  }).join("");
}

function printContract() {
  const draft = getDraftFromForm();
  renderContract();

  const previousTitle = document.title;
  const printTitle = buildContractDocumentTitle(draft);
  let restored = false;

  const restoreTitle = () => {
    if (restored) return;
    restored = true;
    document.title = previousTitle;
  };

  document.title = printTitle;
  window.addEventListener("afterprint", restoreTitle, { once: true });
  window.setTimeout(restoreTitle, 30000);
  window.print();
}

function buildContractDocumentTitle(draft) {
  const studentName = normalizePdfTitlePart(draft.studentName);
  return `${studentName || "未填写契约者"}学習指導契約書`;
}

function normalizePdfTitlePart(value) {
  return String(value || "")
    .trim()
    .replace(/[\\/:*?"<>|]/g, "")
    .replace(/\s+/g, "");
}

function getTodayDateValue() {
  return toDateInputValue(new Date());
}

function getDefaultEndDateValue() {
  const date = new Date();
  date.setMonth(date.getMonth() + 4);
  return toDateInputValue(date);
}

function toDateInputValue(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatJapaneseDate(value) {
  if (!value) return "　　　　年　　月　　日";
  const [year, month, day] = value.split("-").map(Number);
  if (!year || !month || !day) return value;
  return `${year}年${month}月${day}日`;
}

function showMessage(message, type = "info") {
  if (!dom.messageArea) return;
  dom.messageArea.className = `message message-${type}`;
  dom.messageArea.textContent = message;
}

function hideMessage() {
  if (!dom.messageArea) return;
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
