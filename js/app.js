import { APP_VERSION } from "./config.js?v=v2.111.0-supabase-auth-client-init-20260614";
import { initPaymentPage } from "./pages/payment-page.js?v=v2.111.0-supabase-auth-client-init-20260614";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);
  initPaymentPage();
});
