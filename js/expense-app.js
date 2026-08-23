import { APP_VERSION } from "./config.js?v=lesson-week-close-20260823-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initExpensePage } from "./pages/expense-page.js?v=lesson-week-close-20260823-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initExpensePage();
  } catch (error) {
    const messageArea = document.querySelector("#expenseMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `支出记录页面初始化失败：${error.message || error}`;
    }
  }
});
