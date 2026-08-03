import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initStudentPage } from "./pages/student-page.js?v=v10.3.73-single-business-entity";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
