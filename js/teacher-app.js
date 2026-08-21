import { APP_VERSION } from "./config.js?v=filter-contract-b2-20260822-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initTeacherPage } from "./pages/teacher-page.js?v=filter-contract-b2-20260822-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initTeacherPage();
  } catch (error) {
    const messageArea = document.querySelector("#teacherMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师管理页面初始化失败：${error.message || error}`;
    }
  }
});
