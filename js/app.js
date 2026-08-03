import { APP_VERSION } from "./config.js?v=v2.112.0-cash-retry-attempts-20260614";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initPaymentPage } from "./pages/payment-page.js?v=v10.3.38-payment-legacy-cash-cleanup";

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
