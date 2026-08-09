import { APP_VERSION } from "./config.js?v=settlement-writer-p0-closure-20260809-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initSettlementDetailPage } from "./pages/settlement-detail-page.js?v=settlement-writer-p0-closure-20260809-1";

const SETTLEMENT_PAGE_VERSION = "settlement-writer-p0-closure-20260809-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = `${APP_VERSION} · ${SETTLEMENT_PAGE_VERSION}`;
  }

  console.info("[aozora-school-v2]", APP_VERSION, SETTLEMENT_PAGE_VERSION);

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
