import { APP_VERSION } from "./config.js?v=p1-b2b-auth-storage-20260810-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initPartTimeWorkPage } from "./pages/part-time-work-page.js?v=be-ui-20260806-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initPartTimeWorkPage();
  } catch (error) {
    const messageArea = document.querySelector("#partTimeWorkMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `私塾打工页面初始化失败：${error.message || error}`;
    }
  }
});
