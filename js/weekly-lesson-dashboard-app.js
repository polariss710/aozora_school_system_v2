import { APP_VERSION } from "./config.js?v=v10-5-65-20260913-1";
import { requireGlobalSession } from "./auth-guard.js?v=v10-5-65-20260913-1";
import { initWeeklyLessonDashboardPage } from "./pages/weekly-lesson-dashboard-page.js?v=v10-5-65-20260913-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const version = document.querySelector("#appVersion");
  if (version) version.textContent = APP_VERSION;
  initWeeklyLessonDashboardPage();
});
