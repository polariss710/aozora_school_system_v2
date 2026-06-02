import { APP_VERSION } from "./config.js";
import { initSettlementDetailPage } from "./pages/settlement-detail-page.js";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initSettlementDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#settlementDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `学生月度结算详情页面初始化失败：${error.message || error}`;
    }
  }
});
