import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initPartTimeWorkPage } from "./pages/part-time-work-page.js?v=v10.3.95-db-progress";

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
