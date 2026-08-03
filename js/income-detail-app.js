import { APP_VERSION } from "./config.js";
import { initIncomeDetailPage } from "./pages/income-detail-page.js?v=p0f-20260803-1";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initIncomeDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#incomeDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `收入记录详情页面初始化失败：${error.message || error}`;
    }
  }
});
