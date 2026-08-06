import { APP_VERSION } from "./config.js?v=be-ui-20260806-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initTuitionReceiptPage } from "./pages/tuition-receipt-page.js?v=v10.3.65-income-receipt-source";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initTuitionReceiptPage();
  } catch (error) {
    const messageArea = document.querySelector("#tuitionReceiptMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `領収書生成页面初始化失败：${error.message || error}`;
    }
  }
});
