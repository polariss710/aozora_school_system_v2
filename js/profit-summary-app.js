import { APP_VERSION } from "./config.js";
import { initProfitSummaryPage } from "./pages/profit-summary-page.js?v=v2.35.0-profit-summary-readonly-full-autopilot-trial-20260607";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initProfitSummaryPage();
  } catch (error) {
    const messageArea = document.querySelector("#profitSummaryMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `利润分析页面初始化失败：${error.message || error}`;
    }
  }
});
