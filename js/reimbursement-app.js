import { APP_VERSION } from "./config.js";
import { initReimbursementPage } from "./pages/reimbursement-page.js";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initReimbursementPage();
  } catch (error) {
    const messageArea = document.querySelector("#reimbursementMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `报销管理页面初始化失败：${error.message || error}`;
    }
  }
});
