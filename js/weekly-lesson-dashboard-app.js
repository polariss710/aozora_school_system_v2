import { APP_VERSION } from "./config.js?v=p1-b2b-auth-storage-20260810-1";
import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";
import { initWeeklyLessonDashboardPage } from "./pages/weekly-lesson-dashboard-page.js?v=phase-b4-remaining-20260807-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const version = document.querySelector("#appVersion");
  if (version) version.textContent = APP_VERSION;
  initWeeklyLessonDashboardPage();
});
