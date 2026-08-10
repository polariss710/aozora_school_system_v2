import { APP_VERSION } from "./config.js?v=lesson-time-grid-frontend-20260810-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initLessonDetailPage } from "./pages/lesson-detail-page.js?v=lesson-time-grid-frontend-20260810-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initLessonDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#lessonDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `课时详情页面初始化失败：${error.message || error}`;
    }
  }
});
