import { APP_VERSION } from "./config.js";
import { initLessonPage } from "./pages/lesson-page.js?v=v10.3.73-single-business-entity";

document.addEventListener("DOMContentLoaded", () => {
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
