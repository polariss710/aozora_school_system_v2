import { APP_VERSION } from "./config.js";
import { initPaymentPage } from "./pages/payment-page.js?v=v2.110.0-personal-cash-payment-outbox-20260613";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  initPaymentPage();
});
