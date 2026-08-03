import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initClassroomSchedulePage } from "./pages/classroom-schedule-page.js?v=v10.3.81-office-capacity";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) versionEl.textContent = APP_VERSION;
  console.info("[aozora-school-v2]", APP_VERSION);
  try {
    initClassroomSchedulePage();
  } catch (error) {
    const area = document.querySelector("#classroomScheduleMessageArea");
    if (area) {
      area.className = "message message-error";
      area.textContent = `教室排班页面初始化失败：${error.message || error}`;
    }
  }
});
