import { APP_VERSION } from "./config.js";
import { initWeeklyLessonDashboardPage } from "./pages/weekly-lesson-dashboard-page.js?v=v10.3.88-weekly-lesson-operations";

document.addEventListener("DOMContentLoaded", () => {
  const version = document.querySelector("#appVersion");
  if (version) version.textContent = APP_VERSION;
  initWeeklyLessonDashboardPage();
});
