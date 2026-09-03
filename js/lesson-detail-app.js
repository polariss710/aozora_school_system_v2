import { APP_VERSION } from "./config.js?v=makeup-date-hint-removal-20260816-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-role-access-20260903-1";
import { initLessonDetailPage } from "./pages/lesson-detail-page.js?v=lesson-time-hint-removal-20260812-1";

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
