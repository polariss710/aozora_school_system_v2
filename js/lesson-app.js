import { APP_VERSION } from "./config.js?v=phase-b4-lesson-candidates-20260806";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initLessonPage } from "./pages/lesson-page.js?v=phase-b4-lesson-candidates-20260806";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initLessonPage();
  } catch (error) {
    const messageArea = document.querySelector("#lessonMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `课时管理页面初始化失败：${error.message || error}`;
    }
  }
});
