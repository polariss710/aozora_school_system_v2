import { APP_VERSION } from "./config.js";
import { initExpenseDetailPage } from "./pages/expense-detail-page.js?v=v10.3.66-rejected-wage-expense-void";

document.addEventListener("DOMContentLoaded", async () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initExpenseDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#expenseDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `支出记录详情页面初始化失败：${error.message || error}`;
    }
  }
});
