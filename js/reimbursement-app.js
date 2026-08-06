import { APP_VERSION } from "./config.js?v=be-ui-20260806-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initReimbursementPage } from "./pages/reimbursement-page.js?v=be-ui-20260806-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
