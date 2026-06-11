import { APP_VERSION } from "./config.js";
import { initSettlementPage } from "./pages/settlement-page.js?v=v2.96.0-lesson-edit-wage-clearing-display-20260612";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initSettlementPage();
  } catch (error) {
    const messageArea = document.querySelector("#settlementMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `学生月度结算页面初始化失败：${error.message || error}`;
    }
  }
});
