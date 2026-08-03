import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initAccountTransactionDetailPage } from "./pages/account-transaction-detail-page.js?v=v10.1.13-account-management-ui-polish";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initAccountTransactionDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#accountTransactionDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `账户流水详情页面初始化失败：${error.message || error}`;
    }
  }
});
