import { APP_VERSION } from "./config.js";
import { initLessonDetailPage } from "./pages/lesson-detail-page.js?v=r2-f-f2-b-year-month-closure";

document.addEventListener("DOMContentLoaded", () => {
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
