import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initWeeklyLessonDashboardPage } from "./pages/weekly-lesson-dashboard-page.js?v=v10.3.88-weekly-lesson-operations";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const version = document.querySelector("#appVersion");
  if (version) version.textContent = APP_VERSION;
  initWeeklyLessonDashboardPage();
});
