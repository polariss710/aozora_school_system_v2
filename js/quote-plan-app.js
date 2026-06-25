import { APP_VERSION } from "./config.js";
import { initQuotePlanPage } from "./pages/quote-plan-page.js?v=v10.3.23-quote-plan-generator";

document.addEventListener("DOMContentLoaded", () => {
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
