import { APP_VERSION } from "./config.js";
import { initStudentPage } from "./pages/student-page.js?v=v2.98.0-master-simple-edit-open-20260612";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initStudentPage();
  } catch (error) {
    const messageArea = document.querySelector("#studentMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `学生管理页面初始化失败：${error.message || error}`;
    }
  }
});
