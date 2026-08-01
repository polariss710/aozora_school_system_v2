import { APP_VERSION } from "./config.js";
import { initIncomePage } from "./pages/income-page.js?v=v2.115.1-tuition-preview-compact";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initIncomePage();
  } catch (error) {
    const messageArea = document.querySelector("#incomeMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `收入记录页面初始化失败：${error.message || error}`;
    }
  }
});
