import { hasSupabaseConfig } from "../supabase-client.js";
import { fetchWageRuleDetailPage } from "../api/wage-rule-api.js?v=phase-b4-remaining-20260807-1";
import { formatCurrency, formatDate, safeText } from "../utils/format.js";

const SETTLEMENT_TYPE_LABELS = {
  jpy_hourly: "日元时给",
  no_wage: "无工资",
};

const TEACHER_STATUS_LABELS = {
  employed: "在职",
  inactive: "停用",
  retired: "退职",
};

const STUDENT_STATUS_LABELS = {
  active: "在读",
  paused: "暂停",
  left: "已离校",
};

const dom = {};

export function initWageRuleDetailPage() {
  cacheDom();

  if (!hasSupabaseConfig()) {
    showMessage(
      "error",
      "请先在 js/config.js 填写 Supabase URL 和 anon key。当前页面不会发起数据请求。"
    );
    setContentVisible(false);
    return;
  }

  const wageRuleId = readWageRuleId();
  if (!wageRuleId) {
    showMessage("error", "缺少老师工资规则 ID，请从老师工资规则列表进入详情页。");
    setContentVisible(false);
    return;
  }

  loadWageRuleDetail(wageRuleId);
}

function cacheDom() {
  dom.messageArea = document.querySelector("#wageRuleDetailMessageArea");
  dom.loadingState = document.querySelector("#wageRuleDetailLoadingState");
  dom.content = document.querySelector("#wageRuleDetailContent");
  dom.titleText = document.querySelector("#wageRuleDetailTitleText");
  dom.basicInfo = document.querySelector("#wageRuleDetailBasicInfo");
  dom.matchInfo = document.querySelector("#wageRuleDetailMatchInfo");
  dom.rateInfo = document.querySelector("#wageRuleDetailRateInfo");
  dom.systemInfo = document.querySelector("#wageRuleDetailSystemInfo");
  dom.noteBlock = document.querySelector("#wageRuleDetailNoteBlock");
}

function readWageRuleId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || "";
}

async function loadWageRuleDetail(wageRuleId) {
  setLoading(true);
  setContentVisible(false);
  showMessage("info", "正在加载老师工资规则详情...");

  try {
    const data = await fetchWageRuleDetailPage(wageRuleId);
    renderWageRuleDetail(data);
    setContentVisible(true);
    showMessage("success", "老师工资规则详情已加载。");
  } catch (error) {
    setContentVisible(false);
    showMessage("error", `读取老师工资规则详情失败：${error.message || error}`);
  } finally {
    setLoading(false);
  }
}

function renderWageRuleDetail(data) {
  const { rule, teacher, student, subject } = data;

  dom.titleText.textContent = `${teacherName(teacher, rule.teacher_id)} / ${studentName(student, rule.student_id)} / ${subjectName(subject, rule.subject_id)}`;

  dom.basicInfo.innerHTML = renderDefinitionList([
    ["规则 ID", shortId(rule.id)],
    ["结算类型", settlementTypeLabel(rule.settlement_type)],
    ["启用状态", activeLabel(rule.is_active)],
    ["创建时间", formatDate(rule.created_at)],
    ["更新时间", formatDate(rule.updated_at)],
  ]);

  dom.matchInfo.innerHTML = renderDefinitionList([
    ["老师", teacherName(teacher, rule.teacher_id)],
    ["老师编码", displayValue(teacher?.teacher_code)],
    ["老师分类", displayValue(teacher?.department)],
    ["老师状态", teacherStatusLabel(teacher?.status)],
    ["学生", studentName(student, rule.student_id)],
    ["学生编码", displayValue(student?.student_code)],
    ["当前月学生状态", studentStatusLabel(student?.resolved_status)],
    ["科目", subjectName(subject, rule.subject_id)],
    ["科目分类", displaySubjectCategory(subject)],
  ]);

  dom.rateInfo.innerHTML = renderDefinitionList([
    ["日元时薪", formatCurrency(rule.hourly_rate_jpy, "JPY")],
    ["人民币时薪", formatCurrency(rule.hourly_rate_cny, "CNY")],
    ["汇率", displayValue(rule.exchange_rate)],
    ["交通费 JPY", formatCurrency(rule.transport_fee_jpy, "JPY")],
    ["教室费 JPY", formatCurrency(rule.classroom_fee_jpy, "JPY")],
  ]);

  dom.systemInfo.innerHTML = renderDefinitionList([
    ["teacher_id", shortId(rule.teacher_id)],
    ["student_id", shortId(rule.student_id)],
    ["subject_id", shortId(rule.subject_id)],
    ["created_at", formatDate(rule.created_at)],
    ["updated_at", formatDate(rule.updated_at)],
  ]);

  dom.noteBlock.textContent = displayValue(rule.note);
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

function teacherName(teacher, fallbackId) {
  if (!teacher) return fallbackId ? "未知" : "未设置";
  return safeText(teacher.display_name || teacher.name) || "未设置";
}

function studentName(student, fallbackId) {
  if (!student) return fallbackId ? "未知" : "未设置";
  const name = safeText(student.display_name || student.name) || "未设置";
  const code = safeText(student.student_code);
  return code ? `${name} / ${code}` : name;
}

function subjectName(subject, fallbackId) {
  if (!subject) return fallbackId ? "未知" : "未设置";
  return safeText(subject.name) || "未设置";
}

function displaySubjectCategory(subject) {
  if (!subject) return "-";
  return [subject.primary_category, subject.category]
    .map((value) => safeText(value))
    .filter(Boolean)
    .join(" / ") || "-";
}

function settlementTypeLabel(value) {
  return SETTLEMENT_TYPE_LABELS[value] || displayValue(value);
}

function teacherStatusLabel(value) {
  return TEACHER_STATUS_LABELS[value] || displayValue(value);
}

function studentStatusLabel(value) {
  return STUDENT_STATUS_LABELS[value] || displayValue(value);
}

function activeLabel(value) {
  if (value === true) return "启用";
  if (value === false) return "停用";
  return "-";
}

function shortId(value) {
  const text = safeText(value);
  return text ? text.slice(0, 8) : "-";
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
