import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initQuotePlanPage } from "./pages/quote-plan-page.js?v=v10.3.64-quote-print-total-summary";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initQuotePlanPage();
  } catch (error) {
    const messageArea = document.querySelector("#quotePlanMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `报价单生成页面初始化失败：${error.message || error}`;
    }
  }
});
