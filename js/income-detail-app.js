import { APP_VERSION } from "./config.js?v=p1-b2b-auth-storage-20260810-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-role-access-20260903-1";
import { initIncomeDetailPage } from "./pages/income-detail-page.js?v=phase-b4-finance-20260807-2";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
