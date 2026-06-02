import { APP_VERSION } from "./config.js";
import { initPaymentPage } from "./pages/payment-page.js?v=v2.18.0-income-detail-readonly-20260603";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  initPaymentPage();
});
