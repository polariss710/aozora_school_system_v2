import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initWeeklyScheduleImagePage } from "./pages/weekly-schedule-image-page.js?v=v10.3.89-schedule-edit-labels";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initWeeklyScheduleImagePage();
  } catch (error) {
    const messageArea = document.querySelector("#weeklyScheduleMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `周课表图片页面初始化失败：${error.message || error}`;
    }
  }
});
