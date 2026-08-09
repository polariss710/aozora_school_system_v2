import { APP_VERSION } from "./config.js?v=student-settlement-tokyo-month-close-20260810-3";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initSettlementPage } from "./pages/settlement-page.js?v=student-settlement-tokyo-month-close-20260810-3";

const SETTLEMENT_PAGE_VERSION = "student-settlement-tokyo-month-close-20260810-3";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  const authContext = await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = `${APP_VERSION} · ${SETTLEMENT_PAGE_VERSION}`;
  }

  console.info("[aozora-school-v2]", APP_VERSION, SETTLEMENT_PAGE_VERSION);

  try {
    initSettlementPage({ membershipRole: authContext.membership.role });
  } catch (error) {
    const messageArea = document.querySelector("#settlementMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `学生月度结算页面初始化失败：${error.message || error}`;
    }
  }
});
