import { APP_VERSION } from "./config.js?v=v10-5-65-20260913-1";
import { requireGlobalSession } from "./auth-guard.js?v=v10-5-65-20260913-1";
import { initPaymentPage } from "./pages/payment-page.js?v=v10-5-65-20260913-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  initPaymentPage();
});
