import { APP_VERSION } from "./config.js";
import { initTeacherPage } from "./pages/teacher-page.js";

document.addEventListener("DOMContentLoaded", () => {
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
