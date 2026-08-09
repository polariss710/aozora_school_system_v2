import { APP_VERSION } from "./config.js?v=p1-b1c-r-20260810-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initExpenseDetailPage } from "./pages/expense-detail-page.js?v=p1-b1c-r-20260810-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initExpenseDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#expenseDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `支出记录详情页面初始化失败：${error.message || error}`;
    }
  }
});
