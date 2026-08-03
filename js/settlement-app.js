import { APP_VERSION } from "./config.js?v=settlement-error-i18n-20260803-1";
import { initSettlementPage } from "./pages/settlement-page.js?v=settlement-error-i18n-20260803-1";

const SETTLEMENT_PAGE_VERSION = "settlement-error-i18n-20260803-1";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = `${APP_VERSION} · ${SETTLEMENT_PAGE_VERSION}`;
  }

  console.info("[aozora-school-v2]", APP_VERSION, SETTLEMENT_PAGE_VERSION);

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
