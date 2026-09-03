import { APP_VERSION } from "./config.js?v=phase-d-lock-authoritative-source-20260826-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-role-access-20260903-1";
import { initPartTimeWorkAnnualPage } from "./pages/part-time-work-annual-page.js?v=phase-d-lock-authoritative-source-20260826-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  await initPartTimeWorkAnnualPage();
});
