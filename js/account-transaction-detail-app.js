import { APP_VERSION } from "./config.js";
import { initAccountTransactionDetailPage } from "./pages/account-transaction-detail-page.js";

document.addEventListener("DOMContentLoaded", () => {
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
