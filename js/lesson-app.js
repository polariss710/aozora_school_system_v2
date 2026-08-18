import { APP_VERSION } from "./config.js?v=phase2c-d2a1-business-note-snapshot-20260818-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initLessonPage } from "./pages/lesson-page.js?v=phase2c-d2a1-business-note-snapshot-20260818-1";

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
