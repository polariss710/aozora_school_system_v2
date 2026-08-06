import { APP_VERSION } from "./config.js?v=phase-b4-finance-20260807-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initSettlementPage } from "./pages/settlement-page.js?v=phase-b4-finance-20260807-1";

const SETTLEMENT_PAGE_VERSION = "settlement-trusted-tool-20260803-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
