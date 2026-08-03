import { APP_VERSION } from "./config.js";
import { initAccountPage } from "./pages/account-page.js?v=v10.3.73-single-business-entity";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initAccountPage();
  } catch (error) {
    const messageArea = document.querySelector("#accountMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `账户管理页面初始化失败：${error.message || error}`;
    }
  }
});
