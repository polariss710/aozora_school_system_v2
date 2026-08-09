import { APP_VERSION } from "./config.js?v=p1-b1b-payment-rpc-v2-20260809-1";
import { requireGlobalSession } from "./auth-guard.js?v=be-ui-20260806-1";
import { initPaymentPage } from "./pages/payment-page.js?v=p1-b1b-payment-rpc-v2-20260809-1";

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
