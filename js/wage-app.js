import { APP_VERSION } from "./config.js?v=filter-contract-b1-20260822-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-role-access-20260903-1";
import { initWagePage } from "./pages/wage-page.js?v=filter-contract-b1-20260822-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initWagePage();
  } catch (error) {
    const messageArea = document.querySelector("#wageMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资结算页面初始化失败：${error.message || error}`;
    }
  }
});
