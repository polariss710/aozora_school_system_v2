import { APP_VERSION } from "./config.js";
import { initPartTimeWorkAnnualPage } from "./pages/part-time-work-annual-page.js?v=v10.3.69-part-time-annual-page";

document.addEventListener("DOMContentLoaded", async () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  await initPartTimeWorkAnnualPage();
});
