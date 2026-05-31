import { APP_VERSION } from "./config.js";
import { initSubjectPage } from "./pages/subject-page.js";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initSubjectPage();
  } catch (error) {
    const messageArea = document.querySelector("#subjectMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `科目管理页面初始化失败：${error.message || error}`;
    }
  }
});
