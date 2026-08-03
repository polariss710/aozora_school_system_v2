import { APP_VERSION } from "./config.js?v=p0f-20260803-1";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initSettlementDetailPage } from "./pages/settlement-detail-page.js?v=p0f-20260803-1";

const SETTLEMENT_PAGE_VERSION = "p0f-20260803-1";

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
