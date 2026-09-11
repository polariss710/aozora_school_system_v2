import { APP_VERSION } from "./config.js?v=filter-contract-b5-20260822-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-settlement-draft-20260911-3";
import { initWeeklyLessonDashboardPage } from "./pages/weekly-lesson-dashboard-page.js?v=operator-settlement-draft-20260911-3";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const version = document.querySelector("#appVersion");
  if (version) version.textContent = APP_VERSION;
  initWeeklyLessonDashboardPage();
});
