import { APP_VERSION } from "./config.js";
import { initExpenseDetailPage } from "./pages/expense-detail-page.js?v=v2.96.0-lesson-edit-wage-clearing-display-20260612";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initExpenseDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#expenseDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `支出记录详情页面初始化失败：${error.message || error}`;
    }
  }
});
