import { APP_VERSION } from "./config.js";
import { initExpensePage } from "./pages/expense-page.js";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initExpensePage();
  } catch (error) {
    const messageArea = document.querySelector("#expenseMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `支出记录页面初始化失败：${error.message || error}`;
    }
  }
});
