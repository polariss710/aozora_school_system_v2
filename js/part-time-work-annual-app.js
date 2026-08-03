import { APP_VERSION } from "./config.js?v=v10.3.94-annual-version-cache";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initPartTimeWorkAnnualPage } from "./pages/part-time-work-annual-page.js?v=v10.3.94-annual-version-cache";

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
