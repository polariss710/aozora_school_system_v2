import { APP_VERSION } from "./config.js";
import { initReimbursementDetailPage } from "./pages/reimbursement-detail-page.js?v=v2.96.0-lesson-edit-wage-clearing-display-20260612";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initReimbursementDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#reimbursementDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `报销记录详情页面初始化失败：${error.message || error}`;
    }
  }
});
