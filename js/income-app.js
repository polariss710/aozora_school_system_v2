import { APP_VERSION } from "./config.js?v=p0f-20260803-1";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initIncomePage } from "./pages/income-page.js?v=p0f-20260803-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
